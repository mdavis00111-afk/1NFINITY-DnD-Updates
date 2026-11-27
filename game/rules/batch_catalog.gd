extends RefCounted
# Small text batches are imported automatically into a separate SQLite cache.
const SQL = preload("res://systems/sqlite.gd")
const PACKS = ["res://data/2014/creature_core_batch_001.json"]
var last_error: String = ""

func rows() -> Array:
	last_error = ""
	var statements: Array = [SQL.stmt("CREATE TABLE IF NOT EXISTS catalog(category TEXT NOT NULL,id TEXT NOT NULL,name TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(category,id))"), SQL.stmt("DELETE FROM catalog")]
	var count: int = 0
	for path in PACKS:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Array:
			last_error = "Invalid reference batch: "+path
			return []
		for row in parsed:
			if not row is Dictionary or not row.has("index") or not row.has("category") or not row.has("name"):
				last_error = "Invalid reference record: "+path
				return []
			statements.append(SQL.stmt("INSERT OR REPLACE INTO catalog(category,id,name,payload) VALUES(?,?,?,?)",[row["category"],row["index"],row["name"],JSON.stringify(row)]))
			count += 1
	statements.append(SQL.stmt("SELECT category,id,payload FROM catalog ORDER BY category,name COLLATE NOCASE"))
	var response = SQL.run("user://reference_batches.db",statements)
	if not response.get("ok",false):
		last_error = str(response.get("error","Reference batch import failed."))
		return []
	var sets: Array = response.get("results",[])
	if sets.is_empty() or not sets.back() is Array or sets.back().size() != count:
		last_error = "Reference batch import count mismatch."
		return []
	return sets.back()
