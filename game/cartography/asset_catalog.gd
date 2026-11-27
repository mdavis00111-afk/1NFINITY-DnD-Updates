extends RefCounted
## Static art selection only. No licence-pending assets enter the renderer.
const CATALOG = "res://cartography/art/catalog.json"
const STYLES = "res://cartography/art/navigation_styles.json"
var entries: Dictionary = {}
var families: Dictionary = {}
var styles: Dictionary = {}
var cache: Dictionary = {}
const ALIASES = {"forest":"deciduous_forest","woods":"deciduous_forest","mountain":"mountain_peak","mountains":"mountain_range","hills":"rolling_hills","hill":"rolling_hills","grassland":"grasslands","plain":"plains","coast":"rocky_coast","coastline":"rocky_coast","harbor":"harbour","capital_city":"capital","fort":"fortress","poi":"point_of_interest","dungeon_entrance":"hidden_entrance","road":"main_road","track":"dirt_track","path":"footpath","border":"regional_border"}
func initialize() -> bool:
	var root = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if not root is Dictionary or not root.get("assets") is Array:
		return false
	for row in root["assets"]:
		if not row is Dictionary or not row.get("provenance") is Dictionary:
			continue
		if row["provenance"].get("type")=="open_license_reference_crop" or str(row.get("id","")).ends_with(".vintage"):
			continue
		var path = str(row.get("path",""))
		if not path.begins_with("res://cartography/art/") or not path.ends_with(".svg") or path.contains(".."):
			continue
		entries[row["id"]] = row
		var key = str(row["category"])+":"+str(row["kind"])
		if not families.has(key):
			families[key] = []
		families[key].append(str(row["id"]))
	for key in families:
		families[key].sort()
	var raw = JSON.parse_string(FileAccess.get_file_as_string(STYLES))
	if raw is Dictionary:
		for row in raw.get("styles",[]):
			styles[row["id"]] = row
	return not entries.is_empty()

static func normalize(value: Variant) -> String:
	var kind = str(value).strip_edges().to_lower().replace(" ","_").replace("-","_")
	return str(ALIASES.get(kind,kind))

func choose(category: String, kind: Variant, stable_id: String, small: bool = false, explicit: Variant = null) -> Dictionary:
	var normalized = normalize(kind)
	if explicit is String and entries.has(explicit):
		var approved = entries[explicit]
		if approved["category"]==category and approved["kind"]==normalized:
			return approved
	var ids: Array = families.get(category+":"+normalized,[])
	var candidates: Array = []
	for id in ids:
		if entries[id]["lod"]==("symbol" if small else "illustration"):
			candidates.append(id)
	if candidates.is_empty():
		candidates = ids
	if candidates.is_empty():
		return {}
	var index = stable_id.sha256_text().substr(0,8).hex_to_int()%candidates.size()
	return entries[candidates[index]]

func texture(id: String) -> Texture2D:
	if not entries.has(id):
		return null
	if not cache.has(id):
		cache[id] = ResourceLoader.load(entries[id]["path"],"Texture2D") as Texture2D
	return cache[id]

func for_place(row: Dictionary, small: bool) -> Dictionary:
	for category in ["settlements","adventure","terrain","water"]:
		var art = choose(category,row.get("kind",""),str(row["id"]),small,row.get("asset_id"))
		if not art.is_empty():
			return art
	# An unknown kind gets a name-only label, never a fabricated settlement.
	return {}
