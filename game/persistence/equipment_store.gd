extends "res://persistence/gameplay_session.gd"
## C2 migration reconciliation only, not a free equip/swap or party consent.
const ITEMS = preload("res://persistence/item_catalog.gd")

# Exact local choices for existing legacy equipped flags/weapon list. This
# records the missing hand metadata without changing AC, HP, gear or resources.
func reconcile_legacy_slots(id: String,request: Dictionary,local_review: bool = false) -> Dictionary:
	var ctx = begin(id,request,"reconcile_legacy_slots",["assignments"])
	if not ctx.get("ok",false) or ctx.get("replayed",false):
		return ctx
	if not local_review or not request["args"]["assignments"] is Array or request["args"]["assignments"].is_empty() or request["args"]["assignments"].size()>12:
		return fail("Trusted local reconciliation of legacy assignments required.")
	var state: Dictionary = ctx["state"]
	var aid = state["actor_id"]
	var r = read(state,[SQL.stmt("SELECT i.id,i.definition_id,d.origin,d.catalog_category,d.attributes FROM equipment_review v JOIN item_instances i ON i.id=v.instance_id JOIN item_definitions d ON d.id=i.definition_id WHERE v.actor_id=? AND i.actor_id=? ORDER BY i.id",[aid,aid]),SQL.stmt("SELECT slot,instance_id,grip FROM equipment_assignments WHERE actor_id=? ORDER BY slot",[aid])])
	if not r.get("ok",false):
		return r
	if r["sets"][0].is_empty():
		return fail("No unresolved legacy assignment.")
	var gear = state["actor"].get("equipment",{})
	if not gear is Dictionary or not gear.get("weapon_ids",[]) is Array:
		return fail("Legacy equipment malformed.")
	var known: Dictionary = {}
	var used: Dictionary = {}
	for row in r["sets"][1]:
		used[row["slot"]]=row["instance_id"]
	for row in r["sets"][0]:
		var attrs = JSON.parse_string(row["attributes"])
		if not attrs is Dictionary:
			return fail("Legacy definition unavailable.")
		known[row["id"]]={"id":row["definition_id"],"origin":row["origin"],"catalog_category":row["catalog_category"],"attributes":attrs}
	var cat = ITEMS.new()
	var resolved: Array = []
	var commands: Array = []
	for assignment in request["args"]["assignments"]:
		if not DTO.exact_keys(assignment,["instance_id","slot","grip"]) or not known.has(assignment["instance_id"]) or assignment["instance_id"] in resolved or not assignment["slot"] in ["body","shield","main_hand","off_hand"] or not assignment["grip"] in UI.GRIPS or used.has(assignment["slot"]):
			return fail("Invalid or conflicting legacy assignment.")
		var def: Dictionary = known[assignment["instance_id"]]
		var claim = def["id"] in gear["weapon_ids"] if assignment["slot"] in ["main_hand","off_hand"] else def["id"]==gear.get("armor_id" if assignment["slot"]=="body" else "shield_id")
		if not claim or not cat.physical_options(def).any(func(opt): return opt["slot"]==assignment["slot"] and opt["grip"]==assignment["grip"]):
			return fail("Assignment is not an already established compatible equipped item.")
		var row = assignment.duplicate(true)
		used[row["slot"]]=row["instance_id"]
		commands.append(SQL.stmt("INSERT INTO equipment_assignments(actor_id,slot,instance_id,grip) VALUES(?,?,?,?)",[aid,row["slot"],row["instance_id"],row["grip"]]))
		if row["grip"]=="two_handed":
			if row["slot"]!="main_hand" or used.has("off_hand") or used.has("shield"):
				return fail("Two-handed assignment conflicts with established hands.")
			used["off_hand"]=row["instance_id"]
			commands.append(SQL.stmt("INSERT INTO equipment_assignments(actor_id,slot,instance_id,grip) VALUES(?,'off_hand',?,'two_handed')",[aid,row["instance_id"]]))
		resolved.append(row["instance_id"])
		commands.append(SQL.stmt("DELETE FROM equipment_review WHERE actor_id=? AND instance_id=?",[aid,row["instance_id"]]))
	if resolved.size()!=known.size() or (used.has("shield") and used.has("main_hand") and used.has("off_hand")):
		return fail("All legacy claims must be reconciled without excess hands.")
	return _commit(ctx,commands,{"resolved_instance_ids":resolved},"Existing equipment assignments clarified.")

# Future C3 party adapter records only an independently verified consent
# outcome. No automatic control, stat changes or teleporting a companion.
func record_party_membership(id: String,request: Dictionary,local_review: bool = false) -> Dictionary:
	var ctx = begin(id,request,"party_membership",["member_actor_id","status","source_event_id"])
	if not ctx.get("ok",false) or ctx.get("replayed",false):
		return ctx
	var state: Dictionary = ctx["state"]
	var a: Dictionary = request["args"]
	if not local_review or not DTO.id_valid(a["member_actor_id"]) or a["member_actor_id"]==state["actor_id"] or not a["status"] in ["member","departed"]:
		return fail("Trusted local consent or departure outcome required.")
	var e = source(state,a["source_event_id"])
	if not public_source(e) or e["kind"] not in ["mechanical_receipt","gameplay_change"]:
		return fail("Party membership requires an established local outcome.")
	var r = read(state,[SQL.stmt("SELECT a.id,a.location_id,i.visibility FROM actors a JOIN actor_instances i ON i.actor_id=a.id WHERE a.id=? AND a.kind='npc'",[a["member_actor_id"]]),SQL.stmt("SELECT status,source_event_id FROM party_members WHERE actor_id=?",[a["member_actor_id"]])])
	if not r.get("ok",false) or r["sets"][0].size()!=1 or r["sets"][0][0]["visibility"]!="player" or (a["status"]=="member" and r["sets"][0][0]["location_id"]!=state["location_id"]):
		return fail("Companion identity or local access unavailable.")
	if a["status"]=="departed" and r["sets"][1].is_empty():
		return fail("Companion is not a recorded member.")
	if not r["sets"][1].is_empty() and r["sets"][1][0]["status"]==a["status"]:
		return _reuse(ctx,{"member_actor_id":a["member_actor_id"],"status":a["status"]},DTO.sql_int(r["sets"][1][0]["source_event_id"]))
	var commands = [SQL.stmt("INSERT INTO party_members(actor_id,source_event_id,status,visibility) VALUES(?,?,?,'player') ON CONFLICT(actor_id) DO UPDATE SET source_event_id=excluded.source_event_id,status=excluded.status",[a["member_actor_id"],int(a["source_event_id"]),a["status"]])]
	return _commit(ctx,commands,{"member_actor_id":a["member_actor_id"],"status":a["status"]},"Companion membership recorded.")
