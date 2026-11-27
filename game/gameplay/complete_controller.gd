extends Node
## Explicit development-only binding. No live Gemini, no production manager wiring.
signal view_changed(snapshot: Dictionary)
signal semantic_requested(stage: String, packet: Dictionary)
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

func failure(message: String) -> Dictionary:
	return {"ok":false,"error":message}

func bind_campaign(id: String, reviewer: Callable, prose_reviewer: Callable) -> Dictionary:
	if not is_inside_tree() or not campaign_id.is_empty() or not DTO.id_valid(id) or not reviewer.is_valid() or not prose_reviewer.is_valid():
		return failure("Explicit local development binding and reviewers required.")
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
	# An old adopted turn without a C4 journal needs explicit recovery rather
	# than a new action. Never silently adopt another controller's work.
	var pending=registry.session.read(found["state"],[SQL.stmt("SELECT request_id FROM gameplay_requests WHERE status='accepted_pending'")])
	if not pending.get("ok",false):
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
	if closed or not reload():
		return
	var fresh=BASE.new().gameplay_view(campaign_id)
	var ext=fresh.get("interaction_extension",{})
	if ext.get("revision")!=data["state"]["revision"] or ext.get("actor_id")!=actor_id:
		status="Committed view unavailable; actions disabled."
		return
	var job=active()
	var work=data["work"]
	var busy=not job.is_empty()
	var phase="idle" if not busy and ext.get("phase")=="idle" else "busy"
	if busy and job.get("stage") in ["retry","clarification","critical_blocked"]:
		phase="retryable" if job["stage"]=="retry" else "awaiting_decision"
	elif not busy and ext.get("phase")!="idle":
		phase="blocked"
	var caps: Array=[]
	if phase=="idle":
		caps=DIRECT+["chat","skill_check","ability_check","saving_throw","quest_interact"]
		if fresh.has("interaction") and fresh["interaction"] is Dictionary:
			caps+=["rest","resource_use","spell_prepare","spell_unprepare","travel"]
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
	ext["reviewed_preview"]=job.get("candidate",{}).get("text","") if job.get("critical_verified",false) else ""
	ext["work_stage"]=job.get("stage","")
	ext["last_terminal"]=last
	var packet=fresh.get("interaction")
	if packet is Dictionary:
		for key in ["phase","supported_intents","settled_request_id","settled_status","status_text","active_turn_id"]:
			packet[key]=ext[key]
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
	view_changed.emit(fresh.duplicate(true))

func acknowledge(intent: Dictionary,ok: bool,message: String) -> Dictionary:
	return {"ok":ok,"request_id":intent.get("request_id",""),"message":message}

func submit(intent: Dictionary) -> Dictionary:
	if closed or running or not reload():
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
	elif not kind in DIRECT+CHOICES or not REG.TOOLS.has(kind) or not registry.arguments_valid(intent["args"],REG.TOOLS[kind][0]):
		return acknowledge(intent,false,"Explicit registered choice required.")
	var work=data["work"].duplicate(true)
	if intent["request_id"] in [work["active"].get("intent",{}).get("request_id"),work["queued"].get("intent",{}).get("request_id"),work["last"].get("request_id")]:
		return acknowledge(intent,false,"Request already recorded; recover original request.")
	var job={"intent":intent.duplicate(true),"stage":"new","tool":{},"attempt":{}}
	if not work["active"].is_empty():
		if kind!="chat" or intent["schema_version"]!="1" or not work["queued"].is_empty():
			return acknowledge(intent,false,"Only one next natural-language action may be queued.")
		work["queued"]=job
	else:
		if state["pending_turn_id"]!=null or view.get("interaction_extension",{}).get("phase")!="idle":
			return acknowledge(intent,false,"Previous turn must be recovered.")
		work["active"]=job
	if not persist(work):
		# Unknown acknowledgement deliberately does not match C1 success/reject shape.
		return {}
	status="Input saved; processing."
	refresh.call_deferred()
	advance.call_deferred()
	return acknowledge(intent,true,"Saved for processing, not yet resolved.")

func finish(status_code: String,message: String) -> void:
	var work=data["work"].duplicate(true)
	var job=work["active"]
	work["last"]={"request_id":job["intent"]["request_id"],"status":status_code,"text":job["intent"]["args"].get("text",""),"message":message}
	work["active"]={}
	if persist(work):
		status=message
	refresh()
	advance.call_deferred()

func stop(stage: String,message: String) -> void:
	var job=active().duplicate(true)
	job["stage"]=stage
	job["message"]=message
	if update_active(job):
		status=message
	refresh()

func tool_for(intent: Dictionary,state: Dictionary,kind: String,args: Dictionary) -> Dictionary:
	return {"schema_version":"2","campaign_id":campaign_id,"actor_id":actor_id,"expected_revision":state["revision"],"request_id":intent["request_id"],"kind":kind,"args":args.duplicate(true)}

# Deferred semantic adapter requests. Exact request/attempt/revision IDs are
# persisted first. A new attempt invalidates every earlier reply.
func ask(stage: String,job: Dictionary,payload: Dictionary) -> void:
	var state=data["state"]
	var identity={"campaign_id":campaign_id,"actor_id":actor_id,"request_id":job["intent"]["request_id"],"attempt_id":registry.session.make_id(),"revision":state["revision"],"stage":stage}
	job["stage"]=stage
	job["attempt"]=identity
	if not update_active(job):
		return
	status="Processing "+stage.replace("_"," ")+"…"
	refresh()
	semantic_requested.emit(stage,{"identity":identity.duplicate(true),"data":payload.duplicate(true)})

func scene_context(state: Dictionary) -> Dictionary:
	var world=WORLD.new()
	var dm=world.dm_geography(campaign_id)
	if not dm.get("ok",false):
		return dm
	var ids: Array=[]
	for place in dm["locations"]:
		ids.append(place["id"])
	return PACK.public_world(state,dm,world.public_context(campaign_id,ids))

func advance() -> void:
	if closed or running or not reload():
		return
	var work=data["work"]
	if work["active"].is_empty():
		if work["queued"].is_empty() or data["state"]["pending_turn_id"]!=null or work["last"].get("status")!="committed":
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
	match job["stage"]:
		"new","interpret":
			if job["intent"]["schema_version"]=="2" or job["intent"]["kind"] in DIRECT:
				job["tool"]=tool_for(job["intent"],state,job["intent"]["kind"],job["intent"]["args"])
				job["stage"]="execute"
				if update_active(job):
					execute_active()
			else:
				var context=scene_context(state)
				if not context.get("ok",false):
					stop("retry","Relevant context unavailable.")
					return
				ask("interpret",job,{"intent":job["intent"],"catalogue":registry.catalogue(),"scene":context["scene"],"actor":PACK.actor_projection(state)})
		"execute":
			execute_active()
		"narrate","critical","background","reconcile":
			recover_active()
		"retry","clarification","critical_blocked":
			status=str(job.get("message","Awaiting recovery or clarification."))
			refresh()

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
		if prior["request"]!=req:
			stop("retry","Stored request differs; local review required.")
			return
		if prior["status"]=="committed":
			finish("committed","Committed tool result restored.")
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
	running=true
	var result=registry.execute(campaign_id,req,local_review)
	running=false
	if not reload():
		return
	if result.get("status")=="pending_narration":
		recover_active()
	elif result.get("ok",false):
		var confirmed=registry.session.settlement(campaign_id,req["request_id"])
		if confirmed.get("found",false) and confirmed["status"]=="committed":
			finish("committed","Tool committed. Campaign refreshed.")
		else:
			stop("retry","Tool acknowledgement needs recovery.")
	else:
		stop("retry",str(result.get("error","Tool not resolved.")))

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
		finish("committed","Narrated turn settled.")
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
	var payload={"receipt":PACK.public_receipt(receipt),"player_text":result.get("player_text",""),"scene":context["scene"],"maturity_id":state["campaign"].get("maturity_id","standard"),"turn_id":job["turn_id"]}
	if job.get("stage")=="reconcile":
		reconcile(job,receipt,context["ids"])
	elif job.get("candidate",{}).is_empty():
		ask("narrate",job,payload)
	elif not job.get("critical_verified",false):
		payload["candidate"]=job["candidate"]
		ask("critical",job,payload)
	else:
		payload["candidate"]=job["candidate"]
		ask("background",job,payload)

# Provider/mock replies are data only. The trusted review callback, not an
# AI boolean, authorizes critical prose. All claims requiring new mechanics
# are deferred; C2 busy guard remains intact.
func receive(identity: Dictionary,result: Dictionary) -> Dictionary:
	if closed or running or not reload():
		return failure("Controller unavailable.")
	var job=active().duplicate(true)
	if job.is_empty() or identity!=job.get("attempt") or identity.get("revision")!=data["state"]["revision"] or identity.get("stage")!=job["stage"] or JSON.stringify(result).length()>65536:
		return failure("Stale or invalid semantic reply.")
	var stage=job["stage"]
	match stage:
		"interpret":
			if DTO.exact_keys(result,["status","message"]) and result["status"] in ["clarification","unsupported"] and DTO.bounded_text(result["message"],1000):
				stop("clarification",result["message"])
				return {"ok":true}
			if not DTO.exact_keys(result,["kind","args"]) or not REG.TOOLS.has(result["kind"]) or not registry.arguments_valid(result["args"],REG.TOOLS[result["kind"]][0]):
				stop("retry","Interpretation did not identify a supported typed action.")
				return failure(status)
			job["tool"]=tool_for(job["intent"],data["state"],result["kind"],result["args"])
			job["stage"]="execute"
		"narrate":
			if not DTO.exact_keys(result,["text"]) or not DTO.bounded_text(result["text"],12000):
				stop("retry","Invalid narration candidate.")
				return failure(status)
			job["candidate"]=PACK.identity(data["state"],job["turn_id"],identity["attempt_id"])
			job["candidate"]["text"]=result["text"]
			job["stage"]="critical"
		"critical":
			if not DTO.exact_keys(result,["claims"]) or not result["claims"] is Array or result["claims"].size()>32:
				stop("critical_blocked","Invalid output interpretation.")
				return failure(status)
			var prior=registry.recover(campaign_id,job["tool"]["request_id"])
			if prior.get("status")!="pending_narration":
				stop("retry","Receipt unavailable for output review.")
				return failure(status)
			# Independent trusted code reviews exact candidate AND interpreted
			# claims against receipt/canon; never use provider approval flags.
			var verdict=critical_review.call(job["candidate"].duplicate(true),result["claims"].duplicate(true),prior["receipt"].duplicate(true))
			if not verdict is bool or not verdict:
				stop("critical_blocked","Critical claims need correction; no confirmed prose displayed.")
				return failure(status)
			job["critical_verified"]=true
			job["critical_claims"]=result["claims"].duplicate(true)
			job["stage"]="background"
		"background":
			if not DTO.exact_keys(result,["geography"]) or not result["geography"] is Dictionary:
				stop("retry","Invalid deferred geography reply.")
				return failure(status)
			var context=scene_context(data["state"])
			if not context.get("ok",false) or not PACK.valid_geography(result["geography"],PACK.identity(data["state"],job["turn_id"],identity["attempt_id"]),job["candidate"]["text"],context["ids"]):
				stop("retry","Deferred geography failed validation.")
				return failure(status)
			job["geography"]=result["geography"].duplicate(true)
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
	var result=RECON.new().commit_bundle(campaign_id,bundle,known,job.get("critical_verified",false))
	if not result.get("ok",false):
		stop("retry","Narration reconciliation unconfirmed.")
		return
	if reload():
		var settled=registry.recover(campaign_id,job["tool"]["request_id"])
		if settled.get("status")=="committed":
			finish("committed","Narrative reconciliation completed; see committed log.")
		else:
			stop("retry","Narration committed; settlement recovery required.")

func retry() -> Dictionary:
	if running or not reload() or active().is_empty():
		return failure("No recoverable request.")
	var job=active().duplicate(true)
	job["attempt"]={}
	if job.get("stage")=="critical_blocked":
		job.erase("candidate")
		job.erase("critical_verified")
		job.erase("critical_claims")
	job["stage"]="execute" if not job.get("tool",{}).is_empty() else "new"
	if not update_active(job):
		return failure("Retry unconfirmed.")
	advance.call_deferred()
	return {"ok":true}

func cancel() -> Dictionary:
	if running or not reload() or active().is_empty():
		return failure("No cancellable request.")
	var job=active()
	var req=job.get("tool",{})
	if not req.is_empty():
		var prior=registry.session.settlement(campaign_id,req["request_id"])
		if not prior.get("ok",false):
			return prior
		if prior.get("found",false) and prior["status"]=="committed":
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
	# All accepted work is already durable. Provider callbacks are ignored.
