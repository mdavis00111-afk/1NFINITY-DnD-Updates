extends "res://gameplay/complete_controller.gd"
## C5 development integration. Production campaign manager remains unbound.
const ADAPTER=preload("res://gameplay/semantic_adapter.gd")
const POLICY=preload("res://gameplay/semantic_policy.gd")
const REVIEW=preload("res://gameplay/independent_review.gd")
const CONTEXT=preload("res://gameplay/turn_context.gd")
var context_builder=CONTEXT.new()
var scene_cache_key: Array=[]
var scene_cache: Dictionary={}
var scene_reads=0
var scene_hits=0
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
	return not closed and not running and not notifying and reload() and not active().is_empty() and identity==inflight and registry.session.typed_equal(identity,active().get("attempt")) and identity.get("stage")==stage and active().get("stage")==stage and identity.get("revision")==data["state"]["revision"]

func scene_context(state: Dictionary) -> Dictionary:
	var key=[state["campaign_id"],state["actor_id"],state["revision"],state["pending_turn_id"],state["metadata"],state["location_id"]]
	if key==scene_cache_key and not scene_cache.is_empty():
		scene_hits+=1
		return scene_cache.duplicate(true)
	var result=super.scene_context(state)
	scene_reads+=1
	if result.get("ok",false):
		scene_cache_key=key
		scene_cache=result.duplicate(true)
	return result

func command_catalogue() -> Dictionary:
	return context_builder.catalogue(registry)

func ask(stage: String,job: Dictionary,payload: Dictionary) -> void:
	var rid=job["intent"]["request_id"]
	var clock=Time.get_ticks_msec()
	if timing.has(rid) and not timing[rid].has("first_stage"):
		timing[rid]["first_stage"]=clock
		if timing[rid].get("queued",false):
			sample("queue_wait",clock-int(timing[rid]["accepted"]))
	var expanded=payload.duplicate(true)
	var state=data["state"]
	var snap=context_view(state)
	var ext=snap.get("interaction_extension",{})
	if ext.get("revision")!=state["revision"]:
		stop("retry","Context revision changed.")
		return
	# Allowlist character attributes, never settings, master IDs or file paths.
	var character=PACK.actor_projection(state)
	for key in ["ability_modifiers","combat","equipment","resources","spellcasting","coins","carrying_capacity_lb","proficiency_ids","expertise_ids","feat_ids","feature_ids","class_features","racial_traits","subclass_id","subrace_id","xp","review_required"]:
		if state["actor"].has(key):
			character[key]=state["actor"][key]
	character.erase("inventory") # actual instances below, not duplicate catalogue stacks
	character["owned_instances"]=ext.get("inventory_instances",[]).slice(0,64)
	character["slot_assignments"]=ext.get("known_slot_assignments",[])
	expanded["character"]=character
	var memory=context_builder.memory(state,registry.session,str(job.get("tool",{}).get("request_id","")) if stage=="narrate" else "")
	if not memory.get("ok",false):
		stop("retry","Revision-consistent recent moves unavailable.")
		return
	expanded["recent_moves"]=memory["moves"]
	expanded["narrative_recap"]=memory["recap"]
	# Public scene keeps older local evidence but does not repeat recent moves.
	var scene=expanded.get("scene",{}).duplicate(true)
	var move_ids=memory["moves"].map(func(row): return row["event_id"])
	# Retain bounded older evidence, including the opening, with exact source IDs.
	scene["recent_events"]=scene.get("recent_events",[]).filter(func(row): return not row.get("event_id") in move_ids).slice(0,6)
	scene["location_history"]=scene.get("location_history",[]).filter(func(row): return not row.get("event_id") in move_ids).slice(0,6)
	expanded["scene"]=scene
	expanded.erase("actor")
	expanded.erase("inventory")
	expanded.erase("loot")
	expanded.erase("recent_events")
	expanded["public_actors"]=ext.get("public_actors",[]).slice(0,32)
	expanded["public_quests"]=ext.get("public_quests",[]).slice(0,32)
	expanded["story"]=context_builder.select_story(ext.get("story_records",[]),scene,expanded["public_actors"],str(job["intent"]["args"].get("text","")))
	expanded["overview"]=expanded["story"].filter(func(row): return row["kind"] in ["overview","situation"])
	# Keep overview records in one packet field, not twice.
	expanded["story"]=expanded["story"].filter(func(row): return not row["kind"] in ["overview","situation"])
	expanded["selected_context"]=job.get("selected_context",[])
	expanded["recent_outcomes"]=job.get("completed_steps",[])
	expanded["interpreted"]=job.get("tool",{})
	expanded["remaining_intents"]=job.get("remaining",[])
	expanded.erase("original_intent")
	expanded["original_player_text"]=job["intent"]["args"].get("text",payload.get("player_text",""))
	expanded["campaign_context"]={"id":campaign_id,"title":state["campaign"].get("title",""),"maturity_id":state["campaign"].get("maturity_id","standard"),"elapsed_seconds":state["elapsed_seconds"]}
	expanded["situational_context"]=context_builder.situational(expanded["original_player_text"],job.get("tool",{}).get("kind",""),scene,ext)
	expanded["local_loot"]=ext.get("loot_containers",[]).slice(0,16)
	expanded["rules"]=context_builder.rules(expanded["situational_context"],job.get("tool",{}).get("kind",""))
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
		expanded.erase("original_player_text") # exact original already in intent
		expanded["catalogue"]=context_builder.catalogue(registry)
		expanded["lookup_catalogue"]=REG.QUERY_TYPES
		expanded["completed_steps"]=job.get("completed_steps",[])

	elif stage=="narrate":
		expanded["player_text"]=job["intent"]["args"].get("text",payload.get("player_text",""))
		expanded.erase("original_player_text")
		expanded["world_catalogue"]=context_builder.world_catalogue(registry)

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
		adapter.diagnostic("interpret_identity_or_size_rejected")
		return failure("Stale interpretation.")
	if not registry.interpreter_intent_valid(result):
		stop("clarification","Invalid typed interpretation.")
		return failure(status)
	var job=active().duplicate(true)
	if result.has("status"):
		return super.receive(identity,result)
	if not job.get("remaining",[]).is_empty():
		stop("clarification","Legacy dependent interpretation interrupted; recover without reinterpreting.")
		return failure(status)
	var steps=result.get("steps",[result]).duplicate(true)
	var remaining=steps.slice(1)
	var first=steps[0]
	var args=first["args"].duplicate(true)
	if args.has("text") and job["intent"]["kind"]=="chat":
		args["text"]=job["intent"]["args"]["text"]
	var req=tool_for(job["intent"],data["state"],first["kind"],args)
	if not job.get("completed_steps",[]).is_empty():
		req["request_id"]=job.get("next_id",registry.session.make_id())
		for previous in job["completed_steps"]:
			if previous["kind"]==req["kind"] and registry.session.typed_equal(previous["args"],req["args"]):
				stop("clarification","Repeated dependent action requires explicit new intent.")
				return failure(status)
	job["remaining"]=remaining
	if job["intent"]["kind"]=="chat":
		job["input_evidence"]={"request":req.duplicate(true),"original":job["intent"]["args"]["text"],"revision":data["state"]["revision"]}
	job.erase("input_candidate")
	# Never carry an earlier action assessment into a fresh interpretation.
	job.erase("context_review")
	job["tool"]=req
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
		adapter.diagnostic("interpret_journal_write_unconfirmed")
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
		if not settled.get("found",false) or not registry.session.same_request(settled["request"],req) or settled["status"]!="committed" or settled["logical_turn_id"]!=null:
			return {}
		var source=registry.session.source(data["state"],settled["event_id"])
		if not registry.session.public_source(source):
			return {}
		return {"kind":"standalone_settlement","request_id":req["request_id"],"event_id":settled["event_id"],"revision":settled["revision"],"action":req["kind"],"result":settled["result"],"summary":source["data"].get("text","")}
	var recovered=registry.recover(campaign_id,req.get("request_id",""))
	return recovered["receipt"] if recovered.get("status")=="pending_narration" else {}

func legacy_review_stages() -> bool:
	# Production combined protocol never dispatches obsolete review stages.
	return false

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
		if not DTO.exact_keys(result,["text","recap","geography","story","discoveries"]) or not DTO.bounded_text(result["recap"],3000) or not DTO.bounded_text(result["text"],12000) or not context.get("ok",false) or not PACK.valid_geography(result["geography"],PACK.identity(data["state"],job["turn_id"],identity["attempt_id"]),result["text"],context["ids"]) or not valid_story(result["story"],result["text"]) or not valid_discoveries(result["discoveries"],result["text"]):
			adapter.diagnostic("combined_world_validation_rejected")
			stop("retry","Combined narration/world proposal failed validation.")
			return failure(status)
		var verified=outcome(job)
		if verified.is_empty():
			stop("retry","Verified outcome unavailable.")
			return failure(status)
		job["candidate"]=PACK.identity(data["state"],job["turn_id"],identity["attempt_id"])
		job["candidate"]["text"]=result["text"]
		job["narrative_recap"]=result["recap"]
		job["local_recap_hash"]=result["recap"].sha256_text()
		job["geography"]=result["geography"].duplicate(true)
		# Combined transport uses one identity; the B4 local transaction uses
		# distinct operation IDs for narration and geography. Allocate only
		# after checking the exact provider envelope above.
		job["geography"]["request_id"]=registry.session.make_id()
		job["story"]=result["story"].duplicate(true)
		job["discoveries"]=result["discoveries"].duplicate(true)
		job["story_index"]=0
		job["discovery_index"]=0
		job["definition_refs"]={}
		job["discovery_receipts"]={}
		job["local_candidate_hash"]=result["text"].sha256_text()
		job["local_outcome_hash"]=canonical_outcome_hash(verified)
		job["local_outcome_hash_version"]=2
		job["critical_verified"]=true
		job["stage"]="reconcile"
		job["attempt"]={}
		inflight={}
		if not update_active(job):
			adapter.diagnostic("narration_journal_write_unconfirmed")
			return failure("Combined narration persistence unconfirmed.")
		refresh()
		advance.call_deferred()
		return {"ok":true}
	if stage=="adjudicate":
		stop("clarification","Obsolete provider assessment cannot authorize an action.")
		return failure(status)
	if stage=="interpret":
		return receive_interpretation(identity,result,[])
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
			job["discovery_receipts"]={}
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
		job["discovery_receipts"]={}
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
		var result=RECON.new().commit_standalone(campaign_id,job["tool"],job["candidate"],job["geography"],known,job["intent"]["args"].get("text",""),job.get("critical_verified",false),str(job.get("narrative_recap","")))
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

# The journal's source pointer is not authority on its own. Bind it to
# the actual completed action's narration, not merely any public event with
# matching words. This remains valid after subsequent descriptive revisions.
func committed_job_source(job: Dictionary,state: Dictionary) -> bool:
	var req=job.get("tool",{})
	var event_id=job.get("narration_event_id")
	if not DTO.id_valid(req.get("request_id")) or not DTO.whole(event_id,1) or req.get("campaign_id")!=state["campaign_id"] or req.get("actor_id")!=state["actor_id"]:
		return false
	var settled=registry.session.settlement(state["campaign_id"],req["request_id"])
	if not settled.get("ok",false) or not settled.get("found",false) or not registry.session.same_request(settled.get("request"),req) or settled.get("status")!="committed":
		return false
	if standalone(job):
		var linked=RECON.new().standalone_event(state["campaign_id"],req["request_id"])
		return linked.get("ok",false) and linked.get("found",false) and linked.get("event_id")==event_id
	if settled.get("logical_turn_id")!=job.get("turn_id") or settled.get("event_id")!=event_id:
		return false
	var receipt=registry.resolver.store.receipt_by_id(state["campaign_id"],job["turn_id"])
	return receipt.get("ok",false) and receipt.get("found",false) and receipt.get("narration_event_id")==event_id

func discovery_arguments(job: Dictionary,state: Dictionary,index: int,request_id: String,recovered: Dictionary={}) -> Dictionary:
	var entries=job.get("discoveries",[])
	if index<0 or index>=entries.size() or not DTO.id_valid(request_id):
		return {}
	var entry=entries[index]
	var event_id=job.get("narration_event_id")
	if not DTO.whole(event_id,1) or not committed_job_source(job,state):
		return {}
	var source=registry.session.source(state,event_id)
	if source.get("kind")!="narration" or not registry.session.public_source(source) or not valid_discoveries([entry],str(source.get("data",{}).get("text",""))):
		return {}
	var args=entry["args"].duplicate(true)
	args["source_event_id"]=event_id
	if entry["kind"]=="actor_generate":
		args["generation_key"]=request_id
		if args.get("existing_actor_id")==null and args.get("name") is String:
			var found=enquiry("actors",{"location_id":args["location_id"]},64)
			if not found.get("ok",false) or found.get("data",{}).get("truncated",true):
				return {}
			var matches_found: Array=[]
			for individual in found["data"].get("actors",[]):
				if str(individual.get("name","")).strip_edges().to_lower()==str(args["name"]).strip_edges().to_lower():
					matches_found.append(individual)
			if matches_found.size()>1 or (matches_found.size()==1 and (matches_found[0].get("occupation")!=args["occupation"] or matches_found[0].get("kind")!=args["kind"])):
				return {}
			if matches_found.size()==1:
				args["existing_actor_id"]=matches_found[0]["actor_id"]
				if not recovered.is_empty() and recovered.get("result",{}).get("actor_id")==args["existing_actor_id"] and recovered.get("request",{}).get("args",{}).get("existing_actor_id")==null:
					args["existing_actor_id"]=null
	if entry["kind"]=="loot_discover":
		for item in args["items"]:
			if item["definition_id"].begins_with("@"):
				var reference=item["definition_id"].trim_prefix("@")
				if not reference.is_valid_int() or str(int(reference))!=reference or int(reference)<0 or int(reference)>=index:
					return {}
				var original=entries[int(reference)]
				if not original["kind"] in ["define_custom","define_official"]:
					return {}
				var recorded=job.get("discovery_receipts",{}).get(reference,{})
				var prior=registry.session.settlement(state["campaign_id"],str(recorded.get("request_id","")))
				var expected=original["args"].duplicate(true)
				expected["source_event_id"]=event_id
				if not prior.get("ok",false) or not prior.get("found",false) or prior.get("status")!="committed" or not registry.session.same_request(prior.get("request"),recorded) or recorded.get("kind")!=original["kind"] or not registry.session.typed_equal(recorded.get("args"),expected) or prior["revision"]>state["revision"]:
					return {}
				var definition=prior["result"].get("definition_id")
				if not definition is String or definition.is_empty() or definition.begins_with("@"):
					return {}
				item["definition_id"]=definition
	return args

func discovery_request_valid(req: Dictionary,job: Dictionary,state: Dictionary,settled: Dictionary={}) -> bool:
	var index=int(job.get("discovery_index",0))
	var entries=job.get("discoveries",[])
	if index<0 or index>=entries.size() or not registry.session.same_request(req,job.get("story_request")) or req.get("kind")!=entries[index]["kind"] or req.get("campaign_id")!=state["campaign_id"] or req.get("actor_id")!=state["actor_id"]:
		return false
	if settled.is_empty():
		if req.get("expected_revision")!=state["revision"]:
			return false
	elif not registry.session.same_request(settled.get("request"),req) or settled.get("status")!="committed" or settled.get("revision")!=state["revision"]:
		return false
	var expected=discovery_arguments(job,state,index,req.get("request_id",""),settled)
	return not expected.is_empty() and registry.session.typed_equal(req.get("args"),expected) and registry.arguments_valid(expected,REG.TOOLS[req["kind"]][0])

func process_story() -> void:
	if not reload():
		return
	var job=active().duplicate(true)
	if not committed_job_source(job,data["state"]):
		stop("retry","Deferred narration source does not belong to this committed action.")
		return
	if int(job.get("story_index",0))<job.get("story",[]).size():
		super.process_story()
		return
	var index=int(job.get("discovery_index",0))
	var discoveries=job.get("discoveries",[])
	if index<0 or int(job.get("story_index",0))<0:
		stop("retry","Invalid deferred world cursor.")
		return
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
		var request_id=registry.session.make_id()
		var args=discovery_arguments(job,data["state"],index,request_id)
		if args.is_empty():
			stop("retry","Discovery arguments cannot be reconstructed.")
			return
		req=tool_for(job["intent"],data["state"],entry["kind"],args)
		req["request_id"]=request_id
		job["story_request"]=req
		if not update_active(job):
			return
	var prior=registry.session.settlement(campaign_id,req["request_id"])
	if not prior.get("ok",false):
		stop("retry","Discovery settlement unavailable.")
		return
	if not prior.get("found",false):
		if not discovery_request_valid(req,job,data["state"]):
			stop("retry","Discovery arguments differ from staged proposal.")
			return
		if not prepare_review(req,"post_story"):
			return
		running=true
		registry.execute(campaign_id,req,review_tool)
		running=false
		prior=registry.session.settlement(campaign_id,req["request_id"])
	if not prior.get("found",false) or not registry.session.same_request(prior["request"],req) or prior["status"]!="committed" or not reload():
		stop("retry","Discovery not committed; independent review or explicit skip required.")
		return
	# Recovery of an already-present row must prove the EXACT request committed,
	# just as the fresh-execution branch does. Never advance a deferred cursor
	# after a rejected/cancelled request or a different request using this ID.
	if not prior.get("ok",false) or not prior.get("found",false) or not registry.session.same_request(prior.get("request"),req) or prior.get("status")!="committed":
		stop("retry","Deferred settlement differs or was not committed; preserve the pending work.")
		return
	if not discovery_request_valid(req,job,data["state"],prior):
		stop("retry","Committed discovery differs from staged proposal.")
		return
	if not job.has("discovery_receipts"):
		job["discovery_receipts"]={}
	job["discovery_receipts"][str(index)]=req.duplicate(true)
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
	if status_code=="committed" and standalone(job) and job["intent"]["kind"]=="chat" and job.get("narration_event_id")==null:
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
		if not settled.get("ok",false) or not settled.get("found",false) or settled["status"]!="committed" or not registry.session.same_request(settled.get("request"),job["tool"]):
			stop("retry","Dependent action cannot start without prior settlement.")
			return
		var done=job.get("completed_steps",[])
		done.append({"request_id":job["tool"]["request_id"],"kind":job["tool"]["kind"],"args":job["tool"]["args"],"event_id":settled["event_id"],"revision":settled["revision"]})
		if done.size()>=4:
			stop("clarification","Ordered action limit reached; remaining actions not executed.")
			return
		var remaining=job["remaining"].duplicate(true)
		var step=remaining.pop_front()
		if not registry.interpreter_action_valid(step):
			super.finish("cancelled","Prior steps committed; invalid stored dependent intent.")
			return
		var args=step["args"].duplicate(true)
		if args.has("text") and job["intent"]["kind"]=="chat":
			args["text"]=job["intent"]["args"]["text"]
		var req=tool_for(job["intent"],data["state"],step["kind"],args)
		req["request_id"]=registry.session.make_id()
		for previous in done:
			if previous["kind"]==req["kind"] and registry.session.typed_equal(previous["args"],req["args"]):
				super.finish("cancelled","Prior steps committed; repeated dependent action requires new intent.")
				return
		var next={"intent":job["intent"],"stage":"execute","tool":req,"attempt":{},"remaining":remaining,"completed_steps":done,"selected_context":job.get("selected_context",[])}
		if job["intent"]["kind"]=="chat":
			next["input_evidence"]={"request":req.duplicate(true),"original":job["intent"]["args"]["text"],"revision":data["state"]["revision"]}
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
	job.erase("narrative_recap")
	job.erase("local_recap_hash")
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
	if not root.get("found",false) or root["status"]!="committed" or not registry.session.same_request(root["request"],pending["original_request"]) or state["pending_turn_id"]!=null or not idle_database():
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
	if not prior.get("found",false) or not registry.session.same_request(prior["request"],req) or prior["status"]!="committed" or not reload():
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
			job["context_review"]={"request":req.duplicate(true),"revision":state["revision"],"attempt_id":registry.session.make_id(),"report":descriptive,"authorization_version":"committed-description-v027"}
			return update_active(job)
	stop("clarification","Local contextual authorization required. No unverified action executed.")
	return false

func advance() -> void:
	if closed or running or notifying or not reload():
		return
	if not inflight.is_empty() and registry.session.typed_equal(inflight,active().get("attempt")):
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

func canonical_outcome_hash(verified: Dictionary) -> String:
	# Normalize through the same JSON representation used by durable work.
	var normalized=JSON.parse_string(JSON.stringify(verified,"",true,true))
	if not normalized is Dictionary or not registry.session.typed_equal(verified,normalized):
		return ""
	return JSON.stringify(normalized,"",true,true).sha256_text()

func reviewed_candidate(job: Dictionary,verified: Dictionary,scene: Dictionary) -> bool:
	if not job.get("critical_verified",false):
		return false
	var text=str(job.get("candidate",{}).get("text",""))
	if not DTO.bounded_text(text,12000):
		return false
	if job.has("narrative_recap") and (not DTO.bounded_text(job["narrative_recap"],3000) or job.get("local_recap_hash")!=job["narrative_recap"].sha256_text()):
		return false
	if job.get("verified_only",false):
		var expected=str(verified.get("summary","")) if standalone(job) else RECON.new().receipt_line(verified)
		return text==expected
	if job.has("local_candidate_hash"):
		var version=job.get("local_outcome_hash_version",1)
		if not registry.session.typed_equal(version,1) and not registry.session.typed_equal(version,2):
			return false
		var expected=canonical_outcome_hash(verified) if registry.session.typed_equal(version,2) else JSON.stringify(verified).sha256_text()
		return not expected.is_empty() and job["local_candidate_hash"]==text.sha256_text() and job.get("local_outcome_hash")==expected
	var ext=BASE.new().gameplay_view(campaign_id).get("interaction_extension",{})
	if ext.get("revision")!=data["state"]["revision"]:
		return false
	var public_outcome=verified if standalone(job) else PACK.public_receipt(verified)
	var merged=independent.reconcile(job.get("first_review",{}),job.get("second_review",{}),text,str(job["intent"]["args"].get("text","")),public_outcome,independent.public_ids(scene,ext))
	return merged.get("ok",false) and merged.get("effects",[]).is_empty()
