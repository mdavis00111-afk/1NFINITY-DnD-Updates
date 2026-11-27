extends SceneTree
## Run only in a disposable explicitly authorized user root.
## All geography and resolved movement here are TEST FIXTURES, not game generators.
const BASE = preload("res://campaigns/campaign_store.gd")
const PLAYER = preload("res://players/character_store.gd")
const SQL = preload("res://systems/sqlite.gd")
const MIGRATION = preload("res://world/world_migration.gd")
const WORLD = preload("res://world/world_store.gd")
const TURN = preload("res://turns/turn_store.gd")
const RAW = preload("res://turns/raw_mechanics.gd")
const RESOLVER = preload("res://turns/turn_resolver.gd")
const CAT = preload("res://rules/catalog.gd")
const MODEL = preload("res://cartography/map_model.gd")
const ART = preload("res://cartography/asset_catalog.gd")
const CANVAS = preload("res://cartography/map_canvas.gd")
const ATLAS = preload("res://cartography/map_window.gd")
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func expect(ok: bool,message: String) -> void:
	if not ok:
		failures.append(message)

func finish() -> void:
	for message in failures:
		push_error(message)
	print("Cartography renderer smoke failures: ",failures.size())
	quit(0 if failures.is_empty() else 1)

func settle(frames: int = 5) -> void:
	for i in range(frames):
		await process_frame

func read_all(model,id: String) -> bool:
	model.start(id)
	for i in range(MODEL.MAX_PAGES):
		var result = model.fetch_next()
		if result=="done": return true
		if result=="error": return false
	return false

func fake_page(id: String,number: int,revision: int) -> Dictionary:
	var page = {"ok":true,"schema_version":"1","campaign_id":id,"world_id":id,"revision":revision,"annotation_count":0,"page":number,"limit":128,"distance_unit":"mile","x_axis":"east","y_axis":"north","party_location":null}
	for key in MODEL.LISTS:
		page[key] = []
	return page

func test_page_contract() -> void:
	var model = MODEL.new()
	model.start("fixture")
	var first = fake_page("fixture",0,2)
	first["locations"] = [{"id":"known","name":"Known","status":"reported","precision":"unknown","x":0.0,"y":0.0}]
	expect(model.accept_page(first)=="more" and model.data.is_empty(),"Partial map was exposed")
	expect(model.accept_page(fake_page("fixture",1,3))=="error" and model.data.is_empty(),"Mixed revision accepted")
	model.start("fixture")
	expect(model.accept_page(first)=="more","First page rejected")
	var second = fake_page("fixture",1,2)
	second["locations"] = [{"id":"other","name":"Other","status":"visited","precision":"unknown"}]
	expect(model.accept_page(second)=="more","Second page rejected")
	expect(model.accept_page(fake_page("fixture",2,2))=="done" and model.data["locations"].size()==2,"Multi-page completion failed")
	expect(not MODEL.positioned(model.data["locations"][0]),"Provisional/unknown origin plotted")
	model.start("fixture")
	expect(model.accept_page(fake_page("wrong",0,2))=="error","Cross-campaign page accepted")
	model.start("fixture")
	expect(model.accept_page(first)=="more","Duplicate test first page rejected")
	second["locations"] = first["locations"]
	expect(model.accept_page(second)=="error","Duplicate stable ID accepted")
	model.start("fixture")
	first["annotation_count"]=1
	first["annotations"]=[{"id":"note-one","location_id":"known","text":"First"}]
	expect(model.accept_page(first)=="more","Annotation first page rejected")
	var changed = fake_page("fixture",1,2)
	changed["annotation_count"]=2
	expect(model.accept_page(changed)=="error" and model.data.is_empty(),"Changed annotation count accepted at unchanged world revision")
	model.start("fixture")
	first["annotation_count"]=2
	expect(model.accept_page(first)=="more" and model.accept_page(changed)=="error","Incomplete annotation page accepted")

func run() -> void:
	test_page_contract()
	var expected = OS.get_environment("INFINITY_TEST_USER_ROOT").replace("\\","/").trim_suffix("/")
	var actual = ProjectSettings.globalize_path("user://").replace("\\","/").trim_suffix("/")
	if expected.is_empty() or expected!=actual or FileAccess.file_exists("user://players.db") or FileAccess.file_exists("user://settings.cfg") or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(BASE.ROOT)):
		push_error("Cartography smoke requires explicitly authorized empty disposable user directory.")
		quit(2)
		return
	var art = ART.new()
	expect(art.initialize() and art.entries.size()==250,"Art catalogue unavailable or replacements missing")
	expect(art.texture("settlement.bridge.vintage")==null and art.texture("adventure.military_camp.vintage")==null,"Licence-pending texture selected")
	var chosen = art.choose("settlements","bridge","fixture",true,"settlement.bridge.vintage")
	expect(not chosen.is_empty() and chosen["id"]=="settlement.bridge.symbol","No licensed bridge fallback")
	expect(art.choose("settlements","bridge","fixture",true,"settlement.bridge.vintage")==chosen,"Art selection not deterministic")
	expect(art.for_place({"id":"fixture","kind":"unclassified"},false).is_empty(),"Unknown location fabricated artwork")
	var players = PLAYER.new()
	var master_id = players.make_id()
	var error = players.save_record({"id":master_id,"name":"Cartography fixture","status":"ready","ruleset":"5e-2014-2018","catalog_revision":CAT.REVISION,"level":1,"ability_scores":{"str":10,"dex":14,"con":12,"int":10,"wis":12,"cha":10},"ability_modifiers":{"str":0,"dex":2,"con":1,"int":0,"wis":1,"cha":0},"proficiency_bonus":2,"proficiency_ids":["skill-stealth","saving-throw-dex"],"expertise_ids":["skill-stealth"],"skills":{"stealth":{"ability":"dex","proficient":true,"expertise":true,"modifier":6}},"saving_throws":{"str":0,"dex":4,"con":1,"int":0,"wis":1,"cha":0},"coins":{"pp":0,"gp":10,"ep":0,"sp":0,"cp":0},"carrying_capacity_lb":150,"equipment":{"armor_penalty":false},"inventory":[{"item_id":"dagger","quantity":2,"equipped":true}],"combat":{"hp_current":7,"hp_max":8,"speed_feet":30,"size":"Medium","passive_perception":11,"conditions":[],"exhaustion":0,"active_effects":[]}})
	expect(error.is_empty(),"Master fixture save failed")
	if not error.is_empty():
		finish()
		return
	var master = players.load_record(master_id)
	var base = BASE.new()
	var campaign = base.create_campaign("Atlas fixture",master_id,"tavern","standard")
	var sibling = base.create_campaign("Sibling fixture",master_id,"road","standard")
	expect(not campaign.is_empty() and not sibling.is_empty(),"Campaign fixture failed")
	if campaign.is_empty() or sibling.is_empty():
		finish()
		return
	var id = str(campaign["id"])
	var at_id = str(campaign["location_id"])
	var sibling_before = base.gameplay_view(sibling["id"])
	var path = base.path_for(id)
	var model = MODEL.new()
	expect(not read_all(model,id) and model.data.is_empty(),"Uninitialized map exposed or migrated")
	var before = SQL.run(path,[SQL.stmt("SELECT value FROM meta WHERE key='world_schema'")],true)
	expect(before.get("ok",false) and before["results"][0].is_empty(),"Map tab implicitly migrated campaign")
	var hidden = players.make_id()
	expect(SQL.run(path,[SQL.stmt("UPDATE locations SET x=0,y=0 WHERE id=?",[at_id]),SQL.stmt("INSERT INTO locations(id,kind,name,x,y,payload) VALUES(?,'cave','Secret cave',9,9,'{}')",[hidden])]).get("ok",false),"Legacy fixture setup failed")
	var migration = MIGRATION.new().ensure(id)
	expect(migration.get("ok",false),"Disposable migration failed: "+str(migration.get("error","")))
	if not migration.get("ok",false):
		finish()
		return
	expect(read_all(model,id),"Initial MapView failed")
	expect(model.data.get("locations",[]).size()==1 and not MODEL.positioned(model.data.get("party_location",{})),"Unknown legacy origin or hidden location exposed")
	var bridge = players.make_id()
	var unplaced = players.make_id()
	var route = players.make_id()
	var region = players.make_id()
	var fixture = SQL.run(path,[
		SQL.stmt("INSERT INTO terrain_regions(id,name,kind,precision,public_description,source_event_id) VALUES(?,'Greenwood','deciduous_forest','approximate','Known wooded region.',1)",[region]),
		SQL.stmt("INSERT INTO world_discovery(id,region_id,status,visibility,first_event_id) VALUES(?,?,'observed','player',1)",[players.make_id(),region]),
		SQL.stmt("INSERT INTO terrain_points(region_id,seq,x,y) VALUES(?,0,-2,-1),(?,1,2,-1),(?,2,2,4),(?,3,-2,4)",[region,region,region,region]),
		SQL.stmt("UPDATE world_places SET precision='approximate',uncertainty_miles=0.25,region_id=? WHERE location_id=?",[region,at_id]),
		SQL.stmt("INSERT INTO locations(id,kind,name,x,y,payload) VALUES(?,'bridge','Old Bridge',0,3,'{}'),(?,'mill','Reported Mill',NULL,NULL,'{}')",[bridge,unplaced]),
		SQL.stmt("INSERT INTO world_places(location_id,region_id,precision,uncertainty_miles,asset_id,public_description,description) VALUES(?,?,'approximate',0.25,'settlement.bridge.vintage','Public bridge.','Private bridge fact.')",[bridge,region]),
		SQL.stmt("INSERT INTO world_places(location_id,region_id) VALUES(?,?)",[unplaced,region]),
		SQL.stmt("INSERT INTO world_discovery(id,location_id,status,visibility,first_event_id) VALUES(?,?,'reported','player',1),(?,?,'reported','player',1)",[players.make_id(),bridge,players.make_id(),unplaced]),
		SQL.stmt("INSERT INTO world_routes(id,from_id,to_id,name,kind,precision,distance_miles,source_event_id) VALUES(?,?,?,'Dirt road','road','approximate',3,1)",[route,at_id,bridge]),
		SQL.stmt("INSERT INTO world_discovery(id,route_id,status,visibility,first_event_id) VALUES(?,?,'observed','player',1)",[players.make_id(),route]),
		SQL.stmt("INSERT INTO route_points(route_id,seq,x,y) VALUES(?,0,0,0),(?,1,0.4,1),(?,2,0,3)",[route,route,route]),
		SQL.stmt("INSERT INTO location_aliases(location_id,alias,visibility,source_event_id) VALUES(?,'Stone Bridge','player',1),(?,'Private alias','private',1)",[bridge,bridge])
	])
	expect(fixture.get("ok",false),"Geography fixture failed")
	if not fixture.get("ok",false):
		finish()
		return
	expect(read_all(model,id),"Populated map read failed")
	var initial_map = model.data.duplicate(true)
	expect(initial_map["locations"].size()==3 and initial_map["travel"].is_empty() and initial_map["route_points"].size()==3,"Route confused with travel or hidden data leaked")
	expect(not JSON.stringify(initial_map).contains("Secret cave") and not JSON.stringify(initial_map).contains("Private bridge fact") and not JSON.stringify(initial_map).contains("Private alias"),"Private data in player projection")
	expect(model.search("Stone Bridge").get("locations",[]).size()==1 and model.search("Private alias").get("locations",[]).is_empty(),"Search privacy failed")
	expect(not model.annotate(hidden,"Hidden").get("ok",false),"Hidden annotation accepted")
	expect(model.annotate(bridge,"Remember the bridge.").get("ok",false),"B1 annotation save failed")
	expect(read_all(model,id) and model.data["annotations"].size()==1 and model.data["revision"]==0,"Annotation did not reload or changed canon revision")
	# Actual annotation append between pages cannot advance mechanical revision.
	var concurrent = MODEL.new()
	concurrent.start(id)
	expect(concurrent.accept_page(WORLD.new().map_view(id,0,1))=="more","Concurrent note fixture first page failed")
	expect(WORLD.new().add_annotation(id,bridge,"Second annotation during paging").get("ok",false),"Concurrent annotation save failed")
	expect(concurrent.accept_page(WORLD.new().map_view(id,1,1))=="error" and concurrent.data.is_empty(),"Concurrent annotation mixed map pages")
	expect(read_all(model,id) and model.data["annotations"].size()==2 and model.data["revision"]==0,"Annotation refresh changed mechanics or lost note")
	var engine = TURN.new()
	var token = engine.snapshot(id)
	var turn_id = players.make_id()
	var request_id = players.make_id()
	var refs = RAW.refs_for("travel")
	var action = {"handler_id":"travel","target_refs":[{"kind":"location","id":bridge}],"reference_refs":refs,"intent_text":"Walk to the bridge","arguments":{"route_id":route,"destination_id":bridge,"pace":"normal","fast_travel":false}}
	var packet = {"schema_version":"1","request_id":request_id,"turn_id":turn_id,"campaign_id":id,"actor_id":token["actor_id"],"expected_revision":token["revision"],"status":"proposed","actions":[action],"clarification":null,"rule_refs":refs}
	var approval = {"campaign_id":id,"actor_id":token["actor_id"],"turn_id":turn_id,"expected_revision":token["revision"],"action":action,"ruling":{"difficult":false,"clearance":"verified_unobstructed_supplied_foot_travel","establish_clock":true}}
	var resolver = RESOLVER.new()
	var resolved = resolver.resolve(id,token,request_id,turn_id,packet,refs,approval)
	expect(resolved.get("ok",false),"Resolved movement fixture failed: "+str(resolved.get("error","")))
	if not resolved.get("ok",false):
		finish()
		return
	expect(read_all(model,id),"Committed movement projection unavailable")
	expect(model.data["travel"].size()==1 and model.data["travel_points"].size()==3 and model.data["party_location"]["id"]==bridge,"Committed path/party projection wrong")
	var final_map = model.data.duplicate(true)
	var original_actor = base.actor_record(id)
	var original_log = base.read_log(id)
	for extent in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = extent
		var board = CANVAS.new()
		root.add_child(board)
		board.size = Vector2(extent)-Vector2(320,96)
		board.set_snapshot(final_map)
		await settle()
		expect(board.places.size()==3 and board.regions.size()==1 and board.travel_points.size()==1,"Canvas projection mismatch")
		expect(not MODEL.positioned(board.places[unplaced]),"Unresolved mill plotted")
		expect(board.at(board.places[bridge]).y<board.at(board.places[at_id]).y,"North axis inverted incorrectly")
		var measurement = MODEL.measure(board.places[at_id],board.places[bridge])
		expect(is_equal_approx(measurement.get("miles",-1),3.0) and is_equal_approx(measurement.get("uncertainty",-1),0.5),"Distance/uncertainty incorrect")
		expect(MODEL.measure(board.places[at_id],board.places[unplaced]).is_empty(),"Unresolved distance measured")
		var cursor = Vector2(180,180)
		var before_zoom = board.world_at(cursor)
		board.zoom(1.2,cursor)
		var after_zoom = board.world_at(cursor)
		expect(is_equal_approx(before_zoom[0],after_zoom[0]) and is_equal_approx(before_zoom[1],after_zoom[1]),"Pointer zoom drifted")
		board.set_region(region)
		expect(board.region_id==region and board.in_region(board.places[unplaced]),"Region projection failed")
		board.set_layer("Fog of War",false)
		board.set_layer("Party Path",false)
		expect(not board.layers["Fog of War"] and not board.layers["Party Path"] and not board.places.has(hidden),"Layer bypassed disclosure")
		expect(board.center_party(),"Positioned party could not centre")
		expect(board.clipped_segment(Vector2(-100,20),Vector2(100,20)).size()==2,"Visible segment clipped incorrectly")
		expect(board.clipped_segment(Vector2(-100,-100),Vector2(-80,-80)).is_empty(),"Offscreen segment retained")
		root.remove_child(board)
		board.queue_free()
		await settle()
		var intentions: Array = []
		var popup = ATLAS.new()
		popup.configure(id,"Atlas fixture",func(intent):
			intentions.append(intent)
			return {"ok":true,"message":"Fixture accepted intention only."}
		,model.revision)
		root.add_child(popup)
		popup.popup_centered(Vector2i(extent.x-36,extent.y-36))
		for i in range(40):
			await process_frame
			if not popup.is_loading and not popup.model.data.is_empty():
				break
		expect(not popup.is_loading and popup.model.data.get("locations",[]).size()==3,"Atlas failed actual MapView load")
		if popup.model.data.get("locations",[]).size()==3:
			popup.select_location(at_id)
			expect(not popup.travel_button.disabled,"Bound intention handler unavailable")
			popup.request_travel()
			expect(intentions.size()==1 and intentions[0].get("destination_id")==at_id and intentions[0].get("expected_revision")==model.revision,"Wrong intention payload")
			popup.intent_handler = Callable()
			popup.select_location(at_id)
			expect(popup.travel_button.disabled,"Unbound travel not disabled")
			popup.request_travel()
			expect(intentions.size()==1,"Unbound travel emitted")
			popup.search_box.text = "Stone Bridge"
			popup.search_locations()
			expect(popup.location_list.item_count==1,"Atlas alias search failed")
			popup.toggle_fullscreen()
			expect(popup.fullscreen_map,"Fullscreen mode failed")
			popup.toggle_fullscreen()
			expect(not popup.fullscreen_map,"Window restore failed")
			expect(popup.canvas.size.x>0 and popup.canvas.size.y>0,"Map canvas not laid out")
		root.remove_child(popup)
		popup.queue_free()
		await settle()
	expect(read_all(model,id) and model.data==final_map,"Map browsing or intention mutated geography")
	expect(base.actor_record(id)==original_actor and base.read_log(id)==original_log,"Map browsing changed actor or log")
	expect(players.load_record(master_id)==master and base.gameplay_view(sibling["id"])==sibling_before,"Master or sibling changed")
	var integrity = SQL.run(path,[SQL.stmt("PRAGMA integrity_check"),SQL.stmt("PRAGMA foreign_key_check")],true)
	expect(integrity.get("ok",false) and integrity["results"][0][0].get("integrity_check")=="ok" and integrity["results"][1].is_empty(),"Database integrity failed")
	finish()
