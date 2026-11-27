extends "res://persistence/gameplay_session.gd"
## Local actor generation. Canonical monster/NPC block is preserved verbatim.
const ITEMS = preload("res://persistence/item_catalog.gd")
const CAT = preload("res://rules/catalog.gd")
const BATCH = preload("res://rules/batch_catalog.gd")
const DISPLAY = preload("res://gameplay/display_values.gd")
const ABILITY_KEYS = {"str":"strength","dex":"dexterity","con":"constitution","int":"intelligence","wis":"wisdom","cha":"charisma"}
const FIRST_NAMES = ["Aerin","Talan","Mira","Corin","Seren","Riven","Mara","Finn","Elin","Rowan","Tessa","Bram"]
const LAST_NAMES = ["Starbrook","Ashfield","Greywood","Stormvale","Dawnmere","Stonebrook","Willowmere","Oakfield"]
const DENOMINATIONS = ["cp","sp","ep","gp","pp"]

func template(id: String) -> Dictionary:
	var catalogue = ITEMS.new()
	var block = catalogue.official("monsters",id)
	if not catalogue.last_error.is_empty():
		return {}
	var revision = CAT.REVISION
	# The shipped reviewed 2014 core batch is lower coverage, not a replacement
	# for a full official record. Its SQL cache is the existing batch service.
	if block.is_empty():
		var batch = BATCH.new()
		for row in batch.rows():
			if row["category"]=="monsters" and row["id"]==id:
				var candidate = JSON.parse_string(row["payload"])
				if candidate is Dictionary:
					block=candidate
					revision="2014-creature-core-batch-001"
				break
	if block.is_empty() or block.get("index")!=id or not DTO.bounded_text(block.get("name"),100) or not DTO.whole(block.get("hit_points"),1,100000):
		return {}
	var abilities: Dictionary = {}
	for key in ABILITY_KEYS:
		var score = block.get(ABILITY_KEYS[key])
		if not DTO.whole(score,1,30):
			return {}
		abilities[key]=int(score)
	var ac = block.get("armor_class")
	var ac_value: Variant = null
	if DTO.whole(ac,0,100):
		ac_value=int(ac)
	elif ac is Array and ac.size()==1 and ac[0] is Dictionary and DTO.whole(ac[0].get("value"),0,100):
		ac_value=int(ac[0]["value"])
	if ac_value==null:
		return {}
	# Preserve the complete template (including multiple AC variants where
	# supported later). Missing fields are explicit gaps, not fabricated.
	var gaps: Array = []
	for key in ["actions","proficiencies","special_abilities","alignment","speed"]:
		if not block.has(key):
			gaps.append(key)
	return {"id":id,"revision":revision,"block":block,"ability_scores":abilities,"armor_class":ac_value,"hp":int(block["hit_points"]),"coverage_gaps":gaps}

func coins_valid(coins: Variant) -> bool:
	if coins==null:
		return true
	if not DTO.exact_keys(coins,DENOMINATIONS):
		return false
	for key in DENOMINATIONS:
		if not DTO.whole(coins[key]):
			return false
	return true

func item_rows(state: Dictionary,ids: Array) -> Dictionary:
	var result: Dictionary = {}
	for id in ids:
		var r = read(state,[SQL.stmt("SELECT * FROM item_definitions WHERE id=?",[id])])
		if not r.get("ok",false):
			return {}
		if r["sets"][0].size()==1:
			var definition = ITEMS.new().from_row(r["sets"][0][0])
			if definition.is_empty():
				return {}
			result[id]=definition
		else:
			var cat = ITEMS.new()
			var definition = cat.official_definition(id.trim_prefix("magic:"),"magic-items" if id.begins_with("magic:") else "equipment")
			if definition.is_empty():
				return {}
			result[id]=definition
	return result

# Generate a named individual once, or attach an immutable block to an existing
# descriptive NPC. The template list and possessions are trusted locally reviewed
# contextual options, never a provider-controlled rule/equipment patch.
# No player master creation, class progression, roll or stat override.
func generate(id: String,request: Dictionary,local_review: bool = false) -> Dictionary:
	var ctx = begin(id,request,"actor_generate",["generation_key","template_ids","existing_actor_id","kind","name","occupation","location_id","visibility","sheet_visibility","source_event_id","possessions","coins","attitude"])
	if not ctx.get("ok",false) or ctx.get("replayed",false):
		return ctx
	if not local_review:
		return fail("Trusted local actor generation review required.")
	var state: Dictionary = ctx["state"]
	var args: Dictionary = request["args"]
	if not DTO.id_valid(args["generation_key"]) or not args["kind"] in ["npc","enemy"] or not DTO.id_valid(args["location_id"]) or not args["visibility"] in ["player","private"] or not args["sheet_visibility"] in ["public","private"] or (args["visibility"]=="private" and args["sheet_visibility"]=="public") or not DTO.bounded_text(args["occupation"],100) or (args["name"]!=null and not DTO.bounded_text(args["name"],80)) or (args["attitude"]!=null and not DTO.whole(args["attitude"],-5,5)) or not coins_valid(args["coins"]):
		return fail("Invalid individual identity or contextual fields.")
	if not args["template_ids"] is Array or args["template_ids"].is_empty() or args["template_ids"].size()>16 or not args["possessions"] is Array or args["possessions"].size()>32 or (args["existing_actor_id"]!=null and not DTO.id_valid(args["existing_actor_id"])):
		return fail("Invalid template or possession options.")
	var event = source(state,args["source_event_id"])
	if event.is_empty() or (args["visibility"]=="player" and not public_source(event)):
		return fail("Actor generation needs established source/disclosure.")
	var lookup = read(state,[SQL.stmt("SELECT i.actor_id,a.kind,a.location_id,t.catalog_id FROM actor_instances i JOIN actors a ON a.id=i.actor_id LEFT JOIN actor_templates t ON t.id=i.template_id WHERE i.generation_key=?",[args["generation_key"]]),SQL.stmt("SELECT l.id,d.visibility,d.status FROM locations l LEFT JOIN world_discovery d ON d.location_id=l.id WHERE l.id=?",[args["location_id"]]),SQL.stmt("SELECT id,kind,location_id,payload,catalog_id FROM actors WHERE id=?",[args["existing_actor_id"]])])
	if not lookup.get("ok",false):
		return lookup
	var sets: Array = lookup["sets"]
	if not sets[0].is_empty():
		var old = sets[0][0]
		if old["kind"]!=args["kind"] or not old["catalog_id"] in args["template_ids"] or (args["existing_actor_id"]!=null and old["actor_id"]!=args["existing_actor_id"]):
			return fail("Generation key already belongs to a different individual.")
		return {"ok":true,"replayed":true,"result":{"actor_id":old["actor_id"]}}
	if sets[1].size()!=1 or (args["visibility"]=="player" and (sets[1][0]["visibility"]!="player" or sets[1][0]["status"]=="unknown")):
		return fail("Location not established or disclosed.")
	var templates: Array = []
	var seen: Array = []
	for template_id in args["template_ids"]:
		if not DTO.bounded_text(template_id,100) or template_id in seen:
			return fail("Invalid template ID.")
		seen.append(template_id)
		var candidate = template(template_id)
		if candidate.is_empty():
			return fail("Template missing/incomplete: "+template_id)
		templates.append(candidate)
	# Godot selects among explicitly approved canonical variants and names;
	# fixed ability/AC/HP/stat blocks are never randomized.
	var selected: Dictionary = templates.pick_random()
	var actor_id = make_id()
	var name = str(args["name"]) if args["name"]!=null else FIRST_NAMES.pick_random()+" "+LAST_NAMES.pick_random()
	var legacy: Dictionary = {}
	if args["existing_actor_id"]==null and args["name"]!=null:
		# Named local NPCs must be reused explicitly rather than generating a
		# second individual with the same contextual identity.
		var named = read(state,[SQL.stmt("SELECT id,payload FROM actors WHERE kind IN ('npc','enemy') AND location_id=? ORDER BY id LIMIT 257",[args["location_id"]])])
		if not named.get("ok",false) or named["sets"][0].size()>256:
			return fail("Local actor identity search incomplete.")
		for row in named["sets"][0]:
			var data = JSON.parse_string(row["payload"])
			if data is Dictionary and str(data.get("name","")).strip_edges().to_lower()==name.strip_edges().to_lower():
				return fail("Named local individual already exists. Reuse or explicitly upgrade its ID.")
	if args["existing_actor_id"]!=null:
		if args["kind"]!="npc" or sets[2].size()!=1 or sets[2][0]["kind"]!="npc" or sets[2][0]["location_id"]!=args["location_id"] or sets[2][0]["catalog_id"]!=null:
			return fail("Only an existing local descriptive NPC may receive a template.")
		var parsed = JSON.parse_string(sets[2][0]["payload"])
		if not parsed is Dictionary or parsed.get("descriptive_only")!=true or not DTO.bounded_text(parsed.get("name"),80) or (args["name"]!=null and args["name"]!=parsed["name"]) or parsed.get("occupation")!=args["occupation"]:
			return fail("Established NPC identity must be preserved.")
		legacy=parsed
		actor_id=args["existing_actor_id"]
		name=legacy["name"]
		var owned = read(state,[SQL.stmt("SELECT 1 FROM actor_instances WHERE actor_id=? UNION ALL SELECT 1 FROM item_instances WHERE actor_id=? UNION ALL SELECT 1 FROM inventory WHERE actor_id=? LIMIT 1",[actor_id,actor_id,actor_id])])
		if not owned.get("ok",false) or not owned["sets"][0].is_empty():
			return fail("Existing actor already has persistent mechanics or possessions.")
	var item_ids: Array = []
	var gear_seen: Array = []
	for item in args["possessions"]:
		if not DTO.exact_keys(item,["definition_id","quantity","equipped_slot","grip"]) or not DTO.bounded_text(item["definition_id"],100) or not DTO.whole(item["quantity"],1,1000) or item["definition_id"] in item_ids or (item["equipped_slot"]!=null and not item["equipped_slot"] in UI.SLOTS) or (item["equipped_slot"]==null and item["grip"]!=null) or (item["equipped_slot"]!=null and (not item["grip"] in UI.GRIPS or item["equipped_slot"] in gear_seen)):
			return fail("Invalid possession or equipped slot.")
		item_ids.append(item["definition_id"])
		if item["equipped_slot"]!=null:
			gear_seen.append(item["equipped_slot"])
	var defs = item_rows(state,item_ids)
	if defs.size()!=item_ids.size():
		return fail("Possession definition unavailable.")
	var size = str(selected["block"].get("size",""))
	var size_scale = {"Tiny":0.5,"Small":1.0,"Medium":1.0,"Large":2.0,"Huge":4.0,"Gargantuan":8.0}
	var capacity: Variant = null
	if size_scale.has(size):
		capacity=15.0*selected["ability_scores"]["str"]*size_scale[size]
	var load = 0.0
	var hands = 0
	var catalogue = ITEMS.new()
	for item in args["possessions"]:
		var def: Dictionary = defs[item["definition_id"]]
		if def.get("unit_weight_lb")==null or capacity==null:
			return fail("Possession capacity/weight unknown.")
		load+=float(def["unit_weight_lb"])*int(item["quantity"])
		if item["equipped_slot"]!=null:
			if str(selected["block"].get("type","")).to_lower()!="humanoid" or not size in ["Small","Medium"]:
				return fail("Equipped gear anatomy/size requires reviewed support.")
			var possible = catalogue.physical_options(def)
			if not possible.any(func(opt): return opt["slot"]==item["equipped_slot"] and opt["grip"]==item["grip"]):
				return fail("Possession not physically compatible with slot.")
			if item["equipped_slot"] in ["main_hand","off_hand","shield"]:
				hands+=2 if item["grip"]=="two_handed" else 1
	if args["coins"]!=null:
		for denom in DENOMINATIONS:
			load+=float(args["coins"][denom])/50.0
	if (capacity==null and load>0) or hands>2 or (capacity!=null and load>capacity):
		return fail("Possessions exceed hands or carrying capacity.")
	# An equipped armour/weapon cannot be used to override the fixed canonical
	# block. C3 must separately validate proficiency, AC/effects and usable gear.
	var block: Dictionary = selected["block"]
	var modifiers: Dictionary = {}
	for key in selected["ability_scores"]:
		modifiers[key]=floori((selected["ability_scores"][key]-10)/2.0)
	var sheet = {"template_id":selected["id"],"template_revision":selected["revision"],"stat_block":block,"ability_scores":selected["ability_scores"],"ability_modifiers":modifiers,"combat":{"hp_current":selected["hp"],"hp_max":selected["hp"],"armor_class":selected["armor_class"],"size":block.get("size"),"conditions":[]},"speed":block.get("speed"),"proficiencies":block.get("proficiencies"),"actions":block.get("actions"),"traits":block.get("special_abilities"),"alignment":block.get("alignment"),"coverage_gaps":selected["coverage_gaps"],"mechanical_combat_supported":false}
	var payload = legacy.duplicate(true)
	payload.merge({"id":actor_id,"name":name,"occupation":args["occupation"],"location_id":args["location_id"],"descriptive_only":false,"public":args["visibility"]=="player","ruleset":CAT.RULESET,"catalog_revision":selected["revision"],"ability_scores":selected["ability_scores"],"ability_modifiers":modifiers,"combat":sheet["combat"],"coins":args["coins"],"carrying_capacity_lb":capacity,"attitude":legacy.get("attitude",args["attitude"]),"alignment":block.get("alignment"),"equipment":{"armor_id":"","shield_id":"","weapon_ids":[]}},true)
	var commands: Array = []
	var template_key = selected["revision"]+":"+selected["id"]
	commands.append(SQL.stmt("INSERT OR IGNORE INTO actor_templates(id,catalog_category,catalog_id,catalog_revision,stat_block) VALUES(?,'monsters',?,?,?)",[template_key,selected["id"],selected["revision"],JSON.stringify(block)]))
	commands.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('c2_template_guard',(SELECT 'ok' FROM actor_templates WHERE id=? AND stat_block=?))",[template_key,JSON.stringify(block)]))
	commands.append(SQL.stmt("DELETE FROM meta WHERE key='c2_template_guard'"))
	# Build equipment and normalized compatibility rows from actual possessions.
	for item in args["possessions"]:
		var def: Dictionary = defs[item["definition_id"]]
		if item["equipped_slot"]=="body":
			payload["equipment"]["armor_id"]=def["id"]
		elif item["equipped_slot"]=="shield":
			payload["equipment"]["shield_id"]=def["id"]
		elif item["equipped_slot"] in ["main_hand","off_hand"]:
			payload["equipment"]["weapon_ids"].append(def["id"])
	if legacy.is_empty():
		commands.append(SQL.stmt("INSERT INTO actors(id,kind,catalog_id,location_id,payload) VALUES(?,?,?,?,?)",[actor_id,args["kind"],selected["id"],args["location_id"],JSON.stringify(payload)]))
	else:
		commands.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('c2_actor_guard',(SELECT 'ok' FROM actors WHERE id=? AND payload=? AND location_id=? AND catalog_id IS NULL))",[actor_id,sets[2][0]["payload"],args["location_id"]]))
		commands.append(SQL.stmt("UPDATE actors SET catalog_id=?,payload=? WHERE id=?",[selected["id"],JSON.stringify(payload),actor_id]))
		commands.append(SQL.stmt("DELETE FROM meta WHERE key='c2_actor_guard'"))
	commands.append(SQL.stmt("INSERT INTO actor_instances(actor_id,template_id,generation_key,source_event_id,visibility,sheet_visibility,sheet) VALUES(?,?,?,?,?,?,?)",[actor_id,template_key,args["generation_key"],args["source_event_id"],args["visibility"],args["sheet_visibility"],JSON.stringify(sheet)]))
	var rid = request["request_id"]
	commands.append(SQL.stmt("INSERT INTO world_links(id,location_id,actor_id,source_event_id) VALUES(?,?,?,"+EVENT+")",[make_id(),args["location_id"],actor_id,rid]))
	for item in args["possessions"]:
		var def: Dictionary = defs[item["definition_id"]]
		var statement = catalogue.insert_definition(def)
		statement["sql"]=statement["sql"].replace("INSERT INTO","INSERT OR IGNORE INTO")
		commands.append(statement)
		var instance = make_id()
		commands.append(SQL.stmt("INSERT INTO item_instances(id,definition_id,actor_id,quantity,condition,attunement,provenance,source_event_id) VALUES(?,?,?,?,'unknown','unknown',?,"+EVENT+")",[instance,def["id"],actor_id,int(item["quantity"]),JSON.stringify({"kind":"generated_possession","actor_id":actor_id,"template_id":selected["id"]}),rid]))
		commands.append(SQL.stmt("INSERT INTO inventory(actor_id,item_id,quantity,payload) VALUES(?,?,?,?)",[actor_id,def["id"],int(item["quantity"]),JSON.stringify({"item_id":def["id"],"quantity":int(item["quantity"]),"equipped":item["equipped_slot"]!=null})]))
		if item["equipped_slot"]!=null:
			commands.append(SQL.stmt("INSERT INTO equipment_assignments(actor_id,slot,instance_id,grip) VALUES(?,?,?,?)",[actor_id,item["equipped_slot"],instance,item["grip"]]))
			if item["grip"]=="two_handed":
				commands.append(SQL.stmt("INSERT INTO equipment_assignments(actor_id,slot,instance_id,grip) VALUES(?,'off_hand',?,'two_handed')",[actor_id,instance]))
	return _commit(ctx,commands,{"actor_id":actor_id,"template_id":selected["id"],"coverage_gaps":selected["coverage_gaps"]},name+" — "+args["occupation"]+".",args["visibility"])
