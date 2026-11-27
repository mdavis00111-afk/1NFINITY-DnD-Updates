extends "res://persistence/gameplay_session.gd"
## Persistent story records. No generated plot, automatic quest acceptance,
## implicit mechanical relationship effects or private-to-public promotion.
const KINDS = ["overview","situation","quest","objective","relationship","animosity","repeat_offender","faction","debt","promise","unresolved_event","circumstance"]
const TERMINAL = ["completed","failed","abandoned","resolved","closed"]

func update_story(id: String,request: Dictionary,local_review: bool = false) -> Dictionary:
	var ctx = begin(id,request,"story_update",["record_id","identity_key","kind","title","description","status","visibility","certainty","location_id","parent_id","source_event_id","progress_current","progress_max","participants"])
	if not ctx.get("ok",false) or ctx.get("replayed",false):
		return ctx
	if not local_review:
		return fail("Trusted local story reconciliation required.")
	var a: Dictionary = request["args"]
	var state: Dictionary = ctx["state"]
	if (a["record_id"]!=null and not DTO.id_valid(a["record_id"])) or not DTO.bounded_text(a["identity_key"],128) or not a["kind"] in KINDS or not DTO.bounded_text(a["title"],120) or not DTO.bounded_text(a["description"],4000) or not a["visibility"] in ["player","private"] or not a["certainty"] in ["fact","rumour","attitude"] or not a["status"] in ["offered","active","completed","failed","abandoned","resolved","open","closed"] or (a["location_id"]!=null and not DTO.id_valid(a["location_id"])) or (a["parent_id"]!=null and not DTO.id_valid(a["parent_id"])) or not a["participants"] is Array or a["participants"].size()>32:
		return fail("Invalid story record.")
	if (a["kind"]=="overview" and a["identity_key"]!="campaign-overview") or (a["kind"]=="situation" and a["identity_key"]!="campaign-situation"):
		return fail("Overview and situation have fixed campaign identities.")
	if (a["progress_current"]==null)!=(a["progress_max"]==null) or (a["progress_current"]!=null and (not DTO.whole(a["progress_current"]) or not DTO.whole(a["progress_max"],1) or a["progress_current"]>a["progress_max"])):
		return fail("Invalid objective progress.")
	var event = source(state,a["source_event_id"])
	if event.is_empty() or (a["visibility"]=="player" and not public_source(event)):
		return fail("Story provenance or disclosure unavailable.")
	var queried = read(state,[SQL.stmt("SELECT * FROM story_records WHERE identity_key=? OR id=? ORDER BY id",[a["identity_key"],a["record_id"]]),SQL.stmt("SELECT l.id,d.visibility,d.status FROM locations l LEFT JOIN world_discovery d ON d.location_id=l.id WHERE l.id=?",[a["location_id"]]),SQL.stmt("SELECT id,kind,visibility,status FROM story_records WHERE id=?",[a["parent_id"]])])
	if not queried.get("ok",false):
		return queried
	var sets: Array = queried["sets"]
	if sets[0].size()>1 or (a["record_id"]!=null and (sets[0].size()!=1 or sets[0][0]["id"]!=a["record_id"])):
		return fail("Story identity ambiguous or unavailable.")
	if a["location_id"]!=null and (sets[1].size()!=1 or (a["visibility"]=="player" and (sets[1][0]["visibility"]!="player" or sets[1][0]["status"]=="unknown"))):
		return fail("Story location not established/disclosed.")
	if a["parent_id"]!=null and (sets[2].size()!=1 or (a["visibility"]=="player" and sets[2][0]["visibility"]!="player")):
		return fail("Story parent unavailable.")
	if a["kind"]=="objective" and (sets[2].size()!=1 or sets[2][0]["kind"]!="quest"):
		return fail("Objective must belong to a quest.")
	if a["kind"]!="objective" and a["parent_id"]!=null:
		return fail("Only objective-to-quest parent links currently supported.")
	var record_id = make_id()
	var old: Dictionary = {}
	if sets[0].size()==1:
		old=sets[0][0]
		record_id=old["id"]
		if old["identity_key"]!=a["identity_key"] or old["kind"]!=a["kind"] or old["parent_id"]!=a["parent_id"] or old["visibility"]!=a["visibility"] or old["certainty"]!=a["certainty"]:
			return fail("Established identity, disclosure and certainty preserved. Add a separately evidenced record.")
		if a["kind"] in ["quest","objective"] and old["status"] in TERMINAL and old["status"]!=a["status"]:
			return fail("Terminal history cannot be silently reopened.")
		if old["status"]=="active" and a["status"]=="offered":
			return fail("Quest cannot regress to offered.")
		var old_progress = DTO.sql_int(old["progress_current"])
		if old_progress!=null and (a["progress_current"]==null or a["progress_current"]<old_progress or a["progress_max"]!=DTO.sql_int(old["progress_max"])):
			return fail("Established objective progress cannot silently regress.")
		if a["kind"]=="quest" and old["status"]=="offered" and a["status"]=="active" and event["kind"]!="mechanical_receipt" and event["kind"]!="gameplay_change":
			return fail("Quest acceptance requires established player action, not narration alone.")
	elif a["kind"]=="quest" and a["status"]!="offered":
		return fail("New quest must be offered, never forced active.")
	if a["kind"]=="quest" and a["status"]=="completed":
		var incomplete = read(state,[SQL.stmt("SELECT id FROM story_records WHERE parent_id=? AND kind='objective' AND status<>'completed' LIMIT 1",[record_id])])
		if not incomplete.get("ok",false) or not incomplete["sets"][0].is_empty():
			return fail("Quest still has unresolved objectives.")
	if a["kind"]=="objective" and a["status"]=="completed" and a["progress_max"]!=null and a["progress_current"]!=a["progress_max"]:
		return fail("Objective progress incomplete.")
	var participants: Array = []
	for participant in a["participants"]:
		if not DTO.exact_keys(participant,["actor_id","role"]) or not DTO.id_valid(participant["actor_id"]) or not DTO.bounded_text(participant["role"],80) or participants.any(func(p): return p["actor_id"]==participant["actor_id"] and p["role"]==participant["role"]):
			return fail("Invalid participant.")
		var known = read(state,[SQL.stmt("SELECT a.id,a.kind,a.payload,i.visibility FROM actors a LEFT JOIN actor_instances i ON i.actor_id=a.id WHERE a.id=?",[participant["actor_id"]])])
		if not known.get("ok",false) or known["sets"][0].size()!=1:
			return fail("Story participant unavailable.")
		if a["visibility"]=="player":
			var actor = known["sets"][0][0]
			var data = JSON.parse_string(actor["payload"])
			if actor["kind"]!="player" and actor["visibility"]!="player":
				# Original opening NPCs use a committed source link, not public flag.
				var linked = read(state,[SQL.stmt("SELECT e.payload FROM world_links w JOIN events e ON e.id=w.source_event_id WHERE w.actor_id=? AND e.kind='narration' LIMIT 16",[participant["actor_id"]])])
				var disclosed = false
				if linked.get("ok",false) and data is Dictionary and data.get("descriptive_only")==true:
					for row in linked["sets"][0]:
						var e = JSON.parse_string(row["payload"])
						if e is Dictionary and e.get("text") is String and e["text"].contains(str(data.get("name",""))+" — "+str(data.get("occupation",""))) and (e.get("phase")=="opening" or (e.get("b4_reconciled")==true and data.get("public")==true)):
							disclosed=true
				if not disclosed:
					return fail("Participant disclosure unavailable.")
		participants.append(participant.duplicate(true))
	var rid = request["request_id"]
	var commands: Array = []
	if old.is_empty():
		commands.append(SQL.stmt("INSERT INTO story_records(id,kind,identity_key,title,description,status,visibility,certainty,location_id,parent_id,source_event_id,updated_event_id,progress_current,progress_max) VALUES(?,?,?,?,?,?,?,?,?,?,?,"+EVENT+",?,?)",[record_id,a["kind"],a["identity_key"],a["title"],a["description"],a["status"],a["visibility"],a["certainty"],a["location_id"],a["parent_id"],int(a["source_event_id"]),rid,a["progress_current"],a["progress_max"]]))
	else:
		commands.append(SQL.stmt("UPDATE story_records SET title=?,description=?,status=?,location_id=?,updated_event_id="+EVENT+",progress_current=?,progress_max=? WHERE id=?",[a["title"],a["description"],a["status"],a["location_id"],rid,a["progress_current"],a["progress_max"],record_id]))
	# Retain all prior states/participants in immutable history; current
	# participant set is a reviewed snapshot, not an irreversible overwrite.
	commands.append(SQL.stmt("DELETE FROM story_participants WHERE record_id=?",[record_id]))
	for participant in participants:
		commands.append(SQL.stmt("INSERT INTO story_participants(record_id,actor_id,role) VALUES(?,?,?)",[record_id,participant["actor_id"],participant["role"]]))
	commands.append(SQL.stmt("INSERT INTO story_history(record_id,event_id,request_id,snapshot) VALUES(?,"+EVENT+",?,?)",[record_id,rid,rid,JSON.stringify(a)]))
	if a["kind"]=="quest":
		# Keep B4 legacy quest projection compatible without overwriting an
		# unrelated established quest ID. C2 story record is the stable identity.
		var quest_payload = {"title":a["title"],"public":a["visibility"]=="player","public_description":a["description"] if a["visibility"]=="player" else "","story_record_id":record_id}
		if old.is_empty():
			commands.append(SQL.stmt("INSERT INTO quests(id,status,payload) VALUES(?,?,?)",[record_id,a["status"],JSON.stringify(quest_payload)]))
		else:
			commands.append(SQL.stmt("UPDATE quests SET status=?,payload=? WHERE id=?",[a["status"],JSON.stringify(quest_payload),record_id]))
		if a["location_id"]!=null:
			commands.append(SQL.stmt("INSERT INTO world_links(id,location_id,quest_id,source_event_id) VALUES(?,?,?,"+EVENT+")",[make_id(),a["location_id"],record_id,rid]))
	return _commit(ctx,commands,{"record_id":record_id},"Story record updated: "+a["title"]+".",a["visibility"])
