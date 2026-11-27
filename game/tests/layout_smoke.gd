extends SceneTree
# Run after importing the project: godot --headless --path game --script res://tests/layout_smoke.gd
const CREATOR = preload("res://players/character_creator.gd")
const MANAGER = preload("res://players/character_manager.gd")
const BROWSER = preload("res://rules/catalog_browser.gd")
var failures: Array = []

func _initialize() -> void:
	run.call_deferred()

func settle() -> void:
	for i in range(5):
		await process_frame

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func check_creator(stage: int, creator: Control) -> void:
	expect(creator.size.x >= 1000, "Creator root has collapsed")
	expect(creator.reference.size.x >= 230, "Reference panel width collapsed at step "+str(stage))
	expect(creator.reference.size.y >= 120, "Reference panel height collapsed at step "+str(stage))
	expect(creator.scroll.size.x >= 350, "Form width collapsed at step "+str(stage))
	expect(creator.scroll.size.y >= 120, "Form height collapsed at step "+str(stage))

func run() -> void:
	root.size = Vector2i(1280,720)
	var base = Control.new()
	base.theme = load("res://themes/master_theme.tres") as Theme
	base.size = Vector2(1280,720)
	root.add_child(base)
	var creator = CREATOR.new()
	creator.configure(false,func(): pass,func(): pass)
	creator.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.add_child(creator)
	await settle()
	check_creator(1,creator)
	creator.draft["race_id"]="human"
	creator.draft["class_id"]="wizard"
	creator.draft["background_id"]="acolyte"
	creator.rules.roll_scores(creator.draft,"array")
	for stage in range(2,5):
		creator.step=stage
		creator.render()
		await settle()
		check_creator(stage,creator)
	base.remove_child(creator)
	creator.queue_free()
	var manager = MANAGER.new()
	manager.configure(func(_record): pass,func(): pass,func(): pass)
	manager.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.add_child(manager)
	await settle()
	expect(manager.list.size.x >= 160 and manager.list.size.y >= 30,"Player picker collapsed")
	expect(manager.scroll.size.x >= 1000 and manager.scroll.size.y >= 400,"Full sheet viewport collapsed")
	# Test the viewer without changing real player saves.
	var record: Dictionary = {}
	if record.is_empty():
		var rules = preload("res://rules/character_rules.gd").new()
		var draft = rules.fresh()
		draft["name"] = "Layout Test"
		draft["race_id"] = "human"
		draft["class_id"] = "wizard"
		draft["background_id"] = "acolyte"
		rules.roll_scores(draft,"array")
		record = rules.full_record(draft)
	manager.records = [record]
	manager.select_record(0)
	await settle()
	var sheet = manager.body.get_child(1)
	expect(sheet.size.x >= 1000,"Full sheet width collapsed")
	expect(sheet.get_child_count() >= 5,"Sheet sections missing")
	expect(sheet.number(14.0)=="14" and sheet.number(-1.0,true)=="-1" and sheet.number(1.0,true)=="+1","Integer display regression")
	base.remove_child(manager)
	manager.queue_free()
	var browser = BROWSER.new()
	browser.configure(func(): pass)
	browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.add_child(browser)
	await settle()
	expect(browser.results.size.x >= 300 and browser.results.size.y >= 100,"Catalogue list collapsed")
	expect(browser.detail.size.x >= 230 and browser.detail.size.y >= 100,"Catalogue reference collapsed")
	for failure in failures:
		push_error(failure)
	print("Layout smoke test failures: ",failures.size())
	quit(0 if failures.is_empty() else 1)
