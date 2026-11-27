extends "res://gameplay/complete_controller.gd"
## C5 development integration. Production campaign manager remains unbound.
const ADAPTER=preload("res://gameplay/semantic_adapter.gd")
const POLICY=preload("res://gameplay/semantic_policy.gd")
const DISCOVERY=["define_official","define_custom","actor_generate","loot_discover"]
const NARRATABLE=["equip","quick_equip","swap","unequip","attune","unattune","item_use","item_drop","item_transfer","currency_transfer","loot_pickup","loot_take_all","spell_cast","spell_prepare","spell_unprepare","resource_use","rest","object_interact","reconcile_legacy_slots","party_membership"]
var policy=POLICY.new()
var adapter: Node

func bind_ai(id: String,context_reviewer: Callable=Callable(),prose_reviewer: Callable=Callable(),transport_factory: Callable=Callable()) -> Dictionary:
	if not is_inside_tree() or is_instance_valid(adapter):
		return failure("Explicit development AI binding required.")
	policy.controller=self
	policy.contextual=context_reviewer
	policy.prose=prose_reviewer
	adapter=ADAPTER.new()
	add_child(adapter)
	if not adapter.attach(self,transport_factory):
		return failure("Semantic adapter unavailable.")
	return bind_campaign(id,policy.review,policy.review_prose)

func matches(identity: Dictionary,stage: String) -> bool:
	return not closed and not running and not notifying and reload() and not active().is_empty() and identity==inflight and identity==active().get("attempt") and identity.get("stage")==stage and active().get("stage")==stage and identity.get("revision")==data["state"]["revision"]

func ask(stage: String,job: Dictionary,payload: Dictionary) -> void:
	var expanded=payload.duplicate(true)
	var state=data["state"]
	var snap=BASE.new().gameplay_view(campaign_id)
	var ext=snap.get("interaction_extension",{})
	if ext.get("revision")!=state["revision"]:
		stop("retry","Context revision changed.")
		return
	# Allowlist character attributes, never settings, master IDs or file paths.
	var character=PACK.actor_projection(state)
	for key in ["ability_modifiers","combat","equipment","resources","spellcasting","coins","carrying_capacity_lb","proficiency_ids","xp"]:
		if state["actor"].has(key):
			character[key]=state["actor"][key]
	character["owned_instances"]=ext.get("inventory_instances",[]).slice(0,64)
	character["slot_assignments"]=ext.get("known_slot_assignments",[])
	expanded["character"]=character
	expanded["recent_events"]=snap.get("events",[]).slice(maxi(0,snap.get("events",[]).size()-24))
	expanded["public_actors"]=ext.get("public_actors",[]).slice(0,32)
	expanded["public_quests"]=ext.get("public_quests",[]).slice(0,32)
	expanded["story"]=ext.get("story_records",[]).slice(0,32)
	expanded["overview"]=expanded["story"].filter(func(row): return row["kind"] in ["overview","situation"])
	expanded["selected_context"]=job.get("selected_context",[])
	expanded["recent_outcomes"]=job.get("completed_steps",[])
	expanded["interpreted"]=job.get("tool",{})
	expanded["remaining_intents"]=job.get("remaining",[])
	expanded["original_intent"]=job["intent"]
	expanded["correction"]=job.get("correction","")
	if stage=="interpret":
		expanded["intent"]=job["intent"]
		expanded["next_step_hint"]=job.get("remaining",[]).front() if not job.get("remaining",[]).is_empty() else null
		expanded["completed_steps"]=job.get("completed_steps",[])
	elif stage=="narrate":
		var refs: Array=[]
		for section in REG.TOOLS.get(job.get("tool",{}).get("kind",""),[{}, "", []])[2]:
			var q=enquiry("rule_record",{"category":"rule-sections","id":section},1)
			if q.get("ok",false):
				refs.append(q["data"])
		expanded["rules"]=refs
		expanded["player_text"]=job["intent"]["args"].get("text",payload.get("player_text",""))
	# Base C4 payload has its own limit. Trim duplicate large fields only,
	# retaining exact original input and verified outcome.
	if JSON.stringify(expanded).length()>85000:
		for key in ["selected_context","recent_events","story","inventory","public_actors"]:
			if expanded.get(key) is Array:
				expanded[key]=expanded[key].slice(0,8)
	super.ask(stage,job,expanded)

func receive_interpretation(identity: Dictionary,result: Dictionary,selected: Array) -> Dictionary:
	if not matches(identity,"interpret") or JSON.stringify(result).length()>65536:
		return failure("Stale interpretation.")
	var job=active().duplicate(true)
	if result.has("status"):
		return super.receive(identity,result)
	var steps=result.get("steps",[result])
	if not steps is Array or steps.is_empty() or steps.size()>4:
		stop("clarification","No supported ordered action.")
		return failure(status)
	for step in steps:
		if not DTO.exact_keys(step,["kind","args"]) or not REG.TOOLS.has(step["kind"]) or not registry.arguments_valid(step["args"],REG.TOOLS[step["kind"]][0]):
			stop("clarification","Invalid typed proposal.")
			return failure(status)
		# World-administrative tools may only follow verified DM output, never
		# masquerade as an ordinary player intention.
		if step["kind"] in DISCOVERY+["story_update","party_membership","reconcile_legacy_slots"]:
			stop("clarification","World proposal needs an established source and independent review.")
			return failure(status)
	var remaining=job.get("remaining",[])
	if not remaining.is_empty():
		if steps.size()!=1 or steps[0]["kind"]!=remaining[0]["kind"]:
			stop("clarification","Dependent action changed; review before proceeding.")
			return failure(status)
		remaining.pop_front()
	else:
		remaining=steps.slice(1)
	var first=steps[0]
	var args=first["args"].duplicate(true)
	if args.has("text") and job["intent"]["kind"]=="chat":
		args["text"]=job["intent"]["args"]["text"]
	var req=tool_for(job["intent"],data["state"],first["kind"],args)
	if not job.get("completed_steps",[]).is_empty():
		req["request_id"]=job.get("next_id",registry.session.make_id())
		for previous in job["completed_steps"]:
			if previous["kind"]==req["kind"] and previous["args"]==req["args"]:
				stop("clarification","Repeated dependent action requires explicit new intent.")
				return failure(status)
	job["remaining"]=remaining
	job["tool"]=req
	job["selected_context"]=selected.slice(0,8) if JSON.stringify(selected).length()<=32000 else []
	job["stage"]="execute"
	job["attempt"]={}
	inflight={}
	if not update_active(job):
		return failure("Interpretation persistence unconfirmed.")
	refresh()
	advance.call_deferred()
	return {"ok":true}

func standalone(job: Dictionary) -> bool:
	return job.get("tool",{}).get("kind") in NARRATABLE

func outcome(job: Dictionary) -> Dictionary:
	var req=job.get("tool",{})
	if standalone(job):
		var settled=registry.session.settlement(campaign_id,req["request_id"])
		if not settled.get("found",false) or settled["request"]!=req or settled["status"]!="committed" or settled["logical_turn_id"]!=null:
			return {}
		var source=registry.session.source(data["state"],settled["event_id"])
		if not registry.session.public_source(source):
			return {}
		return {"kind":"standalone_settlement","request_id":req["request_id"],"event_id":settled["event_id"],"revision":settled["revision"],"action":req["kind"],"result":settled["result"],"summary":source["data"].get("text","")}
	var recovered=registry.recover(campaign_id,req.get("request_id",""))
	return recovered["receipt"] if recovered.get("status")=="pending_narration" else {}

func recover_active() -> void:
	if not reload():
		return
	var job=active().duplicate(true)
	if not standalone(job):
		super.recover_active()
		return
	var rid=job["tool"]["request_id"]
	var event=RECON.new().standalone_event(campaign_id,rid)
	if not event.get("ok",false):
		stop("retry","Standalone narration recovery unavailable.")
		return
	if event.get("found",false):
		after_narration(job,event)
		return
	var verified=outcome(job)
	if verified.is_empty() or verified["revision"]!=data["state"]["revision"]:
		stop("retry","Standalone settlement changed; recover before narration.")
		return
	job["turn_id"]=rid
	var context=scene_context(data["state"])
	if not context.get("ok",false):
		stop("retry","Narration context unavailable.")
		return
	var payload={"settlement":verified,"turn_id":rid,"scene":context["scene"],"player_text":job["intent"]["args"].get("text",""),"maturity_id":data["state"]["campaign"].get("maturity_id","standard")}
	if job.get("stage")=="reconcile":
		reconcile(job,verified,context["ids"])
	elif job.get("candidate",{}).is_empty():
		ask("narrate",job,payload)
	else:
		payload["candidate"]=job["candidate"]
		ask("background" if job.get("critical_verified",false) else "critical",job,payload)

func receive(identity: Dictionary,result: Dictionary) -> Dictionary:
	var stage=identity.get("stage","")
	if not matches(identity,stage) or JSON.stringify(result).length()>65536:
		return failure("Stale semantic response.")
	var job=active().duplicate(true)
	if stage=="critical":
		if not DTO.exact_keys(result,["claims"]) or not valid_claims(result["claims"],job["candidate"]["text"]):
			return correction(job,"Unresolved mechanical/agency claim. Leave it as an offer or pending consequence, not a completed event.")
		var verified=outcome(job)
		var context=scene_context(data["state"])
		if verified.is_empty() or not context.get("ok",false):
			stop("retry","Outcome or canon unavailable.")
			return failure(status)
		if not policy.review_prose(job["candidate"],result["claims"],verified,context["scene"]):
			return correction(job,"Independent review could not verify the exact passage. Preserve confirmed mechanics and avoid unverified claims.")
		job["critical_verified"]=true
		job["critical_claims"]=result["claims"].duplicate(true)
		job["stage"]="background"
		job["attempt"]={}
		inflight={}
		if not update_active(job):
			return failure("Critical review persistence unconfirmed.")
		refresh()
		advance.call_deferred()
		return {"ok":true}
	if stage=="background":
		if not DTO.exact_keys(result,["geography","story","discoveries"]) or not valid_discoveries(result["discoveries"],job["candidate"]["text"]):
			stop("retry","Invalid deferred discovery proposal.")
			return failure(status)
		job["discoveries"]=result["discoveries"].duplicate(true)
		job["discovery_index"]=0
		job["definition_refs"]={}
		if not update_active(job):
			return failure("Discovery work persistence unconfirmed.")
		return super.receive(identity,{"geography":result["geography"],"story":result["story"]})
	return super.receive(identity,result)

func correction(job: Dictionary,message: String) -> Dictionary:
	inflight={}
	var count=int(job.get("correction_count",0))
	if count>=1:
		stop("critical_blocked",message+" Correction limit reached; no confirmed prose displayed.")
		return failure(status)
	job["correction_count"]=count+1
	job["correction"]=message
	job.erase("candidate")
	job.erase("critical_verified")
	job.erase("critical_claims")
	job["stage"]="narrate"
	job["attempt"]={}
	if not update_active(job):
		return failure("Correction persistence unconfirmed.")
	advance.call_deferred()
	return {"ok":true}

func reconcile(job: Dictionary,receipt: Dictionary,known: Array) -> void:
	if standalone(job):
		var result=RECON.new().commit_standalone(campaign_id,job["tool"],job["candidate"],job["geography"],known,job["intent"]["args"].get("text",""),job.get("critical_verified",false))
		if not result.get("found",false):
			stop("retry",str(result.get("error","Standalone narration reconciliation unconfirmed.")))
			return
		if reload():
			after_narration(job,result)
		return
	# The C4 default can replace conflicted prose. C5 already displayed a
	# reviewed preview; instead hold on conflict rather than silently replace.
	var planned=RECON.new().plan(data["state"],job["geography"],job["candidate"]["text"],known)
	if not planned.get("ok",false) or planned["audit"].any(func(row): return row["status"]!="accepted"):
		stop("retry","Deferred geography conflicts; reviewed preview remains provisional.")
		return
	super.reconcile(job,receipt,known)

func valid_discoveries(value: Variant,text: String) -> bool:
	if not value is Array or value.size()>8:
		return false
	for entry in value:
		if not DTO.exact_keys(entry,["evidence","kind","args"]) or not entry["kind"] in DISCOVERY or not DTO.bounded_text(entry["evidence"],1000) or not text.contains(entry["evidence"]) or not entry["args"] is Dictionary:
			return false
		var args=entry["args"].duplicate(true)
		if args.has("source_event_id") or (entry["kind"]=="actor_generate" and args.has("generation_key")):
			return false
		args["source_event_id"]=1
		if entry["kind"]=="actor_generate":
			args["generation_key"]="00000000000000000000000000000000"
			if args.get("visibility")!="player" or args.get("sheet_visibility")!="private":
				return false
		if not registry.arguments_valid(args,REG.TOOLS[entry["kind"]][0]):
			return false
	return true

func process_story() -> void:
	if not reload():
		return
	var job=active().duplicate(true)
	if int(job.get("story_index",0))<job.get("story",[]).size():
		super.process_story()
		return
	var index=int(job.get("discovery_index",0))
	var discoveries=job.get("discoveries",[])
	if index>=discoveries.size():
		finish("committed","Narration and deferred processing complete.")
		return
	var entry=discoveries[index]
	var source=registry.session.source(data["state"],job["narration_event_id"])
	if source.get("kind")!="narration" or not str(source.get("data",{}).get("text","")).contains(entry["evidence"]):
		stop("retry","Discovery source not committed.")
		return
	var req=job.get("story_request",{})
	if req.is_empty():
		var args=entry["args"].duplicate(true)
		args["source_event_id"]=job["narration_event_id"]
		if entry["kind"]=="actor_generate":
			args["generation_key"]=registry.session.make_id()
		if entry["kind"]=="loot_discover":
			for item in args["items"]:
				if item["definition_id"].begins_with("@"):
					var reference=item["definition_id"].trim_prefix("@")
					if not job.get("definition_refs",{}).has(reference):
						stop("retry","Unresolved discovery definition reference.")
						return
					item["definition_id"]=job["definition_refs"][reference]
		req=tool_for(job["intent"],data["state"],entry["kind"],args)
		req["request_id"]=registry.session.make_id()
		job["story_request"]=req
		if not update_active(job):
			return
	var prior=registry.session.settlement(campaign_id,req["request_id"])
	if not prior.get("ok",false):
		stop("retry","Discovery settlement unavailable.")
		return
	if not prior.get("found",false):
		running=true
		registry.execute(campaign_id,req,review_tool)
		running=false
		prior=registry.session.settlement(campaign_id,req["request_id"])
	if not prior.get("found",false) or prior["request"]!=req or prior["status"]!="committed" or not reload():
		stop("retry","Discovery not committed; independent review or explicit skip required.")
		return
	if entry["kind"] in ["define_official","define_custom"] and prior["result"].has("definition_id"):
		job["definition_refs"][str(index)]=prior["result"]["definition_id"]
	job["discovery_index"]=index+1
	job.erase("story_request")
	if update_active(job):
		refresh()
		advance.call_deferred()

func finish(status_code: String,message: String) -> void:
	if not reload() or active().is_empty():
		return
	var job=active().duplicate(true)
	if status_code=="committed" and standalone(job) and job.get("narration_event_id")==null:
		recover_active()
		return
	if status_code=="committed" and not job.get("remaining",[]).is_empty():
		var settled=registry.session.settlement(campaign_id,job["tool"]["request_id"])
		if not settled.get("found",false) or settled["status"]!="committed":
			stop("retry","Dependent action cannot start without prior settlement.")
			return
		var done=job.get("completed_steps",[])
		done.append({"request_id":job["tool"]["request_id"],"kind":job["tool"]["kind"],"args":job["tool"]["args"],"event_id":settled["event_id"],"revision":settled["revision"]})
		if done.size()>=4:
			stop("clarification","Ordered action limit reached; remaining actions not executed.")
			return
		var next={"intent":job["intent"],"stage":"interpret","tool":{},"attempt":{},"remaining":job["remaining"],"completed_steps":done,"next_id":registry.session.make_id()}
		if update_active(next):
			refresh()
			advance.call_deferred()
		return
	if status_code!="committed" and not job.get("completed_steps",[]).is_empty():
		message="Earlier ordered steps remain committed. Remaining action stopped. "+message
	super.finish(status_code,message)

func refresh() -> void:
	super.refresh()
	# Standalone preview follows the same distinction as B2 pending receipt.
	# Emit only when base view matches current committed revision.
	if closed or view.is_empty():
		return
	var job=active()
	if standalone(job) and job.get("critical_verified",false) and job.get("narration_event_id")==null and view.get("interaction_extension",{}).get("revision")==data.get("state",{}).get("revision"):
		view["interaction_extension"]["reviewed_preview"]=job["candidate"]["text"]
		notifying=true
		view_changed.emit(view.duplicate(true))
		notifying=false
