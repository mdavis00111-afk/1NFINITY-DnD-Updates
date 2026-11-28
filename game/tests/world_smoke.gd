extends SceneTree
## Run only with explicitly authorized empty disposable user://.
const BASE = preload("res://campaigns/campaign_store.gd")
const PLAYER = preload("res://players/character_store.gd")
const SQL = preload("res://systems/sqlite.gd")
const MIGRATION = preload("res://world/world_migration.gd")
const DTO = preload("res://world/world_dto.gd")
const WORLD = preload("res://world/world_store.gd")
const TURN = preload("res://turns/turn_store.gd")
const RAW = preload("res://turns/raw_mechanics.gd")
const RESOLVER = preload("res://turns/turn_resolver.gd")
const SESSION = preload("res://persistence/gameplay_session.gd")
const CAT = preload("res://rules/catalog.gd")
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func finish() -> void:
	for message in failures:
		push_error(message)
	print("World/turn smoke failures: ",failures.size())
	quit(0 if failures.is_empty() else 1)

func action_packet(token: Dictionary, request_id: String, turn_id: String, action: Dictionary) -> Dictionary:
	return {"schema_version":"1","request_id":request_id,"turn_id":turn_id,"campaign_id":token["campaign_id"],"actor_id":token["actor_id"],"expected_revision":token["revision"],"status":"proposed","actions":[action],"clarification":null,"rule_refs":action["reference_refs"]}

func local_approval(token: Dictionary, turn_id: String, action: Dictionary, ruling: Dictionary) -> Dictionary:
	return {"campaign_id":token["campaign_id"],"actor_id":token["actor_id"],"turn_id":turn_id,"expected_revision":token["revision"],"action":action,"ruling":ruling}

func travel_action(route: String, dest: String, fast: bool) -> Dictionary:
	return {"handler_id":"travel","target_refs":[{"kind":"location","id":dest}],"reference_refs":RAW.refs_for("travel"),"intent_text":"Walk to the chosen location","arguments":{"route_id":route,"destination_id":dest,"pace":"normal","fast_travel":fast}}

func run() -> void:
	var expected = OS.get_environment("INFINITY_TEST_USER_ROOT").replace("\\","/").trim_suffix("/")
	var actual = ProjectSettings.globalize_path("user://").replace("\\","/").trim_suffix("/")
	if expected.is_empty() or expected!=actual or FileAccess.file_exists("user://players.db") or FileAccess.file_exists("user://settings.cfg") or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(BASE.ROOT)):
		push_error("World smoke requires an explicitly authorized empty disposable user directory.")
		quit(2)
		return
	var players = PLAYER.new()
	var master_id = players.make_id()
	var error = players.save_record({"id":master_id,"name":"World fixture","status":"ready","ruleset":"5e-2014-2018","catalog_revision":CAT.REVISION,"level":1,"ability_scores":{"str":10,"dex":14,"con":12,"int":10,"wis":12,"cha":10},"ability_modifiers":{"str":0,"dex":2,"con":1,"int":0,"wis":1,"cha":0},"proficiency_bonus":2,"proficiency_ids":["skill-stealth","saving-throw-dex"],"expertise_ids":["skill-stealth"],"skills":{"stealth":{"ability":"dex","proficient":true,"expertise":true,"modifier":6}},"saving_throws":{"str":0,"dex":4,"con":1,"int":0,"wis":1,"cha":0},"coins":{"pp":0,"gp":10,"ep":0,"sp":0,"cp":0},"carrying_capacity_lb":150,"equipment":{"armor_penalty":false},"inventory":[{"item_id":"dagger","quantity":2,"equipped":true}],"combat":{"hp_current":7,"hp_max":8,"speed_feet":30,"size":"Medium","passive_perception":11,"conditions":[],"exhaustion":0,"active_effects":[]}})
	expect(error.is_empty(),"Master fixture save failed")
	if not error.is_empty():
		finish()
		return
	var original_master = players.load_record(master_id)
	var base = BASE.new()
	var a = base.create_campaign("World A",master_id,"tavern","standard")
	var b = base.create_campaign("World B",master_id,"road","standard")
	expect(not a.is_empty() and not b.is_empty(),"Campaign fixtures unavailable")
	if a.is_empty() or b.is_empty():
		finish()
		return
	var id = str(a["id"])
	var at = str(a["location_id"])
	var actor_id = str(a["actor_id"])
	var sibling = base.gameplay_view(b["id"])
	var opening = base.prepare_opening(id)
	expect(not opening.is_empty(),"Opening preparation failed")
	if not opening.is_empty():
		expect(base.commit_opening(id,opening["previous"],JSON.stringify({"start_id":"tavern","location_name":"Oakhaven","atmosphere":"A busy inn.","npcs":[{"name":"Mara","occupation":"Innkeeper","attitude":0}],"world_facts":["The inn has an oak door."],"thumbnail_id":"tavern"})).is_empty(),"Opening fixture failed")
	var original_actor = base.actor_record(id)
	var travel_fixture=original_actor.duplicate(true)
	var travel_load={"complete":true,"known_lb":0.0}
	for speed in [25,30,35,25.0,30.0,35.0]:
		travel_fixture["combat"]["speed_feet"]=speed
		expect(RAW.travel_actor(travel_fixture,[],null,travel_load).get("ok",false),"Supported travel speed rejected: "+str(speed))
	for speed in [0,26,30.5,"30",true,null]:
		travel_fixture["combat"]["speed_feet"]=speed
		expect(not RAW.travel_actor(travel_fixture,[],null,travel_load).get("ok",false),"Unsupported travel speed accepted: "+str(speed))
	travel_fixture["combat"]["speed_feet"]=30.0
	travel_fixture["combat"]["exhaustion"]=1
	expect(not RAW.travel_actor(travel_fixture,[],null,travel_load).get("ok",false),"Exhausted travel accepted")
	travel_fixture["combat"]["exhaustion"]=0
	travel_fixture["combat"]["conditions"]=["prone"]
	expect(not RAW.travel_actor(travel_fixture,[],null,travel_load).get("ok",false),"Conditioned travel accepted")
	var original_log = base.read_log(id)
	var path = base.path_for(id)
	var hidden = players.make_id()
	var bridge = players.make_id()
	var route = players.make_id()
	var seed = SQL.run(path,[SQL.stmt("UPDATE locations SET x=0,y=0 WHERE id=?",[at]),SQL.stmt("INSERT INTO locations(id,kind,name,x,y,payload) VALUES(?,'cave','Secret cave',7,8,'{}')",[hidden])])
	expect(seed.get("ok",false),"Legacy coordinate fixture failed")
	var migrate = MIGRATION.new()
	var migrated = migrate.ensure(id)
	expect(migrated.get("ok",false) and migrated.get("migrated",false),"Migration failed: "+str(migrated.get("error","")))
	if not migrated.get("ok",false):
		finish()
		return
	expect(FileAccess.file_exists(str(migrated.get("backup",""))),"Backup missing")
	var backup = SQL.run(migrated["backup"],[SQL.stmt("SELECT value FROM meta WHERE key='world_schema'"),SQL.stmt("PRAGMA integrity_check")],true)
	expect(backup.get("ok",false) and backup["results"][0].is_empty() and backup["results"][1][0].get("integrity_check")=="ok","Backup is not pre-migration copy")
	expect(not migrate.ensure(id).get("migrated",true),"Repeated migration was not idempotent")
	expect(base.actor_record(id)==original_actor and base.read_log(id)==original_log,"Migration changed actor or opening log")
	var world = WORLD.new()
	var first = world.map_view(id)
	expect(first.get("ok",false) and first.get("locations",[]).size()==1,"Initial visibility wrong")
	if first.get("ok",false):
		expect(first["party_location"].get("x")==null and first["party_location"].get("precision")=="unknown","Legacy origin invented")
	expect(base.gameplay_view(id).get("locations",[]).size()==1,"Old location popup bypassed discovery")
	expect(world.search_locations(id,"Secret").get("locations",[]).is_empty(),"Hidden search result leaked")
	# Future B4 approved geography fixture; no AI write interface is invoked.
	var fixtures = SQL.run(path,[
		SQL.stmt("UPDATE world_places SET precision='approximate',uncertainty_miles=0.25 WHERE location_id=?",[at]),
		SQL.stmt("INSERT INTO locations(id,kind,name,x,y,payload) VALUES(?,'bridge','Old Bridge',0,3,'{}')",[bridge]),
		SQL.stmt("INSERT INTO world_places(location_id,precision,uncertainty_miles) VALUES(?,'approximate',0.25)",[bridge]),
		SQL.stmt("INSERT INTO world_discovery(id,location_id,status,visibility,first_event_id) VALUES(?,?,'reported','player',1)",[players.make_id(),bridge]),
		SQL.stmt("INSERT INTO geographic_relationships(id,from_id,to_id,kind,direction,distance_miles,precision,visibility,source_event_id) VALUES(?,?,?,'relative','north',3,'approximate','player',1)",[players.make_id(),at,bridge]),
		SQL.stmt("INSERT INTO world_routes(id,from_id,to_id,name,kind,precision,distance_miles,source_event_id) VALUES(?,?,?,'Dirt road','road','approximate',3,1)",[route,at,bridge]),
		SQL.stmt("INSERT INTO world_discovery(id,route_id,status,visibility,first_event_id) VALUES(?,?,'reported','player',1)",[players.make_id(),route]),
		SQL.stmt("INSERT INTO route_points(route_id,seq,x,y) VALUES(?,0,0,0)",[route]),
		SQL.stmt("INSERT INTO route_points(route_id,seq,x,y) VALUES(?,1,0,3)",[route]),
		SQL.stmt("INSERT INTO location_aliases(location_id,alias,visibility,source_event_id) VALUES(?,'Stone Bridge','player',1)",[bridge]),
		SQL.stmt("INSERT INTO location_aliases(location_id,alias,visibility,source_event_id) VALUES(?,'Secret Alias','private',1)",[bridge])
	])
	expect(fixtures.get("ok",false),"Approved geography fixture failed")
	var map = world.map_view(id)
	expect(map.get("ok",false) and map.get("locations",[]).size()==2 and map.get("route_points",[]).size()==2 and map.get("travel",[]).is_empty(),"Map confused roads with actual travel or leaked hidden place")
	expect(world.search_locations(id,"Stone Bridge").get("locations",[]).size()==1 and world.search_locations(id,"Secret Alias").get("locations",[]).is_empty(),"Alias visibility wrong")
	var dm = world.dm_geography(id)
	expect(dm.get("ok",false) and dm.get("locations",[]).size()==2 and dm.get("local_facts",[]).has("The inn has an oak door."),"DM context missing relevant canon")
	expect(not world.add_annotation(id,hidden,"Hidden").get("ok",false),"Hidden annotation accepted")
	expect(world.add_annotation(id,bridge,"Remember the bridge.").get("ok",false),"Visible annotation failed")
	var engine = TURN.new()
	var token = engine.snapshot(id)
	expect(token.get("ok",false),"Turn token unavailable")
	if not token.get("ok",false):
		finish()
		return
	var resolver = RESOLVER.new()
	var catalogue = CAT.new()
	expect(RAW.selected_die([2,19],"advantage")==19 and RAW.selected_die([2,19],"disadvantage")==2 and RAW.selected_die([20],"normal")==20 and RAW.selected_die([1.5],"normal")==null,"d20 selection invalid")
	var natural_one = {"roll_id":players.make_id(),"kind":"ability_check","sides":20,"mode":"normal","values":[1],"selected":1,"modifier":6,"total":7,"target":5,"result":"success"}
	expect(RAW.roll_valid(natural_one,"ability_check","normal",6,5),"Natural 1 incorrectly forces check failure")
	var natural_twenty = {"roll_id":players.make_id(),"kind":"saving_throw","sides":20,"mode":"normal","values":[20],"selected":20,"modifier":0,"total":20,"target":25,"result":"failure"}
	expect(RAW.roll_valid(natural_twenty,"saving_throw","normal",0,25),"Natural 20 incorrectly forces save success")
	var forged_roll = natural_one.duplicate(true)
	forged_roll["total"]=99
	expect(not RAW.roll_valid(forged_roll,"ability_check","normal",6,5),"Forged dice total accepted")
	var advantage_roll = RAW.roll_receipt("ability_check","advantage",2,15)
	expect(RAW.roll_valid(advantage_roll,"ability_check","advantage",2,15) and advantage_roll["values"].size()==2,"Advantage receipt invalid")
	expect(RAW.time_after({"kind":"time","seconds":60,"establish_clock":false},{"elapsed_seconds":null})==null and RAW.time_after({"kind":"time","seconds":null,"establish_clock":false},{"elapsed_seconds":60})==null and not RAW.time_valid({"kind":"time","seconds":60,"establish_clock":true},{"elapsed_seconds":60}),"Unknown or established clock silently reset")
	expect(RAW.travel_seconds(3.0,"normal",false)==3600 and RAW.travel_seconds(3.0,"normal",true)==7200 and RAW.travel_seconds(4.0,"fast",false)==3600 and RAW.travel_seconds(2.0,"slow",false)==3600 and RAW.travel_seconds(32.0,"fast",false)==null,"PHB hourly pace invalid")
	var mod = RAW.modifier_for(token["actor"],"ability_check","dex","stealth",catalogue)
	expect(mod.get("modifier")==6,"Expertise not doubled exactly once")
	expect(RAW.modifier_for(token["actor"],"ability_check","str","stealth",catalogue).get("modifier")==4,"Alternate ability skill check wrong")
	expect(RAW.modifier_for(token["actor"],"saving_throw","dex",null,catalogue).get("modifier")==4,"Save proficiency wrong")
	expect(RAW.roll_context(token["actor"],"ability_check","dex",true,true).get("mode")=="normal","Advantage/disadvantage did not cancel")
	var conditioned = token["actor"].duplicate(true)
	conditioned["combat"]["conditions"]=["poisoned"]
	expect(RAW.roll_context(conditioned,"ability_check","dex",false,false).get("mode")=="disadvantage","Poison condition missing")
	conditioned["combat"]["conditions"]=["paralyzed"]
	expect(RAW.roll_context(conditioned,"saving_throw","dex",false,false).get("automatic_failure")==true,"Automatic failure missing")
	var turn_id = players.make_id()
	var request_id = players.make_id()
	var action = travel_action(route,bridge,false)
	var ruling = {"difficult":false,"clearance":"verified_unobstructed_supplied_foot_travel","establish_clock":true}
	var packet = action_packet(token,request_id,turn_id,action)
	var approval = local_approval(token,turn_id,action,ruling)
	var first_fast = travel_action(route,bridge,true)
	expect(not resolver.prepare(token,turn_id,first_fast,local_approval(token,turn_id,first_fast,ruling)).get("ok",false),"Untraversed fast route accepted")
	var invalid = packet.duplicate(true)
	invalid["actions"][0]["arguments"]["distance_miles"]=99
	expect(not resolver.resolve(id,token,request_id,turn_id,invalid,action["reference_refs"],approval).get("ok",false),"Provider distance accepted")
	expect(not resolver.resolve(id,token,request_id,turn_id,packet,action["reference_refs"],{}).get("ok",false),"Travel without local approval accepted")
	var no_refs = packet.duplicate(true)
	no_refs["rule_refs"]=[]
	no_refs["actions"][0]["reference_refs"]=[]
	expect(not resolver.validate_proposal(token,request_id,turn_id,no_refs,[]).get("ok",false),"Required rules absent from frozen context accepted")
	var prepared = resolver.prepare(token,turn_id,action,approval)
	expect(prepared.get("ok",false),"Travel plan failed: "+str(prepared.get("error","")))
	if not prepared.get("ok",false):
		finish()
		return
	var receipt = prepared["receipt"]
	var bad_geometry = receipt.duplicate(true)
	bad_geometry["effects"][0]["segments"][0]["points"][1]["y"]=4
	expect(not engine.commit_receipt(id,token,bad_geometry).get("ok",false),"Unestablished geometry committed")
	expect(not engine.commit_receipt(b["id"],token,receipt).get("ok",false),"Wrong campaign receipt accepted")
	expect(not engine.receipt_by_id(id,turn_id).get("found",false) and engine.snapshot(id)["location_id"]==at,"Rejected receipt changed state")
	var trigger = SQL.run(path,[SQL.stmt("CREATE TRIGGER b2_test_abort BEFORE INSERT ON movement_points BEGIN SELECT RAISE(ABORT,'fixture'); END")])
	expect(trigger.get("ok",false),"Rollback fixture setup failed")
	var rejected = resolver.resolve(id,token,request_id,turn_id,packet,action["reference_refs"],approval)
	expect(not rejected.get("ok",false),"Injected movement failure committed")
	expect(not engine.receipt_by_id(id,turn_id).get("found",false) and engine.snapshot(id)["location_id"]==at and engine.snapshot(id)["elapsed_seconds"]==null,"Movement rollback incomplete")
	expect(SQL.run(path,[SQL.stmt("DROP TRIGGER b2_test_abort")]).get("ok",false),"Rollback trigger removal failed")
	var cached = resolver.unresolved.get(id,{}).get("receipt",{}).duplicate(true)
	var committed = resolver.resolve(id,token,request_id,turn_id,packet,action["reference_refs"],approval)
	expect(committed.get("ok",false) and committed.get("receipt")==cached,"Retry did not preserve prepared receipt")
	if not committed.get("ok",false):
		finish()
		return
	receipt=committed["receipt"]
	expect(RAW.stored_receipt_usable(receipt),"Committed travel receipt rejected")
	var wrong_duration = receipt.duplicate(true)
	wrong_duration["effects"].back()["seconds"]=1
	expect(not RAW.stored_receipt_usable(wrong_duration),"Inconsistent stored travel clock accepted")
	var missing_rules = receipt.duplicate(true)
	missing_rules["rule_refs"]=[]
	expect(not RAW.stored_receipt_usable(missing_rules),"Stored receipt missing rules accepted")
	expect(engine.snapshot(id).get("elapsed_seconds")==3600,"Clock was not established from approved travel")
	expect(resolver.resolve(id,token,request_id,turn_id,packet,action["reference_refs"],approval).get("replayed",false),"Receipt retry not idempotent")
	var after = world.map_view(id)
	expect(after.get("travel",[]).size()==1 and after.get("travel_points",[]).size()==2 and after.get("party_location",{}).get("id")==bridge and after.get("party_location",{}).get("status")=="visited","Actual path or visited state not committed")
	expect(engine.commit_narration(id,turn_id,1,"The stone bridge is ahead.").get("ok",false),"Narration commit failed")
	expect(not engine.commit_narration(id,turn_id,1,"Duplicate").get("ok",false),"Duplicate narration accepted")
	token=engine.snapshot(id)
	expect(token.get("revision")==2 and token.get("pending_turn_id")==null,"Reopened revision wrong")
	turn_id=players.make_id()
	request_id=players.make_id()
	action=travel_action(route,at,true)
	ruling["establish_clock"]=false
	packet=action_packet(token,request_id,turn_id,action)
	approval=local_approval(token,turn_id,action,ruling)
	var ordinary = travel_action(route,at,false)
	var same_path = resolver.prepare(token,turn_id,ordinary,local_approval(token,turn_id,ordinary,ruling))
	var fast_path = resolver.prepare(token,turn_id,action,approval)
	expect(same_path.get("ok",false) and fast_path.get("ok",false) and same_path["receipt"]["effects"]==fast_path["receipt"]["effects"],"Fast travel changed time or path")
	var back = resolver.resolve(id,token,request_id,turn_id,packet,action["reference_refs"],approval)
	expect(back.get("ok",false) and engine.snapshot(id).get("elapsed_seconds")==7200 and engine.snapshot(id).get("location_id")==at,"Return journey failed")
	if not back.get("ok",false):
		finish()
		return
	expect(engine.commit_narration(id,turn_id,3,"Back at the inn.").get("ok",false),"Return narration failed")
	token=engine.snapshot(id)
	turn_id=players.make_id()
	request_id=players.make_id()
	var refs = RAW.refs_for("ability_check","dex","stealth")
	action={"handler_id":"ability_check","target_refs":[],"reference_refs":refs,"intent_text":"Sneak past the obstruction","arguments":{"ability":"dex","skill":"stealth"}}
	packet=action_packet(token,request_id,turn_id,action)
	ruling={"difficulty":"medium","effect_dc":null,"advantage":true,"disadvantage":true,"seconds":60,"establish_clock":false,"optional_features_resolved":true}
	approval=local_approval(token,turn_id,action,ruling)
	var checked = resolver.resolve(id,token,request_id,turn_id,packet,refs,approval)
	expect(checked.get("ok",false),"Ability check failed: "+str(checked.get("error","")))
	if not checked.get("ok",false):
		finish()
		return
	var check_receipt = checked["receipt"]
	var impossible_auto = check_receipt.duplicate(true)
	impossible_auto["results"][0]["outcome"]="automatic_failure"
	impossible_auto["results"][0]["roll_id"]=null
	impossible_auto["rolls"]=[]
	expect(not RAW.stored_receipt_usable(impossible_auto),"Automatic failure of ability check accepted on replay")
	var roll = check_receipt["rolls"][0]
	expect(roll["mode"]=="normal" and roll["values"].size()==1 and roll["total"]==roll["selected"]+6 and roll["target"]==15 and roll["result"]==("success" if roll["total"]>=15 else "failure"),"Incorrect check receipt")
	expect(engine.snapshot(id).get("elapsed_seconds")==7260,"Check time not committed")
	var replayed_check=resolver.resolve(id,token,request_id,turn_id,packet,refs,approval)
	expect(replayed_check.get("ok",false) and SESSION.new().typed_equal(replayed_check.get("receipt"),check_receipt),"Committed check replay changed receipt or failed")
	expect(engine.commit_narration(id,turn_id,5,"The check is resolved.").get("ok",false),"Check narration failed")
	token=engine.snapshot(id)
	turn_id=players.make_id()
	request_id=players.make_id()
	refs=RAW.refs_for("saving_throw","dex",null)
	action={"handler_id":"saving_throw","target_refs":[],"reference_refs":refs,"intent_text":"Resolve the approved Dexterity save","arguments":{"ability":"dex","skill":null}}
	packet=action_packet(token,request_id,turn_id,action)
	ruling={"difficulty":null,"effect_dc":12,"advantage":false,"disadvantage":true,"seconds":6,"establish_clock":false,"optional_features_resolved":true}
	approval=local_approval(token,turn_id,action,ruling)
	var saved = resolver.resolve(id,token,request_id,turn_id,packet,refs,approval)
	expect(saved.get("ok",false),"Saving throw failed")
	if not saved.get("ok",false):
		finish()
		return
	roll=saved["receipt"]["rolls"][0]
	expect(roll["mode"]=="disadvantage" and roll["values"].size()==2 and roll["selected"]==mini(int(roll["values"][0]),int(roll["values"][1])) and roll["total"]==roll["selected"]+4,"Save receipt wrong")
	expect(engine.commit_narration(id,turn_id,7,"The saving throw is resolved.").get("ok",false),"Save narration failed")
	expect(engine.snapshot(id).get("elapsed_seconds")==7266,"Saving throw time not committed")
	# A syntactically valid receipt can disagree with its relational identity.
	var prior = engine.receipt_by_id(id,turn_id)
	expect(prior.get("ok",false) and prior.get("found",false),"Committed receipt lookup failed")
	if prior.get("found",false):
		var stored = prior["receipt"]
		var forged = stored.duplicate(true)
		forged["prior_revision"]=20
		forged["next_revision"]=21
		forged["resulting_turn"]=10
		expect(SQL.run(path,[SQL.stmt("UPDATE turn_receipts SET payload=? WHERE turn_id=?",[JSON.stringify(forged),turn_id])]).get("ok",false),"Receipt corruption fixture failed")
		expect(not engine.receipt_by_id(id,turn_id).get("ok",false),"Receipt with mismatched relational revisions accepted")
		expect(SQL.run(path,[SQL.stmt("UPDATE turn_receipts SET payload=? WHERE turn_id=?",[JSON.stringify(stored),turn_id])]).get("ok",false),"Receipt restoration failed")
		var narration_row = SQL.run(path,[SQL.stmt("SELECT event_id FROM turn_narrations WHERE turn_id=?",[turn_id])],true)
		if narration_row.get("ok",false) and narration_row["results"][0].size()==1:
			var event_id = narration_row["results"][0][0]["event_id"]
			expect(SQL.run(path,[SQL.stmt("UPDATE events SET turn=99 WHERE id=?",[event_id])]).get("ok",false),"Narration corruption fixture failed")
			expect(not engine.receipt_by_id(id,turn_id).get("ok",false),"Wrong narration event turn accepted")
			expect(SQL.run(path,[SQL.stmt("UPDATE events SET turn=? WHERE id=?",[stored["resulting_turn"],event_id])]).get("ok",false),"Narration restoration failed")
		expect(engine.receipt_by_id(id,turn_id).get("ok",false),"Restored receipt lookup failed")
	expect(BASE.new().actor_record(id).get("combat")==original_actor.get("combat"),"Resolution changed HP")
	expect(BASE.new().gameplay_view(b["id"])==sibling and players.load_record(master_id)==original_master,"Sibling or master changed")
	var integrity = SQL.run(path,[SQL.stmt("PRAGMA integrity_check"),SQL.stmt("PRAGMA foreign_key_check"),SQL.stmt("SELECT quantity FROM inventory WHERE actor_id=?",[actor_id])],true)
	expect(integrity.get("ok",false) and integrity["results"][0][0].get("integrity_check")=="ok" and integrity["results"][1].is_empty() and int(integrity["results"][2][0]["quantity"])==2,"Integrity or inventory preservation failed")
	var proposal = {"schema_version":"1","request_id":players.make_id(),"turn_id":turn_id,"campaign_id":id,"actor_id":actor_id,"expected_revision":8,"source_event_id":null,"facts":[{"kind":"discovery","subject":{"id":bridge,"local_key":null},"entity_kind":"place","status":"observed","visibility":"player","evidence":"The stone bridge is ahead."}]}
	expect(DTO.geography_proposal_valid(proposal),"Valid descriptive proposal shape rejected")
	proposal["facts"][0]["status"]="visited"
	expect(not DTO.geography_proposal_valid(proposal),"Interpreter allowed to declare actual visit")
	finish()
