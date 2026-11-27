extends RefCounted
## Original 5e, level-one character builder. No AI controls numbers or choices.
const CATALOG = preload("res://rules/catalog.gd")
const ABILITIES = ["str","dex","con","int","wis","cha"]
const POINT_COST = {8:0,9:1,10:2,11:3,12:4,13:5,14:7,15:9}
const SUBCLASS_AT = {"cleric":1,"sorcerer":1,"warlock":1,"druid":2,"wizard":2,"barbarian":3,"bard":3,"fighter":3,"monk":3,"paladin":3,"ranger":3,"rogue":3}
const PRIORITY = {"barbarian":["str","con","dex","wis","cha","int"],"bard":["cha","dex","con","wis","int","str"],"cleric":["wis","con","str","dex","cha","int"],"druid":["wis","con","dex","int","cha","str"],"fighter":["str","con","dex","wis","cha","int"],"monk":["dex","wis","con","str","cha","int"],"paladin":["str","cha","con","wis","dex","int"],"ranger":["dex","wis","con","str","cha","int"],"rogue":["dex","con","int","wis","cha","str"],"sorcerer":["cha","con","dex","wis","int","str"],"warlock":["cha","con","dex","wis","int","str"],"wizard":["int","con","dex","wis","cha","str"]}
var cat = CATALOG.new()

func fresh() -> Dictionary:
	return {"name":"","race_id":"","subrace_id":"","class_id":"","subclass_id":"","background_id":"","sex":"","alignment":"Neutral","description":"","portrait":"","personality":"","ideal":"","bond":"","flaw":"","backstory":"","ability_method":"","base_scores":{},"roll_pool":[],"roll_history":[],"answers":{}}

func mod_for(score: int) -> int:
	return floori((score - 10) / 2.0)

func roll_scores(d: Dictionary, method: String) -> void:
	var pool: Array = []
	var history: Array = []
	if method == "roll":
		for i in range(6):
			var dice: Array = []
			for j in range(4):
				dice.append(randi_range(1,6))
			history.append(dice.duplicate())
			dice.sort()
			pool.append(int(dice[1])+int(dice[2])+int(dice[3]))
	elif method == "array":
		pool = [15,14,13,12,10,8]
	else:
		pool = [8,8,8,8,8,8]
	pool.sort()
	pool.reverse()
	d["base_scores"] = {}
	var priority = PRIORITY.get(d.get("class_id",""),ABILITIES)
	for i in range(6):
		d["base_scores"][priority[i]] = pool[i]
	d["ability_method"] = method
	d["roll_pool"] = pool
	d["roll_history"] = history
	d["answers"] = {}

func points_used(d: Dictionary) -> int:
	var total = 0
	for a in ABILITIES:
		var score = int(d.get("base_scores",{}).get(a,0))
		if not POINT_COST.has(score):
			return 999
		total += int(POINT_COST[score])
	return total

func record(d: Dictionary, table: String, key: String) -> Dictionary:
	return cat.get_record(table,str(d.get(key,"")))

func base(d: Dictionary) -> Dictionary:
	var race = record(d,"races","race_id")
	var sub = record(d,"subraces","subrace_id")
	var role = record(d,"classes","class_id")
	var bg = record(d,"backgrounds","background_id")
	var lv = cat.get_record("levels",str(d.get("class_id",""))+"-1")
	var slv = cat.get_record("levels",str(d.get("subclass_id",""))+"-1")
	var traits = cat.references(race.get("traits",[])) + cat.references(sub.get("racial_traits",[]))
	var features = cat.references(lv.get("features",[])) + cat.references(slv.get("features",[]))
	var p = cat.references(role.get("proficiencies",[])) + cat.references(bg.get("starting_proficiencies",[]))
	for id in traits:
		p.append_array(cat.references(cat.get_record("traits",id).get("proficiencies",[])))
	if d.get("subclass_id") == "life":
		p.append("heavy-armor")
	var profs: Array = []
	var duplicates: Array = []
	for id in p:
		if id in profs:
			var proficiency = cat.get_record("proficiencies",id)
			if id.begins_with("skill-") or proficiency.get("type","") in ["Artisan's Tools","Gaming Sets","Musical Instruments","Other","Vehicles"]:
				duplicates.append(id)
		else:
			profs.append(id)
	var langs = cat.references(race.get("languages",[]))
	if d.get("subclass_id") == "draconic" and not "draconic" in langs:
		langs.append("draconic")
	return {"race":race,"sub":sub,"role":role,"bg":bg,"level":lv,"traits":traits,"features":features,"profs":profs,"duplicates":duplicates,"langs":langs}

func option(table: String, id: String, amount: int = 1, caption: String = "") -> Dictionary:
	var label = caption if not caption.is_empty() else cat.title(table,id)
	if table == "equipment" and amount > 1:
		label = str(amount)+" × "+label
	return {"key":table+":"+id+":"+str(amount),"label":label,"parts":[{"table":table,"id":id,"quantity":amount}]}

func from_rows(table: String, records: Array) -> Array:
	var options: Array = []
	for rec in records:
		options.append(option(table,str(rec.get("index",""))))
	return options

func combine(a: Dictionary, b: Dictionary) -> Dictionary:
	return {"key":str(a["key"])+"+"+str(b["key"]),"label":str(a["label"])+" + "+str(b["label"]),"parts":a["parts"]+b["parts"]}

func combinations(options: Array, count: int, repeated: bool, start: int = 0) -> Array:
	if count <= 0:
		return [{"key":"","label":"","parts":[]}]
	var result: Array = []
	for i in range(start,options.size()):
		if count == 1:
			result.append(options[i])
		else:
			for tail in combinations(options,count-1,repeated,i if repeated else i+1):
				result.append(combine(options[i],tail))
		if result.size() > 5000:
			break
	return result

func expand_option(raw: Variant, table: String) -> Array:
	if raw is String:
		return [option("text",raw,1,raw.capitalize())]
	if not raw is Dictionary:
		return []
	match str(raw.get("option_type","")):
		"reference":
			return [option(table,str(raw["item"]["index"]))]
		"counted_reference":
			return [option(table,str(raw["of"]["index"]),int(raw.get("count",1)))]
		"ability_bonus":
			return [option("ability-scores",str(raw["ability_score"]["index"]),int(raw.get("bonus",1)))]
		"string":
			return [option("text",str(raw.get("string","")),1,str(raw.get("string","")))]
		"choice":
			var nested = raw.get("choice",{})
			var opts = choice_options(nested,table)
			return combinations(opts,int(nested.get("choose",1)),table=="equipment")
		"multiple":
			var result: Array = []
			for child in raw.get("items",[]):
				var next = expand_option(child,table)
				if result.is_empty():
					result = next
				else:
					var merged: Array = []
					for a in result:
						for b in next:
							merged.append(combine(a,b))
					result = merged
			return result
	return []

func choice_options(raw: Dictionary, table: String) -> Array:
	var src = raw.get("from",{})
	var result: Array = []
	match str(src.get("option_set_type","")):
		"options_array":
			for opt in src.get("options",[]):
				result.append_array(expand_option(opt,table))
		"equipment_category":
			var category = cat.get_record("equipment-categories",str(src.get("equipment_category",{}).get("index","")))
			for item in cat.references(category.get("equipment",[])):
				result.append(option(table,item))
		"resource_list":
			result = from_rows(table,cat.rows(table))
	return result

func selected(d: Dictionary, group: Dictionary) -> Array:
	var result: Array = []
	var keys = d.get("answers",{}).get(group["key"],[])
	for key in keys:
		for opt in group["options"]:
			if opt["key"] == key:
				result.append(opt)
				break
	return result

func selected_ids(d: Dictionary, group: Dictionary) -> Array:
	var ids: Array = []
	for opt in selected(d,group):
		for part in opt["parts"]:
			ids.append(str(part["id"]))
	return ids

func add_group(result: Array,d: Dictionary,key: String,label: String,kind: String,count: int,options: Array,blocked: Array = []) -> void:
	if count <= 0:
		return
	var valid: Array = []
	var unique: Dictionary = {}
	for opt in options:
		var allowed = true
		for part in opt["parts"]:
			if part["id"] in blocked:
				allowed = false
		if allowed and not unique.has(opt["key"]):
			valid.append(opt)
			unique[opt["key"]] = true
	var g = {"key":key,"label":label,"kind":kind,"count":count,"options":valid}
	result.append(g)

func raw_group(result: Array,d: Dictionary,key: String,label: String,kind: String,table: String,raw: Variant,blocked: Array = []) -> void:
	if not raw is Dictionary or raw.is_empty():
		return
	add_group(result,d,key,str(raw.get("desc",label)),kind,int(raw.get("choose",1)),choice_options(raw,table),blocked)

func scores(d: Dictionary) -> Dictionary:
	var b = base(d)
	var values: Dictionary = {}
	for a in ABILITIES:
		values[a] = int(d.get("base_scores",{}).get(a,0))
	for src in [b["race"],b["sub"]]:
		for entry in src.get("ability_bonuses",[]):
			var a = str(entry["ability_score"]["index"])
			if values.has(a):
				values[a] = int(values[a])+int(entry["bonus"])
	for g in groups(d,2):
		for opt in selected(d,g):
			for p in opt["parts"]:
				if values.has(p["id"]):
					values[p["id"]] = int(values[p["id"]])+int(p["quantity"])
	return values

func collect(result: Array,d: Dictionary,kind: String) -> Array:
	var ids: Array = []
	for g in result:
		if g["kind"] == kind:
			ids.append_array(selected_ids(d,g))
	return ids

func groups(d: Dictionary,step: int) -> Array:
	var b = base(d)
	var result: Array = []
	var race = b["race"]
	var role = b["role"]
	var bg = b["bg"]
	var role_id = str(d.get("class_id",""))
	var sub_id = str(d.get("subclass_id",""))
	if step == 2:
		raw_group(result,d,"race-bonus","Racial ability increases","bonus","ability-scores",race.get("ability_bonus_options"))
		return result
	if step == 3:
		var p = b["profs"].duplicate()
		var languages = b["langs"].duplicate()
		var all_skills: Array = []
		for skill in cat.rows("skills"):
			all_skills.append(option("proficiencies","skill-"+str(skill["index"])))
		var all_tools: Array = []
		for proficiency in cat.rows("proficiencies"):
			if proficiency.get("type","") in ["Artisan's Tools","Gaming Sets","Musical Instruments","Other","Vehicles"]:
				all_tools.append(option("proficiencies",str(proficiency["index"])))
		for i in range(b["duplicates"].size()):
			var skill_duplicate = str(b["duplicates"][i]).begins_with("skill-")
			add_group(result,d,"replacement-"+str(i),"Replace overlapping skill proficiency" if skill_duplicate else "Replace overlapping tool proficiency","profs",1,all_skills if skill_duplicate else all_tools,p)
			p.append_array(selected_ids(d,result.back()))
		var i = 0
		for raw in role.get("proficiency_choices",[])+bg.get("proficiency_choices",[]):
			raw_group(result,d,"prof-"+str(i),"Choose proficiency","profs","proficiencies",raw,p)
			p.append_array(selected_ids(d,result.back()))
			i += 1
		for t in b["traits"]:
			var tr = cat.get_record("traits",t)
			if tr.has("proficiency_choices"):
				raw_group(result,d,"trait-prof-"+t,"Racial proficiency","profs","proficiencies",tr["proficiency_choices"],p)
				p.append_array(selected_ids(d,result.back()))
			if tr.has("language_options"):
				raw_group(result,d,"trait-language-"+t,"Extra language","languages","languages",tr["language_options"],languages)
				languages.append_array(selected_ids(d,result.back()))
			if t == "high-elf-cantrip":
				add_group(result,d,"racial-cantrip","High Elf: Wizard cantrip (INT)","racial-spell",1,from_rows("spells",cat.spell_rows("wizard",0)))
			if t == "draconic-ancestry":
				raw_group(result,d,"dragon-ancestry","Dragonborn ancestry","traits","traits",tr.get("trait_specific",{}).get("subtrait_options"))
		for src in [race,bg]:
			if src.get("language_options") is Dictionary:
				raw_group(result,d,"language-"+str(src["index"]),"Choose language","languages","languages",src["language_options"],languages)
				languages.append_array(selected_ids(d,result.back()))
		for f in b["features"]:
			var feature = cat.get_record("features",f)
			var specific = feature.get("feature_specific",{})
			if specific.has("subfeature_options"):
				raw_group(result,d,"feature-"+f,cat.title("features",f),"features","features",specific["subfeature_options"])
		if role_id == "rogue":
			var expertise: Array = []
			for id in p:
				if id.begins_with("skill-") or id == "thieves-tools":
					expertise.append(option("proficiencies",id))
			add_group(result,d,"expertise","Expertise: two trained skills or a skill and thieves' tools","expertise",2,expertise)
		if role_id == "ranger":
			var enemies: Array = []
			for id in ["aberrations","beasts","celestials","constructs","dragons","elementals","fey","fiends","giants","monstrosities","oozes","plants","undead"]:
				enemies.append(option("text",id))
			add_group(result,d,"favored-enemy","Favored enemy type (humanoid-pair option pending)","favored-enemy",1,enemies)
			var terrain: Array = []
			for id in ["arctic","coast","desert","forest","grassland","mountain","swamp","underdark"]:
				terrain.append(option("text",id))
			add_group(result,d,"favored-terrain","Natural Explorer terrain","terrain",1,terrain)
			add_group(result,d,"enemy-language","Favored enemy language — verify against creature languages","enemy-language",1,from_rows("languages",cat.rows("languages"))+[option("text","none",1,"None (no spoken language)")],languages)
		var sp = b["level"].get("spellcasting",{})
		var cantrips = int(sp.get("cantrips_known",0))
		if cantrips > 0:
			add_group(result,d,"class-cantrips","Class cantrips","cantrips",cantrips,from_rows("spells",cat.spell_rows(role_id,0)))
		if int(sp.get("spell_slots_level_1",0)) > 0:
			var list = from_rows("spells",cat.spell_rows(role_id,1,sub_id if role_id=="warlock" else ""))
			var ability = str(role.get("spellcasting",{}).get("spellcasting_ability",{}).get("index",""))
			var prep = maxi(1,mod_for(int(scores(d).get(ability,10)))+1)
			if role_id == "wizard":
				add_group(result,d,"spellbook","Spellbook: six first-level spells","known-spells",6,list)
				var book = selected_ids(d,result.back())
				var available: Array = []
				for opt in list:
					if opt["parts"][0]["id"] in book:
						available.append(opt)
				add_group(result,d,"prepared","Prepared from spellbook","prepared",prep,available)
			elif role_id in ["cleric","druid"]:
				add_group(result,d,"prepared","Prepared spells (domain spells are separate)","prepared",prep,list,["bless","cure-wounds"] if sub_id=="life" else [])
			else:
				add_group(result,d,"known","First-level spells known","known-spells",int(sp.get("spells_known",0)),list)
		return result
	if step == 4:
		var gear = role.get("starting_equipment_options",[]).duplicate(true)
		if d.get("background_id") != "folk-hero":
			gear.append_array(bg.get("starting_equipment_options",[]))
		for i in range(gear.size()):
			var raw = gear[i]
			var blocked: Array = []
			if role_id == "cleric":
				var trained = b["profs"]+collect(groups(d,3),d,"profs")
				if not "heavy-armor" in trained:
					blocked.append("chain-mail")
				if not "martial-weapons" in trained and not "warhammers" in trained:
					blocked.append("warhammer")
			raw_group(result,d,"equipment-"+str(i),"Starting equipment","gear","equipment",raw,blocked)
		return result
	return result

func validate_step(d: Dictionary,step: int) -> String:
	if not cat.initialize():
		return "Rules database unavailable."
	if step == 1:
		if str(d.get("name","")).strip_edges().is_empty():
			return "Enter a character name."
		var b = base(d)
		if b["race"].is_empty() or b["role"].is_empty() or b["bg"].is_empty():
			return "Choose a race, class and background."
		if (not b["race"].get("subraces",[]).is_empty() or not str(d.get("subrace_id","")).is_empty()) and not d.get("subrace_id") in cat.references(b["race"].get("subraces",[])):
			return "Choose an eligible subrace."
		if int(SUBCLASS_AT.get(d.get("class_id"),99)) == 1 and not d.get("subclass_id") in cat.references(b["role"].get("subclasses",[])):
			return "Choose a level-one subclass."
		if int(SUBCLASS_AT.get(d.get("class_id"),99)) != 1 and not str(d.get("subclass_id","")).is_empty():
			return "This class chooses its subclass later."
	if step == 2:
		var method = str(d.get("ability_method",""))
		if not method in ["roll","array","point"]:
			return "Choose an ability generation method."
		if method == "point":
			if points_used(d) > 27:
				return "Point-buy exceeds the 27-point budget or 8–15 score limits."
		else:
			var assigned: Array = []
			for a in ABILITIES:
				assigned.append(int(d.get("base_scores",{}).get(a,0)))
			assigned.sort()
			var pool = d.get("roll_pool",[]).duplicate()
			pool.sort()
			if pool.size()!=6 or assigned != pool:
				return "Assign each score from the generated pool exactly once."
			if method == "array" and pool != [8,10,12,13,14,15]:
				return "Invalid standard array."
			if method == "roll":
				var history = d.get("roll_history",[])
				if history.size()!=6:
					return "Missing recorded dice rolls."
				var totals: Array = []
				for row in history:
					if not row is Array or row.size()!=4:
						return "Invalid dice history."
					var dice = row.duplicate()
					for v in dice:
						if int(v)<1 or int(v)>6:
							return "Invalid die value."
					dice.sort()
					totals.append(int(dice[1])+int(dice[2])+int(dice[3]))
				totals.sort()
				if totals!=pool:
					return "Recorded rolls do not match the assigned pool."
	for g in groups(d,step):
		var picks = selected(d,g)
		if picks.size()!=int(g["count"]):
			return "Complete: " + str(g["label"])
		var keys: Array = []
		var parts: Array = []
		for opt in picks:
			if opt["key"] in keys:
				return "Choose distinct options: " + str(g["label"])
			keys.append(opt["key"])
			if g["kind"] != "gear":
				for p in opt["parts"]:
					if p["id"] in parts:
						return "Duplicate selection: " + str(g["label"])
					parts.append(p["id"])
	return ""

func add_inventory(inv: Dictionary,id: String,quantity: int) -> void:
	if quantity <= 0:
		return
	var item = cat.get_record("equipment",id)
	if item.is_empty():
		inv[id] = int(inv.get(id,0))+quantity
		return
	var contents = item.get("contents",[])
	if not contents.is_empty():
		for child in contents:
			add_inventory(inv,str(child.get("item",{}).get("index","")),int(child.get("quantity",1))*quantity)
	else:
		inv[id] = int(inv.get(id,0))+quantity

func full_record(d: Dictionary) -> Dictionary:
	var b = base(d)
	var s = scores(d)
	var mods: Dictionary = {}
	var saving: Dictionary = {}
	var profs = b["profs"].duplicate()
	var gs = groups(d,3)
	profs.append_array(collect(gs,d,"profs"))
	var traits = b["traits"] + collect(gs,d,"traits")
	var features = b["features"] + collect(gs,d,"features")
	var languages = b["langs"]+collect(gs,d,"languages")
	for id in collect(gs,d,"enemy-language"):
		if id != "none" and not id in languages:
			languages.append(id)
	var expertise = collect(gs,d,"expertise")
	for a in ABILITIES:
		mods[a] = mod_for(int(s[a]))
		saving[a] = int(mods[a])+(2 if ("saving-throw-"+a) in profs else 0)
	var skill_values: Dictionary = {}
	for skill in cat.rows("skills"):
		var id = str(skill["index"])
		var trained = "skill-"+id in profs
		var expert = "skill-"+id in expertise
		skill_values[id] = {"ability":skill["ability_score"]["index"],"proficient":trained,"expertise":expert,"modifier":int(mods[skill["ability_score"]["index"]])+(4 if expert else (2 if trained else 0))}
	var inventory: Dictionary = {}
	for src in [b["role"],b["bg"]]:
		for item in src.get("starting_equipment",[]):
			add_inventory(inventory,str(item["equipment"]["index"]),int(item.get("quantity",1)))
	for g in groups(d,4):
		for opt in selected(d,g):
			for p in opt["parts"]:
				add_inventory(inventory,str(p["id"]),int(p["quantity"]))
	if d.get("background_id") == "folk-hero":
		for g in gs:
			if str(g["label"]) == "Artisan tool proficiency":
				for id in selected_ids(d,g):
					add_inventory(inventory,id,1)
	var armor = ""
	var shield = ""
	var ac = 10+int(mods["dex"])
	var role_id = str(d.get("class_id",""))
	if role_id == "barbarian":
		ac += int(mods["con"])
	if role_id == "monk":
		ac += int(mods["wis"])
	if d.get("subclass_id") == "draconic":
		ac = 13+int(mods["dex"])
	for id in inventory:
		var item = cat.get_record("equipment",id)
		var category = str(item.get("armor_category",""))
		if category == "Shield" and "shields" in profs and role_id != "monk":
			shield = id
		elif category in ["Light","Medium","Heavy"] and category.to_lower()+"-armor" in profs:
			var value = int(item.get("armor_class",{}).get("base",10))
			if item.get("armor_class",{}).get("dex_bonus",false):
				var dex = int(mods["dex"])
				if item["armor_class"].has("max_bonus"):
					dex = mini(dex,int(item["armor_class"]["max_bonus"]))
				value += dex
			if value > ac:
				armor = id
				ac = value
	if d.has("equipped_armor") or d.has("equipped_shield"):
		var selected_armor = str(d.get("equipped_armor",armor))
		var selected_shield = str(d.get("equipped_shield",shield))
		if selected_armor.is_empty() or (inventory.has(selected_armor) and cat.get_record("equipment",selected_armor).get("armor_category","") in ["Light","Medium","Heavy"]):
			armor=selected_armor
		if selected_shield.is_empty() or (inventory.has(selected_shield) and cat.get_record("equipment",selected_shield).get("armor_category","")=="Shield"):
			shield=selected_shield
		ac=10+int(mods["dex"])
		if armor.is_empty():
			if role_id=="barbarian": ac+=int(mods["con"])
			if role_id=="monk" and shield.is_empty(): ac+=int(mods["wis"])
			if d.get("subclass_id")=="draconic": ac=13+int(mods["dex"])
		else:
			var ar=cat.get_record("equipment",armor).get("armor_class",{})
			ac=int(ar.get("base",10))
			if ar.get("dex_bonus",false): ac+=mini(int(mods["dex"]),int(ar.get("max_bonus",99)))
	if not shield.is_empty():
		ac += 2
	if not armor.is_empty() and "fighter-fighting-style-defense" in features:
		ac += 1
	var hit_die = int(b["role"].get("hit_die",0))
	var hp = maxi(1,hit_die + int(mods["con"]))
	if "dwarven-toughness" in traits:
		hp += 1
	if d.get("subclass_id") == "draconic":
		hp += 1
	var cantrips = collect(gs,d,"cantrips")
	var racial = collect(gs,d,"racial-spell")
	if "infernal-legacy" in traits:
		racial.append("thaumaturgy")
	var prepared = collect(gs,d,"prepared")
	var always: Array = ["bless","cure-wounds"] if d.get("subclass_id")=="life" else []
	var casting = str(b["role"].get("spellcasting",{}).get("spellcasting_ability",{}).get("index",""))
	if int(b["level"].get("spellcasting",{}).get("spell_slots_level_1",0))==0:
		casting=""
	var slots: Dictionary = {}
	for i in range(1,10):
		slots[str(i)] = {"maximum":int(b["level"].get("spellcasting",{}).get("spell_slots_level_"+str(i),0)),"spent":0}
	var spell_data = {"ability":casting,"save_dc":8+2+int(mods.get(casting,0)) if not casting.is_empty() and int(slots["1"]["maximum"])>0 else null,"attack_bonus":2+int(mods.get(casting,0)) if not casting.is_empty() and int(slots["1"]["maximum"])>0 else null,"cantrip_ids":cantrips,"racial_cantrip_ids":racial,"racial_casting_ability":"int" if d.get("subrace_id")=="high-elf" else ("cha" if d.get("race_id")=="tiefling" else ""),"known_ids":collect(gs,d,"known-spells"),"prepared_ids":prepared,"always_prepared_ids":always,"slots":slots,"pact_magic":role_id=="warlock","concentration":null}
	var resources: Dictionary = {}
	match role_id:
		"barbarian": resources["rage"]={"max":2,"spent":0,"reset":"long_rest"}
		"bard": resources["bardic_inspiration"]={"max":maxi(1,int(mods["cha"])),"spent":0,"reset":"long_rest","die":"1d6"}
		"fighter": resources["second_wind"]={"max":1,"spent":0,"reset":"short_or_long_rest"}
		"paladin":
			resources["lay_on_hands"]={"max":5,"spent":0,"reset":"long_rest"}
			resources["divine_sense"]={"max":maxi(1,1+int(mods["cha"])),"spent":0,"reset":"long_rest"}
		"wizard": resources["arcane_recovery"]={"max":1,"spent":0,"reset":"long_rest","recover_slot_levels":1}
	if "breath-weapon" in traits: resources["breath_weapon"]={"max":1,"spent":0,"reset":"short_or_long_rest","save_dc":10+int(mods["con"])}
	if "relentless-endurance" in traits: resources["relentless_endurance"]={"max":1,"spent":0,"reset":"long_rest"}
	var attacks: Array = []
	for id in inventory:
		var weapon = cat.get_record("equipment",id)
		if not weapon.has("weapon_category"):
			continue
		var trained = str(weapon["weapon_category"]).to_lower()+"-weapons" in profs
		for proficiency in profs:
			var pr = cat.get_record("proficiencies",proficiency)
			if pr.get("reference",{}).get("index") == id:
				trained = true
		var ability = "dex" if weapon.get("weapon_range") == "Ranged" else "str"
		if role_id == "monk" and armor.is_empty() and shield.is_empty() and (id == "shortsword" or (weapon.get("weapon_category") == "Simple" and weapon.get("weapon_range") == "Melee" and not "two-handed" in cat.references(weapon.get("properties",[])))) and int(mods["dex"]) > int(mods["str"]):
			ability="dex"
		if "finesse" in cat.references(weapon.get("properties",[])) and int(mods["dex"]) > int(mods["str"]):
			ability = "dex"
		var attack_bonus = int(mods[ability])+(2 if trained else 0)
		if weapon.get("weapon_range") == "Ranged" and "fighter-fighting-style-archery" in features:
			attack_bonus += 2
		attacks.append({"item_id":id,"ability":ability,"proficient":trained,"attack_bonus":attack_bonus,"damage_dice":weapon.get("damage",{}).get("damage_dice",""),"damage_modifier":mods[ability],"damage_type":weapon.get("damage",{}).get("damage_type",{}).get("index",""),"range":weapon.get("range",{})})
	var equipped_weapons: Array = []
	for id in d.get("equipped_weapons",[]):
		if inventory.has(id) and cat.get_record("equipment",id).has("weapon_category") and not id in equipped_weapons:
			equipped_weapons.append(id)
	var items: Array = []
	for id in inventory:
		items.append({"item_id":id,"quantity":inventory[id],"equipped":id==armor or id==shield or id in equipped_weapons})
	var speed = int(b["sub"].get("speed",b["race"].get("speed",0)))
	if not armor.is_empty() and d.get("race_id")!="dwarf" and int(cat.get_record("equipment",armor).get("str_minimum",0))>int(s["str"]):
		speed=maxi(0,speed-10)
	var weight = 0.0
	for item in items:
		var w = cat.get_record("equipment",item["item_id"]).get("weight")
		if w is float or w is int: weight += float(w)*int(item["quantity"])
	var review: Array = []
	var hands = 0 if shield.is_empty() else 1
	for id in equipped_weapons:
		hands+=2 if "two-handed" in cat.references(cat.get_record("equipment",id).get("properties",[])) else 1
	if hands>2: review.append("Equipped weapons and shield require more than two hands.")
	var armor_proficient = armor.is_empty() or str(cat.get_record("equipment",armor).get("armor_category","")).to_lower()+"-armor" in profs
	var shield_proficient = shield.is_empty() or "shields" in profs
	if role_id == "ranger":
		review.append("Favored enemy language and humanoid-pair alternatives require a rule review.")
	if role_id == "cleric":
		for it in items:
			if it["item_id"] == "warhammer" and not "martial-weapons" in profs and not "warhammers" in profs:
				review.append("Warhammer starting choice requires proficiency.")
	for it in items:
		if cat.get_record("equipment",it["item_id"]).is_empty():
			review.append("Unresolved equipment reference: "+it["item_id"])
	var passive = 10+int(skill_values.get("perception",{}).get("modifier",0))
	return {"schema_version":1,"ruleset":CATALOG.RULESET,"catalog_revision":CATALOG.REVISION,"name":d.get("name",""),"race_id":d.get("race_id",""),"subrace_id":d.get("subrace_id",""),"class_id":role_id,"subclass_id":d.get("subclass_id",""),"background_id":d.get("background_id",""),"level":1,"xp":0,"sex":d.get("sex",""),"alignment":d.get("alignment",""),"description":d.get("description",""),"portrait":d.get("portrait",""),"personality":d.get("personality",""),"ideal":d.get("ideal",""),"bond":d.get("bond",""),"flaw":d.get("flaw",""),"backstory":d.get("backstory",""),"ability_scores":s,"ability_modifiers":mods,"base_scores":d.get("base_scores",{}),"ability_method":d.get("ability_method",""),"dice_history":d.get("roll_history",[]),"proficiency_bonus":2,"proficiency_ids":profs,"expertise_ids":expertise,"saving_throws":saving,"skills":skill_values,"language_ids":languages,"racial_trait_ids":traits,"class_feature_ids":features,"background_feature":b["bg"].get("feature",{}),"spellcasting":spell_data,"inventory":items,"coins":{"cp":0,"sp":0,"ep":0,"gp":int(b["bg"].get("starting_gold",{}).get("quantity",0)),"pp":0},"equipment":{"armor_id":armor,"shield_id":shield,"weapon_ids":equipped_weapons,"armor_proficient":armor_proficient,"shield_proficient":shield_proficient,"armor_penalty":not armor_proficient or not shield_proficient},"attacks":attacks,"resources":resources,"carried_weight_lb":weight,"carrying_capacity_lb":15*int(s["str"]),"favored_enemy_ids":collect(gs,d,"favored-enemy"),"favored_terrain_ids":collect(gs,d,"terrain"),"combat":{"armor_class":ac,"hp_max":hp,"hp_current":hp,"hp_temp":0,"initiative":mods["dex"],"speed_feet":speed,"size":b["race"].get("size",""),"passive_perception":passive,"hit_die":hit_die,"hit_dice_total":1,"hit_dice_spent":0,"death_save_successes":0,"death_save_failures":0,"inspiration":false,"conditions":[],"exhaustion":0,"active_effects":[]},"review_required":review,"draft":d.duplicate(true)}
