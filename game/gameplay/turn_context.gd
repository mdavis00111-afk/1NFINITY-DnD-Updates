extends RefCounted
## v0.0.27 bounded, read-only context. No AI requests, no mechanical authority.
const SQL=preload("res://systems/sqlite.gd")
const DTO=preload("res://world/world_dto.gd")
const CAT=preload("res://rules/catalog.gd")
const PACK=preload("res://turns/agent_packets.gd")
const REG=preload("res://gameplay/tool_registry.gd")
const DIRECT_KINDS="'equip','quick_equip','swap','unequip','attune','unattune','item_use','item_drop','item_transfer','currency_transfer','loot_pickup','loot_take_all','spell_cast','spell_prepare','spell_unprepare','resource_use','rest','object_interact'"
# Only durable narration linked by the existing turn receipt or standalone
# pointer. Administrative discoveries/story updates are not separate moves.
const LINKED="(EXISTS(SELECT 1 FROM turn_narrations n JOIN turn_receipts tr2 ON tr2.turn_id=n.turn_id WHERE n.event_id=e.id AND tr2.actor_id=? AND json_extract(e.payload,'$.turn_id')=n.turn_id) OR EXISTS(SELECT 1 FROM meta m JOIN gameplay_requests q ON q.request_id=json_extract(e.payload,'$.standalone_request_id') WHERE m.key='c5_narration:'||q.request_id AND m.value=CAST(e.id AS TEXT) AND q.actor_id=? AND q.status='committed' AND q.logical_turn_id IS NULL AND q.event_id=json_extract(e.payload,'$.source_event_id'))) "
const PUBLIC="json_valid(e.payload) AND coalesce(json_extract(e.payload,'$.visibility'),'player')='player'"
var cache_key: Array=[]
var cached_memory: Dictionary={}
var cached_catalogue: Dictionary={}
var cached_world: Dictionary={}
var memory_reads=0
var memory_hits=0
var rules_catalogue=CAT.new()

# One revision-checked read of names and IDs. No scene projection, rules
# records, character sheets or campaign memory assembly at this stage.
func interpreter_packet(state: Dictionary,intent: Dictionary,registry) -> Dictionary:
	var location = state["location_id"]
	var actor = state["actor_id"]
	var text = intent["args"].get("text","")
	var rows = registry.session.read(state,[
		SQL.stmt("SELECT l.id,substr(l.name,1,100) AS name FROM locations l JOIN world_discovery d ON d.location_id=l.id WHERE d.visibility='player' AND d.status<>'unknown' ORDER BY l.id=? DESC,instr(lower(?),lower(l.name))>0 DESC,l.id LIMIT 24",[location,text]),
		SQL.stmt("SELECT a.id,substr(json_extract(a.payload,'$.name'),1,100) AS name FROM actors a JOIN world_discovery d ON d.location_id=a.location_id LEFT JOIN actor_instances i ON i.actor_id=a.id WHERE a.location_id=? AND a.kind IN ('npc','enemy') AND d.visibility='player' AND d.status<>'unknown' AND (i.visibility='player' OR (i.actor_id IS NULL AND json_extract(a.payload,'$.descriptive_only')=1 AND EXISTS(SELECT 1 FROM world_links w JOIN events e ON e.id=w.source_event_id WHERE w.actor_id=a.id AND e.kind='narration' AND "+PUBLIC+" AND instr(json_extract(e.payload,'$.text'),json_extract(a.payload,'$.name'))>0 AND instr(json_extract(e.payload,'$.text'),json_extract(a.payload,'$.occupation'))>0 AND (json_extract(e.payload,'$.phase')='opening' OR (json_extract(e.payload,'$.b4_reconciled')=1 AND json_extract(a.payload,'$.public')=1))))) ORDER BY instr(lower(?),lower(json_extract(a.payload,'$.name')))>0 DESC,a.id LIMIT 16",[location,text]),
		SQL.stmt("SELECT i.id AS instance_id,d.id AS definition_id,substr(d.name,1,100) AS name,i.quantity FROM item_instances i JOIN item_definitions d ON d.id=i.definition_id WHERE i.actor_id=? ORDER BY instr(lower(?),lower(d.name))>0 DESC,i.id LIMIT 32",[actor,text]),
		SQL.stmt("SELECT slot,instance_id,grip FROM equipment_assignments WHERE actor_id=? ORDER BY slot",[actor]),
		SQL.stmt("SELECT c.id AS container_id,c.source_event_id,i.id AS instance_id,substr(d.name,1,100) AS name,i.quantity FROM loot_containers c LEFT JOIN item_instances i ON i.container_id=c.id LEFT JOIN item_definitions d ON d.id=i.definition_id WHERE c.location_id=? AND c.visibility='player' AND c.status='available' ORDER BY instr(lower(?),lower(d.name))>0 DESC,c.id,i.id LIMIT 16",[location,text]),
		SQL.stmt("SELECT r.id,substr(r.name,1,100) AS name,r.from_id,r.to_id FROM world_routes r JOIN world_discovery d ON d.route_id=r.id JOIN world_discovery f ON f.location_id=r.from_id JOIN world_discovery t ON t.location_id=r.to_id WHERE ? IN (r.from_id,r.to_id) AND d.visibility='player' AND f.visibility='player' AND t.visibility='player' AND d.status<>'unknown' AND f.status<>'unknown' AND t.status<>'unknown' ORDER BY r.id LIMIT 16",[location]),
		SQL.stmt("SELECT e.id,substr(json_extract(e.payload,'$.text'),1,360) AS text FROM events e WHERE e.kind='narration' AND "+PUBLIC+" AND "+LINKED+" ORDER BY e.id DESC LIMIT 1",[actor,actor])
	])
	if not rows.get("ok",false):
		return {}
	var sets = rows["sets"]
	for index in [2,4]:
		for row in sets[index]:
			row["quantity"]=DTO.sql_int(row["quantity"])
			if row.has("source_event_id"):
				row["source_event_id"]=DTO.sql_int(row["source_event_id"])
	for row in sets[6]:
		row["id"]=DTO.sql_int(row["id"])
	var casting = state["actor"].get("spellcasting",{})
	var spells: Dictionary = {}
	if casting is Dictionary:
		var sources = {"known":"known_ids","prepared":"prepared_ids","always_prepared":"always_prepared_ids","class_cantrip":"cantrip_ids","racial_cantrip":"racial_cantrip_ids"}
		for source in sources:
			var ids = casting.get(sources[source],[])
			if ids is Array and not ids.is_empty():
				spells[source]=ids.slice(0,24)
	return {"intent":intent,"revision":state["revision"],"references":{"location_id":location,"locations":sets[0],"npcs":sets[1],"inventory":sets[2],"slots":sets[3],"local_loot":sets[4],"routes":sets[5],"recent_narration":sets[6],"actor":{"id":actor,"name":state["actor"].get("name",""),"class_id":state["actor"].get("class_id",""),"race_id":state["actor"].get("race_id",""),"spell_ids_by_source":spells}}}

func memory(state: Dictionary,session,excluded_request_id: String="") -> Dictionary:
	if not state.get("ok",false):
		return {"ok":false}
	var key=[state["campaign_id"],state["actor_id"],state["revision"],state["pending_turn_id"],state["metadata"],excluded_request_id]
	if key==cache_key and not cached_memory.is_empty():
		memory_hits+=1
		return cached_memory.duplicate(true)
	memory_reads+=1
	var rows=session.read(state,[
		SQL.stmt("SELECT e.id,e.turn,e.kind,e.payload,r.payload AS receipt_event FROM events e LEFT JOIN turn_narrations n ON n.event_id=e.id LEFT JOIN turn_receipts tr ON tr.turn_id=n.turn_id LEFT JOIN events r ON r.id=tr.event_id WHERE "+PUBLIC+" AND ((e.kind='narration' AND "+LINKED+") OR (e.kind='gameplay_change' AND EXISTS(SELECT 1 FROM gameplay_requests q WHERE q.event_id=e.id AND q.actor_id=? AND q.request_id<>? AND q.status='committed' AND q.kind IN ("+DIRECT_KINDS+") AND NOT EXISTS(SELECT 1 FROM meta m WHERE m.key='c5_narration:'||q.request_id)))) ORDER BY e.id DESC LIMIT 10",[state["actor_id"],state["actor_id"],state["actor_id"],excluded_request_id]),
		SQL.stmt("SELECT e.id,json_extract(e.payload,'$.narrative_recap') AS recap FROM events e WHERE e.kind='narration' AND "+PUBLIC+" AND "+LINKED+" AND json_type(e.payload,'$.narrative_recap')='text' AND length(json_extract(e.payload,'$.narrative_recap')) BETWEEN 1 AND 3000 ORDER BY e.id DESC LIMIT 1",[state["actor_id"],state["actor_id"]])
	])
	if not rows.get("ok",false):
		return {"ok":false}
	var moves: Array=[]
	for row in rows["sets"][0]:
		var value=JSON.parse_string(row["payload"])
		# Standalone and direct events legitimately have no joined receipt.
		var receipt: Variant=null
		if row.get("receipt_event") is String and not row["receipt_event"].is_empty():
			receipt=JSON.parse_string(row["receipt_event"])
		if not value is Dictionary or not DTO.bounded_text(value.get("text"),12000):
			return {"ok":false}
		var original=value.get("player_text",receipt.get("player_text","") if receipt is Dictionary else "")
		var text=str(value["text"])
		moves.push_front({"event_id":DTO.sql_int(row["id"]),"turn":DTO.sql_int(row["turn"]),"kind":row["kind"],"player_text":original if original is String else "","text":text.left(2000),"excerpt":text.length()>2000})
	var recap: Dictionary={}
	if not rows["sets"][1].is_empty():
		var row=rows["sets"][1][0]
		recap={"source_event_id":DTO.sql_int(row["id"]),"text":row["recap"],"authority":"narrative_memory_only"}
	cache_key=key
	cached_memory={"ok":true,"moves":moves,"recap":recap}
	return cached_memory.duplicate(true)

func catalogue(registry) -> Dictionary:
	if cached_catalogue.is_empty():
		var source=registry.catalogue()
		var tools: Array=[]
		for row in source["tools"]:
			if row["mode"]=="query" or row["id"] in ["define_official","define_custom","actor_generate","loot_discover","story_update","party_membership","reconcile_legacy_slots"]:
				continue
			tools.append({"id":row["id"],"arguments":row["arguments"],"purpose":row["purpose"],"rules":row["rules"]})
		cached_catalogue={"schema_version":source["schema_version"],"ruleset":source["ruleset"],"catalog_revision":source["catalog_revision"],"tools":tools,"unsupported":source["unsupported"]}
	return cached_catalogue.duplicate(true)

func world_catalogue(registry) -> Dictionary:
	if cached_world.is_empty():
		var source=registry.catalogue()
		var tools: Array=[]
		for row in source["tools"]:
			if row["id"] in ["define_official","define_custom","actor_generate","loot_discover","story_update"]:
				tools.append({"id":row["id"],"arguments":row["arguments"],"purpose":row["purpose"]})
		cached_world={"schema_version":source["schema_version"],"tools":tools}
	return cached_world.duplicate(true)

# Text hints only choose which references to INCLUDE; never dispatch a command
# or determine mechanics from keywords. Typed resolved kind takes precedence.
func situational(text: String,kind: String,_scene: Dictionary,_extension: Dictionary) -> Dictionary:
	var lower=text.to_lower()
	var travel=kind in ["move","travel"] or ["travel","road","walk","route","journey","ride"].any(func(word): return lower.contains(word))
	var trade=kind in ["item_transfer","currency_transfer","loot_pickup","loot_take_all"] or ["buy","sell","shop","merchant","trade","price","pay","take"].any(func(word): return lower.contains(word))
	var casting=kind in ["spell_cast","spell_prepare","spell_unprepare"] or ["cast","spell","magic"].any(func(word): return lower.contains(word))
	var rest=kind in ["rest","resource_use"] or ["rest","sleep","recover"].any(func(word): return lower.contains(word))
	var combat=kind in ["saving_throw"] or ["fight","attack","combat","strike","defend"].any(func(word): return lower.contains(word))
	return {"travel":travel,"trade":trade,"casting":casting,"rest":rest,"combat":combat,"combat_supported":false}

# Load applicable immutable records in one pinned catalogue read. Keep exact
# interpreter lookup results in their own field, including historical revision.
func rules(packet: Dictionary,kind: String) -> Dictionary:
	var requested: Array = []
	for id in REG.TOOLS.get(kind,[{},"",[]])[2]:
		requested.append(["rule-sections",id])
	var outcome = packet.get("receipt",packet.get("settlement",{}).get("result",{}))
	for ref in outcome.get("rule_refs",[]):
		# Older standalone equipment settlements use section IDs as strings.
		var key: Array = []
		if ref is String and DTO.bounded_text(ref,128):
			key=["rule-sections",ref]
		elif ref is Dictionary and ref.get("category") in CAT.TABLES and DTO.bounded_text(ref.get("id"),128) and ref.get("ruleset")==CAT.RULESET and ref.get("revision")==CAT.REVISION:
			key=[ref["category"],ref["id"]]
		else:
			return {"ok":false}
		if not key in requested:
			requested.append(key)
	var mandatory_count = requested.size()
	var situation = packet["situational_context"]
	var optional: Array = []
	if situation.get("travel",false): optional.append_array(["movement","time"])
	if situation.get("trade",false): optional.append_array(["standard-exchange-rates","wearing-and-wielding-items"])
	if situation.get("casting",false): optional.append("casting-a-spell")
	if situation.get("rest",false): optional.append("resting")
	if situation.get("combat",false): optional.append("damage-and-healing")
	for id in optional:
		var key = ["rule-sections",id]
		if not key in requested:
			requested.append(key)
	var commands: Array = []
	var required: Array = []
	for index in range(requested.size()):
		var key = requested[index]
		var selected: bool = packet["selected_context"].any(func(entry):
			if not entry is Dictionary or not entry.get("query") is Dictionary or not entry.get("result") is Dictionary:
				return false
			var query = entry["query"]
			var result = entry["result"]
			var record = result.get("data")
			return query.get("kind")=="rule_record" and query.get("args")=={"category":key[0],"id":key[1]} and result.get("ok",false) and record is Dictionary and record.get("index")==key[1])
		if not selected:
			commands.append(SQL.stmt("SELECT category,id,payload FROM catalog WHERE category=? AND id=?",key))
			required.append(index<mandatory_count)
	if commands.is_empty():
		return {"ok":true,"records":[]}
	var path = rules_catalogue.database_path()
	if path.is_empty():
		return {"ok":false}
	var result = SQL.run(path,commands,true)
	if not result.get("ok",false) or result["results"].size()!=commands.size():
		return {"ok":false}
	var records: Array = []
	var optional_budget = 10000
	for index in range(commands.size()):
		var rows = result["results"][index]
		var row = rows[0] if rows.size()==1 else {}
		var record = JSON.parse_string(row.get("payload",""))
		if not record is Dictionary or record.get("index")!=row.get("id"):
			if required[index]:
				return {"ok":false}
			continue
		if not required[index]:
			var size = row["payload"].length()
			if size>optional_budget:
				continue
			optional_budget-=size
		records.append({"category":row["category"],"id":row["id"],"record":record})
	return {"ok":true,"records":records}

# Rank existing disclosed memory by current scene, named references, open
# threads and recency. This changes context selection only, not game rules.
func select_story(records: Array,scene: Dictionary,actors: Array,text: String) -> Array:
	var lower=text.to_lower()
	var local=scene.get("location_id")
	var actor_ids=actors.map(func(row): return row.get("actor_id"))
	var scored: Array=[]
	for row in records:
		var score=0
		if row.get("kind") in ["overview","situation"]:
			score+=100
		if local!=null and row.get("location_id")==local:
			score+=30
		if row.get("status") in ["open","active","offered"]:
			score+=15
		var title=str(row.get("title","")).to_lower()
		if title.length()>=3 and lower.contains(title):
			score+=60
		for person in row.get("participants",[]):
			if person.get("actor_id") in actor_ids:
				score+=20
				break
		scored.append({"score":score,"row":row})
	scored.sort_custom(func(x,y): return x["score"]>y["score"] if x["score"]!=y["score"] else int(x["row"].get("updated_event_id",0))>int(y["row"].get("updated_event_id",0)))
	var selected: Array=[]
	var budget=10000
	for entry in scored:
		var row=entry["row"]
		var size=JSON.stringify(row).length()
		if size>budget:
			continue
		selected.append(row)
		budget-=size
		if selected.size()>=24:
			break
	return selected

# Journal entries identify earlier steps. The durable settlement and receipt
# supply their outcomes. Never promote a journal description to a result.
func committed_steps(state: Dictionary,job: Dictionary,registry) -> Dictionary:
	var steps = job.get("completed_steps",[])
	if not steps is Array or steps.size()>4:
		return {"ok":false}
	var output: Array = []
	var seen: Array = [job["tool"]["request_id"]]
	var revision = job["intent"]["expected_revision"]
	for step in steps:
		if not DTO.exact_keys(step,["request_id","kind","args","event_id","revision"]) or not DTO.id_valid(step["request_id"]) or step["request_id"] in seen or not DTO.whole(step["revision"],revision,job["tool"]["expected_revision"]):
			return {"ok":false}
		var settled = registry.session.settlement(state["campaign_id"],step["request_id"])
		if not settled.get("ok",false) or not settled.get("found",false) or settled["status"]!="committed" or settled["event_id"]!=step["event_id"] or settled["revision"]!=step["revision"]:
			return {"ok":false}
		var request = settled["request"]
		if request["actor_id"]!=state["actor_id"] or request["expected_revision"]<revision or request["kind"]!=step["kind"] or not registry.session.typed_equal(request["args"],step["args"]):
			return {"ok":false}
		var source = registry.session.source(state,settled["event_id"])
		if not registry.session.public_source(source):
			return {"ok":false}
		var verified = step.duplicate(true)
		if settled["logical_turn_id"]==null:
			verified["result"]=settled["result"]
		else:
			var stored = registry.resolver.store.receipt_by_id(state["campaign_id"],settled["logical_turn_id"])
			var receipt = stored.get("receipt",{})
			if not stored.get("ok",false) or not stored.get("found",false) or stored.get("narration_event_id")!=settled["event_id"] or not PACK.committed_receipt_usable(receipt) or receipt["prior_revision"]!=request["expected_revision"] or receipt["next_revision"]+1>settled["revision"]:
				return {"ok":false}
			verified["receipt"]=PACK.public_receipt(receipt)
		output.append(verified)
		seen.append(step["request_id"])
		revision=step["revision"]
	return {"ok":true,"outcomes":output}

# The existing narration payload is the inspectable packet. This final
# assembly is read-only and verifies its current and earlier outcomes.
func dm_packet(state: Dictionary,job: Dictionary,payload: Dictionary,registry) -> Dictionary:
	var request = job.get("tool",{})
	var intent = job.get("intent",{})
	var session = registry.session
	if not session.request_valid(request) or not session.request_valid(intent,str(intent.get("schema_version",""))) or request["campaign_id"]!=state["campaign_id"] or request["actor_id"]!=state["actor_id"] or intent["campaign_id"]!=state["campaign_id"] or intent["actor_id"]!=state["actor_id"] or intent["expected_revision"]>request["expected_revision"]:
		return {}
	var settled = session.settlement(state["campaign_id"],request["request_id"])
	if not settled.get("ok",false) or not settled.get("found",false) or not session.same_request(settled["request"],request):
		return {}
	var turn_id = payload.get("turn_id")
	if payload.has("receipt"):
		if settled["status"]!="accepted_pending" or settled["logical_turn_id"]!=turn_id or state["pending_turn_id"]!=turn_id:
			return {}
		var stored = registry.resolver.store.receipt_by_id(state["campaign_id"],turn_id)
		var receipt = stored.get("receipt",{})
		if not stored.get("ok",false) or not stored.get("found",false) or stored.get("narration_event_id")!=null or not PACK.committed_receipt_usable(receipt) or receipt["prior_revision"]!=request["expected_revision"] or receipt["next_revision"]!=state["revision"] or not session.typed_equal(payload["receipt"],PACK.public_receipt(receipt)):
			return {}
	else:
		var outcome = payload.get("settlement",{})
		if settled["status"]!="committed" or settled["logical_turn_id"]!=null or state["pending_turn_id"]!=null or turn_id!=request["request_id"] or settled["revision"]!=state["revision"] or outcome.get("request_id")!=request["request_id"] or outcome.get("event_id")!=settled["event_id"] or outcome.get("revision")!=settled["revision"] or outcome.get("action")!=request["kind"] or not session.typed_equal(outcome.get("result"),settled["result"]):
			return {}
		var source = session.source(state,settled["event_id"])
		if not session.public_source(source) or outcome.get("summary")!=source["data"].get("text",""):
			return {}
	var earlier = committed_steps(state,job,registry)
	var current = session.token(state["campaign_id"])
	if not earlier.get("ok",false) or not current.get("ok",false) or not registry.resolver.store.matching_token(state,current):
		return {}
	var packet = payload.duplicate(true)
	packet["binding"]={"schema_version":"1","campaign_id":state["campaign_id"],"actor_id":state["actor_id"],"intent_request_id":intent["request_id"],"tool_request_id":request["request_id"],"expected_revision":request["expected_revision"],"revision":state["revision"],"turn_id":turn_id}
	packet["player_text"]=intent["args"].get("text",payload.get("player_text",""))
	packet["recent_outcomes"]=earlier["outcomes"]
	# Continuations identify an earlier outcome. Leave the old proposal and
	# uncommitted prose out of the confirmed history.
	var prior = payload.get("prior_outcome",{})
	if not prior.is_empty():
		var linked: Array = earlier["outcomes"].filter(func(step): return step["request_id"]==prior.get("original_request_id") and step["event_id"]==prior.get("original_event_id"))
		if linked.size()!=1:
			return {}
		packet["prior_outcome"]={"original_request_id":linked[0]["request_id"],"original_event_id":linked[0]["event_id"]}
	return packet

# First DM packet carries established facts and explicitly unresolved intent.
func unresolved_packet(state: Dictionary,job: Dictionary,payload: Dictionary,registry) -> Dictionary:
	var intent = job["intent"]
	var session = registry.session
	if state["pending_turn_id"]!=null or job["lookup_revision"]!=state["revision"] or not session.request_valid(intent,"1") or intent["kind"]!="chat" or intent["campaign_id"]!=state["campaign_id"] or intent["actor_id"]!=state["actor_id"] or payload["turn_id"]!=intent["request_id"]:
		return {}
	var prior = session.settlement(state["campaign_id"],intent["request_id"])
	var current = session.token(state["campaign_id"])
	if not prior.get("ok",false) or prior.get("found",false) or not current.get("ok",false) or not registry.resolver.store.matching_token(state,current):
		return {}
	var packet = payload.duplicate(true)
	packet["binding"]={"schema_version":"1","campaign_id":state["campaign_id"],"actor_id":state["actor_id"],"intent_request_id":intent["request_id"],"tool_request_id":null,"expected_revision":state["revision"],"revision":state["revision"],"turn_id":intent["request_id"]}
	packet["lookup_facts"]=job["lookup_facts"]
	packet["unresolved_intent"]=true
	packet["mechanical_catalogue"]=catalogue(registry)["tools"].filter(func(row): return row["id"] in REG.DM_OPERATIONS)
	return packet
