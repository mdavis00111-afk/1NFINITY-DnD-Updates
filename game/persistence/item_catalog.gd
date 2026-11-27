extends RefCounted
## Pinned official definitions, separate campaign custom definitions. No provider.
const SQL = preload("res://systems/sqlite.gd")
const CAT = preload("res://rules/catalog.gd")
const DTO = preload("res://world/world_dto.gd")
const DISPLAY = preload("res://gameplay/display_values.gd")
const UI = preload("res://gameplay/ui_intents.gd")
var cat = CAT.new()
var last_error = ""

# Use the checksum-verified base SQL file, not the optional private monster
# overlay or mutable catalogue cache. No silent replacement of official stats.
func official(category: String,id: String) -> Dictionary:
	if not category in CAT.TABLES or not DTO.bounded_text(id,128):
		return {}
	var path = cat.database_path()
	if path.is_empty():
		last_error="Pinned catalogue unavailable."
		return {}
	var result = SQL.run(path,[SQL.stmt("SELECT payload FROM catalog WHERE category=? AND id=?",[category,id])],true)
	if not result.get("ok",false):
		last_error="Pinned catalogue read failed."
		return {}
	var rows: Array = result["results"][0]
	if rows.size()!=1:
		return {}
	var data = JSON.parse_string(rows[0]["payload"])
	return data if data is Dictionary and data.get("index")==id else {}

func search(category: String,query: String,limit: int = 24) -> Dictionary:
	if not category in CAT.TABLES or not DTO.bounded_text(query,100) or limit<1 or limit>64:
		return {"ok":false,"error":"Invalid catalogue search."}
	var path = cat.database_path()
	if path.is_empty():
		return {"ok":false,"error":"Pinned catalogue unavailable."}
	var result = SQL.run(path,[SQL.stmt("SELECT id,name FROM catalog WHERE category=? AND (instr(lower(name),lower(?))>0 OR id=?) ORDER BY name COLLATE NOCASE,id LIMIT ?",[category,query.strip_edges(),query.strip_edges(),limit])],true)
	return {"ok":true,"ruleset":CAT.RULESET,"revision":CAT.REVISION,"records":result["results"][0]} if result.get("ok",false) else {"ok":false,"error":"Catalogue search failed."}

func official_definition(id: String,category: String = "equipment") -> Dictionary:
	if not category in ["equipment","magic-items"]:
		return {}
	var data = official(category,id)
	if data.is_empty():
		return {}
	# Keep complete immutable rules object. Weight calculation is the existing
	# edition-specific ammunition/pack display helper; absent remains null.
	var weight: Variant = null
	if category=="equipment":
		weight=DISPLAY.unit_weight(cat,id)
	var key = id if category=="equipment" else "magic:"+id
	return {"id":key,"origin":"official","catalog_category":category,"catalog_id":id,"catalog_revision":CAT.REVISION,"name":str(data.get("name",id)),"unit_weight_lb":weight,"attributes":data,"source_event_id":null}

func insert_definition(definition: Dictionary) -> Dictionary:
	return SQL.stmt("INSERT INTO item_definitions(id,origin,catalog_category,catalog_id,catalog_revision,name,unit_weight_lb,attributes,source_event_id) VALUES(?,?,?,?,?,?,?,?,?)",[definition["id"],definition["origin"],definition.get("catalog_category"),definition.get("catalog_id"),definition.get("catalog_revision"),definition["name"],definition.get("unit_weight_lb"),JSON.stringify(definition["attributes"]),definition.get("source_event_id")])

func legacy_definition(id: String) -> Dictionary:
	var known = official_definition(id.trim_prefix("magic:"),"magic-items" if id.begins_with("magic:") else "equipment")
	if not known.is_empty():
		return known
	known=official_definition(id,"magic-items")
	if not known.is_empty():
		# Preserve the original normalized item_id on migration.
		known["id"]=id
		return known
	return {"id":id,"origin":"legacy_unresolved","name":id,"unit_weight_lb":null,"attributes":{"warning":"Legacy definition unavailable; no mechanics inferred."},"source_event_id":null}

# Novel attributes are descriptive or typed numeric proposals, NOT executable
# effects. A custom weapon/magic object's mechanics remain unsupported until C3.
func custom_valid(proposal: Variant) -> bool:
	var keys = ["name","category","description","unit_weight_lb","cost_cp","properties","charges_max","attunement_required"]
	if proposal is Dictionary and proposal.has("mechanical_attributes"):
		keys.append("mechanical_attributes")
	if not DTO.exact_keys(proposal,keys) or not DTO.bounded_text(proposal["name"],100) or not DTO.bounded_text(proposal["description"],2000):
		return false
	if not proposal["category"] in ["gear","tool","weapon","armor","consumable","magic","container","object"] or (proposal["unit_weight_lb"]!=null and not DTO.number(proposal["unit_weight_lb"],0,1000000)) or (proposal["cost_cp"]!=null and not DTO.whole(proposal["cost_cp"])) or (proposal["charges_max"]!=null and not DTO.whole(proposal["charges_max"])) or (proposal["attunement_required"]!=null and not proposal["attunement_required"] is bool):
		return false
	if not proposal["properties"] is Array or proposal["properties"].size()>16:
		return false
	var seen: Array = []
	for property in proposal["properties"]:
		if not DTO.bounded_text(property,100) or property in seen:
			return false
		seen.append(property)
	var attrs = proposal.get("mechanical_attributes")
	if attrs!=null:
		if not DTO.exact_keys(attrs,["damage","armor_class_base","range_feet","physical_options"]):
			return false
		var damage = attrs["damage"]
		if damage!=null and (not DTO.exact_keys(damage,["count","sides","type"]) or not DTO.whole(damage["count"],1,100) or not damage["sides"] in [4,6,8,10,12,20,100] or not damage["type"] in ["acid","bludgeoning","cold","fire","force","lightning","necrotic","piercing","poison","psychic","radiant","slashing","thunder"]):
			return false
		if attrs["armor_class_base"]!=null and not DTO.whole(attrs["armor_class_base"],0,30):
			return false
		var reach = attrs["range_feet"]
		if reach!=null and (not DTO.exact_keys(reach,["normal","long"]) or not DTO.whole(reach["normal"],1,100000) or not DTO.whole(reach["long"],int(reach["normal"]),100000)):
			return false
		if not attrs["physical_options"] is Array or attrs["physical_options"].size()>12:
			return false
		var option_keys: Array = []
		for option in attrs["physical_options"]:
			if not DTO.exact_keys(option,["slot","grip"]) or not option["slot"] in UI.SLOTS or not option["grip"] in UI.GRIPS:
				return false
			var key = str(option["slot"])+":"+str(option["grip"])
			if key in option_keys:
				return false
			option_keys.append(key)
	return true

func from_row(row: Dictionary) -> Dictionary:
	var attrs = JSON.parse_string(str(row["attributes"]))
	if not attrs is Dictionary:
		return {}
	return {"id":row["id"],"origin":row["origin"],"catalog_category":row["catalog_category"],"catalog_id":row["catalog_id"],"catalog_revision":row["catalog_revision"],"name":row["name"],"unit_weight_lb":DTO.sql_number(row["unit_weight_lb"]),"attributes":attrs,"source_event_id":DTO.sql_int(row["source_event_id"])}

# Physical candidate categories only. C3 independently validates actual
# proficiency, hand conflicts, use, time and effects; no available offer yet.
func physical_options(definition: Dictionary) -> Array:
	if definition.get("origin")=="custom":
		var data = definition.get("attributes",{})
		if custom_valid(data) and data.get("mechanical_attributes") is Dictionary:
			return data["mechanical_attributes"]["physical_options"].duplicate(true)
		return []
	if definition.get("origin")!="official" or definition.get("catalog_category")!="equipment":
		return []
	var attrs: Dictionary = definition["attributes"]
	if attrs.get("armor_category") in ["Light","Medium","Heavy"]:
		return [{"slot":"body","grip":"worn"}]
	if attrs.get("armor_category")=="Shield":
		return [{"slot":"shield","grip":"one_handed"}]
	if attrs.has("weapon_category"):
		var properties = cat.references(attrs.get("properties",[]))
		if "two-handed" in properties:
			return [{"slot":"main_hand","grip":"two_handed"}]
		var options = [{"slot":"main_hand","grip":"one_handed"},{"slot":"off_hand","grip":"one_handed"}]
		if "versatile" in properties:
			options.append({"slot":"main_hand","grip":"two_handed"})
		return options
	return []


func exact_official_name(name: String) -> Dictionary:
	if not DTO.bounded_text(name,100):
		return {"ok":false,"error":"Invalid official name."}
	var path = cat.database_path()
	if path.is_empty():
		return {"ok":false,"error":"Pinned catalogue unavailable."}
	var result = SQL.run(path,[SQL.stmt("SELECT category,id FROM catalog WHERE category IN ('equipment','magic-items') AND lower(trim(name))=lower(trim(?)) ORDER BY category,id LIMIT 3",[name])],true)
	return {"ok":true,"records":result["results"][0]} if result.get("ok",false) else {"ok":false,"error":"Pinned definition search failed."}
