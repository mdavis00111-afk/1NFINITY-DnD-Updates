extends "res://gameplay/complete_controller.gd"
## C5 development integration. Production campaign manager remains unbound.
const ADAPTER=preload("res://gameplay/semantic_adapter.gd")
const POLICY=preload("res://gameplay/semantic_policy.gd")
const REVIEW=preload("res://gameplay/independent_review.gd")
const DISCOVERY=["define_official","define_custom","actor_generate","loot_discover"]
const NARRATABLE=["equip","quick_equip","swap","unequip","attune","unattune","item_use","item_drop","item_transfer","currency_transfer","loot_pickup","loot_take_all","spell_cast","spell_prepare","spell_unprepare","resource_use","rest","object_interact","reconcile_legacy_slots","party_membership"]
var policy=POLICY.new()
var independent=REVIEW.new()
var adapter: Node
# Session-local monotonic timing only. No text, IDs, keys or campaign data
# are included in the samples. Restarted jobs have no fabricated durations.
var timing: Dictionary={}
var timing_samples: Array=[]

func bind_ai(id: String,context_reviewer: Callable=Callable(),prose_reviewer: Callable=Callable(),transport_factory: Callable=Callable()) -> Dictionary:
	if not is_inside_tree() or is_instance_valid(adapter):
		return failure("Explicit development AI binding required.")
	policy.controller=self
	independent.controller=self
	if context_reviewer.is_valid() or prose_reviewer.is_valid():
		return failure("C5b binds its actual policy; fixture approval callbacks are not accepted.")
	adapter=ADAPTER.new()
	add_child(adapter)
	if not adapter.attach(self,transport_factory):
		return failure("Semantic adapter unavailable.")
	return bind_campaign(id,policy.review,policy.review_prose)

func matches(identity: Dictionary,stage: String) -> bool:
	return not closed and not running and not notifying and reload() and not active().is_empty() and identity==inflight and identity==active().get("attempt") and identity.get("stage")==stage and active().get("stage")==stage and identity.get("revision")==data["state"]["revision"]

func ask(stage: String,job: Dictionary,payload: Dictionary) -> void:
	var rid=job["intent"]["request_id"]
	var clock=Time.get_ticks_msec()
	if timing.has(rid) and not timing[rid].has("first_stage"):
		timing[rid]["first_stage"]=clock
		if timing[rid].get("queued",false):
			sample("queue_wait",clock-int(timing[rid]["accepted"]))
	var expanded=payload.duplicate(true)
	var state=data["state"]
	var snap=BASE.new().gameplay_view(campaign_id)
	var ext=snap.get("interaction_extension",{})
	if ext.get("revision")!=state["revision"]:
		stop("retry","Context revision changed.")
		return
	# Allowlist character attributes, never settings, master IDs or file paths.
	var character=PACK.actor_projection(state)
	for key in ["ability_modifiers","combat","equipment","resources","spellcasting","coins","carrying_capacity_lb","proficiency_ids","expertise_ids","feat_ids","feature_ids","class_features","racial_traits","subclass_id","subrace_id","xp","review_required"]:
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
	expanded["prior_outcome"]=job.get("prior_outcome",{})
	if job.has("pending_consequence") and stage=="narrate":
		expanded["pending_for_narrator"]={"proposal":job["pending_consequence"]["proposal"],"status":"pending, not committed"}
	if stage=="critical":
		expanded.erase("correction") # independent review sees actual text/outcome, not prior correction rationale
		expanded["candidate_hash"]=job["candidate"]["text"].sha256_text()
		expanded["candidate_length"]=job["candidate"]["text"].length()
		expanded["independent_review"]=job.has("first_review")
		expanded["known_public_ids"]=independent.public_ids(expanded.get("scene",{}),ext)
		expanded["original_player_text"]=job["intent"]["args"].get("text","")
		expanded["verified_outcome"]=expanded.get("receipt",expanded.get("settlement",{}))
	if stage=="interpret":
		expanded["intent"]=job["intent"]
		expanded["next_step_hint"]=job.get("remaining",[]).front() if not job.get("remaining",[]).is_empty() else null
		expanded["completed_steps"]=job.get("completed_steps",[])
		expanded["independent_pass"]=false
		var shapes={}
		for kind in REG.TOOLS:
			var args={}
			for key in REG.TOOLS[kind][0]:
				args[key]=null
			shapes[kind]=policy.rule_shape({"kind":kind,"args":args})
		expanded["ruling_shapes"]=shapes
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
	sample("context_build",Time.get_ticks_msec()-clock)
	super.ask(stage,job,expanded)

func receive_interpretation(identity: Dictionary,result: Dictionary,selected: Array) -> Dictionary:
	if not matches(identity,"interpret") or JSON.stringify(result).length()>65536:
		return failure("Stale interpretation.")
	var job=active().duplicate(true)
	if result.has("status"):
		return super.receive(identity,result)
	var steps=result.get("steps",[result]).duplicate(true)
	var assessment: Dictionary={}
	if steps is Array and not steps.is_empty() and steps[0] is Dictionary:
		var supplied=steps[0].get("assessment",{})
		if supplied is Dictionary:
			assessment=supplied.duplicate(true)
		for step in steps:
			if step is Dictionary:
				step.erase("assessment")
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
	if job["intent"]["kind"]=="chat":
		job["input_evidence"]={"request":req.duplicate(true),"original":job["intent"]["args"]["text"],"revision":data["state"]["revision"]}
	job.erase("input_candidate")
	job["tool"]=req
	# Bind the combined interpretation/assessment to the exact local request.
	# Existing independent interpretation remains until checkpoint 3.
	if not assessment.is_empty():
		var checked=policy.validate_assessment(req,assessment,job,data["state"])
		if not checked.get("ok",false) and not policy.direct_safe(req,job,data["state"]):
			stop("clarification",checked.get("error","Contextual assessment unavailable."))
			return failure(status)
		if checked.get("ok",false):
			job["context_review"]={"request":req.duplicate(true),"revision":data["state"]["revision"],"attempt_id":identity["attempt_id"],"report":assessment}
	var combined=job.get("selected_context",[])+selected
	var distinct: Array=[]
	for entry in combined:
		if not distinct.any(func(row): return row.get("query")==entry.get("query")):
			distinct.append(entry)
	job["selected_context"]=distinct.slice(0,8) if JSON.stringify(distinct).length()<=32000 else []
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
	else:
		ask("narrate",job,payload)

func receive(identity: Dictionary,result: Dictionary) -> Dictionary:
	var stage=identity.get("stage","")
	if not matches(identity,stage) or JSON.stringify(result).length()>65536:
		return failure("Stale semantic response.")
	var job=active().duplicate(true)
	if stage=="narrate" and result.has("geography"):
		var context=scene_context(data["state"])
		if not DTO.exact_keys(result,["text","geography","story","discoveries"]) or not DTO.bounded_text(result["text"],12000) or not context.get("ok",false) or not PACK.valid_geography(result["geography"],PACK.identity(data["state"],job["turn_id"],identity["attempt_id"]),result["text"],context["ids"]) or not valid_story(result["story"],result["text"]) or not valid_discoveries(result["discoveries"],result["text"]):
			stop("retry","Combined narration/world proposal failed validation.")
			return failure(status)
		var verified=outcome(job)
		if verified.is_empty():
			stop("retry","Verified outcome unavailable.")
			return failure(status)
		job["candidate"]=PACK.identity(data["state"],job["turn_id"],identity["attempt_id"])
		job["candidate"]["text"]=result["text"]
		job["geography"]=result["geography"].duplicate(true)
		job["story"]=result["story"].duplicate(true)
		job["discoveries"]=result["discoveries"].duplicate(true)
		job["story_index"]=0
		job["discovery_index"]=0
		job["definition_refs"]={}
		job["local_candidate_hash"]=result["text"].sha256_text()
		job["local_outcome_hash"]=JSON.stringify(verified).sha256_text()
		job["critical_verified"]=true
		job["stage"]="reconcile"
		job["attempt"]={}
		inflight={}
		if not update_active(job):
			return failure("Combined narration persistence unconfirmed.")
		refresh()
		advance.call_deferred()
		return {"ok":true}
	if stage=="adjudicate":
		var review_req=job.get("review_request",{})
		var checked=policy.validate_assessment(review_req,result,job,data["state"])
		if not checked.get("ok",false):
			stop("clarification",checked.get("error","Contextual assessment unavailable."))
			return failure(status)
		job["context_review"]={"request":review_req.duplicate(true),"revision":data["state"]["revision"],"attempt_id":identity["attempt_id"],"report":result.duplicate(true)}
		job["stage"]=job["review_resume"]
		job["attempt"]={}
		job.erase("review_request")
		job.erase("review_resume")
		inflight={}
		if not update_active(job):
			return failure("Contextual evidence persistence unconfirmed.")
		advance.call_deferred()
		return {"ok":true}
	if stage=="critical":
		var verified=outcome(job)
		var context=scene_context(data["state"])
		if verified.is_empty() or not context.get("ok",false):
			stop("retry","Outcome or canon unavailable.")
			return failure(status)
		var public_outcome=verified if standalone(job) else PACK.public_receipt(verified)
		var ext=BASE.new().gameplay_view(campaign_id).get("interaction_extension",{})
		if ext.get("revision")!=data["state"]["revision"]:
			stop("retry","Review context changed.")
			return failure(status)
		var known=independent.public_ids(context["scene"],ext)
		var original=str(job["intent"]["args"].get("text",""))
		var checked=independent.parse_report(result,job["candidate"]["text"],original,public_outcome,known)
		if not checked.get("ok",false):
			return correction(job,checked["error"])
		if not job.has("first_review"):
			job["first_review"]=result.duplicate(true)
			job["attempt"]={}
			inflight={}
			if not update_active(job):
				return failure("First review persistence unconfirmed.")
			advance.call_deferred()
			return {"ok":true}
		var merged=independent.reconcile(job["first_review"],result,job["candidate"]["text"],original,public_outcome,known)
		if not merged.get("ok",false):
			return correction(job,merged["error"])
		if not merged["effects"].is_empty():
			job["second_review"]=result.duplicate(true)
			return prepare_consequence(job,merged["effects"][0])
		job["critical_verified"]=true
		job["critical_claims"]=result["claims"].duplicate(true)
		job["second_review"]=result.duplicate(true)
		job["stage"]="background"
		if job.has("combined_world"):
			var world=job["combined_world"]
			job["geography"]=world["geography"]
			job["story"]=world["story"]
			job["discoveries"]=world["discoveries"]
			job["story_index"]=0
			job["discovery_index"]=0
			job["definition_refs"]={}
			job["stage"]="reconcile"
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
	job.erase("combined_world")
	job.erase("critical_verified")
	job.erase("critical_claims")
	job.erase("first_review")
	job.erase("second_review")
	job.erase("verified_only")
	job["stage"]="narrate"
	job["attempt"]={}
	if not update_active(job):
		return failure("Correction persistence unconfirmed.")
	advance.call_deferred()
	return {"ok":true}

func reconcile(job: Dictionary,receipt: Dictionary,known: Array) -> void:
	var context=scene_context(data["state"])
	if not context.get("ok",false) or not reviewed_candidate(job,receipt,context["scene"]):
		stop("critical_blocked","Durable independent review no longer matches exact candidate/outcome; recover before committing narration.")
		return
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
		if job.has("pending_consequence"):
			process_consequence()
			return
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
			# B4 may already have created the descriptive identity from the same
			# narration. Upgrade that actual scoped actor rather than duplicate it.
			if args.get("existing_actor_id")==null and args.get("name") is String:
				var found=enquiry("actors",{"location_id":args["location_id"]},64)
				if not found.get("ok",false) or found.get("data",{}).get("truncated",true):
					stop("retry","Actor identity enquiry incomplete.")
					return
				var matches_found: Array=[]
				for individual in found["data"].get("actors",[]):
					if str(individual.get("name","")).strip_edges().to_lower()==str(args["name"]).strip_edges().to_lower():
						matches_found.append(individual)
				if matches_found.size()>1 or (matches_found.size()==1 and (matches_found[0].get("occupation")!=args["occupation"] or matches_found[0].get("kind")!=args["kind"])):
					stop("retry","Actor identity ambiguous; preserve established actor.")
					return
				if matches_found.size()==1:
					args["existing_actor_id"]=matches_found[0]["actor_id"]
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
		if not prepare_review(req,"post_story"):
			return
		running=true
		registry.execute(campaign_id,req,review_tool)
		running=false
		prior=registry.session.settlement(campaign_id,req["request_id"])
	if not prior.get("found",false) or prior["request"]!=req or prior["status"]!="committed" or not reload():
		stop("retry","Discovery not committed; independent review or explicit skip required.")
		return
	# Recovery of an already-present row must prove the EXACT request committed,
	# just as the fresh-execution branch does. Never advance a deferred cursor
	# after a rejected/cancelled request or a different request using this ID.
	if not prior.get("ok",false) or not prior.get("found",false) or prior.get("request")!=req or prior.get("status")!="committed":
		stop("retry","Deferred settlement differs or was not committed; preserve the pending work.")
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
	if status_code=="committed" and job.has("pending_consequence") and job.get("narration_event_id")!=null:
		process_consequence()
		return
	if status_code=="committed" and standalone(job) and job.get("narration_event_id")==null:
		recover_active()
		return
	if status_code=="committed" and not job.get("remaining",[]).is_empty():
		var settled=registry.session.settlement(campaign_id,job["tool"]["request_id"])
		if settled.get("found",false) and settled.get("logical_turn_id")!=null:
			var receipt=registry.resolver.store.receipt_by_id(campaign_id,settled["logical_turn_id"])
			if not receipt.get("found",false):
				stop("retry","Dependent action receipt unavailable.")
				return
			for result in receipt["receipt"]["results"]:
				if result.get("outcome") in ["failure","automatic_failure","failed"]:
					super.finish("cancelled","Prior mechanical outcome remains committed; dependent actions stopped after failure.")
					return
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
	var rid=job["intent"]["request_id"]
	if timing.has(rid) and data.get("work",{}).get("last",{}).get("request_id")==rid:
		var completed=Time.get_ticks_msec()
		sample("input_to_terminal",completed-int(timing[rid]["accepted"]))
		if timing[rid].has("preview"):
			sample("preview_to_terminal",completed-int(timing[rid]["preview"]))
		timing.erase(rid)

func preview_text(job: Dictionary,state: Dictionary) -> String:
	var text=super.preview_text(job,state)
	if standalone(job) and job.get("critical_verified",false) and job.get("narration_event_id")==null:
		text=str(job.get("candidate",{}).get("text",""))
	if not text.is_empty() and not job.get("verified_only",false):
		var hash_value=text.sha256_text()
		if job.get("local_candidate_hash")!=hash_value and (job.get("first_review",{}).get("candidate_hash")!=hash_value or job.get("second_review",{}).get("candidate_hash")!=hash_value):
			return ""
	if not text.is_empty():
		var rid=job.get("intent",{}).get("request_id","")
		if timing.has(rid) and not timing[rid].has("preview"):
			var now=Time.get_ticks_msec()
			timing[rid]["preview"]=now
			sample("input_to_reviewed_preview",now-int(timing[rid]["accepted"]))
			if timing[rid].has("first_stage"):
				sample("critical_path",now-int(timing[rid]["first_stage"]))
	return text

func submit(intent: Dictionary) -> Dictionary:
	var clock=Time.get_ticks_msec()
	var was_busy=not active().is_empty()
	var result=super.submit(intent)
	sample("submit_ack",Time.get_ticks_msec()-clock)
	if result.get("ok",false):
		timing[intent["request_id"]]={"accepted":clock,"queued":was_busy}
	return result

func sample(stage: String,elapsed: int) -> void:
	timing_samples.append({"stage":stage,"elapsed_ms":maxi(0,elapsed)})
	timing_samples=timing_samples.slice(maxi(0,timing_samples.size()-128))

# Explicit recovery path: retain the committed mechanical result when the
# semantic service cannot safely reconcile prose. Never erase a visible preview
# without user choosing this alternative; remaining dependent steps are stopped.
func settle_verified_only() -> Dictionary:
	if closed or running or notifying or not reload():
		return failure("Controller unavailable.")
	var job=active().duplicate(true)
	if job.is_empty() or not job.get("stage") in ["retry","critical_blocked","clarification"] or job.get("narration_event_id")!=null:
		return failure("No unresolved committed outcome eligible for this recovery.")
	var verified=outcome(job)
	if verified.is_empty():
		return failure("Committed outcome unavailable.")
	retire_attempt()
	var state=data["state"]
	var turn_id=job["tool"]["request_id"] if standalone(job) else verified["turn_id"]
	var text=str(verified.get("summary","")) if standalone(job) else RECON.new().receipt_line(verified)
	if text.is_empty():
		return failure("Verified summary unavailable.")
	var candidate=PACK.identity(state,turn_id,registry.session.make_id())
	candidate["text"]=text
	var geography=PACK.identity(state,turn_id,registry.session.make_id())
	geography["source_event_id"]=null
	geography["facts"]=[]
	job["turn_id"]=turn_id
	job["candidate"]=candidate
	job["geography"]=geography
	job["critical_verified"]=true
	job["verified_only"]=true
	job["story"]=[]
	job["discoveries"]=[]
	job["story_index"]=0
	job["discovery_index"]=0
	job["remaining"]=[]
	job.erase("pending_consequence")
	job.erase("consequence_request")
	job["stage"]="reconcile"
	job["attempt"]={}
	if not update_active(job):
		return failure("Verified-only recovery not confirmed.")
	advance.call_deferred()
	return {"ok":true}

# Store the unshown original, reviewed proposal, consent and both reports.
# Settle a corrected pending-offer narration under the original receipt
# before attempting a fresh C3 transfer. Never mutate while B2 is pending.
func prepare_consequence(job: Dictionary,claim: Dictionary) -> Dictionary:
	if job.has("pending_consequence") or job.get("is_consequence",false) or int(job.get("correction_count",0))>=1:
		return correction(job,"New transfer must await a separate player intention; no completed claim is verified.")
	var proposal=claim["proposal"]
	var original=str(job["intent"]["args"].get("text",""))
	if not DTO.bounded_text(proposal.get("consent"),2000) or not original.contains(proposal["consent"]):
		return correction(job,"No explicit original player consent for the proposed transfer.")
	job["pending_consequence"]={"proposal":proposal.duplicate(true),"evidence":claim["evidence"],"candidate":job["candidate"].duplicate(true),"candidate_hash":job["candidate"]["text"].sha256_text(),"first_review":job["first_review"].duplicate(true),"second_review":job["second_review"].duplicate(true),"original_request":job["tool"].duplicate(true),"revision":data["state"]["revision"]}
	return correction(job,"Keep the creative scene and dialogue, but show the specific proposed transfer as offered or pending, not completed. Do not claim inventory or gold changed yet.")

func process_consequence() -> void:
	if not reload():
		return
	var job=active().duplicate(true)
	var pending=job.get("pending_consequence",{})
	var state=data["state"]
	if pending.is_empty() or not DTO.whole(job.get("narration_event_id"),1):
		stop("retry","Continuation source unavailable.")
		return
	var root=registry.session.settlement(campaign_id,job["tool"]["request_id"])
	if not root.get("found",false) or root["status"]!="committed" or root["request"]!=pending["original_request"] or state["pending_turn_id"]!=null or not idle_database():
		stop("retry","Original action and narration must settle before continuation.")
		return
	var source=registry.session.source(state,job["narration_event_id"])
	if source.get("kind")!="narration" or not registry.session.public_source(source) or not policy.source_text(source)==job["candidate"]["text"]:
		stop("retry","Committed continuation source differs from reviewed pending narrative.")
		return
	var req=job.get("consequence_request",{})
	if req.is_empty():
		var proposal=pending["proposal"]
		var args=independent.resolve_transfer(proposal,state)
		if args.is_empty():
			stop("clarification","Proposed transfer has no unique eligible owned possession. No acquisition occurred.")
			return
		req=tool_for(job["intent"],state,proposal["kind"],args)
		req["request_id"]=registry.session.make_id()
		job["consequence_request"]=req
		if not update_active(job):
			return
	var prior=registry.session.settlement(campaign_id,req["request_id"])
	if not prior.get("ok",false):
		stop("retry","Continuation settlement unavailable.")
		return
	if not prior.get("found",false):
		if req["expected_revision"]!=data["state"]["revision"]:
			stop("clarification","Continuation state changed; no transfer automatically rebased.")
			return
		if not prepare_review(req,"post_story"):
			return
		running=true
		registry.execute(campaign_id,req,review_tool)
		running=false
		prior=registry.session.settlement(campaign_id,req["request_id"])
	if not prior.get("found",false) or prior["request"]!=req or prior["status"]!="committed" or not reload():
		stop("retry","Transfer not committed; recover or cancel without asserting acquisition.")
		return
	# Save the exact C3 settlement identity before narrating it. If interrupted
	# before this journal write, lookup above restores it without another move.
	var previous={"request_id":root["request"]["request_id"],"kind":root["request"]["kind"],"args":root["request"]["args"],"event_id":root["event_id"],"revision":root["revision"]}
	var done=job.get("completed_steps",[])
	done.append(previous)
	var next={"intent":job["intent"],"tool":req,"stage":"narrate","attempt":{},"turn_id":req["request_id"],"is_consequence":true,"remaining":job.get("remaining",[]),"completed_steps":done,"prior_outcome":{"original_request_id":previous["request_id"],"original_event_id":previous["event_id"],"pending_narration_event_id":job["narration_event_id"],"pending_text":job["candidate"]["text"],"proposal":pending["proposal"]},"selected_context":job.get("selected_context",[])}
	if update_active(next):
		refresh()
		advance.call_deferred()

# Do not silently skip a required transfer as if it were descriptive memory.
func skip_deferred() -> Dictionary:
	if not reload():
		return failure("Work recovery unavailable.")
	if active().has("pending_consequence"):
		return failure("A transfer is pending. Recover or explicitly cancel the transfer first.")
	return super.skip_deferred()

func cancel() -> Dictionary:
	if closed or running or notifying or not reload():
		return failure("Controller unavailable.")
	var job=active().duplicate(true)
	if not job.has("pending_consequence"):
		return super.cancel()
	if job.get("narration_event_id")==null:
		return failure("Original receipt still needs narration settlement; use verified-only recovery to omit the pending transfer.")
	var req=job.get("consequence_request",{})
	if not req.is_empty():
		var prior=registry.session.settlement(campaign_id,req["request_id"])
		if not prior.get("ok",false):
			return failure("Transfer settlement unavailable.")
		if prior.get("found",false) or registry.noncombat.prepared.has(campaign_id):
			return failure("Transfer may already be committed or prepared; recover it before cancellation.")
	if not job.get("story_request",{}).is_empty() and registry.noncombat.prepared.has(campaign_id):
		return failure("Deferred write must be recovered before cancellation.")
	retire_attempt()
	job.erase("pending_consequence")
	job.erase("consequence_request")
	job.erase("review_request")
	job.erase("review_resume")
	job.erase("context_review")
	job["remaining"]=[]
	job["stage"]="post_story"
	job["attempt"]={}
	if not update_active(job):
		return failure("Cancellation not confirmed.")
	status="Pending transfer canceled; previous committed narrative retained."
	refresh()
	advance.call_deferred()
	return {"ok":true}

func prepare_review(req: Dictionary,resume_stage: String) -> bool:
	if not reload():
		return false
	var job=active().duplicate(true)
	var state=data["state"]
	if policy.direct_safe(req,job,state):
		return true
	var descriptive=policy.descriptive_assessment(req,job,state)
	if not descriptive.is_empty():
		var checked=policy.validate_assessment(req,descriptive,job,state)
		if checked.get("ok",false):
			job["context_review"]={"request":req.duplicate(true),"revision":state["revision"],"attempt_id":registry.session.make_id(),"report":descriptive}
			return update_active(job)
	var record=job.get("context_review",{})
	if record.get("request")==req and record.get("revision")==state["revision"]:
		var checked=policy.validate_assessment(req,record.get("report"),job,state)
		if checked.get("ok",false):
			return true
		stop("clarification",checked.get("error","Contextual review no longer valid."))
		return false
	stop("clarification","Combined Rules-Check assessment missing or stale. No unverified action executed.")
	return false

func advance() -> void:
	if closed or running or notifying or not reload():
		return
	if not inflight.is_empty() and inflight==active().get("attempt"):
		return
	var job=active().duplicate(true)
	if job.get("stage")=="adjudicate":
		# Legacy pending assessment cannot authorize a write or restart an obsolete provider stage.
		stop("clarification","Legacy contextual assessment interrupted. Recover or clarify the pending action.")
		return
	super.advance()

func retry() -> Dictionary:
	if closed or running or notifying or not reload() or active().is_empty():
		return failure("No recoverable request.")
	var job=active().duplicate(true)
	retire_attempt()
	job["attempt"]={}
	if job.get("stage")=="critical_blocked":
		for key in ["geography","story","candidate","critical_verified","critical_claims","first_review","second_review","verified_only"]:
			job.erase(key)
		job["correction_count"]=0
	# Recover a durable request first, not a new interpretation. Context
	# assessment can be refreshed only before an uncommitted write.
	if job.get("stage")=="adjudicate" or job.has("review_request"):
		job.erase("review_request")
		job.erase("review_resume")
		job["stage"]="post_story" if job.get("narration_event_id")!=null else ("execute" if not job.get("tool",{}).is_empty() else "new")
	elif job.get("narration_event_id")!=null:
		job["stage"]="post_story"
	elif not job.get("geography",{}).is_empty() and job.get("critical_verified",false):
		job["stage"]="reconcile"
	elif not job.get("tool",{}).is_empty():
		job["stage"]="execute"
	else:
		job["stage"]="new"
	if not update_active(job):
		return failure("Retry persistence unconfirmed.")
	advance.call_deferred()
	return {"ok":true}

func reviewed_candidate(job: Dictionary,verified: Dictionary,scene: Dictionary) -> bool:
	if not job.get("critical_verified",false):
		return false
	var text=str(job.get("candidate",{}).get("text",""))
	if not DTO.bounded_text(text,12000):
		return false
	if job.get("verified_only",false):
		var expected=str(verified.get("summary","")) if standalone(job) else RECON.new().receipt_line(verified)
		return text==expected
	if job.has("local_candidate_hash"):
		return job["local_candidate_hash"]==text.sha256_text() and job.get("local_outcome_hash")==JSON.stringify(verified).sha256_text()
	var ext=BASE.new().gameplay_view(campaign_id).get("interaction_extension",{})
	if ext.get("revision")!=data["state"]["revision"]:
		return false
	var public_outcome=verified if standalone(job) else PACK.public_receipt(verified)
	var merged=independent.reconcile(job.get("first_review",{}),job.get("second_review",{}),text,str(job["intent"]["args"].get("text","")),public_outcome,independent.public_ids(scene,ext))
	return merged.get("ok",false) and merged.get("effects",[]).is_empty()
