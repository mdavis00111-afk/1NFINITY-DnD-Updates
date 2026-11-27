extends RefCounted
## Versioned local record interface. No game updates write to user://players.
const ROOT = "user://players/v1"
const SCHEMA = 1

func make_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

func valid_id(id: String) -> bool:
	var re = RegEx.new()
	re.compile("^[0-9a-f]{32}$")
	return re.search(id) != null

func list_records() -> Array:
	var result: Array = []
	var dir = DirAccess.open(ROOT)
	if dir == null:
		return result
	for name in dir.get_files():
		if name.ends_with(".json") and valid_id(name.trim_suffix(".json")):
			var record = load_record(name.trim_suffix(".json"))
			if not record.is_empty():
				result.append(record)
	result.sort_custom(func(a,b): return str(a.get("name","")).naturalnocasecmp_to(str(b.get("name",""))) < 0)
	return result

func load_record(id: String) -> Dictionary:
	if not valid_id(id):
		return {}
	var path = ROOT.path_join(id + ".json")
	if not FileAccess.file_exists(path):
		return {}
	var record = JSON.parse_string(FileAccess.get_file_as_string(path))
	if record is Dictionary and int(record.get("schema_version",0)) == SCHEMA and record.get("id") == id and record.get("ruleset") == "5e-2014-2018":
		return record
	return {}

func save_record(record: Dictionary) -> String:
	var id = str(record.get("id",""))
	if not valid_id(id):
		return "Invalid character ID."
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT)) != OK:
		return "Could not create save directory."
	var path = ROOT.path_join(id + ".json")
	var tmp = path + ".tmp"
	var backup = path + ".bak"
	var copy = record.duplicate(true)
	copy["schema_version"] = SCHEMA
	copy["updated_at"] = Time.get_datetime_string_from_system(true)
	if not copy.has("created_at"):
		copy["created_at"] = copy["updated_at"]
	var file = FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return "Cannot write character."
	file.store_string(JSON.stringify(copy,"  "))
	file.flush()
	var err = file.get_error()
	file.close()
	if err != OK:
		return "Cannot finish character save."
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(backup))
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(path),ProjectSettings.globalize_path(backup)) != OK:
			return "Cannot back up existing character."
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp),ProjectSettings.globalize_path(path)) != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(backup),ProjectSettings.globalize_path(path))
		return "Could not commit character save."
	return ""

func save_portrait(id: String, source: String) -> String:
	if source.is_empty() or not valid_id(id):
		return ""
	if source.begins_with(ROOT + "/") and FileAccess.file_exists(source):
		return source
	var image = Image.load_from_file(source)
	if image.is_empty():
		return ""
	if maxi(image.get_width(),image.get_height()) > 1024:
		var scale = 1024.0 / maxi(image.get_width(),image.get_height())
		image.resize(maxi(1,roundi(image.get_width()*scale)),maxi(1,roundi(image.get_height()*scale)),Image.INTERPOLATE_LANCZOS)
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT.path_join("portraits"))) != OK:
		return ""
	var path = ROOT.path_join("portraits").path_join(id + ".png")
	if image.save_png(path) != OK:
		return ""
	return path

func archive(id: String) -> String:
	if load_record(id).is_empty():
		return "Character not found."
	var trash = ROOT.path_join("archive")
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(trash)) != OK:
		return "Cannot create archive."
	var destination = trash.path_join(id + "-" + str(Time.get_unix_time_from_system()).replace(".","-") + ".json")
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(ROOT.path_join(id+".json")),ProjectSettings.globalize_path(destination)) != OK:
		return "Cannot archive character."
	return ""

func campaign_template(id: String) -> Dictionary:
	var record = load_record(id)
	if record.get("status") != "ready":
		return {}
	var instance = record.duplicate(true)
	instance["master_character_id"] = id
	instance["id"] = make_id()
	return instance
