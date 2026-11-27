extends RefCounted
## C2 same-transaction projection helper. No campaign-store or turn-store
## dependency, so the existing gameplay_view can include it without a cycle.
const SQL = preload("res://systems/sqlite.gd")
const DTO = preload("res://world/world_dto.gd")
const ITEMS = preload("res://persistence/item_catalog.gd")
const UI = preload("res://gameplay/ui_intents.gd")
const RAW = preload("res://turns/raw_mechanics.gd")
const CAT = preload("res://rules/catalog.gd")
const DISPLAY = preload("res://gameplay/display_values.gd")
const MAX_ROWS = 512
const VISIBLE_LOCATION = "EXISTS(SELECT 1 FROM world_discovery d WHERE d.location_id=l.id AND d.visibility='player' AND d.status<>'unknown')"
const INSTANCE_SELECT = "SELECT i.*,d.origin,d.catalog_category,d.catalog_id,d.catalog_revision,d.name,d.unit_weight_lb,d.attributes,d.source_event_id AS definition_source_event_id FROM item_instances i JOIN item_definitions d ON d.id=i.definition_id"
const PUBLIC_STORY = "s.visibility='player' AND (s.location_id IS NULL OR EXISTS(SELECT 1 FROM world_discovery d WHERE d.location_id=s.location_id AND d.visibility='player' AND d.status<>'unknown')) AND (s.parent_id IS NULL OR EXISTS(SELECT 1 FROM story_records p WHERE p.id=s.parent_id AND p.visibility='player'))"
const ACTOR_SELECT = "SELECT a.id,a.kind,a.catalog_id,a.location_id,a.payload,i.visibility,i.sheet_visibility,i.sheet,i.source_event_id FROM actors a LEFT JOIN actor_instances i ON i.actor_id=a.id"
const WARNING = "C3 deterministic eligibility and action timing not connected."
const DENOMS = ["cp","sp","ep","gp","pp"]

# The caller appends these statements before COMMIT of the EXISTING gameplay
# read transaction. No second state query, no optimistic or placeholder state.
func commands(campaign_id: String,actor_id: String,location_id: String) -> Array:
	return [
		SQL.stmt("SELECT value FROM meta WHERE key='gameplay_schema'"),
		SQL.stmt("SELECT campaign_id,revision,turn_number,pending_turn_id,elapsed_seconds FROM world_state WHERE campaign_id=?",[campaign_id]),
		SQL.stmt(INSTANCE_SELECT+" WHERE i.actor_id=? ORDER BY i.id LIMIT ?",[actor_id,MAX_ROWS+1]),
		SQL.stmt("SELECT slot,instance_id,grip FROM equipment_assignments WHERE actor_id=? ORDER BY slot",[actor_id]),
		SQL.stmt("SELECT instance_id,reason FROM equipment_review WHERE actor_id=? ORDER BY instance_id",[actor_id]),
		SQL.stmt("SELECT request_id,status,logical_turn_id,settled_revision FROM gameplay_requests WHERE actor_id=? ORDER BY rowid DESC LIMIT 1",[actor_id]),
		SQL.stmt("SELECT request_id,logical_turn_id FROM gameplay_requests WHERE actor_id=? AND status='accepted_pending' LIMIT 2",[actor_id]),
		SQL.stmt("SELECT s.* FROM story_records s WHERE "+PUBLIC_STORY+" ORDER BY s.updated_event_id DESC,s.id LIMIT ?",[MAX_ROWS+1]),
		SQL.stmt("SELECT q.id,q.status,q.payload,w.location_id,e.id AS source_event_id,e.kind AS source_kind,e.payload AS evidence FROM quests q JOIN world_links w ON w.quest_id=q.id JOIN events e ON e.id=w.source_event_id JOIN locations l ON l.id=w.location_id WHERE NOT EXISTS(SELECT 1 FROM story_records s WHERE s.id=q.id) AND "+VISIBLE_LOCATION+" ORDER BY q.id,e.id DESC LIMIT ?",[MAX_ROWS+1]),
		SQL.stmt(ACTOR_SELECT+" JOIN party_members p ON p.actor_id=a.id WHERE p.status='member' AND p.visibility='player' AND a.id<>? ORDER BY a.id LIMIT ?",[actor_id,MAX_ROWS+1]),
		SQL.stmt(ACTOR_SELECT+" JOIN locations l ON l.id=a.location_id WHERE a.kind IN ('npc','enemy') AND a.location_id=? AND "+VISIBLE_LOCATION+" AND (i.visibility='player' OR i.actor_id IS NULL) ORDER BY a.id LIMIT ?",[location_id,MAX_ROWS+1]),
		SQL.stmt("SELECT w.actor_id,e.id AS source_event_id,e.payload FROM world_links w JOIN events e ON e.id=w.source_event_id WHERE w.location_id=? AND w.actor_id IS NOT NULL AND e.kind='narration' ORDER BY w.actor_id,e.id DESC LIMIT ?",[location_id,MAX_ROWS+1]),
		SQL.stmt("SELECT id,location_id,source_kind,source_event_id,name,status FROM loot_containers WHERE location_id=? AND visibility='player' AND status='available' ORDER BY id LIMIT ?",[location_id,MAX_ROWS+1]),
		SQL.stmt(INSTANCE_SELECT+" JOIN loot_containers c ON c.id=i.container_id WHERE c.location_id=? AND c.visibility='player' AND c.status='available' ORDER BY i.container_id,i.id LIMIT ?",[location_id,MAX_ROWS+1]),
		SQL.stmt("SELECT m.container_id,m.denomination,m.quantity FROM loot_currency m JOIN loot_containers c ON c.id=m.container_id WHERE c.location_id=? AND c.visibility='player' AND c.status='available' ORDER BY m.container_id,m.denomination LIMIT ?",[location_id,MAX_ROWS*5+1]),
		SQL.stmt("SELECT e.id,e.turn,e.kind,e.payload,r.payload AS receipt FROM events e LEFT JOIN turn_receipts r ON r.event_id=e.id WHERE e.kind IN ('campaign_created','narration','mechanical_receipt','gameplay_change') ORDER BY e.id"),
		SQL.stmt("SELECT p.record_id,p.actor_id,p.role FROM story_participants p JOIN story_records s ON s.id=p.record_id WHERE "+PUBLIC_STORY+" ORDER BY p.record_id,p.actor_id LIMIT ?",[MAX_ROWS*4+1])
	]

func text_of_definition(row: Dictionary,attrs: Dictionary) -> String:
	if row["origin"]=="custom":
		return str(attrs.get("description","Custom definition; mechanical effects not yet supported."))
	if row["origin"]=="legacy_unresolved":
		return "Unresolved legacy definition. No mechanical values inferred."
	var parts: PackedStringArray = []
	for key in ["desc","equipment_category","weapon_category","armor_category","armor_class","damage","properties","range","cost","rarity"]:
		if attrs.has(key) and attrs[key]!=null:
			parts.append(key.replace("_"," ").capitalize()+": "+CAT.new().human(attrs[key]))
	return "\n".join(parts).left(4000)

func instance_view(row: Dictionary) -> Dictionary:
	var attrs = JSON.parse_string(row["attributes"])
	var qty = DTO.sql_int(row["quantity"])
	var charge = DTO.sql_int(row["charges"])
	var weight = DTO.sql_number(row["unit_weight_lb"])
	if not attrs is Dictionary or not DTO.id_valid(row["id"]) or qty==null or qty<1 or (row["charges"]!=null and charge==null) or (row["unit_weight_lb"]!=null and weight==null):
		return {}
	return {"instance_id":row["id"],"definition_id":row["definition_id"],"name":row["name"],"description":text_of_definition(row,attrs),"quantity":qty,"unit_weight_lb":weight,"charges":charge,"condition":row["condition"],"attunement_status":row["attunement"],"origin":row["origin"],"source_event_id":DTO.sql_int(row["source_event_id"]),"equip_options":[]}

func story_view(row: Dictionary) -> Dictionary:
	return {"id":row["id"],"kind":row["kind"],"title":row["title"],"description":row["description"],"status":row["status"],"certainty":row["certainty"],"location_id":row["location_id"],"parent_id":row["parent_id"],"source_event_id":DTO.sql_int(row["source_event_id"]),"updated_event_id":DTO.sql_int(row["updated_event_id"]),"progress_current":DTO.sql_int(row["progress_current"]),"progress_max":DTO.sql_int(row["progress_max"]),"participants":[]}

func public_actor(row: Dictionary,disclosures: Array) -> Dictionary:
	var data = JSON.parse_string(row["payload"])
	if not data is Dictionary or not DTO.bounded_text(data.get("name"),100) or not DTO.id_valid(row["id"]):
		return {}
	var source_id = DTO.sql_int(row["source_event_id"])
	if row["visibility"]!="player":
		# Original B4 descriptive NPCs are public only via committed opening
		# or B4 disclosure, not simply because they share a location.
		if row["visibility"]!=null or data.get("descriptive_only")!=true or not DTO.bounded_text(data.get("occupation"),100):
			return {}
		for link in disclosures:
			if link["actor_id"]!=row["id"]:
				continue
			var event = JSON.parse_string(link["payload"])
			if event is Dictionary and event.get("text") is String and event["text"].contains(data["name"]) and event["text"].contains(data["occupation"]) and (event.get("phase")=="opening" or (event.get("b4_reconciled")==true and data.get("public")==true)):
				source_id=DTO.sql_int(link["source_event_id"])
				break
		if source_id==null:
			return {}
	var sheet: Variant = null
	if row["sheet_visibility"]=="public":
		var parsed = JSON.parse_string(str(row["sheet"]))
		if parsed is Dictionary and parsed.get("stat_block") is Dictionary:
			sheet=parsed.duplicate(true)
			# Current authoritative actor HP/resources, not frozen template HP.
			sheet["combat"]=data.get("combat")
	return {"actor_id":row["id"],"kind":row["kind"],"name":data["name"],"occupation":str(data.get("occupation","")),"location_id":row["location_id"],"source_event_id":source_id,"sheet":sheet,"sheet_status":"disclosed" if sheet!=null else ("descriptive_only" if data.get("descriptive_only")==true else "not_disclosed")}

func spell_offers(actor: Dictionary) -> Dictionary:
	var casting: Dictionary = actor.get("spellcasting",{})
	var slots: Dictionary = casting.get("slots",{})
	var cat = CAT.new()
	var casts: Array = []
	var preparation: Array = []
	var seen: Array = []
	for pair in [["cantrip_ids","class_cantrip"],["racial_cantrip_ids","racial_cantrip"],["known_ids","known"],["prepared_ids","prepared"],["always_prepared_ids","always_prepared"]]:
		for spell_id in casting.get(pair[0],[]):
			var rec = cat.get_record("spells",str(spell_id))
			var level = rec.get("level")
			if not DTO.whole(level,0,9):
				continue
			var levels: Array = [0] if level==0 else []
			if level>0:
				for slot_level in range(int(level),10):
					var slot = slots.get(str(slot_level),{})
					if slot is Dictionary and DTO.whole(slot.get("maximum"),1):
						levels.append(slot_level)
			for slot_level in levels:
				var key = str(spell_id)+":"+pair[1]+":"+str(slot_level)
				if key in seen:
					continue
				seen.append(key)
				casts.append({"spell_id":spell_id,"source":pair[1],"slot_level":slot_level,"available":false,"warning":WARNING})
	# Explicitly owned prepared options; C3 owns additional class-list eligibility.
	for spell_id in casting.get("prepared_ids",[]):
		if not preparation.any(func(p): return p["spell_id"]==spell_id):
			preparation.append({"spell_id":spell_id,"kind":"spell_unprepare","available":false,"warning":WARNING})
	for spell_id in casting.get("known_ids",[]):
		if not spell_id in casting.get("prepared_ids",[]) and not preparation.any(func(p): return p["spell_id"]==spell_id):
			preparation.append({"spell_id":spell_id,"kind":"spell_prepare","available":false,"warning":WARNING})
	return {"spell_options":casts,"preparation_options":preparation}

func committed_events(rows: Array) -> Array:
	var output: Array = []
	for row in rows:
		var data = JSON.parse_string(row["payload"])
		var event_id = DTO.sql_int(row["id"])
		var turn = DTO.sql_int(row["turn"])
		if not data is Dictionary or data.get("visibility","player")!="player" or event_id==null or turn==null:
			continue
		var kind = row["kind"]
		if kind=="mechanical_receipt":
			var receipt = JSON.parse_string(str(row["receipt"]))
			if not RAW.stored_receipt_usable(receipt) or receipt["turn_id"]!=data.get("turn_id") or receipt["resulting_turn"]!=turn:
				continue
			if DTO.bounded_text(data.get("player_text"),2000):
				output.append({"id":event_id,"subsequence":0,"turn":turn,"kind":"player_action","text":data["player_text"]})
			var action = receipt["results"][0]
			var text = ""
			if action["kind"] in ["ability_check","saving_throw"]:
				text=action["kind"].replace("_"," ").capitalize()+" — "+str(action["outcome"]).replace("_"," ")+"."
				if not receipt["rolls"].is_empty():
					var roll = receipt["rolls"][0]
					text+=" Total: "+str(roll["total"])+"."
			else:
				text=RAW.summary(receipt)
			output.append({"id":event_id,"subsequence":1,"turn":turn,"kind":"mechanical_summary","text":text})
		elif DTO.bounded_text(data.get("text"),12000):
			if kind=="narration" and DTO.id_valid(data.get("standalone_request_id")) and DTO.bounded_text(data.get("player_text"),2000):
				output.append({"id":event_id,"subsequence":0,"turn":turn,"kind":"player_action","text":data["player_text"]})
			output.append({"id":event_id,"subsequence":1 if kind=="narration" and data.has("standalone_request_id") else 0,"turn":turn,"kind":"mechanical_summary" if kind=="gameplay_change" else kind,"text":data["text"]})
	return output

func project(snapshot: Dictionary,sets: Array) -> Dictionary:
	if sets.size()!=17 or sets[0].size()!=1 or sets[0][0]["value"]!="1" or sets[1].size()!=1:
		return {}
	var state: Dictionary = sets[1][0]
	var cid = snapshot["campaign"]["id"]
	var aid = snapshot["actor"]["id"]
	var revision = DTO.sql_int(state["revision"])
	if state["campaign_id"]!=cid or revision==null or DTO.sql_int(state["turn_number"])!=snapshot["campaign"].get("turn") or sets[6].size()>1:
		return {}
	for index in [2,7,8,9,10,11,12,13]:
		if sets[index].size()>MAX_ROWS:
			return {} # No silently truncated authoritative view.
	if sets[14].size()>MAX_ROWS*5 or sets[16].size()>MAX_ROWS*4:
		return {}
	var instances: Array = []
	var owned: Dictionary = {}
	var defs: Dictionary = {}
	var aggregate: Dictionary = {}
	for row in sets[2]:
		var item = instance_view(row)
		if item.is_empty() or owned.has(item["instance_id"]):
			return {}
		owned[item["instance_id"]]=item
		instances.append(item)
		var attrs = JSON.parse_string(row["attributes"])
		defs[item["instance_id"]]={"id":row["definition_id"],"origin":row["origin"],"catalog_category":row["catalog_category"],"attributes":attrs}
		aggregate[row["definition_id"]]=int(aggregate.get(row["definition_id"],0))+item["quantity"]
	if aggregate.size()!=snapshot["inventory"].size():
		return {}
	for item in snapshot["inventory"]:
		if aggregate.get(item["item_id"])!=item["quantity"]:
			return {}
	var slots: Dictionary = {}
	for slot in UI.SLOTS:
		slots[slot]=null
	for row in sets[3]:
		if not row["slot"] in UI.SLOTS or slots[row["slot"]]!=null or not owned.has(row["instance_id"]):
			return {}
		slots[row["slot"]]=row["instance_id"]
	var reviews: Array = []
	for row in sets[4]:
		if not owned.has(row["instance_id"]):
			return {}
		reviews.append(row)
	var catalogue = ITEMS.new()
	for item in instances:
		for option in catalogue.physical_options(defs[item["instance_id"]]):
			var displaced: Array = []
			var relevant = [option["slot"]]
			if option["grip"]=="two_handed":
				relevant=["main_hand","off_hand","shield"]
			elif option["slot"]=="off_hand":
				relevant.append("shield")
			elif option["slot"]=="shield":
				relevant.append("off_hand")
			for slot in relevant:
				var other = slots[slot]
				if other!=null and other!=item["instance_id"] and not other in displaced:
					displaced.append(other)
			item["equip_options"].append({"slot":option["slot"],"grip":option["grip"],"available":false,"warning":WARNING,"replace_instance_ids":displaced})
	var stories: Array = []
	var quests: Array = []
	var story_map: Dictionary = {}
	for row in sets[7]:
		var item = story_view(row)
		stories.append(item)
		story_map[item["id"]]=item
		if item["kind"]=="quest":
			quests.append({"id":item["id"],"title":item["title"],"description":item["description"],"status":item["status"],"source_event_id":item["source_event_id"]})
	for participant in sets[16]:
		if story_map.has(participant["record_id"]):
			story_map[participant["record_id"]]["participants"].append({"actor_id":participant["actor_id"],"role":participant["role"]})
	var quest_ids: Array = []
	for quest in quests:
		quest_ids.append(quest["id"])
	for row in sets[8]:
		if row["id"] in quest_ids:
			continue
		var data = JSON.parse_string(row["payload"])
		var evidence = JSON.parse_string(row["evidence"])
		if not data is Dictionary or data.get("public")!=true or not evidence is Dictionary or evidence.get("visibility","player")!="player" or not evidence.get("text") is String or not row["source_kind"] in ["narration","gameplay_change"]:
			continue
		var title = data.get("title",data.get("name"))
		if not DTO.bounded_text(title,120) or not evidence["text"].contains(title):
			continue
		var desc = data.get("public_description","")
		if not desc is String or not evidence["text"].contains(desc):
			desc=""
		quest_ids.append(row["id"])
		quests.append({"id":row["id"],"title":title,"description":desc,"status":str(row["status"]),"source_event_id":DTO.sql_int(row["source_event_id"])})
	var actors: Array = []
	for row in sets[10]:
		var individual = public_actor(row,sets[11])
		if not individual.is_empty():
			actors.append(individual)
	var party: Array = []
	for row in sets[9]:
		var data = JSON.parse_string(row["payload"])
		if not data is Dictionary or not DTO.bounded_text(data.get("name"),100):
			continue
		var combat = data.get("combat",{})
		if not combat is Dictionary:
			combat={}
		party.append({"actor_id":row["id"],"name":data["name"],"portrait":str(data.get("portrait","")),"level":data.get("level") if DTO.whole(data.get("level")) else null,"hp_current":combat.get("hp_current") if DTO.whole(combat.get("hp_current")) else null,"hp_max":combat.get("hp_max") if DTO.whole(combat.get("hp_max")) else null})
	var loot: Array = []
	var containers: Dictionary = {}
	for row in sets[12]:
		var container = {"container_id":row["id"],"location_id":row["location_id"],"source_kind":row["source_kind"],"source_event_id":DTO.sql_int(row["source_event_id"]),"name":row["name"],"status":row["status"],"items":[],"coins":{}}
		containers[row["id"]]=container
		loot.append(container)
	for row in sets[13]:
		if not containers.has(row["container_id"]):
			return {}
		var item = instance_view(row)
		if item.is_empty():
			return {}
		containers[row["container_id"]]["items"].append(item)
	for row in sets[14]:
		if not containers.has(row["container_id"]) or not row["denomination"] in DENOMS:
			return {}
		var amount = DTO.sql_int(row["quantity"])
		if amount==null:
			return {}
		containers[row["container_id"]]["coins"][row["denomination"]]=amount
	for container in loot:
		if container["coins"].size()!=DENOMS.size():
			return {}
	var recent = committed_events(sets[15])
	var phase = "idle"
	var active = state["pending_turn_id"]
	if active!=null:
		phase="retryable"
	if not sets[6].is_empty():
		active=sets[6][0]["logical_turn_id"]
		phase="retryable" if state["pending_turn_id"]!=null else "blocked"
	var settled: Dictionary = {} if sets[5].is_empty() else sets[5][0]
	var spell = spell_offers(snapshot["actor"])
	var packet = {"schema_version":"1","campaign_id":cid,"actor_id":aid,"revision":revision,"phase":phase,"pending_turn_id":state["pending_turn_id"],"active_turn_id":active,"supported_intents":[],"status_text":WARNING,"settled_request_id":settled.get("request_id"),"settled_status":settled.get("status"),"inventory_instances":instances,"slot_assignments":slots,"spell_options":spell["spell_options"],"preparation_options":spell["preparation_options"],"public_quests":quests,"party_members":party,"party_candidates":[]}
	# Do not pretend ambiguous legacy hands are established empty. C4 can
	# inspect instances and explicit unresolved review rows using the extension.
	var gear: Dictionary = snapshot["actor"].get("equipment",{})
	var armor = owned[slots["body"]]["definition_id"] if slots["body"]!=null else ""
	var shield = owned[slots["shield"]]["definition_id"] if slots["shield"]!=null else ""
	var weapon_ids: Array = []
	for hand in ["main_hand","off_hand"]:
		if slots[hand]!=null and defs[slots[hand]]["attributes"].has("weapon_category") and not owned[slots[hand]]["definition_id"] in weapon_ids:
			weapon_ids.append(owned[slots[hand]]["definition_id"])
	var legacy_weapons: Array = gear.get("weapon_ids",[]).duplicate()
	weapon_ids.sort()
	legacy_weapons.sort()
	var mirror_matches = armor==gear.get("armor_id","") and shield==gear.get("shield_id","") and weapon_ids==legacy_weapons
	var compatible = reviews.is_empty() and mirror_matches and UI.valid_view(packet,cid,aid)
	var extension = {"schema_version":"2","campaign_id":cid,"actor_id":aid,"revision":revision,"phase":phase,"pending_turn_id":state["pending_turn_id"],"active_turn_id":active,"settled_request_id":settled.get("request_id"),"settled_status":settled.get("status"),"inventory_instances":instances,"known_slot_assignments":sets[3],"equipment_review":reviews,"legacy_equipment_mirror_matches":mirror_matches,"public_quests":quests,"public_actors":actors,"loot_containers":loot,"story_records":stories,"supported_intents":[]}
	# Weight from actual instance definitions, including custom weights; unknown
	# remains partial. Never let a legacy catalogue fallback overwrite it.
	var weight = 0.0
	var missing: Array = []
	for item in instances:
		if item["unit_weight_lb"]==null:
			missing.append(item["definition_id"])
		else:
			weight+=float(item["unit_weight_lb"])*item["quantity"]
	var coins = snapshot["actor"].get("coins",{})
	for denom in DENOMS:
		if coins is Dictionary and DTO.whole(coins.get(denom)):
			weight+=float(coins[denom])/50.0
		else:
			missing.append("coin "+denom)
	return {"interaction":packet if compatible else null,"interaction_extension":extension,"events":recent,"weight_projection":{"known_lb":weight,"complete":missing.is_empty(),"missing":missing}}
