extends SceneTree
const SQL = preload("res://systems/sqlite.gd")
const CAT = preload("res://rules/catalog.gd")
const RULES = preload("res://rules/character_rules.gd")
func _initialize() -> void:
	var cat = CAT.new()
	if not cat.initialize():
		push_error("Rules SQLite: "+cat.last_error)
		quit(1)
		return
	if cat.rows("classes").size()!=12 or cat.rows("skills").size()!=18 or cat.get_record("spells","fire-bolt").is_empty():
		push_error("Catalogue counts or spell lookup failed.")
		quit(1)
		return
	var path = "user://sqlite-smoke-"+Crypto.new().generate_random_bytes(8).hex_encode()+".db"
	var result = SQL.run(path,[SQL.stmt("CREATE TABLE test(id TEXT PRIMARY KEY,value TEXT)"),SQL.stmt("INSERT INTO test VALUES(?,?)",["id","O'Brien — café"]),SQL.stmt("SELECT value FROM test WHERE id=?",["id"])])
	var ok = result.get("ok",false)
	if ok:
		ok = result["results"][2][0]["value"]=="O'Brien — café"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not ok:
		push_error("SQLite parameter/transaction check: "+str(result.get("error","value mismatch")))
		quit(1)
		return
	var rules = RULES.new()
	var draft = rules.fresh()
	draft["race_id"]="human"
	draft["class_id"]="wizard"
	draft["background_id"]="sage"
	draft["name"]="Test"
	rules.roll_scores(draft,"point")
	if rules.points_used(draft)!=0 or rules.scores(draft)["int"]!=9:
		push_error("Point buy or racial modifiers failed.")
		quit(1)
		return
	rules.roll_scores(draft,"array")
	if not rules.validate_step(draft,2).is_empty():
		push_error("Standard array check failed.")
		quit(1)
		return
	print("SQLite read, write, transaction, UTF-8, parameter binding, catalogue and ability checks passed.")
	quit(0)
