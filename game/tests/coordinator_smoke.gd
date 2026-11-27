extends SceneTree
## Disposable Godot/SQL + mocked Gemini integration. Never requests the network.
const BASE = preload("res://campaigns/campaign_store.gd")
const PLAYER = preload("res://players/character_store.gd")
const SQL = preload("res://systems/sqlite.gd")
const TURN = preload("res://turns/turn_store.gd")
const RAW = preload("res://turns/raw_mechanics.gd")
const CAT = preload("res://rules/catalog.gd")
const COORD = preload("res://turns/turn_coordinator.gd")
const PACK = preload("res://turns/agent_packets.gd")
const NARRATOR = preload("res://campaigns/narrator_prompt.gd")
const MATURITY = preload("res://campaigns/maturity_profiles.gd")
const WORLD = preload("res://world/world_store.gd")
const MIGRATION = preload("res://world/world_migration.gd")
const RECONCILER = preload("res://world/geography_reconciler.gd")

class MockProvider:
	extends Node
	signal completed(ok: bool, message: String)
	var captured_prompt = ""
	var captured_schema: Dictionary = {}
	var canceled = false
	func generate(prompt: String, _key: String, _model: String, _complete: bool, schema: Dictionary, _limit: int, _tokens: int, _temperature: float) -> void:
		captured_prompt=prompt
		captured_schema=schema.duplicate(true)
	func cancel_generation() -> void:
		canceled=true

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func finish() -> void:
	for message in failures:
		push_error(message)
	print("Coordinator smoke failures: ",failures.size())
	quit(0 if failures.is_empty() else 1)

func controller() -> Node:
	var instance = COORD.new()
	instance.provider_factory=func(): return MockProvider.new()
	root.add_child(instance)
	return instance

func reply(ctrl, fields: Dictionary, ok: bool = true) -> void:
	var packet: Dictionary = ctrl.attempt.get("identity",{}).duplicate(true)
	packet.merge(fields)
	if is_instance_valid(ctrl.transport):
		ctrl.transport.completed.emit(ok,JSON.stringify(packet))

func proposal() -> Dictionary:
	var refs = RAW.refs_for("ability_check","str")
	return {"status":"proposed","actions":[{"handler_id":"ability_check","target_refs":[],"reference_refs":refs,"intent_text":"Check the strength of the beam.","arguments":{"ability":"str","skill":null}}],"clarification":null,"rule_refs":refs}

func entity_ref(id: String) -> Dictionary:
	return {"id":id,"local_key":null}

func local_ref(key: String) -> Dictionary:
	return {"id":null,"local_key":key}

func place_fact(key: String,name: String,kind: String,evidence: String,description: Variant = null) -> Dictionary:
	return {"kind":"place","subject":local_ref(key),"name":name,"place_kind":kind,"parent":null,"region":null,"position":null,"precision":"provisional","uncertainty_miles":null,"elevation_feet":null,"terrain":null,"footprint":[],"population":null,"occupancy":"unknown","asset_id":null,"description":description,"visibility":"player","evidence":evidence}

func local_approval(ctrl,ruling: Dictionary) -> Dictionary:
	var request = ctrl.approval_request()
	return {"campaign_id":request["campaign_id"],"actor_id":request["actor_id"],"turn_id":request["turn_id"],"expected_revision":request["expected_revision"],"action":request["action"],"ruling":ruling}

func run() -> void:
	var expected = OS.get_environment("INFINITY_TEST_USER_ROOT").replace("\\","/").trim_suffix("/")
	var actual = ProjectSettings.globalize_path("user://").replace("\\","/").trim_suffix("/")
	if expected.is_empty() or expected!=actual or FileAccess.file_exists("user://players.db") or FileAccess.file_exists("user://settings.cfg") or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(BASE.ROOT)):
		push_error("Coordinator smoke requires an explicitly authorized empty disposable user directory.")
		quit(2)
		return
	var players = PLAYER.new()
	var master_id = players.make_id()
	var err = players.save_record({"id":master_id,"name":"Fixture adventurer","status":"ready","ruleset":CAT.RULESET,"catalog_revision":CAT.REVISION,"level":1,"ability_scores":{"str":10,"dex":14,"con":12,"int":10,"wis":12,"cha":10},"ability_modifiers":{"str":0,"dex":2,"con":1,"int":0,"wis":1,"cha":0},"proficiency_bonus":2,"proficiency_ids":[],"expertise_ids":[],"skills":{},"saving_throws":{"str":0,"dex":2,"con":1,"int":0,"wis":1,"cha":0},"equipment":{"armor_penalty":false},"inventory":[{"item_id":"dagger","quantity":2,"equipped":true}],"combat":{"hp_current":7,"hp_max":8,"conditions":[],"active_effects":[],"exhaustion":0}})
	expect(err.is_empty(),"Master fixture save failed")
	var base = BASE.new()
	var a = base.create_campaign("First campaign",master_id,"tavern","family")
	var b = base.create_campaign("Sibling campaign",master_id,"road","standard")
	if a.is_empty() or b.is_empty():
		expect(false,"Campaign fixture creation failed")
		finish()
		return
	var original_master = players.load_record(master_id)
	var sibling = base.gameplay_view(b["id"])
	var actor = base.actor_record(a["id"])
	var opening = base.prepare_opening(a["id"])
	expect(not opening.is_empty(),"Opening preparation failed")
	if not opening.is_empty():
		expect(base.commit_opening(a["id"],opening["previous"],JSON.stringify({"start_id":"tavern","location_name":"Oakhaven","atmosphere":"A busy inn.","npcs":[{"name":"Mara","occupation":"Innkeeper","attitude":0}],"world_facts":["The hearth is river stone."],"thumbnail_id":"tavern"})).is_empty(),"Opening fixture failed")
	expect(NARRATOR.save_prompt("Custom storyteller fixture.").is_empty() and MATURITY.save_guidance("family","Family guidance fixture.").is_empty(),"Settings fixture failed")
	var ctrl = controller()
	var bound = ctrl.bind_campaign(a["id"])
	if not bound.get("ok",false):
		expect(false,"Controller bind/migration failed: "+str(bound))
		finish()
		return
	var store = TURN.new()
	var before = store.snapshot(a["id"])
	var secret = players.make_id()
	var bridge = players.make_id()
	var fixtures = [
		SQL.stmt("INSERT INTO locations(id,kind,name,payload) VALUES(?,'cave','Secret Needle Cave','{}')",[secret]),
		SQL.stmt("INSERT INTO world_places(location_id,description) VALUES(?,'Private fixture')",[secret]),
		SQL.stmt("INSERT INTO world_discovery(id,location_id,status,visibility) VALUES(?,?,'unknown','private')",[players.make_id(),secret]),
		SQL.stmt("INSERT INTO geographic_relationships(id,from_id,to_id,kind,precision,visibility,source_event_id) VALUES(?,?,?,'relative','unknown','private',1)",[players.make_id(),a["location_id"],secret]),
		SQL.stmt("INSERT INTO locations(id,kind,name,payload) VALUES(?,'bridge','Old Stone Bridge','{}')",[bridge]),
		SQL.stmt("INSERT INTO world_places(location_id,public_description) VALUES(?,'A bridge north of Oakhaven')",[bridge]),
		SQL.stmt("INSERT INTO world_discovery(id,location_id,status,visibility,first_event_id) VALUES(?,?,'reported','player',1)",[players.make_id(),bridge]),
		SQL.stmt("INSERT INTO geographic_relationships(id,from_id,to_id,kind,direction,distance_miles,precision,visibility,source_event_id) VALUES(?,?,?,'relative','north',3,'provisional','player',1)",[players.make_id(),a["location_id"],bridge])
	]
	expect(SQL.run(base.path_for(a["id"]),fixtures).get("ok",false),"World context fixture failed")
	var quest_id = players.make_id()
	var private_quest_id = players.make_id()
	var quest_fixture = SQL.run(base.path_for(a["id"]),[
		SQL.stmt("INSERT INTO events(turn,game_time,kind,payload) VALUES(0,'Unstarted','narration',?)",[JSON.stringify({"location_id":a["location_id"],"b4_reconciled":true,"text":"The Missing Ledger is an established local quest."})]),
		SQL.stmt("INSERT INTO quests(id,status,payload) VALUES(?,'active',?)",[quest_id,JSON.stringify({"title":"The Missing Ledger","public":true,"public_description":"an established local quest"})]),
		SQL.stmt("INSERT INTO world_links(id,location_id,quest_id,source_event_id) VALUES(?,?,?,(SELECT max(id) FROM events))",[players.make_id(),a["location_id"],quest_id]),
		SQL.stmt("INSERT INTO quests(id,status,payload) VALUES(?,'active',?)",[private_quest_id,JSON.stringify({"title":"Undisclosed ledger","public":false})]),
		SQL.stmt("INSERT INTO world_links(id,location_id,quest_id,source_event_id) VALUES(?,?,?,1)",[players.make_id(),a["location_id"],private_quest_id])
	])
	expect(quest_fixture.get("ok",false),"Quest provenance fixture failed")
	var visible = WORLD.new().public_context(a["id"],[a["location_id"],bridge,secret])
	expect(visible.get("ok",false) and visible.get("local_npcs",[]).size()==1 and visible["local_npcs"][0]["name"]=="Mara","Migrated opening NPC provenance missing")
	expect(visible.get("local_quests",[]).size()==1 and visible["local_quests"][0]["id"]==quest_id,"Public quest missing or private quest leaked")
	expect(ctrl.submit("Check the beam's strength.").get("ok",false) and ctrl.phase=="rules_pending","Rules request failed")
	if ctrl.phase!="rules_pending":
		finish()
		return
	var first = ctrl.transport
	var first_id = ctrl.turn_id
	var first_request = ctrl.attempt["identity"]["request_id"]
	expect(first.captured_prompt.contains("Old Stone Bridge") and not first.captured_prompt.contains("Secret Needle Cave") and not first.captured_prompt.contains(secret) and not first.captured_prompt.contains("Sibling campaign"),"Context missing canon or leaked private/sibling")
	expect(not first.captured_prompt.contains("actor_payload") and not first.captured_prompt.contains("master_character_id") and not first.captured_prompt.contains("Undisclosed ledger"),"Raw/private local token leaked")
	expect(first.captured_prompt.contains("Mara") and first.captured_prompt.contains("The Missing Ledger"),"Established NPC or quest not supplied")
	reply(ctrl,{"status":"clarification","actions":[],"clarification":"Which beam?","rule_refs":[]})
	expect(ctrl.phase=="clarification" and store.snapshot(a["id"])["revision"]==before["revision"],"Clarification committed a turn")
	expect(ctrl.submit("Cast an unsupported spell.").get("ok",false),"Unsupported request did not reach interpreter")
	reply(ctrl,{"status":"unsupported","actions":[],"clarification":"Spell mechanics are not implemented.","rule_refs":[]})
	expect(ctrl.phase=="unsupported" and store.snapshot(a["id"])["revision"]==before["revision"],"Unsupported action committed a turn")
	expect(ctrl.submit("Check the roof beam.").get("ok",false),"New clarified request failed")
	if ctrl.phase!="rules_pending":
		finish()
		return
	var late = ctrl.transport
	var late_identity = ctrl.attempt["identity"].duplicate(true)
	expect(ctrl.cancel().get("ok",false) and late.canceled,"Cancel did not retire provider")
	expect(ctrl.submit("Check the roof beam.").get("ok",false),"Retry after cancel failed")
	var late_packet = late_identity.duplicate(true)
	late_packet.merge(proposal())
	late.completed.emit(true,JSON.stringify(late_packet))
	expect(ctrl.phase=="rules_pending" and ctrl.turn_id!=first_id and ctrl.attempt["identity"]["request_id"]!=first_request,"Late canceled reply accepted")
	reply(ctrl,{},false)
	expect(ctrl.phase=="rules_failed" and store.snapshot(a["id"])["revision"]==before["revision"],"Provider failure mutated state")
	var logical = ctrl.turn_id
	var retry = ctrl.retry()
	expect(retry.get("ok",false) and ctrl.turn_id==logical,"Rules retry lost logical identity")
	if ctrl.phase!="rules_pending":
		finish()
		return
	var wrong = ctrl.attempt["identity"].duplicate(true)
	wrong["campaign_id"]=b["id"]
	wrong.merge(proposal())
	ctrl.transport.completed.emit(true,JSON.stringify(wrong))
	expect(ctrl.phase=="rules_failed","Cross-campaign provider reply accepted")
	expect(ctrl.retry().get("ok",false),"Retry after wrong campaign failed")
	reply(ctrl,proposal())
	expect(ctrl.phase=="awaiting_local_approval" and not ctrl.approve({}).get("ok",false),"Provider proposal bypassed local approval")
	var request = ctrl.approval_request()
	if request.is_empty():
		finish()
		return
	var ruling = {"difficulty":"easy","effect_dc":null,"advantage":false,"disadvantage":false,"seconds":null,"establish_clock":false,"optional_features_resolved":true}
	var approval = {"campaign_id":request["campaign_id"],"actor_id":request["actor_id"],"turn_id":request["turn_id"],"expected_revision":request["expected_revision"],"action":request["action"],"ruling":ruling}
	expect(ctrl.approve(approval).get("ok",false) and ctrl.phase=="narration_pending","Locally approved check did not reach narration")
	var committed = store.receipt_by_id(a["id"],logical)
	if not committed.get("found",false) or ctrl.phase!="narration_pending":
		expect(false,"Committed receipt missing")
		finish()
		return
	expect(committed["player_text"]=="Check the roof beam." and committed["receipt"]["rolls"].size()==1,"Original intent or roll not committed")
	var original_receipt = committed["receipt"].duplicate(true)
	var damaged = original_receipt.duplicate(true)
	damaged["results"]=[]
	expect(PACK.committed_receipt_usable(original_receipt) and not PACK.committed_receipt_usable(damaged),"Unreadable receipt projection accepted")
	expect(ctrl.transport.captured_prompt.contains("Custom storyteller fixture.") and ctrl.transport.captured_prompt.contains("Family guidance fixture.") and ctrl.transport.captured_prompt.contains("Old Stone Bridge"),"Narrator settings/canon missing")
	reply(ctrl,{},false)
	expect(ctrl.phase=="narration_failed","Narration failure not retained")
	expect(ctrl.cancel().get("ok",false) and ctrl.phase=="pending_narration","Cancel lost committed receipt")
	ctrl.queue_free()
	var reopened = controller()
	expect(reopened.bind_campaign(a["id"]).get("ok",false) and reopened.phase=="pending_narration","Resume did not discover pending receipt")
	expect(reopened.retry().get("ok",false) and reopened.phase=="narration_pending","Resume narration retry failed")
	if reopened.phase!="narration_pending":
		finish()
		return
	expect(reopened.transport.captured_prompt.contains("Check the roof beam.") and store.receipt_by_id(a["id"],logical)["receipt"]==original_receipt and reopened.view_state()["committed_player_text"]=="Check the roof beam.","Resume lost original intent or rerolled")
	var narration = "Old Stone Bridge lies south of Oakhaven. Old Watermill is built of stone. Willow River is a river. Old Watermill stands on the eastern bank of Willow River. Dirt Road connects Oakhaven and Old Stone Bridge, three miles long. Old Watermill is also known as Stone Mill. Tessa, the carpenter, stands nearby. Secret Needle Cave is a cave. Old Watermill is visible."
	reply(reopened,{"text":narration})
	expect(reopened.phase=="geography_pending","Separate geography request not made")
	var wrong_ref = {"kind":"relationship","from":entity_ref(a["location_id"]),"to":entity_ref(secret),"relation_kind":"relative","direction":"south","distance_miles":null,"precision":"provisional","visibility":"player","evidence":"Old Stone Bridge lies south of Oakhaven."}
	reply(reopened,{"source_event_id":null,"facts":[wrong_ref]})
	expect(reopened.phase=="geography_failed","Private geography reference accepted")
	expect(reopened.retry().get("ok",false),"Geography retry failed")
	var conflict = wrong_ref.duplicate(true)
	conflict["to"]=entity_ref(bridge)
	var facts = [
		conflict,
		place_fact("mill","Old Watermill","watermill","Old Watermill is built of stone.","Old Watermill is built of stone."),
		place_fact("river","Willow River","river","Willow River is a river."),
		{"kind":"relationship","from":local_ref("river"),"to":local_ref("mill"),"relation_kind":"bank","direction":"east","distance_miles":null,"precision":"provisional","visibility":"player","evidence":"Old Watermill stands on the eastern bank of Willow River."},
		{"kind":"route","subject":local_ref("road"),"from":entity_ref(a["location_id"]),"to":entity_ref(bridge),"name":"Dirt Road","route_kind":"road","precision":"provisional","distance_miles":3,"points":[],"visibility":"player","evidence":"Dirt Road connects Oakhaven and Old Stone Bridge, three miles long."},
		{"kind":"alias","subject":local_ref("mill"),"alias":"Stone Mill","visibility":"player","evidence":"Old Watermill is also known as Stone Mill."},
		{"kind":"npc_description","subject":local_ref("tessa"),"location":entity_ref(a["location_id"]),"name":"Tessa","occupation":"carpenter","visibility":"player","evidence":"Tessa, the carpenter, stands nearby."},
		place_fact("hidden_collision","Secret Needle Cave","cave","Secret Needle Cave is a cave."),
		{"kind":"discovery","subject":local_ref("mill"),"entity_kind":"place","status":"observed","visibility":"player","evidence":"Old Watermill is visible."}
	]
	var captured: Array = []
	reopened.state_changed.connect(func(view):
		if view["phase"]=="reconcile_pending":
			captured.append(reopened.reconciliation_bundle()))
	# Inject a database write failure after the narration event would be inserted.
	var trigger = SQL.run(base.path_for(a["id"]),[SQL.stmt("CREATE TRIGGER b4_fixture_reject BEFORE INSERT ON world_places WHEN NEW.precision='provisional' BEGIN SELECT RAISE(ABORT,'fixture'); END")])
	expect(trigger.get("ok",false),"Rollback trigger fixture failed")
	reply(reopened,{"source_event_id":null,"facts":facts})
	expect(reopened.phase=="reconcile_pending" and store.receipt_by_id(a["id"],logical).get("narration_event_id")==null,"Failed world transaction persisted narration")
	var failed = SQL.run(base.path_for(a["id"]),[SQL.stmt("SELECT count(*) AS n FROM locations WHERE name='Old Watermill'"),SQL.stmt("SELECT count(*) AS n FROM geography_audit")],true)
	expect(failed.get("ok",false) and int(failed["results"][0][0]["n"])==0 and int(failed["results"][1][0]["n"])==0,"Failed transaction partially wrote world/audit")
	expect(SQL.run(base.path_for(a["id"]),[SQL.stmt("DROP TRIGGER b4_fixture_reject")]).get("ok",false),"Could not clear rollback fixture")
	expect(reopened.retry().get("ok",false) and reopened.phase=="idle","Ordinary reconciliation needed manual approval or failed")
	var final = store.receipt_by_id(a["id"],logical)
	expect(final.get("narration_event_id")!=null and final.get("receipt")==original_receipt and store.snapshot(a["id"])["pending_turn_id"]==null,"Narration replay or pending gate invalid")
	var map = WORLD.new().map_view(a["id"])
	var found_mill = WORLD.new().search_locations(a["id"],"Stone Mill")
	expect(map.get("ok",false) and map["party_location"]["id"]==a["location_id"] and map["travel"].is_empty() and map["travel_points"].is_empty(),"Narration moved player or created travel")
	expect(found_mill.get("locations",[]).size()==1 and found_mill["locations"][0]["x"]==null and found_mill["locations"][0]["y"]==null and found_mill["locations"][0]["status"]=="observed","Alias, discovery or coordinate validation failed")
	var mill_id = str(found_mill["locations"][0]["id"]) if not found_mill.get("locations",[]).is_empty() else ""
	expect(not JSON.stringify(map).contains("Secret Needle Cave") and WORLD.new().search_locations(a["id"],"Secret Needle Cave").get("locations",[]).is_empty(),"Undiscovered place leaked")
	var readback = SQL.run(base.path_for(a["id"]),[
		SQL.stmt("SELECT direction,distance_miles FROM geographic_relationships WHERE from_id=? AND to_id=? AND kind='relative'",[a["location_id"],bridge]),
		SQL.stmt("SELECT count(*) AS n FROM geography_audit WHERE status='conflict'"),
		SQL.stmt("SELECT count(*) AS n FROM turn_narrations WHERE turn_id=?",[logical]),
		SQL.stmt("SELECT count(*) AS n FROM world_routes WHERE name='Dirt Road'"),
		SQL.stmt("SELECT count(*) AS n FROM movement_history"),
		SQL.stmt("PRAGMA foreign_key_check")
	],true)
	expect(readback.get("ok",false) and readback["results"][0][0]["direction"]=="north" and int(readback["results"][1][0]["n"])>=2 and int(readback["results"][2][0]["n"])==1 and int(readback["results"][3][0]["n"])==1 and int(readback["results"][4][0]["n"])==0 and readback["results"][5].is_empty(),"Canon conflict, route, audit or atomicity failed")
	var log = base.read_log(a["id"])
	expect(not JSON.stringify(log).contains("south of Oakhaven") and not JSON.stringify(log).contains("Secret Needle Cave") and JSON.stringify(log).contains("Old Watermill"),"Unaccepted narration leaked or accepted details lost")
	if not captured.is_empty():
		var replay = RECONCILER.new().commit_bundle(a["id"],captured[0],[])
		expect(replay.get("ok",false) and replay.get("replayed",false),"Committed reconciliation not idempotent")
	# Return to the same scene after a new logical action. New proposal-local
	# keys must resolve to the original location/NPC/route, not duplicates.
	expect(reopened.submit("Check the beam again.").get("ok",false),"Revisit request failed")
	if reopened.phase!="rules_pending":
		finish()
		return
	expect(reopened.transport.captured_prompt.contains("Old Watermill") and reopened.transport.captured_prompt.contains("Tessa") and reopened.transport.captured_prompt.contains("The Missing Ledger"),"Revisit forgot established geography/NPC/quest")
	reply(reopened,proposal())
	expect(reopened.phase=="awaiting_local_approval","Revisit bypassed local mechanics")
	if reopened.phase=="awaiting_local_approval":
		expect(reopened.approve(local_approval(reopened,ruling)).get("ok",false),"Revisit local approval failed")
	if reopened.phase=="narration_pending":
		reply(reopened,{"text":"Stone Mill is a watermill. Tessa, the carpenter, stands nearby. Dirt Road connects Oakhaven and Old Stone Bridge, three miles long."})
	if reopened.phase=="geography_pending":
		var repeat_route = facts[4].duplicate(true)
		repeat_route["subject"]=local_ref("road_again")
		var repeat_npc = facts[6].duplicate(true)
		repeat_npc["subject"]=local_ref("tessa_again")
		reply(reopened,{"source_event_id":null,"facts":[place_fact("mill_again","Stone Mill","watermill","Stone Mill is a watermill."),repeat_route,repeat_npc]})
	expect(reopened.phase=="idle","Revisit narration did not reconcile")
	var repeated = WORLD.new().search_locations(a["id"],"Stone Mill")
	var count = SQL.run(base.path_for(a["id"]),[SQL.stmt("SELECT count(*) AS n FROM locations WHERE name IN ('Old Watermill','Stone Mill')"),SQL.stmt("SELECT count(*) AS n FROM actors WHERE kind='npc' AND instr(payload,'Tessa')>0"),SQL.stmt("SELECT count(*) AS n FROM world_routes WHERE name='Dirt Road'")],true)
	expect(repeated.get("locations",[]).size()==1 and repeated["locations"][0]["id"]==mill_id and repeated["locations"][0]["status"]=="observed" and count.get("ok",false) and int(count["results"][0][0]["n"])==1 and int(count["results"][1][0]["n"])==1 and int(count["results"][2][0]["n"])==1,"Revisit duplicated stable identities")
	expect(base.actor_record(a["id"])==actor and base.gameplay_view(b["id"])==sibling and players.load_record(master_id)==original_master,"Coordinator altered actor/master/sibling")
	# Opening generation after migration and idempotent provenance repair of a
	# simulated already-migrated legacy campaign.
	var c = base.create_campaign("Opening after migration",master_id,"tavern","standard")
	expect(not c.is_empty(),"Opening order fixture failed")
	if not c.is_empty():
		expect(MIGRATION.new().ensure(c["id"]).get("ok",false),"Pre-opening migration failed")
		var prepared = base.prepare_opening(c["id"])
		if not prepared.is_empty():
			var raw = JSON.stringify({"start_id":"tavern","location_name":"Oak Inn","atmosphere":"A quiet room.","npcs":[{"name":"Finn","occupation":"Innkeeper","attitude":0}],"world_facts":["The floor is wooden."],"thumbnail_id":"tavern"})
			expect(base.commit_opening(c["id"],prepared["previous"],raw).is_empty(),"Post-migration opening did not commit")
			expect(not base.commit_opening(c["id"],prepared["previous"],raw).is_empty(),"Duplicate opening accepted")
			var opening_view = WORLD.new().public_context(c["id"],[])
			expect(opening_view.get("local_npcs",[]).size()==1 and opening_view["party_location"]["public_description"]=="A quiet room.","Opening source link or description missing")
			var legacy = SQL.run(base.path_for(c["id"]),[SQL.stmt("DELETE FROM world_links WHERE actor_id IS NOT NULL"),SQL.stmt("UPDATE world_places SET description='',public_description='',source_event_id=NULL WHERE location_id=?",[c["location_id"]])])
			expect(legacy.get("ok",false),"Legacy provenance fixture failed")
			var repaired = MIGRATION.new().ensure(c["id"])
			expect(repaired.get("ok",false) and repaired.get("opening_backfilled",false),"Legacy opening provenance not repaired")
			expect(not MIGRATION.new().ensure(c["id"]).get("opening_backfilled",false) and WORLD.new().public_context(c["id"],[]).get("local_npcs",[]).size()==1,"Opening backfill duplicated NPC/link")
		else:
			expect(false,"Post-migration opening not prepared")
	reopened.queue_free()
	finish()
