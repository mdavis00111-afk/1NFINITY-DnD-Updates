extends Control

const MANIFEST_URL := "https://raw.githubusercontent.com/mdavis00111-afk/1NFINITY-DnD-Updates/hybrid4-godot/game/version.json"
var version := ""
var pending_version := ""
var status: Label
var check_button: Button
var request: HTTPRequest
var dialog: ConfirmationDialog

func _ready() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://version.json"))
	version = str(manifest.get("version", "unknown")) if manifest is Dictionary else "unknown"
	var bg := ColorRect.new()
	bg.color = Color("#10151e")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var menu := VBoxContainer.new()
	menu.custom_minimum_size = Vector2(420, 0)
	menu.add_theme_constant_override("separation", 12)
	center.add_child(menu)
	var heading := Label.new()
	heading.text = "1NFINITY D&D"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 50)
	heading.add_theme_color_override("font_color", Color("#e2c38a"))
	menu.add_child(heading)
	var subtitle := Label.new()
	subtitle.text = "HYBRID IV  /  DEVELOPMENT BUILD"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("#abb9cb"))
	menu.add_child(subtitle)
	for item in ["New Campaign", "Continue Campaign", "Load Campaign", "Settings"]:
		var b := add_button(menu, item)
		b.disabled = true
		b.tooltip_text = "Not implemented in this foundation build."
	check_button = add_button(menu, "Check for Updates")
	check_button.pressed.connect(check_updates)
	add_button(menu, "Exit Game").pressed.connect(get_tree().quit)
	status = Label.new()
	status.text = "Version " + version + "  |  Godot update channel"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(420, 40)
	menu.add_child(status)
	request = HTTPRequest.new()
	request.timeout = 20
	add_child(request)
	request.request_completed.connect(update_response)
	dialog = ConfirmationDialog.new()
	dialog.title = "Install update"
	add_child(dialog)
	dialog.confirmed.connect(install_update)

func add_button(parent: VBoxContainer, caption: String) -> Button:
	var b := Button.new()
	b.text = caption
	b.custom_minimum_size = Vector2(420, 44)
	b.add_theme_font_size_override("font_size", 19)
	parent.add_child(b)
	return b

func check_updates() -> void:
	check_button.disabled = true
	status.text = "Checking GitHub..."
	var error := request.request(MANIFEST_URL + "?t=" + str(Time.get_unix_time_from_system()), ["Cache-Control: no-cache"])
	if error != OK:
		status.text = "Could not start update check."
		check_button.disabled = false

func valid_version(v: String) -> bool:
	var parts := v.split(".")
	if parts.size() != 3:
		return false
	for part in parts:
		if not part.is_valid_int() or int(part) < 0:
			return false
	return true

func newer(a: String, b: String) -> bool:
	if not valid_version(a) or not valid_version(b):
		return false
	var aa := a.split(".")
	var bb := b.split(".")
	for i in range(3):
		if int(aa[i]) != int(bb[i]):
			return int(aa[i]) > int(bb[i])
	return false

func update_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	check_button.disabled = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status.text = "Update check failed (HTTP " + str(code) + "). Try again."
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or data.get("channel") != "hybrid4-godot":
		status.text = "Invalid update manifest."
		return
	var remote := str(data.get("version", ""))
	if not valid_version(remote):
		status.text = "Invalid remote version."
		return
	if not newer(remote, version):
		status.text = "Version " + version + " is up to date."
		return
	pending_version = remote
	status.text = "Update " + remote + " available."
	dialog.dialog_text = "Version " + version + " → " + remote + "\n\n" + str(data.get("notes", "")) + "\n\nThe game will close, install and restart."
	dialog.popup_centered(Vector2i(500, 220))

func install_update() -> void:
	var root := ProjectSettings.globalize_path("res://").trim_suffix("/").trim_suffix("\\").get_base_dir()
	var launcher := root.path_join("launcher.ps1")
	if not FileAccess.file_exists(launcher) or OS.get_name() != "Windows":
		status.text = "Windows launcher not found. Start through Launch.cmd."
		return
	var args := PackedStringArray(["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", launcher, "-Mode", "Update", "-ExpectedVersion", pending_version, "-GamePid", str(OS.get_process_id())])
	var pid := OS.create_process("powershell.exe", args, true)
	if pid <= 0:
		status.text = "Could not start updater."
		return
	get_tree().quit()
