extends RefCounted
# The expanded reference library is independent of the immutable core catalogue.
const SQL = preload("res://systems/sqlite.gd")
const PACK = "res://data/reference.db.gz"
const EXPECTED_SHA = "197734c2a4a58078e08894d9cb5d3392c4d4ba42ff02e351a10c55e3585a08b0"
const EXPECTED_SIZE = 21127168
const EXPECTED_PAGES = 1327
var last_error: String = ""

func database_path() -> String:
	last_error = ""
	if not FileAccess.file_exists(PACK):
		var legacy = OS.get_executable_path().get_base_dir().path_join("reference/private_rules.db")
		if FileAccess.file_exists(legacy):
			return legacy
		last_error = "Expanded reference library is not included in this release."
		return ""
	var folder = "user://rules_cache"
	var cached = folder.path_join("reference-" + EXPECTED_SHA.left(16) + ".db")
	if FileAccess.file_exists(cached) and FileAccess.get_sha256(cached) == EXPECTED_SHA:
		return cached
	var unpacked = FileAccess.get_file_as_bytes(PACK).decompress_dynamic(EXPECTED_SIZE, FileAccess.COMPRESSION_GZIP)
	if unpacked.size() != EXPECTED_SIZE:
		last_error = "Reference database decompression failed."
		return ""
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK:
		last_error = "Cannot create reference cache."
		return ""
	var temp = cached + "." + Crypto.new().generate_random_bytes(8).hex_encode() + ".tmp"
	var file = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		last_error = "Cannot write reference cache."
		return ""
	file.store_buffer(unpacked)
	file.close()
	if FileAccess.get_sha256(temp) != EXPECTED_SHA:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
		last_error = "Reference database checksum mismatch."
		return ""
	if FileAccess.file_exists(cached):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cached))
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(cached)) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
		last_error = "Cannot activate reference cache."
		return ""
	return cached

func search_pages(q: String) -> Dictionary:
	var path = database_path()
	if path.is_empty():
		return {"ok":false, "error":last_error}
	return SQL.run(path,[SQL.stmt("SELECT d.title,p.pdf_page,p.body FROM reference_pages p JOIN reference_documents d ON p.document_id=d.id WHERE instr(lower(p.body),lower(?))>0 ORDER BY d.title,p.pdf_page LIMIT 100",[q])],true)

func verify_pack() -> bool:
	var path = database_path()
	if path.is_empty():
		return false
	var check = SQL.run(path,[SQL.stmt("SELECT count(*) AS page_count FROM reference_pages"),SQL.stmt("SELECT count(*) AS document_count FROM reference_documents")],true)
	if not check.get("ok",false):
		last_error = str(check.get("error","Reference database query failed."))
		return false
	var sets: Array = check.get("results",[])
	if sets.size() != 2 or sets[0].is_empty() or sets[1].is_empty():
		last_error = "Reference verification returned no counts."
		return false
	if int(sets[0][0]["page_count"]) != EXPECTED_PAGES or int(sets[1][0]["document_count"]) != 4:
		last_error = "Reference database count mismatch."
		return false
	return true
