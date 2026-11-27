extends RefCounted
## Pure B2 rules and receipt validation. No provider, no database writes.
## 2014 PHB ch. 7 (pp. 173–179), ch. 8 (pp. 181–183), appendix A.
## Rule IDs match the packaged 2014/2018 catalogue.
const DTO = preload("res://world/world_dto.gd")
const CAT = preload("res://rules/catalog.gd")
const DISPLAY = preload("res://gameplay/display_values.gd")
const ABILITIES = ["str","dex","con","int","wis","cha"]
const DIFFICULTY = {"very_easy":5,"easy":10,"medium":15,"hard":20,"very_hard":25,"nearly_impossible":30}
const PACE = {"slow":2,"normal":3,"fast":4}
# Hourly route legs only. The PHB daily column differs from hourly
# approximations; do not extrapolate fast pace to 32 miles/day.
const DAILY_MILES = {"slow":18,"normal":24,"fast":30}
const MAX_WALK_SECONDS = 28800
const HANDLERS = ["ability_check","saving_throw","observe","wait","move","travel"]
const CONDITIONS = ["blinded","charmed","deafened","frightened","grappled","incapacitated","invisible","paralyzed","petrified","poisoned","prone","restrained","stunned","unconscious"]

static func fail(message: String, status: String = "unsupported") -> Dictionary:
	return {"ok":false,"status":status,"error":message}

static func rule_ref(id: String, category: String = "rule-sections") -> Dictionary:
	return {"category":category,"id":id,"ruleset":CAT.RULESET,"revision":CAT.REVISION}

static func ref_valid(ref: Variant, cat) -> bool:
	return DTO.exact_keys(ref,["category","id","ruleset","revision"]) and ref["category"] in ["rule-sections","skills","ability-scores","conditions"] and DTO.bounded_text(ref["id"],100) and ref["ruleset"]==CAT.RULESET and ref["revision"]==CAT.REVISION and not cat.get_record(ref["category"],ref["id"]).is_empty()

static func refs_for(kind: String, ability: String = "", skill: Variant = null, actor: Dictionary = {}) -> Array:
	var refs: Array = []
	if kind in ["ability_check","saving_throw"]:
		for id in ["ability-scores-and-modifiers","proficiency-bonus","advantage-and-disadvantage","ability-checks" if kind=="ability_check" else "saving-throws","time"]:
			refs.append(rule_ref(id))
		refs.append(rule_ref(ability,"ability-scores"))
		if skill!=null:
			refs.append(rule_ref(str(skill),"skills"))
		var combat = actor.get("combat",{})
		for condition in CONDITIONS:
			if condition in combat.get("conditions",[]):
				refs.append(rule_ref(condition,"conditions"))
		if int(combat.get("exhaustion",0))>0:
			refs.append(rule_ref("exhaustion","conditions"))
	elif kind in ["travel","move"]:
		refs = [rule_ref("movement"),rule_ref("time")]
	else:
		refs = [rule_ref("time")]
	return refs

static func valid_refs(refs: Variant, expected: Array, cat) -> bool:
	if not refs is Array or refs!=expected or not cat.initialize():
		return false
	for ref in refs:
		if not ref_valid(ref,cat):
			return false
	return true

# Stored scores/proficiencies are the authority; inconsistent legacy derived
# values or unimplemented feature effects must not produce an invented bonus.
static func actor_ready(actor: Dictionary) -> bool:
	var combat = actor.get("combat")
	if actor.get("ruleset")!=CAT.RULESET or actor.get("catalog_revision")!=CAT.REVISION or not combat is Dictionary or not DTO.whole(actor.get("level"),1,20) or not DTO.whole(combat.get("hp_current"),1) or not DTO.whole(combat.get("hp_max"),1) or combat["hp_current"]>combat["hp_max"]:
		return false
	if not combat.get("conditions") is Array or not combat.get("active_effects") is Array or not DTO.whole(combat.get("exhaustion"),0,5):
		return false
	if not combat["active_effects"].is_empty():
		return false
	for condition in combat["conditions"]:
		if not condition in CONDITIONS:
			return false
	return true

static func modifier_for(actor: Dictionary, kind: String, ability: String, skill: Variant, cat) -> Dictionary:
	if not actor_ready(actor) or not ability in ABILITIES:
		return fail("Actor statistics or active effects require review.")
	var scores = actor.get("ability_scores")
	var modifiers = actor.get("ability_modifiers")
	var profs = actor.get("proficiency_ids")
	var expertise = actor.get("expertise_ids")
	var skills = actor.get("skills")
	var saves = actor.get("saving_throws")
	var pb = actor.get("proficiency_bonus")
	if not scores is Dictionary or not modifiers is Dictionary or not profs is Array or not expertise is Array or not skills is Dictionary or not saves is Dictionary or not DTO.whole(pb,2,6) or pb!=2+floori((int(actor["level"])-1)/4.0):
		return fail("Missing or inconsistent proficiency statistics.")
	if not DTO.whole(scores.get(ability),1,30) or not DTO.whole(modifiers.get(ability),-5,10):
		return fail("Ability score or modifier unavailable.")
	var base = floori((int(scores[ability])-10)/2.0)
	if base!=modifiers[ability]:
		return fail("Saved ability modifier differs from its score.")
	var modifier = base
	if kind=="saving_throw":
		if skill!=null:
			return fail("A saving throw does not use a skill.","invalid")
		if "saving-throw-"+ability in profs:
			modifier+=int(pb)
		var protection = actor.get("equipment",{}).get("protection_bonus",0)
		if not DTO.whole(protection,0,2):
			return fail("Protection bonus requires review.")
		modifier+=int(protection)
		if not DTO.whole(saves.get(ability),-5,30) or saves[ability]!=modifier:
			return fail("Saving throw has missing or unsupported modifiers.")
	elif skill!=null:
		if not skill is String:
			return fail("Invalid skill ID.","invalid")
		var rule = cat.get_record("skills",skill)
		var entry = skills.get(skill)
		if rule.is_empty() or not entry is Dictionary:
			return fail("Skill reference or actor skill is unavailable.")
		var trained = "skill-"+skill in profs
		var expert = "skill-"+skill in expertise
		if entry.get("proficient")!=trained or entry.get("expertise")!=expert or (expert and not trained):
			return fail("Skill proficiency state inconsistent.")
		var default_ability = rule.get("ability_score",{}).get("index")
		if not default_ability in ABILITIES or entry.get("ability")!=default_ability or not DTO.whole(scores.get(default_ability),1,30) or not DTO.whole(modifiers.get(default_ability),-5,10) or modifiers[default_ability]!=floori((int(scores[default_ability])-10)/2.0):
			return fail("Skill ability or saved modifier unavailable.")
		var extra = int(pb)*(2 if expert else (1 if trained else 0))
		if not DTO.whole(entry.get("modifier"),-5,30) or entry["modifier"]!=int(modifiers[default_ability])+extra:
			return fail("Skill has unsupported situational or feature modifiers.")
		modifier+=extra
	elif kind!="ability_check":
		return fail("Unknown roll handler.","invalid")
	return {"ok":true,"modifier":modifier}

# No automatic natural-1/20 success/failure for checks/saves. Condition
# effects that need context (e.g. a visible fear source) require a local ruling.
static func roll_context(actor: Dictionary, kind: String, ability: String, advantage: bool, disadvantage: bool) -> Dictionary:
	var combat = actor["combat"]
	var conditions: Array = combat["conditions"]
	var exhaustion = int(combat["exhaustion"])
	var equipment = actor.get("equipment",{})
	if not equipment is Dictionary or not equipment.get("armor_penalty") is bool:
		return fail("Equipment proficiency state requires review.")
	# PHB p. 144: nonproficient armor imposes disadvantage on STR/DEX checks/saves.
	if ability in ["str","dex"] and equipment.get("armor_penalty",false)==true:
		disadvantage=true
	var auto_fail = false
	for condition in ["paralyzed","petrified","stunned","unconscious"]:
		if condition in conditions and kind=="saving_throw" and ability in ["str","dex"]:
			auto_fail=true
	if kind=="ability_check":
		disadvantage = disadvantage or exhaustion>=1 or "poisoned" in conditions
		if "incapacitated" in conditions or "unconscious" in conditions or "paralyzed" in conditions or "petrified" in conditions or "stunned" in conditions:
			return fail("This actor cannot perform the proposed active check.")
	else:
		disadvantage = disadvantage or exhaustion>=3 or (ability=="dex" and "restrained" in conditions)
	var mode = "normal"
	if advantage!=disadvantage:
		mode = "advantage" if advantage else "disadvantage"
	return {"ok":true,"mode":mode,"automatic_failure":auto_fail}

static func selected_die(values: Array, mode: String) -> Variant:
	var count = 1 if mode=="normal" else 2
	if not mode in ["normal","advantage","disadvantage"] or values.size()!=count:
		return null
	for v in values:
		if not DTO.whole(v,1,20):
			return null
	if mode=="advantage":
		return maxi(int(values[0]),int(values[1]))
	if mode=="disadvantage":
		return mini(int(values[0]),int(values[1]))
	return int(values[0])

static func roll_receipt(kind: String, mode: String, modifier: int, dc: int) -> Dictionary:
	var values: Array = []
	for i in range(1 if mode=="normal" else 2):
		values.append(randi_range(1,20))
	var selected = selected_die(values,mode)
	var total = int(selected)+modifier
	return {"roll_id":Crypto.new().generate_random_bytes(16).hex_encode(),"kind":kind,"sides":20,"mode":mode,"values":values,"selected":selected,"modifier":modifier,"total":total,"target":dc,"result":"success" if total>=dc else "failure"}

static func roll_valid(roll: Variant, kind: String, mode: String, modifier: int, dc: int) -> bool:
	if not DTO.exact_keys(roll,["roll_id","kind","sides","mode","values","selected","modifier","total","target","result"]) or not DTO.id_valid(roll["roll_id"]) or roll["kind"]!=kind or roll["sides"]!=20 or roll["mode"]!=mode or not roll["values"] is Array:
		return false
	var selected = selected_die(roll["values"],mode)
	return selected!=null and DTO.whole(roll["selected"],1,20) and roll["selected"]==selected and DTO.whole(roll["modifier"],-5,30) and roll["modifier"]==modifier and DTO.whole(roll["total"],-4,50) and roll["total"]==selected+modifier and DTO.whole(roll["target"],0,DTO.MAX_INT) and roll["target"]==dc and roll["result"]==("success" if roll["total"]>=dc else "failure")

static func time_valid(effect: Variant, current: Dictionary) -> bool:
	if not DTO.exact_keys(effect,["kind","seconds","establish_clock"]) or effect["kind"]!="time" or not effect["establish_clock"] is bool or (effect["seconds"]!=null and not DTO.whole(effect["seconds"],0,MAX_WALK_SECONDS)):
		return false
	if effect["establish_clock"] and (current.get("elapsed_seconds")!=null or effect["seconds"]==null):
		return false
	if effect["seconds"]!=null and current.get("elapsed_seconds")!=null and not DTO.whole(int(current["elapsed_seconds"])+int(effect["seconds"])):
		return false
	return true

static func time_after(effect: Dictionary,current: Dictionary) -> Variant:
	if effect["seconds"]==null:
		return null
	if effect["establish_clock"]:
		return int(effect["seconds"])
	if current.get("elapsed_seconds")==null:
		return null
	return int(current["elapsed_seconds"])+int(effect["seconds"])

static func travel_seconds(distance: Variant, pace: String, difficult: bool) -> Variant:
	if not PACE.has(pace) or not DTO.number(distance,0.000001,float(DAILY_MILES[pace])):
		return null
	var seconds = ceili(float(distance)*3600.0/float(PACE[pace])*(2.0 if difficult else 1.0))
	return seconds if DTO.whole(seconds,1,MAX_WALK_SECONDS) else null

static func travel_actor(actor: Dictionary, inventory: Array, cat) -> Dictionary:
	if not actor_ready(actor):
		return fail("Actor is not able to undertake supported travel.")
	var combat = actor["combat"]
	if not combat.get("speed_feet") in [25,30,35] or combat["exhaustion"]!=0 or not combat["conditions"].is_empty():
		return fail("Travel with conditions, exhaustion or unknown speed requires another handler.")
	var scores = actor.get("ability_scores")
	if not scores is Dictionary:
		return fail("Ability scores unavailable.")
	var strength = scores.get("str")
	if not DTO.whole(combat.get("passive_perception"),0,40) or not DTO.whole(strength,1,30) or not combat.get("size") in ["Small","Medium"] or not DTO.number(actor.get("carrying_capacity_lb"),0,100000) or actor["carrying_capacity_lb"]!=int(strength)*15:
		return fail("Passive perception, size or carrying capacity requires review.")
	var load = DISPLAY.weight_summary(cat,inventory,actor.get("coins"))
	if not load.get("complete",false) or float(load["known_lb"])>float(actor["carrying_capacity_lb"]):
		return fail("Travel load is incomplete or exceeds carrying capacity.")
	return {"ok":true,"passive_perception":int(combat["passive_perception"])}

# Validate all registered nested unions before any write. Travel route facts
# are rechecked by TurnStore under the same revision and SQL guard.
static func receipt_valid(receipt: Variant, current: Dictionary, cat) -> bool:
	if not DTO.receipt_valid(receipt) or receipt["results"].size()!=1 or receipt["effects"].is_empty():
		return false
	var result = receipt["results"][0]
	var kind = result.get("kind")
	var time = receipt["effects"].back()
	if not time_valid(time,current):
		return false
	if kind in ["ability_check","saving_throw"]:
		if not DTO.exact_keys(result,["kind","ability","skill","dc","advantage","disadvantage","mode","outcome","roll_id"]) or not DTO.whole(result["dc"],0,DTO.MAX_INT) or not result["advantage"] is bool or not result["disadvantage"] is bool or not result["ability"] in ABILITIES or receipt["effects"].size()!=1:
			return false
		var mod = modifier_for(current["actor"],kind,result["ability"],result["skill"],cat)
		if not mod.get("ok",false):
			return false
		var context = roll_context(current["actor"],kind,result["ability"],result["advantage"],result["disadvantage"])
		if not context.get("ok",false) or result["mode"]!=context["mode"] or not valid_refs(receipt["rule_refs"],refs_for(kind,result["ability"],result["skill"],current["actor"]),cat):
			return false
		if context["automatic_failure"]:
			return result["roll_id"]==null and result["outcome"]=="automatic_failure" and receipt["rolls"].is_empty()
		if receipt["rolls"].size()!=1:
			return false
		var roll = receipt["rolls"][0]
		return roll_valid(roll,kind,context["mode"],mod["modifier"],int(result["dc"])) and result["roll_id"]==roll["roll_id"] and result["outcome"]==roll["result"]
	if kind in ["observe","wait"]:
		return actor_ready(current["actor"]) and not "unconscious" in current["actor"]["combat"]["conditions"] and DTO.exact_keys(result,["kind","outcome"]) and result["outcome"]=="completed" and receipt["rolls"].is_empty() and receipt["effects"].size()==1 and (kind!="wait" or (time["seconds"]!=null and time["seconds"]>0)) and valid_refs(receipt["rule_refs"],refs_for(kind),cat)
	if kind in ["move","travel"]:
		if not DTO.exact_keys(result,["kind","outcome","pace","difficult","fast_travel","passive_perception","route_id","destination_id"]) or result["outcome"]!="arrived" or not result["difficult"] is bool or not result["fast_travel"] is bool or not PACE.has(result["pace"]) or receipt["effects"].size()!=2 or not receipt["rolls"].is_empty() or not DTO.id_valid(result["route_id"]) or not DTO.id_valid(result["destination_id"]):
			return false
		var move = receipt["effects"][0]
		if not DTO.movement_valid(move) or move["segments"].size()!=1:
			return false
		var segment = move["segments"][0]
		var seconds = travel_seconds(segment["distance_miles"],result["pace"],result["difficult"])
		var actor_check = travel_actor(current["actor"],current.get("inventory",[]),cat)
		return actor_check.get("ok",false) and segment["from_id"]==current["location_id"] and segment["to_id"]==result["destination_id"] and segment["route_id"]==result["route_id"] and seconds!=null and segment["elapsed_seconds"]==seconds and time["seconds"]==seconds and result["passive_perception"]==actor_check["passive_perception"]-(5 if result["pace"]=="fast" else 0) and valid_refs(receipt["rule_refs"],refs_for(kind),cat)
	return false

# Validate a persisted B2 receipt's self-consistency without reconstructing
# old actor state, rerolling, querying a provider or re-adjudicating a turn.
static func stored_receipt_usable(value: Variant) -> bool:
	if not DTO.receipt_valid(value) or value["results"].size()!=1 or value["effects"].is_empty() or value["effects"].back().get("kind")!="time":
		return false
	var time = value["effects"].back()
	if time["establish_clock"] and time["seconds"]==null:
		return false
	var action = value["results"][0]
	var kind = action.get("kind")
	if not kind in HANDLERS:
		return false
	var expected: Array = []
	if kind in ["ability_check","saving_throw"]:
		if not DTO.exact_keys(action,["kind","ability","skill","dc","advantage","disadvantage","mode","outcome","roll_id"]) or not action["ability"] in ABILITIES or not DTO.whole(action["dc"]) or not action["advantage"] is bool or not action["disadvantage"] is bool or not action["mode"] in ["normal","advantage","disadvantage"] or value["effects"].size()!=1:
			return false
		if (action["skill"]!=null and not DTO.bounded_text(action["skill"],100)) or (kind=="saving_throw" and action["skill"]!=null):
			return false
		expected=refs_for(kind,action["ability"],action["skill"])
		if action["outcome"]=="automatic_failure":
			if kind!="saving_throw" or not action["ability"] in ["str","dex"] or action["roll_id"]!=null or not value["rolls"].is_empty():
				return false
		else:
			if not action["outcome"] in ["success","failure"] or value["rolls"].size()!=1:
				return false
			var roll = value["rolls"][0]
			if not DTO.whole(roll.get("modifier"),-5,30) or not roll_valid(roll,kind,action["mode"],int(roll["modifier"]),int(action["dc"])) or roll["roll_id"]!=action["roll_id"] or roll["result"]!=action["outcome"]:
				return false
	elif kind in ["move","travel"]:
		if not DTO.exact_keys(action,["kind","outcome","pace","difficult","fast_travel","passive_perception","route_id","destination_id"]) or action["outcome"]!="arrived" or not PACE.has(action["pace"]) or not action["difficult"] is bool or not action["fast_travel"] is bool or not DTO.whole(action["passive_perception"],-5,40) or not DTO.id_valid(action["route_id"]) or not DTO.id_valid(action["destination_id"]) or not value["rolls"].is_empty() or value["effects"].size()!=2 or not DTO.movement_valid(value["effects"][0]) or value["effects"][0]["segments"].size()!=1:
			return false
		var segment = value["effects"][0]["segments"][0]
		var seconds = travel_seconds(segment["distance_miles"],action["pace"],action["difficult"])
		if seconds==null or segment["elapsed_seconds"]!=seconds or time["seconds"]!=seconds or segment["to_id"]!=action["destination_id"] or segment["route_id"]!=action["route_id"]:
			return false
		expected=refs_for(kind)
	else:
		if not DTO.exact_keys(action,["kind","outcome"]) or action["outcome"]!="completed" or not value["rolls"].is_empty() or value["effects"].size()!=1 or (kind=="wait" and not DTO.whole(time["seconds"],1,MAX_WALK_SECONDS)):
			return false
		expected=refs_for(kind)
	# Base references are mandatory; historical condition context cannot be
	# recomputed from the post-turn actor. Validate extra reference shape only.
	var seen: Array = []
	for ref in value["rule_refs"]:
		if not DTO.exact_keys(ref,["category","id","ruleset","revision"]) or not ref["category"] in ["rule-sections","skills","ability-scores","conditions"] or not DTO.bounded_text(ref["id"],100) or ref["ruleset"]!=CAT.RULESET or ref["revision"]!=CAT.REVISION or ref in seen:
			return false
		if not ref in expected and (not kind in ["ability_check","saving_throw"] or ref["category"]!="conditions" or not ref["id"] in CONDITIONS+["exhaustion"]):
			return false
		seen.append(ref)
	for ref in expected:
		if not ref in seen:
			return false
	return true

static func summary(receipt: Dictionary) -> String:
	var action = receipt["results"][0]
	match action["kind"]:
		"ability_check","saving_throw":
			if action["outcome"]=="automatic_failure":
				return "Automatic failure: "+action["ability"].to_upper()+" save (condition)."
			var roll = receipt["rolls"][0]
			return action["kind"].replace("_"," ").capitalize()+": "+str(roll["values"])+"; selected "+str(roll["selected"])+"; modifier "+("%+d" % int(roll["modifier"]))+"; total "+str(roll["total"])+" vs DC "+str(roll["target"])+" — "+roll["result"]+"."
		"move","travel":
			var segment = receipt["effects"][0]["segments"][0]
			return "Travel completed: "+str(segment["distance_miles"])+" miles at "+action["pace"]+" pace in "+str(segment["elapsed_seconds"])+" seconds."
		"wait":
			return "Waited "+str(receipt["effects"].back()["seconds"])+" seconds."
	return "Observation completed; no mechanical change."
