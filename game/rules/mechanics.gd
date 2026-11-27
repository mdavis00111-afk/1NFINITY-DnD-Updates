extends RefCounted
## 2018 Basic Rules pp. 8–12, 15–21, 22–33, 60–65. Level-one draft, not a complete character builder.
const ABILITIES = ["STR","DEX","CON","INT","WIS","CHA"]
const RACES = {
	"Hill Dwarf":{"bonuses":{"CON":2,"WIS":1},"speed":25,"extra_hp":1},
	"Mountain Dwarf":{"bonuses":{"CON":2,"STR":2},"speed":25,"extra_hp":0},
	"High Elf":{"bonuses":{"DEX":2,"INT":1},"speed":30,"extra_hp":0},
	"Wood Elf":{"bonuses":{"DEX":2,"WIS":1},"speed":35,"extra_hp":0},
	"Lightfoot Halfling":{"bonuses":{"DEX":2,"CHA":1},"speed":25,"extra_hp":0},
	"Stout Halfling":{"bonuses":{"DEX":2,"CON":1},"speed":25,"extra_hp":0},
	"Human":{"bonuses":{"STR":1,"DEX":1,"CON":1,"INT":1,"WIS":1,"CHA":1},"speed":30,"extra_hp":0}}
const CLASSES = {
	"Cleric":{"die":8,"priority":["WIS","CON","STR","DEX","CHA","INT"],"saves":["WIS","CHA"]},
	"Fighter":{"die":10,"priority":["STR","CON","DEX","WIS","CHA","INT"],"saves":["STR","CON"]},
	"Rogue":{"die":8,"priority":["DEX","INT","CON","CHA","WIS","STR"],"saves":["DEX","INT"]},
	"Wizard":{"die":6,"priority":["INT","CON","DEX","WIS","CHA","STR"],"saves":["INT","WIS"]}}
const SKILLS = {"Acrobatics":"DEX","Animal Handling":"WIS","Arcana":"INT","Athletics":"STR","Deception":"CHA","History":"INT","Insight":"WIS","Intimidation":"CHA","Investigation":"INT","Medicine":"WIS","Nature":"INT","Perception":"WIS","Performance":"CHA","Persuasion":"CHA","Religion":"INT","Sleight of Hand":"DEX","Stealth":"DEX","Survival":"WIS"}
const XP = [0,300,900,2700,6500,14000,23000,34000,48000,64000,85000,100000,120000,140000,165000,195000,225000,265000,305000,355000]

static func modifier(score: int) -> int:
	return floori((score - 10) / 2.0)

static func proficiency(level: int) -> int:
	return 2 + floori((level - 1) / 4.0) if level >= 1 and level <= 20 else 0

static func roll(count: int, sides: int) -> Array:
	var values = []
	if count < 1 or count > 100 or sides < 2 or sides > 1000:
		return values
	for i in range(count):
		values.append(randi_range(1, sides))
	return values

static func draft(race: String, role: String, gender: String, character_name: String, standard: bool) -> Dictionary:
	if not RACES.has(race) or not CLASSES.has(role):
		return {}
	var history = []
	var values = [15,14,13,12,10,8] if standard else []
	if not standard:
		for i in range(6):
			var dice = roll(4,6)
			history.append(dice.duplicate())
			dice.sort()
			values.append(int(dice[1]) + int(dice[2]) + int(dice[3]))
		values.sort()
		values.reverse()
	var race_data = RACES[race]
	var class_data = CLASSES[role]
	var scores = {}
	var mods = {}
	var saves = {}
	for i in range(6):
		var key = class_data["priority"][i]
		scores[key] = int(values[i]) + int(race_data["bonuses"].get(key,0))
		mods[key] = modifier(scores[key])
		saves[key] = mods[key] + (2 if key in class_data["saves"] else 0)
	var hp = int(class_data["die"]) + int(mods["CON"]) + int(race_data["extra_hp"])
	return {"draft":true,"name":character_name,"race":race,"class":role,"gender":gender,"level":1,"xp":0,"proficiency":2,"scores":scores,"modifiers":mods,"saves":saves,"hp":hp,"hit_die":class_data["die"],"speed":race_data["speed"],"initiative":mods["DEX"],"unarmored_ac":10+int(mods["DEX"]),"roll_history":history,"method":"standard_array" if standard else "4d6_drop_lowest"}
