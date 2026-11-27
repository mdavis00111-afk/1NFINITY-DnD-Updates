extends RefCounted
## v0.0.27 bounded, read-only context. No AI requests, no mechanical authority.
const SQL=preload("res://systems/sqlite.gd")
const DTO=preload("res://world/world_dto.gd")
const CAT=preload("res://rules/catalog.gd")
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

func memory(state: Dictionary,session) -> Dictionary:
	if not state.get("ok",false):
		return {"ok":false}
	var key=[state["campaign_id"],state["actor_id"],state["revision"],state["pending_turn_id"],state["metadata"]]
	if key==cache_key and not cached_memory.is_empty():
		memory_hits+=1
		return cached_memory.duplicate(true)
	memory_reads+=1
	var rows=session.read(state,[
		SQL.stmt("SELECT e.id,e.turn,e.kind,e.payload,r.payload AS receipt_event FROM events e LEFT JOIN turn_narrations n ON n.event_id=e.id LEFT JOIN turn_receipts tr ON tr.turn_id=n.turn_id LEFT JOIN events r ON r.id=tr.event_id WHERE "+PUBLIC+" AND ((e.kind='narration' AND "+LINKED+") OR (e.kind='gameplay_change' AND EXISTS(SELECT 1 FROM gameplay_requests q WHERE q.event_id=e.id AND q.actor_id=? AND q.status='committed' AND q.kind IN ("+DIRECT_KINDS+") AND NOT EXISTS(SELECT 1 FROM meta m WHERE m.key='c5_narration:'||q.request_id)))) ORDER BY e.id DESC LIMIT 10",[state["actor_id"],state["actor_id"],state["actor_id"]]),
		SQL.stmt("SELECT e.id,json_extract(e.payload,'$.narrative_recap') AS recap FROM events e WHERE e.kind='narration' AND "+PUBLIC+" AND "+LINKED+" AND json_type(e.payload,'$.narrative_recap')='text' AND length(json_extract(e.payload,'$.narrative_recap')) BETWEEN 1 AND 3000 ORDER BY e.id DESC LIMIT 1",[state["actor_id"],state["actor_id"]])
	])
	if not rows.get("ok",false):
		return {"ok":false}
	var moves: Array=[]
	for row in rows["sets"][0]:
		var value=JSON.parse_string(row["payload"])
		var receipt=JSON.parse_string(str(row["receipt_event"]))
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

func rules(situation: Dictionary,kind: String) -> Array:
	var ids: Array=["ability-checks","using-each-ability","saving-throws"]
	ids.append_array(REG.TOOLS.get(kind,[{},"",[]])[2])
	if situation.get("travel",false): ids.append_array(["movement","time"])
	if situation.get("trade",false): ids.append_array(["standard-exchange-rates","wearing-and-wielding-items"])
	if situation.get("casting",false): ids.append("casting-a-spell")
	if situation.get("rest",false): ids.append("resting")
	if situation.get("combat",false): ids.append("damage-and-healing")
	var output: Array=[]
	var seen: Array=[]
	var budget=10000
	for id in ids:
		if id in seen: continue
		seen.append(id)
		var record=rules_catalogue.get_record("rule-sections",id)
		if record.is_empty(): continue
		var size=JSON.stringify(record).length()
		if size>budget: continue
		budget-=size
		output.append({"id":id,"record":record})
	return output

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
		if row.get("location_id")==local:
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
