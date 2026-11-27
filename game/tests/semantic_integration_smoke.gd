extends SceneTree
## C5 actual controller, registry, SQLite and prompt workflow. Only transport
## and explicitly scoped independent contextual/prose review are fixtures.
const BASE=preload("res://campaigns/campaign_store.gd")
const PLAYER=preload("res://players/character_store.gd")
const CAT=preload("res://rules/catalog.gd")
const SESSION=preload("res://persistence/gameplay_session.gd")
const MIGRATION=preload("res://persistence/gameplay_migration.gd")
const CTRL=preload("res://gameplay/semantic_controller.gd")
const WORKSPACE=preload("res://gameplay/game_workspace.gd")
const PACK=preload("res://turns/agent_packets.gd")
const RECON=preload("res://world/geography_reconciler.gd")
const NARRATOR=preload("res://campaigns/narrator_prompt.gd")
const SHARE=preload("res://campaigns/prompt_sharing.gd")
const PROSE="The shield settles against your arm. A carved amber tally lies on the counter."
const TALK="The innkeeper mentions a bridge."
const INPUT="I lift that shield onto my arm."
var base=BASE.new()
var session=SESSION.new()
var ctrl
var workspace
var failures: Array[String]=[]

class MockTransport:
	extends Node
	signal completed(ok: bool,message: String)
	var prompt=""
	var cancelled=false
	func generate(value: String,_key: String="",_model: String="",_complete: bool=false,_schema: Dictionary={},_chars: int=4000,_tokens: int=2048,_temperature: float=0.8) -> void:
		prompt=value
	func cancel_generation() -> void:
		cancelled=true
	func reply(value: Variant) -> void:
		completed.emit(true,value if value is String else JSON.stringify(value))

func _initialize() -> void:
	run.call_deferred()

func expect(ok: bool,message: String) -> bool:
	if not ok:
		failures.append(message)
	return ok

func finish() -> void:
	for failure in failures:
		push_error(failure)
	print("C5 semantic integration failures: ",failures.size())
	quit(0 if failures.is_empty() else 1)

func master_record(id: String,role: String="fighter") -> Dictionary:
	var slots: Dictionary={}
	for level in range(1,10):
		slots[str(level)]={"maximum":2 if role=="cleric" and level==1 else 0,"spent":0}
	var profs=["simple-weapons","light-armor","medium-armor","shields"]
	if role=="fighter":
		profs.append_array(["martial-weapons","heavy-armor","saving-throw-str","saving-throw-con"])
	else:
		profs.append_array(["saving-throw-wis","saving-throw-cha"])
	var saves={"str":2 if role=="fighter" else 0,"dex":2,"con":3 if role=="fighter" else 1,"int":0,"wis":1 if role=="fighter" else 3,"cha":0 if role=="fighter" else 2}
	return {"id":id,"name":"C3 fixture "+role,"status":"ready","ruleset":CAT.RULESET,"catalog_revision":CAT.REVISION,"level":1,"race_id":"human","class_id":role,"subclass_id":"","ability_scores":{"str":10,"dex":14,"con":12,"int":10,"wis":12,"cha":10},"ability_modifiers":{"str":0,"dex":2,"con":1,"int":0,"wis":1,"cha":0},"proficiency_bonus":2,"proficiency_ids":profs,"expertise_ids":[],"skills":{},"saving_throws":saves,"equipment":{"armor_id":"","shield_id":"","weapon_ids":[],"armor_penalty":false},"attacks":[],"inventory":[{"item_id":"dagger","quantity":2,"equipped":false},{"item_id":"shield","quantity":1,"equipped":false},{"item_id":"greatsword","quantity":1,"equipped":false},{"item_id":"leather-armor","quantity":1,"equipped":false},{"item_id":"magic:potion-of-healing-common","quantity":1,"equipped":false},{"item_id":"rations-1-day","quantity":1,"equipped":false}],"coins":{"cp":0,"sp":0,"ep":0,"gp":5,"pp":0},"carrying_capacity_lb":150,"combat":{"hp_current":4,"hp_max":11 if role=="fighter" else 9,"hp_temp":0,"conditions":[],"active_effects":[],"exhaustion":0,"armor_class":12,"speed_feet":30,"size":"Medium","passive_perception":11,"hit_die":10 if role=="fighter" else 8,"hit_dice_total":1,"hit_dice_spent":0},"resources":{"second_wind":{"max":1,"spent":0,"reset":"short_or_long_rest"}} if role=="fighter" else {},"spellcasting":{"ability":"wis" if role=="cleric" else "","slots":slots,"pact_magic":false,"concentration":null,"attack_bonus":3 if role=="cleric" else null,"save_dc":11 if role=="cleric" else null,"known_ids":[],"prepared_ids":["cure-wounds","healing-word"] if role=="cleric" else [],"always_prepared_ids":[],"cantrip_ids":[],"racial_cantrip_ids":[]},"review_required":[]}


func money(gp: int) -> Dictionary:
	return {"cp":0,"sp":0,"ep":0,"gp":gp,"pp":0}


func factory() -> Node:
	return MockTransport.new()

func contextual(req: Dictionary,_scope: Dictionary,_intent: Dictionary,state: Dictionary) -> Dictionary:
	var accepted=false
	if req["kind"] in ["define_custom","loot_discover"]:
		var source=session.source(state,req["args"]["source_event_id"])
		accepted=source.get("kind")=="narration" and source.get("data",{}).get("text")==PROSE
		if req["kind"]=="define_custom":
			accepted=accepted and req["args"]["definition"]["name"]=="Carved amber tally"
		else:
			accepted=accepted and req["args"]["location_id"]==state["location_id"] and req["args"]["items"].size()==1 and req["args"]["items"][0]["quantity"]==1
	return {"request_id":req["request_id"],"campaign_id":req["campaign_id"],"actor_id":req["actor_id"],"expected_revision":req["expected_revision"],"accepted":accepted,"ruling":{},"reason":"Specific disposable source/effect review only."}

func prose(candidate: Dictionary,claims: Array,outcome: Dictionary,_scene: Dictionary) -> bool:
	if claims.is_empty():
		return false
	if candidate["text"]==PROSE:
		return outcome.get("kind")=="standalone_settlement" and outcome.get("action")=="equip" and outcome.get("result",{}).get("armor_class")==14
	return candidate["text"]==TALK and PACK.committed_receipt_usable(outcome) and outcome["rolls"].is_empty()

func bind(id: String) -> bool:
	ctrl=CTRL.new()
	root.add_child(ctrl)
	if not expect(ctrl.bind_ai(id,contextual,prose,factory).get("ok",false),"Explicit C5 binding failed"):
		return false
	workspace=WORKSPACE.new()
	if not expect(ctrl.mount_workspace(workspace,Callable(),Callable()).get("ok",false),"Actual workspace mount"):
		return false
	root.add_child(workspace)
	return true

func pump(stage: String,after_serial: int=-1) -> bool:
	for i in range(60):
		await process_frame
		if stage=="idle" and ctrl.active().is_empty() and ctrl.view.get("interaction_extension",{}).get("phase")=="idle":
			return true
		if stage!="idle" and ctrl.inflight.get("stage")==stage and is_instance_valid(ctrl.adapter.transport) and not ctrl.adapter.transport.prompt.is_empty() and ctrl.adapter.serial>after_serial:
			return true
	return expect(false,"Expected "+stage+"; got "+str(ctrl.active().get("stage"))+" / "+ctrl.status)

func reply(value: Variant) -> void:
	ctrl.adapter.transport.reply(value)

func geography() -> Dictionary:
	var identity=PACK.identity(session.token(ctrl.campaign_id),ctrl.active()["turn_id"],ctrl.inflight["attempt_id"])
	identity["source_event_id"]=null
	identity["facts"]=[]
	return identity

func prompt_fixture() -> void:
	var cfg=ConfigFile.new()
	cfg.set_value("gemini","api_key","fixture-local-key-not-shared")
	cfg.set_value("prompts","Scene","Fixture scene")
	expect(cfg.save(NARRATOR.PATH)==OK,"Fixture settings save")
	expect(NARRATOR.save_prompt("Local creative prompt.").is_empty(),"Local prompt save")
	expect(not SHARE.export_proposal("test",false).get("ok",false),"Export without consent blocked")
	var exported=SHARE.export_proposal("Fixture change",true)
	if not expect(exported.get("ok",false),"Prompt-only export"):
		return
	var read=SHARE.read_file(exported["path"])
	if not expect(read.get("ok",false) and not FileAccess.get_file_as_string(exported["path"]).contains("fixture-local-key-not-shared"),"Export schema and no key"):
		return
	var remote=read["bundle"].duplicate(true)
	remote["kind"]="shared"
	remote["source_commit"]="1111111111111111111111111111111111111111"
	remote["prompt"]="Lead-reviewed creative prompt."
	remote["prompt_hash"]=remote["prompt"].sha256_text()
	var shared=SHARE.write_unique(SHARE.ROOT+"/fixture","shared",remote)
	if not expect(shared.get("ok",false),"Shared fixture write"):
		return
	var inspected=SHARE.inspect_shared(shared["path"])
	expect(inspected.get("conflict",false),"Local versus shared conflict detected")
	expect(not SHARE.apply_shared(inspected,true,false).get("ok",false),"Unconfirmed replacement rejected")
	expect(SHARE.apply_shared(inspected,false,true).get("ok",false),"Keep-local conflict resolution")
	expect(NARRATOR.load_prompt()=="Local creative prompt.","Local customization retained")
	cfg.load(NARRATOR.PATH)
	expect(cfg.get_value("gemini","api_key")=="fixture-local-key-not-shared" and cfg.get_value("prompts","Scene")=="Fixture scene","Other settings preserved")
	expect(not SHARE.inspect_shared(shared["path"]).get("ok",false),"Stale shared revision rejected")

func run() -> void:
	var expected=OS.get_environment("INFINITY_TEST_USER_ROOT").replace("\\","/").trim_suffix("/")
	var actual=ProjectSettings.globalize_path("user://").replace("\\","/").trim_suffix("/")
	if expected.is_empty() or expected!=actual or FileAccess.file_exists("user://players.db") or FileAccess.file_exists("user://settings.cfg") or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(BASE.ROOT)):
		push_error("C5 fixture requires explicitly authorized empty disposable user directory.")
		quit(2)
		return
	prompt_fixture()
	var players=PLAYER.new()
	var master=players.make_id()
	if not expect(players.save_record(master_record(master)).is_empty(),"Master fixture"):
		finish()
		return
	var original=players.load_record(master)
	var a=base.create_campaign("C5 fixture",master,"tavern","standard")
	var b=base.create_campaign("C5 sibling",master,"road","standard")
	if not expect(not a.is_empty() and not b.is_empty(),"Campaign fixture"):
		finish()
		return
	var id=a["id"]
	var sibling=base.gameplay_view(b["id"])
	if not expect(MIGRATION.new().ensure(id).get("ok",false),"C2 migration"):
		finish()
		return
	var opening=base.prepare_opening(id)
	if opening.is_empty():
		expect(false,"Opening unavailable")
		finish()
		return
	var raw=JSON.stringify({"start_id":"tavern","location_name":"Oak Inn","atmosphere":"A quiet room.","npcs":[{"name":"Mara","occupation":"Innkeeper","attitude":0}],"world_facts":["The floor is wooden."],"thumbnail_id":"tavern"})
	if not expect(base.commit_opening(id,opening["previous"],raw).is_empty(),"Opening"):
		finish()
		return
	if not bind(id):
		finish()
		return
	var shield=""
	for item in ctrl.view["interaction_extension"]["inventory_instances"]:
		if item["definition_id"]=="shield":
			shield=item["instance_id"]
	if not expect(not shield.is_empty(),"Owned shield"):
		finish()
		return
	workspace.composer.text=INPUT
	workspace.submit_chat()
	if not await pump("interpret"):
		finish()
		return
	var rid=ctrl.inflight["request_id"]
	var serial=ctrl.adapter.serial
	reply({"queries":[{"kind":"inventory","args":{"actor_id":ctrl.actor_id},"limit":8}]})
	if not await pump("interpret",serial):
		finish()
		return
	expect(ctrl.adapter.transport.prompt.contains(shield),"Real inventory enquiry feedback")
	serial=ctrl.adapter.serial
	reply({"kind":"equip","args":{"instance_id":shield}})
	if not await pump("interpret",serial):
		finish()
		return
	expect(ctrl.adapter.transport.prompt.contains("validation_error"),"Malformed typed request repaired")
	var equip={"kind":"equip","args":{"instance_id":shield,"slot":"shield","grip":"one_handed"}}
	serial=ctrl.adapter.serial
	reply(equip)
	if not await pump("interpret",serial):
		finish()
		return
	expect(ctrl.adapter.transport.prompt.contains("independent_pass"),"Second independent interpretation")
	reply(equip)
	if not await pump("narrate"):
		finish()
		return
	expect(workspace.actor["combat"]["armor_class"]==14 and session.settlement(id,rid).get("status")=="committed","Real equip and committed GUI refresh")
	expect(ctrl.adapter.transport.prompt.contains(NARRATOR.load_prompt()) and ctrl.adapter.transport.prompt.contains(INPUT),"Existing editable prompt and exact original input")
	reply("You gain ten gold.")
	if not await pump("critical"):
		finish()
		return
	reply({"claims":[{"kind":"required_effect","evidence":"You gain ten gold.","proposal":{"kind":"currency_transfer","args":{}}}]})
	if not await pump("narrate"):
		finish()
		return
	expect(workspace.actor["coins"]["gp"]==5,"Invented grant blocked before display")
	reply(PROSE)
	if not await pump("critical"):
		finish()
		return
	reply({"claims":[{"kind":"receipt_claim","evidence":"The shield settles against your arm.","proposal":null},{"kind":"description","evidence":"A carved amber tally lies on the counter.","proposal":null}]})
	if not await pump("background"):
		finish()
		return
	expect(ctrl.view["interaction_extension"]["reviewed_preview"]==PROSE,"Early standalone preview")
	workspace.composer.text="Ask her about the bridge, then look around."
	workspace.submit_chat()
	await process_frame
	expect(not ctrl.view["interaction_extension"]["queued_text"].is_empty(),"Queued natural action")
	var old=ctrl.inflight.duplicate(true)
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	await process_frame
	if not bind(id) or not await pump("background"):
		finish()
		return
	expect(not ctrl.receive(old,{}).get("ok",false),"Late prior-session output rejected")
	var definition={"name":"Carved amber tally","category":"gear","description":"A carved amber tally.","unit_weight_lb":0.1,"cost_cp":1,"properties":[],"charges_max":null,"attunement_required":false}
	var discovered=[{"kind":"define_custom","evidence":"A carved amber tally lies on the counter.","args":{"definition":definition,"official_equivalent_id":null}},{"kind":"loot_discover","evidence":"A carved amber tally lies on the counter.","args":{"location_id":session.token(id)["location_id"],"name":"Counter discovery","items":[{"definition_id":"@0","quantity":1,"charges":null,"condition":"intact","attunement":"not_required"}],"coins":money(0)}}]
	reply({"geography":geography(),"story":[],"discoveries":discovered})
	if not await pump("interpret"):
		finish()
		return
	expect(ctrl.inflight["revision"]>old["revision"],"Queue uses latest committed state")
	expect(RECON.new().standalone_event(id,rid).get("found",false),"Source-linked standalone narration")
	var loot=ctrl.view["interaction_extension"]["loot_containers"]
	expect(loot.size()==1 and loot[0]["items"][0]["name"]=="Carved amber tally","Actual custom definition/discovery; no auto-pickup")
	var queued=ctrl.active()["intent"]["args"]["text"]
	var root_id=ctrl.inflight["request_id"]
	reply({"steps":[{"kind":"conversation","args":{"text":queued}},{"kind":"observe","args":{"text":queued}}]})
	if not await pump("narrate"):
		finish()
		return
	reply(TALK)
	if not await pump("critical"):
		finish()
		return
	reply({"claims":[{"kind":"description","evidence":TALK,"proposal":null}]})
	if not await pump("background"):
		finish()
		return
	reply({"geography":geography(),"story":[],"discoveries":[]})
	if not await pump("interpret"):
		finish()
		return
	expect(session.settlement(id,root_id).get("status")=="committed" and ctrl.active().get("completed_steps",[]).size()==1,"Dependent step waits for prior settlement")
	reply({"kind":"observe","args":{"text":queued}})
	if not await pump("narrate"):
		finish()
		return
	var sub_id=ctrl.active()["tool"]["request_id"]
	expect(sub_id!=root_id,"Distinct durable subrequest")
	reply(TALK)
	if not await pump("critical"):
		finish()
		return
	reply({"claims":[{"kind":"description","evidence":TALK,"proposal":null}]})
	if not await pump("background"):
		finish()
		return
	reply({"geography":geography(),"story":[],"discoveries":[]})
	if not await pump("idle"):
		finish()
		return
	expect(session.settlement(id,sub_id).get("status")=="committed","Dependent action committed once")
	expect(players.load_record(master)==original and base.gameplay_view(b["id"])==sibling,"Master and sibling isolation")
	expect(not ctrl.adapter.metrics.is_empty(),"Mock call timing instrumentation")
	expect(not ctrl.timing_samples.is_empty(),"Controller context timing instrumentation")
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	finish()
