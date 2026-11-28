extends Node
## Explicit development-only binding. No live Gemini, no production manager wiring.
signal view_changed(snapshot: Dictionary)
signal semantic_requested(stage: String, packet: Dictionary)
signal semantic_cancelled(identity: Dictionary)
static var bindings: Dictionary={}
const REG=preload("res://gameplay/tool_registry.gd")
const JOURNAL=preload("res://gameplay/work_journal.gd")
const BASE=preload("res://campaigns/campaign_store.gd")
const MIGRATE=preload("res://persistence/gameplay_migration.gd")
const UI=preload("res://gameplay/ui_intents.gd")
const DTO=preload("res://world/world_dto.gd")
const PACK=preload("res://turns/agent_packets.gd")
const WORLD=preload("res://world/world_store.gd")
const RECON=preload("res://world/geography_reconciler.gd")
const SQL=preload("res://systems/sqlite.gd")
const RAW=preload("res://turns/raw_mechanics.gd")
const DIRECT=["equip","swap","unequip","attune","unattune","item_use","item_drop","spell_cast"]
const CHOICES=["rest","resource_use","spell_prepare","spell_unprepare","travel","loot_pickup","loot_take_all","reconcile_legacy_slots"]
const SEMANTIC=["chat","skill_check","ability_check","saving_throw","quest_interact","party_add"]
var registry=REG.new()
var journal=JOURNAL.new()
var campaign_id=""
var actor_id=""
var local_review: Callable
var critical_review: Callable
var data: Dictionary={}
var view: Dictionary={}
var status=""
var running=false
var closed=false
var inflight: Dictionary={}
var notifying=false

func failure(message: String) -> Dictionary:
	return {"ok":false,"error":message}

func bind_campaign(id: String, reviewer: Callable, prose_reviewer: Callable) -> Dictionary:
	if not is_inside_tree() or not campaign_id.is_empty() or not DTO.id_valid(id) or not reviewer.is_valid() or not prose_reviewer.is_valid():
		return failure("Explicit local development binding and reviewers required.")
	var existing=bindings.get(id)
	if existing is WeakRef and is_instance_valid(existing.get_ref()):
		return failure("Campaign already bound to another local controller.")
	var migrated=MIGRATE.new().ensure(id)
	if not migrated.get("ok",false):
		return migrated
	var found=journal.read(id)
	if not found.get("ok",false):
		return found
	campaign_id=id
	actor_id=found["state"]["actor_id"]
	local_review=reviewer
	critical_review=prose_reviewer
	data=found
	bindings[id]=weakref(self)
	# An old adopted turn without a C4 journal needs explicit recovery rather
	# than a new action. Never silently adopt another controller's work.
	var pending=registry.session.read(found["state"],[SQL.stmt("SELECT request_id FROM gameplay_requests WHERE status='accepted_pending'")])
	if not pending.get("ok",false):
		close_session()
		return failure("Pending request lookup failed.")
	if data["work"]["active"].is_empty() and (found["state"]["pending_turn_id"]!=null or not pending["sets"][0].is_empty()):
		status="Existing pending turn requires original controller recovery."
	else:
		status="Development controller ready."
	refresh()
	if not data["work"]["active"].is_empty() or not data["work"]["queued"].is_empty():
		advance.call_deferred()
	return {"ok":true}

func reload() -> bool:
	var latest=journal.read(campaign_id)
	if not latest.get("ok",false):
		status="Campaign work readback unavailable. Retry recovery."
		return false
	data=latest
	return true

func persist(work: Dictionary) -> bool:
	var saved=journal.write(campaign_id,data,work)
	if not saved.get("ok",false):
		status="Work not confirmed. Recover before retrying."
		return false
	data=saved
	return true

func active() -> Dictionary:
	return data.get("work",{}).get("active",{})

func update_active(job: Dictionary) -> bool:
	var work=data["work"].duplicate(true)
	work["active"]=job.duplicate(true)
	return persist(work)

func enquiry(kind: String,args: Dictionary,limit: int=64) -> Dictionary:
	var state=registry.session.token(campaign_id)
	if not state.get("ok",false):
		return state
	return registry.enquire(campaign_id,{"schema_version":"2","campaign_id":campaign_id,"expected_revision":state["revision"],"query_id":registry.session.make_id(),"kind":kind,"args":args,"limit":limit})

# Only the committed read model is passed to the workspace. Pending preview is
# a separate presentation field, never inserted into canonical event history.
func refresh() -> void:
	if closed:
		return
	if not reload():
		block_view("Campaign work readback unavailable.")
		return
	var fresh=BASE.new().gameplay_view(campaign_id)
	var ext=fresh.get("interaction_extension",{})
	if ext.get("revision")!=data["state"]["revision"] or ext.get("actor_id")!=actor_id:
		block_view("Committed view unavailable; actions disabled.")
		return
	var job=active()
	var work=data["work"]
	var busy=not job.is_empty()
	var queue_wait=not busy and not work["queued"].is_empty()
	var phase="idle" if not busy and ext.get("phase")=="idle" else "busy"
	if busy and job.get("stage") in ["retry","clarification","critical_blocked"]:
		phase="retryable" if job["stage"]=="retry" else "awaiting_decision"
	elif not busy and (ext.get("phase")!="idle" or queue_wait):
		phase="blocked"
	var caps: Array=[]
	if phase=="idle":
		caps=["chat","skill_check","ability_check","saving_throw"]
		if fresh.get("interaction") is Dictionary:
			caps+=DIRECT+["rest","resource_use","spell_prepare","spell_unprepare","travel","quest_interact"]
	# One durable queued chat, not a rebase of an old mechanical selection.
	if busy and work["queued"].is_empty():
		caps.append("chat")
	var last=work["last"]
	var settled_id=last.get("request_id",ext.get("settled_request_id"))
	var settled_status=last.get("status",ext.get("settled_status"))
	if busy:
		settled_id=job["intent"]["request_id"]
		settled_status="accepted_pending"
	if not work["queued"].is_empty():
		settled_id=work["queued"]["intent"]["request_id"]
		settled_status="accepted_pending"
	for key in ["phase","supported_intents","settled_request_id","settled_status","status_text"]:
		var values={"phase":phase,"supported_intents":caps,"settled_request_id":settled_id,"settled_status":settled_status,"status_text":status}
		ext[key]=values[key]
	ext["active_turn_id"]=job.get("turn_id",job.get("intent",{}).get("request_id",ext.get("active_turn_id")))
	ext["queued_text"]=work["queued"].get("intent",{}).get("args",{}).get("text","")
	ext["can_queue"]=busy and work["queued"].is_empty()
	ext["processing"]=busy
	ext["reviewed_preview"]=preview_text(job,data["state"])
	ext["work_stage"]=job.get("stage","")
	ext["last_terminal"]=last
	ext["accepted_request_ids"]=[job.get("intent",{}).get("request_id"),work["queued"].get("intent",{}).get("request_id")]
	ext["request_history"]=work["history"]
	ext["queue_wait"]=queue_wait
	ext["draft"]=work["draft"]
	ext["local_binding"]=true
	ext["choice_tools"]=(DIRECT+CHOICES if fresh.get("interaction") is Dictionary else ["reconcile_legacy_slots"]) if phase=="idle" else []
	var packet=fresh.get("interaction")
	if packet is Dictionary:
		for key in ["phase","supported_intents","settled_request_id","settled_status","status_text","active_turn_id"]:
			packet[key]=ext[key]
		packet["can_queue"]=ext["can_queue"]
		# Physical options are offers for local review, not legal effects.
		for item in packet["inventory_instances"]:
			for opt in item["equip_options"]:
				opt["available"]=true
				opt["warning"]="Requires contextual and mechanical validation."
		for opt in packet["spell_options"]:
			var slot=fresh["actor"].get("spellcasting",{}).get("slots",{}).get(str(opt["slot_level"]),{})
			opt["available"]=opt["spell_id"] in ["cure-wounds","healing-word"] and opt["slot_level"]==1 and DTO.whole(slot.get("maximum"),1) and DTO.whole(slot.get("spent")) and slot["spent"]<slot["maximum"]
			opt["warning"]="Self healing only; components and eligibility checked by engine."
		for opt in packet["preparation_options"]:
			opt["available"]=true
			opt["warning"]="Verified rest and complete prepared list required."
	fresh["interaction_extension"]=ext
	view=fresh
	notifying=true
	view_changed.emit(fresh.duplicate(true))
	notifying=false

func acknowledge(intent: Dictionary,ok: bool,message: String) -> Dictionary:
	return {"ok":ok,"request_id":intent.get("request_id",""),"message":message}

func submit(intent: Dictionary) -> Dictionary:
	if closed or running or notifying or not reload():
		return acknowledge(intent,false,"Controller busy or unavailable.")
	var state=data["state"]
	if not (registry.session.request_valid(intent,"1") or registry.session.request_valid(intent,"2")) or intent["campaign_id"]!=campaign_id or intent["actor_id"]!=actor_id or intent["expected_revision"]!=state["revision"]:
		return acknowledge(intent,false,"Stale or invalid intention.")
	var kind=intent["kind"]
	if intent["schema_version"]=="1":
		if kind=="chat":
			if not DTO.exact_keys(intent["args"],["text"]) or not DTO.bounded_text(intent["args"]["text"],2000):
				return acknowledge(intent,false,"Invalid player text.")
		else:
			var guard=UI.new()
			guard.configure(view)
			if not kind in DIRECT+SEMANTIC+CHOICES or not guard.validate_args(kind,intent["args"]):
				return acknowledge(intent,false,"Selection is not offered.")
	elif not kind in view.get("interaction_extension",{}).get("choice_tools",[]) or not REG.TOOLS.has(kind) or not registry.arguments_valid(intent["args"],REG.TOOLS[kind][0]):
		return acknowledge(intent,false,"Explicit registered choice required.")
	var work=data["work"].duplicate(true)
	if intent["request_id"] in [work["active"].get("intent",{}).get("request_id"),work["queued"].get("intent",{}).get("request_id"),work["last"].get("request_id")] or work["history"].any(func(row): return row.get("request_id")==intent["request_id"]):
		return acknowledge(intent,false,"Request already recorded; recover original request.")
	var prior=registry.session.settlement(campaign_id,intent["request_id"])
	if not prior.get("ok",false) or prior.get("found",false):
		return acknowledge(intent,false,"Request identity unavailable or already settled.")
	var job={"intent":intent.duplicate(true),"stage":"new","tool":{},"attempt":{}}
	if not work["active"].is_empty():
		if kind!="chat" or intent["schema_version"]!="1" or not work["queued"].is_empty():
			return acknowledge(intent,false,"Only one next natural-language action may be queued.")
		work["queued"]=job
	else:
		if state["pending_turn_id"]!=null or not idle_database() or not work["queued"].is_empty() or view.get("interaction_extension",{}).get("phase")!="idle" or view.get("interaction_extension",{}).get("revision")!=state["revision"]:
			return acknowledge(intent,false,"Previous turn must be recovered.")
		work["active"]=job
	if kind=="chat":
		work["draft"]=""
	if not persist(work):
		# Unknown acknowledgement deliberately does not match C1 success/reject shape.
		return {}
	status="Input saved; processing."
	refresh.call_deferred()
	advance.call_deferred()
	return acknowledge(intent,true,"Saved for processing, not yet resolved.")

func finish(status_code: String,message: String) -> void:
	retire_attempt()
	var work=data["work"].duplicate(true)
	var job=work["active"]
	work["last"]={"request_id":job["intent"]["request_id"],"status":status_code,"text":job["intent"]["args"].get("text",""),"message":message}
	work["history"].append(work["last"].duplicate(true))
	work["history"]=work["history"].slice(maxi(0,work["history"].size()-64))
	work["active"]={}
	inflight={}
	if persist(work):
		status=message
	refresh()
	advance.call_deferred()

func stop(stage: String,message: String) -> void:
	var job=active().duplicate(true)
	job["stage"]=stage
	job["message"]=message
	inflight={}
	if update_active(job):
		status=message
	refresh()

func tool_for(intent: Dictionary,state: Dictionary,kind: String,args: Dictionary) -> Dictionary:
	return {"schema_version":"2","campaign_id":campaign_id,"actor_id":actor_id,"expected_revision":state["revision"],"request_id":intent["request_id"],"kind":kind,"args":args.duplicate(true)}

# Deferred semantic adapter requests. Exact request/attempt/revision IDs are
# persisted first. A new attempt invalidates every earlier reply.
func ask(stage: String,job: Dictionary,payload: Dictionary) -> void:
	if JSON.stringify(payload).length()>120000:
		stop("retry","Semantic context exceeds the bounded packet budget.")
		return
	var state=data["state"]
	var identity={"campaign_id":campaign_id,"actor_id":actor_id,"request_id":job["intent"]["request_id"],"attempt_id":registry.session.make_id(),"revision":state["revision"],"stage":stage}
	job["stage"]=stage
	job["attempt"]=identity
	if not update_active(job):
		return
	inflight=identity.duplicate(true)
	status="Processing "+stage.replace("_"," ")+"…"
	refresh()
	semantic_requested.emit(stage,{"identity":identity.duplicate(true),"data":payload.duplicate(true)})

# Read-only context may reuse the currently emitted committed projection
# when identity, revision and campaign metadata all match a fresh token.
func context_view(state: Dictionary) -> Dictionary:
	if view.get("campaign",{})==state["campaign"] and view.get("interaction_extension",{}).get("revision")==state["revision"] and view.get("interaction_extension",{}).get("actor_id")==state["actor_id"]:
		return view
	return BASE.new().gameplay_view(state["campaign_id"])

func command_catalogue() -> Dictionary:
	return registry.catalogue()

func scene_context(state: Dictionary) -> Dictionary:
	var world=WORLD.new()
	var dm=world.scene_seed(state)
	if not dm.get("ok",false):
		return dm
	var ids: Array=[]
	for place in dm["locations"]:
		ids.append(place["id"])
	return PACK.public_world(state,dm,world.public_context_from_token(state,ids))

func advance() -> void:
	if closed or running or notifying or not reload():
		return
	if not inflight.is_empty() and registry.session.typed_equal(inflight,active().get("attempt")):
		return
	var work=data["work"]
	if work["active"].is_empty():
		if work["queued"].is_empty() or data["state"]["pending_turn_id"]!=null or not work["last"].get("status") in ["committed","rejected"] or not idle_database():
			return
		var next=work.duplicate(true)
		next["active"]=next["queued"]
		next["queued"]={}
		# Natural text is interpreted afresh only after settlement. Original
		# submission revision is retained for provenance, not used as tool revision.
		if not persist(next):
			return
	var job=active().duplicate(true)
	var state=data["state"]
	if job.is_empty():
		return
	match job["stage"]:
		"new","interpret":
			if job["intent"]["schema_version"]=="2" or job["intent"]["kind"] in DIRECT:
				if job["intent"]["expected_revision"]!=state["revision"]:
					stop("clarification","Selection changed; cancel and choose again.")
					return
				job["tool"]=tool_for(job["intent"],state,job["intent"]["kind"],job["intent"]["args"])
				job["stage"]="execute"
				if update_active(job):
					execute_active()
			else:
				var context=scene_context(state)
				if not context.get("ok",false):
					stop("retry","Relevant context unavailable.")
					return
				var public_view=context_view(state).get("interaction_extension",{})
				if public_view.get("revision")!=state["revision"]:
					stop("retry","Public action context changed.")
					return
				ask("interpret",job,{"intent":job["intent"],"catalogue":command_catalogue(),"scene":context["scene"],"actor":PACK.actor_projection(state),"public_actors":public_view.get("public_actors",[]),"public_quests":public_view.get("public_quests",[]),"story":public_view.get("story_records",[]),"inventory":public_view.get("inventory_instances",[]),"loot":public_view.get("loot_containers",[])})
		"execute":
			execute_active()
		"narrate","critical","background","reconcile":
			recover_active()
		"post_story":
			process_story()
		"retry","clarification","critical_blocked":
			status=str(job.get("message","Awaiting recovery or clarification."))
			refresh()

# Only retire a rejected root action when no durable or in-memory outcome
# can still require recovery. Never cancel a prepared or adopted transaction.
func reject_local(req: Dictionary,message: String) -> void:
	if not reload():
		return
	var job=active()
	if job.is_empty() or not registry.session.same_request(job.get("tool"),req):
		stop("retry","Local rejection identity changed; recover original request.")
		return
	var prior=registry.session.settlement(campaign_id,req["request_id"])
	if not prior.get("ok",false) or prior.get("found",false) or registry.noncombat.prepared.has(campaign_id) or registry.resolver.unresolved.has(campaign_id) or data["state"]["pending_turn_id"]!=null or data["state"]["revision"]!=req["expected_revision"] or not idle_database():
		stop("retry",message+" Recovery required before new input.")
		return
	finish("rejected",message)

func execute_active() -> void:
	if running or not reload():
		return
	var job=active()
	var req=job.get("tool",{})
	if req.is_empty():
		stop("retry","No validated tool request.")
		return
	var prior=registry.session.settlement(campaign_id,req["request_id"])
	if not prior.get("ok",false):
		stop("retry","Settlement lookup unavailable.")
		return
	if prior.get("found",false):
		if not registry.session.same_request(prior["request"],req):
			stop("retry","Stored request differs; local review required.")
			return
		if prior["status"]=="committed":
			if prior.get("logical_turn_id")!=null:
				after_narration(job,prior)
			else:
				finish("committed",tool_message(req,prior,"Committed tool result restored."))
			return
		if prior["status"]=="accepted_pending":
			var recovered=registry.recover(campaign_id,req["request_id"])
			if recovered.get("status")=="pending_narration" or recovered.get("status")=="committed":
				recover_active()
				return
			if not recovered.get("ok",false):
				stop("retry","Adopted request recovery unavailable.")
				return
		elif prior["status"] in ["cancelled","rejected"]:
			finish(prior["status"],"Request already settled.")
			return
	if data["state"]["revision"]!=req["expected_revision"]:
		stop("retry","Tool request is stale; no automatic rebase.")
		return
	if not prepare_review(req,"execute"):
		return
	running=true
	var result=registry.execute(campaign_id,req,review_tool)
	running=false
	if not reload():
		return
	if result.get("status")=="pending_narration":
		recover_active()
	elif result.get("ok",false):
		var confirmed=registry.session.settlement(campaign_id,req["request_id"])
		if confirmed.get("found",false) and confirmed["status"]=="committed":
			finish("committed",tool_message(req,confirmed,"Tool committed. Campaign refreshed."))
		else:
			stop("retry","Tool acknowledgement needs recovery.")
	else:
		var message=str(result.get("error","Tool not resolved."))
		var code = result.get("code")
		if code==REG.MISSING_CUSTOM_ATTRIBUTES:
			if registry.missing_custom_attributes_valid(result,req):
				missing_attributes(req,result)
			else:
				stop("retry","Missing item attribute result could not be verified.")
		elif code in ["invalid","unsupported","decision_required","review_required"]+REG.ITEM_REJECTIONS and not result.get("adopted_pending",false):
			reject_local(req,message)
		else:
			stop("retry",message)

func tool_message(req: Dictionary,settled: Dictionary,fallback: String) -> String:
	if req["kind"]=="inspect_inscription" and DTO.bounded_text(settled.get("result",{}).get("inscription"),160):
		return "Inscription: "+settled["result"]["inscription"]
	return fallback

func missing_attributes(req: Dictionary,result: Dictionary) -> void:
	reject_local(req,"Required custom item attributes are missing. "+result["error"])

func legacy_review_stages() -> bool:
	return true

func recover_active() -> void:
	if not reload():
		return
	var job=active().duplicate(true)
	var req=job.get("tool",{})
	if req.is_empty():
		stop("retry","Missing durable tool identity.")
		return
	var result=registry.recover(campaign_id,req["request_id"])
	if result.get("status")=="committed":
		after_narration(job,result)
		return
	if not result.get("ok",false) or result.get("status")!="pending_narration":
		stop("retry","Receipt recovery required.")
		return
	var state=data["state"]
	var receipt=result["receipt"]
	if state["pending_turn_id"]!=receipt["turn_id"] or not PACK.committed_receipt_usable(receipt):
		stop("retry","Committed receipt identity invalid.")
		return
	job["turn_id"]=receipt["turn_id"]
	var context=scene_context(state)
	if not context.get("ok",false):
		stop("retry","Narration context unavailable.")
		return
	var public_view=context_view(state).get("interaction_extension",{})
	if public_view.get("revision")!=state["revision"]:
		stop("retry","Committed narration context changed.")
		return
	var payload={"receipt":PACK.public_receipt(receipt),"player_text":result.get("player_text",""),"scene":context["scene"],"maturity_id":state["campaign"].get("maturity_id","standard"),"turn_id":job["turn_id"],"public_actors":public_view.get("public_actors",[]),"public_quests":public_view.get("public_quests",[]),"story":public_view.get("story_records",[])}
	if job.get("stage")=="reconcile":
		reconcile(job,receipt,context["ids"])
	elif legacy_review_stages() and job.get("stage") in ["critical","background"]:
		payload["candidate"]=job.get("candidate",{}).duplicate(true)
		ask(job["stage"],job,payload)
	else:
		# The durable receipt remains authoritative; regenerate narration only.
		ask("narrate",job,payload)

# Provider/mock replies are data only. The trusted review callback, not an
# AI boolean, authorizes critical prose. All claims requiring new mechanics
# are deferred; C2 busy guard remains intact.
func receive(identity: Dictionary,result: Dictionary) -> Dictionary:
	if closed or running or notifying or not reload():
		return failure("Controller unavailable.")
	var job=active().duplicate(true)
	if job.is_empty() or identity!=inflight or not registry.session.typed_equal(identity,job.get("attempt")) or identity.get("revision")!=data["state"]["revision"] or identity.get("stage")!=job["stage"] or JSON.stringify(result).length()>65536:
		return failure("Stale or invalid semantic reply.")
	var stage=job["stage"]
	inflight={}
	match stage:
		"interpret":
			if DTO.exact_keys(result,["status","message"]) and result["status"] in ["clarification","unsupported"] and DTO.bounded_text(result["message"],1000):
				stop("clarification",result["message"])
				return {"ok":true}
			if not DTO.exact_keys(result,["kind","args"]) or not REG.TOOLS.has(result["kind"]) or not registry.arguments_valid(result["args"],REG.TOOLS[result["kind"]][0]):
				stop("retry","Interpretation did not identify a supported typed action.")
				return failure(status)
			var args=result["args"].duplicate(true)
			if args.has("text") and job["intent"]["kind"]=="chat":
				args["text"]=job["intent"]["args"]["text"]
			job["tool"]=tool_for(job["intent"],data["state"],result["kind"],args)
			job["stage"]="execute"
		"narrate":
			if not DTO.exact_keys(result,["text"]) or not DTO.bounded_text(result["text"],12000):
				stop("retry","Invalid narration candidate.")
				return failure(status)
			job["candidate"]=PACK.identity(data["state"],job["turn_id"],identity["attempt_id"])
			job["candidate"]["text"]=result["text"]
			job["stage"]="critical"
		"critical":
			if not DTO.exact_keys(result,["claims"]) or not valid_claims(result["claims"],job["candidate"]["text"]):
				stop("critical_blocked","Invalid output interpretation.")
				return failure(status)
			var prior=registry.recover(campaign_id,job["tool"]["request_id"])
			if prior.get("status")!="pending_narration":
				stop("retry","Receipt unavailable for output review.")
				return failure(status)
			# Independent trusted code reviews exact candidate AND interpreted
			# claims against receipt/canon; never use provider approval flags.
			var context=scene_context(data["state"])
			if not context.get("ok",false):
				stop("retry","Critical review context unavailable.")
				return failure(status)
			var verdict=critical_review.call(job["candidate"].duplicate(true),result["claims"].duplicate(true),prior["receipt"].duplicate(true),context["scene"].duplicate(true))
			if not verdict is bool or not verdict:
				stop("critical_blocked","Critical claims need correction; no confirmed prose displayed.")
				return failure(status)
			job["critical_verified"]=true
			job["critical_claims"]=result["claims"].duplicate(true)
			job["stage"]="background"
		"background":
			if not DTO.exact_keys(result,["geography","story"]) or not result["geography"] is Dictionary or not valid_story(result["story"],job["candidate"]["text"]):
				stop("retry","Invalid deferred geography reply.")
				return failure(status)
			var context=scene_context(data["state"])
			if not context.get("ok",false) or not PACK.valid_geography(result["geography"],PACK.identity(data["state"],job["turn_id"],identity["attempt_id"]),job["candidate"]["text"],context["ids"]):
				stop("retry","Deferred geography failed validation.")
				return failure(status)
			job["geography"]=result["geography"].duplicate(true)
			job["story"]=result["story"].duplicate(true)
			job["story_index"]=0
			job["stage"]="reconcile"
		_:
			return failure("No semantic reply expected.")
	job["attempt"]={}
	if not update_active(job):
		return failure("Reply persistence unconfirmed.")
	refresh()
	advance.call_deferred()
	return {"ok":true}

func reconcile(job: Dictionary,receipt: Dictionary,known: Array) -> void:
	var bundle={"campaign_id":campaign_id,"actor_id":actor_id,"turn_id":job["turn_id"],"expected_revision":data["state"]["revision"],"receipt":receipt,"narration":job["candidate"],"geography":job["geography"]}
	var result=RECON.new().commit_bundle(campaign_id,bundle,known,job.get("critical_verified",false),str(job.get("narrative_recap","")))
	if not result.get("ok",false):
		stop("retry","Narration reconciliation unconfirmed.")
		return
	if reload():
		var settled=registry.recover(campaign_id,job["tool"]["request_id"])
		if settled.get("status")=="committed":
			after_narration(job,settled)
		else:
			stop("retry","Narration committed; settlement recovery required.")

func retry() -> Dictionary:
	if running or notifying or not reload() or active().is_empty():
		return failure("No recoverable request.")
	retire_attempt()
	var job=active().duplicate(true)
	job["attempt"]={}
	if job.get("stage")=="critical_blocked":
		job.erase("geography")
		job.erase("story")
		job.erase("candidate")
		job.erase("critical_verified")
		job.erase("critical_claims")
	job["stage"]="post_story" if job.get("narration_event_id")!=null else ("reconcile" if not job.get("geography",{}).is_empty() and job.get("critical_verified",false) else ("execute" if not job.get("tool",{}).is_empty() else "new"))
	if not update_active(job):
		return failure("Retry unconfirmed.")
	advance.call_deferred()
	return {"ok":true}

func cancel() -> Dictionary:
	if running or notifying or not reload() or active().is_empty():
		return failure("No cancellable request.")
	var job=active()
	var req=job.get("tool",{})
	if not req.is_empty():
		var prior=registry.session.settlement(campaign_id,req["request_id"])
		if not prior.get("ok",false):
			return prior
		if prior.get("found",false) and prior["status"]=="committed":
			if prior.get("logical_turn_id")!=null:
				after_narration(job,prior)
			else:
				finish("committed","Already committed.")
			return {"ok":true}
		if prior.get("found",false) or registry.noncombat.prepared.has(campaign_id) or registry.resolver.unresolved.has(campaign_id):
			var canceled=registry.cancel_uncommitted(campaign_id,req["request_id"])
			if not canceled.get("ok",false):
				return failure("Committed or unresolved receipt cannot be canceled; retry recovery.")
	if not reload():
		return failure("Cancellation readback unavailable.")
	finish("cancelled","Uncommitted request canceled; queued input retained.")
	return {"ok":true}

func close_session() -> void:
	closed=true
	retire_attempt()
	# All accepted work is durable. No callback can mutate after closure.
	var existing=bindings.get(campaign_id)
	if existing is WeakRef and existing.get_ref()==self:
		bindings.erase(campaign_id)

func _exit_tree() -> void:
	close_session()

# Trusted local adapter receives original intention independently of tool args.
func review_tool(req: Dictionary,scope: Dictionary) -> Dictionary:
	var job=active()
	if job.is_empty() or not local_review.is_valid():
		return {}
	return local_review.call(req.duplicate(true),scope.duplicate(true),job["intent"].duplicate(true))

# Untrusted bidirectional output DTO. A new effect may not be committed
# inside adopted narration: C5 must request a supported continuation or
# correction. Offers/descriptions do not themselves transfer anything.
func valid_claims(claims: Variant,text: String) -> bool:
	if not claims is Array or claims.size()>32:
		return false
	for claim in claims:
		if not DTO.exact_keys(claim,["kind","evidence","proposal"]) or not claim["kind"] in ["description","receipt_claim","offer","agency","disclosure","contradiction","required_effect"] or not DTO.bounded_text(claim["evidence"],1000) or not text.contains(claim["evidence"]):
			return false
		if claim["kind"]=="required_effect" or claim["proposal"]!=null:
			return false # No post-receipt mechanical continuation in C4.
	return true

func valid_story(stories: Variant,text: String) -> bool:
	if not stories is Array or stories.size()>8:
		return false
	var keys=REG.TOOLS["story_update"][0].keys()
	keys.erase("source_event_id")
	for story in stories:
		if not DTO.exact_keys(story,["evidence","args"]) or not DTO.bounded_text(story["evidence"],1000) or not text.contains(story["evidence"]) or not DTO.exact_keys(story["args"],keys):
			return false
		var args=story["args"].duplicate(true)
		args["source_event_id"]=1 # Shape placeholder only; real source assigned after commit.
		if args["visibility"]!="player" or not registry.arguments_valid(args,REG.TOOLS["story_update"][0]):
			return false
	return true

func after_narration(job: Dictionary,settled: Dictionary) -> void:
	var event_id=settled.get("event_id",settled.get("result",{}).get("narration_event_id"))
	if not DTO.whole(event_id,1):
		stop("retry","Narration settlement source event unavailable.")
		return
	job["narration_event_id"]=event_id
	job["stage"]="post_story"
	if update_active(job):
		refresh()
		advance.call_deferred()

# C3 story writes are standalone post-settlement operations, not part of the
# B2 receipt. Each receives a persisted local request ID and current revision.
# Only evidence present in the ACTUAL committed narration may be used.
func process_story() -> void:
	if not reload():
		return
	var job=active().duplicate(true)
	var stories=job.get("story",[])
	var index=int(job.get("story_index",0))
	if index<0:
		stop("retry","Invalid deferred story cursor.")
		return
	if index>=stories.size():
		finish("committed","Turn and deferred processing complete.")
		return
	var source=registry.session.source(data["state"],job["narration_event_id"])
	var event_text=source.get("data",{}).get("text","")
	var item=stories[index]
	if source.get("kind")!="narration" or not event_text is String or not event_text.contains(item["evidence"]):
		stop("retry","Deferred evidence not present in committed narrative; review or skip.")
		return
	var req=job.get("story_request",{})
	if req.is_empty():
		var args=item["args"].duplicate(true)
		args["source_event_id"]=job["narration_event_id"]
		req={"schema_version":"2","campaign_id":campaign_id,"actor_id":actor_id,"expected_revision":data["state"]["revision"],"request_id":registry.session.make_id(),"kind":"story_update","args":args}
		job["story_request"]=req
		if not update_active(job):
			return
	var expected_args=item["args"].duplicate(true)
	expected_args["source_event_id"]=job["narration_event_id"]
	if not DTO.id_valid(req.get("request_id")) or req.get("kind")!="story_update" or req.get("campaign_id")!=campaign_id or req.get("actor_id")!=actor_id or not registry.session.typed_equal(req.get("args"),expected_args):
		stop("retry","Deferred story request differs from committed narrative proposal.")
		return
	var prior=registry.session.settlement(campaign_id,req["request_id"])
	if not prior.get("ok",false):
		stop("retry","Deferred story settlement unavailable.")
		return
	if not prior.get("found",false):
		if not registry.session.typed_equal(req.get("expected_revision"),data["state"]["revision"]):
			stop("retry","Deferred story revision changed.")
			return
		if not prepare_review(req,"post_story"):
			return
		running=true
		registry.execute(campaign_id,req,review_tool)
		running=false
		prior=registry.session.settlement(campaign_id,req["request_id"])
	if not prior.get("found",false) or not registry.session.same_request(prior["request"],req) or prior["status"]!="committed" or not reload():
		stop("retry","Deferred story proposal not committed; retry or explicitly skip.")
		return
	# Recovery of an already-present row must prove the EXACT request committed,
	# just as the fresh-execution branch does. Never advance a deferred cursor
	# after a rejected/cancelled request or a different request using this ID.
	if not prior.get("ok",false) or not prior.get("found",false) or not registry.session.same_request(prior.get("request"),req) or prior.get("status")!="committed":
		stop("retry","Deferred settlement differs or was not committed; preserve the pending work.")
		return
	job["story_index"]=index+1
	job.erase("story_request")
	if update_active(job):
		refresh()
		advance.call_deferred()

func skip_deferred() -> Dictionary:
	if running or notifying or not reload() or active().get("narration_event_id")==null:
		return failure("No settled narrative with deferred work.")
	var req=active().get("story_request",{})
	if not req.is_empty():
		var prior=registry.session.settlement(campaign_id,req["request_id"])
		if not prior.get("ok",false) or registry.noncombat.prepared.has(campaign_id):
			return failure("Deferred settlement must be recovered first.")
	finish("committed","Optional deferred proposals explicitly skipped; committed narrative retained.")
	return {"ok":true}

func resume_queue() -> Dictionary:
	if closed or notifying or not reload() or not active().is_empty() or data["work"]["queued"].is_empty() or data["state"]["pending_turn_id"]!=null or not idle_database():
		return failure("No available queued action.")
	var work=data["work"].duplicate(true)
	work["active"]=work["queued"]
	work["queued"]={}
	if not persist(work):
		return failure("Queue recovery unconfirmed.")
	refresh()
	advance.call_deferred()
	return {"ok":true}

func discard_queue() -> Dictionary:
	if closed or notifying or not reload() or data["work"]["queued"].is_empty():
		return failure("No queued action.")
	var work=data["work"].duplicate(true)
	work["draft"]=work["queued"]["intent"]["args"]["text"]
	work["queued"]={}
	if not persist(work):
		return failure("Queue change unconfirmed.")
	refresh()
	return {"ok":true}

func save_draft(text: String) -> Dictionary:
	if closed or notifying or text.length()>2000 or not reload():
		return failure("Draft unavailable.")
	var work=data["work"].duplicate(true)
	work["draft"]=text
	return {"ok":true} if persist(work) else failure("Draft not confirmed.")

# Explicit development harness only. Existing campaign manager never calls it.
func mount_workspace(workspace: Node,leave: Callable,settings: Callable) -> Dictionary:
	if campaign_id.is_empty() or view.is_empty() or workspace.is_inside_tree() or not workspace.has_method("bind_development_controller"):
		return failure("Development workspace binding unavailable.")
	workspace.configure(view,view["campaign"],leave,settings,Callable(),false,"",submit)
	workspace.bind_development_controller(self)
	view_changed.connect(workspace.apply_authoritative_view)
	return {"ok":true}

func routes_to(destination: String,revision: int) -> Dictionary:
	var state=registry.session.token(campaign_id)
	if not state.get("ok",false) or state["revision"]!=revision or not DTO.id_valid(destination):
		return failure("Travel selection revision changed.")
	var context=scene_context(state)
	if not context.get("ok",false):
		return context
	var routes: Array=[]
	for route in context["scene"]["routes"]:
		if destination!=state["location_id"] and destination in [route["from_id"],route["to_id"]] and state["location_id"] in [route["from_id"],route["to_id"]]:
			routes.append(route)
	return {"ok":true,"routes":routes,"revision":revision}

func request_status(id: String) -> Dictionary:
	if not DTO.id_valid(id) or not reload():
		return failure("Delivery lookup unavailable.")
	for slot in ["active","queued"]:
		if data["work"][slot].get("intent",{}).get("request_id")==id:
			return {"ok":true,"recorded":true,"status":"accepted_pending"}
	for row in data["work"]["history"]:
		if row.get("request_id")==id:
			return {"ok":true,"recorded":true,"status":row["status"]}
	var prior=registry.session.settlement(campaign_id,id)
	if not prior.get("ok",false):
		return prior
	return {"ok":true,"recorded":prior.get("found",false),"status":prior.get("status")}

func idle_database() -> bool:
	var read=registry.session.read(data["state"],[SQL.stmt("SELECT request_id FROM gameplay_requests WHERE status='accepted_pending' LIMIT 1")])
	return read.get("ok",false) and read["sets"][0].is_empty()

func retire_attempt() -> void:
	var previous=inflight.duplicate(true)
	inflight={}
	if not previous.is_empty():
		semantic_cancelled.emit(previous)

func provider_failed(identity: Dictionary,detail: String = "Provider request unavailable.") -> Dictionary:
	if closed or notifying or not reload() or identity!=inflight or not registry.session.typed_equal(identity,active().get("attempt")):
		return failure("Stale provider failure ignored.")
	retire_attempt()
	stop("retry",str(identity.get("stage","AI"))+": "+detail.left(600)+" Retry the saved request.")
	return {"ok":true}

func block_view(message: String) -> void:
	status=message
	if view.is_empty():
		return
	var blocked=view.duplicate(true)
	var ext=blocked.get("interaction_extension",{})
	ext["phase"]="blocked"
	ext["supported_intents"]=[]
	ext["choice_tools"]=[]
	ext["can_queue"]=false
	ext["status_text"]=message
	if blocked.get("interaction") is Dictionary:
		blocked["interaction"]["phase"]="blocked"
		blocked["interaction"]["supported_intents"]=[]
		blocked["interaction"]["status_text"]=message
	view=blocked
	notifying=true
	view_changed.emit(blocked.duplicate(true))
	notifying=false

func preview_text(job: Dictionary,state: Dictionary) -> String:
	return str(job.get("candidate",{}).get("text","")) if job.get("critical_verified",false) and state["pending_turn_id"]!=null else ""

# C5b overrides this to await independent bounded contextual assessment.
func prepare_review(_request: Dictionary,_resume_stage: String) -> bool:
	return true
