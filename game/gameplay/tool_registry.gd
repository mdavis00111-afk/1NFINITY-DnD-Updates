extends RefCounted
## Local C3 registry. Provider receives only catalogue and permitted queries.
const SESSION = preload("res://persistence/gameplay_session.gd")
const NONCOMBAT = preload("res://persistence/noncombat_store.gd")
const LOOT = preload("res://persistence/loot_store.gd")
const ACTORS = preload("res://persistence/actor_generation.gd")
const STORY = preload("res://persistence/story_store.gd")
const EQUIP = preload("res://persistence/equipment_store.gd")
const QUERIES = preload("res://persistence/gameplay_queries.gd")
const DTO = preload("res://world/world_dto.gd")
const RAW = preload("res://turns/raw_mechanics.gd")
const RESOLVER = preload("res://turns/turn_resolver.gd")
const ITEMS = preload("res://persistence/item_catalog.gd")
const CAT = preload("res://rules/catalog.gd")
const SQL = preload("res://systems/sqlite.gd")
const UI = preload("res://gameplay/ui_intents.gd")
const SPELL_SOURCES = ["class_cantrip","racial_cantrip","known","prepared","always_prepared"]
const MATERIAL_AC = {"cloth":11,"paper":11,"rope":11,"crystal":13,"glass":13,"ice":13,"wood":15,"bone":15,"stone":17,"iron":19,"steel":19,"mithral":21,"adamantine":23}
const OBJECT_HP = {"tiny":[2,5],"small":[3,10],"medium":[4,18],"large":[5,27]}
const ADOPTED = ["ability_check","skill_check","saving_throw","object_check","conversation","observe","wait","move","travel"]
# Execution-only outcomes. The interpreter cannot submit these codes.
const MISSING_CUSTOM_ATTRIBUTES = "missing_custom_attributes"
const ITEM_REJECTIONS = ["ineligible","eligibility_unknown","invalid_data","insufficient_resources"]
const EQUIPMENT = ["equip","quick_equip","swap","unequip","attune","unattune"]
const QUERY_TYPES = {"rules_search":{"category":"text","query":"text"},"rule_record":{"category":"text","id":"text"},"actors":{"location_id":"id"},"actor_sheet":{"actor_id":"id"},"actor_template":{"template_id":"text"},"item_definition":{"definition_id":"text"},"inventory":{"actor_id":"id"},"geography":{"page":"integer"},"story":{"kind":"text?","location_id":"id?","participant_id":"id?"},"story_history":{"record_id":"id"},"history":{"location_id":"id?","before_event_id":"positive?"},"overview":{},"loot":{"container_id":"id?"},"settlement":{"request_id":"id"},"object_profile":{"material":"material","size":"object_size","resilience":"resilience"},"equipment_options":{"instance_id":"id"}}
const TOOLS = {"inspect_inscription":[{"instance_id":"id"},"Read the inscription on an explicitly requested owned custom object or gear.",[]],"equip":[{"instance_id":"id","slot":"slot","grip":"grip"},"Equip a selected owned instance in a chosen compatible slot and grip.",["wearing-and-wielding-items","time"]],"quick_equip":[{"instance_id":"id","slot":"slot","grip":"grip"},"Equip an instance in an explicitly chosen compatible slot; never implicitly displace gear.",["wearing-and-wielding-items","time"]],"swap":[{"instance_id":"id","slot":"slot","grip":"grip","replace_instance_ids":"ids"},"Atomically replace exactly the selected displaced instances.",["wearing-and-wielding-items","time"]],"unequip":[{"instance_id":"id","slot":"slot"},"Unequip an actual slot assignment and update derived statistics.",["wearing-and-wielding-items","time"]],"attune":[{"instance_id":"id"},"Attune supported protection item during a focused short rest.",["attunement","resting"]],"unattune":[{"instance_id":"id"},"End supported attunement during a focused short rest.",["attunement","resting"]],"item_use":[{"instance_id":"id","quantity":"positive","target_id":"id?"},"Consume one supported healing potion or daily ration on explicit self target.",["activating-an-item","damage-and-healing"]],"item_drop":[{"instance_id":"id","quantity":"positive"},"Drop an owned unequipped possession into a recoverable local container.",["movement","time"]],"item_transfer":[{"from_actor_id":"id","to_actor_id":"id","instance_id":"id","quantity":"positive"},"Transfer an actual item with consent between player and local NPC.",["movement","time"]],"currency_transfer":[{"from_actor_id":"id","to_actor_id":"id","coins":"coins"},"Transfer explicit coin denominations.",["standard-exchange-rates","movement"]],"loot_pickup":[{"container_id":"id","source_event_id":"positive","items":"selections","coins":"coins"},"Collect selected unclaimed loot and coin amounts.",["movement","standard-exchange-rates"]],"loot_take_all":[{"container_id":"id","source_event_id":"positive"},"Collect every remaining eligible possession or reject atomically.",["movement","standard-exchange-rates"]],"loot_discover":[{"source_event_id":"positive","location_id":"id","name":"text","items":"possessions","coins":"coins"},"Record verified local discovery; no automatic award.",["objects"]],"define_official":[{"category":"text","catalog_id":"text","source_event_id":"positive"},"Register an immutable pinned definition.",[]],"define_custom":[{"definition":"definition","source_event_id":"positive","official_equivalent_id":"text?"},"Validate proposed custom item attributes; prefer actual official equivalent.",["objects"]],"spell_cast":[{"spell_id":"text","source":"spell_source","slot_level":"slot_level","target_id":"id?"},"Resolve supported self-healing spell and debit actual slot.",["casting-a-spell","damage-and-healing"]],"spell_prepare":[{"spell_id":"text","prepared_ids":"texts"},"Choose complete new preparation list after verified long rest.",["casting-a-spell","resting"]],"spell_unprepare":[{"spell_id":"text","prepared_ids":"texts"},"Remove selected spell as part of explicit final prepared list.",["casting-a-spell","resting"]],"resource_use":[{"resource_id":"text","quantity":"positive","target_id":"id?"},"Use supported Second Wind or Lay on Hands resource.",["damage-and-healing"]],"rest":[{"rest_kind":"rest_kind","hit_dice":"integer","prepared_ids":"texts?"},"Resolve supported rest, hit dice, resources and preparation.",["resting","time"]],"ability_check":[{"ability":"ability","skill":"text?","difficulty":"difficulty","text":"text","source_event_id":"positive","circumstances":"circumstances"},"Resolve contextual uncertain task with RAW difficulty category.",["ability-checks","advantage-and-disadvantage"]],"skill_check":[{"ability":"ability","skill_id":"text","difficulty":"difficulty","text":"text","source_event_id":"positive","circumstances":"circumstances"},"Resolve contextual skill/ability check with proficiency.",["ability-checks","using-each-ability"]],"saving_throw":[{"ability":"ability","text":"text","source_event_id":"positive","circumstances":"circumstances"},"Resolve saving throw against independently verified triggering DC.",["saving-throws","advantage-and-disadvantage"]],"object_interact":[{"object_id":"id","operation":"object_operation","source_event_id":"positive"},"Open or close a verified unlocked, unobstructed local mundane object recorded as a circumstance.",["objects","time"]],"object_check":[{"object_id":"id","ability":"ability","skill":"text?","difficulty":"difficulty","text":"text","source_event_id":"positive","circumstances":"circumstances"},"Resolve check concerning established local object, without invented object damage/state.",["objects","ability-checks"]],"conversation":[{"text":"text"},"Ordinary conversation, no roll or implied effect.",["time"]],"observe":[{"text":"text"},"Routine observation without a roll or invented discovery.",["time"]],"wait":[{"seconds":"positive","text":"text"},"Advance a verified safe duration.",["time"]],"move":[{"route_id":"id","destination_id":"id","pace":"pace","fast_travel":"bool","text":"text"},"Resolve movement on canonical cleared foot route.",["movement","time"]],"travel":[{"route_id":"id","destination_id":"id","pace":"pace","fast_travel":"bool","text":"text"},"Resolve ordinary or fast travel using identical RAW pace and route rules.",["movement","time"]],"actor_generate":[{"generation_key":"id","template_ids":"texts","existing_actor_id":"id?","kind":"actor_kind","name":"text?","occupation":"text","location_id":"id","visibility":"visibility","sheet_visibility":"sheet_visibility","source_event_id":"positive","possessions":"actor_possessions","coins":"coins?","attitude":"attitude?"},"Create or reuse a verified canonical NPC/monster instance.",[]],"story_update":[{"record_id":"id?","identity_key":"text","kind":"text","title":"text","description":"text","status":"text","visibility":"visibility","certainty":"text","location_id":"id?","parent_id":"id?","source_event_id":"positive","progress_current":"integer?","progress_max":"positive?","participants":"participants"},"Record source-backed locally approved story/quest lifecycle.",[]],"party_membership":[{"member_actor_id":"id","status":"text","source_event_id":"positive"},"Record actual consent/departure, no combat or teleportation.",[]],"reconcile_legacy_slots":[{"assignments":"assignments"},"Resolve missing existing hand metadata without changing prior equipment.",["wearing-and-wielding-items"]]}
# Explicit supported slice: tool presence is not permission to invent effects.
const CAPABILITIES = {"spell_cast":{"spell_ids":["cure-wounds","healing-word"],"slot_levels":[1],"target":"self","combat":false},"item_use":{"catalog_ids":["potion-of-healing-common","potion-of-healing-greater","potion-of-healing-superior","potion-of-healing-supreme","rations-1-day"],"target":"self"},"attune":{"catalog_ids":["ring-of-protection","cloak-of-protection"]},"unattune":{"catalog_ids":["ring-of-protection","cloak-of-protection"]},"resource_use":{"resource_ids":["second_wind","lay_on_hands"],"target":"self"},"spell_prepare":{"classes":["cleric","druid","wizard"],"requires_verified_long_rest":true},"spell_unprepare":{"classes":["cleric","druid","wizard"],"requires_verified_long_rest":true},"rest":{"actor_level":1,"kinds":["short","long"],"unresolved_conditions":false},"object_interact":{"operations":["open","close"],"requires_established_unlocked_unobstructed_object":true},"travel":{"mode":"known_cleared_foot_route","fast_travel_requires_prior_traversal":true}}
const SCOPES = {"loot_pickup":"loot_transfer","loot_take_all":"loot_transfer","item_drop":"drop_transfer","loot_discover":"eligible_discovery","define_custom":"custom_definition","define_official":"official_definition","actor_generate":"actor_generation","story_update":"story_update","party_membership":"party_membership","reconcile_legacy_slots":"legacy_equipment","object_interact":"object_interaction","item_use":"item_use","item_transfer":"actor_transfer","currency_transfer":"actor_transfer","spell_cast":"spell_cast","spell_prepare":"spell_prepare","spell_unprepare":"spell_prepare","rest":"rest","resource_use":"resource_use"}
var session=SESSION.new()
var noncombat=NONCOMBAT.new()
var resolver=RESOLVER.new()

func error_result(code: String,message: String,details: Dictionary = {}) -> Dictionary:
	return {"ok":false,"code":code,"error":message,"details":details}

func catalogue() -> Dictionary:
	var result: Array=[]
	for kind in QUERY_TYPES:
		result.append({"id":kind,"mode":"query","purpose":"Read verified "+kind.replace("_"," ")+" data without state change.","arguments":QUERY_TYPES[kind],"rules":["objects"] if kind=="object_profile" else [],"result":"bounded revision-tagged data or structured error"})
	for kind in TOOLS:
		result.append({"id":kind,"mode":"adopted_turn" if kind in ADOPTED else "atomic_request","purpose":TOOLS[kind][1],"arguments":TOOLS[kind][0],"rules":TOOLS[kind][2],"result":"committed mechanical receipt and pending narration" if kind in ADOPTED else "durable settlement with verified result, revision and event","requires_local_context":true,"supported_slice":CAPABILITIES.get(kind,{})})
	return {"schema_version":"3","ruleset":CAT.RULESET,"catalog_revision":CAT.REVISION,"tools":result,"unsupported":["combat","attack","damage_object","initiative","level_up","unimplemented_spells","unimplemented_resource_effects"],"validation_codes":["invalid","unsupported","decision_required","stale","busy","review_required","unconfirmed"]}

func typed(value: Variant,spec: String) -> bool:
	if spec.ends_with("?"):
		return value==null or typed(value,spec.trim_suffix("?"))
	match spec:
		"id": return DTO.id_valid(value)
		"text": return DTO.bounded_text(value,2000)
		"positive": return DTO.whole(value,1)
		"integer": return DTO.whole(value)
		"signed": return DTO.whole(value,-DTO.MAX_INT,DTO.MAX_INT)
		"attitude": return DTO.whole(value,-5,5)
		"slot_level": return DTO.whole(value,0,9)
		"bool": return value is bool
		"slot": return value in UI.SLOTS
		"grip": return value in UI.GRIPS
		"ability": return value in RAW.ABILITIES
		"difficulty": return RAW.DIFFICULTY.has(value)
		"pace": return RAW.PACE.has(value)
		"spell_source": return value in SPELL_SOURCES
		"rest_kind": return value in ["short","long"]
		"actor_kind": return value in ["npc","enemy"]
		"visibility": return value in ["player","private"]
		"sheet_visibility": return value in ["public","private"]
		"material": return MATERIAL_AC.has(value)
		"object_size": return OBJECT_HP.has(value)
		"resilience": return value in ["fragile","resilient"]
		"object_operation": return value in ["open","close"]
		"coins": return LOOT.new().coin_map(value)
		"definition": return ITEMS.new().custom_valid(value)
		"array": return value is Array and value.size()<=128
		"actor_possessions","participants","assignments":
			if not value is Array or value.size()>(12 if spec=="assignments" else (32 if spec=="participants" else 64)):
				return false
			for row in value:
				if spec=="actor_possessions":
					if not DTO.exact_keys(row,["definition_id","quantity","equipped_slot","grip"]) or not DTO.bounded_text(row["definition_id"],100) or not DTO.whole(row["quantity"],1) or ((row["equipped_slot"]==null)!=(row["grip"]==null)) or (row["equipped_slot"]!=null and (not row["equipped_slot"] in UI.SLOTS or not row["grip"] in UI.GRIPS)):
						return false
				elif spec=="participants":
					if not DTO.exact_keys(row,["actor_id","role"]) or not DTO.id_valid(row["actor_id"]) or not DTO.bounded_text(row["role"],80):
						return false
				elif not DTO.exact_keys(row,["instance_id","slot","grip"]) or not DTO.id_valid(row["instance_id"]) or not row["slot"] in UI.SLOTS or not row["grip"] in UI.GRIPS:
					return false
			return true
		"ids","texts":
			if not value is Array or value.size()>128:
				return false
			var seen: Array=[]
			for v in value:
				if not typed(v,"id" if spec=="ids" else "text") or v in seen:
					return false
				seen.append(v)
			return true
		"selections","possessions":
			if not value is Array or value.size()>128:
				return false
			var seen: Array=[]
			for item in value:
				if spec=="selections":
					if not DTO.exact_keys(item,["instance_id","quantity"]) or not DTO.id_valid(item["instance_id"]) or not DTO.whole(item["quantity"],1) or item["instance_id"] in seen:
						return false
					seen.append(item["instance_id"])
				elif not DTO.exact_keys(item,["definition_id","quantity","charges","condition","attunement"]) or not DTO.bounded_text(item["definition_id"],100) or not DTO.whole(item["quantity"],1) or (item["charges"]!=null and not DTO.whole(item["charges"])) or not item["condition"] in ["unknown","intact","worn","damaged","broken"] or not item["attunement"] in ["unknown","not_required","unattuned"]:
					return false
			return true
		"circumstances":
			if not value is Array or value.size()>8:
				return false
			for item in value:
				if not DTO.exact_keys(item,["kind","reason","source_event_id"]) or not item["kind"] in ["advantage","disadvantage"] or not DTO.bounded_text(item["reason"],500) or not DTO.whole(item["source_event_id"],1):
					return false
			return true
	return false

func arguments_valid(args: Variant,schema: Dictionary) -> bool:
	if not DTO.exact_keys(args,schema.keys()):
		return false
	for key in schema:
		if not typed(args[key],schema[key]):
			return false
	return true

# Shared provider boundary; mechanical eligibility remains local to execute.
const INTERPRETER_EXCLUDED=["define_official","define_custom","actor_generate","loot_discover","story_update","party_membership","reconcile_legacy_slots"]

func interpreter_action_valid(value: Variant) -> bool:
	return DTO.exact_keys(value,["kind","args"]) and value["kind"] is String and TOOLS.has(value["kind"]) and not value["kind"] in INTERPRETER_EXCLUDED and arguments_valid(value["args"],TOOLS[value["kind"]][0])

func interpreter_queries_valid(value: Variant) -> bool:
	if not value is Array or value.size()>8:
		return false
	for query in value:
		if not DTO.exact_keys(query,["kind","args","limit"]) or not query["kind"] is String or not QUERY_TYPES.has(query["kind"]) or not arguments_valid(query["args"],QUERY_TYPES[query["kind"]]) or not DTO.whole(query["limit"],1,16):
			return false
		if query["kind"] in ["rule_record","rules_search"] and not query["args"]["category"] in CAT.TABLES:
			return false
	return true

func interpreter_intent_valid(value: Variant) -> bool:
	if DTO.exact_keys(value,["status","message"]):
		return value["status"] is String and value["status"] in ["clarification","unsupported"] and DTO.bounded_text(value["message"],1000)
	if DTO.exact_keys(value,["steps"]):
		if not value["steps"] is Array or value["steps"].is_empty() or value["steps"].size()>4:
			return false
		for step in value["steps"]:
			if not interpreter_action_valid(step):
				return false
		return true
	return interpreter_action_valid(value)

func interpreter_envelope_valid(value: Variant) -> bool:
	if not value is Dictionary or JSON.stringify(value).length()>65536:
		return false
	if value.has("status"):
		return interpreter_intent_valid(value)
	if not value.has("queries") or not interpreter_queries_valid(value["queries"]):
		return false
	var intent=value.duplicate(true)
	intent.erase("queries")
	return interpreter_intent_valid(intent)

func validate_request(id: String,req: Variant) -> Dictionary:
	if not session.request_valid(req) or req["campaign_id"]!=id or not TOOLS.has(req["kind"]) or not arguments_valid(req["args"],TOOLS[req["kind"]][0]):
		return error_result("invalid","Unregistered tool, mismatched envelope or invalid typed arguments.")
	var current=session.token(id)
	if not current.get("ok",false) or req["actor_id"]!=current.get("actor_id"):
		return error_result("invalid","Campaign or actor unavailable.")
	var prior=session.settlement(id,req["request_id"])
	if not prior.get("ok",false):
		return error_result("unconfirmed","Request settlement lookup failed.")
	if prior.get("found",false):
		if not session.same_request(prior["request"],req):
			return error_result("invalid","Request ID reused with different content.")
		return {"ok":true,"state":current,"prior":prior}
	if current["revision"]!=req["expected_revision"]:
		return error_result("stale","Refresh the authoritative campaign view.")
	if current["pending_turn_id"]!=null:
		return error_result("busy","Committed narration must finish.")
	var busy=session.read(current,[SQL.stmt("SELECT request_id FROM gameplay_requests WHERE status='accepted_pending' LIMIT 1")])
	if not busy.get("ok",false) or not busy["sets"][0].is_empty():
		return error_result("busy","An adopted logical request is pending.")
	return {"ok":true,"state":current,"prior":prior}

# Execute the entire validated read-only selection at one authoritative revision.
# Results are context only, never clearance or mechanical patches.
func interpreter_lookups(id: String,revision: int,requested: Variant) -> Dictionary:
	if not interpreter_queries_valid(requested):
		return error_result("invalid","Invalid interpreter lookup selection.")
	var state=session.token(id)
	if not state.get("ok",false) or state.get("revision")!=revision:
		return error_result("stale","Lookup revision unavailable.")
	var selected: Array=[]
	for query in requested:
		if selected.any(func(entry): return session.typed_equal(entry["query"],query)):
			continue
		var result=enquire(id,{"schema_version":"2","campaign_id":id,"expected_revision":revision,"query_id":session.make_id(),"kind":query["kind"],"args":query["args"],"limit":query["limit"]})
		if not result.get("ok",false):
			return result
		if JSON.stringify(result).length()>12000:
			return error_result("invalid","Lookup result exceeds packet limit.")
		selected.append({"query":query.duplicate(true),"result":result,"revision":revision})
		if JSON.stringify(selected).length()>32000:
			return error_result("invalid","Lookup selection exceeds packet limit.")
	var current=session.token(id)
	if not current.get("ok",false) or current.get("revision")!=revision:
		return error_result("stale","Campaign changed during lookup selection.")
	return {"ok":true,"selected":selected}

func enquire(id: String,query: Dictionary) -> Dictionary:
	return _enquire(id,query,false)

func enquire_local(id: String,query: Dictionary) -> Dictionary:
	return _enquire(id,query,true)

func _enquire(id: String,query: Dictionary,private_scope: bool) -> Dictionary:
	if not DTO.exact_keys(query,["schema_version","campaign_id","expected_revision","query_id","kind","args","limit"]) or query["schema_version"]!="2" or query["campaign_id"]!=id or not DTO.id_valid(query["query_id"]) or not DTO.whole(query["expected_revision"]) or not DTO.whole(query["limit"],1,64) or not QUERY_TYPES.has(query["kind"]) or not arguments_valid(query["args"],QUERY_TYPES[query["kind"]]):
		return error_result("invalid","Invalid bounded enquiry.")
	var state=session.token(id)
	if not state.get("ok",false) or state["revision"]!=query["expected_revision"]:
		return error_result("stale","Enquiry revision unavailable.")
	var args=query["args"]
	if query["kind"]=="object_profile":
		if ITEMS.new().official("rule-sections","objects").is_empty():
			return error_result("unsupported","Pinned object rule missing.")
		return {"ok":true,"schema_version":"2","campaign_id":id,"kind":query["kind"],"scope":"local" if private_scope else "public","query_id":query["query_id"],"revision":state["revision"],"data":{"material":args["material"],"size":args["size"],"resilience":args["resilience"],"suggested_ac":MATERIAL_AC[args["material"]],"suggested_hp":OBJECT_HP[args["size"]][0 if args["resilience"]=="fragile" else 1],"immunities":["poison","psychic"],"provenance":"2014 suggested object statistics; not damage resolution","rule_refs":[RAW.rule_ref("objects")]}}
	if query["kind"]=="equipment_options":
		var pack=noncombat.read_owned(state,state["actor_id"])
		if not pack.get("ok",false) or not pack["items"].has(args["instance_id"]):
			return error_result("decision_required","Owned instance or legacy slot review required.")
		var options=ITEMS.new().physical_options(pack["definitions"][args["instance_id"]])
		return {"ok":true,"schema_version":"2","campaign_id":id,"kind":query["kind"],"scope":"local" if private_scope else "public","query_id":query["query_id"],"revision":state["revision"],"data":{"instance_id":args["instance_id"],"physical_options":options,"slot_assignments":pack["slots"],"requires_context_validation":true}}
	return QUERIES.new().query_local(id,query) if private_scope else QUERIES.new().query_public(id,query)

func clearance(req: Dictionary,scope: String) -> Dictionary:
	return {"request_id":req["request_id"],"campaign_id":req["campaign_id"],"actor_id":req["actor_id"],"expected_revision":req["expected_revision"],"scope":scope,"approved":true}

# The review callable belongs exclusively to trusted local C4/C5 code.
# It must independently check intent and facts, not forward provider approval.
func reviewed(req: Dictionary,state: Dictionary,review: Callable) -> Dictionary:
	if not review.is_valid():
		return error_result("review_required","Local controller contextual review is not bound.")
	var decision=review.call(req.duplicate(true),{"campaign_id":state["campaign_id"],"actor_id":state["actor_id"],"revision":state["revision"],"location_id":state["location_id"]})
	if not DTO.exact_keys(decision,["request_id","campaign_id","actor_id","expected_revision","accepted","ruling","reason"]) or decision["request_id"]!=req["request_id"] or decision["campaign_id"]!=req["campaign_id"] or decision["actor_id"]!=req["actor_id"] or decision["expected_revision"]!=req["expected_revision"] or not decision["accepted"] is bool or not decision["ruling"] is Dictionary or not decision["reason"] is String:
		return error_result("review_required","Local contextual decision is invalid.")
	if not decision["accepted"]:
		return error_result("decision_required",decision["reason"])
	return {"ok":true,"ruling":decision["ruling"]}

func source_valid(state: Dictionary,event_id: int) -> bool:
	var event=session.source(state,event_id)
	if event.is_empty() or not event.get("kind") in ["campaign_created","narration","mechanical_receipt","gameplay_change"]:
		return false
	var data=event["data"]
	return data.get("location_id")==state["location_id"] or (event["kind"]=="campaign_created" and state["turn"]==0) or (DTO.sql_int(event["turn"])==state["turn"] and event["kind"] in ["narration","mechanical_receipt"])

func plan_action(state: Dictionary,req: Dictionary,ruling: Dictionary) -> Dictionary:
	var kind=req["kind"]
	var a=req["args"]
	var handler=kind
	var arguments: Dictionary={}
	var targets: Array=[]
	var raw_ruling: Dictionary={}
	var text=str(a.get("text",""))
	var refs: Array=[]
	if kind in ["ability_check","skill_check","object_check","saving_throw"]:
		if not source_valid(state,int(a["source_event_id"])):
			return error_result("review_required","Contextual challenge source is not an established local event.")
		if not DTO.exact_keys(ruling,["seconds","establish_clock","optional_features_resolved","verified_circumstances","effect_dc"]) or not ruling["verified_circumstances"] is Array or ruling["verified_circumstances"]!=a["circumstances"] or not ruling["optional_features_resolved"] is bool or ruling["optional_features_resolved"]!=true or not ruling["establish_clock"] is bool:
			return error_result("review_required","Challenge context or mandatory feature handling not established.")
		var advantage=false
		var disadvantage=false
		for circumstance in a["circumstances"]:
			if not source_valid(state,int(circumstance["source_event_id"])):
				return error_result("review_required","Circumstance evidence is not established locally.")
			advantage=advantage or circumstance["kind"]=="advantage"
			disadvantage=disadvantage or circumstance["kind"]=="disadvantage"
		if kind=="object_check":
			var object_rows=session.read(state,[SQL.stmt("SELECT id FROM item_instances WHERE id=? AND (actor_id=? OR container_id IN (SELECT id FROM loot_containers WHERE location_id=? AND visibility='player' AND status='available')) UNION ALL SELECT id FROM story_records WHERE id=? AND kind='circumstance' AND location_id=? AND visibility='player'",[a["object_id"],state["actor_id"],state["location_id"],a["object_id"],state["location_id"]])])
			if not object_rows.get("ok",false) or object_rows["sets"][0].size()!=1:
				return error_result("decision_required","Object identity is not an established local instance or circumstance.")
		handler="saving_throw" if kind=="saving_throw" else "ability_check"
		var skill=a.get("skill_id",a.get("skill"))
		if handler=="saving_throw" and not DTO.whole(ruling["effect_dc"],0,DTO.MAX_INT):
			return error_result("review_required","Saving throw needs independently verified triggering effect DC.")
		if handler!="saving_throw" and ruling["effect_dc"]!=null:
			return error_result("invalid","Contextual checks use the RAW difficulty category, not a supplied numeric DC.")
		arguments={"ability":a["ability"],"skill":skill}
		raw_ruling={"difficulty":null if handler=="saving_throw" else a["difficulty"],"effect_dc":ruling["effect_dc"],"advantage":advantage,"disadvantage":disadvantage,"seconds":ruling["seconds"],"establish_clock":ruling["establish_clock"],"optional_features_resolved":true}
		refs=RAW.refs_for(handler,a["ability"],skill,state["actor"])
	elif kind in ["travel","move"]:
		if not DTO.exact_keys(ruling,["difficult","clearance","establish_clock"]):
			return error_result("review_required","Actual route and hazards/supplies/time clearance required.")
		arguments={"route_id":a["route_id"],"destination_id":a["destination_id"],"pace":a["pace"],"fast_travel":a["fast_travel"]}
		targets=[{"kind":"location","id":a["destination_id"]}]
		raw_ruling=ruling
		refs=RAW.refs_for(handler)
	else:
		handler="wait" if kind=="wait" else "observe"
		if not DTO.exact_keys(ruling,["safe_nonmechanical","seconds","establish_clock"]) or not ruling["safe_nonmechanical"] is bool or ruling["safe_nonmechanical"]!=true or (kind=="wait" and ruling["seconds"]!=a["seconds"]) or (kind=="conversation" and (ruling["seconds"]!=0 or ruling["establish_clock"]!=false)):
			return error_result("review_required","Routine no-roll/time context not established.")
		raw_ruling=ruling
		refs=RAW.refs_for(handler)
	var action={"handler_id":handler,"target_refs":targets,"reference_refs":refs,"intent_text":text,"arguments":arguments}
	return {"ok":true,"action":action,"ruling":raw_ruling,"refs":refs,"text":text}

func resolve_adopted(id: String,req: Dictionary,state: Dictionary,prior: Dictionary,ruling: Dictionary) -> Dictionary:
	if prior.get("found",false):
		if prior["status"]!="accepted_pending":
			return error_result("invalid","Request is not pending.")
		if state["revision"]!=req["expected_revision"]:
			return error_result("stale","Adopted request no longer has its original revision.")
	var plan=plan_action(state,req,ruling)
	if not plan.get("ok",false):
		return plan
	var turn_id=prior["logical_turn_id"] if prior.get("found",false) else session.make_id()
	var request_id=req["request_id"]
	var action=plan["action"]
	var proposal={"schema_version":"1","request_id":request_id,"turn_id":turn_id,"campaign_id":id,"actor_id":state["actor_id"],"expected_revision":state["revision"],"status":"proposed","actions":[action],"clarification":null,"rule_refs":plan["refs"]}
	var valid=resolver.validate_proposal(state,request_id,turn_id,proposal,plan["refs"])
	if not valid.get("ok",false):
		return valid
	var approval={"campaign_id":id,"actor_id":state["actor_id"],"turn_id":turn_id,"expected_revision":state["revision"],"action":action,"ruling":plan["ruling"]}
	var adopted=session.adopt_tool(id,req,turn_id)
	if not adopted.get("found",false) or adopted.get("status")!="accepted_pending":
		return error_result("unconfirmed","Durable adoption not established; recover by request ID.")
	var bind=session.adoption_binding(id,request_id,turn_id)
	if not bind.get("ok",false):
		return bind
	var result=resolver.resolve(id,state,request_id,turn_id,proposal,plan["refs"],approval,plan["text"],bind["binding"])
	if result.get("ok",false):
		result["status"]="pending_narration"
	else:
		result["adopted_pending"]=true
	result["request_id"]=request_id
	result["turn_id"]=turn_id
	return result

# This validates the local handoff shape and exact request binding. Authority
# comes from the handler's revision-bound eligibility checks and SQLite reads.
func missing_custom_attributes_valid(result: Dictionary,req: Dictionary) -> bool:
	if not DTO.exact_keys(result,["ok","code","error","details"]) or not result["ok"] is bool or result["ok"] or result["code"]!=MISSING_CUSTOM_ATTRIBUTES or not DTO.bounded_text(result["error"],500):
		return false
	var details = result["details"]
	if not DTO.exact_keys(details,["request","instance_id","definition_id","origin","quantity","missing_paths","context"]):
		return false
	if not session.same_request(details["request"],req) or details["origin"]!="custom" or not DTO.id_valid(details["instance_id"]) or details["instance_id"]!=req["args"].get("instance_id") or not DTO.bounded_text(details["definition_id"],100) or not DTO.whole(details["quantity"],1):
		return false
	var paths = details["missing_paths"]
	if not paths is Array or paths.is_empty() or paths.size()>16 or not details["context"] is Dictionary or not session.json_safe(details["context"]):
		return false
	var seen: Array = []
	for path in paths:
		if not DTO.bounded_text(path,128) or path in seen:
			return false
		seen.append(path)
	return true

func execute(id: String,req: Dictionary,review: Callable,attribute: Dictionary={}) -> Dictionary:
	var result=_execute(id,req,review,attribute)
	if result.get("code")==MISSING_CUSTOM_ATTRIBUTES:
		if not missing_custom_attributes_valid(result,req):
			return error_result("unconfirmed","Missing item attribute result could not be verified.")
		var current = validate_request(id,req)
		if not current.get("ok",false):
			return current
		if current["prior"].get("found",false) or noncombat.prepared.has(id) or resolver.unresolved.has(id):
			return error_result("unconfirmed","Outstanding execution must be recovered before attribute review.")
	if not result.get("ok",false) and not result.has("code"):
		result["code"]="unconfirmed" if result.get("adopted_pending",false) or noncombat.prepared.has(id) else "review_required"
		result["details"]={"request_id":req.get("request_id")}
	return result

func _execute(id: String,req: Dictionary,review: Callable,attribute: Dictionary) -> Dictionary:
	if not attribute.is_empty() and req.get("kind")!="inspect_inscription":
		return error_result("invalid","Attribute proposal is outside the supported action.")
	var validated=validate_request(id,req)
	if not validated.get("ok",false):
		return validated
	var prior=validated["prior"]
	if prior.get("found",false) and prior["status"]!="accepted_pending":
		if noncombat.prepared.has(id) and session.same_request(noncombat.prepared[id]["context"]["request"],req) and prior["status"]=="committed":
			return noncombat.retry_prepared(id,req["request_id"])
		return {"ok":prior["status"]=="committed","replayed":true,"status":prior["status"],"result":prior["result"],"revision":prior["revision"],"request_id":req["request_id"]}
	if noncombat.prepared.has(id):
		if not session.same_request(noncombat.prepared[id]["context"]["request"],req):
			return error_result("busy","Reconcile the unconfirmed standalone request first.")
		return noncombat.retry_prepared(id,req["request_id"])
	if prior.get("found",false) and req["kind"] in ADOPTED:
		var persisted=resolver.store.receipt_by_id(id,prior["logical_turn_id"])
		if not persisted.get("ok",false):
			return persisted
		if persisted.get("found",false):
			return recover(id,req["request_id"])
	var state=validated["state"]
	var decision=reviewed(req,state,review)
	if not decision.get("ok",false):
		return decision
	var kind=req["kind"]
	if kind in ADOPTED:
		if not noncombat.quiet_context(state):
			return error_result("unsupported","Active encounters are outside the noncombat tool phase.")
		return resolve_adopted(id,req,state,prior,decision["ruling"])
	if prior.get("found",false) or resolver.unresolved.has(id):
		return error_result("busy","Reconcile the pending logical request before standalone execution.")
	if not decision["ruling"].is_empty():
		return error_result("invalid","Standalone tool does not accept additional mechanical ruling fields.")
	var catalog=ITEMS.new()
	for section in TOOLS[kind][2]:
		if catalog.official("rule-sections",section).is_empty():
			return error_result("unsupported","Applicable pinned rule unavailable: "+section)
	var scope="equipment" if kind in EQUIPMENT else str(SCOPES.get(kind,""))
	var permit=clearance(req,scope)
	noncombat.action_seconds=0
	if kind in EQUIPMENT:
		return noncombat.equipment_action(id,req,permit)
	match kind:
		"inspect_inscription": return noncombat.inspect_inscription(id,req,clearance(req,"inspect_inscription"),attribute)
		"item_use": return noncombat.consume(id,req,permit)
		"spell_cast": return noncombat.spell_cast(id,req,permit)
		"spell_prepare","spell_unprepare": return noncombat.prepare_spells(id,req,permit)
		"resource_use": return noncombat.use_resource(id,req,permit)
		"rest": return noncombat.rest(id,req,permit)
		"object_interact": return noncombat.object_interact(id,req,permit)
		"item_transfer","currency_transfer": return noncombat.transfer(id,req,permit)
		"loot_pickup","loot_take_all","item_drop":
			if not noncombat.safe_actor(state) or not noncombat.quiet_context(state):
				return error_result("unsupported","Transfer requires verified noncombat context.")
			noncombat.action_seconds=6
			return noncombat.drop(id,req,permit) if kind=="item_drop" else noncombat.pickup(id,req,permit)
		"loot_discover": return LOOT.new().reveal_discovery(id,req,permit)
		"define_custom": return LOOT.new().define_custom(id,req,permit)
		"define_official": return LOOT.new().define_official(id,req)
		"actor_generate": return ACTORS.new().generate(id,req,true)
		"story_update": return STORY.new().update_story(id,req,true)
		"party_membership": return EQUIP.new().record_party_membership(id,req,true)
		"reconcile_legacy_slots": return EQUIP.new().reconcile_legacy_slots(id,req,true)
	return error_result("unsupported","No registered handler.")

func recover(id: String,request_id: String) -> Dictionary:
	var prior=session.settlement(id,request_id)
	if not prior.get("found",false) or prior["status"]!="accepted_pending":
		return prior
	var receipt=resolver.store.receipt_by_id(id,prior["logical_turn_id"])
	if not receipt.get("ok",false):
		return receipt
	if not receipt.get("found",false):
		return {"ok":true,"status":"accepted_pending","request_id":request_id,"turn_id":prior["logical_turn_id"],"receipt":null}
	if receipt.get("narration_event_id")!=null:
		return session.settle_adopted(id,request_id,"committed")
	return {"ok":true,"status":"pending_narration","request_id":request_id,"receipt":receipt["receipt"],"player_text":receipt.get("player_text","")}

func cancel_uncommitted(id: String,request_id: String) -> Dictionary:
	if noncombat.prepared.has(id):
		return noncombat.abandon_prepared(id,request_id)
	var prior=session.settlement(id,request_id)
	if not prior.get("found",false) or prior["status"]!="accepted_pending":
		return error_result("invalid","No adopted request to cancel.")
	if resolver.unresolved.has(id):
		if resolver.unresolved[id]["receipt"]["turn_id"]!=prior["logical_turn_id"]:
			return error_result("busy","Different prepared receipt requires reconciliation.")
		var abandoned=resolver.abandon_uncommitted(id,prior["logical_turn_id"])
		if not abandoned.get("ok",false):
			return abandoned
	return session.settle_adopted(id,request_id,"cancelled",true)

func execute_sequence(id: String,requests: Array,review: Callable) -> Dictionary:
	if requests.is_empty() or requests.size()>16:
		return error_result("invalid","Provide one to sixteen ordered typed requests.")
	var results: Array=[]
	var seen: Array=[]
	for req in requests:
		if not req is Dictionary or not DTO.id_valid(req.get("request_id")) or req["request_id"] in seen:
			return {"ok":false,"code":"invalid","results":results,"next_index":results.size()}
		seen.append(req["request_id"])
		var result=execute(id,req,review)
		results.append(result)
		if not result.get("ok",false) or result.get("status") in ["accepted_pending","pending_narration"] or result.get("adopted_pending",false):
			return {"ok":result.get("ok",false),"status":"interrupted","results":results,"next_index":results.size()}
	return {"ok":true,"status":"completed","results":results,"next_index":results.size()}

const SUBJECT_CATEGORIES = {"spells":["spells"],"items":["equipment","magic-items"],"skills":["skills"],"abilities":["ability-scores"],"features":["features","traits"],"resources":[],"rules":["rule-sections"],"world":[]}
const DM_OPERATIONS = ["item_use","spell_cast"]

func lookup_subjects_valid(value: Dictionary) -> bool:
	var count = 0
	for key in value:
		if not SUBJECT_CATEGORIES.has(key) or not value[key] is Array:
			return false
		for subject in value[key]:
			if not DTO.bounded_text(subject,100):
				return false
			count+=1
	return count<=8

func subject_matches_name(subject: String, candidate: String) -> bool:
	return subject.strip_edges().to_lower().replace("-"," ")==candidate.strip_edges().to_lower().replace("-"," ")

# A lookup mention confers no authorization. An explicit first-person cast
# grounded in the original text can establish the need for a known spell.
func exact_cast_subject(text: String,subject: String) -> bool:
	var input = text.strip_edges().to_lower()
	var name = subject.strip_edges().to_lower().replace("-"," ")
	return subject_at_start(input,"i cast "+name) or subject_at_start(input,"cast "+name)

func subject_at_start(input: String, prefix: String) -> bool:
	return input==prefix or (input.begins_with(prefix) and input.substr(prefix.length(),1) in [" ",".",",","!"])

func spell_access(actor: Dictionary,spell: Dictionary) -> Dictionary:
	var casting = actor.get("spellcasting",{})
	var sources: Array = []
	var keys = {"class_cantrip":"cantrip_ids","racial_cantrip":"racial_cantrip_ids","known":"known_ids","prepared":"prepared_ids","always_prepared":"always_prepared_ids"}
	var level = int(spell.get("level",-1))
	if level<0 or level>9:
		return {}
	for source in keys:
		if (source in ["class_cantrip","racial_cantrip"])!=(level==0):
			continue
		if source=="known" and actor.get("class_id") in ["wizard","druid","cleric"]:
			continue
		if spell["index"] in casting.get(keys[source],[]):
			sources.append(source)
	var levels: Array = []
	for actual in range(maxi(1,level),10):
		var slot = casting.get("slots",{}).get(str(actual),{})
		if DTO.whole(slot.get("maximum")) and DTO.whole(slot.get("spent"),0,int(slot["maximum"])) and slot["spent"]<slot["maximum"]:
			levels.append(actual)
	return {"sources":sources,"slot_required":level>0,"available_slot_levels":levels if level>0 else [],"armor_blocks_casting":actor.get("equipment",{}).get("armor_penalty")!=false,"components":spell.get("components",[]),"concentration":casting.get("concentration")}

func lookup_subjects(state: Dictionary, subjects: Dictionary,text: String) -> Dictionary:
	if not lookup_subjects_valid(subjects):
		return error_result("invalid","Invalid lookup subjects.")
	var facts: Array = []
	var ids: Dictionary = {}
	var catalog = ITEMS.new()
	var owned = {}
	if not subjects.get("items",[]).is_empty() or not subjects.get("spells",[]).is_empty():
		owned=noncombat.read_owned(state,state["actor_id"])
		if not owned.get("ok",false):
			return error_result("unconfirmed","Owned item or casting context unavailable.")
	for key in subjects:
		for subject in subjects[key]:
			var fact = {"category":key,"subject":subject,"records":[]}
			for category in SUBJECT_CATEGORIES[key]:
				var searched = catalog.search(category,subject,12)
				if not searched.get("ok",false):
					return error_result("unconfirmed","Pinned "+key+" lookup unavailable.")
				for entry in searched["records"]:
					if not subject_matches_name(subject,entry["name"]) and not subject_matches_name(subject,entry["id"]):
						continue
					var record = catalog.official(category,entry["id"])
					if record.is_empty():
						return error_result("unconfirmed","Pinned subject record unavailable.")
					var binding = category+":"+entry["id"]
					if not ids.has(binding):
						fact["records"].append(record)
						ids[binding]=true
			if key=="spells" and fact["records"].size()==1:
				var spell = fact["records"][0]
				var access = spell_access(state["actor"],spell)
				if access.is_empty():
					return error_result("unconfirmed","Casting data unavailable.")
				access["free_hand"]=noncombat.casting_hand_free(owned)
				fact["access"]=access
				if exact_cast_subject(text,str(spell["name"])):
					if access["sources"].is_empty():
						return error_result("ineligible","You do not have "+str(spell["name"])+" available to cast.")
					if access["armor_blocks_casting"] or ("S" in access["components"] and "M" not in access["components"] and not access["free_hand"]):
						return error_result("ineligible","Your equipment prevents casting "+str(spell["name"])+".")
					if access["slot_required"] and access["available_slot_levels"].is_empty() and not spell.get("ritual",false):
						return error_result("insufficient_resources","You have no available slot for "+str(spell["name"])+".")
			elif key=="items":
				fact["owned"]=[]
				for iid in owned["items"]:
					var row = owned["items"][iid]
					if subject_matches_name(subject,row["name"]) or subject_matches_name(subject,row["definition_id"]) or subject==iid:
						fact["owned"].append({"instance_id":iid,"quantity":row["quantity"],"definition":owned["definitions"][iid]})
				var lower = text.strip_edges().to_lower()
				var named = subject.strip_edges().to_lower()
				var uses_owned = lower.trim_suffix(".") in ["i use my "+named,"use my "+named,"i eat my "+named,"eat my "+named,"i drink my "+named,"drink my "+named]
				if lower.begins_with("i cast ") and lower.contains(" carry my "):
					var carried = lower.get_slice(" carry my ",1)
					uses_owned = uses_owned or carried.trim_suffix(".")==named or carried.begins_with(named+" and ")
				if uses_owned and fact["owned"].is_empty():
					return error_result("ineligible","You do not have "+subject+" in your inventory.")
			elif key=="resources":
				fact["availability"]=state["actor"].get("resources",{}).get(subject.to_lower().replace(" ","_"))
			elif key=="world":
				var locations = session.read(state,[SQL.stmt("SELECT l.id,l.name,l.kind FROM locations l JOIN world_discovery d ON d.location_id=l.id WHERE d.visibility='player' AND d.status<>'unknown' AND (l.id=? OR lower(l.name)=lower(?)) ORDER BY l.id LIMIT 8",[subject,subject])])
				var actors = enquire(state["campaign_id"],{"schema_version":"2","campaign_id":state["campaign_id"],"expected_revision":state["revision"],"query_id":session.make_id(),"kind":"actors","args":{"location_id":state["location_id"]},"limit":16})
				if not locations.get("ok",false) or not actors.get("ok",false):
					return error_result("unconfirmed","Disclosed world lookup unavailable.")
				fact["locations"]=locations["sets"][0]
				fact["actors"]=actors["data"]["actors"].filter(func(row): return row["actor_id"]==subject or subject_matches_name(subject,row["name"]))
			facts.append(fact)
			if JSON.stringify(facts).length()>32000:
				return error_result("invalid","Lookup facts exceed the bounded packet.")
	var current = session.token(state["campaign_id"])
	if not current.get("ok",false) or not resolver.store.matching_token(state,current):
		return error_result("stale","Campaign changed during subject lookup.")
	return {"ok":true,"facts":facts}

func dm_operation_bound(operation: Dictionary,facts: Array,text: String) -> bool:
	var args = operation["args"]
	for fact in facts:
		if operation["kind"]=="spell_cast" and fact["category"]=="spells":
			for record in fact["records"]:
				if record["index"]==args["spell_id"] and exact_cast_subject(text,record["name"]):
					return true
		if operation["kind"]=="item_use" and fact["category"]=="items":
			for item in fact.get("owned",[]):
				var name = fact["subject"].to_lower().strip_edges()
				var input = text.to_lower().strip_edges()
				if args["instance_id"]==item["instance_id"] and input in ["i use my "+name,"use my "+name,"i eat my "+name,"eat my "+name,"i drink my "+name,"drink my "+name]:
					return true
	return false

func dm_check_valid(check: Variant) -> bool:
	return DTO.exact_keys(check,["ability","skill","difficulty"]) and check["ability"] in RAW.ABILITIES and (check["skill"]==null or DTO.bounded_text(check["skill"],100)) and RAW.DIFFICULTY.has(check["difficulty"])
