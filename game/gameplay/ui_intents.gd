extends RefCounted
## C1 local presentation adapter. No SQL, dice, provider, or mechanical authority.
## The controller must independently revalidate every intent; this is not a plan.
const VERSION = "1"
const SLOTS = ["head","cloak","body","hands","feet","neck","ring","accessory","belt","shield","main_hand","off_hand"]
const GRIPS = ["worn","one_handed","two_handed"]
const ABILITIES = ["str","dex","con","int","wis","cha"]
const SPELL_SOURCES = ["class_cantrip","racial_cantrip","known","prepared","always_prepared"]
const FIELDS = {
	"equip":["instance_id","slot","grip"],
	"swap":["instance_id","slot","grip","replace_instance_ids"],
	"unequip":["instance_id","slot"],
	"item_use":["instance_id","quantity","target_id"],
	"item_drop":["instance_id","quantity"],
	"attune":["instance_id"],
	"unattune":["instance_id"],
	"spell_prepare":["spell_id"],
	"spell_unprepare":["spell_id"],
	"spell_cast":["spell_id","source","slot_level","target_id"],
	"skill_check":["skill_id"],
	"ability_check":["ability"],
	"saving_throw":["ability"],
	"rest":["rest_kind"],
	"resource_use":["resource_id","quantity"],
	"level_up":[],
	"quest_interact":["quest_id"],
	"party_add":["member_actor_id"],
	"travel":["destination_id"],
	"chat":["text"],
	"retry":["turn_id"],
	"cancel":["turn_id"]
}
var snapshot: Dictionary = {}
var interaction: Dictionary = {}
var handler: Callable
var campaign_id = ""
var actor_id = ""
var revision = -1
var outstanding_id = ""
var invalid_reply = false
var view_valid = false
var last_error = ""

static func stable_id(value: Variant) -> bool:
	if not value is String or value.length()!=32:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true

static func integer(value: Variant, minimum: int = 0, maximum: int = 2147483647) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floor(float(value))==float(value) and float(value)>=minimum and float(value)<=maximum

static func identifier(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length()<=128

static func exact_keys(value: Dictionary, keys: Array) -> bool:
	if value.size()!=keys.size():
		return false
	for key in keys:
		if not value.has(key):
			return false
	return true

func configure(value: Dictionary, callback: Callable = Callable()) -> void:
	handler = callback
	snapshot = {}
	interaction = {}
	campaign_id = ""
	actor_id = ""
	revision = -1
	outstanding_id = ""
	invalid_reply = false
	last_error = ""
	accept_view(value)

func accept_view(value: Dictionary) -> bool:
	view_valid = false
	# The legacy read model is usable for browsing, never for a state-changing intent.
	var campaign = value.get("campaign",{})
	var actor = value.get("actor",{})
	if not campaign is Dictionary or not actor is Dictionary:
		last_error = "Invalid campaign or actor view."
		return false
	var cid = str(campaign.get("id",""))
	var aid = str(actor.get("id",""))
	if not campaign_id.is_empty() and (cid!=campaign_id or aid!=actor_id):
		last_error = "Campaign or actor changed; reopen the workspace."
		return false
	var packet = value.get("interaction")
	if packet!=null and (campaign.get("actor_id")!=aid or not valid_view(packet,cid,aid)):
		last_error = "Interaction view invalid; gameplay mutations unavailable."
		return false
	if packet==null and revision>=0:
		last_error = "Authoritative interaction view missing; refresh required."
		return false
	if packet is Dictionary and int(packet["revision"])<revision:
		last_error = "Stale interaction view ignored."
		return false
	campaign_id = cid
	actor_id = aid
	snapshot = value.duplicate(true)
	interaction = packet.duplicate(true) if packet is Dictionary else {}
	if not interaction.is_empty():
		revision = int(interaction["revision"])
		if not outstanding_id.is_empty() and interaction.get("settled_request_id")==outstanding_id:
			outstanding_id = ""
			invalid_reply = false
	last_error = ""
	view_valid = true
	return true

static func valid_view(packet: Variant,cid: String,aid: String) -> bool:
	if not packet is Dictionary or not stable_id(cid) or not stable_id(aid):
		return false
	if packet.get("schema_version")!=VERSION or packet.get("campaign_id")!=cid or packet.get("actor_id")!=aid or not integer(packet.get("revision")):
		return false
	if not packet.get("phase") in ["idle","busy","awaiting_decision","retryable","blocked"] or not packet.get("supported_intents") is Array:
		return false
	for key in ["pending_turn_id","active_turn_id","settled_request_id"]:
		if not packet.has(key) or (packet[key]!=null and not stable_id(packet[key])):
			return false
	if not packet.has("settled_status") or (packet.get("settled_request_id")==null and packet["settled_status"]!=null) or (packet.get("settled_request_id")!=null and not packet["settled_status"] in ["accepted_pending","committed","rejected","cancelled"]):
		return false
	for kind in packet["supported_intents"]:
		if not kind is String or not FIELDS.has(kind):
			return false
	if not packet.get("inventory_instances") is Array or not packet.get("slot_assignments") is Dictionary or not exact_keys(packet["slot_assignments"],SLOTS):
		return false
	var ids = {}
	for row in packet["inventory_instances"]:
		if not row is Dictionary or not stable_id(row.get("instance_id")) or ids.has(row["instance_id"]) or not identifier(row.get("definition_id")) or not integer(row.get("quantity"),1) or not row.get("name") is String or not row.get("description") is String or not row.get("equip_options") is Array:
			return false
		ids[row["instance_id"]] = true
		var options_seen = {}
		for opt in row["equip_options"]:
			if not opt is Dictionary or not opt.get("slot") in SLOTS or not opt.get("grip") in GRIPS or not opt.get("available") is bool or not opt.get("warning") is String or not opt.get("replace_instance_ids") is Array:
				return false
			var key = str(opt["slot"])+":"+str(opt["grip"])
			if options_seen.has(key):
				return false
			options_seen[key] = true
			var displaced = {}
			for other in opt["replace_instance_ids"]:
				if not stable_id(other) or other==row["instance_id"] or displaced.has(other):
					return false
				displaced[other] = true
	for key in packet["slot_assignments"]:
		if not key in SLOTS or (packet["slot_assignments"][key]!=null and not ids.has(packet["slot_assignments"][key])):
			return false
	for row in packet["inventory_instances"]:
		for opt in row["equip_options"]:
			for other in opt["replace_instance_ids"]:
				if not ids.has(other):
					return false
	if not packet.get("spell_options") is Array or not packet.get("preparation_options") is Array or not packet.get("public_quests") is Array:
		return false
	var casts_seen = {}
	for opt in packet["spell_options"]:
		if not opt is Dictionary or not identifier(opt.get("spell_id")) or not opt.get("source") in SPELL_SOURCES or not integer(opt.get("slot_level"),0,9) or not opt.get("available") is bool or not opt.get("warning") is String:
			return false
		var key = str(opt["spell_id"])+":"+str(opt["source"])+":"+str(int(opt["slot_level"]))
		if casts_seen.has(key):
			return false
		casts_seen[key] = true
	var preparation_seen = {}
	for opt in packet["preparation_options"]:
		if not opt is Dictionary or not identifier(opt.get("spell_id")) or not opt.get("kind") in ["spell_prepare","spell_unprepare"] or not opt.get("available") is bool or not opt.get("warning") is String:
			return false
		var key = str(opt["spell_id"])+":"+str(opt["kind"])
		if preparation_seen.has(key):
			return false
		preparation_seen[key] = true
	var quests_seen = {}
	for row in packet["public_quests"]:
		if not row is Dictionary or not stable_id(row.get("id")) or quests_seen.has(row["id"]) or not row.get("title") is String or not row.get("description") is String or not row.get("status") is String or not integer(row.get("source_event_id"),1):
			return false
		quests_seen[row["id"]] = true
	if not packet.get("party_members",[]) is Array or not packet.get("party_candidates",[]) is Array:
		return false
	var members = {}
	members[aid] = true
	for member in packet.get("party_members",[]):
		if not member is Dictionary or not stable_id(member.get("actor_id")) or members.has(member["actor_id"]) or not member.get("name") is String or not member.get("portrait","") is String:
			return false
		for key in ["hp_current","hp_max","level"]:
			if member.get(key)!=null and not integer(member[key]):
				return false
		members[member["actor_id"]] = true
	for candidate in packet.get("party_candidates",[]):
		if not candidate is Dictionary or not stable_id(candidate.get("actor_id")) or members.has(candidate["actor_id"]) or not candidate.get("name") is String or not candidate.get("available") is bool or not candidate.get("warning") is String:
			return false
		members[candidate["actor_id"]] = true
	return true

func available(kind: String) -> bool:
	if not view_valid or not handler.is_valid() or interaction.is_empty() or not outstanding_id.is_empty() or not kind in interaction.get("supported_intents",[]):
		return false
	if kind=="retry":
		return stable_id(interaction.get("active_turn_id")) and interaction.get("phase")=="retryable"
	if kind=="cancel":
		return stable_id(interaction.get("active_turn_id")) and interaction.get("phase") in ["retryable","awaiting_decision","busy","blocked"]
	return interaction.get("phase")=="idle" and interaction.get("pending_turn_id")==null

func reason(kind: String) -> String:
	if not view_valid:
		return "Invalid or stale authoritative view; refresh required."
	if not handler.is_valid():
		return "Controller not connected — inspection only."
	if interaction.is_empty():
		return "Authoritative revision and instance view unavailable."
	if not outstanding_id.is_empty():
		return "Awaiting authoritative refresh; do not resubmit."
	if not kind in interaction.get("supported_intents",[]):
		return "Handler unavailable."
	if not available(kind):
		return "Turn pending or controller not ready."
	return ""

func instance(id: String) -> Dictionary:
	for row in interaction.get("inventory_instances",[]):
		if row.get("instance_id")==id:
			return row
	return {}

func option_for(id: String,slot: String,grip: String) -> Dictionary:
	for opt in instance(id).get("equip_options",[]):
		if opt.get("slot")==slot and opt.get("grip")==grip:
			return opt
	return {}

func owns_spell(id: String) -> bool:
	var sp = snapshot.get("actor",{}).get("spellcasting",{})
	for key in ["known_ids","prepared_ids","always_prepared_ids","cantrip_ids","racial_cantrip_ids"]:
		if id in sp.get(key,[]):
			return true
	return false

func preparation_option(id: String,kind: String) -> Dictionary:
	for row in interaction.get("preparation_options",[]):
		if row.get("spell_id")==id and row.get("kind")==kind:
			return row
	return {}

func validate_args(kind: String,args: Dictionary) -> bool:
	if not FIELDS.has(kind) or not exact_keys(args,FIELDS[kind]):
		return false
	var actor = snapshot.get("actor",{})
	match kind:
		"equip","swap","unequip","item_use","item_drop","attune","unattune":
			if not stable_id(args.get("instance_id")):
				return false
			var row = instance(args["instance_id"])
			if row.is_empty():
				return false
			if kind in ["equip","swap"]:
				if not args["slot"] in SLOTS or not args["grip"] in GRIPS:
					return false
				var opt = option_for(args["instance_id"],args["slot"],args["grip"])
				if opt.is_empty() or not opt.get("available",false):
					return false
				var replaced = opt.get("replace_instance_ids",[])
				var current = interaction["slot_assignments"].get(args["slot"])
				if current!=null and current!=args["instance_id"] and not current in replaced:
					return false
				return (kind=="equip" and replaced.is_empty()) or (kind=="swap" and not replaced.is_empty() and args["replace_instance_ids"]==replaced)
			if kind=="unequip":
				return args["slot"] in SLOTS and interaction["slot_assignments"].get(args["slot"])==args["instance_id"]
			if kind in ["item_use","item_drop"]:
				if not integer(args["quantity"],1,int(row["quantity"])):
					return false
				return kind=="item_drop" or args["target_id"]==null or stable_id(args["target_id"])
			if kind=="attune":
				return row.get("attunement_status")=="unattuned"
			return row.get("attunement_status")=="attuned"
		"spell_prepare","spell_unprepare":
			return identifier(args["spell_id"]) and preparation_option(args["spell_id"],kind).get("available",false)
		"spell_cast":
			if not identifier(args["spell_id"]) or not integer(args["slot_level"],0,9) or not args["source"] in SPELL_SOURCES or (args["target_id"]!=null and not stable_id(args["target_id"])):
				return false
			for opt in interaction.get("spell_options",[]):
				if opt.get("spell_id")==args["spell_id"] and opt.get("source")==args["source"] and opt.get("slot_level")==args["slot_level"] and opt.get("available",false):
					return true
			return false
		"skill_check":
			return identifier(args["skill_id"]) and actor.get("skills",{}).has(args["skill_id"])
		"ability_check","saving_throw":
			return args["ability"] in ABILITIES and actor.get("saving_throws" if kind=="saving_throw" else "ability_scores",{}).has(args["ability"])
		"rest":
			return args["rest_kind"] in ["short","long"]
		"resource_use":
			if not identifier(args["resource_id"]):
				return false
			var resource = actor.get("resources",{}).get(args["resource_id"],{})
			var maximum = resource.get("max")
			var spent = resource.get("spent")
			return integer(maximum) and integer(spent) and int(spent)<=int(maximum) and integer(args["quantity"],1,int(maximum)-int(spent))
		"level_up":
			return true
		"quest_interact":
			if not stable_id(args["quest_id"]):
				return false
			for row in interaction.get("public_quests",[]):
				if row.get("id")==args["quest_id"]:
					return true
			return false
		"party_add":
			if not stable_id(args["member_actor_id"]):
				return false
			for row in interaction.get("party_candidates",[]):
				if row.get("actor_id")==args["member_actor_id"] and row.get("available",false):
					return true
			return false
		"travel":
			# Caller also checks matching MapView revision. Do not forward an ID
			# absent from the same authoritative visible gameplay projection.
			if not stable_id(args["destination_id"]) or args["destination_id"]==actor.get("location_id"):
				return false
			for row in snapshot.get("locations",[]):
				if row.get("id")==args["destination_id"]:
					return true
			return false
		"chat":
			return args["text"] is String and not args["text"].strip_edges().is_empty() and args["text"].length()<=2000
		"retry","cancel":
			return stable_id(args["turn_id"]) and args["turn_id"]==interaction.get("active_turn_id")
	return false

func request(kind: String,args: Dictionary) -> Dictionary:
	if not available(kind):
		return {"ok":false,"message":reason(kind)}
	if not validate_args(kind,args):
		return {"ok":false,"message":"Invalid or no longer offered selection. Refresh the campaign."}
	var id = Crypto.new().generate_random_bytes(16).hex_encode()
	var packet = {"schema_version":VERSION,"campaign_id":campaign_id,"actor_id":actor_id,"expected_revision":revision,"request_id":id,"kind":kind,"args":args.duplicate(true)}
	outstanding_id = id
	var reply = handler.call(packet)
	# Acknowledgement is never a receipt or a state change. Unknown delivery
	# stays locked until a trusted controller refresh reconciles the request.
	if not reply is Dictionary or reply.get("request_id")!=id or not reply.get("ok") is bool or not reply.get("message") is String:
		invalid_reply = true
		return {"ok":false,"message":"Request acknowledgement unavailable. Reconcile before retrying."}
	if not reply["ok"]:
		outstanding_id = ""
		return {"ok":false,"message":reply["message"]}
	return {"ok":true,"message":"Intention accepted for processing; awaiting committed state."}
