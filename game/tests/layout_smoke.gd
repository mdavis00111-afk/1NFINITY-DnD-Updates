extends SceneTree
# Run after project import using an isolated user:// directory.
# godot --headless --path game --script res://tests/layout_smoke.gd
const CREATOR = preload("res://players/character_creator.gd")
const MANAGER = preload("res://players/character_manager.gd")
const BROWSER = preload("res://rules/catalog_browser.gd")
const CATALOGUE = preload("res://rules/catalog.gd")
const THEME = preload("res://themes/master_theme.tres")
const SQL = preload("res://systems/sqlite.gd")
const STORE = preload("res://players/character_store.gd")
const PORTRAIT_ART = preload("res://players/portrait_art.gd")
const RESOLUTIONS = [Vector2i(1280, 720), Vector2i(1920, 1080)]
const LONG_NAME = "Aurelia Brightwater of the High Silverwood and the Northern Marches"
const PROSE_LINE = "A line of narrative that should remain available in full. "
var failures: Array[String] = []
var saved_test_id = ""
var saved_test_portrait = ""


func _initialize() -> void:
	run.call_deferred()


func settle() -> void:
	for frame in range(5):
		await process_frame


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func inside(control: Control, viewport: Rect2, context: String) -> void:
	var bounds = control.get_global_rect()
	expect(control.is_visible_in_tree() and bounds.has_area(), context + " is invisible or collapsed")
	expect(viewport.grow(1.0).encloses(bounds), context + " exceeds " + str(viewport) + ": " + str(bounds))


func find_button(node: Node, caption: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == caption:
			return child
		var match_button = find_button(child, caption)
		if match_button != null:
			return match_button
	return null


func check_action(node: Node, caption: String, viewport: Rect2, context: String) -> Button:
	var button = find_button(node, caption)
	expect(button != null, context + " is missing " + caption)
	if button != null:
		inside(button, viewport, context + " " + caption)
	return button


func check_creator(creator: Control, viewport: Rect2, context: String) -> void:
	inside(creator.body, viewport, context + " frame")
	inside(creator.form, viewport, context + " form")
	inside(creator.reference, viewport, context + " reference")
	expect(creator.form.size.x >= 350, context + " form width collapsed")
	expect(creator.reference.size.x >= 175, context + " reference width collapsed")
	var parent = creator.form.get_parent()
	while parent != creator:
		expect(not parent is ScrollContainer, context + " central form is inside a scrolling viewport")
		parent = parent.get_parent()


func exercise_picker(creator: Control) -> void:
	var choices = [{"key":"cure","label":"Cure Wounds"},{"key":"fire","label":"Fire Bolt"}]
	var selected: Array[String] = []
	creator.choose_popup("Layout Test Picker", choices, func(id: String): selected.append(id), "cure")
	await settle()
	var overlay = creator.picker_overlay
	expect(is_instance_valid(overlay), "Choice dropdown did not open")
	if not is_instance_valid(overlay): return
	var panel = overlay.get_node_or_null("ChoiceDropdown")
	expect(panel != null, "Choice dropdown panel missing")
	if panel != null: inside(panel,creator.get_global_rect(),"Choice dropdown")
	var lists = overlay.find_children("*","ItemList",true,false)
	var searches = overlay.find_children("*","LineEdit",true,false)
	expect(not lists.is_empty() and not searches.is_empty(),"Choice dropdown lacks search or results")
	if lists.is_empty() or searches.is_empty():
		creator.close_picker()
		return
	var results: ItemList = lists.front()
	var search: LineEdit = searches.front()
	expect(results.item_count==2 and results.is_selected(0),"Choice dropdown did not show current choice")
	search.text = "fire"
	search.text_changed.emit(search.text)
	expect(results.item_count==1 and results.get_item_text(0)=="Fire Bolt","Choice search did not filter")
	results.item_selected.emit(0)
	await settle()
	expect(selected==["fire"] and not is_instance_valid(creator.picker_overlay),"Choice selection did not close or return the selected value")
	creator.choose_popup("Layout Test Picker",choices,func(id: String): selected.append(id))
	await settle()
	if is_instance_valid(creator.picker_overlay):
		var cancel_button = find_button(creator.picker_overlay,"Cancel")
		expect(cancel_button!=null,"Choice dropdown lacks cancel")
		if cancel_button!=null: cancel_button.pressed.emit()
	await settle()
	expect(selected==["fire"],"Choice cancel changed selection")


func exercise_creator(base: Control, role: String) -> Dictionary:
	var creator = CREATOR.new()
	creator.configure(false, func(): pass, func(): pass)
	creator.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.add_child(creator)
	await settle()
	var viewport = base.get_global_rect()
	var context = str(base.size) + " " + role
	var long_prose = PROSE_LINE.repeat(24)
	creator.draft["name"] = LONG_NAME
	creator.draft["description"] = long_prose
	creator.draft["backstory"] = long_prose
	if role == "fighter":
		creator.draft["race_id"] = "dwarf"
		creator.draft["subrace_id"] = "hill-dwarf"
		creator.draft["portrait"] = ProjectSettings.globalize_path("res://art/castle.jpg")
	else:
		creator.draft["race_id"] = "human"
	creator.draft["class_id"] = role
	creator.draft["background_id"] = "acolyte"
	creator.render()
	await settle()
	check_creator(creator, viewport, context + " identity")
	expect(creator.description_editor.text == long_prose, context + " editable description lost text")
	if role == "wizard" and base.size.x == 1280:
		await exercise_picker(creator)
		var details = {"description":"Example response from a test double.","personality":"Curious","ideal":"Truth","bond":"Home","flaw":"Impatient","backstory":"A traveller."}
		creator.description_received(true,JSON.stringify(details))
		for key in details:
			expect(creator.draft[key]==details[key] and creator.identity_editors[key].text==details[key],"AI response did not fill "+key)
		var before = creator.draft.duplicate(true)
		creator.description_received(true,JSON.stringify({"description":"Incomplete"}))
		expect(creator.draft==before,"Incomplete AI response changed the draft")
		creator.description_editor.text = long_prose
		creator.description_editor.text_changed.emit()
		creator.description_received(false, "Example error from a test double.")
		expect(creator.description_editor.text == long_prose and not creator.ai_button.disabled, "AI failure changed the draft or left its button disabled")
	check_action(creator, "Choose Portrait", viewport, context + " identity")
	check_action(creator, "Save Draft", viewport, context + " identity")
	var next = check_action(creator, "Next", viewport, context + " identity")
	if next != null:
		next.pressed.emit()
		await settle()
	expect(creator.step == 2, context + " valid identity did not advance")
	for ability in ["STR","DEX","CON","INT","WIS","CHA"]:
		check_action(creator,ability,viewport,context+" pre-roll card")
	expect(creator.draft["ability_method"].is_empty() and creator.draft["roll_history"].is_empty(),"Pre-roll view mutated dice state")
	for mode in [["roll", "Roll 4d6, Drop Lowest"], ["point", "Point Buy 27"], ["array", "Standard Array"]]:
		var mode_button = check_action(creator, mode[1], viewport, context + " abilities")
		if mode_button != null:
			mode_button.pressed.emit()
			await settle()
		check_creator(creator, viewport, context + " abilities " + mode[0])
		expect(creator.draft["ability_method"] == mode[0], context + " score method did not update")
		expect(creator.rules.validate_step(creator.draft, 2).is_empty(), context + " invalid " + mode[0] + " score state")
		if mode[0] == "roll":
			var reroll = check_action(creator, "Reroll", viewport, context + " abilities")
			var rolls = creator.draft["roll_history"].duplicate(true)
			if reroll != null:
				reroll.pressed.emit()
				await settle()
			expect(creator.draft["roll_history"].size() == 6 and creator.draft["roll_history"] != rolls, context + " reroll did not refresh six dice records")
			var totals: Array = []
			for dice in creator.draft["roll_history"]:
				expect(dice.size()==4,"Ability roll did not use four dice")
				var sorted = dice.duplicate()
				for die in sorted: expect(int(die)>=1 and int(die)<=6,"Die outside d6 range")
				sorted.sort()
				if sorted.size()==4: totals.append(int(sorted[1])+int(sorted[2])+int(sorted[3]))
			totals.sort()
			var pool = creator.draft["roll_pool"].duplicate()
			pool.sort()
			expect(totals==pool,"Recorded pool does not equal 4d6 drop lowest")
	next = check_action(creator, "Next", viewport, context + " abilities")
	if next != null:
		next.pressed.emit()
		await settle()
	expect(creator.step == 3, context + " valid abilities did not advance")
	creator.auto_fill(3)
	creator.render()
	await settle()
	check_creator(creator, viewport, context + " skills and spells")
	next = check_action(creator, "Next", viewport, context + " skills and spells")
	if next != null:
		next.pressed.emit()
		await settle()
	expect(creator.step == 4, context + " valid skill and spell selections did not advance")
	creator.auto_fill(4)
	creator.render()
	await settle()
	check_creator(creator, viewport, context + " loadout")
	check_action(creator, "Save Character", viewport, context + " loadout")
	var begin = check_action(creator, "Begin Adventure", viewport, context + " loadout")
	expect(begin != null and begin.disabled, context + " adventure action must stay disabled")
	var record: Dictionary = creator.rules.full_record(creator.draft)
	expect(not record.get("inventory", []).is_empty(), context + " finished record has no inventory")
	var back = check_action(creator, "Back", viewport, context + " loadout")
	if back != null:
		back.pressed.emit()
		await settle()
	expect(creator.step == 3, context + " back navigation did not return to skills and spells")
	expect(creator.draft["name"] == LONG_NAME and creator.draft["description"] == long_prose, context + " navigation lost draft data")
	if role == "fighter" and base.size.x == 1280 and check_persistence_enabled():
		await exercise_save(base, creator, long_prose)
	base.remove_child(creator)
	creator.queue_free()
	return record


func check_persistence_enabled() -> bool:
	var isolated_directory = OS.get_environment("XDG_DATA_HOME")
	return OS.get_environment("INFINITY_TEST_TRANSPORT") != "" and not isolated_directory.is_empty() and ProjectSettings.globalize_path("user://").begins_with(isolated_directory + "/")


func exercise_save(base: Control, creator: Control, long_prose: String) -> void:
	var viewport = base.get_global_rect()
	var save_draft = check_action(creator, "Save Draft", viewport, "Persistence")
	if save_draft == null:
		return
	save_draft.pressed.emit()
	await settle()
	var store = STORE.new()
	saved_test_id = str(creator.existing.get("id", ""))
	var saved = store.load_record(saved_test_id)
	expect(saved.get("status") == "draft", "Draft did not persist")
	expect(saved.get("draft", {}).get("description") == long_prose, "Draft description differed after reload")
	saved_test_portrait = str(saved.get("draft", {}).get("portrait", ""))
	expect(saved_test_portrait.begins_with("user://players/v1/portraits/") and FileAccess.file_exists(saved_test_portrait), "Draft portrait was not copied to user storage")
	if saved.is_empty():
		return

	var finished: Array[bool] = []
	var resumed = CREATOR.new()
	resumed.configure(false, func(): pass, func(): finished.append(true), saved)
	resumed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.remove_child(creator)
	base.add_child(resumed)
	await settle()
	expect(resumed.draft["description"] == long_prose and resumed.draft["portrait"] == saved_test_portrait, "Resume did not restore draft fields")
	resumed.step = 4
	resumed.render()
	await settle()
	var finalize = check_action(resumed, "Save Character", viewport, "Persistence")
	if finalize != null:
		finalize.pressed.emit()
		await settle()
	saved = store.load_record(saved_test_id)
	var finalized = finished == [true] and saved.get("status") in ["ready", "needs_review"]
	expect(finalized, "Final save did not complete under the same character ID: " + resumed.note.text)
	if finalized:
		expect(saved.get("portrait") == saved_test_portrait and FileAccess.file_exists(saved_test_portrait), "Final record lost its saved portrait")
	else:
		saved_test_id = ""
	base.remove_child(resumed)
	resumed.queue_free()
	base.add_child(creator)


func exercise_archive(base: Control) -> void:
	if saved_test_id.is_empty():
		return
	var manager = MANAGER.new()
	manager.configure(func(_record): pass, func(): pass, func(): pass)
	manager.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.add_child(manager)
	await settle()
	expect(manager.active.get("id") == saved_test_id, "Opening the manager did not reload the finalized record")
	if manager.active.get("id") == saved_test_id:
		manager.archive_button.pressed.emit()
		await settle()
		var dialogs = manager.find_children("*", "ConfirmationDialog", true, false)
		expect(not dialogs.is_empty(), "Archive confirmation dialog did not open")
		if not dialogs.is_empty():
			dialogs.back().confirmed.emit()
			await settle()
			expect(manager.records.is_empty(), "Archived record remains available in manager")
			var archive = SQL.run(STORE.DB, [SQL.stmt("SELECT payload FROM archived_players WHERE id=?", [saved_test_id])], true)
			var rows = archive.get("results", [[]])[0]
			expect(archive.get("ok", false) and rows.size() == 1, "Archiving did not retain the finalized record payload")
			if not rows.is_empty():
				var archived = JSON.parse_string(rows[0]["payload"])
				expect(archived is Dictionary and archived.get("id") == saved_test_id and archived.get("status") in ["ready", "needs_review"], "Archive payload does not identify the finalized record")
			expect(FileAccess.file_exists(saved_test_portrait), "Archiving deleted the player portrait")
	base.remove_child(manager)
	manager.queue_free()
	print("Layout smoke exercised save, reload and archive in isolated user data.")


func exercise_viewer(base: Control, records: Array) -> void:
	var edited: Array[String] = []
	var manager = MANAGER.new()
	manager.configure(func(record: Dictionary): edited.append(record["name"]), func(): pass, func(): pass)
	manager.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.add_child(manager)
	await settle()
	var viewport = base.get_global_rect()
	inside(manager.roster_scroll, viewport, "Player portrait roster")
	inside(manager.toolbar,viewport,"Bottom actions")
	expect(find_button(manager,"Delete") != null and find_button(manager,"Archive") == null and find_button(manager,"Rules Catalogue") == null,"Manager action labels differ from approved controls")
	expect(manager.toolbar.get_global_rect().position.y>manager.scroll.get_global_rect().position.y,"Manager actions not below sheet")
	inside(manager.scroll, viewport, "Sheet viewport")
	expect(manager.scroll.size.x >= 700 and manager.scroll.size.y >= 400, "Sheet viewport collapsed")
	manager.records = records
	manager.rebuild_roster()
	manager.select_record(0)
	expect(manager.roster_buttons.size()==records.size(),"Roster does not contain all saved characters")
	await settle()
	expect(manager.body.get_child_count() >= 2, "Sheet content is missing")
	if manager.body.get_child_count() >= 2:
		var sheet = manager.body.get_child(1)
		expect(sheet.get_child_count() >= 5, "Sheet sections missing")
		expect(sheet.number(14.0) == "14" and sheet.number(-1.0, true) == "-1" and sheet.number(1.0, true) == "+1", "Integer display regression")
	expect(is_equal_approx(manager.sheet_scale(),0.70),"Sheet does not default to fixed 70 percent")
	expect(manager.canvas.get_global_rect().size.x <= manager.scroll.size.x,"Sheet exceeds viewport")
	expect(absf(manager.canvas.position.x-(manager.sheet_extent.size.x-manager.canvas.size.x*manager.sheet_scale())*0.5)<2.0,"Sheet is not centered")
	expect(not manager.scroll.get_h_scroll_bar().visible,"Fixed sheet requires horizontal scrolling")
	manager.scroll.scroll_vertical = 100
	await settle()
	expect(manager.scroll.scroll_vertical>0,"Sheet cannot scroll vertically")
	expect(find_button(manager,"Fit width")==null and find_button(manager,"+")==null,"Unwanted zoom controls remain")

	manager.roster_buttons[1].pressed.emit()
	await settle()
	expect(manager.active == records[1], "Changing selection did not load the second record")
	var portraits = manager.body.find_children("*", "TextureRect", true, false)
	var loaded_portrait = false
	for candidate in portraits:
		if candidate.texture is ImageTexture:
			loaded_portrait = true
	expect(loaded_portrait, "Sheet did not display the selected local portrait")
	manager.edit_button.pressed.emit()
	expect(edited == [LONG_NAME], "Edit did not call back with the active record")
	base.remove_child(manager)
	manager.queue_free()


func exercise_catalogue(base: Control) -> void:
	var browser = BROWSER.new()
	browser.configure(func(): pass)
	browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.add_child(browser)
	await settle()
	var viewport = base.get_global_rect()
	inside(browser.results, viewport, "Catalogue list")
	inside(browser.detail, viewport, "Catalogue reference")
	expect(browser.results.size.x >= 300 and browser.results.size.y >= 100, "Catalogue list collapsed")
	expect(browser.detail.size.x >= 230 and browser.detail.size.y >= 100, "Catalogue reference collapsed")
	base.remove_child(browser)
	browser.queue_free()


func run() -> void:
	var catalogue = CATALOGUE.new()
	if not catalogue.initialize():
		push_error("Layout smoke requires a populated rules catalogue: " + catalogue.last_error)
		quit(1)
		return
	var default_art = PORTRAIT_ART.texture_for("")
	expect(default_art is ImageTexture and default_art.get_width()>0 and default_art.get_height()>0,"Default sample portrait extraction failed")
	seed(1001)
	for resolution in RESOLUTIONS:
		root.size = resolution
		var base = Control.new()
		base.theme = THEME
		base.size = Vector2(resolution)
		root.add_child(base)
		var caster = await exercise_creator(base, "wizard")
		var martial = await exercise_creator(base, "fighter")
		await exercise_viewer(base, [caster, martial])
		if resolution.x == 1280 and check_persistence_enabled():
			await exercise_archive(base)
		await exercise_catalogue(base)
		root.remove_child(base)
		base.queue_free()
	for failure in failures:
		push_error(failure)
	print("Layout smoke test failures: ", failures.size())
	quit(0 if failures.is_empty() else 1)
