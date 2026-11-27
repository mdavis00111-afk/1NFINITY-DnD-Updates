extends SceneTree
## Run only with explicitly authorized empty disposable user://.
const BASE = preload("res://campaigns/campaign_store.gd")
const PLAYER = preload("res://players/character_store.gd")
const SQL = preload("res://systems/sqlite.gd")
const MIGRATION = preload("res://world/world_migration.gd")
const DTO = preload("res://world/world_dto.gd")
const WORLD = preload("res://world/world_store.gd")
const TURN = preload("res://turns/turn_store.gd")
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

func run() -> void:
	var expected = OS.get_environment("INFINITY_TEST_USER_ROOT").replace("\\","/").trim_suffix("/")
	var actual = ProjectSettings.globalize_path("user://").replace("\\","/").trim_suffix("/")
	if expected.is_empty() or expected!=actual or FileAccess.file_exists("user://players.db") or FileAccess.file_exists("user://settings.cfg") or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(BASE.ROOT)):
		push_error("World smoke requires an explicitly authorized empty disposable user directory.")
		quit(2)
		return
	var players = PLAYER.new()
	var master_id = players.make_id()
	var error = players.save_record({"id":master_id,"name":"World fixture","status":"ready","ruleset":"5e-2014-2018","level":1,"inventory":[{"item_id":"dagger","quantity":2,"equipped":true}],"combat":{"hp_current":7,"hp_max":8}})
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
	var turn_id = players.make_id()
	var receipt = {"schema_version":"1","campaign_id":id,"actor_id":actor_id,"turn_id":turn_id,"prior_revision":token["revision"],"next_revision":token["revision"]+1,"resulting_turn":token["turn"]+1,"results":[],"rolls":[],"effects":[{"kind":"movement","segments":[{"from_id":at,"to_id":bridge,"route_id":route,"distance_miles":3,"elapsed_seconds":null,"precision":"approximate","points":[{"x":0,"y":0},{"x":0,"y":3}]}]}],"rule_refs":[]}
	var invalid = receipt.duplicate(true)
	invalid["effects"][0]["segments"][0]["points"][1]["y"]=4
	expect(not engine.commit_receipt(id,token,invalid).get("ok",false),"Unestablished geometry committed")
	expect(not engine.receipt_by_id(id,turn_id).get("found",false) and engine.snapshot(id)["location_id"]==at,"Failed receipt changed state")
	expect(not engine.commit_receipt(b["id"],token,receipt).get("ok",false),"Wrong campaign receipt accepted")
	expect(engine.commit_receipt(id,token,receipt).get("ok",false),"Resolved movement commit failed")
	expect(engine.commit_receipt(id,token,receipt).get("replayed",false),"Receipt retry not idempotent")
	var stored = engine.receipt_by_id(id,turn_id)
	expect(stored.get("found",false) and stored.get("receipt")==receipt,"Committed receipt unavailable")
	var after = world.map_view(id)
	expect(after.get("travel",[]).size()==1 and after.get("travel_points",[]).size()==2 and after.get("party_location",{}).get("id")==bridge and after.get("party_location",{}).get("status")=="visited","Actual path or visited state not committed")
	expect(engine.commit_narration(id,turn_id,1,"The stone bridge is ahead.").get("ok",false),"Narration commit failed")
	expect(not engine.commit_narration(id,turn_id,1,"Duplicate").get("ok",false),"Duplicate narration accepted")
	expect(TURN.new().snapshot(id).get("revision")==2 and TURN.new().snapshot(id).get("pending_turn_id")==null,"Reopened revision wrong")
	expect(BASE.new().actor_record(id).get("combat")==original_actor.get("combat"),"Movement changed HP")
	expect(BASE.new().gameplay_view(b["id"])==sibling and players.load_record(master_id)==original_master,"Sibling or master changed")
	var integrity = SQL.run(path,[SQL.stmt("PRAGMA integrity_check"),SQL.stmt("PRAGMA foreign_key_check"),SQL.stmt("SELECT quantity FROM inventory WHERE actor_id=?",[actor_id])],true)
	expect(integrity.get("ok",false) and integrity["results"][0][0].get("integrity_check")=="ok" and integrity["results"][1].is_empty() and int(integrity["results"][2][0]["quantity"])==2,"Integrity or inventory preservation failed")
	var proposal = {"schema_version":"1","request_id":players.make_id(),"turn_id":turn_id,"campaign_id":id,"actor_id":actor_id,"expected_revision":2,"source_event_id":null,"facts":[{"kind":"discovery","subject":{"id":bridge,"local_key":null},"entity_kind":"place","status":"observed","visibility":"player","evidence":"The stone bridge is ahead."}]}
	expect(DTO.geography_proposal_valid(proposal),"Valid descriptive proposal shape rejected")
	proposal["facts"][0]["status"]="visited"
	expect(not DTO.geography_proposal_valid(proposal),"Interpreter allowed to declare actual visit")
	finish()
