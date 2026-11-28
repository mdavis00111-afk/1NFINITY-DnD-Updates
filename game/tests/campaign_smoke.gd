extends SceneTree
## Use a disposable user directory; never run against the player's live database.
## Require INFINITY_TEST_USER_ROOT to equal the globalized user:// root exactly.
const SQL = preload("res://systems/sqlite.gd")
const STORE = preload("res://campaigns/campaign_store.gd")
const PLAYER = preload("res://players/character_store.gd")
const MATURITY = preload("res://campaigns/maturity_profiles.gd")
const OPENING = preload("res://campaigns/opening_scene.gd")
const NARRATOR = preload("res://campaigns/narrator_prompt.gd")
const STARTS = preload("res://campaigns/campaign_starts.gd")
const MANAGER = preload("res://campaigns/campaign_manager.gd")
const MAIN_SCENE = preload("res://main.tscn")
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func finish() -> void:
	for failure in failures:
		push_error(failure)
	print("Campaign smoke failures: ",failures.size())
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	var expected = OS.get_environment("INFINITY_TEST_USER_ROOT").replace("\\","/").trim_suffix("/")
	var actual = ProjectSettings.globalize_path("user://").replace("\\","/").trim_suffix("/")
	if expected.is_empty() or expected != actual or FileAccess.file_exists("user://players.db") or FileAccess.file_exists("user://settings.cfg") or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(STORE.ROOT)):
		push_error("Campaign smoke requires an explicitly authorized empty disposable user directory.")
		quit(2)
		return
	expect(STARTS.STARTS.size()==6,"Expected six opening choices")
	for start in STARTS.STARTS:
		expect(STARTS.valid_art(start["id"]) and STARTS.texture_for(start["id"])!=null,"Missing opening artwork")
	expect(not MATURITY.validate([{"id":"test"}]).is_empty(),"Incomplete maturity profile accepted")
	var profile = [{"id":"standard","name":"Standard","instructions":"Test policy for isolated settings."}]
	expect(MATURITY.save_profiles(profile).is_empty(),"Could not save isolated test profile")
	var master = PLAYER.new()
	var id = master.make_id()
	var fixture = {"id":id,"name":"Campaign Test Player","status":"ready","ruleset":"5e-2014-2018","level":1,"inventory":[{"item_id":"dagger","quantity":2,"equipped":true}],"combat":{"hp_max":8,"hp_current":8}}
	var error = master.save_record(fixture)
	expect(error.is_empty(),"Player fixture save failed: "+error)
	if not error.is_empty():
		finish()
		return
	var saved_master = master.load_record(id)
	var campaigns = STORE.new()
	expect(campaigns.create_campaign("Bad profile",id,"tavern","missing").is_empty(),"Missing maturity accepted")
	expect(campaigns.create_campaign("Bad opening",id,"invalid","standard").is_empty(),"Unknown start accepted")
	var a = campaigns.create_campaign("First adventure",id,"tavern","standard")
	var b = campaigns.create_campaign("Second adventure",id,"sea","family")
	expect(not a.is_empty() and not b.is_empty(),"Campaign creation failed: "+campaigns.last_error)
	if a.is_empty() or b.is_empty():
		finish()
		return
	expect(a["id"]!=b["id"] and a["actor_id"]!=b["actor_id"],"Campaign isolation IDs collide")
	expect(campaigns.list_campaigns().size()==2,"Campaign roster did not reload both campaigns")
	var actor = campaigns.actor_record(a["id"])
	expect(actor.get("master_character_id")==id and actor.get("id")!=id,"Player was not cloned")
	var inventory = SQL.run(campaigns.path_for(a["id"]),[SQL.stmt("SELECT quantity FROM inventory WHERE actor_id=?",[a["actor_id"]]),SQL.stmt("PRAGMA foreign_key_check")],true)
	expect(inventory.get("ok",false),"Inventory query failed")
	if inventory.get("ok",false):
		expect(inventory["results"][0].size()==1 and int(inventory["results"][0][0]["quantity"])==2,"Inventory clone wrong")
		expect(inventory["results"][1].is_empty(),"Foreign key violations")
	expect(campaigns.synopsis(a["id"]).contains("tavern"),"Opening not reflected in log")
	var proposal = {"start_id":"tavern","location_name":"The Copper Kettle","atmosphere":"Oak beams and lanterns.","npcs":[{"name":"Mara","occupation":"Innkeeper","attitude":0}],"world_facts":["The hearth is built of river stone."],"thumbnail_id":"tavern"}
	expect(NARRATOR.save_prompt("Custom opening narrator fixture.").is_empty(),"Could not edit Narrator settings")
	expect(MATURITY.save_guidance("family","Family-only fixture.").is_empty(),"Could not edit Family settings")
	var prepared = campaigns.prepare_opening(a["id"])
	var sibling_packet = campaigns.prepare_opening(b["id"])
	expect(not sibling_packet.is_empty(),"Sibling opening request not prepared")
	if not prepared.is_empty() and not sibling_packet.is_empty():
		var a_prompt = str(prepared["prompt"])
		var b_prompt = str(sibling_packet["prompt"])
		expect(a_prompt.contains("First adventure") and not a_prompt.contains("Second adventure") and not a_prompt.contains("Family-only fixture."),"Sibling context or profile leaked into first request")
		expect(b_prompt.contains("Second adventure") and b_prompt.contains("Family-only fixture.") and not b_prompt.contains("First adventure") and not b_prompt.contains("Test policy for isolated settings."),"First context or profile leaked into sibling request")
		expect(a_prompt.contains("Custom opening narrator fixture.") and b_prompt.contains("Custom opening narrator fixture."),"Saved Narrator guidance not applied")
		expect(prepared["response_schema"]==OPENING.response_schema("tavern") and sibling_packet["response_schema"]==OPENING.response_schema("sea"),"Opening schema not campaign-scoped")
		var sibling_before = campaigns.gameplay_view(b["id"])
		expect(not campaigns.commit_opening(b["id"],prepared["previous"],JSON.stringify(proposal)).is_empty(),"Cross-campaign opening accepted")
		expect(campaigns.gameplay_view(b["id"])==sibling_before,"Cross-campaign attempt changed sibling")
		expect(NARRATOR.save_prompt("Updated opening narrator fixture.").is_empty(),"Narrator edit failed")
		expect(str(campaigns.prepare_opening(b["id"]).get("prompt","")).contains("Updated opening narrator fixture."),"Retry ignored current prompt settings")
	expect(not prepared.is_empty(),"Opening request not prepared")
	if not prepared.is_empty():
		expect(str(prepared["prompt"]).contains("Test policy for isolated settings.") and str(prepared["prompt"]).contains("MANDATORY ENGINE AUTHORITY"),"Opening prompt missing profile or authority")
		var before = campaigns.actor_record(a["id"])
		var invalid = proposal.duplicate(true)
		invalid["hp"]=0
		expect(not campaigns.commit_opening(a["id"],prepared["previous"],JSON.stringify(invalid)).is_empty(),"Extra mechanical key accepted")
		invalid=proposal.duplicate(true)
		invalid["npcs"]=[]
		expect(OPENING.validate(JSON.stringify(invalid),"tavern").is_empty(),"Empty inhabited opening accepted")
		invalid=proposal.duplicate(true)
		invalid["npcs"][0]["attitude"]=0.5
		expect(OPENING.validate(JSON.stringify(invalid),"tavern").is_empty(),"Fractional attitude accepted")
		invalid=proposal.duplicate(true)
		invalid["thumbnail_id"]="../../invalid"
		expect(OPENING.validate(JSON.stringify(invalid),"tavern").get("thumbnail_id")=="tavern","Unsafe thumbnail did not fall back")
		expect(OPENING.validate(JSON.stringify(proposal),"sea").is_empty(),"Wrong starting scope accepted")
		expect(not campaigns.synopsis(a["id"]).contains("Copper Kettle"),"Invalid response leaked into log")
		expect(campaigns.commit_opening(a["id"],prepared["previous"],JSON.stringify(proposal)).is_empty(),"Valid opening did not commit")
		expect(not campaigns.commit_opening(a["id"],prepared["previous"],JSON.stringify(proposal)).is_empty(),"Opening replay accepted")
		expect(campaigns.actor_record(a["id"])==before,"Opening changed player state")
		var persisted = SQL.run(campaigns.path_for(a["id"]),[SQL.stmt("SELECT name,payload FROM locations WHERE id=?",[a["location_id"]]),SQL.stmt("SELECT id,payload FROM actors WHERE kind='npc'"),SQL.stmt("SELECT count(*) AS n FROM events WHERE kind='narration'"),SQL.stmt("PRAGMA foreign_key_check")],true)
		expect(persisted.get("ok",false),"Opening readback failed")
		if persisted.get("ok",false):
			expect(not persisted["results"][0].is_empty() and persisted["results"][0][0]["name"]=="The Copper Kettle" and str(persisted["results"][0][0]["payload"]).contains("river stone"),"Location facts not persisted")
			expect(persisted["results"][1].size()==1,"NPC not persisted exactly once")
			expect(int(persisted["results"][2][0]["n"])==1 and persisted["results"][3].is_empty(),"Opening log or foreign keys invalid")
		expect(campaigns.synopsis(a["id"]).contains("Copper Kettle") and not campaigns.synopsis(b["id"]).contains("Copper Kettle"),"Opening log isolation failed")
		expect(campaigns.load_campaign(a["id"]).get("opening_committed",false),"Opening completion flag missing")
	var stale_opening = campaigns.prepare_opening(b["id"])
	if not stale_opening.is_empty():
		expect(campaigns.update_thumbnail(b["id"],"road").is_empty(),"Could not change pending opening metadata")
		var sea = proposal.duplicate(true)
		sea["start_id"]="sea"
		expect(not campaigns.commit_opening(b["id"],stale_opening["previous"],JSON.stringify(sea)).is_empty(),"Stale opening accepted")
		expect(not campaigns.synopsis(b["id"]).contains("Copper Kettle"),"Stale opening wrote log")
	var events = SQL.run(campaigns.path_for(a["id"]),[SQL.stmt("INSERT INTO events(turn,game_time,kind,payload) VALUES(1,?,'synopsis',?)",["Test",JSON.stringify({"text":"Verified summary fixture."})]),SQL.stmt("INSERT INTO events(turn,game_time,kind,payload) VALUES(2,?,'narration',?)",["Test",JSON.stringify({"text":"Later log fixture."})])])
	expect(events.get("ok",false),"Test log insert failed")
	expect(campaigns.synopsis(a["id"])=="Verified summary fixture.\n\nLater log fixture.","Synopsis did not prefer latest log summary")
	expect(not campaigns.synopsis(b["id"]).contains("fixture"),"Log leaked between campaigns")
	expect(not campaigns.gameplay_view(a["id"]).get("opening_available",true),"Committed history still offers opening")
	# An older save with history but no opening flag must not offer a new scene.
	var legacy_history = SQL.run(campaigns.path_for(b["id"]),[SQL.stmt("INSERT INTO events(turn,game_time,kind,payload) VALUES(0,?,'synopsis',?)",["Test",JSON.stringify({"text":"Legacy summary"})])])
	expect(legacy_history.get("ok",false) and not campaigns.gameplay_view(b["id"]).get("opening_available",true) and campaigns.prepare_opening(b["id"]).is_empty(),"Legacy history allowed another opening")
	expect(not campaigns.update_thumbnail(a["id"],"../../invalid").is_empty(),"Invalid artwork accepted")
	expect(campaigns.update_thumbnail(a["id"],"woods").is_empty(),"Valid artwork save failed")
	expect(campaigns.load_campaign(a["id"]).get("thumbnail_id")=="woods","Thumbnail was not persisted")
	profile[0]["instructions"]="Updated test policy."
	expect(MATURITY.save_profiles(profile).is_empty() and MATURITY.resolve("standard").get("instructions")=="Updated test policy.","Live profile update not resolved")
	var stale = campaigns.load_campaign(a["id"])
	var stale_raw = campaigns.loaded_metadata
	var before_delete = SQL.run(campaigns.path_for(a["id"]),[SQL.stmt("SELECT count(*) AS n FROM events WHERE kind='campaign_deleted'")],true)
	expect(before_delete.get("ok",false),"Deletion baseline query failed")
	expect(campaigns.delete_campaign(a["id"]).is_empty(),"Campaign delete failed")
	stale["thumbnail_id"]="sea"
	expect(not campaigns.write_metadata(a["id"],stale_raw,stale).is_empty(),"Stale metadata resurrected deleted campaign")
	var deletion_count = SQL.run(campaigns.path_for(a["id"]),[SQL.stmt("SELECT count(*) AS n FROM events WHERE kind='campaign_deleted'")],true)
	expect(deletion_count.get("ok",false) and int(deletion_count["results"][0][0]["n"])==1,"Deletion event not committed exactly once")
	expect(campaigns.list_campaigns().size()==1 and campaigns.load_campaign(a["id"]).is_empty(),"Deleted campaign still visible")
	expect(campaigns.load_campaign(a["id"],true).get("status")=="deleted" and campaigns.db_exists(a["id"]),"Recovery database was lost")
	var failed_batch = SQL.run(campaigns.path_for(b["id"]),[SQL.stmt("UPDATE inventory SET quantity=7 WHERE actor_id=?",[b["actor_id"]]),SQL.stmt("UPDATE inventory SET quantity=0 WHERE actor_id=?",[b["actor_id"]])])
	expect(not failed_batch.get("ok",false),"Invalid inventory transaction succeeded")
	var after_rollback = SQL.run(campaigns.path_for(b["id"]),[SQL.stmt("SELECT quantity FROM inventory WHERE actor_id=?",[b["actor_id"]])],true)
	expect(after_rollback.get("ok",false) and int(after_rollback["results"][0][0]["quantity"])==2,"Failed transaction did not roll back")
	var actor_a = campaigns.load_campaign(a["id"],true)
	expect(actor_a.get("actor_id")==a["actor_id"],"Deleted actor metadata lost")
	# Exercise every start through the real store, rather than only inspecting labels/art.
	for start in STARTS.STARTS:
		var opening_id = str(start["id"])
		var fresh = campaigns.create_campaign("QA "+opening_id,id,opening_id,"family")
		expect(not fresh.is_empty(),"Could not create "+opening_id)
		if fresh.is_empty():
			continue
		var packet = campaigns.prepare_opening(fresh["id"])
		expect(not packet.is_empty(),"Could not prepare "+opening_id)
		if packet.is_empty():
			continue
		var scene = proposal.duplicate(true)
		scene["start_id"]=opening_id
		scene["thumbnail_id"]=""
		if opening_id in ["woods","road"]:
			scene["npcs"]=[]
		expect(campaigns.commit_opening(fresh["id"],packet["previous"],JSON.stringify(scene)).is_empty(),"Opening commit failed: "+opening_id)
		var reload = STORE.new().load_campaign(fresh["id"])
		expect(reload.get("opening_committed",false) and reload.get("thumbnail_id")==opening_id,"Opening reload failed: "+opening_id)
	await exercise_ui(campaigns)
	expect(master.load_record(id)==saved_master,"Campaign operation modified master character")
	finish()

func settle() -> void:
	for frame in range(5):
		await process_frame

func exercise_ui(campaigns) -> void:
	# The fixture settings contain no Gemini credentials. No network call.
	var last_id = ""
	for resolution in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=resolution
		var base = Control.new()
		base.size=Vector2(resolution)
		root.add_child(base)
		var manager = MANAGER.new()
		manager.configure("new",func(): pass,func(): pass)
		base.add_child(manager)
		manager.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await settle()
		var bounds = base.get_global_rect().grow(1.0)
		expect(manager.maturity_choice.selected==MATURITY.IDS.find("standard") and not manager.adult_confirmation.visible,"Standard default")
		for control in [manager.title_input,manager.maturity_choice,manager.synopsis]:
			expect(bounds.encloses(control.get_global_rect()) and control.get_global_rect().has_area(),"Campaign control outside viewport: "+str(resolution))
		manager.title_input.text="UI fixture "+str(resolution.x)
		var mature_index = MATURITY.IDS.find("mature")
		manager.maturity_choice.select(mature_index)
		manager.maturity_choice.item_selected.emit(mature_index)
		await settle()
		expect(manager.adult_confirmation.visible and bounds.encloses(manager.adult_confirmation.get_global_rect()),"Adult confirmation missing or clipped")
		var count_before = campaigns.list_campaigns().size()
		manager.create()
		expect(manager.mode=="new" and campaigns.list_campaigns().size()==count_before,"Unconfirmed Mature campaign created")
		manager.adult_confirmation.button_pressed=true
		manager.select_start("road")
		manager.create()
		await settle()
		expect(manager.mode=="workspace","Confirmed campaign did not open workspace")
		if manager.mode=="workspace":
			var created_id = str(manager.active["id"])
			last_id=created_id
			manager.create() # Stale/double create callback must not create a second campaign.
			expect(campaigns.list_campaigns().size()==count_before+1,"Duplicate create callback saved another campaign")
			expect(campaigns.load_campaign(created_id).get("maturity_id")=="mature","Maturity ID not saved")
			manager.request_opening()
			await settle()
			expect(manager.pending_campaign.is_empty() and is_instance_valid(manager.opening_button) and not manager.opening_button.disabled,"No-key failure did not enable retry")
			expect(not campaigns.load_campaign(created_id).get("opening_committed",false),"No-key failure changed saved opening")
			manager.leave()
			await settle()
			expect(manager.mode=="library" and manager.active.get("id")==created_id,"Save & Exit lost campaign selection")
			manager.resume()
			await settle()
			expect(manager.mode=="workspace" and manager.active.get("id")==created_id,"Resume failed")
			# Stage provider completions without credentials/network; use the same bound signal.
			var proposal = {"start_id":"road","location_name":"North Road","atmosphere":"A dry lane.","npcs":[],"world_facts":["A stone marker stands beside the road."],"thumbnail_id":"road"}
			var original = campaigns.gameplay_view(created_id)
			var other = campaigns.create_campaign("Other UI fixture "+str(resolution.x),manager.selected_player,"road","standard")
			var other_id = str(other.get("id",""))
			var other_before = campaigns.gameplay_view(other_id)
			var old_source = stage_reply(manager,campaigns,created_id)
			expect(is_instance_valid(old_source),"Could not stage canceled opening")
			if is_instance_valid(old_source) and not other.is_empty():
				manager.workspace.navigate("Campaign")
				expect(manager.pending_campaign.is_empty() and manager.mode=="library","Campaign navigation did not cancel pending opening")
				for i in range(manager.rows.size()):
					if manager.rows[i]["id"]==other_id: manager.select_campaign(i)
				manager.resume()
				var new_source = stage_reply(manager,campaigns,other_id)
				old_source.completed.emit(true,JSON.stringify(proposal))
				expect(manager.pending_campaign==other_id and campaigns.gameplay_view(created_id)==original and campaigns.gameplay_view(other_id)==other_before,"Canceled response leaked across campaigns")
				if is_instance_valid(new_source):
					new_source.completed.emit(false,"Stub failure")
				expect(manager.pending_campaign.is_empty() and campaigns.gameplay_view(other_id)==other_before,"Failed reply changed second campaign")
				manager.leave()
				for i in range(manager.rows.size()):
					if manager.rows[i]["id"]==created_id: manager.select_campaign(i)
				manager.resume()
			var invalid_source = stage_reply(manager,campaigns,created_id)
			if is_instance_valid(invalid_source):
				invalid_source.completed.emit(true,"not JSON")
			expect(campaigns.gameplay_view(created_id)==original and is_instance_valid(manager.opening_button) and not manager.opening_button.disabled,"Malformed reply changed opening or disabled retry")
			var valid_source = stage_reply(manager,campaigns,created_id)
			if is_instance_valid(valid_source):
				valid_source.completed.emit(true,JSON.stringify(proposal))
				valid_source.completed.emit(true,JSON.stringify(proposal))
			var committed = campaigns.gameplay_view(created_id)
			expect(committed.get("events",[]).size()==2 and committed.get("location",{}).get("name")=="North Road" and not committed.get("opening_available",true),"Opening failed to reload or remained eligible")
			expect(not is_instance_valid(manager.opening_button) and same_committed_view(manager.workspace.view,committed),"Workspace did not refresh committed log")
			var save = find_button(manager.workspace,"Save & Exit")
			expect(is_instance_valid(save),"Save & Exit missing")
			if is_instance_valid(save): save.pressed.emit()
			expect(manager.mode=="library" and manager.active.get("id")==created_id and manager.synopsis.text.contains("North Road"),"Save & Exit lost selection or synopsis")
			manager.resume()
			expect(same_committed_view(manager.workspace.view,committed) and not is_instance_valid(manager.opening_button),"Resume duplicated or lost opening")
			expect(campaigns.gameplay_view(other_id)==other_before,"Opening changed another campaign")
			# A concurrent successful opening invalidates a button rendered earlier.
			if not other_id.is_empty():
				manager.leave()
				for i in range(manager.rows.size()):
					if manager.rows[i]["id"]==other_id: manager.select_campaign(i)
				manager.resume()
				var external = campaigns.prepare_opening(other_id)
				expect(not external.is_empty() and is_instance_valid(manager.opening_button),"Stale retry fixture not eligible")
				if not external.is_empty():
					expect(campaigns.commit_opening(other_id,external["previous"],JSON.stringify(proposal)).is_empty(),"External opening commit failed")
					manager.request_opening()
					expect(manager.pending_campaign.is_empty() and same_committed_view(manager.workspace.view,campaigns.gameplay_view(other_id)) and not is_instance_valid(manager.opening_button),"Stale retry did not refresh committed opening")
					expect(campaigns.gameplay_view(created_id)==committed,"Stale retry changed sibling campaign")
		root.remove_child(base)
		base.queue_free()
		await settle()
	# Exercise actual main-menu Settings route, not just mock navigation callbacks.
	if last_id.is_empty():
		return
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await settle()
	main.show_screen("Existing Campaigns")
	await settle()
	var library = main.screen.get_child(0)
	for i in range(library.rows.size()):
		if library.rows[i]["id"]==last_id: library.select_campaign(i)
	library.resume()
	await settle()
	var committed_view = campaigns.gameplay_view(last_id)
	library.workspace.navigate("Settings")
	await settle()
	expect(main.active_screen=="Settings" and main.settings_campaign_id==last_id,"Main settings route lost campaign ID")
	main.show_screen("Edit Content Rules")
	await settle()
	var return_button = find_button(main.screen,"Return to Campaign")
	expect(is_instance_valid(return_button),"Content rules return route missing")
	if is_instance_valid(return_button): return_button.pressed.emit()
	await settle()
	expect(main.active_screen=="Game Workspace","Content rules did not return to gameplay")
	if main.active_screen=="Game Workspace":
		var returned = main.screen.get_child(0)
		expect(returned.mode=="workspace" and returned.active.get("id")==last_id and same_committed_view(returned.workspace.view,committed_view),"Settings returned to wrong campaign or lost log")
		returned.workspace.navigate("Settings")
		await settle()
		main.navigate("Return to Main")
		await settle()
		var again = main.screen.get_child(0)
		expect(again.mode=="workspace" and again.active.get("id")==last_id and same_committed_view(again.workspace.view,committed_view),"Settings menu return did not preserve exact campaign")
	root.remove_child(main)
	main.queue_free()
	await settle()

# Controller-bound views intentionally enrich interaction fields with queue and
# capability state. Compare the committed campaign content, not those fields.
func same_committed_view(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.is_empty() or expected.is_empty():
		return false
	for key in ["campaign","actor","inventory","events","location","opening_available"]:
		if not actual.has(key) or not expected.has(key) or actual[key]!=expected[key]:
			print("Committed workspace mismatch: ",key)
			return false
	return true

func stage_reply(manager, campaigns, id: String):
	var prepared = campaigns.prepare_opening(id)
	expect(not prepared.is_empty(),"Could not stage opening for "+id)
	if prepared.is_empty():
		return null
	manager.ensure_gemini()
	manager.pending_campaign=id
	manager.pending_metadata=prepared["previous"]
	if is_instance_valid(manager.opening_button):
		manager.opening_button.disabled=true
	return manager.gemini

func find_button(node: Node, caption: String) -> Button:
	if node is Button and node.text==caption:
		return node
	for child in node.get_children():
		var found = find_button(child,caption)
		if found!=null:
			return found
	return null
