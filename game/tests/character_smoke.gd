extends SceneTree
const RULES=preload("res://rules/character_rules.gd")
var rules=RULES.new()
var failures: Array=[]
func _initialize() -> void:
	if not rules.cat.initialize():
		push_error(rules.cat.last_error)
		quit(1)
		return
	var cases: Array=[]
	for role in rules.cat.rows("classes"):
		cases.append(["human","",role["index"],"acolyte"])
	for race in rules.cat.rows("races"):
		var sub=race.get("subraces",[])
		if sub.is_empty():
			cases.append([race["index"],"","wizard","sage"])
		else:
			for s in sub:
				cases.append([race["index"],s["index"],"wizard","sage"])
	for c in cases:
		var d=rules.fresh()
		d["name"]="Smoke Test"
		d["race_id"]=c[0]
		d["subrace_id"]=c[1]
		d["class_id"]=c[2]
		d["background_id"]=c[3]
		if int(RULES.SUBCLASS_AT.get(c[2],99))==1:
			d["subclass_id"]=rules.cat.filtered("subclasses","class",c[2])[0]["index"]
		rules.roll_scores(d,"array")
		for stage in range(2,5):
			var done: Array=[]
			for j in range(100):
				var next_group: Dictionary={}
				for g in rules.groups(d,stage):
					if not g["key"] in done:
						next_group=g
						break
				if next_group.is_empty():
					break
				done.append(next_group["key"])
				var picked: Array=[]
				var used: Array=[]
				for opt in next_group["options"]:
					var collision=false
					for part in opt["parts"]:
						if part["id"] in used and next_group["kind"]!="gear":
							collision=true
					if collision:
						continue
					picked.append(opt["key"])
					for part in opt["parts"]:
						used.append(part["id"])
					if picked.size()>=int(next_group["count"]):
						break
				d["answers"][next_group["key"]]=picked
		for stage in range(1,5):
			var err=rules.validate_step(d,stage)
			if not err.is_empty():
				failures.append(str(c)+" stage "+str(stage)+": "+err)
		var result=rules.full_record(d)
		if result["combat"]["hp_max"]<=0 or result["inventory"].is_empty() or result["skills"].size()!=18:
			failures.append(str(c)+": bad derived record")
	if rules.mod_for(8)!=-1 or rules.mod_for(9)!=-1 or rules.mod_for(18)!=4:
		failures.append("Ability modifier formula")
	for failure in failures:
		push_error(failure)
	print("Character creator smoke cases: ",cases.size(),"; failures: ",failures.size())
	quit(0 if failures.is_empty() else 1)
