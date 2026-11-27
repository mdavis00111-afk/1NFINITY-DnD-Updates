extends SceneTree
## C5 actual controller, registry, SQLite and prompt workflow. Only transport
## is mocked. Actual C5b semantic review/context policy runs locally.
const BASE=preload("res://campaigns/campaign_store.gd")
const PLAYER=preload("res://players/character_store.gd")
const CAT=preload("res://rules/catalog.gd")
const SESSION=preload("res://persistence/gameplay_session.gd")
const SQL=preload("res://systems/sqlite.gd")
const MIGRATION=preload("res://persistence/gameplay_migration.gd")
const CTRL=preload("res://gameplay/semantic_controller.gd")
const WORKSPACE=preload("res://gameplay/game_workspace.gd")
const PACK=preload("res://turns/agent_packets.gd")
const RECON=preload("res://world/geography_reconciler.gd")
const GENERATOR=preload("res://persistence/actor_generation.gd")
const REG=preload("res://gameplay/tool_registry.gd")
const NARRATOR=preload("res://campaigns/narrator_prompt.gd")
const SHARE=preload("res://campaigns/prompt_sharing.gd")
const PROSE="The shield settles against your arm. Mara laughs. \"That suits you,\" she says, polishing a cup. An abandoned carved amber tally lies on the counter, free to take. Mara offers two gold pieces for your help."
const TALK="Mara leans forward, her voice dropping. \"The bridge? A mason named Orrin built it.\" She stares into the hearth, as though remembering an old argument."
const ACCEPT="I accept the two gold pieces Mara offers."
const PROPOSED="Mara places two gold pieces into your hand."
const PENDING="Mara holds out two gold pieces. \"For your trouble,\" she says."
const TRANSFERRED="Mara smiles as the two gold pieces pass to you. \"A debt paid,\" she says."
const DECLINE="I decline her offer."
const DECLINED="Mara nods. \"Fair enough.\" She puts her purse away."
const ACCEPT_ITEM="I accept one of Mara’s daggers."
const ITEM_PROPOSED="Mara hands you one of her daggers."
const ITEM_PENDING="Mara holds out one of her daggers for you."
const ITEM_SETTLED="Mara passes the dagger across. \"Keep it sharp,\" she says."
const INPUT="I lift that shield onto my arm."
var base=BASE.new()
var session=SESSION.new()
var ctrl
var workspace
var failures: Array[String]=[]
var outbound: Array=[]

class MockTransport:
	extends Node
	signal completed(ok: bool,message: String)
	var prompt=""
	var cancelled=false
	var recorder: Callable
	func generate(value: String,_key: String="",_model: String="",_complete: bool=false,_schema: Dictionary={},_chars: int=4000,_tokens: int=2048,_temperature: float=0.8) -> void:
		prompt=value
		if recorder.is_valid():
			recorder.call(value)
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
	var mock=MockTransport.new()
	mock.recorder=func(value: String): outbound.append({"stage":ctrl.inflight.get("stage"),"prompt":value})
	return mock

func bind(id: String) -> bool:
	ctrl=CTRL.new()
	root.add_child(ctrl)
	if not expect(ctrl.bind_ai(id,Callable(),Callable(),factory).get("ok",false),"Explicit C5 binding failed"):
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

func claim(kind: String,evidence: String,proposal: Variant=null,refs: Array=[]) -> Dictionary:
	return {"kind":kind,"evidence":evidence,"proposal":proposal,"refs":refs}

func report(text: String,claims: Array) -> Dictionary:
	return {"candidate_hash":text.sha256_text(),"coverage":[{"start":0,"end":text.length()}],"claims":claims}

func review_twice(text: String,claims: Array) -> bool:
	if not await pump("critical"):
		return false
	var serial=ctrl.adapter.serial
	reply(report(text,claims))
	if not await pump("critical",serial):
		return false
	expect(ctrl.view["interaction_extension"]["reviewed_preview"].is_empty(),"First pass never confirms prose")
	reply(report(text,claims))
	return await pump("background")

func assess(original: String,source_id: Variant=null,evidence: String="",ruling: Dictionary={}) -> void:
	var sources: Array=[]
	if source_id!=null:
		sources.append({"event_id":source_id,"evidence":evidence})
	reply({"disposition":"supported","intent_evidence":original,"context":sources,"ruling":ruling,"reason":"Fixture semantic assessment; local policy and registered tools remain authoritative."})

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
	var local=base.gameplay_view(id)["interaction_extension"]["public_actors"]
	if not expect(local.size()==1,"Disclosed local NPC"):
		finish()
		return
	var mara=local[0]["actor_id"]
	var opening_event=int(local[0]["source_event_id"])
	var state=session.token(id)
	var npc_args={"generation_key":session.make_id(),"template_ids":["commoner"],"existing_actor_id":mara,"kind":"npc","name":"Mara","occupation":"Innkeeper","location_id":state["location_id"],"visibility":"player","sheet_visibility":"private","source_event_id":opening_event,"possessions":[{"definition_id":"dagger","quantity":2,"equipped_slot":null,"grip":null}],"coins":money(3),"attitude":null}
	var npc_req={"schema_version":"2","campaign_id":id,"actor_id":state["actor_id"],"expected_revision":state["revision"],"request_id":session.make_id(),"kind":"actor_generate","args":npc_args}
	if not expect(GENERATOR.new().generate(id,npc_req,true).get("ok",false),"Canonical disposable NPC upgrade"):
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
	await interrupted_consumption(id)
	await duplicate_response_cases(id,b["id"])
	await legacy_recovery_cases(id)
	await request_count_cases(id,shield)
	await authority_cases(id,shield)
	await persistent_npc_location(id)
	await geography_discovery_case(id)
	expect(players.load_record(master)==original and base.gameplay_view(b["id"])==sibling,"Master and sibling isolation")
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	finish()

func persistent_npc_location(id: String) -> void:
	var before=durable_snapshot(id)
	var calls=outbound.size()
	var input="I ask Mara about the nearby village and the people here."
	workspace.composer.text=input
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	reply({"kind":"conversation","args":{"text":input}})
	if not await pump("narrate"):
		return
	var location_id=session.token(id)["location_id"]
	var place_evidence="Mara describes Willowfen, a village."
	var npc_evidence="Tessa, the weaver, is here."
	var response=combined(place_evidence+" "+npc_evidence)
	response["geography"]["facts"]=[
		{"kind":"place","subject":{"id":null,"local_key":"willowfen"},"name":"Willowfen","place_kind":"village","parent":null,"region":null,"position":null,"precision":"provisional","uncertainty_miles":null,"elevation_feet":null,"terrain":null,"footprint":[],"population":null,"occupancy":"unknown","asset_id":null,"description":null,"visibility":"player","evidence":place_evidence},
		{"kind":"npc_description","subject":{"id":null,"local_key":"tessa"},"location":{"id":location_id,"local_key":null},"name":"Tessa","occupation":"weaver","visibility":"player","evidence":npc_evidence}
	]
	reply(response)
	if not await pump("idle"):
		return
	expect(outbound.size()-calls==2,"Persistent world turn exactly two provider requests")
	var after=durable_snapshot(id)
	expect(after["actor"]==before["actor"] and after["owned"]==before["owned"],"Descriptive world creation preserves player mechanics")
	var statements=[
		SQL.stmt("SELECT l.id,l.kind,w.source_event_id FROM locations l JOIN world_places w ON w.location_id=l.id WHERE l.name=?",["Willowfen"]),
		SQL.stmt("SELECT a.id,a.location_id,a.payload,w.source_event_id FROM actors a JOIN world_links w ON w.actor_id=a.id WHERE a.kind='npc' AND json_extract(a.payload,'$.name')=?",["Tessa"])
	]
	var persisted=SQL.run(base.path_for(id),statements,true)
	if not expect(persisted.get("ok",false),"Read campaign-local persisted world records"):
		return
	var results=persisted.get("results",[])
	if not expect(results.size()==2,"World record query results"):
		return
	var places: Array=results[0]
	var npcs: Array=results[1]
	if not expect(places.size()==1 and npcs.size()==1,"Exactly one persisted village and NPC"):
		return
	expect(not str(places[0]["id"]).is_empty() and places[0]["kind"]=="village" and places[0]["source_event_id"]!=null,"Village stable identity and committed source")
	expect(not str(npcs[0]["id"]).is_empty() and npcs[0]["location_id"]==location_id and npcs[0]["source_event_id"]!=null,"NPC stable identity and local campaign source")
	var npc=JSON.parse_string(npcs[0]["payload"])
	expect(npc is Dictionary and npc.get("id")==npcs[0]["id"] and npc.get("occupation")=="weaver","NPC persisted identity and occupation")
	expect(SQL.run(base.path_for(id),statements,true)==persisted,"World identities stable on independent SQLite read")

func geography_discovery_case(id: String) -> void:
	var rows=SQL.run(base.path_for(id),[SQL.stmt("SELECT id FROM locations WHERE name=?",["Willowfen"])],true)
	if not expect(rows.get("ok",false) and rows["results"][0].size()==1,"Existing named location"):
		return
	var village=rows["results"][0][0]["id"]
	var location=session.token(id)["location_id"]
	var before=durable_snapshot(id)
	var calls=outbound.size()
	var input="I ask about the road and look at the counter."
	workspace.composer.text=input
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	reply({"kind":"conversation","args":{"text":input}})
	if not await pump("narrate"):
		return
	var evidence="An abandoned carved amber tally lies on the counter, free to take."
	var relation="Willowfen lies north of Oak Inn."
	var road="The Willow Road connects Oak Inn and Willowfen."
	var response=combined(relation+" "+road+" "+evidence)
	var from={"id":location,"local_key":null}
	var to={"id":village,"local_key":null}
	response["geography"]["facts"]=[
		{"kind":"relationship","from":from,"to":to,"relation_kind":"relative","direction":"north","distance_miles":null,"precision":"provisional","visibility":"player","evidence":relation},
		{"kind":"route","subject":{"id":null,"local_key":"willow-road"},"from":from,"to":to,"name":"Willow Road","route_kind":"road","precision":"provisional","distance_miles":null,"points":[],"visibility":"player","evidence":road}
	]
	var definition={"name":"Carved amber tally","category":"gear","description":"A carved amber tally.","unit_weight_lb":0.1,"cost_cp":1,"properties":[],"charges_max":null,"attunement_required":false}
	response["discoveries"]=[
		{"kind":"define_custom","evidence":evidence,"args":{"definition":definition,"official_equivalent_id":null}},
		{"kind":"loot_discover","evidence":evidence,"args":{"location_id":location,"name":"Counter discovery","items":[{"definition_id":"@0","quantity":1,"charges":null,"condition":"intact","attunement":"not_required"}],"coins":money(0)}}
	]
	reply(response)
	if not await pump("idle"):
		return
	expect(outbound.size()-calls==2,"Geography and discovery exactly two provider calls")
	var after=durable_snapshot(id)
	expect(after["actor"]==before["actor"] and after["owned"]==before["owned"],"Discovery does not grant resources")
	var persisted=SQL.run(base.path_for(id),[
		SQL.stmt("SELECT l.id,l.x,l.y,d.status FROM locations l JOIN world_discovery d ON d.location_id=l.id WHERE l.name=?",["Willowfen"]),
		SQL.stmt("SELECT from_id,to_id,direction FROM geographic_relationships WHERE from_id=? AND to_id=?",[location,village]),
		SQL.stmt("SELECT r.from_id,r.to_id,d.status FROM world_routes r JOIN world_discovery d ON d.route_id=r.id WHERE r.name=?",["Willow Road"]),
		SQL.stmt("SELECT request_id,request_payload,result_payload FROM gameplay_requests WHERE kind IN ('define_custom','loot_discover') AND status='committed' ORDER BY settled_revision")
	],true)
	if not expect(persisted.get("ok",false),"Persisted geography and discovery query"):
		return
	var result=persisted["results"]
	if not expect(result[0].size()==1 and result[1].size()==1 and result[2].size()==1 and result[3].size()==2,"Exact persisted world and discovery rows"):
		return
	expect(result[0][0]["id"]==village and result[0][0]["x"]==null and result[0][0]["y"]==null and result[0][0]["status"]=="reported","Stable reported village with unknown coordinates")
	expect(result[1][0]["direction"]=="north" and result[2][0]["from_id"]==location and result[2][0]["to_id"]==village and result[2][0]["status"]=="reported","Persisted relationship and untraveled route")
	var defined=JSON.parse_string(result[3][0]["result_payload"])
	var request=JSON.parse_string(result[3][1]["request_payload"])
	var settlement=session.settlement(id,result[3][1]["request_id"])
	expect(request["args"]["items"][0]["definition_id"]==defined["definition_id"] and request["args"]["location_id"]==location,"Proposal-local definition resolves to persistent ID at current location")
	expect(settlement.get("request")==request and request["campaign_id"]==id and request["request_id"]==result[3][1]["request_id"],"Exact durable transformed request")
	var source=session.source(session.token(id),request["args"]["source_event_id"])
	expect(source.get("kind")=="narration" and str(source.get("data",{}).get("text","")).contains(evidence),"Discovery binds committed narrative evidence")
	var loot=ctrl.view["interaction_extension"]["loot_containers"]
	expect(loot.size()==1 and loot[0]["items"][0]["name"]=="Carved amber tally","Discovered item remains in local loot")

func wait_frames() -> void:
	for i in range(12):
		await process_frame

func combined(text: String) -> Dictionary:
	return {"text":text,"geography":geography(),"story":[],"discoveries":[]}

func legacy_recovery_cases(id: String) -> void:
	for stage in ["critical","background","adjudicate"]:
		var text="I ask Mara about the old bridge."
		workspace.composer.text=text
		workspace.submit_chat()
		if not await pump("interpret"):
			return
		reply({"kind":"conversation","args":{"text":text}})
		if not await pump("narrate"):
			return
		var job=ctrl.active().duplicate(true)
		var request=job["tool"].duplicate(true)
		var rid=request["request_id"]
		var settled=session.settlement(id,rid)
		var before=durable_snapshot(id)
		var calls=outbound.size()
		job["stage"]=stage
		job["attempt"]={}
		job["candidate"]={}
		job["critical_verified"]=false
		if not expect(ctrl.update_active(job),"Persist legacy "+stage+" fixture"):
			return
		ctrl.close_session()
		workspace.queue_free()
		ctrl.queue_free()
		await process_frame
		if not bind(id):
			return
		if stage=="adjudicate":
			await wait_frames()
			expect(outbound.size()==calls,"Legacy adjudication never dispatches provider")
			expect(session.settlement(id,rid)==settled,"Legacy adjudication preserves settlement")
			expect(session.token(id)["revision"]==before["revision"],"Legacy adjudication does not replay mechanics")
			ctrl.retry()
		if not await pump("narrate"):
			return
		expect(ctrl.active()["tool"]==request,"Legacy "+stage+" exact durable request")
		expect(session.settlement(id,rid)==settled and session.token(id)["revision"]==before["revision"],"Legacy "+stage+" no mechanical replay")
		expect(session.token(id)["actor"]==before["actor"],"Legacy "+stage+" unchanged actor")
		expect(outbound.size()-calls==1 and outbound.back()["stage"]=="narrate","Legacy "+stage+" Storyteller only")
		var identity=ctrl.inflight.duplicate(true)
		var response=combined(TALK)
		reply(response)
		if not await pump("idle"):
			return
		expect(session.settlement(id,rid)==settled,"Legacy "+stage+" original settlement intact")
		await rejected_response(id,identity,response,false,"Legacy "+stage+" duplicate narration")

func authority_cases(id: String,shield: String) -> void:
	var text="I ask Mara what she knows."
	workspace.composer.text=text
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	reply({"kind":"conversation","args":{"text":text}})
	if not await pump("narrate"):
		return
	var before=durable_snapshot(id)
	var calls=outbound.size()
	var identity=ctrl.inflight.duplicate(true)
	var malicious=combined("You gain 100 gold, ten daggers, full HP and temporary HP, a spell slot, a level and experience. Your shield vanishes and all conditions disappear.")
	malicious["mechanical_patch"]={"hp_current":99,"hp_temp":99,"coins":{"gp":100},"inventory":[{"definition_id":"dagger","quantity":10}],"equipment":{},"spellcasting":{"slots":{"1":{"spent":0}}},"experience":10000,"level":5,"conditions":[]}
	reply(malicious)
	await wait_frames()
	expect(session.token(id)["actor"]==before["actor"] and session.token(id)["revision"]==before["revision"],"Unauthorized structured mechanical patch rejected")
	expect(REG.new().noncombat.read_owned(session.token(id),ctrl.actor_id)==before["owned"],"Unauthorized inventory and ownership unchanged")
	expect(outbound.size()==calls,"Unauthorized patch does not trigger automatic review")
	if not ctrl.active().is_empty():
		ctrl.retry()
		if not await pump("narrate"):
			return
		reply(combined("Mara looks toward the hearth."))
		if not await pump("idle"):
			return
	expect(session.token(id)["actor"]==before["actor"],"Narration recovery leaves mechanical actor unchanged")
	# A valid envelope with unsupported prose claims must not mutate mechanics.
	workspace.composer.text=text
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	reply({"kind":"conversation","args":{"text":text}})
	if not await pump("narrate"):
		return
	before=durable_snapshot(id)
	calls=outbound.size()
	reply(combined(malicious["text"]))
	if not await pump("idle"):
		return
	expect(session.token(id)["actor"]==before["actor"],"Prose claims cannot alter HP, currency, equipment, slots, level or conditions")
	expect(REG.new().noncombat.read_owned(session.token(id),ctrl.actor_id)==before["owned"],"Prose claims cannot grant inventory")
	expect(outbound.size()==calls,"Combined narration has no extra review")
	# Actual workspace intent handler, not a refresh or direct registry call.
	var equipped_before=workspace.equipped(shield)
	var revision=session.token(id)["revision"]
	calls=outbound.size()
	var result=workspace.request_intent("unequip",{"instance_id":shield,"slot":"shield"}) if equipped_before else workspace.request_intent("equip",{"instance_id":shield,"slot":"shield","grip":"one_handed"})
	expect(result.get("ok",false),"Workspace equipment intent accepted")
	if not await pump("idle"):
		return
	expect(outbound.size()==calls,"Deterministic equipment mutation zero transport calls")
	expect(workspace.equipped(shield)!=equipped_before,"Actual equipment assignment changed")
	expect(session.token(id)["revision"]>revision,"Equipment mutation advances revision")
	var owned=REG.new().noncombat.read_owned(session.token(id),ctrl.actor_id)
	expect(REG.new().noncombat.aggregate(owned).get("shield",{}).get("quantity",0)==1,"Shield ownership conserved")
	var persisted=session.token(id)["actor"].duplicate(true)
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	await process_frame
	if not bind(id):
		return
	expect(session.token(id)["actor"]==persisted and workspace.equipped(shield)!=equipped_before,"Equipment persists after reopen")
	expect(outbound.size()==calls,"Equipment reopen no provider calls")

func durable_snapshot(id: String) -> Dictionary:
	var state=session.token(id)
	var owned=REG.new().noncombat.read_owned(state,state["actor_id"])
	return {"revision":state["revision"],"actor":state["actor"],"owned":owned,"view":base.gameplay_view(id)}

func rejected_response(id: String,identity: Dictionary,value: Dictionary,interpret: bool,label: String) -> void:
	var before=durable_snapshot(id)
	var calls=outbound.size()
	var result=ctrl.receive_interpretation(identity,value,[]) if interpret else ctrl.receive(identity,value)
	expect(not result.get("ok",false),label+" rejected")
	await wait_frames()
	expect(durable_snapshot(id)==before,label+" authoritative state and public history unchanged")
	expect(outbound.size()==calls,label+" no additional transport calls")

func duplicate_response_cases(id: String,sibling_id: String) -> void:
	var text="I ask Mara about the bridge."
	workspace.composer.text=text
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	var identity=ctrl.inflight.duplicate(true)
	var action={"kind":"conversation","args":{"text":text}}
	for field in ["request_id","campaign_id","attempt_id","revision"]:
		var wrong=identity.duplicate(true)
		wrong[field]=int(identity[field])-1 if field=="revision" else (sibling_id if field=="campaign_id" else session.make_id())
		await rejected_response(id,wrong,action,true,"Incorrect interpretation "+field)
	reply(action)
	if not await pump("narrate"):
		return
	await rejected_response(id,identity,action,true,"Duplicate settled interpretation")
	var narration_id=ctrl.inflight.duplicate(true)
	var narration=combined(TALK)
	for field in ["request_id","campaign_id","attempt_id","revision"]:
		var wrong=narration_id.duplicate(true)
		wrong[field]=int(narration_id[field])-1 if field=="revision" else (sibling_id if field=="campaign_id" else session.make_id())
		await rejected_response(id,wrong,narration,false,"Incorrect narration "+field)
	reply(narration)
	if not await pump("idle"):
		return
	await rejected_response(id,narration_id,narration,false,"Duplicate persisted narration")
	await rejected_response(id,identity,action,true,"Late settled interpretation")

func ration_quantity(id: String) -> int:
	var owned=REG.new().noncombat.read_owned(session.token(id),ctrl.actor_id)
	if not expect(owned.get("ok",false),"Read authoritative owned inventory"):
		return -1
	return int(REG.new().noncombat.aggregate(owned).get("rations-1-day",{}).get("quantity",0))

func interrupted_consumption(id: String) -> void:
	var instance=""
	for item in ctrl.view["interaction_extension"]["inventory_instances"]:
		if item["definition_id"]=="rations-1-day":
			instance=item["instance_id"]
			break
	var initial=ration_quantity(id)
	if not expect(initial>0 and not instance.is_empty(),"Initial ration available"):
		return
	var initial_revision=session.token(id)["revision"]
	var start=outbound.size()
	var text="I eat one of my daily rations."
	workspace.composer.text=text
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	reply({"kind":"item_use","args":{"instance_id":instance,"quantity":1,"target_id":ctrl.actor_id},"assessment":{"disposition":"supported","intent_evidence":text,"context":[],"ruling":{},"reason":"Explicit self consumption of owned ration."}})
	if not await pump("narrate"):
		return
	var request=ctrl.active()["tool"].duplicate(true)
	var rid=request["request_id"]
	var settlement=session.settlement(id,rid)
	var committed_revision=session.token(id)["revision"]
	if not expect(settlement.get("status")=="committed" and settlement.get("request")==request and ration_quantity(id)==initial-1 and committed_revision>initial_revision,"Ration committed exactly once before narration"):
		return
	var old=ctrl.inflight.duplicate(true)
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	await process_frame
	if not bind(id) or not await pump("narrate"):
		return
	expect(ctrl.active()["tool"]==request and session.settlement(id,rid)==settlement,"Recovery retains exact mechanical settlement")
	expect(ration_quantity(id)==initial-1 and session.token(id)["revision"]==committed_revision,"Recovery does not consume again or advance mechanical revision")
	expect(not ctrl.receive(old,{}).get("ok",false),"Interrupted transport identity rejected")
	reply(combined("You finish your ration."))
	if not await pump("idle"):
		return
	expect(ration_quantity(id)==initial-1,"Final inventory decreased exactly once")
	expect(session.settlement(id,rid)==settlement,"Original mechanical settlement unchanged after narration")
	expect(RECON.new().standalone_event(id,rid).get("found",false),"Recovered narration persisted")
	expect(outbound.size()-start==3,"One interpretation and two narration attempts across interruption")

func request_count_cases(id: String,shield: String) -> void:
	var start=outbound.size()
	workspace.composer.text=TALK
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	reply({"kind":"conversation","args":{"text":TALK}})
	if not await pump("narrate"):
		return
	reply(combined(TALK))
	if not await pump("idle"):
		return
	expect(outbound.size()-start==2,"Conversation exactly two actual generate calls")
	start=outbound.size()
	workspace.composer.text=INPUT
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	var rid=ctrl.inflight["request_id"]
	var equip={"kind":"equip","args":{"instance_id":shield,"slot":"shield","grip":"one_handed"},"assessment":{"disposition":"supported","intent_evidence":INPUT,"context":[],"ruling":{},"reason":"Owned shield and explicit equip intent."}}
	reply(equip)
	if not await pump("narrate"):
		return
	var settled=session.settlement(id,rid)
	expect(settled.get("status")=="committed" and workspace.actor["combat"]["armor_class"]==14,"Equip committed before narration")
	reply(combined("The shield settles against your arm."))
	if not await pump("idle"):
		return
	expect(outbound.size()-start==2 and session.settlement(id,rid)==settled,"Equip two calls and exact unchanged settlement")
	start=outbound.size()
	workspace.composer.text="Equip a shield I do not own."
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	var before=session.token(id)
	var invalid=equip.duplicate(true)
	invalid["args"]["instance_id"]=session.make_id()
	invalid["assessment"]["intent_evidence"]="Equip a shield I do not own."
	reply(invalid)
	await wait_frames()
	expect(outbound.size()-start==1 and session.token(id)["actor"]==before["actor"],"Rejected equip one call and unchanged actor")
	# Clear only the rejected pending request using the production cancellation path.
	if not ctrl.active().is_empty():
		ctrl.cancel()
	await wait_frames()
	start=outbound.size()
	workspace.composer.text="Malformed response fixture"
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	reply("not JSON")
	await wait_frames()
	expect(outbound.size()-start==1,"Malformed response never automatically resubmitted")
	if not ctrl.active().is_empty():
		ctrl.cancel()
	await wait_frames()
	start=outbound.size()
	ctrl.refresh()
	await wait_frames()
	expect(outbound.size()==start,"Deterministic workspace refresh zero provider calls")

# Historical safety scenarios retained for migration in 3b.3b/c.
# This function is not executed: its old provider protocol is obsolete.
func legacy_scenarios(id: String,shield: String,mara: String,master: String,original: Dictionary,b: Dictionary,sibling: Dictionary,players) -> void:
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
	if not await pump("adjudicate"):
		finish()
		return
	assess(INPUT)
	if not await pump("narrate"):
		finish()
		return
	expect(workspace.actor["combat"]["armor_class"]==14 and session.settlement(id,rid).get("status")=="committed","Real equip and committed GUI refresh")
	expect(ctrl.adapter.transport.prompt.contains(NARRATOR.load_prompt()) and ctrl.adapter.transport.prompt.contains(INPUT),"Existing editable prompt and exact original input")
	reply("You gain ten gold.")
	if not await pump("critical"):
		finish()
		return
	var omitted=ctrl.adapter.serial
	reply(report("You gain ten gold.",[claim("description","You gain ten gold.")]))
	if not await pump("critical",omitted):
		finish()
		return
	reply(report("You gain ten gold.",[claim("contradiction","You gain ten gold.")]))
	if not await pump("narrate"):
		finish()
		return
	expect(workspace.actor["coins"]["gp"]==5,"Invented grant blocked before display")
	reply(PROSE)
	if not await review_twice(PROSE,[claim("description","The shield settles against your arm."),claim("dialogue","That suits you",null,[mara]),claim("description","An abandoned carved amber tally lies on the counter, free to take."),claim("offer","Mara offers two gold pieces for your help.",null,[mara])]):
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
	var discovered=[{"kind":"define_custom","evidence":"An abandoned carved amber tally lies on the counter, free to take.","args":{"definition":definition,"official_equivalent_id":null}},{"kind":"loot_discover","evidence":"An abandoned carved amber tally lies on the counter, free to take.","args":{"location_id":session.token(id)["location_id"],"name":"Counter discovery","items":[{"definition_id":"@0","quantity":1,"charges":null,"condition":"intact","attunement":"not_required"}],"coins":money(0)}}]
	reply({"geography":geography(),"story":[],"discoveries":discovered})
	if not await pump("adjudicate"):
		finish()
		return
	var source_id=ctrl.active()["narration_event_id"]
	var pass_serial=ctrl.adapter.serial
	# Inject a valid-looking committed row under the deferred request ID but
	# with different arguments. Only this disposable DB is modified.
	var deferred_req=ctrl.active()["story_request"].duplicate(true)
	var other_req=deferred_req.duplicate(true)
	other_req["args"]["definition"]["name"]="Different fixture item"
	var forged=SQL.run(base.path_for(id),[SQL.stmt("INSERT INTO gameplay_requests(request_id,actor_id,kind,expected_revision,status,request_payload,result_payload,settled_revision,event_id) VALUES(?,?,?,?,'committed',?,?,?,?)",[deferred_req["request_id"],deferred_req["actor_id"],deferred_req["kind"],deferred_req["expected_revision"],JSON.stringify(other_req),JSON.stringify({"definition_id":"wrong-fixture-definition"}),deferred_req["expected_revision"],source_id])])
	if not expect(forged.get("ok",false),"Deferred mismatch fixture"):
		finish()
		return
	assess("An abandoned carved amber tally lies on the counter, free to take.",source_id,"An abandoned carved amber tally lies on the counter, free to take.")
	for frame in range(60):
		await process_frame
		if ctrl.active().get("stage")=="retry":
			break
	if not expect(ctrl.active().get("stage")=="retry" and ctrl.active().get("discovery_index")==0 and ctrl.active().get("story_request")==deferred_req,"Mismatched deferred settlement advanced discovery"):
		finish()
		return
	if not expect(SQL.run(base.path_for(id),[SQL.stmt("DELETE FROM gameplay_requests WHERE request_id=?",[deferred_req["request_id"]])]).get("ok",false) and ctrl.retry().get("ok",false),"Restore disposable fixture and retry"):
		finish()
		return
	if not await pump("adjudicate",pass_serial):
		finish()
		return
	assess("An abandoned carved amber tally lies on the counter, free to take.",source_id,"An abandoned carved amber tally lies on the counter, free to take.")
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
	if not await review_twice(TALK,[claim("dialogue","The bridge? A mason named Orrin built it."),claim("npc_action","She stares into the hearth, as though remembering an old argument.",null,[mara])]):
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
	if not await review_twice(TALK,[claim("dialogue","The bridge? A mason named Orrin built it."),claim("npc_action","She stares into the hearth, as though remembering an old argument.",null,[mara])]):
		finish()
		return
	reply({"geography":geography(),"story":[],"discoveries":[]})
	if not await pump("idle"):
		finish()
		return
	expect(session.settlement(id,sub_id).get("status")=="committed","Dependent action committed once")
	# Real DM-originated accepted transfer. Prior offer had no inventory effect.
	expect(workspace.actor["coins"]["gp"]==5,"Offer/discovery never transferred currency")
	workspace.composer.text=ACCEPT
	workspace.submit_chat()
	if not await pump("interpret"):
		finish()
		return
	var transfer_root=ctrl.inflight["request_id"]
	reply({"kind":"conversation","args":{"text":ACCEPT}})
	if not await pump("narrate"):
		finish()
		return
	reply(PROPOSED)
	if not await pump("critical"):
		finish()
		return
	var proposal={"kind":"currency_transfer","args":{"from_actor_id":mara,"to_actor_id":ctrl.actor_id,"coins":money(2)},"consent":ACCEPT}
	var required=[claim("required_effect",PROPOSED,proposal,[mara,ctrl.actor_id])]
	var first_serial=ctrl.adapter.serial
	reply(report(PROPOSED,required))
	if not await pump("critical",first_serial):
		finish()
		return
	reply(report(PROPOSED,required))
	if not await pump("narrate"):
		finish()
		return
	expect(workspace.actor["coins"]["gp"]==5 and ctrl.view["interaction_extension"]["reviewed_preview"].is_empty(),"New completed claim hidden before settlement")
	reply(PENDING)
	if not await review_twice(PENDING,[claim("offer","Mara holds out two gold pieces.",null,[mara]),claim("dialogue","For your trouble",null,[mara])]):
		finish()
		return
	reply({"geography":geography(),"story":[],"discoveries":[]})
	if not await pump("adjudicate"):
		finish()
		return
	var continuation_id=ctrl.active()["consequence_request"]["request_id"]
	var pending_event=ctrl.active()["narration_event_id"]
	var old_review=ctrl.inflight.duplicate(true)
	expect(session.settlement(id,transfer_root).get("status")=="committed" and workspace.actor["coins"]["gp"]==5,"Original turn settled before transfer")
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	await process_frame
	if not bind(id) or not await pump("adjudicate"):
		finish()
		return
	expect(ctrl.active()["consequence_request"]["request_id"]==continuation_id and not ctrl.receive(old_review,{}).get("ok",false),"Continuation ID and stale review on reopen")
	assess(ACCEPT,pending_event,"Mara holds out two gold pieces.")
	if not await pump("narrate"):
		finish()
		return
	expect(workspace.actor["coins"]["gp"]==7 and session.settlement(id,continuation_id).get("status")=="committed","Actual C3 transfer settles once")
	var npc_pack=REG.new().noncombat.read_owned(session.token(id),mara)
	expect(npc_pack.get("ok",false) and npc_pack["actor"]["coins"]["gp"]==1,"Sender debited exact quantity")
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	await process_frame
	if not bind(id) or not await pump("narrate"):
		finish()
		return
	expect(workspace.actor["coins"]["gp"]==7 and ctrl.active()["tool"]["request_id"]==continuation_id,"Committed transfer not replayed on reopen")
	reply(TRANSFERRED)
	if not await review_twice(TRANSFERRED,[claim("receipt_claim","two gold pieces",{"path":["result","coins","gp"],"value":2},[mara,ctrl.actor_id]),claim("dialogue","A debt paid",null,[mara])]):
		finish()
		return
	reply({"geography":geography(),"story":[],"discoveries":[]})
	if not await pump("idle"):
		finish()
		return
	expect(RECON.new().standalone_event(id,continuation_id).get("found",false),"Verified continuation narration persisted")
	workspace.composer.text=DECLINE
	workspace.submit_chat()
	if not await pump("interpret"):
		finish()
		return
	reply({"kind":"conversation","args":{"text":DECLINE}})
	if not await pump("narrate"):
		finish()
		return
	reply(DECLINED)
	if not await review_twice(DECLINED,[claim("dialogue","Fair enough",null,[mara]),claim("npc_action","She puts her purse away.",null,[mara])]):
		finish()
		return
	reply({"geography":geography(),"story":[],"discoveries":[]})
	if not await pump("idle"):
		finish()
		return
	expect(workspace.actor["coins"]["gp"]==7,"Decline produces no extra transfer")
	# Definition-only reference to an actual NPC possession, never guessed ID.
	workspace.composer.text=ACCEPT_ITEM
	workspace.submit_chat()
	if not await pump("interpret"):
		finish()
		return
	reply({"kind":"conversation","args":{"text":ACCEPT_ITEM}})
	if not await pump("narrate"):
		finish()
		return
	reply(ITEM_PROPOSED)
	if not await pump("critical"):
		finish()
		return
	var item_proposal={"kind":"item_transfer","args":{"from_actor_id":mara,"to_actor_id":ctrl.actor_id,"definition_id":"dagger","quantity":1},"consent":ACCEPT_ITEM}
	var item_claims=[claim("required_effect",ITEM_PROPOSED,item_proposal,[mara,ctrl.actor_id])]
	var item_serial=ctrl.adapter.serial
	reply(report(ITEM_PROPOSED,item_claims))
	if not await pump("critical",item_serial):
		finish()
		return
	reply(report(ITEM_PROPOSED,item_claims))
	if not await pump("narrate"):
		finish()
		return
	reply(ITEM_PENDING)
	if not await review_twice(ITEM_PENDING,[claim("offer",ITEM_PENDING,null,[mara])]):
		finish()
		return
	reply({"geography":geography(),"story":[],"discoveries":[]})
	if not await pump("adjudicate"):
		finish()
		return
	var item_req=ctrl.active()["consequence_request"]
	expect(item_req["args"].has("instance_id") and not item_req["args"].has("definition_id"),"Locally resolved actual NPC instance")
	assess(ACCEPT_ITEM,ctrl.active()["narration_event_id"],ITEM_PENDING)
	if not await pump("narrate"):
		finish()
		return
	var owned=REG.new().noncombat.read_owned(session.token(id),mara)
	var player_pack=REG.new().noncombat.read_owned(session.token(id),ctrl.actor_id)
	var registry=REG.new()
	expect(owned.get("ok",false) and player_pack.get("ok",false) and registry.noncombat.aggregate(owned)["dagger"]["quantity"]==1 and registry.noncombat.aggregate(player_pack)["dagger"]["quantity"]==3,"Actual item quantity conserved")
	reply(ITEM_SETTLED)
	if not await review_twice(ITEM_SETTLED,[claim("receipt_claim","Mara passes the dagger across.",{"path":["result","quantity"],"value":1},[mara,ctrl.actor_id]),claim("dialogue","Keep it sharp",null,[mara])]):
		finish()
		return
	reply({"geography":geography(),"story":[],"discoveries":[]})
	if not await pump("idle"):
		finish()
		return
	expect(session.settlement(id,item_req["request_id"]).get("status")=="committed","Exact item transfer settlement")
	expect(players.load_record(master)==original and base.gameplay_view(b["id"])==sibling,"Master and sibling isolation")
	expect(not ctrl.adapter.metrics.is_empty(),"Mock call timing instrumentation")
	expect(not ctrl.timing_samples.is_empty(),"Controller context timing instrumentation")
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	finish()
