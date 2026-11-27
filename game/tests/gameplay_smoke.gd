extends SceneTree
## Run in explicitly authorized disposable user data; never use personal saves.
const STORE = preload("res://campaigns/campaign_store.gd")
const PLAYER = preload("res://players/character_store.gd")
const SQL = preload("res://systems/sqlite.gd")
const UI = preload("res://gameplay/game_workspace.gd")
const DICE = preload("res://gameplay/manual_dice.gd")
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func settle() -> void:
	for i in range(5): await process_frame

func inside(control: Control, bounds: Rect2, context: String) -> void:
	expect(is_instance_valid(control) and control.get_global_rect().has_area() and bounds.grow(2).encloses(control.get_global_rect()),context+" is clipped or absent")

func run() -> void:
	var expected = OS.get_environment("INFINITY_TEST_USER_ROOT").replace("\\","/").trim_suffix("/")
	var actual = ProjectSettings.globalize_path("user://").replace("\\","/").trim_suffix("/")
	if expected.is_empty() or expected!=actual or FileAccess.file_exists("user://players.db") or FileAccess.file_exists("user://settings.cfg") or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(STORE.ROOT)):
		push_error("Gameplay smoke requires an explicitly authorized empty disposable user directory.")
		quit(2)
		return
	var players = PLAYER.new()
	var master_id = players.make_id()
	var fixture = {"id":master_id,"name":"A Very Long Test Character Name of the Northern Lands","status":"ready","ruleset":"5e-2014-2018","race_id":"human","class_id":"wizard","level":1,"combat":{"hp_current":4,"hp_max":7,"armor_class":11,"speed_feet":30,"initiative":1,"passive_perception":12},"ability_scores":{"str":10,"dex":12,"con":12,"int":16,"wis":14,"cha":8},"ability_modifiers":{"str":0,"dex":1,"con":1,"int":3,"wis":2,"cha":-1},"proficiency_bonus":2,"coins":{"gp":17,"sp":2},"carried_weight_lb":6,"carrying_capacity_lb":150,"inventory":[{"item_id":"shortsword","quantity":1,"equipped":true},{"item_id":"backpack","quantity":1,"equipped":false}],"equipment":{"armor_id":"","shield_id":"","weapon_ids":["shortsword"]},"spellcasting":{"cantrip_ids":["fire-bolt"],"known_ids":["sleep"],"prepared_ids":["sleep"],"slots":{"1":{"maximum":2,"spent":1}},"save_dc":13,"attack_bonus":5},"skills":{"arcana":{"modifier":5,"proficient":true}}}
	var error = players.save_record(fixture)
	expect(error.is_empty(),"Master fixture save failed: "+error)
	var master = players.load_record(master_id)
	var store = STORE.new()
	var campaign = store.create_campaign("Gameplay fixture",master_id,"road","standard")
	expect(not campaign.is_empty(),"Campaign creation failed: "+store.last_error)
	if campaign.is_empty():
		finish()
		return
	var id = str(campaign["id"])
	var updated = SQL.run(store.path_for(id),[SQL.stmt("UPDATE inventory SET quantity=3 WHERE actor_id=? AND item_id='backpack'",[campaign["actor_id"]]),SQL.stmt("INSERT INTO events(turn,game_time,kind,payload) VALUES(0,?,'synopsis',?)",["Test",JSON.stringify({"text":"Not a chat event"})]),SQL.stmt("INSERT INTO events(turn,game_time,kind,payload) VALUES(0,?,'narration',?)",["Test",JSON.stringify({"text":"Committed dialogue fixture. ".repeat(120)})])])
	expect(updated.get("ok",false),"Fixture event/inventory update failed")
	var snapshot = store.gameplay_view(id)
	expect(not snapshot.is_empty() and snapshot.get("events",[]).size()==2,"Projection omitted committed events or included synopsis")
	var canonical = false
	for item in snapshot.get("inventory",[]):
		if item["item_id"]=="backpack": canonical = item["quantity"]==3
	expect(canonical,"Inventory read used stale actor payload")
	var original = snapshot.duplicate(true)
	for sides in DICE.SIDES:
		for count in [1,20]:
			var roll = DICE.roll(sides,count)
			var sum = 0
			for value in roll.get("values",[]):
				expect(value>=1 and value<=sides,"Die outside range")
				sum+=value
			expect(roll.get("values",[]).size()==count and roll.get("total")==sum,"Dice total/count mismatch")
	expect(DICE.roll(7,1).is_empty() and DICE.roll(20,0).is_empty() and DICE.roll(20,21).is_empty(),"Invalid dice accepted")
	for resolution in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = resolution
		var base = Control.new()
		base.size = Vector2(resolution)
		root.add_child(base)
		var called: Array[String] = []
		var ui = UI.new()
		ui.configure(snapshot,campaign,func(): called.append("leave"),func(): called.append("settings"),func(): called.append("retry"),false)
		base.add_child(ui)
		ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await settle()
		var bounds = base.get_global_rect()
		for control in [ui.nav_bar,ui.left_panel,ui.center_panel,ui.right_panel,ui.composer,ui.send_button,ui.dice_type,ui.dice_count,ui.dice_result,ui.log_scroll]:
			inside(control,bounds,str(resolution))
		expect(not ui.composer.editable and ui.send_button.disabled,"Future action input unexpectedly active")
		var columns_width = ui.left_panel.size.x+ui.center_panel.size.x+ui.right_panel.size.x
		expect(columns_width>0 and absf(ui.left_panel.size.x/columns_width-27.0/99.0)<0.05 and absf(ui.center_panel.size.x/columns_width-43.0/99.0)<0.05 and absf(ui.right_panel.size.x/columns_width-29.0/99.0)<0.05,"Column proportions differ from reference")
		expect(ui.inventory_cells.has("backpack") and ui.inventory_cells.has("shortsword"),"Normalized inventory cells missing")
		ui.select_item("backpack")
		expect(ui.inventory_detail.text.contains("Quantity: 3"),"Selected quantity not normalized")
		ui.roll_dice()
		expect(not ui.last_roll.is_empty(),"Manual UI roll failed")
		ui.dice_tool("Clear")
		expect(ui.last_roll.is_empty(),"Clear did not clear informational dice")
		for tab in ["Spells","Skills","Features","Notes","Inventory"]:
			ui.show_tab(tab)
			await settle()
			expect(ui.current_tab==tab and ui.right_content.get_child_count()>0,"Right panel switch failed")
		ui.navigate("Settings")
		ui.navigate("Campaign")
		expect(called==["settings","leave"],"Navigation callbacks failed")
		root.remove_child(base)
		base.queue_free()
		await settle()
	expect(store.gameplay_view(id)==original,"Read-only workspace changed campaign state")
	expect(players.load_record(master_id)==master,"Workspace modified master")
	finish()

func finish() -> void:
	for failure in failures: push_error(failure)
	print("Gameplay smoke failures: ",failures.size())
	quit(0 if failures.is_empty() else 1)
