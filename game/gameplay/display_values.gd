extends RefCounted
## Read-only display projection; never persist these derived values.
## PHB 2014 pp. 143, 150–151: 50 coins/lb; ammunition weights per lot.
const COINS = ["pp","gp","ep","sp","cp"]
const AMMO_LOTS = {"arrow":20,"crossbow-bolt":20,"blowgun-needle":50,"sling-bullet":20}

static func numeric(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func nonnegative_integer(value: Variant) -> bool:
	return numeric(value) and float(value)>=0 and floor(float(value))==float(value)

static func weight_number(value: Variant) -> String:
	if not numeric(value):
		return "—"
	var result = String.num(float(value),3)
	if result.contains("."):
		while result.ends_with("0"):
			result = result.trim_suffix("0")
		result = result.trim_suffix(".")
	return result

static func unit_weight(cat, id: String, ancestors: Array = []) -> Variant:
	if id.is_empty() or id in ancestors or ancestors.size()>=16:
		return null
	var rec = cat.get_record("equipment",id)
	var raw = rec.get("weight")
	if numeric(raw) and float(raw)>=0:
		return float(raw)/float(AMMO_LOTS.get(id,1))
	# Character creation normally expands packs. Support legacy pack rows.
	var contents = rec.get("contents",[])
	if not contents is Array or contents.is_empty():
		return null
	var total = 0.0
	for child in contents:
		if not child is Dictionary or not child.get("item") is Dictionary or not nonnegative_integer(child.get("quantity")):
			return null
		var weight = unit_weight(cat,str(child["item"].get("index","")),ancestors+[id])
		if weight==null:
			return null
		total += float(weight)*float(child["quantity"])
	return total

static func weight_summary(cat, items: Array, coins: Variant) -> Dictionary:
	var known = 0.0
	var missing: Array = []
	for item in items:
		var id = str(item.get("item_id",""))
		var weight = unit_weight(cat,id)
		if weight==null or not nonnegative_integer(item.get("quantity")):
			missing.append(id)
		else:
			known += float(weight)*float(item["quantity"])
	for denomination in COINS:
		var amount = coins.get(denomination) if coins is Dictionary else null
		if nonnegative_integer(amount):
			known += float(amount)/50.0
		else:
			missing.append("coin "+denomination)
	return {"known_lb":known,"complete":missing.is_empty(),"missing":missing}

static func load_text(actor: Dictionary) -> String:
	var summary = actor.get("weight_projection",{})
	var capacity = weight_number(actor.get("carrying_capacity_lb"))
	if summary.is_empty():
		return weight_number(actor.get("carried_weight_lb"))+" / "+capacity+" lb"
	return weight_number(summary.get("known_lb"))+(" / " if summary.get("complete",false) else "+ / ")+capacity+" lb"+("" if summary.get("complete",false) else " (partial)")

static func remaining_text(maximum: Variant, spent: Variant) -> String:
	var max_text = str(int(maximum)) if nonnegative_integer(maximum) else "—"
	if not nonnegative_integer(maximum) or not nonnegative_integer(spent) or float(spent)>float(maximum):
		return "— / "+max_text
	return str(int(maximum)-int(spent))+" / "+max_text

static func racial_spell_text(actor: Dictionary) -> String:
	var sp = actor.get("spellcasting",{})
	if sp.get("racial_cantrip_ids",[]).is_empty():
		return ""
	var ability = str(sp.get("racial_casting_ability",""))
	if ability.is_empty():
		return "Racial casting ability not recorded"
	var modifier = actor.get("ability_modifiers",{}).get(ability)
	var proficiency = actor.get("proficiency_bonus")
	if not numeric(modifier) or floor(float(modifier))!=float(modifier) or not nonnegative_integer(proficiency):
		return "Racial casting ("+ability.to_upper()+") — DC/attack not recorded"
	var attack = int(modifier)+int(proficiency)
	return "Racial casting ("+ability.to_upper()+") · Save DC "+str(8+attack)+" · Attack "+("%+d" % attack)

static func slot_item(cat, id: String, kind: String, item_map: Dictionary, warnings: Array) -> String:
	if id.is_empty():
		return ""
	if not item_map.has(id) or item_map[id].get("equipped")!=true:
		warnings.append("Slot references absent or unequipped item: "+id)
		return ""
	var rec = cat.get_record("equipment",id)
	if not rec.is_empty():
		var valid = false
		match kind:
			"armor": valid = rec.get("armor_category","") in ["Light","Medium","Heavy"]
			"shield": valid = rec.get("armor_category","")=="Shield"
			"weapon": valid = rec.has("weapon_category")
		if not valid:
			warnings.append("Slot item has incompatible catalogue category: "+id)
			return ""
	return id

static func project_inventory(cat, actor: Dictionary, items: Array) -> void:
	var warnings: Array = []
	var gear = actor.get("equipment",{}).duplicate(true)
	var item_map: Dictionary = {}
	var claims: Array = gear.get("weapon_ids",[]).duplicate()
	claims.append(str(gear.get("armor_id","")))
	claims.append(str(gear.get("shield_id","")))
	for item in items:
		var id = str(item.get("item_id",""))
		# Explicit row flag wins; legacy missing flag falls back to stored slot.
		if not item.get("equipped") is bool:
			item["equipped"] = id in claims
			warnings.append("Inventory equipped flag missing: "+id+" (stored slot fallback)")
		item_map[id]=item
	gear["armor_id"] = slot_item(cat,str(gear.get("armor_id","")),"armor",item_map,warnings)
	gear["shield_id"] = slot_item(cat,str(gear.get("shield_id","")),"shield",item_map,warnings)
	var weapons: Array = []
	for id in gear.get("weapon_ids",[]):
		var valid_id = slot_item(cat,str(id),"weapon",item_map,warnings)
		if not valid_id.is_empty() and not valid_id in weapons:
			weapons.append(valid_id)
	gear["weapon_ids"] = weapons
	var displayed_slots: Array = weapons.duplicate()
	displayed_slots.append(gear["armor_id"])
	displayed_slots.append(gear["shield_id"])
	for item in items:
		if item.get("equipped")==true and not str(item.get("item_id","")) in displayed_slots:
			warnings.append("Equipped item has no supported stored slot: "+str(item["item_id"]))
	actor["equipment"] = gear
	actor["inventory"] = items
	var attacks: Array = []
	for attack in actor.get("attacks",[]):
		var id = str(attack.get("item_id",""))
		if id.is_empty() or item_map.has(id):
			attacks.append(attack)
		else:
			warnings.append("Attack references absent inventory item: "+id)
	actor["attacks"] = attacks
	actor["display_warnings"] = warnings
	actor["weight_projection"] = weight_summary(cat,items,actor.get("coins"))
	actor["carried_weight_lb"] = actor["weight_projection"]["known_lb"] if actor["weight_projection"]["complete"] else null
