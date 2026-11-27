extends "res://persistence/gameplay_session.gd"
## Campaign definitions and loot ownership. All methods are trusted local
## persistence boundaries; C3 supplies the independently validated ruling.
const ITEMS = preload("res://persistence/item_catalog.gd")
const DENOMS = ["cp","sp","ep","gp","pp"]
const INSTANCE_ROWS = "SELECT i.*,d.name,d.origin,d.unit_weight_lb,d.attributes FROM item_instances i JOIN item_definitions d ON d.id=i.definition_id"

func coin_map(value: Variant) -> bool:
	if not DTO.exact_keys(value,DENOMS):
		return false
	for denom in DENOMS:
		if not DTO.whole(value[denom]):
			return false
	return true

func empty_coins() -> Dictionary:
	return {"cp":0,"sp":0,"ep":0,"gp":0,"pp":0}

# A trusted local adapter must establish these facts from the actual supported
# action and state, not from a provider response. This is not proof by shape.
func local_clearance(request: Dictionary,clearance: Dictionary,scope: String) -> bool:
	return DTO.exact_keys(clearance,["request_id","campaign_id","actor_id","expected_revision","scope","approved"]) and clearance.get("request_id")==request.get("request_id") and clearance.get("campaign_id")==request.get("campaign_id") and clearance.get("actor_id")==request.get("actor_id") and clearance.get("expected_revision")==request.get("expected_revision") and clearance.get("scope")==scope and clearance.get("approved") is bool and clearance["approved"]

func define_custom(id: String,request: Dictionary,clearance: Dictionary) -> Dictionary:
	var ctx = begin(id,request,"define_custom",["definition","source_event_id","official_equivalent_id"])
	if not ctx.get("ok",false) or ctx.get("replayed",false):
		return ctx
	if not local_clearance(request,clearance,"custom_definition"):
		return fail("Trusted local definition review required.")
	var state: Dictionary = ctx["state"]
	var args: Dictionary = request["args"]
	var cat = ITEMS.new()
	var proposed = args["definition"]
	if not cat.custom_valid(proposed):
		return fail("Invalid custom definition.")
	var event = source(state,args["source_event_id"])
	if event.is_empty():
		return fail("Definition provenance unavailable.")
	# A verified equivalent always reuses the immutable official definition.
	var search = cat.exact_official_name(proposed["name"])
	if not search.get("ok",false):
		return search
	var matches: Array = search["records"]
	if args["official_equivalent_id"]!=null:
		if not DTO.bounded_text(args["official_equivalent_id"],100):
			return fail("Invalid official equivalent.")
		var eq = str(args["official_equivalent_id"])
		var category = "magic-items" if eq.begins_with("magic:") else "equipment"
		var canonical = cat.official_definition(eq.trim_prefix("magic:"),category)
		if canonical.is_empty():
			return fail("Official equivalent unavailable.")
		return register_official(ctx,canonical)
	if matches.size()>1:
		return fail("Choose the exact canonical equivalent.")
	if matches.size()==1:
		var canonical = cat.official_definition(matches[0]["id"],matches[0]["category"])
		if canonical.is_empty():
			return fail("Official equivalent unavailable.")
		return register_official(ctx,canonical)
	var existing = read(state,[SQL.stmt("SELECT * FROM item_definitions WHERE lower(trim(name))=lower(trim(?)) ORDER BY id LIMIT 2",[proposed["name"]])])
	if not existing.get("ok",false):
		return existing
	if not existing["sets"][0].is_empty():
		if existing["sets"][0].size()!=1:
			return fail("Definition identity ambiguous.")
		var old = cat.from_row(existing["sets"][0][0])
		if old.get("origin")=="custom" and old.get("attributes")==proposed:
			return _reuse(ctx,{"definition_id":old["id"]},args["source_event_id"])
		return fail("Existing definition preserved. Use its ID or an explicitly distinct name.")
	var key = "custom-"+make_id()
	var definition = {"id":key,"origin":"custom","name":proposed["name"].strip_edges(),"unit_weight_lb":proposed["unit_weight_lb"],"attributes":proposed,"source_event_id":args["source_event_id"]}
	# Definition availability is not player discovery/ownership; do not publish
	# private names in the public log. Mechanical custom effects are unsupported.
	return _commit(ctx,[cat.insert_definition(definition)],{"definition_id":key},"A campaign object definition was registered.","private")

func register_official(ctx: Dictionary,definition: Dictionary) -> Dictionary:
	var state: Dictionary = ctx["state"]
	var existing = read(state,[SQL.stmt("SELECT id,attributes FROM item_definitions WHERE catalog_category=? AND catalog_id=? AND catalog_revision=?",[definition["catalog_category"],definition["catalog_id"],definition["catalog_revision"]])])
	if not existing.get("ok",false):
		return existing
	if not existing["sets"][0].is_empty():
		return _reuse(ctx,{"definition_id":existing["sets"][0][0]["id"]},ctx["request"]["args"]["source_event_id"])
	return _commit(ctx,[ITEMS.new().insert_definition(definition)],{"definition_id":definition["id"]},"An official item definition was registered.","private")

# Discovered items outside combat: a verified local discovery/ownership ruling
# may establish a source, once per committed source event, at current location.
# No narrative-only automatic reward; the local adapter owns permission/timing.
func reveal_discovery(id: String,request: Dictionary,clearance: Dictionary) -> Dictionary:
	var ctx = begin(id,request,"loot_discover",["source_event_id","location_id","name","items","coins"])
	if not ctx.get("ok",false) or ctx.get("replayed",false):
		return ctx
	if not local_clearance(request,clearance,"eligible_discovery"):
		return fail("Verified local discovery and access required.")
	var state: Dictionary = ctx["state"]
	var args: Dictionary = request["args"]
	if args["location_id"]!=state["location_id"] or not DTO.bounded_text(args["name"],100) or not args["items"] is Array or args["items"].size()>64 or not coin_map(args["coins"]):
		return fail("Invalid discovery container.")
	var event = source(state,args["source_event_id"])
	if not public_source(event) or (event["data"].get("location_id")!=state["location_id"] and (event["kind"]!="campaign_created" or state["turn"]!=0)):
		return fail("Discovery source is not a committed local event.")
	var existing = read(state,[SQL.stmt("SELECT id FROM loot_containers WHERE source_kind='discovery' AND source_key=?",[str(int(args["source_event_id"]))])])
	if not existing.get("ok",false):
		return existing
	if not existing["sets"][0].is_empty():
		return _reuse(ctx,{"container_id":existing["sets"][0][0]["id"]},args["source_event_id"])
	var container_id = make_id()
	var commands: Array = [SQL.stmt("INSERT INTO loot_containers(id,location_id,source_kind,source_key,source_event_id,name,visibility,status) VALUES(?,?,'discovery',?,?,?,'player','available')",[container_id,state["location_id"],str(int(args["source_event_id"])),int(args["source_event_id"]),args["name"].strip_edges()])]
	var cat = ITEMS.new()
	var seen: Array = []
	for row in args["items"]:
		if not DTO.exact_keys(row,["definition_id","quantity","charges","condition","attunement"]) or not DTO.bounded_text(row["definition_id"],100) or not DTO.whole(row["quantity"],1,100000) or (row["charges"]!=null and not DTO.whole(row["charges"])) or not row["condition"] in ["unknown","intact","worn","damaged","broken"] or not row["attunement"] in ["unknown","not_required","unattuned"] or (row["charges"]!=null and row["quantity"]!=1):
			return fail("Invalid discovered possession.")
		var def = read(state,[SQL.stmt("SELECT * FROM item_definitions WHERE id=?",[row["definition_id"]])])
		if not def.get("ok",false):
			return def
		if def["sets"][0].size()!=1 or def["sets"][0][0]["origin"]=="legacy_unresolved":
			return fail("Register a verified item definition before discovery.")
		var attributes = cat.from_row(def["sets"][0][0])
		if attributes.is_empty():
			return fail("Definition malformed.")
		if row["charges"]!=null:
			var maximum = attributes["attributes"].get("charges_max")
			if not DTO.whole(maximum) or row["charges"]>maximum:
				return fail("Charge capacity not established.")
		commands.append(SQL.stmt("INSERT INTO item_instances(id,definition_id,container_id,quantity,charges,condition,attunement,provenance,source_event_id) VALUES(?,?,?,?,?,?,?,?,?)",[make_id(),row["definition_id"],container_id,int(row["quantity"]),row["charges"],row["condition"],row["attunement"],JSON.stringify({"kind":"discovery","source_event_id":args["source_event_id"]}),int(args["source_event_id"])]))
		seen.append(row["definition_id"])
	var total_coins = 0
	for denom in DENOMS:
		total_coins+=int(args["coins"][denom])
		commands.append(SQL.stmt("INSERT INTO loot_currency(container_id,denomination,quantity) VALUES(?,?,?)",[container_id,denom,int(args["coins"][denom])]))
	if seen.is_empty() and total_coins==0:
		return fail("No recoverable possessions established.")
	return _commit(ctx,commands,{"container_id":container_id},"Recoverable possessions discovered: "+args["name"]+".")

# Future combat bridge. No function here manufactures a defeated enemy.
# A future trusted combat system must commit this exact outcome event:
# {schema_version:"1",encounter_id,source_actor_id,location_id,loot_eligible:true,
#  recoverable_instance_ids:[...],recover_currency:bool,visibility:"player"}.
func reveal_outcome(id: String,request: Dictionary,clearance: Dictionary) -> Dictionary:
	var ctx = begin(id,request,"loot_outcome",["source_event_id"])
	if not ctx.get("ok",false) or ctx.get("replayed",false):
		return ctx
	if not local_clearance(request,clearance,"eligible_outcome"):
		return fail("Verified local encounter outcome required.")
	var state: Dictionary = ctx["state"]
	var event = source(state,request["args"]["source_event_id"])
	var outcome = event.get("data",{})
	if event.get("kind")!="encounter_outcome" or not DTO.exact_keys(outcome,["schema_version","encounter_id","source_actor_id","location_id","loot_eligible","recoverable_instance_ids","recover_currency","visibility"]) or outcome["schema_version"]!="1" or outcome["loot_eligible"]!=true or not outcome["recover_currency"] is bool or outcome["visibility"]!="player" or outcome["location_id"]!=state["location_id"] or not DTO.id_valid(outcome["encounter_id"]) or not DTO.id_valid(outcome["source_actor_id"]) or outcome["source_actor_id"]==state["actor_id"] or not outcome["recoverable_instance_ids"] is Array or outcome["recoverable_instance_ids"].size()>128:
		return fail("No eligible committed outcome. Combat remains unsupported.")
	var source_id = outcome["source_actor_id"]
	var prior = read(state,[SQL.stmt("SELECT id FROM loot_containers WHERE source_kind='encounter_outcome' AND source_key=?",[source_id]),SQL.stmt("SELECT id FROM encounters WHERE id=? AND status IN ('resolved','completed','closed','defeated')",[outcome["encounter_id"]]),SQL.stmt("SELECT payload FROM actors WHERE id=? AND kind IN ('npc','enemy') AND location_id=?",[source_id,state["location_id"]]),SQL.stmt(INSTANCE_ROWS+" WHERE i.actor_id=? ORDER BY i.id",[source_id]),SQL.stmt("SELECT item_id,quantity,payload FROM inventory WHERE actor_id=? ORDER BY item_id",[source_id]),SQL.stmt("SELECT slot,instance_id FROM equipment_assignments WHERE actor_id=?",[source_id]),SQL.stmt("SELECT instance_id FROM equipment_review WHERE actor_id=? LIMIT 1",[source_id])])
	if not prior.get("ok",false):
		return prior
	var sets: Array = prior["sets"]
	if not sets[0].is_empty():
		return _reuse(ctx,{"container_id":sets[0][0]["id"]},request["args"]["source_event_id"])
	if sets[1].size()!=1 or sets[2].size()!=1 or not sets[6].is_empty():
		return fail("Outcome source is not a resolved local encounter actor or equipment requires review.")
	var payload = JSON.parse_string(sets[2][0]["payload"])
	if not payload is Dictionary or not payload.get("equipment",{}) is Dictionary:
		return fail("Source actor malformed.")
	var normalized: Dictionary = {}
	for row in sets[3]:
		var amount = DTO.sql_int(row["quantity"])
		if amount==null or amount<1:
			return fail("Source instance quantity invalid.")
		normalized[row["definition_id"]]=int(normalized.get(row["definition_id"],0))+amount
	if normalized.size()!=sets[4].size():
		return fail("Source instance ownership disagrees with normalized inventory.")
	for row in sets[4]:
		if normalized.get(row["item_id"])!=DTO.sql_int(row["quantity"]):
			return fail("Source instance quantity mismatch.")
	var selected: Array = []
	var requested = outcome["recoverable_instance_ids"]
	for instance_id in requested:
		if not DTO.id_valid(instance_id) or selected.any(func(row): return row["id"]==instance_id):
			return fail("Duplicate or invalid recoverable instance.")
		var row: Dictionary = {}
		for item in sets[3]:
			if item["id"]==instance_id:
				row=item
				break
		if row.is_empty() or row["attunement"]=="attuned" or DTO.sql_int(row["quantity"])==null:
			return fail("Recoverable possession unavailable or still attuned.")
		selected.append(row)
	var coins = empty_coins()
	if outcome["recover_currency"]:
		if not coin_map(payload.get("coins")):
			return fail("Source currency not established.")
		coins=payload["coins"].duplicate(true)
	var container_id = make_id()
	var event_id = int(request["args"]["source_event_id"])
	var commands: Array = [SQL.stmt("INSERT INTO loot_containers(id,location_id,source_kind,source_key,source_actor_id,source_event_id,name,visibility,status) VALUES(?,?,'encounter_outcome',?,?,?,?,'player','available')",[container_id,state["location_id"],source_id,source_id,event_id,"Recoverable possessions"])]
	commands.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('c2_source_guard',(SELECT 'ok' FROM actors WHERE id=? AND payload=? AND location_id=?))",[source_id,sets[2][0]["payload"],state["location_id"]]))
	var removed: Dictionary = {}
	var selected_ids: Array = []
	for row in selected:
		selected_ids.append(row["id"])
		var quantity = DTO.sql_int(row["quantity"])
		removed[row["definition_id"]]=int(removed.get(row["definition_id"],0))+quantity
		commands.append(SQL.stmt("DELETE FROM equipment_assignments WHERE actor_id=? AND instance_id=?",[source_id,row["id"]]))
		commands.append(SQL.stmt("DELETE FROM equipment_review WHERE actor_id=? AND instance_id=?",[source_id,row["id"]]))
		commands.append(SQL.stmt("UPDATE item_instances SET actor_id=NULL,container_id=? WHERE id=? AND actor_id=?",[container_id,row["id"],source_id]))
		commands.append(SQL.stmt("INSERT INTO item_transfers(id,request_id,source_instance_id,destination_instance_id,definition_id,quantity,source_container_id,destination_actor_id,source_event_id) VALUES(?,?,?,?,?,?,NULL,NULL,"+EVENT+")",[make_id(),request["request_id"],row["id"],row["id"],row["definition_id"],quantity,request["request_id"]]))
	# Preserve source actor's other possessions and exact canonical stat block.
	# No defeated state, HP, actions or movement is synthesized here.
	var remaining_items: Array = []
	var gear: Dictionary = payload.get("equipment",{}).duplicate(true)
	var remaining_equipped: Dictionary = {}
	for assignment in sets[5]:
		if assignment["instance_id"] in selected_ids:
			continue
		for owned_row in sets[3]:
			if owned_row["id"]==assignment["instance_id"]:
				remaining_equipped[owned_row["definition_id"]]=true
	for row in sets[4]:
		var data = JSON.parse_string(row["payload"])
		var quantity = DTO.sql_int(row["quantity"])
		if not data is Dictionary or quantity==null:
			return fail("Source normalized inventory malformed.")
		var item_id = row["item_id"]
		var left = quantity-int(removed.get(item_id,0))
		if left<0:
			return fail("Source ownership mismatch.")
		if not remaining_equipped.has(item_id):
			if gear.get("armor_id")==item_id:
				gear["armor_id"]=""
			if gear.get("shield_id")==item_id:
				gear["shield_id"]=""
			if gear.get("weapon_ids",[]) is Array:
				var weapons: Array = gear["weapon_ids"]
				weapons.erase(item_id)
				gear["weapon_ids"]=weapons
		if left==0:
			commands.append(SQL.stmt("DELETE FROM inventory WHERE actor_id=? AND item_id=?",[source_id,item_id]))
		else:
			data["quantity"]=left
			data["equipped"]=remaining_equipped.has(item_id)
			remaining_items.append(data)
			commands.append(SQL.stmt("UPDATE inventory SET quantity=?,payload=? WHERE actor_id=? AND item_id=?",[left,JSON.stringify(data),source_id,item_id]))
	if outcome["recover_currency"]:
		payload["coins"]=empty_coins()
	payload["inventory"]=remaining_items
	payload["equipment"]=gear
	commands.append(SQL.stmt("UPDATE actors SET payload=? WHERE id=?",[JSON.stringify(payload),source_id]))
	commands.append(SQL.stmt("DELETE FROM meta WHERE key='c2_source_guard'"))
	for denom in DENOMS:
		commands.append(SQL.stmt("INSERT INTO loot_currency(container_id,denomination,quantity) VALUES(?,?,?)",[container_id,denom,int(coins[denom])]))
	return _commit(ctx,commands,{"container_id":container_id},"Recoverable possessions are now available.")

# Atomic selective pickup or take-all. All-or-nothing, no implicit transfer on
# reveal or victory. Caller must independently establish time/access/legal use.
func pickup(id: String,request: Dictionary,clearance: Dictionary) -> Dictionary:
	var kind = str(request.get("kind",""))
	if not kind in ["loot_pickup","loot_take_all"]:
		return fail("Invalid loot intent.")
	var fields = ["container_id","source_event_id"] if kind=="loot_take_all" else ["container_id","source_event_id","items","coins"]
	var ctx = begin(id,request,kind,fields)
	if not ctx.get("ok",false) or ctx.get("replayed",false):
		return ctx
	if not local_clearance(request,clearance,"loot_transfer"):
		return fail("Trusted local pickup/access ruling required.")
	var state: Dictionary = ctx["state"]
	var args: Dictionary = request["args"]
	if not DTO.id_valid(args["container_id"]) or not DTO.whole(args["source_event_id"],1):
		return fail("Invalid loot source identity.")
	var cid = args["container_id"]
	var data = read(state,[SQL.stmt("SELECT id,source_event_id FROM loot_containers WHERE id=? AND location_id=? AND visibility='player' AND status='available'",[cid,state["location_id"]]),SQL.stmt(INSTANCE_ROWS+" WHERE i.container_id=? ORDER BY i.id",[cid]),SQL.stmt("SELECT denomination,quantity FROM loot_currency WHERE container_id=? ORDER BY denomination",[cid]),SQL.stmt(INSTANCE_ROWS+" WHERE i.actor_id=? ORDER BY i.id",[state["actor_id"]])])
	if not data.get("ok",false):
		return data
	var sets: Array = data["sets"]
	if sets[0].size()!=1 or DTO.sql_int(sets[0][0]["source_event_id"])!=args["source_event_id"]:
		return fail("Loot not available at the committed location.")
	if sets[2].size()!=DENOMS.size():
		return fail("Container currency is incomplete.")
	var available_coins = empty_coins()
	for row in sets[2]:
		var amount = DTO.sql_int(row["quantity"])
		if amount==null:
			return fail("Invalid loot currency.")
		available_coins[row["denomination"]]=amount
	var choices: Array = []
	var coins: Dictionary = {}
	if kind=="loot_take_all":
		for row in sets[1]:
			choices.append({"instance_id":row["id"],"quantity":DTO.sql_int(row["quantity"])})
		coins=available_coins.duplicate(true)
	else:
		if not args["items"] is Array or args["items"].size()>128 or not coin_map(args["coins"]):
			return fail("Invalid loot selection.")
		choices=args["items"]
		coins=args["coins"]
	var current_coins = state["actor"].get("coins")
	var capacity = state["actor"].get("carrying_capacity_lb")
	if not coin_map(current_coins) or not DTO.number(capacity,0,100000000):
		return fail("Carrying capacity or currency not established.")
	var current_load = 0.0
	var owned: Dictionary = {}
	for row in sets[3]:
		var weight = DTO.sql_number(row["unit_weight_lb"])
		var qty = DTO.sql_int(row["quantity"])
		if weight==null or qty==null or qty<1:
			return fail("Owned item weight/quantity unknown; cannot verify pickup capacity.")
		current_load+=float(weight)*qty
		owned[row["definition_id"]]=int(owned.get(row["definition_id"],0))+qty
	var items: Dictionary = {}
	for row in state["inventory"]:
		items[row["item_id"]]=row.duplicate(true)
	if items.size()!=owned.size():
		return fail("Normalized inventory and instance ownership disagree.")
	for item_id in owned:
		if not items.has(item_id) or items[item_id]["quantity"]!=owned[item_id]:
			return fail("Normalized inventory and instance ownership disagree.")
	var updated_coins: Dictionary = current_coins.duplicate(true)
	var coin_total = 0
	for denom in DENOMS:
		if coins[denom]>available_coins[denom] or not DTO.whole(int(updated_coins[denom])+int(coins[denom])):
			return fail("Currency unavailable or exceeds supported range.")
		updated_coins[denom]=int(updated_coins[denom])+int(coins[denom])
		coin_total+=int(coins[denom])
		current_load+=float(updated_coins[denom])/50.0
	if choices.is_empty() and coin_total==0:
		return fail("No unclaimed possessions selected.")
	var selected: Array = []
	var seen: Array = []
	var commands: Array = []
	for choice in choices:
		if not DTO.exact_keys(choice,["instance_id","quantity"]) or not DTO.id_valid(choice["instance_id"]) or not DTO.whole(choice["quantity"],1) or choice["instance_id"] in seen:
			return fail("Invalid or duplicate selected instance.")
		seen.append(choice["instance_id"])
		var row: Dictionary = {}
		for candidate in sets[1]:
			if candidate["id"]==choice["instance_id"]:
				row=candidate
				break
		if row.is_empty():
			return fail("Selected item already collected or unavailable.")
		var qty = DTO.sql_int(row["quantity"])
		var weight = DTO.sql_number(row["unit_weight_lb"])
		var amount = int(choice["quantity"])
		if qty==null or amount>qty or weight==null or row["attunement"]=="attuned" or (amount<qty and (row["charges"]!=null or row["origin"]!="official" or not row["attunement"] in ["unknown","not_required"])):
			return fail("Quantity, weight, charges or attunement requires adjudication.")
		current_load+=float(weight)*amount
		var destination = row["id"] if amount==qty else make_id()
		commands.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('c2_pick_guard',(SELECT 'ok' FROM item_instances WHERE id=? AND container_id=? AND quantity=CAST(? AS INTEGER)))",[row["id"],cid,qty]))
		if amount==qty:
			commands.append(SQL.stmt("UPDATE item_instances SET actor_id=?,container_id=NULL WHERE id=?",[state["actor_id"],row["id"]]))
		else:
			commands.append(SQL.stmt("UPDATE item_instances SET quantity=quantity-CAST(? AS INTEGER) WHERE id=?",[amount,row["id"]]))
			commands.append(SQL.stmt("INSERT INTO item_instances(id,definition_id,actor_id,quantity,charges,condition,attunement,provenance,source_event_id) SELECT ?,definition_id,?,CAST(? AS INTEGER),NULL,condition,attunement,provenance,source_event_id FROM item_instances WHERE id=?",[destination,state["actor_id"],amount,row["id"]]))
		commands.append(SQL.stmt("DELETE FROM meta WHERE key='c2_pick_guard'"))
		commands.append(SQL.stmt("INSERT INTO item_transfers(id,request_id,source_instance_id,destination_instance_id,definition_id,quantity,source_container_id,destination_actor_id,source_event_id) VALUES(?,?,?,?,?,?,?,?,"+EVENT+")",[make_id(),request["request_id"],row["id"],destination,row["definition_id"],amount,cid,state["actor_id"],request["request_id"]]))
		var item_id = row["definition_id"]
		var current: Dictionary = items.get(item_id,{"item_id":item_id,"quantity":0,"equipped":false})
		current["quantity"]=int(current["quantity"])+amount
		if not DTO.whole(current["quantity"],1):
			return fail("Inventory quantity exceeds supported range.")
		items[item_id]=current
		selected.append({"instance_id":destination,"definition_id":item_id,"quantity":amount})
	if current_load>float(capacity):
		return fail("Selection exceeds established carrying capacity.")
	for denom in DENOMS:
		if coins[denom]>0:
			commands.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('c2_coin_guard',(SELECT 'ok' FROM loot_currency WHERE container_id=? AND denomination=? AND quantity=CAST(? AS INTEGER)))",[cid,denom,available_coins[denom]]))
			commands.append(SQL.stmt("UPDATE loot_currency SET quantity=quantity-CAST(? AS INTEGER) WHERE container_id=? AND denomination=?",[int(coins[denom]),cid,denom]))
			commands.append(SQL.stmt("DELETE FROM meta WHERE key='c2_coin_guard'"))
	for item_id in items:
		var row: Dictionary = items[item_id]
		commands.append(SQL.stmt("INSERT INTO inventory(actor_id,item_id,quantity,payload) VALUES(?,?,?,?) ON CONFLICT(actor_id,item_id) DO UPDATE SET quantity=excluded.quantity,payload=excluded.payload",[state["actor_id"],item_id,int(row["quantity"]),JSON.stringify(row)]))
	var actor: Dictionary = state["actor"].duplicate(true)
	actor["coins"]=updated_coins
	actor["inventory"]=items.values()
	actor["carried_weight_lb"]=current_load
	commands.append(SQL.stmt("UPDATE actors SET payload=? WHERE id=?",[JSON.stringify(actor),state["actor_id"]]))
	commands.append(SQL.stmt("UPDATE loot_containers SET status='closed' WHERE id=? AND NOT EXISTS(SELECT 1 FROM item_instances WHERE container_id=?) AND NOT EXISTS(SELECT 1 FROM loot_currency WHERE container_id=? AND quantity>0)",[cid,cid,cid]))
	return _commit(ctx,commands,{"items":selected,"coins":coins,"container_id":cid},"Selected possessions collected.")


# Immutable official definition registration, no invented custom proposal.
func define_official(id: String,request: Dictionary) -> Dictionary:
	var ctx = begin(id,request,"define_official",["category","catalog_id","source_event_id"])
	if not ctx.get("ok",false) or ctx.get("replayed",false):
		return ctx
	var args: Dictionary = request["args"]
	if not args["category"] in ["equipment","magic-items"] or not DTO.bounded_text(args["catalog_id"],100) or source(ctx["state"],args["source_event_id"]).is_empty():
		return fail("Invalid official definition reference.")
	var definition = ITEMS.new().official_definition(args["catalog_id"],args["category"])
	if definition.is_empty():
		return fail("Pinned official definition unavailable.")
	return register_official(ctx,definition)

# Underlying C3 drop persistence. A resolved local action may transfer an
# unequipped, non-attuned possession to a visible recoverable container.
func drop(id: String,request: Dictionary,clearance: Dictionary) -> Dictionary:
	var ctx = begin(id,request,"item_drop",["instance_id","quantity"])
	if not ctx.get("ok",false) or ctx.get("replayed",false):
		return ctx
	if not local_clearance(request,clearance,"drop_transfer"):
		return fail("Trusted local drop ruling required.")
	var state: Dictionary = ctx["state"]
	var args: Dictionary = request["args"]
	if not DTO.id_valid(args["instance_id"]) or not DTO.whole(args["quantity"],1):
		return fail("Invalid drop selection.")
	var data = read(state,[SQL.stmt(INSTANCE_ROWS+" WHERE i.id=? AND i.actor_id=?",[args["instance_id"],state["actor_id"]]),SQL.stmt("SELECT instance_id FROM equipment_assignments WHERE instance_id=? UNION ALL SELECT instance_id FROM equipment_review WHERE instance_id=?",[args["instance_id"],args["instance_id"]]),SQL.stmt("SELECT definition_id,sum(quantity) AS quantity FROM item_instances WHERE actor_id=? GROUP BY definition_id",[state["actor_id"]]),SQL.stmt("SELECT 1 FROM world_discovery WHERE location_id=? AND visibility='player' AND status<>'unknown'",[state["location_id"]])])
	if not data.get("ok",false):
		return data
	var sets: Array = data["sets"]
	if sets[0].size()!=1 or not sets[1].is_empty() or sets[3].size()!=1:
		return fail("Possession unavailable, equipped, or location undisclosed.")
	var row: Dictionary = sets[0][0]
	var total = DTO.sql_int(row["quantity"])
	var amount = int(args["quantity"])
	if total==null or amount>total or row["attunement"]=="attuned" or (amount<total and (row["charges"]!=null or row["origin"]!="official" or not row["attunement"] in ["unknown","not_required"])):
		return fail("Quantity or charge/attunement state requires adjudication.")
	var aggregate: Dictionary = {}
	for entry in sets[2]:
		aggregate[entry["definition_id"]]=DTO.sql_int(entry["quantity"])
	var items: Dictionary = {}
	for item in state["inventory"]:
		if aggregate.get(item["item_id"])!=item["quantity"]:
			return fail("Inventory ownership mirror disagrees.")
		items[item["item_id"]]=item.duplicate(true)
	if items.size()!=aggregate.size() or not items.has(row["definition_id"]):
		return fail("Inventory ownership mirror disagrees.")
	var rid = request["request_id"]
	var container_id = make_id()
	var destination = row["id"] if amount==total else make_id()
	var commands: Array = [SQL.stmt("INSERT INTO loot_containers(id,location_id,source_kind,source_key,source_actor_id,source_event_id,name,visibility,status) VALUES(?,?,'drop',?,?,"+EVENT+",'Dropped possessions','player','available')",[container_id,state["location_id"],rid,state["actor_id"],rid])]
	commands.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('c2_drop_guard',(SELECT 'ok' FROM item_instances WHERE id=? AND actor_id=? AND quantity=CAST(? AS INTEGER) AND NOT EXISTS(SELECT 1 FROM equipment_assignments WHERE instance_id=?) AND NOT EXISTS(SELECT 1 FROM equipment_review WHERE instance_id=?)))",[row["id"],state["actor_id"],total,row["id"],row["id"]]))
	if amount==total:
		commands.append(SQL.stmt("UPDATE item_instances SET actor_id=NULL,container_id=? WHERE id=?",[container_id,row["id"]]))
	else:
		commands.append(SQL.stmt("UPDATE item_instances SET quantity=quantity-CAST(? AS INTEGER) WHERE id=?",[amount,row["id"]]))
		commands.append(SQL.stmt("INSERT INTO item_instances(id,definition_id,container_id,quantity,charges,condition,attunement,provenance,source_event_id) SELECT ?,definition_id,?,CAST(? AS INTEGER),NULL,condition,attunement,provenance,source_event_id FROM item_instances WHERE id=?",[destination,container_id,amount,row["id"]]))
	commands.append(SQL.stmt("DELETE FROM meta WHERE key='c2_drop_guard'"))
	for denom in DENOMS:
		commands.append(SQL.stmt("INSERT INTO loot_currency(container_id,denomination,quantity) VALUES(?,?,0)",[container_id,denom]))
	commands.append(SQL.stmt("INSERT INTO item_transfers(id,request_id,source_instance_id,destination_instance_id,definition_id,quantity,source_container_id,destination_actor_id,source_event_id) VALUES(?,?,?,?,?,?,NULL,NULL,"+EVENT+")",[make_id(),rid,row["id"],destination,row["definition_id"],amount,rid]))
	var mirror: Dictionary = items[row["definition_id"]]
	mirror["quantity"]=int(mirror["quantity"])-amount
	if mirror["quantity"]==0:
		items.erase(row["definition_id"])
		commands.append(SQL.stmt("DELETE FROM inventory WHERE actor_id=? AND item_id=?",[state["actor_id"],row["definition_id"]]))
	else:
		commands.append(SQL.stmt("UPDATE inventory SET quantity=?,payload=? WHERE actor_id=? AND item_id=?",[mirror["quantity"],JSON.stringify(mirror),state["actor_id"],row["definition_id"]]))
	var actor: Dictionary = state["actor"].duplicate(true)
	actor["inventory"]=items.values()
	# Recompute weight in the authoritative view, not from a stale saved total.
	actor["carried_weight_lb"]=null
	commands.append(SQL.stmt("UPDATE actors SET payload=? WHERE id=?",[JSON.stringify(actor),state["actor_id"]]))
	return _commit(ctx,commands,{"container_id":container_id,"instance_id":destination,"quantity":amount},"Selected possession dropped.")
