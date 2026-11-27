extends "res://persistence/loot_store.gd"
## C3 standalone noncombat mutations. All effects/rolls created locally;
## C2 _commit is the only writer, with durable request/result + revision.
const CAT = preload("res://rules/catalog.gd")
const RAW = preload("res://turns/raw_mechanics.gd")
const PROJECTION = preload("res://persistence/interaction_projection.gd")
const PROTECTION = ["ring-of-protection","cloak-of-protection"]
const HEALING = {"potion-of-healing-common":[2,4,2],"potion-of-healing-greater":[4,4,4],"potion-of-healing-superior":[8,4,8],"potion-of-healing-supreme":[10,4,20]}
const ARMOR_SECONDS = {"Light":[60,60],"Medium":[300,60],"Heavy":[600,300],"Shield":[6,6]}
const MAX_ITEMS = 512
var prepared: Dictionary = {}
var catalogue = ITEMS.new()

func safe_actor(state: Dictionary) -> bool:
	var a = state["actor"]
	return RAW.actor_ready(a) and a["combat"]["conditions"].is_empty() and a["combat"]["exhaustion"]==0 and a.get("level")==1 and a.get("review_required",[]).is_empty()

func quiet_context(state: Dictionary) -> bool:
	var q = read(state,[SQL.stmt("SELECT count(*) AS n FROM encounters WHERE status NOT IN ('resolved','completed','closed','defeated')")])
	return q.get("ok",false) and DTO.sql_int(q["sets"][0][0]["n"])==0

func allowed(ctx: Dictionary, clearance: Dictionary, scope: String) -> bool:
	return local_clearance(ctx["request"],clearance,scope) and safe_actor(ctx["state"]) and quiet_context(ctx["state"])

func read_owned(state: Dictionary, owner: String) -> Dictionary:
	var q = read(state,[
		SQL.stmt(PROJECTION.INSTANCE_SELECT+" WHERE i.actor_id=? ORDER BY i.id LIMIT ?",[owner,MAX_ITEMS+1]),
		SQL.stmt("SELECT slot,instance_id,grip FROM equipment_assignments WHERE actor_id=? ORDER BY slot",[owner]),
		SQL.stmt("SELECT instance_id FROM equipment_review WHERE actor_id=?",[owner]),
		SQL.stmt("SELECT item_id,quantity,payload FROM inventory WHERE actor_id=? ORDER BY item_id",[owner]),
		SQL.stmt("SELECT id,location_id,payload,kind FROM actors WHERE id=?",[owner])
	])
	if not q.get("ok",false):
		return q
	var sets: Array = q["sets"]
	if sets[0].size()>MAX_ITEMS or not sets[2].is_empty() or sets[4].size()!=1:
		return fail("Incomplete ownership or unresolved legacy equipment; review required.")
	var actor = JSON.parse_string(sets[4][0]["payload"])
	if not actor is Dictionary or actor.get("id")!=owner or sets[4][0]["location_id"]!=state["location_id"]:
		return fail("Actor identity or local access unavailable.")
	var items: Dictionary = {}
	var definitions: Dictionary = {}
	for row in sets[0]:
		var qty = DTO.sql_int(row["quantity"])
		var def = {"id":row["definition_id"],"origin":row["origin"],"catalog_id":row["catalog_id"],"catalog_category":row["catalog_category"],"catalog_revision":row["catalog_revision"],"attributes":JSON.parse_string(row["attributes"]),"unit_weight_lb":DTO.sql_number(row["unit_weight_lb"])}
		if not DTO.id_valid(row["id"]) or qty==null or qty<1 or not def["attributes"] is Dictionary:
			return fail("Invalid owned instance.")
		var item: Dictionary = row.duplicate(true)
		item["quantity"]=qty
		items[row["id"]]=item
		definitions[row["id"]]=def
	var assignments: Dictionary = {}
	for row in sets[1]:
		if not row["slot"] in UI.SLOTS or not row["grip"] in UI.GRIPS or assignments.has(row["slot"]) or not items.has(row["instance_id"]):
			return fail("Equipment assignment inconsistent.")
		assignments[row["slot"]]={"instance_id":row["instance_id"],"grip":row["grip"]}
	var mirror: Dictionary = {}
	for row in sets[3]:
		var qty = DTO.sql_int(row["quantity"])
		var payload = JSON.parse_string(row["payload"])
		if qty==null or qty<1 or not payload is Dictionary:
			return fail("Inventory mirror invalid.")
		payload["item_id"]=row["item_id"]
		payload["quantity"]=qty
		mirror[row["item_id"]]=payload
	var pack = {"ok":true,"owner":owner,"actor":actor,"raw_actor":sets[4][0]["payload"],"items":items,"definitions":definitions,"slots":assignments,"mirror":mirror,"raw_rows":sets[0],"raw_slots":sets[1],"raw_inventory":sets[3]}
	if not mirror_matches(pack):
		return fail("Ownership and normalized inventory mirror disagree.")
	return pack

func aggregate(pack: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for iid in pack["items"]:
		var row = pack["items"][iid]
		var key = row["definition_id"]
		if not result.has(key):
			result[key]={"item_id":key,"quantity":0,"equipped":false}
		result[key]["quantity"]+=int(row["quantity"])
		for slot in pack["slots"]:
			if pack["slots"][slot]["instance_id"]==iid:
				result[key]["equipped"]=true
	return result

func mirror_matches(pack: Dictionary) -> bool:
	var a = aggregate(pack)
	if a.size()!=pack["mirror"].size():
		return false
	for key in a:
		if not DTO.whole(a[key]["quantity"],1) or not pack["mirror"].has(key) or a[key]["quantity"]!=pack["mirror"][key]["quantity"] or a[key]["equipped"]!=pack["mirror"][key].get("equipped",false):
			return false
	return true

func owned_guards(pack: Dictionary) -> Array:
	var owner = pack["owner"]
	var batch: Array = [
		SQL.stmt("INSERT INTO meta(key,value) VALUES('c3_owned_guard',(SELECT 'ok' FROM actors WHERE id=? AND payload=? AND (SELECT count(*) FROM item_instances WHERE actor_id=?)=CAST(? AS INTEGER) AND (SELECT count(*) FROM equipment_assignments WHERE actor_id=?)=CAST(? AS INTEGER) AND (SELECT count(*) FROM inventory WHERE actor_id=?)=CAST(? AS INTEGER) AND NOT EXISTS(SELECT 1 FROM equipment_review WHERE actor_id=?)))",[owner,pack["raw_actor"],owner,pack["raw_rows"].size(),owner,pack["raw_slots"].size(),owner,pack["raw_inventory"].size(),owner]),
		SQL.stmt("DELETE FROM meta WHERE key='c3_owned_guard'")
	]
	for row in pack["raw_rows"]:
		batch.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('c3_owned_guard',(SELECT 'ok' FROM item_instances i JOIN item_definitions d ON d.id=i.definition_id WHERE i.id=? AND i.actor_id=? AND i.definition_id=? AND i.quantity=CAST(? AS INTEGER) AND i.charges IS ? AND i.condition=? AND i.attunement=? AND d.attributes=? AND d.unit_weight_lb IS ?))",[row["id"],owner,row["definition_id"],row["quantity"],row["charges"],row["condition"],row["attunement"],row["attributes"],row["unit_weight_lb"]]))
		batch.append(SQL.stmt("DELETE FROM meta WHERE key='c3_owned_guard'"))
	for row in pack["raw_slots"]:
		batch.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('c3_owned_guard',(SELECT 'ok' FROM equipment_assignments WHERE actor_id=? AND slot=? AND instance_id=? AND grip=?))",[owner,row["slot"],row["instance_id"],row["grip"]]))
		batch.append(SQL.stmt("DELETE FROM meta WHERE key='c3_owned_guard'"))
	for row in pack["raw_inventory"]:
		batch.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('c3_owned_guard',(SELECT 'ok' FROM inventory WHERE actor_id=? AND item_id=? AND quantity=CAST(? AS INTEGER) AND payload=?))",[owner,row["item_id"],row["quantity"],row["payload"]]))
		batch.append(SQL.stmt("DELETE FROM meta WHERE key='c3_owned_guard'"))
	return batch

func weight(pack: Dictionary, actor: Dictionary) -> Variant:
	if not coin_map(actor.get("coins")):
		return null
	var load = 0.0
	for iid in pack["items"]:
		var w = pack["definitions"][iid]["unit_weight_lb"]
		if not DTO.number(w,0,1000000):
			return null
		load+=float(w)*int(pack["items"][iid]["quantity"])
	for denom in DENOMS:
		load+=float(actor["coins"][denom])/50.0
	return load

func mirror_commands(pack: Dictionary, actor: Dictionary) -> Array:
	var rows = aggregate(pack)
	var commands: Array = []
	for key in pack["mirror"]:
		if not rows.has(key):
			commands.append(SQL.stmt("DELETE FROM inventory WHERE actor_id=? AND item_id=?",[pack["owner"],key]))
	var updated: Array = []
	for key in rows:
		var row = pack["mirror"].get(key,{}).duplicate(true)
		row.merge(rows[key],true)
		updated.append(row)
		commands.append(SQL.stmt("INSERT INTO inventory(actor_id,item_id,quantity,payload) VALUES(?,?,?,?) ON CONFLICT(actor_id,item_id) DO UPDATE SET quantity=excluded.quantity,payload=excluded.payload",[pack["owner"],key,row["quantity"],JSON.stringify(row)]))
	actor["inventory"]=updated
	actor["carried_weight_lb"]=weight(pack,actor)
	commands.append(SQL.stmt("UPDATE actors SET payload=? WHERE id=?",[JSON.stringify(actor),pack["owner"]]))
	return commands

func official(def: Dictionary) -> bool:
	return def.get("origin")=="official" and def.get("catalog_revision")==CAT.REVISION and catalogue.official(def.get("catalog_category",""),def.get("catalog_id",""))==def.get("attributes")

func slotted(pack: Dictionary,slot: String) -> String:
	return str(pack["slots"].get(slot,{}).get("instance_id",""))

func assigned(pack: Dictionary,iid: String) -> bool:
	for slot in pack["slots"]:
		if slotted(pack,slot)==iid:
			return true
	return false

func clear_instance(pack: Dictionary,iid: String) -> void:
	for slot in pack["slots"].keys():
		if slotted(pack,slot)==iid:
			pack["slots"].erase(slot)

func protection(pack: Dictionary) -> Variant:
	var value = 0
	for iid in pack["items"]:
		var row = pack["items"][iid]
		if row["attunement"]=="attuned":
			var def = pack["definitions"][iid]
			if not official(def) or not def["catalog_id"] in PROTECTION or row["quantity"]!=1:
				return null
			if assigned(pack,iid):
				value+=1
		elif assigned(pack,iid) and pack["definitions"][iid].get("catalog_id") in PROTECTION and row["attunement"]=="unknown":
			return null
	return value if value<=2 else null

# Only validated level-one PC equipment formulas. No combat is executed.
func gear_stats(pack: Dictionary,actor: Dictionary) -> Dictionary:
	var mods = actor.get("ability_modifiers")
	var profs = actor.get("proficiency_ids")
	var features = actor.get("class_feature_ids",[])
	if not mods is Dictionary or not profs is Array or not features is Array:
		return {}
	for ability in RAW.ABILITIES:
		if not DTO.whole(mods.get(ability),-5,10):
			return {}
	var armor_id = ""
	var shield_id = ""
	var weapons: Array = []
	var armor: Dictionary = {}
	var dex = int(mods["dex"])
	var role = actor.get("class_id","")
	var ac = 10+dex
	var shield = slotted(pack,"shield")
	var body = slotted(pack,"body")
	var bonus = protection(pack)
	if bonus==null:
		return {}
	for slot in pack["slots"]:
		var iid = slotted(pack,slot)
		var def = pack["definitions"][iid]
		if not official(def):
			# Novel objects may be held descriptively, but no custom equipment
			# may silently grant armor, damage or other mechanical effects.
			if def.get("origin")!="custom" or not slot in ["main_hand","off_hand"] or not catalogue.custom_valid(def["attributes"]) or def["attributes"].get("category") not in ["weapon","tool","gear","object"]:
				return {}
		var grip = pack["slots"][slot]["grip"]
		if slot=="off_hand" and grip=="two_handed" and slotted(pack,"main_hand")==iid:
			continue
		if not catalogue.physical_options(def).any(func(opt): return opt["slot"]==slot and opt["grip"]==grip):
			return {}
		if pack["items"][iid]["condition"] in ["damaged","broken"]:
			return {}
	if not body.is_empty():
		var def = pack["definitions"][body]
		armor=def["attributes"]
		armor_id=def["id"]
		var spec = armor.get("armor_class")
		if not spec is Dictionary or not DTO.whole(spec.get("base"),10,20) or not armor.get("armor_category") in ["Light","Medium","Heavy"] or not spec.get("dex_bonus") is bool:
			return {}
		ac=int(spec["base"])
		if spec["dex_bonus"]:
			ac+=mini(dex,int(spec.get("max_bonus",99)))
	else:
		if role=="barbarian":
			ac+=int(mods["con"])
		elif role=="monk" and shield.is_empty():
			ac+=int(mods["wis"])
		elif actor.get("subclass_id")=="draconic":
			ac=13+dex
	if not shield.is_empty():
		shield_id=pack["definitions"][shield]["id"]
		ac+=2
	if not armor_id.is_empty() and "fighter-fighting-style-defense" in features:
		ac+=1
	ac+=int(bonus)
	for hand in ["main_hand","off_hand"]:
		var iid = slotted(pack,hand)
		if not iid.is_empty() and pack["definitions"][iid]["attributes"].has("weapon_category") and not pack["definitions"][iid]["id"] in weapons:
			weapons.append(pack["definitions"][iid]["id"])
	var armor_proficient = armor_id.is_empty() or str(armor.get("armor_category","")).to_lower()+"-armor" in profs
	var shield_proficient = shield_id.is_empty() or "shields" in profs
	var race = catalogue.official("races",str(actor.get("race_id","")))
	var subrace = catalogue.official("subraces",str(actor.get("subrace_id",""))) if not str(actor.get("subrace_id","")).is_empty() else {}
	var speed = subrace.get("speed",race.get("speed"))
	if not DTO.whole(speed,1,60) or not DTO.whole(actor.get("ability_scores",{}).get("str"),1,30):
		return {}
	if not armor_id.is_empty() and actor.get("race_id")!="dwarf" and int(armor.get("str_minimum",0))>int(actor["ability_scores"]["str"]):
		speed=maxi(0,int(speed)-10)
	var saves: Dictionary = {}
	for ability in RAW.ABILITIES:
		saves[ability]=int(mods[ability])+(int(actor["proficiency_bonus"]) if "saving-throw-"+ability in profs else 0)+int(bonus)
	return {"equipment":{"armor_id":armor_id,"shield_id":shield_id,"weapon_ids":weapons,"armor_proficient":armor_proficient,"shield_proficient":shield_proficient,"armor_penalty":not armor_proficient or not shield_proficient,"protection_bonus":bonus},"armor_class":ac,"speed_feet":speed,"saving_throws":saves}

func same_gear(stats: Dictionary,actor: Dictionary) -> bool:
	if stats.is_empty() or stats["armor_class"]!=actor["combat"].get("armor_class") or stats["speed_feet"]!=actor["combat"].get("speed_feet") or stats["saving_throws"]!=actor.get("saving_throws"):
		return false
	var current = actor.get("equipment",{})
	for key in ["armor_id","shield_id","armor_penalty"]:
		if stats["equipment"][key]!=current.get(key):
			return false
	var a: Array = stats["equipment"]["weapon_ids"].duplicate()
	var b: Array = current.get("weapon_ids",[]).duplicate()
	a.sort()
	b.sort()
	return a==b

func apply_gear(actor: Dictionary,stats: Dictionary) -> void:
	actor["equipment"]=stats["equipment"]
	actor["combat"]["armor_class"]=stats["armor_class"]
	actor["combat"]["speed_feet"]=stats["speed_feet"]
	actor["saving_throws"]=stats["saving_throws"]

func wear_duration(pack: Dictionary,iid: String,donning: bool) -> int:
	var category = pack["definitions"][iid]["attributes"].get("armor_category","")
	return int(ARMOR_SECONDS[category][0 if donning else 1]) if ARMOR_SECONDS.has(category) else 6

# Structured equip/swap/unequip and attunement. C1's slot names are presentation
# slots; we reject unsupported extra ring/accessory layouts rather than infer.
func equipment_action(id: String,req: Dictionary,clearance: Dictionary) -> Dictionary:
	var kind = str(req.get("kind",""))
	var fields = {"equip":["instance_id","slot","grip"],"swap":["instance_id","slot","grip","replace_instance_ids"],"unequip":["instance_id","slot"],"attune":["instance_id"],"unattune":["instance_id"]}
	if not fields.has(kind):
		return fail("Unknown equipment action.")
	var ctx = begin(id,req,kind,fields[kind])
	if not ctx.get("ok",false) or ctx.get("replayed",false):
		return ctx
	if not allowed(ctx,clearance,"equipment"):
		return fail("Verified quiet equipment context and complete actor required.")
	var state = ctx["state"]
	var args = req["args"]
	var pack = read_owned(state,state["actor_id"])
	if not pack.get("ok",false):
		return pack
	var iid = args["instance_id"]
	if not DTO.id_valid(iid) or not pack["items"].has(iid):
		return fail("Owned instance unavailable.")
	var actor: Dictionary = pack["actor"].duplicate(true)
	if not same_gear(gear_stats(pack,actor),actor):
		return fail("Existing derived equipment stats require review before a change.")
	var commands = owned_guards(pack)
	var def = pack["definitions"][iid]
	var row = pack["items"][iid]
	var seconds = 0
	if kind in ["attune","unattune"]:
		if not official(def) or not def["catalog_id"] in PROTECTION or row["quantity"]!=1 or row["condition"] in ["damaged","broken"]:
			return fail("Only verified Ring/Cloak of Protection attunement is currently supported.")
		var n = 0
		for item in pack["items"].values():
			if item["attunement"]=="attuned":
				n+=1
		if kind=="attune" and (row["attunement"]!="unattuned" or n>=3):
			return fail("Attunement eligibility or three-item limit not established.")
		if kind=="unattune" and row["attunement"]!="attuned":
			return fail("Item is not attuned.")
		row["attunement"]="attuned" if kind=="attune" else "unattuned"
		seconds=3600
		commands.append(SQL.stmt("UPDATE item_instances SET attunement=? WHERE id=? AND actor_id=?",[row["attunement"],iid,state["actor_id"]]))
	elif kind=="unequip":
		if not args["slot"] in UI.SLOTS or slotted(pack,args["slot"])!=iid:
			return fail("Selected slot does not contain that item.")
		seconds=wear_duration(pack,iid,false)
		clear_instance(pack,iid)
	else:
		if not args["slot"] in UI.SLOTS or not args["grip"] in UI.GRIPS or row["condition"] in ["damaged","broken"] or row["quantity"]<1 or not catalogue.physical_options(def).any(func(opt): return opt["slot"]==args["slot"] and opt["grip"]==args["grip"]):
			return fail("Item cannot occupy requested slot/grip.")
		var relevant = [args["slot"]]
		if args["grip"]=="two_handed":
			relevant=["main_hand","off_hand","shield"]
		elif args["slot"]=="off_hand":
			relevant.append("shield")
		elif args["slot"]=="shield":
			relevant.append("off_hand")
		var displaced: Array = []
		for slot in relevant:
			var other = slotted(pack,slot)
			if not other.is_empty() and other!=iid and not other in displaced:
				displaced.append(other)
		displaced.sort()
		var requested: Array = []
		if kind=="swap":
			if not args["replace_instance_ids"] is Array:
				return fail("Explicit displaced item choices required.")
			requested=args["replace_instance_ids"].duplicate()
			requested.sort()
		if displaced!=requested:
			return fail("Slot conflict changed; choose an exact atomic swap.")
		for other in displaced:
			seconds+=wear_duration(pack,other,false)
			clear_instance(pack,other)
		if assigned(pack,iid):
			seconds+=wear_duration(pack,iid,false)
			clear_instance(pack,iid)
		pack["slots"][args["slot"]]={"instance_id":iid,"grip":args["grip"]}
		if args["grip"]=="two_handed":
			pack["slots"]["off_hand"]={"instance_id":iid,"grip":"two_handed"}
		seconds+=wear_duration(pack,iid,true)
	var stats = gear_stats(pack,actor)
	if stats.is_empty():
		return fail("Equipment combination requires unsupported mechanical effects.")
	apply_gear(actor,stats)
	commands.append(SQL.stmt("DELETE FROM equipment_assignments WHERE actor_id=?",[state["actor_id"]]))
	for slot in pack["slots"]:
		commands.append(SQL.stmt("INSERT INTO equipment_assignments(actor_id,slot,instance_id,grip) VALUES(?,?,?,?)",[state["actor_id"],slot,slotted(pack,slot),pack["slots"][slot]["grip"]]))
	commands.append_array(mirror_commands(pack,actor))
	action_seconds=seconds
	return _commit(ctx,commands,{"kind":kind,"instance_id":iid,"slot_assignments":pack["slots"],"equipment":stats["equipment"],"armor_class":stats["armor_class"],"speed_feet":stats["speed_feet"],"saving_throws":stats["saving_throws"],"rule_refs":["wearing-and-wielding-items","attunement" if kind in ["attune","unattune"] else "movement"]},"Equipment updated.")

# Receipts for healing dice (never supplied by caller) persisted with outcome.
func healing_dice(count: int,sides: int,modifier: int) -> Dictionary:
	var rolls: Array = []
	var total = modifier
	for i in range(count):
		var value = randi_range(1,sides)
		rolls.append(value)
		total+=value
	return {"roll_id":make_id(),"kind":"healing","sides":sides,"values":rolls,"modifier":modifier,"total":total}

func heal(actor: Dictionary,dice: Dictionary) -> int:
	var combat = actor["combat"]
	var actual = mini(int(combat["hp_max"])-int(combat["hp_current"]),maxi(0,int(dice["total"])))
	combat["hp_current"]=int(combat["hp_current"])+actual
	return actual

# Keep an unresolved prepared mutation in this service instance. Do not expose
# rolls until durable readback. Retrying the same ID uses the same batch.
func _commit(context: Dictionary,commands: Array,result_data: Dictionary,message: String,visibility: String = "player") -> Dictionary:
	var rid = context["request"]["request_id"]
	var cid = context["state"]["campaign_id"]
	if prepared.has(cid):
		var held = prepared[cid]
		if held["context"]["request"]!=context["request"]:
			return fail("Unconfirmed local mechanical request must be reconciled.")
		return retry_prepared(cid,rid)
	prepared[cid]={"context":context.duplicate(true),"commands":commands.duplicate(true),"result":result_data.duplicate(true),"message":message,"visibility":visibility,"seconds":action_seconds}
	return retry_prepared(cid,rid)

func retry_prepared(id: String,rid: String) -> Dictionary:
	if not prepared.has(id) or prepared[id]["context"]["request"]["request_id"]!=rid:
		return fail("No prepared request in this local instance.")
	var entry = prepared[id]
	var prior = settlement(id,rid)
	if not prior.get("ok",false):
		return prior
	if prior.get("found",false):
		if prior["request"]!=entry["context"]["request"] or prior["status"]!="committed":
			return fail("Prepared request conflicts with durable settlement.")
		prepared.erase(id)
		return {"ok":true,"replayed":true,"result":prior["result"],"revision":prior["revision"]}
	action_seconds=entry["seconds"]
	var saved = super._commit(entry["context"],entry["commands"],entry["result"],entry["message"],entry["visibility"])
	if saved.get("ok",false):
		prepared.erase(id)
	action_seconds=0
	return saved

func abandon_prepared(id: String,rid: String) -> Dictionary:
	if not prepared.has(id) or prepared[id]["context"]["request"]["request_id"]!=rid:
		return fail("No matching local prepared request.")
	var prior=settlement(id,rid)
	if not prior.get("ok",false) or prior.get("found",false):
		return fail("Cannot abandon a committed or unconfirmed settlement.")
	prepared.erase(id)
	return {"ok":true,"abandoned_request_id":rid}

func consume(id: String,req: Dictionary,clearance: Dictionary) -> Dictionary:
	var ctx = begin(id,req,"item_use",["instance_id","quantity","target_id"])
	if not ctx.get("ok",false) or ctx.get("replayed",false):
		return ctx
	if not allowed(ctx,clearance,"item_use"):
		return fail("Verified quiet consumable context required.")
	var state=ctx["state"]
	var args=req["args"]
	if args["target_id"]!=state["actor_id"] or not DTO.whole(args["quantity"],1,1) or not DTO.id_valid(args["instance_id"]):
		return fail("Choose the explicit self target and one consumable.")
	var pack=read_owned(state,state["actor_id"])
	if not pack.get("ok",false):
		return pack
	var iid=args["instance_id"]
	if not pack["items"].has(iid) or assigned(pack,iid):
		return fail("Consumable unavailable or equipped.")
	var item=pack["items"][iid]
	var def=pack["definitions"][iid]
	if not official(def) or not HEALING.has(def.get("catalog_id")) or item["condition"] in ["damaged","broken"] or item["charges"]!=null or item["attunement"]=="attuned":
		return fail("Unsupported item effect or ambiguous potion potency.")
	var commands=owned_guards(pack)
	if item["quantity"]==1:
		pack["items"].erase(iid)
		pack["definitions"].erase(iid)
		commands.append(SQL.stmt("DELETE FROM item_instances WHERE id=? AND actor_id=?",[iid,state["actor_id"]]))
	else:
		item["quantity"]-=1
		commands.append(SQL.stmt("UPDATE item_instances SET quantity=quantity-1 WHERE id=?",[iid]))
	var actor=pack["actor"].duplicate(true)
	var dice_spec=HEALING[def["catalog_id"]]
	var dice=healing_dice(dice_spec[0],dice_spec[1],dice_spec[2])
	var restored=heal(actor,dice)
	commands.append_array(mirror_commands(pack,actor))
	action_seconds=6
	return _commit(ctx,commands,{"kind":"item_use","instance_id":iid,"definition_id":def["id"],"consumed":1,"rolls":[dice],"hp_restored":restored,"hp_current":actor["combat"]["hp_current"],"rule_refs":[RAW.rule_ref("damage-and-healing"),RAW.rule_ref("activating-an-item"),{"category":"magic-items","id":def["catalog_id"],"ruleset":CAT.RULESET,"revision":CAT.REVISION}]},"Healing potion consumed; restored "+str(restored)+" HP.")
