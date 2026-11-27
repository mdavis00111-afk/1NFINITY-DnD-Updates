extends SceneTree
const ASSETS = preload("res://systems/asset_library.gd")
const CAT = preload("res://rules/catalog.gd")
func _initialize() -> void:
	var assets=ASSETS.new()
	var cat=CAT.new()
	if not assets.initialize() or not cat.initialize():
		push_error("Asset or rules database unavailable: "+assets.error+" "+cat.last_error)
		quit(1)
		return
	var tokens=assets.rows("token-art")
	var sheets=assets.rows("sheet-templates")
	if tokens.size()!=81 or sheets.size()!=7:
		push_error("Unexpected asset counts.")
		quit(1)
		return
	var linked=0
	for record in tokens:
		if not FileAccess.file_exists(assets.safe_path(record)):
			push_error("Missing token: "+str(record["id"]))
			quit(1)
			return
		if record["link_status"]=="exact-name":
			linked+=1
			if cat.get_record("monsters",str(record["creature_id"])).is_empty():
				push_error("Missing creature link: "+str(record["id"]))
				quit(1)
				return
	if linked!=38 or assets.texture_for_creature("black-bear")==null or assets.template_fields("character-sheet-2014-fillable").size()!=336:
		push_error("Asset cross-reference or preview failed.")
		quit(1)
		return
	for sheet in sheets:
		if not FileAccess.file_exists(assets.safe_path(sheet)):
			push_error("Missing template: "+str(sheet["id"]))
			quit(1)
			return
	print("81 tokens, 38 linked creatures and 7 sheets verified.")
	quit(0)
