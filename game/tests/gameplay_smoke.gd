extends SceneTree
## Run in explicitly authorized disposable user data; never use personal saves.
const STORE = preload("res://campaigns/campaign_store.gd")
const PLAYER = preload("res://players/character_store.gd")
const SQL = preload("res://systems/sqlite.gd")
const UI = preload("res://gameplay/game_workspace.gd")
const DICE = preload("res://gameplay/manual_dice.gd")
const DISPLAY = preload("res://gameplay/display_values.gd")
const CATALOG = preload("res://rules/catalog.gd")
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func settle() -> void:
	for i in range(5): await process_frame

func inside(control: Control, bounds: Rect2, context: String) -> void:
	expect(is_instance_valid(control) and control.get_global_rect().has_area() and bounds.grow(2).encloses(control.get_global_rect()),context+" is clipped or absent")

func has_text(node: Node, fragment: String) -> bool:
	if node is Label or node is Button or node is RichTextLabel:
		if str(node.get("text")).contains(fragment):
			return true
	for child in node.get_children():
		if has_text(child,fragment):
			return true
	return false

func run() -> void:
	var expected = OS.get_environment("INFINITY_TEST_USER_ROOT").replace("\\","/").trim_suffix("/")
	var actual = ProjectSettings.globalize_path("user://").replace("\\","/").trim_suffix("/")
	if expected.is_empty() or expected!=actual or FileAccess.file_exists("user://players.db") or FileAccess.file_exists("user://settings.cfg") or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(STORE.ROOT)):
		push_error("Gameplay smoke requires an explicitly authorized empty disposable user directory.")
		quit(2)
		return
	var players = PLAYER.new()
	var master_id = players.make_id()
	var fixture = {"id":master_id,"name":"A Very Long Test Character Name of the Northern Lands","status":"ready","ruleset":"5e-2014-2018","race_id":"human","class_id":"wizard","level":1,"combat":{"hp_current":4,"hp_max":7,"armor_class":11,"speed_feet":30,"initiative":1,"passive_perception":12},"ability_scores":{"str":10,"dex":12,"con":12,"int":16,"wis":14,"cha":8},"ability_modifiers":{"str":0,"dex":1,"con":1,"int":3,"wis":2,"cha":-1},"proficiency_bonus":2,"coins":{"pp":0,"gp":17,"ep":0,"sp":2,"cp":0},"carried_weight_lb":6,"carrying_capacity_lb":150,"inventory":[{"item_id":"shortsword","quantity":1,"equipped":true},{"item_id":"backpack","quantity":1,"equipped":false},{"item_id":"arrow","quantity":20,"equipped":false}],"equipment":{"armor_id":"","shield_id":"shield","weapon_ids":["shortsword","backpack"]},"spellcasting":{"cantrip_ids":["fire-bolt"],"known_ids":["sleep"],"prepared_ids":["sleep"],"slots":{"1":{"maximum":2,"spent":1}},"save_dc":13,"attack_bonus":5},"skills":{"arcana":{"modifier":5,"proficient":true}}}
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
	var projected = snapshot.get("actor",{})
	var load = projected.get("carried_weight_lb")
	expect(load!=null and is_equal_approx(float(load),18.38),"Current load must include three backpacks, shortsword, 20 arrows and 19 coins")
	expect(projected.get("equipment",{}).get("weapon_ids")==["shortsword"] and projected.get("equipment",{}).get("shield_id")=="","Stale or unequipped slot item displayed")
	expect(projected.get("combat")==master.get("combat") and projected.get("skills")==master.get("skills") and projected.get("spellcasting")==master.get("spellcasting") and projected.get("coins")==master.get("coins"),"Projection altered committed actor statistics")
	var catalogue = CATALOG.new()
	for pair in [["arrow",0.05],["crossbow-bolt",0.075],["blowgun-needle",0.02],["sling-bullet",0.075]]:
		var unit = DISPLAY.unit_weight(catalogue,pair[0])
		expect(unit!=null and is_equal_approx(float(unit),pair[1]),"Incorrect per-projectile weight: "+pair[0])
	var incomplete = DISPLAY.weight_summary(catalogue,[{"item_id":"missing-test-item","quantity":1}],{})
	expect(not incomplete["complete"] and incomplete["missing"].has("missing-test-item"),"Unknown weight silently treated as complete")
	expect(DISPLAY.remaining_text(2,1)=="1 / 2" and DISPLAY.remaining_text(2,2)=="0 / 2" and DISPLAY.remaining_text(2,3)=="— / 2" and DISPLAY.remaining_text(2,null)=="— / 2","Invalid slot/resource display")
	var racial_fixture = {"spellcasting":{"racial_cantrip_ids":["fire-bolt"],"racial_casting_ability":"int","save_dc":12},"ability_modifiers":{"int":3},"proficiency_bonus":2}
	expect(DISPLAY.racial_spell_text(racial_fixture).contains("Save DC 13") and DISPLAY.racial_spell_text(racial_fixture).contains("Attack +5"),"Racial spell ability incorrectly shares class DC")
	var original = snapshot.duplicate(true)
	var raw_actor = store.actor_record(id)
	expect(raw_actor.get("carried_weight_lb")==6,"Read projection unexpectedly rewrote cached actor load")
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
		for caption in ["4 / 7","30 ft.","Weight: 18.38 / 150 lb","17 gp","2 sp","Passive Perception","Proficiency"]:
			expect(has_text(ui,caption),"Missing displayed campaign value: "+caption)
		var columns_width = ui.left_panel.size.x+ui.center_panel.size.x+ui.right_panel.size.x
		expect(columns_width>0 and absf(ui.left_panel.size.x/columns_width-27.0/99.0)<0.05 and absf(ui.center_panel.size.x/columns_width-43.0/99.0)<0.05 and absf(ui.right_panel.size.x/columns_width-29.0/99.0)<0.05,"Column proportions differ from reference")
		expect(ui.inventory_cells.has("backpack") and ui.inventory_cells.has("shortsword"),"Normalized inventory cells missing")
		ui.select_item("backpack")
		expect(ui.inventory_detail.text.contains("Quantity: 3") and ui.inventory_detail.text.contains("Stack weight: 15 lb"),"Selected quantity or stack weight not normalized")
		expect(ui.equipped("shortsword") and not ui.equipped("backpack"),"Equipment filter not based on normalized inventory")
		ui.select_item("arrow")
		expect(ui.inventory_detail.text.contains("Unit weight: 0.05 lb") and ui.inventory_detail.text.contains("Stack weight: 1 lb") and ui.inventory_detail.text.contains("per 20"),"Ammunition display uses lot as individual")
		ui.roll_dice()
		expect(not ui.last_roll.is_empty(),"Manual UI roll failed")
		ui.dice_tool("Clear")
		expect(ui.last_roll.is_empty(),"Clear did not clear informational dice")
		for tab in ["Spells","Skills","Features","Notes","Inventory"]:
			ui.show_tab(tab)
			await settle()
			expect(ui.current_tab==tab and ui.right_content.get_child_count()>0,"Right panel switch failed")
			if tab=="Spells":
				expect(has_text(ui.right_content,"Class Save DC 13") and has_text(ui.right_content,"Attack +5") and has_text(ui.right_content,"Level 1 slots: 1 / 2"),"Spell statistics not displayed from actor")
			elif tab=="Skills":
				expect(has_text(ui.right_content,"◆ Arcana   +5"),"Stored skill modifier or proficiency missing")
		ui.navigate("Settings")
		ui.navigate("Campaign")
		expect(called==["settings","leave"],"Navigation callbacks failed")
		root.remove_child(base)
		base.queue_free()
		await settle()
	expect(store.gameplay_view(id)==original,"Read-only workspace changed campaign state")
	expect(store.actor_record(id)==raw_actor,"Read-only workspace changed underlying actor payload")
	expect(players.load_record(master_id)==master,"Workspace modified master")
	finish()

func finish() -> void:
	for failure in failures: push_error(failure)
	print("Gameplay smoke failures: ",failures.size())
	quit(0 if failures.is_empty() else 1)
