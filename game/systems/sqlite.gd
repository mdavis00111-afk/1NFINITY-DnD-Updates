extends RefCounted
## SQLite is authoritative. JSON is only the local transport and structured record payload.
static var bridge_calls: int=0
static var bridge_elapsed_ms: int=0

static func metrics() -> Dictionary:
	return {"calls":bridge_calls,"elapsed_ms":bridge_elapsed_ms}

static func stmt(sql: String, values: Array = []) -> Dictionary:
	return {"sql":sql,"params":values}

static func run(database: String, statements: Array, readonly: bool = false) -> Dictionary:
	if OS.get_name() != "Windows":
		return {"ok":false,"error":"This SQLite adapter requires Windows 10/11."}
	var folder = "user://sql_transport"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK:
		return {"ok":false,"error":"Cannot create SQLite transport directory."}
	var token = Crypto.new().generate_random_bytes(16).hex_encode()
	var req = folder.path_join(token+".request")
	var res = folder.path_join(token+".response")
	var file = FileAccess.open(req, FileAccess.WRITE)
	if file == null:
		return {"ok":false,"error":"Cannot open SQLite request."}
	file.store_string(JSON.stringify({"database":ProjectSettings.globalize_path(database),"readonly":readonly,"statements":statements}))
	file.close()
	var output: Array = []
	var started=Time.get_ticks_msec()
	OS.execute("powershell.exe",PackedStringArray(["-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",ProjectSettings.globalize_path("res://systems/sqlite_bridge.ps1"),"-RequestFile",ProjectSettings.globalize_path(req),"-ResponseFile",ProjectSettings.globalize_path(res)]),output,true)
	bridge_calls+=1
	bridge_elapsed_ms+=Time.get_ticks_msec()-started
	var response: Variant = null
	if FileAccess.file_exists(res):
		response = JSON.parse_string(FileAccess.get_file_as_string(res))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(req))
	if FileAccess.file_exists(res):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(res))
	if not response is Dictionary:
		return {"ok":false,"error":"SQLite bridge did not return a response."}
	return response
