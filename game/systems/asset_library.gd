extends RefCounted
## Personal-use artwork and sheet references are separate from the rules engine.
const SQL = preload("res://systems/sqlite.gd")
static var loaded: bool = false
static var error: String = ""
static var tokens: Array = []
static var sheets: Array = []
static var token_index: Dictionary = {}
static var creature_index: Dictionary = {}
static var sheet_index: Dictionary = {}

func root_path() -> String:
	return OS.get_executable_path().get_base_dir().path_join("reference/assets")

func initialize() -> bool:
	if loaded:
		return true
	var db = root_path().path_join("assets.db")
	if not FileAccess.file_exists(db):
		error = "Local asset library not installed."
		return false
	var response = SQL.run(db,[SQL.stmt("SELECT * FROM tokens ORDER BY name COLLATE NOCASE"), SQL.stmt("SELECT * FROM sheet_templates ORDER BY edition,name COLLATE NOCASE")],true)
	if not response.get("ok",false):
		error = str(response.get("error","Cannot read asset library."))
		return false
	tokens = response["results"][0]
	sheets = response["results"][1]
	token_index.clear()
	creature_index.clear()
	sheet_index.clear()
	for rec in tokens:
		token_index[str(rec["id"])] = rec
		if rec.get("link_status") == "exact-name" and rec.get("creature_id") != null:
			creature_index[str(rec["creature_id"])] = rec
	for rec in sheets:
		sheet_index[str(rec["id"])] = rec
	loaded = true
	error = ""
	return true

func rows(category: String) -> Array:
	if not initialize():
		return []
	return tokens if category == "token-art" else (sheets if category == "sheet-templates" else [])

func token_for_creature(creature_id: String) -> Dictionary:
	if not initialize():
		return {}
	return creature_index.get(creature_id,{})

func safe_path(record: Dictionary) -> String:
	var relative = str(record.get("relative_path",""))
	if relative.is_empty() or relative.contains("..") or relative.begins_with("/") or relative.contains("\\") or relative.contains(":"):
		return ""
	return root_path().path_join(relative)

func texture_for_token(record: Dictionary) -> Texture2D:
	var path = safe_path(record)
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var img = Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)

func texture_for_creature(creature_id: String) -> Texture2D:
	return texture_for_token(token_for_creature(creature_id))

func template_path(id: String) -> String:
	if not initialize():
		return ""
	return safe_path(sheet_index.get(id,{}))

func template_fields(id: String) -> Array:
	if not initialize() or not sheet_index.has(id):
		return []
	var response = SQL.run(root_path().path_join("assets.db"),[SQL.stmt("SELECT page,ordinal,field_name,field_type,rect_json,record_path,mapping_status FROM sheet_fields WHERE template_id=? ORDER BY page,ordinal",[id])],true)
	if not response.get("ok",false):
		error = str(response.get("error","Cannot read sheet fields."))
		return []
	return response["results"][0]
