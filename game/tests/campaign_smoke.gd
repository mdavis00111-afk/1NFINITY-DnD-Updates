extends SceneTree
## Use a disposable user directory; never run against the player's live database.
## Require INFINITY_TEST_USER_ROOT to equal the globalized user:// root exactly.
const SQL = preload("res://systems/sqlite.gd")
const STORE = preload("res://campaigns/campaign_store.gd")
const PLAYER = preload("res://players/character_store.gd")
const MATURITY = preload("res://campaigns/maturity_profiles.gd")
const STARTS = preload("res://campaigns/campaign_starts.gd")
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
	var profile = [{"id":"fixture","name":"Test only","instructions":"Test policy, not a shipped default."}]
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
	expect(campaigns.create_campaign("Bad opening",id,"invalid","fixture").is_empty(),"Unknown start accepted")
	var a = campaigns.create_campaign("First adventure",id,"tavern","fixture")
	var b = campaigns.create_campaign("Second adventure",id,"sea","fixture")
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
	var events = SQL.run(campaigns.path_for(a["id"]),[SQL.stmt("INSERT INTO events(turn,game_time,kind,payload) VALUES(1,?,'synopsis',?)",["Test",JSON.stringify({"text":"Verified summary fixture."})]),SQL.stmt("INSERT INTO events(turn,game_time,kind,payload) VALUES(2,?,'narration',?)",["Test",JSON.stringify({"text":"Later log fixture."})])])
	expect(events.get("ok",false),"Test log insert failed")
	expect(campaigns.synopsis(a["id"])=="Verified summary fixture.\n\nLater log fixture.","Synopsis did not prefer latest log summary")
	expect(not campaigns.synopsis(b["id"]).contains("fixture"),"Log leaked between campaigns")
	expect(not campaigns.update_thumbnail(a["id"],"../../invalid").is_empty(),"Invalid artwork accepted")
	expect(campaigns.update_thumbnail(a["id"],"woods").is_empty(),"Valid artwork save failed")
	expect(campaigns.load_campaign(a["id"]).get("thumbnail_id")=="woods","Thumbnail was not persisted")
	profile[0]["instructions"]="Updated test policy."
	expect(MATURITY.save_profiles(profile).is_empty() and MATURITY.resolve("fixture").get("instructions")=="Updated test policy.","Live profile update not resolved")
	expect(campaigns.delete_campaign(a["id"]).is_empty(),"Campaign delete failed")
	expect(campaigns.list_campaigns().size()==1 and campaigns.load_campaign(a["id"]).is_empty(),"Deleted campaign still visible")
	expect(campaigns.load_campaign(a["id"],true).get("status")=="deleted" and campaigns.db_exists(a["id"]),"Recovery database was lost")
	expect(master.load_record(id)==saved_master,"Campaign operation modified master character")
	finish()
