extends Control

const CHANNEL = "https://raw.githubusercontent.com/mdavis00111-afk/1NFINITY-DnD-Updates/godot/channel.json"
const GOLD = Color("#d7bb81")
const MUTED = Color("#9ca9b9")
var version: String = ""
var status: Label
var check_button: Button
var request: HTTPRequest
var remote: Dictionary = {}
var dialog: ConfirmationDialog

func _ready() -> void:
	version = FileAccess.get_file_as_string("res://version.txt").strip_edges()
	var bg = ColorRect.new()
	bg.color = Color("#111722")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var menu = VBoxContainer.new()
	menu.custom_minimum_size.x = 380
	menu.add_theme_constant_override("separation", 12)
	center.add_child(menu)
	var heading = label("1NFINITY D&D", 48, GOLD)
	menu.add_child(heading)
	menu.add_child(label("FANTASY SANDBOX  /  HYBRID IV", 16, MUTED))
	menu.add_child(HSeparator.new())
	for caption in ["New Campaign", "Continue Campaign", "Load Campaign", "Settings"]:
		var b = menu_button(caption)
		b.disabled = true
		menu.add_child(b)
	check_button = menu_button("Check for Updates")
	menu.add_child(check_button)
	check_button.pressed.connect(check_updates)
	var exit_button = menu_button("Exit Game")
	menu.add_child(exit_button)
	exit_button.pressed.connect(func(): get_tree().quit())
	status = label("Development build  |  v" + version, 15, MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu.add_child(status)
	request = HTTPRequest.new()
	request.timeout = 20.0
	add_child(request)
	request.request_completed.connect(on_response)
	dialog = ConfirmationDialog.new()
	dialog.title = "Install update"
	add_child(dialog)
	dialog.confirmed.connect(install_update)
	# Signal readiness only after the menu has been constructed.
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

func label(value: String, size: int, color: Color) -> Label:
	var l = Label.new()
	l.text = value
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func menu_button(value: String) -> Button:
	var b = Button.new()
	b.text = value
	b.custom_minimum_size.y = 44
	b.add_theme_font_size_override("font_size", 19)
	return b

func install_root() -> String:
	return ProjectSettings.globalize_path("res://").trim_suffix("/").trim_suffix("\\").get_base_dir()

func check_updates() -> void:
	check_button.disabled = true
	status.text = "Checking Godot update channel..."
	var err = request.request(CHANNEL + "?t=" + str(Time.get_unix_time_from_system()))
	if err != OK:
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
	dialog.dialog_text = "Version " + latest + "\n\n" + str(data.get("notes", "")) + "\n\nThe game will close and restart."
	dialog.popup_centered(Vector2i(480, 220))
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
	var pid = OS.create_process("powershell.exe", args, true)
	if pid <= 0:
		status.text = "Unable to start updater."
		return
	get_tree().quit()
