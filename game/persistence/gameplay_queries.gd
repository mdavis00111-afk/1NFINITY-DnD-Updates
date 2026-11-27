extends "res://persistence/gameplay_session.gd"
## Versioned bounded tool enquiries for C3/C4/C5. Local scope is NEVER a
## provider-selected flag. No SQL, effect, or unreviewed write tool.
const ITEMS = preload("res://persistence/item_catalog.gd")
const GENERATOR = preload("res://persistence/actor_generation.gd")
const PROJECTION = preload("res://persistence/interaction_projection.gd")
const LIMIT = 64
const QUERY_FIELDS = {
	"rules_search":["category","query"],
	"rule_record":["category","id"],
	"actors":["location_id"],
	"actor_sheet":["actor_id"],
	"actor_template":["template_id"],
	"item_definition":["definition_id"],
	"inventory":["actor_id"],
	"geography":["page"],
	"story":["kind","location_id","participant_id"],
	"story_history":["record_id"],
	"history":["location_id","before_event_id"],
	"overview":[],
	"loot":["container_id"],
	"settlement":["request_id"]
}

func query_valid(value: Variant) -> bool:
	return DTO.exact_keys(value,["schema_version","campaign_id","expected_revision","query_id","kind","args","limit"]) and value["schema_version"]=="2" and DTO.id_valid(value["campaign_id"]) and DTO.id_valid(value["query_id"]) and DTO.whole(value["expected_revision"]) and DTO.whole(value["limit"],1,LIMIT) and value["kind"] is String and QUERY_FIELDS.has(value["kind"]) and DTO.exact_keys(value["args"],QUERY_FIELDS[value["kind"]])

func query_public(id: String,query: Dictionary) -> Dictionary:
	return _query(id,query,false)

# ONLY trusted local engine/C5 packet builder. The caller owns a separate
# disclosure review before any private rows are serialized to a provider.
func query_local(id: String,query: Dictionary) -> Dictionary:
	return _query(id,query,true)

func _query(id: String,query: Dictionary,private_scope: bool) -> Dictionary:
	if not query_valid(query) or query["campaign_id"]!=id:
		return fail("Invalid typed query.")
	var state = token(id)
	if not state.get("ok",false) or state["revision"]!=query["expected_revision"]:
		return fail("Query revision changed or gameplay schema unavailable.")
	var args: Dictionary = query["args"]
	var limit = int(query["limit"])
	var kind = query["kind"]
	var output: Variant = null
	var projection = PROJECTION.new()
	match kind:
		"rules_search":
			if not args["category"] is String or not args["query"] is String:
				return fail("Invalid rules search.")
			var result = ITEMS.new().search(args["category"],args["query"],limit)
			if not result.get("ok",false):
				return result
			output=result
		"rule_record":
			if not args["category"] is String or not args["id"] is String:
				return fail("Invalid rule identity.")
			var record = ITEMS.new().official(args["category"],args["id"])
			if record.is_empty():
				return fail("Pinned rule unavailable.")
			output=record
		"actor_template":
			if not DTO.bounded_text(args["template_id"],100):
				return fail("Invalid actor template identity.")
			var record = GENERATOR.new().template(args["template_id"])
			if record.is_empty():
				return fail("Canonical template unavailable or ambiguous.")
			output=record
		"geography":
			if not DTO.whole(args["page"],0,100000):
				return fail("Invalid map page.")
			var result = WORLD.new().dm_geography(id) if private_scope else WORLD.new().map_view(id,int(args["page"]),limit)
			if not result.get("ok",false) or result.get("revision")!=state["revision"]:
				return fail("Geography revision changed or unavailable.")
			output=result
		"item_definition":
			if not DTO.bounded_text(args["definition_id"],100):
				return fail("Invalid definition ID.")
			var key = args["definition_id"]
			var r = read(state,[SQL.stmt("SELECT d.* FROM item_definitions d WHERE d.id=? AND (?='local' OR d.origin='official' OR EXISTS(SELECT 1 FROM item_instances i WHERE i.definition_id=d.id AND (i.actor_id=? OR i.container_id IN (SELECT id FROM loot_containers WHERE location_id=? AND visibility='player' AND status='available'))))",[key,"local" if private_scope else "public",state["actor_id"],state["location_id"]])])
			if not r.get("ok",false):
				return r
			if r["sets"][0].size()==1:
				output=ITEMS.new().from_row(r["sets"][0][0])
			elif not key.begins_with("custom-"):
				output=ITEMS.new().official_definition(key.trim_prefix("magic:"),"magic-items" if key.begins_with("magic:") else "equipment")
			if output==null or output.is_empty():
				return fail("Definition unavailable.")
		"inventory":
			if not DTO.id_valid(args["actor_id"]) or (not private_scope and args["actor_id"]!=state["actor_id"]):
				return fail("Inventory not disclosed.")
			var r = read(state,[SQL.stmt("SELECT id,payload FROM actors WHERE id=?",[args["actor_id"]]),SQL.stmt(PROJECTION.INSTANCE_SELECT+" WHERE i.actor_id=? ORDER BY i.id LIMIT ?",[args["actor_id"],limit+1]),SQL.stmt("SELECT slot,instance_id,grip FROM equipment_assignments WHERE actor_id=? ORDER BY slot",[args["actor_id"]]),SQL.stmt("SELECT instance_id,reason FROM equipment_review WHERE actor_id=? ORDER BY instance_id",[args["actor_id"]])])
			if not r.get("ok",false) or r["sets"][0].size()!=1:
				return fail("Actor inventory unavailable.")
			var data = JSON.parse_string(r["sets"][0][0]["payload"])
			if not data is Dictionary:
				return fail("Actor payload unavailable.")
			var items: Array = []
			for row in r["sets"][1].slice(0,limit):
				var item = projection.instance_view(row)
				if item.is_empty():
					return fail("Invalid instance record.")
				items.append(item)
			var included: Array = []
			for item in items:
				included.append(item["instance_id"])
			var slots: Array = []
			for row in r["sets"][2]:
				if row["instance_id"] in included:
					slots.append(row)
			var reviews: Array = []
			for row in r["sets"][3]:
				if row["instance_id"] in included:
					reviews.append(row)
			output={"actor_id":args["actor_id"],"items":items,"coins":data.get("coins"),"known_slot_assignments":slots,"equipment_review":reviews,"truncated":r["sets"][1].size()>limit}
		"actors","actor_sheet":
			var target = args.get("actor_id") if kind=="actor_sheet" else args.get("location_id")
			if not DTO.id_valid(target):
				return fail("Invalid actor/location identity.")
			var filter = "a.id=?" if kind=="actor_sheet" else "a.location_id=? AND a.kind IN ('npc','enemy')"
			var condition = "" if private_scope else " AND (a.id=? OR ((i.visibility='player' OR i.actor_id IS NULL) AND EXISTS(SELECT 1 FROM world_discovery d WHERE d.location_id=a.location_id AND d.visibility='player' AND d.status<>'unknown')))"
			var params = [target] if private_scope else [target,state["actor_id"]]
			var r = read(state,[SQL.stmt(PROJECTION.ACTOR_SELECT+" WHERE "+filter+condition+" ORDER BY a.id LIMIT ?",params+[limit+1]),SQL.stmt("SELECT w.actor_id,e.id AS source_event_id,e.payload FROM world_links w JOIN events e ON e.id=w.source_event_id WHERE w.actor_id IS NOT NULL AND e.kind='narration' AND w.actor_id IN (SELECT a.id FROM actors a WHERE "+filter+") ORDER BY w.actor_id,e.id DESC LIMIT ?",[target,LIMIT*8])])
			if not r.get("ok",false):
				return r
			var actors: Array = []
			for row in r["sets"][0].slice(0,limit):
				var payload = JSON.parse_string(row["payload"])
				if not payload is Dictionary:
					return fail("Malformed actor record.")
				if private_scope or row["id"]==state["actor_id"]:
					var sheet = JSON.parse_string(str(row["sheet"])) if row["sheet"]!=null else null
					# Allowlisted structured fields; no portrait paths, master IDs,
					# hidden config, raw arbitrary payload or complete player draft.
					var actor = {"actor_id":row["id"],"kind":row["kind"],"name":payload.get("name"),"occupation":payload.get("occupation"),"location_id":row["location_id"],"template":sheet,"source_event_id":DTO.sql_int(row["source_event_id"])}
					for field in ["ability_scores","ability_modifiers","saving_throws","skills","combat","equipment","resources","spellcasting","coins","alignment","attitude","level","xp","carrying_capacity_lb"]:
						if payload.has(field):
							actor[field]=payload[field]
					actors.append(actor)
				else:
					var visible = projection.public_actor(row,r["sets"][1])
					if not visible.is_empty():
						actors.append(visible)
			if kind=="actor_sheet" and actors.size()!=1:
				return fail("Actor sheet not disclosed or unavailable.")
			output={"actors":actors,"truncated":r["sets"][0].size()>limit}
		"story":
			for key in ["location_id","participant_id"]:
				if args[key]!=null and not DTO.id_valid(args[key]):
					return fail("Invalid story query identity.")
			if args["kind"]!=null and not args["kind"] in ["overview","situation","quest","objective","relationship","animosity","repeat_offender","faction","debt","promise","unresolved_event","circumstance"]:
				return fail("Invalid story kind.")
			var visibility = "1=1" if private_scope else PROJECTION.PUBLIC_STORY
			var r = read(state,[SQL.stmt("SELECT s.*,(SELECT count(*) FROM story_history h WHERE h.record_id=s.id) AS history_count FROM story_records s WHERE "+visibility+" AND (? IS NULL OR s.kind=?) AND (? IS NULL OR s.location_id=? OR s.location_id IS NULL) AND (? IS NULL OR EXISTS(SELECT 1 FROM story_participants p WHERE p.record_id=s.id AND p.actor_id=?)) ORDER BY s.updated_event_id DESC,s.id LIMIT ?",[args["kind"],args["kind"],args["location_id"],args["location_id"],args["participant_id"],args["participant_id"],limit+1])])
			if not r.get("ok",false):
				return r
			var records: Array = []
			for row in r["sets"][0].slice(0,limit):
				var entry = projection.story_view(row)
				entry["history_count"]=DTO.sql_int(row["history_count"])
				var p = read(state,[SQL.stmt("SELECT actor_id,role FROM story_participants WHERE record_id=? ORDER BY actor_id,role LIMIT 33",[row["id"]])])
				if not p.get("ok",false) or p["sets"][0].size()>32:
					return fail("Story participant query incomplete.")
				entry["participants"]=p["sets"][0]
				records.append(entry)
			output={"records":records,"truncated":r["sets"][0].size()>limit}
		"story_history":
			if not DTO.id_valid(args["record_id"]):
				return fail("Invalid story identity.")
			var visibility = "1=1" if private_scope else PROJECTION.PUBLIC_STORY
			var r = read(state,[SQL.stmt("SELECT h.id,h.event_id,h.snapshot FROM story_history h JOIN story_records s ON s.id=h.record_id WHERE h.record_id=? AND "+visibility+" ORDER BY h.id DESC LIMIT ?",[args["record_id"],limit+1])])
			if not r.get("ok",false):
				return r
			var history: Array = []
			for row in r["sets"][0].slice(0,limit):
				var data = JSON.parse_string(row["snapshot"])
				if data is Dictionary and (private_scope or data.get("visibility")=="player"):
					history.append({"event_id":DTO.sql_int(row["event_id"]),"title":data.get("title"),"description":data.get("description"),"status":data.get("status"),"certainty":data.get("certainty"),"progress_current":data.get("progress_current"),"progress_max":data.get("progress_max"),"source_event_id":data.get("source_event_id")})
			output={"history":history,"truncated":r["sets"][0].size()>limit}
		"history":
			if (args["location_id"]!=null and not DTO.id_valid(args["location_id"])) or (args["before_event_id"]!=null and not DTO.whole(args["before_event_id"],1)):
				return fail("Invalid history range.")
			if args["location_id"]!=null and not private_scope:
				var visible = read(state,[SQL.stmt("SELECT 1 FROM world_discovery WHERE location_id=? AND visibility='player' AND status<>'unknown'",[args["location_id"]])])
				if not visible.get("ok",false) or visible["sets"][0].is_empty():
					return fail("History location unavailable.")
			var at = args["location_id"]
			# Source links and location-tagged events are durable, not a rolling
			# chat summary. JSON payload is parsed locally and filtered below.
			var r = read(state,[SQL.stmt("SELECT e.id,e.turn,e.kind,e.payload,r.payload AS receipt FROM events e LEFT JOIN turn_receipts r ON r.event_id=e.id WHERE e.kind IN ('campaign_created','narration','mechanical_receipt','gameplay_change') AND (? IS NULL OR e.id<?) AND (? IS NULL OR instr(e.payload,?)>0 OR e.id IN (SELECT source_event_id FROM world_links WHERE location_id=? UNION SELECT source_event_id FROM world_places WHERE location_id=? UNION SELECT source_event_id FROM story_records WHERE location_id=? UNION SELECT updated_event_id FROM story_records WHERE location_id=?)) ORDER BY e.id DESC LIMIT ?",[args["before_event_id"],args["before_event_id"],at,"\"location_id\":\""+str(at)+"\"",at,at,at,at,limit+1])])
			if not r.get("ok",false):
				return r
			var rows: Array = r["sets"][0].slice(0,limit)
			rows.reverse()
			var history = projection.committed_events(rows)
			if private_scope:
				for row in rows:
					var data = JSON.parse_string(row["payload"])
					if data is Dictionary and data.get("visibility")=="private" and DTO.bounded_text(data.get("text"),4000):
						history.append({"id":DTO.sql_int(row["id"]),"turn":DTO.sql_int(row["turn"]),"kind":"private_event","text":data["text"]})
				history.sort_custom(func(a,b): return a["id"]<b["id"])
			output={"events":history,"truncated":r["sets"][0].size()>limit,"next_before_event_id":DTO.sql_int(rows[0]["id"]) if not rows.is_empty() else null}
		"overview","loot":
			# Use the exact same committed C1/C2 view, not an independently
			# synthesized display model. Revision checked again.
			var snapshot = BASE.new().gameplay_view(id)
			var view = snapshot.get("interaction_extension",{})
			if view.get("revision")!=state["revision"] or view.get("campaign_id")!=id:
				return fail("Committed interaction snapshot unavailable.")
			if kind=="loot":
				if args["container_id"]!=null and not DTO.id_valid(args["container_id"]):
					return fail("Invalid loot container identity.")
				var visible: Array = []
				for row in view["loot_containers"]:
					if args["container_id"]==null or row["container_id"]==args["container_id"]:
						visible.append(row)
				output={"containers":visible.slice(0,limit),"truncated":visible.size()>limit}
			else:
				var overview: Array = []
				for item in view["story_records"]:
					if item["kind"] in ["overview","situation"]:
						overview.append(item)
				output={"title":snapshot["campaign"].get("title"),"current_location":snapshot["location"].get("name"),"overview":overview,"recent_events":snapshot["events"].slice(maxi(0,snapshot["events"].size()-limit)),"quests":view["public_quests"].slice(0,limit),"persistent_factors":view["story_records"].slice(0,limit)}
		"settlement":
			if not DTO.id_valid(args["request_id"]):
				return fail("Invalid settlement identity.")
			var settled = settlement(id,args["request_id"])
			if not settled.get("ok",false):
				return settled
			# Public settlement status only, not private request payload/result.
			output={"found":settled.get("found",false),"status":settled.get("status"),"logical_turn_id":settled.get("logical_turn_id"),"revision":settled.get("revision"),"event_id":settled.get("event_id")}
	if output==null or JSON.stringify(output).length()>100000:
		return fail("Typed query result unavailable or exceeds bounded packet.")
	# Revision can only change via a canonical local write; reject late reads.
	var latest = token(id)
	if not latest.get("ok",false) or not TURN.new().matching_token(state,latest):
		return fail("Query snapshot changed.")
	return {"ok":true,"schema_version":"2","campaign_id":id,"revision":state["revision"],"query_id":query["query_id"],"kind":kind,"scope":"local" if private_scope else "public","data":output}
