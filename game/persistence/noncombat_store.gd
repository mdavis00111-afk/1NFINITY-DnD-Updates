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
	if not mods is Dictionary or not profs is Array or not features is Array or not DTO.whole(actor.get("proficiency_bonus"),2,2):
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
		if grip=="two_handed" and (slotted(pack,"off_hand")!=iid or not slotted(pack,"shield").is_empty()):
			return {}
	if not slotted(pack,"shield").is_empty() and not slotted(pack,"off_hand").is_empty():
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
	if kind in ["attune","unattune"] and not restore_short(actor):
		return fail("Short-rest resource state requires review.")
	# Rebuild the actor mirror after any short-rest reset as part of this batch.
	if kind in ["attune","unattune"]:
		commands.append(SQL.stmt("UPDATE actors SET payload=? WHERE id=?",[JSON.stringify(actor),state["actor_id"]]))
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

# Known first-level resource reset rules only. Unknown features fail closed.
const SHORT_RESETS = ["second_wind","breath_weapon"]
const LONG_RESETS = ["rage","bardic_inspiration","lay_on_hands","divine_sense","arcane_recovery","relentless_endurance"]

func resource_map_valid(actor: Dictionary) -> bool:
	var resources = actor.get("resources")
	if not resources is Dictionary:
		return false
	for key in resources:
		var entry = resources[key]
		if not key in SHORT_RESETS+LONG_RESETS or not entry is Dictionary or not DTO.whole(entry.get("max")) or not DTO.whole(entry.get("spent"),0,int(entry["max"])):
			return false
	return true

func slots_valid(actor: Dictionary) -> bool:
	var sp = actor.get("spellcasting")
	if not sp is Dictionary or not sp.get("slots") is Dictionary or not sp.get("pact_magic") is bool:
		return false
	for key in sp["slots"]:
		var slot = sp["slots"][key]
		if not key is String or not key.is_valid_int() or not DTO.whole(int(key),1,9) or not slot is Dictionary or not DTO.whole(slot.get("maximum"),0,4) or not DTO.whole(slot.get("spent"),0,int(slot["maximum"])):
			return false
	return true

func restore_short(actor: Dictionary) -> bool:
	if not resource_map_valid(actor) or not slots_valid(actor):
		return false
	for key in SHORT_RESETS:
		if actor["resources"].has(key):
			actor["resources"][key]["spent"]=0
	if actor["spellcasting"]["pact_magic"]:
		for slot in actor["spellcasting"]["slots"].values():
			slot["spent"]=0
	return true

func spell_preparation(actor: Dictionary, ids: Variant) -> Dictionary:
	if not ids is Array or ids.is_empty() or ids.size()>32 or not slots_valid(actor):
		return fail("Provide the complete prepared spell list.")
	var role = str(actor.get("class_id",""))
	if not role in ["cleric","druid","wizard"]:
		return fail("Prepared spell list not supported for this class/level.")
	var sp=actor["spellcasting"]
	var ability = "int" if role=="wizard" else "wis"
	var mod=actor.get("ability_modifiers",{}).get(ability)
	if not DTO.whole(mod,-5,10) or not sp.get("known_ids") is Array or not sp.get("always_prepared_ids") is Array:
		return fail("Spell preparation ability or lists unavailable.")
	var limit=maxi(1,int(actor["level"])+int(mod))
	if ids.size()>limit:
		return fail("Prepared spell limit exceeded.")
	var seen: Array = []
	var minutes=0
	for spell_id in ids:
		if not DTO.bounded_text(spell_id,100) or spell_id in seen or spell_id in sp["always_prepared_ids"]:
			return fail("Duplicate, invalid, or always-prepared spell.")
		var spell=catalogue.official("spells",spell_id)
		if spell.is_empty() or not DTO.whole(spell.get("level"),1,9) or not role in catalogue.cat.references(spell.get("classes",[])) or int(sp["slots"].get(str(int(spell["level"])),{}).get("maximum",0))<1 or (role=="wizard" and not spell_id in sp["known_ids"]):
			return fail("Spell is not eligible for the class, available slot level or wizard spellbook.")
		seen.append(spell_id)
		minutes+=int(spell["level"])
	return {"ok":true,"prepared_ids":seen,"limit":limit,"seconds":minutes*60}

func casting_hand_free(pack: Dictionary) -> bool:
	var main=slotted(pack,"main_hand")
	var off=slotted(pack,"off_hand")
	var shield=slotted(pack,"shield")
	# A two-handed weapon only needs two hands to attack. Here require an
	# explicitly released/free hand rather than infer that the actor released it.
	return main.is_empty() or (off.is_empty() and shield.is_empty())

func spell_cast(id: String,req: Dictionary,clearance: Dictionary) -> Dictionary:
	var ctx=begin(id,req,"spell_cast",["spell_id","source","slot_level","target_id"])
	if not ctx.get("ok",false) or ctx.get("replayed",false):
		return ctx
	if not allowed(ctx,clearance,"spell_cast"):
		return fail("Verified quiet casting context, components and target required.")
	var state=ctx["state"]
	var args=req["args"]
	if args["target_id"]!=state["actor_id"] or not args["spell_id"] in ["cure-wounds","healing-word"] or not DTO.whole(args["slot_level"],1,1):
		return fail("Supported casting slice: explicit self-target Cure Wounds or Healing Word using a first-level slot.")
	var pack=read_owned(state,state["actor_id"])
	if not pack.get("ok",false):
		return pack
	var actor=pack["actor"].duplicate(true)
	if not slots_valid(actor) or actor.get("equipment",{}).get("armor_penalty")!=false:
		return fail("Casting slots or armor proficiency unavailable.")
	var sp=actor["spellcasting"]
	if sp.get("concentration")!=null:
		return fail("Existing concentration requires effect handling.")
	var spell=catalogue.official("spells",args["spell_id"])
	var role=str(actor.get("class_id",""))
	var source_keys={"known":"known_ids","prepared":"prepared_ids","always_prepared":"always_prepared_ids"}
	if spell.is_empty() or spell.get("level")!=1 or not source_keys.has(args["source"]) or not sp.get(source_keys[args["source"]]) is Array or not args["spell_id"] in sp[source_keys[args["source"]]]:
		return fail("Spell source is not actually available.")
	if role in ["cleric","druid","wizard"] and args["source"]=="known":
		return fail("A spellbook or class list entry is not a prepared spell.")
	if not role in ["bard","cleric","druid","sorcerer","warlock","wizard"] or (not role in catalogue.cat.references(spell.get("classes",[])) and not args["source"]=="always_prepared"):
		return fail("Class/subclass spell access not verified.")
	if args["source"]=="always_prepared" and not (actor.get("subclass_id")=="life" and args["spell_id"]=="cure-wounds"):
		return fail("Always-prepared source requires verified subclass rule.")
	if "S" in spell.get("components",[]) and not casting_hand_free(pack):
		return fail("Somatic component needs an explicitly free hand.")
	if "M" in spell.get("components",[]):
		return fail("Material component handler not available.")
	var ability=sp.get("ability")
	var expected={"bard":"cha","cleric":"wis","druid":"wis","sorcerer":"cha","warlock":"cha","wizard":"int"}
	var modifier=actor.get("ability_modifiers",{}).get(ability)
	if ability!=expected[role] or not DTO.whole(modifier,-5,10) or sp.get("attack_bonus")!=2+int(modifier) or sp.get("save_dc")!=10+int(modifier):
		return fail("Spellcasting ability and saved modifiers disagree.")
	var slot=sp["slots"].get("1",{})
	if not DTO.whole(slot.get("maximum"),1,2) or not DTO.whole(slot.get("spent"),0,int(slot["maximum"])-1):
		return fail("No eligible spell slot remaining.")
	var sides=8 if args["spell_id"]=="cure-wounds" else 4
	var bonus=int(modifier)
	if actor.get("subclass_id")=="life":
		bonus+=3 # Disciple of Life, 2 + spell level
	var dice=healing_dice(1,sides,bonus)
	var restored=heal(actor,dice)
	slot["spent"]=int(slot["spent"])+1
	var commands=owned_guards(pack)
	commands.append(SQL.stmt("UPDATE actors SET payload=? WHERE id=?",[JSON.stringify(actor),state["actor_id"]]))
	action_seconds=6
	return _commit(ctx,commands,{"kind":"spell_cast","spell_id":args["spell_id"],"source":args["source"],"slot_level":1,"slot_spent":slot["spent"],"rolls":[dice],"hp_restored":restored,"hp_current":actor["combat"]["hp_current"],"rule_refs":[RAW.rule_ref("casting-a-spell"),RAW.rule_ref("damage-and-healing"),{"category":"spells","id":args["spell_id"],"ruleset":CAT.RULESET,"revision":CAT.REVISION}]},"Spell cast; restored "+str(restored)+" HP.")

func use_resource(id: String,req: Dictionary,clearance: Dictionary) -> Dictionary:
	var ctx=begin(id,req,"resource_use",["resource_id","quantity","target_id"])
	if not ctx.get("ok",false) or ctx.get("replayed",false):
		return ctx
	if not allowed(ctx,clearance,"resource_use"):
		return fail("Verified noncombat feature use required.")
	var state=ctx["state"]
	var args=req["args"]
	var actor=state["actor"].duplicate(true)
	if args["target_id"]!=state["actor_id"] or not DTO.whole(args["quantity"],1,5) or not resource_map_valid(actor):
		return fail("Explicit self target, valid resource amount and resource state required.")
	var rid=args["resource_id"]
	if not rid in ["second_wind","lay_on_hands"] or not actor["resources"].has(rid):
		return fail("Resource effect not implemented.")
	var entry=actor["resources"][rid]
	var amount=int(args["quantity"])
	if int(entry["spent"])+amount>int(entry["max"]):
		return fail("Resource already spent or quantity unavailable.")
	var rolls: Array=[]
	var actual=0
	if rid=="second_wind":
		if actor.get("class_id")!="fighter" or entry["max"]!=1 or amount!=1:
			return fail("Second Wind eligibility not verified.")
		var die=healing_dice(1,10,int(actor["level"]))
		rolls.append(die)
		actual=heal(actor,die)
	else:
		if actor.get("class_id")!="paladin" or entry["max"]!=5*int(actor["level"]) or amount>int(actor["combat"]["hp_max"])-int(actor["combat"]["hp_current"]):
			return fail("Lay on Hands self-healing amount or eligibility invalid.")
		actual=heal(actor,{"total":amount})
	entry["spent"]=int(entry["spent"])+amount
	action_seconds=6
	return _commit(ctx,[SQL.stmt("UPDATE actors SET payload=? WHERE id=?",[JSON.stringify(actor),state["actor_id"]])],{"kind":"resource_use","resource_id":rid,"spent":entry["spent"],"rolls":rolls,"hp_restored":actual,"hp_current":actor["combat"]["hp_current"],"rule_refs":[RAW.rule_ref("damage-and-healing")]},"Class resource used; restored "+str(actual)+" HP.")

func rest(id: String,req: Dictionary,clearance: Dictionary) -> Dictionary:
	var ctx=begin(id,req,"rest",["rest_kind","hit_dice","prepared_ids"])
	if not ctx.get("ok",false) or ctx.get("replayed",false):
		return ctx
	if not allowed(ctx,clearance,"rest"):
		return fail("Verified uninterrupted rest, supplies, timing and eligible actor required.")
	var state=ctx["state"]
	var args=req["args"]
	var actor=state["actor"].duplicate(true)
	var combat=actor["combat"]
	if not args["rest_kind"] in ["short","long"] or not DTO.whole(args["hit_dice"],0,1) or not DTO.whole(combat.get("hit_dice_total"),1,1) or not DTO.whole(combat.get("hit_dice_spent"),0,1) or not combat.get("hit_die") in [6,8,10,12] or not DTO.whole(actor.get("ability_modifiers",{}).get("con"),-5,10) or not resource_map_valid(actor) or not slots_valid(actor) or actor["spellcasting"].get("concentration")!=null:
		return fail("Rest hit dice, resources or effect state requires review.")
	var commands: Array=[]
	var rolls: Array=[]
	var restored=0
	var preparation: Dictionary={}
	if args["rest_kind"]=="short":
		if args["prepared_ids"]!=null or int(combat["hit_dice_spent"])+int(args["hit_dice"])>int(combat["hit_dice_total"]):
			return fail("Short rest cannot prepare spells or overspend hit dice.")
		if args["hit_dice"]==1:
			var die=healing_dice(1,int(combat["hit_die"]),int(actor["ability_modifiers"]["con"]))
			rolls.append(die)
			restored=heal(actor,die)
			combat["hit_dice_spent"]+=1
		if not restore_short(actor):
			return fail("Short-rest features unavailable.")
		action_seconds=3600
	else:
		if args["hit_dice"]!=0 or state["elapsed_seconds"]==null:
			return fail("Long rest requires known tracked time and no short-rest hit dice expenditure.")
		var history=read(state,[SQL.stmt("SELECT payload FROM events WHERE kind='c3_long_rest' ORDER BY id DESC LIMIT 1")])
		if not history.get("ok",false):
			return history
		var end_time=int(state["elapsed_seconds"])+28800
		if not history["sets"][0].is_empty():
			var last=JSON.parse_string(history["sets"][0][0]["payload"])
			if not last is Dictionary or not DTO.whole(last.get("end_elapsed_seconds")) or end_time-int(last["end_elapsed_seconds"])<86400:
				return fail("A long rest benefit is available at most once per 24 hours.")
		if not DTO.whole(end_time):
			return fail("Rest exceeds tracked time range.")
		if args["prepared_ids"]!=null:
			preparation=spell_preparation(actor,args["prepared_ids"])
			if not preparation.get("ok",false):
				return preparation
			actor["spellcasting"]["prepared_ids"]=preparation["prepared_ids"]
		restored=int(combat["hp_max"])-int(combat["hp_current"])
		combat["hp_current"]=combat["hp_max"]
		combat["hp_temp"]=0
		combat["hit_dice_spent"]=maxi(0,int(combat["hit_dice_spent"])-maxi(1,floori(int(combat["hit_dice_total"])/2.0)))
		for entry in actor["resources"].values():
			entry["spent"]=0
		for slot in actor["spellcasting"]["slots"].values():
			slot["spent"]=0
		commands.append(SQL.stmt("INSERT INTO events(turn,game_time,kind,payload) VALUES(?,?,'c3_long_rest',?)",[state["turn"],"Elapsed "+str(end_time)+" seconds (tracked epoch)",JSON.stringify({"request_id":req["request_id"],"actor_id":state["actor_id"],"end_elapsed_seconds":end_time})]))
		action_seconds=28800+int(preparation.get("seconds",0))
	commands.append(SQL.stmt("UPDATE actors SET payload=? WHERE id=?",[JSON.stringify(actor),state["actor_id"]]))
	return _commit(ctx,commands,{"kind":"rest","rest_kind":args["rest_kind"],"rolls":rolls,"hp_restored":restored,"combat":combat,"resources":actor["resources"],"spellcasting":actor["spellcasting"],"rule_refs":[RAW.rule_ref("resting"),RAW.rule_ref("time")]},"Completed "+args["rest_kind"]+" rest.")

# Transfer one selected unequipped/unattuned instance or explicit denomination
# amounts between the controlled actor and a disclosed generated local NPC.
# No change to NPC template, actions, fixed AC/HP or any combat outcome.
func transfer(id: String,req: Dictionary,clearance: Dictionary) -> Dictionary:
	var kind=str(req.get("kind",""))
	if not kind in ["item_transfer","currency_transfer"]:
		return fail("Unknown transfer.")
	var fields=["from_actor_id","to_actor_id","instance_id","quantity"] if kind=="item_transfer" else ["from_actor_id","to_actor_id","coins"]
	var ctx=begin(id,req,kind,fields)
	if not ctx.get("ok",false) or ctx.get("replayed",false):
		return ctx
	if not allowed(ctx,clearance,"actor_transfer"):
		return fail("Verified local access, consent and quiet transfer required.")
	var state=ctx["state"]
	var args=req["args"]
	var from_id=args["from_actor_id"]
	var to_id=args["to_actor_id"]
	if not DTO.id_valid(from_id) or not DTO.id_valid(to_id) or from_id==to_id or not state["actor_id"] in [from_id,to_id]:
		return fail("One participant must be the controlled actor.")
	var npc=to_id if from_id==state["actor_id"] else from_id
	var visible=read(state,[SQL.stmt("SELECT a.id FROM actors a JOIN actor_instances i ON i.actor_id=a.id WHERE a.id=? AND a.kind='npc' AND a.location_id=? AND i.visibility='player'",[npc,state["location_id"]])])
	if not visible.get("ok",false) or visible["sets"][0].size()!=1:
		return fail("Local disclosed NPC unavailable; no enemy/combat transfers.")
	var sender=read_owned(state,from_id)
	var receiver=read_owned(state,to_id)
	if not sender.get("ok",false) or not receiver.get("ok",false):
		return fail("Participant ownership or mirror unavailable.")
	var a=sender["actor"].duplicate(true)
	var b=receiver["actor"].duplicate(true)
	var commands=owned_guards(sender)
	commands.append_array(owned_guards(receiver))
	var result={"kind":kind,"from_actor_id":from_id,"to_actor_id":to_id}
	if kind=="currency_transfer":
		if not coin_map(args["coins"]) or not coin_map(a.get("coins")) or not coin_map(b.get("coins")):
			return fail("Currency denominations unavailable.")
		var total=0
		for denom in DENOMS:
			var n=int(args["coins"][denom])
			if n>int(a["coins"][denom]) or not DTO.whole(int(b["coins"][denom])+n):
				return fail("Currency unavailable or exceeds supported amount.")
			total+=n
			a["coins"][denom]-=n
			b["coins"][denom]+=n
		if total==0:
			return fail("No currency selected.")
		result["coins"]=args["coins"]
	else:
		var iid=args["instance_id"]
		if not DTO.id_valid(iid) or not sender["items"].has(iid) or assigned(sender,iid) or not DTO.whole(args["quantity"],1):
			return fail("Select an owned, unequipped item.")
		var row=sender["items"][iid]
		var def=sender["definitions"][iid]
		var amount=int(args["quantity"])
		var old=int(row["quantity"])
		if amount>old or row["attunement"]=="attuned" or (amount<old and (row["charges"]!=null or row["origin"]!="official" or not row["attunement"] in ["unknown","not_required"])):
			return fail("Transfer quantity, charges or attunement requires review.")
		var dest=iid if amount==old else make_id()
		if amount==old:
			sender["items"].erase(iid)
			sender["definitions"].erase(iid)
			commands.append(SQL.stmt("UPDATE item_instances SET actor_id=? WHERE id=? AND actor_id=?",[to_id,iid,from_id]))
		else:
			row["quantity"]=old-amount
			commands.append(SQL.stmt("UPDATE item_instances SET quantity=? WHERE id=?",[old-amount,iid]))
			commands.append(SQL.stmt("INSERT INTO item_instances(id,definition_id,actor_id,quantity,charges,condition,attunement,provenance,source_event_id) SELECT ?,definition_id,?,CAST(? AS INTEGER),NULL,condition,attunement,provenance,source_event_id FROM item_instances WHERE id=?",[dest,to_id,amount,iid]))
		var copy=row.duplicate(true)
		copy["id"]=dest
		copy["actor_id"]=to_id
		copy["quantity"]=amount
		receiver["items"][dest]=copy
		receiver["definitions"][dest]=def
		commands.append(SQL.stmt("INSERT INTO item_transfers(id,request_id,source_instance_id,destination_instance_id,definition_id,quantity,destination_actor_id,source_event_id) VALUES(?,?,?,?,?,?,?,"+EVENT+")",[make_id(),req["request_id"],iid,dest,def["id"],amount,to_id,req["request_id"]]))
		result["instance_id"]=dest
		result["quantity"]=amount
	var load=weight(receiver,b)
	if load==null or not DTO.number(b.get("carrying_capacity_lb"),0,100000000) or load>float(b["carrying_capacity_lb"]):
		return fail("Recipient weight or carrying capacity unavailable.")
	commands.append_array(mirror_commands(sender,a))
	commands.append_array(mirror_commands(receiver,b))
	action_seconds=6
	return _commit(ctx,commands,result,"Selected possessions transferred.")
