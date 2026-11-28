extends Control

const CHANNEL = "https://raw.githubusercontent.com/mdavis00111-afk/1NFINITY-DnD-Updates/godot/channel.json"
const GOLD = Color("#f4ce7b")
const MUTED = Color("#a8997e")
const GEMINI = preload("res://systems/gemini.gd")
const THEME_PATH = "res://themes/master_theme.tres"
const CONFIG_PATH = "user://settings.cfg"
const LOG_COPY_LIMIT = 256 * 1024
var version: String = ""
var status: Label
var check_button: Button
var request: HTTPRequest
var remote: Dictionary = {}
var dialog: ConfirmationDialog
var update_version: Label
var update_notes: RichTextLabel
var screen: Control
var campaign_screen: Control
var backdrop: TextureRect
var copy_log_button: Button
var log_feedback: Timer
var config = ConfigFile.new()
var active_screen = "Main"
var busy = false
var fullscreen = true

const NAV = {
	"Main": ["Player", "Campaign", "Settings", "Full Screen", "Exit"],
	"Settings": ["Set and Store API", "Edit AI Prompts", "Edit Content Rules", "Rules Library", "Rules Catalogue", "Update from GitHub", "Return to Main"],
	"Player Manager": ["Create New", "Manage Players", "Exit"],
	"Campaign Manager": ["New Campaign", "Existing Campaigns"]
}
const RULES = preload("res://rules/library.gd")
const MASTER = preload("res://rules/master_reference.gd")
var master = MASTER.new()
const MECHANICS = preload("res://rules/mechanics.gd")
const SHEET = preload("res://players/character_sheet.gd")
const CREATOR = preload("res://players/character_creator.gd")
const MANAGER = preload("res://players/character_manager.gd")
const BROWSER = preload("res://rules/catalog_browser.gd")
const CAMPAIGN = preload("res://campaigns/campaign_manager.gd")
const MATURITY = preload("res://campaigns/maturity_profiles.gd")
const NARRATOR = preload("res://campaigns/narrator_prompt.gd")
var editing_record: Dictionary = {}
var browser_return: String = "Settings"
var settings_campaign_id = ""
var library = RULES.new()
const DETAILS = {
	"Quick Generate Player": "Choose race, class and gender; generate remaining legal fields. RAW character generation is not connected yet.",
	"Create Player": "Full D&D 5e character creation, character sheet and live dice rolls. Rules engine pending.",
	"Manage / Edit Players": "Select and edit a saved player. Player storage pending.",
	"Delete Players": "Select a saved player to delete. Player storage pending.",
	"Create New Campaign": "Select a player and configure a new sandbox campaign. Campaign engine pending.",
	"Resume Existing Campaign": "Select a saved campaign to resume. Campaign storage pending.",
	"Delete Campaign": "Select a campaign to delete. Campaign storage pending.",
	"Edit Content Rules": "Content rule editor shell. Legacy Python format must be reviewed before Gemini integration."
}

func _ready() -> void:
	# The project theme is loaded only at runtime, after editor asset import.
	var imported_theme = ResourceLoader.load(THEME_PATH, "Theme") as Theme
	if imported_theme == null or imported_theme.default_font == null:
		push_error("Game theme or imported font unavailable. Run asset import again.")
		get_tree().quit(1)
		return
	theme = imported_theme
	version = FileAccess.get_file_as_string("res://version.txt").strip_edges()
	config.load(CONFIG_PATH)
	var prompt_error = NARRATOR.seed_default()
	if prompt_error.is_empty():
		config.load(CONFIG_PATH)
	else:
		push_warning(prompt_error)
	fullscreen = bool(config.get_value("display", "fullscreen", false))
	if OS.get_cmdline_user_args().has("recovery-windowed") or DisplayServer.get_name() == "headless":
		fullscreen = false
	if fullscreen:
		get_window().mode = Window.MODE_FULLSCREEN
	request = HTTPRequest.new()
	request.timeout = 20.0
	request.use_threads = true
	add_child(request)
	request.request_completed.connect(on_response)
	dialog = ConfirmationDialog.new()
	dialog.title = "Install update"
	add_child(dialog)
	dialog.confirmed.connect(install_update)
	var update_content = VBoxContainer.new()
	dialog.add_child(update_content)
	update_version = Label.new()
	update_content.add_child(update_version)
	update_notes = RichTextLabel.new()
	update_notes.custom_minimum_size.y = 120
	update_notes.fit_content = false
	update_notes.scroll_active = true
	update_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	update_notes.selection_enabled = true
	var notes_style = StyleBoxFlat.new()
	notes_style.bg_color = Color("#21180f")
	notes_style.set_content_margin_all(8)
	update_notes.add_theme_stylebox_override("normal", notes_style)
	update_content.add_child(update_notes)
	var update_footer = Label.new()
	update_footer.text = "The game will close and restart."
	update_content.add_child(update_footer)
	backdrop = TextureRect.new()
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	show_screen("Main")
	add_log_button()
	await get_tree().process_frame
	await get_tree().process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("ready="):
			var token = arg.trim_prefix("ready=")
			var re = RegEx.new()
			re.compile("^[0-9a-f]{32}$")
			if re.search(token):
				var f = FileAccess.open(install_root().path_join("ready-" + token), FileAccess.WRITE)
				if f:
					f.store_string(version)
					f.close()

func make_label(value: String, font_size: int, color: Color = GOLD) -> Label:
	var l = Label.new()
	l.text = value
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func menu_button(value: String, action: Callable) -> Button:
	var b = preload("res://themes/menu_button.gd").new()
	b.text = value
	b.pressed.connect(action)
	return b

func add_log_button() -> void:
	copy_log_button = Button.new()
	copy_log_button.text = "Copy log"
	copy_log_button.tooltip_text = "Copy the recent game log to the clipboard."
	copy_log_button.add_theme_font_size_override("font_size", 16)
	copy_log_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(copy_log_button)
	copy_log_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	copy_log_button.offset_left = -108
	copy_log_button.offset_right = -12
	copy_log_button.offset_top = 12
	copy_log_button.offset_bottom = 44
	copy_log_button.pressed.connect(copy_game_log)
	log_feedback = Timer.new()
	log_feedback.one_shot = true
	log_feedback.wait_time = 2.0
	log_feedback.timeout.connect(func(): copy_log_button.text = "Copy log")
	add_child(log_feedback)

func game_log_path() -> String:
	# The installed launcher directs the engine log to the installation root.
	var installed_log = install_root().path_join("game.log")
	if FileAccess.file_exists(installed_log):
		return installed_log
	return str(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log"))

func read_recent_log(path: String) -> String:
	var log_file = FileAccess.open(path, FileAccess.READ)
	if log_file == null:
		return ""
	var length = log_file.get_length()
	var start = maxi(0, length - LOG_COPY_LIMIT)
	log_file.seek(start)
	var content = log_file.get_buffer(length - start)
	if start > 0:
		var newline = content.find(10)
		if newline >= 0 and newline + 1 < content.size():
			content = content.slice(newline + 1)
		else:
			var first = 0
			while first < content.size() and (content[first] & 0xc0) == 0x80:
				first += 1
			content = content.slice(first)
	return content.get_string_from_utf8()

func copy_game_log() -> void:
	var recent = read_recent_log(game_log_path())
	if recent.is_empty():
		copy_log_button.text = "No log"
	else:
		DisplayServer.clipboard_set(recent)
		copy_log_button.text = "Copied"
	log_feedback.start()

func _unhandled_key_input(event: InputEvent) -> void:
	if busy or active_screen == "Main" or not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_ESCAPE:
		return
	get_viewport().set_input_as_handled()
	return_to_main.call_deferred(screen)

func return_to_main(previous: Control) -> void:
	if busy or screen != previous or active_screen == "Main":
		return
	if is_instance_valid(campaign_screen) and not campaign_screen.can_return_to_main():
		return
	settings_campaign_id = ""
	show_screen("Main")

func show_screen(name: String) -> void:
	if busy:
		return
	active_screen = name
	if is_instance_valid(screen):
		remove_child(screen)
		screen.queue_free()
	campaign_screen = null
	screen = Control.new()
	add_child(screen)
	if is_instance_valid(copy_log_button):
		move_child(copy_log_button, -1)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var art = "castle"
	if name == "Main":
		art = "castle"
	elif name == "Settings" or name in NAV["Settings"]:
		art = "hall" # Reuse approved artwork until dedicated Settings art is supplied.
	elif name == "Player Manager" or name in NAV["Player Manager"] or name in ["Delete Players","Edit Character"]:
		art = "hall"
	elif name == "Campaign Manager" or name in NAV["Campaign Manager"] or name=="Game Workspace":
		art = "valley"
	var painted_title = false
	var art_loaded = false
	for candidate in ["res://art/" + art + ".png", "res://art/" + art + ".jpg", "user://art/" + art + ".png", "user://art/" + art + ".jpg"]:
		var texture: Texture2D = null
		if candidate.begins_with("res://"):
			# Packaged artwork is imported by Godot and works in exported builds.
			if ResourceLoader.exists(candidate, "Texture2D"):
				texture = ResourceLoader.load(candidate, "Texture2D") as Texture2D
		elif FileAccess.file_exists(candidate):
			# User-provided images are external files and are not imported resources.
			var img = Image.load_from_file(candidate)
			if not img.is_empty():
				texture = ImageTexture.create_from_image(img)
		if texture != null:
			backdrop.texture = texture
			art_loaded = true
			painted_title = name == "Main"
			break
	if not art_loaded:
		if art=="valley":
			# Painted scenery from the existing approved castle art; custom valley wallpaper still wins.
			var scenery = AtlasTexture.new()
			scenery.atlas = preload("res://art/castle.jpg")
			scenery.region = Rect2(900,14,760,570)
			backdrop.texture = scenery
		else:
			backdrop.texture = load("res://art/" + ("forest" if art == "hall" else art) + ".svg")
	if name in ["Create New","Edit Character"]:
		var creator = CREATOR.new()
		creator.configure(false,func(): show_screen("Player Manager"),func(): show_screen("Manage Players"),editing_record if name=="Edit Character" else {})
		creator.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		screen.add_child(creator)
		creator.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	if name in ["Manage Players","Delete Players"]:
		var manager = MANAGER.new()
		manager.configure(edit_character,func(): show_screen("Player Manager"),open_catalogue_from_manager)
		manager.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		screen.add_child(manager)
		manager.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	if name in ["New Campaign","Existing Campaigns","Game Workspace"]:
		var campaign = CAMPAIGN.new()
		campaign_screen = campaign
		var resume_id = settings_campaign_id if name=="Game Workspace" else ""
		settings_campaign_id = ""
		campaign.configure("new" if name=="New Campaign" else "library",func(): show_screen("Campaign Manager"),func(): show_screen("Edit Content Rules"),open_game_settings,resume_id)
		screen.add_child(campaign)
		campaign.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	if name == "Rules Catalogue":
		var browser = BROWSER.new()
		browser.configure(func(): show_screen(browser_return))
		browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		screen.add_child(browser)
		browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	var margin = MarginContainer.new()
	screen.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 220 if painted_title else 120)
	margin.add_theme_constant_override("margin_top", 226 if painted_title else 64)
	margin.add_theme_constant_override("margin_right", 100 if name in ["Create New", "Generate Character", "Rules Library", "Master Reference","Edit Content Rules","Edit AI Prompts"] else 540)
	margin.add_theme_constant_override("margin_bottom", 44)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var menu = VBoxContainer.new()
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.add_theme_constant_override("separation", 5)
	scroll.add_child(menu)
	var title = make_label("1NFINITY D&D" if name == "Main" else name, 42 if name == "Main" else 32)
	if not painted_title:
		menu.add_child(title)
		if name == "Main":
			menu.add_child(make_label("────────  ∞  ────────", 28))
	else:
		title.free()
	var footer = make_label("v" + version + " dev build", 12, Color(0.67, 0.57, 0.37, 0.65))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	screen.add_child(footer)
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	footer.offset_left = -240
	footer.offset_top = -32
	footer.offset_right = -18
	footer.offset_bottom = -12
	if NAV.has(name):
		for entry in NAV[name]:
			var item: String = entry
			var caption = "Return to Campaign" if name=="Settings" and item=="Return to Main" and not settings_campaign_id.is_empty() else item
			menu.add_child(menu_button(caption, func(): navigate(item)))
		if name=="Campaign Manager":
			menu.add_child(menu_button("Exit",func(): show_screen("Main")))
	elif name == "Rules Library":
		rules_screen(menu)
	elif name == "Master Reference":
		master_screen(menu)
	elif name in ["Generate Character", "Create New"]:
		character_screen(menu, name == "Generate Character")
	elif name == "Manage Players":
		menu.add_child(make_label("Saved player storage is not yet implemented.", 19))
		menu.add_child(menu_button("Delete Players", func(): show_screen("Delete Players")))
		menu.add_child(menu_button("Exit", func(): show_screen("Player Manager")))
	elif name == "Delete Players":
		menu.add_child(make_label("No saved players available.", 19))
		menu.add_child(menu_button("Exit", func(): show_screen("Manage Players")))
	elif name == "Set and Store API":
		api_screen(menu)
	elif name == "Edit AI Prompts":
		prompt_screen(menu)
	elif name == "Edit Content Rules":
		content_rules_screen(menu)
	elif name == "Update from GitHub":
		check_button = menu_button("Check for Updates", check_updates)
		menu.add_child(check_button)
		status = make_label("Installed: v" + version, 18)
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		menu.add_child(status)
		menu.add_child(menu_button("Return to Settings", func(): show_screen("Settings")))
	else:
		var desc = make_label(str(DETAILS.get(name, "Development screen.")), 23)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		menu.add_child(desc)
		if name == "Quick Generate Player":
			for field in ["Race", "Class", "Gender"]:
				menu.add_child(make_label(field, 20))
				var value = LineEdit.new()
				value.placeholder_text = field
				menu.add_child(value)
		menu.add_child(menu_button("Return", func(): show_screen(parent_screen(name))))

func open_game_settings(id: String) -> void:
	settings_campaign_id = id
	show_screen("Settings")

func edit_character(rec: Dictionary) -> void:
	editing_record=rec
	show_screen("Edit Character")

func open_catalogue_from_manager() -> void:
	browser_return="Manage Players"
	show_screen("Rules Catalogue")

func open_catalogue_from_library() -> void:
	browser_return="Rules Library"
	show_screen("Rules Catalogue")

func parent_screen(name: String) -> String:
	for group in ["Settings", "Player Manager", "Campaign Manager"]:
		if name in NAV[group]:
			return group
	return "Main"

func navigate(item: String) -> void:
	if item == "Exit":
		if active_screen == "Main":
			get_tree().quit()
		else:
			show_screen("Main")
	elif item == "Player":
		show_screen("Player Manager")
	elif item == "Campaign":
		show_screen("Campaign Manager")
	elif item == "Rules Catalogue":
		browser_return="Settings"
		show_screen(item)
	elif item == "Full Screen":
		fullscreen = not fullscreen
		get_window().mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
		config.set_value("display", "fullscreen", fullscreen)
		config.save(CONFIG_PATH)
		show_screen("Main")
	elif item == "Return to Main":
		show_screen("Game Workspace" if not settings_campaign_id.is_empty() else "Main")
	else:
		show_screen(item)

func api_screen(menu: VBoxContainer) -> void:
	var key = LineEdit.new()
	key.secret = true
	key.placeholder_text = "Gemini API key"
	key.text = str(config.get_value("gemini", "api_key", ""))
	menu.add_child(key)
	var model = LineEdit.new()
	model.placeholder_text = "Model ID"
	model.text = str(config.get_value("gemini", "model", GEMINI.DEFAULT_MODEL))
	menu.add_child(model)
	var choices = OptionButton.new()
	choices.fit_to_longest_item = false
	choices.add_item("Discover available models…")
	choices.disabled = true
	menu.add_child(choices)
	var note = make_label("Discover models, choose one, then test and save.", 18)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var client = GEMINI.new()
	screen.add_child(client)
	var discover = menu_button("Discover Models", func():
		note.text = "Retrieving available models…"
		client.list_models(key.text))
	menu.add_child(discover)
	var test = menu_button("Test Connection", func():
		if key.text.strip_edges().is_empty():
			note.text = "Enter an API key."
			return
		note.text = "Testing " + model.text + "…"
		client.generate("Reply with exactly: Connection OK",key.text,model.text))
	menu.add_child(test)
	choices.item_selected.connect(func(i: int):
		if i >= 0:
			model.text = str(choices.get_item_metadata(i))
			note.text = "Test the selected model, then save it.")
	client.models_completed.connect(func(ok: bool, models: Array, message: String):
		if not ok:
			note.text = message
			return
		choices.clear()
		var selected = -1
		for id in models:
			choices.add_item(str(id))
			choices.set_item_metadata(choices.item_count-1,str(id))
			if str(id) == model.text.strip_edges().trim_prefix("models/"):
				selected = choices.item_count-1
		choices.disabled = models.is_empty()
		if not models.is_empty():
			if selected < 0:
				selected = 0
				for preferred in [GEMINI.DEFAULT_MODEL,"gemini-3.5-flash","gemini-3.6-flash"]:
					var found = models.find(preferred)
					if found >= 0:
						selected = found
						break
			choices.select(selected)
			model.text = str(choices.get_item_metadata(selected))
		note.text = message)
	client.completed.connect(func(ok: bool, message: String):
		note.text = "Connected to Gemini. Save API Settings to use this model." if ok else message)
	menu.add_child(menu_button("Save API Settings", func():
		if key.text.strip_edges().is_empty() or model.text.strip_edges().is_empty():
			note.text = "Enter a key and select a model first."
			return
		config.set_value("gemini", "api_key", key.text.strip_edges())
		config.set_value("gemini", "model", model.text.strip_edges().trim_prefix("models/"))
		note.text = "Saved locally." if config.save(CONFIG_PATH) == OK else "Save failed."))
	menu.add_child(note)
	menu.add_child(menu_button("Return to Settings", func(): show_screen("Settings")))

func prompt_screen(menu: VBoxContainer) -> void:
	var role = OptionButton.new()
	for item in ["Scene", "Interpreter", "Brief", "Narrator", "Write-back", "NPC"]:
		role.add_item(item)
	role.select(3)
	menu.add_child(role)
	var editor = TextEdit.new()
	editor.custom_minimum_size.y = 310
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	editor.text = NARRATOR.load_prompt()
	menu.add_child(editor)
	var note = make_label("Narrator guidance is editable. Godot authority and audience safeguards remain mandatory.",17)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var reset = menu_button("Reset Narrator to Default",func():
		var error = NARRATOR.reset_prompt()
		if error.is_empty():
			config.load(CONFIG_PATH)
			editor.text = NARRATOR.load_prompt()
		note.text = "Narrator default restored." if error.is_empty() else error)
	role.item_selected.connect(func(i: int):
		var key = role.get_item_text(i)
		editor.text = NARRATOR.load_prompt() if key == "Narrator" else str(config.get_value("prompts",key,""))
		reset.disabled = key != "Narrator"
		note.text = "Editing "+key+". Save before switching roles.")
	menu.add_child(menu_button("Save Selected Prompt",func():
		var key = role.get_item_text(role.selected)
		if key == "Narrator":
			var error = NARRATOR.save_prompt(editor.text)
			if error.is_empty():
				config.load(CONFIG_PATH)
				editor.text = NARRATOR.load_prompt()
			note.text = "Saved locally." if error.is_empty() else error
		else:
			var loaded = config.load(CONFIG_PATH)
			if loaded != OK and loaded != ERR_FILE_NOT_FOUND:
				note.text = "Cannot read settings; not overwritten."
				return
			config.set_value("prompts",key,editor.text)
			note.text = "Saved locally." if config.save(CONFIG_PATH) == OK else "Save failed."))
	menu.add_child(reset)
	menu.add_child(menu_button("Narrator Prompt Handover",func():
		preload("res://campaigns/prompt_sharing_dialog.gd").open(menu,func():
			config.load(CONFIG_PATH)
			if role.get_item_text(role.selected)=="Narrator":
				editor.text=NARRATOR.load_prompt())
	))
	menu.add_child(note)
	menu.add_child(menu_button("Return to Settings",func(): show_screen("Settings")))

func content_rules_screen(menu: VBoxContainer) -> void:
	var intro = make_label("Edit narration guidance and Gemini thresholds by audience profile. Provider safeguards remain in force.",19)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu.add_child(intro)
	var profiles = MATURITY.selectable_profiles()
	var picker = OptionButton.new()
	for profile in profiles:
		picker.add_item(str(profile["name"]))
		picker.set_item_metadata(picker.item_count-1,profile["id"])
	picker.select(MATURITY.IDS.find(MATURITY.DEFAULT_ID))
	menu.add_child(picker)
	var editor = TextEdit.new()
	editor.custom_minimum_size.y = 245
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	editor.text = str(MATURITY.resolve(MATURITY.DEFAULT_ID)["instructions"])
	menu.add_child(editor)
	var threshold_pickers: Dictionary = {}
	for category in MATURITY.CATEGORIES:
		var row = HBoxContainer.new()
		row.add_child(make_label(MATURITY.CATEGORIES[category],17))
		var options = OptionButton.new()
		for label in ["Block low and above","Block medium and above","Block high only","No category filter"]:
			options.add_item(label)
		row.add_child(options)
		menu.add_child(row)
		threshold_pickers[category]=options
	var show_profile = func(id: String):
		var profile = MATURITY.resolve(id)
		editor.text = profile["instructions"]
		for category in threshold_pickers:
			threshold_pickers[category].select(MATURITY.THRESHOLDS.find(profile["thresholds"][category]))
	show_profile.call(MATURITY.DEFAULT_ID)
	var note = make_label("Changes apply to campaigns using this profile ID. Save before switching profiles.",17)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	picker.item_selected.connect(func(i: int):
		show_profile.call(str(picker.get_item_metadata(i)))
		note.text = "Editing "+picker.get_item_text(i)+".")
	menu.add_child(menu_button("Save Content Rules",func():
		var thresholds: Dictionary = {}
		for category in threshold_pickers:
			thresholds[category]=MATURITY.THRESHOLDS[threshold_pickers[category].selected]
		var error = MATURITY.save_guidance(str(picker.get_item_metadata(picker.selected)),editor.text,thresholds)
		if error.is_empty():
			config.load(CONFIG_PATH)
		note.text = "Saved locally." if error.is_empty() else error))
	menu.add_child(menu_button("Reset Selected Profile",func():
		var id = str(picker.get_item_metadata(picker.selected))
		var error = MATURITY.reset_guidance(id)
		if error.is_empty():
			config.load(CONFIG_PATH)
			show_profile.call(id)
		note.text = "Default restored." if error.is_empty() else error))
	menu.add_child(note)
	menu.add_child(menu_button("Return to Settings",func(): show_screen("Settings")))
	menu.add_child(menu_button("Return to Campaign",func(): show_screen("Game Workspace" if not settings_campaign_id.is_empty() else "New Campaign")))

func rules_screen(menu: VBoxContainer) -> void:
	var status_line = make_label(library.status(), 19)
	menu.add_child(status_line)
	var picker = FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.filters = PackedStringArray(["*.json ; Personal rules library"])
	screen.add_child(picker)
	picker.file_selected.connect(func(path: String):
		status_line.text = library.import_archive(path))
	menu.add_child(menu_button("Rules Catalogue - 2014 / 2018", open_catalogue_from_library))
	menu.add_child(menu_button("Master Reference - Both Editions", func(): show_screen("Master Reference")))
	menu.add_child(menu_button("Import Personal Rules Library", func(): picker.popup_centered_ratio(0.75)))
	var query = LineEdit.new()
	query.placeholder_text = "Search exact rule text"
	menu.add_child(query)
	var results = TextEdit.new()
	results.editable = false
	results.custom_minimum_size.y = 240
	menu.add_child(menu_button("Search", func(): results.text = library.search(query.text)))
	menu.add_child(results)
	menu.add_child(menu_button("Exit", func(): show_screen("Settings")))

func character_screen(menu: VBoxContainer, quick: bool) -> void:
	var choices = HBoxContainer.new()
	menu.add_child(choices)
	var race = OptionButton.new()
	for value in MECHANICS.RACES.keys():
		race.add_item(value)
	choices.add_child(race)
	var role = OptionButton.new()
	for value in MECHANICS.CLASSES.keys():
		role.add_item(value)
	choices.add_child(role)
	var gender = LineEdit.new()
	gender.placeholder_text = "Gender"
	gender.custom_minimum_size.x = 100
	choices.add_child(gender)
	var sheet = SHEET.new()
	var note = make_label("Level 1 draft only. Skills, equipment, spells and other choices still pending.", 19)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu.add_child(note)
	var character_name = LineEdit.new()
	character_name.placeholder_text = "Character name"
	menu.add_child(character_name)
	menu.add_child(menu_button("Roll Ability Scores" if quick else "Roll Draft Ability Scores", func():
		sheet.display(MECHANICS.draft(race.get_item_text(race.selected), role.get_item_text(role.selected), gender.text, character_name.text, false))))
	menu.add_child(menu_button("Use Standard Array", func():
		sheet.display(MECHANICS.draft(race.get_item_text(race.selected), role.get_item_text(role.selected), gender.text, character_name.text, true))))
	menu.add_child(sheet)
	menu.add_child(menu_button("Character Rules Reference", func(): show_screen("Master Reference")))
	menu.add_child(menu_button("Exit", func(): show_screen("Player Manager")))

func master_screen(menu: VBoxContainer) -> void:
	menu.add_child(make_label("2014/2018 mechanics remain active. Revised 2024 rules are reference only.", 19))
	var edition = OptionButton.new()
	edition.add_item("2018 Basic Rules - original 5e")
	edition.add_item("SRD 5.2.1 - revised 5e")
	menu.add_child(edition)
	var section = OptionButton.new()
	menu.add_child(section)
	var search_text = LineEdit.new()
	search_text.placeholder_text = "Name, term, or page number"
	menu.add_child(search_text)
	var output = TextEdit.new()
	output.editable = false
	output.custom_minimum_size = Vector2(300, 360)
	output.add_theme_font_override("font", ThemeDB.fallback_font)
	output.add_theme_font_size_override("font_size", 17)
	var refresh = func():
		section.clear()
		var id = "2018" if edition.selected == 0 else "2024"
		for category in master.categories(id):
			section.add_item(category)
		output.text = "Select a category and search. " + master.status()
	edition.item_selected.connect(func(_index: int): refresh.call())
	refresh.call()
	menu.add_child(menu_button("Look Up Rules", func():
		if section.selected < 0:
			output.text = master.status()
			return
		var id = "2018" if edition.selected == 0 else "2024"
		output.text = master.lookup(id, section.get_item_text(section.selected), search_text.text)))
	menu.add_child(output)
	menu.add_child(menu_button("Exit", func(): show_screen("Rules Library")))

func install_root() -> String:
	return ProjectSettings.globalize_path("res://").trim_suffix("/").trim_suffix("\\").get_base_dir()

func check_updates() -> void:
	busy = true
	check_button.disabled = true
	status.text = "Checking Godot update channel..."
	var err = request.request(CHANNEL + "?t=" + str(Time.get_unix_time_from_system()))
	if err != OK:
		busy = false
		status.text = "Could not start update check."
		check_button.disabled = false

func version_parts(value: String) -> Array:
	var p = value.split(".")
	if p.size() != 3:
		return []
	var out = []
	for n in p:
		if not n.is_valid_int() or int(n) < 0:
			return []
		out.append(int(n))
	return out

func newer(candidate: String) -> bool:
	var a = version_parts(candidate)
	var b = version_parts(version)
	if a.size() != 3 or b.size() != 3:
		return false
	for i in range(3):
		if a[i] != b[i]:
			return a[i] > b[i]
	return false

func on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	check_button.disabled = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status.text = "Update check failed (HTTP " + str(code) + ")."
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or data.get("channel") != "godot":
		status.text = "Invalid update channel."
		return
	var latest = str(data.get("version", ""))
	if version_parts(latest).is_empty():
		status.text = "Invalid release version."
		return
	if not newer(latest):
		status.text = "You are up to date.  |  v" + version
		return
	remote = data
	update_version.text = "Version " + latest
	update_notes.custom_minimum_size.x = clampf(get_window().size.x - 64.0, 0.0, 400.0)
	update_notes.text = str(data.get("notes", ""))
	dialog.popup_centered(Vector2i(clampi(get_window().size.x - 16, 1, 480), 220))
	update_notes.scroll_to_line.call_deferred(0)
	status.text = "Update available: v" + latest

func install_update() -> void:
	if OS.get_name() != "Windows":
		status.text = "The packaged updater currently supports Windows only."
		return
	var root = install_root()
	var script = root.path_join("Update.ps1")
	if not FileAccess.file_exists(script):
		status.text = "Updater missing. Use the original installation package."
		return
	var args = PackedStringArray(["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, "-InstallRoot", root, "-ExpectedVersion", str(remote["version"]), "-GamePid", str(OS.get_process_id())])
	if fullscreen:
		get_window().mode = Window.MODE_WINDOWED
	status.text = "Starting external updater. See update.log for details."
	var pid = OS.create_process("powershell.exe", args, true)
	if pid <= 0:
		status.text = "Unable to start updater."
		return
	get_tree().quit()
