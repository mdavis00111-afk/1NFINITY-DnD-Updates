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
		SQL.stmt("INSERT INTO locations(id,kind,name,payload) VALUES(?,'cave','SECRET NEVER SEND','{}')",[secret]),
		SQL.stmt("INSERT INTO world_places(location_id,description) VALUES(?,'Private fixture')",[secret]),
		SQL.stmt("INSERT INTO world_discovery(id,location_id,status,visibility) VALUES(?,?,'unknown','private')",[players.make_id(),secret]),
		SQL.stmt("INSERT INTO geographic_relationships(id,from_id,to_id,kind,precision,visibility,source_event_id) VALUES(?,?,?,'relative','unknown','private',1)",[players.make_id(),a["location_id"],secret]),
		SQL.stmt("INSERT INTO locations(id,kind,name,payload) VALUES(?,'bridge','Old Stone Bridge','{}')",[bridge]),
		SQL.stmt("INSERT INTO world_places(location_id,public_description) VALUES(?,'A bridge north of Oakhaven')",[bridge]),
		SQL.stmt("INSERT INTO world_discovery(id,location_id,status,visibility,first_event_id) VALUES(?,?,'reported','player',1)",[players.make_id(),bridge]),
		SQL.stmt("INSERT INTO geographic_relationships(id,from_id,to_id,kind,direction,distance_miles,precision,visibility,source_event_id) VALUES(?,?,?,'relative','north',3,'provisional','player',1)",[players.make_id(),a["location_id"],bridge])
	]
	expect(SQL.run(base.path_for(a["id"]),fixtures).get("ok",false),"World context fixture failed")
	expect(ctrl.submit("Check the beam's strength.").get("ok",false) and ctrl.phase=="rules_pending","Rules request failed")
	if ctrl.phase!="rules_pending":
		finish()
		return
	var first = ctrl.transport
	var first_id = ctrl.turn_id
	var first_request = ctrl.attempt["identity"]["request_id"]
	expect(first.captured_prompt.contains("Old Stone Bridge") and not first.captured_prompt.contains("SECRET NEVER SEND") and not first.captured_prompt.contains(secret) and not first.captured_prompt.contains("Sibling campaign"),"Context missing canon or leaked private/sibling")
	expect(not first.captured_prompt.contains("actor_payload") and not first.captured_prompt.contains("master_character_id"),"Raw local token leaked")
	reply(ctrl,{"status":"clarification","actions":[],"clarification":"Which beam?","rule_refs":[]})
	expect(ctrl.phase=="clarification" and store.snapshot(a["id"])["revision"]==before["revision"],"Clarification committed a turn")
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
	expect(reopened.transport.captured_prompt.contains("Check the roof beam.") and store.receipt_by_id(a["id"],logical)["receipt"]==original_receipt,"Resume lost original intent or rerolled")
	reply(reopened,{"text":"The Old Stone Bridge lies north of Oakhaven."})
	expect(reopened.phase=="geography_pending","Separate geography request not made")
	var fact = {"kind":"relationship","from":{"id":a["location_id"],"local_key":null},"to":{"id":bridge,"local_key":null},"relation_kind":"relative","direction":"north","distance_miles":null,"precision":"provisional","visibility":"player","evidence":"The Old Stone Bridge lies north of Oakhaven."}
	var invalid = fact.duplicate(true)
	invalid["to"]["id"]=secret
	reply(reopened,{"source_event_id":null,"facts":[invalid]})
	expect(reopened.phase=="geography_failed","Private geography reference accepted")
	expect(reopened.retry().get("ok",false),"Geography retry failed")
	reply(reopened,{"source_event_id":null,"facts":[fact]})
	expect(reopened.phase=="reconcile_pending" and not reopened.accept_reviewed_text(reopened.reconciliation_bundle()).get("ok",false),"Nonempty geography bypassed B4")
	expect(store.receipt_by_id(a["id"],logical).get("narration_event_id")==null,"Unreviewed narration persisted")
	expect(reopened.cancel().get("ok",false) and reopened.retry().get("ok",false),"Regenerate candidate after rejection failed")
	reply(reopened,{"text":"The beam is weathered."})
	reply(reopened,{"source_event_id":null,"facts":[]})
	expect(reopened.phase=="reconcile_pending" and reopened.accept_reviewed_text(reopened.reconciliation_bundle()).get("ok",false),"Trusted text-only narration did not commit")
	var final = store.receipt_by_id(a["id"],logical)
	expect(final.get("narration_event_id")!=null and final.get("receipt")==original_receipt and store.snapshot(a["id"])["pending_turn_id"]==null,"Narration replay or pending gate invalid")
	expect(base.actor_record(a["id"])==actor and base.gameplay_view(b["id"])==sibling and players.load_record(master_id)==original_master,"Coordinator altered actor/master/sibling")
	expect(reopened.phase=="idle","Controller not ready after accepted narration")
	reopened.queue_free()
	finish()
