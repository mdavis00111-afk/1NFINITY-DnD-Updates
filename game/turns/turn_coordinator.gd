extends Node
## B3 controller, intentionally not wired to gameplay composer until B4/QA.
## One trusted controller per active campaign. No provider-originated approvals.
signal state_changed(state: Dictionary)
const PACK = preload("res://turns/agent_packets.gd")
const DTO = preload("res://world/world_dto.gd")
const RAW = preload("res://turns/raw_mechanics.gd")
const RESOLVER = preload("res://turns/turn_resolver.gd")
const STORE = preload("res://turns/turn_store.gd")
const WORLD = preload("res://world/world_store.gd")
const MIGRATION = preload("res://world/world_migration.gd")
const GEMINI = preload("res://systems/gemini.gd")

var store = STORE.new()
var world = WORLD.new()
var resolver = RESOLVER.new()
var provider_factory: Callable
var transport: Node
var campaign_id = ""
var actor_id = ""
var turn_id = ""
var phase = "unbound"
var status_text = ""
var token: Dictionary = {}
var offered_refs: Array = []
var scene: Dictionary = {}
var known_ids: Array = []
var player_text = ""
var proposal: Dictionary = {}
var proposal_request_id = ""
var approval: Dictionary = {}
var receipt: Dictionary = {}
var candidate: Dictionary = {}
var geography: Dictionary = {}
var attempt: Dictionary = {}
var generation = 0

func make_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

func fail(message: String) -> Dictionary:
	return {"ok":false,"error":message}

func set_phase(next: String, message: String = "") -> void:
	phase=next
	status_text=message
	state_changed.emit(view_state())

# Public projection never exposes a candidate, raw provider error or private token.
func view_state() -> Dictionary:
	return {"campaign_id":campaign_id,"actor_id":actor_id,"turn_id":turn_id,"phase":phase,"status_text":status_text,"mechanical_summary":RAW.summary(receipt) if not receipt.is_empty() else "","retry_allowed":phase in ["rules_failed","mechanics_retry","pending_narration","narration_failed","geography_failed","reconcile_pending"]}

func retire() -> void:
	generation+=1
	attempt={}
	var old = transport
	transport=null
	if is_instance_valid(old):
		if old.has_method("cancel_generation"):
			old.call("cancel_generation")
		old.queue_free()

func _exit_tree() -> void:
	# Late callbacks can never mutate a departed screen. Committed receipts remain.
	retire()

func reset_turn() -> void:
	turn_id=""
	token={}
	offered_refs=[]
	scene={}
	known_ids=[]
	player_text=""
	proposal={}
	proposal_request_id=""
	approval={}
	receipt={}
	candidate={}
	geography={}

# Explicit trusted binding; not a map-tab or startup migration.
func bind_campaign(id: String) -> Dictionary:
	if not is_inside_tree() or not DTO.id_valid(id):
		return fail("Bind a valid campaign from a live controller.")
	if not resolver.unresolved.is_empty() or phase=="mechanics_retry":
		return fail("Reconcile the outstanding mechanical receipt before switching.")
	retire()
	reset_turn()
	campaign_id=""
	actor_id=""
	var migrated = MIGRATION.new().ensure(id)
	if not migrated.get("ok",false):
		set_phase("unbound","Campaign world migration unavailable.")
		return migrated
	var current = store.snapshot(id)
	if not current.get("ok",false):
		set_phase("unbound","Campaign snapshot unavailable.")
		return current
	campaign_id=id
	actor_id=current["actor_id"]
	token=current
	if current["pending_turn_id"]!=null:
		turn_id=current["pending_turn_id"]
		return restore_pending()
	set_phase("idle","Ready for a supported action.")
	return {"ok":true}

func refresh_scene(current: Dictionary) -> Dictionary:
	var dm = world.dm_geography(campaign_id)
	var visible = world.map_view(campaign_id,0,128)
	var result = PACK.public_world(current,dm,visible)
	if result.get("ok",false):
		scene=result["scene"]
		known_ids=result["ids"]
	return result

# Player submission does not spend dice or persist a player turn.
func submit(text: String) -> Dictionary:
	if phase not in ["idle","clarification","unsupported","rules_failed"] or campaign_id.is_empty() or not DTO.bounded_text(text,2000):
		return fail("No available turn or invalid player action.")
	if not resolver.unresolved.is_empty():
		return fail("An earlier mechanical receipt is unresolved.")
	var current = store.snapshot(campaign_id)
	if not current.get("ok",false) or current.get("actor_id")!=actor_id:
		return fail("Campaign or actor changed. Rebind.")
	if current["pending_turn_id"]!=null:
		reset_turn()
		token=current
		turn_id=current["pending_turn_id"]
		return restore_pending()
	reset_turn()
	token=current
	turn_id=make_id()
	player_text=text.strip_edges()
	return start_rules()

func start_rules() -> Dictionary:
	var latest = store.snapshot(campaign_id)
	if not latest.get("ok",false) or not store.matching_token(token,latest):
		set_phase("clarification","Campaign changed; submit the action again.")
		return fail(status_text)
	var context = refresh_scene(token)
	var rules = PACK.rule_context(token,resolver.cat)
	if not context.get("ok",false) or not rules.get("ok",false):
		set_phase("rules_failed","Relevant world or rules context is unavailable.")
		return fail(status_text)
	offered_refs=rules["refs"]
	var expected = PACK.identity(token,turn_id,make_id())
	var prompt = PACK.rules_prompt(expected,player_text,PACK.actor_projection(token),scene,rules["records"])
	return send("rules",expected,prompt,PACK.action_schema(expected),0.1)

# A separate node and generation/identity per attempt. No automatic model
# switching; current selected model and API key are read by the existing client.
func send(stage: String, expected: Dictionary, prompt: String, schema: Dictionary, temperature: float) -> Dictionary:
	if not is_inside_tree() or prompt.length()>120000 or schema.is_empty():
		set_phase(stage+"_failed","Request exceeds the bounded context or is unavailable.")
		return fail(status_text)
	retire()
	var source = provider_factory.call() if provider_factory.is_valid() else GEMINI.new()
	if not source is Node or not source.has_signal("completed") or not source.has_method("generate"):
		set_phase(stage+"_failed","Provider unavailable.")
		return fail(status_text)
	transport=source
	add_child(source)
	attempt={"stage":stage,"identity":expected.duplicate(true),"generation":generation}
	var epoch = generation
	source.completed.connect(received.bind(source,epoch))
	set_phase(stage+"_pending","Requesting "+stage+" from Gemini…")
	if transport!=source or generation!=epoch:
		return fail("Request canceled.")
	source.generate(prompt,"","",true,schema,65536,8192,temperature)
	return {"ok":true,"request_id":expected["request_id"]}

func received(ok: bool, message: String, source: Node, epoch: int) -> void:
	if not is_inside_tree() or source!=transport or epoch!=generation or attempt.is_empty():
		return
	var frozen = attempt.duplicate(true)
	retire()
	var stage = str(frozen["stage"])
	var expected: Dictionary = frozen["identity"]
	if phase!=stage+"_pending" or expected["campaign_id"]!=campaign_id or expected["actor_id"]!=actor_id or expected["turn_id"]!=turn_id:
		return
	var latest = store.snapshot(campaign_id)
	if not latest.get("ok",false) or latest.get("actor_id")!=actor_id or latest.get("revision")!=expected["expected_revision"] or not store.matching_token(token,latest):
		set_phase(stage+"_failed","Campaign changed during request. Reload before retry.")
		return
	if not ok or message.length()>65536:
		set_phase(stage+"_failed","Gemini request failed. Saved state is unchanged; retry or select a compatible model.")
		return
	var parsed = JSON.parse_string(message)
	if not PACK.identity_matches(parsed,expected):
		set_phase(stage+"_failed","Invalid or mismatched provider reply.")
		return
	match stage:
		"rules":
			var verified = resolver.validate_proposal(token,expected["request_id"],turn_id,parsed,offered_refs)
			if not verified.get("ok",false):
				var status = str(verified.get("status","invalid"))
				if status in ["clarification","unsupported"]:
					# Model clarification is a question only, not a committed log.
					set_phase(status,str(verified.get("error","Clarify the action.")))
				else:
					set_phase("rules_failed","Rejected invalid action proposal.")
				return
			var action: Dictionary = verified["action"]
			if action["handler_id"] in ["move","travel"]:
				var args = action["arguments"]
				var found = false
				for route in scene["routes"]:
					if route["id"]==args["route_id"] and args["destination_id"] in [route["from_id"],route["to_id"]] and args["destination_id"]!=token["location_id"]:
						found=true
				if not found:
					set_phase("clarification","Choose a known visible destination and route.")
					return
			proposal=parsed.duplicate(true)
			proposal_request_id=expected["request_id"]
			set_phase("awaiting_local_approval","Confirm interpreted intent and supply a verified local ruling.")
		"narration":
			if latest.get("pending_turn_id")!=turn_id or not PACK.valid_narration(parsed,expected):
				set_phase("narration_failed","Narration did not match the committed receipt.")
				return
			candidate=parsed.duplicate(true)
			start_geography()
		"geography":
			if latest.get("pending_turn_id")!=turn_id or not PACK.valid_geography(parsed,expected,candidate.get("text",""),known_ids):
				set_phase("geography_failed","Geographical proposal rejected. No narrative or geography saved.")
				return
			geography=parsed.duplicate(true)
			set_phase("reconcile_pending","Candidate narration and geography await trusted review/B4 reconciliation.")

# Read only by a trusted local adjudication adapter, never a provider tool.
func approval_request() -> Dictionary:
	if phase!="awaiting_local_approval":
		return {}
	return {"campaign_id":campaign_id,"actor_id":actor_id,"turn_id":turn_id,"expected_revision":token["revision"],"player_text":player_text,"action":proposal["actions"][0].duplicate(true)}

# Caller must independently confirm player intent and ruling; matching shape
# alone is NOT proof. Never synthesize the ruling from a model response.
func approve(local_approval: Dictionary) -> Dictionary:
	if phase!="awaiting_local_approval" or not resolver.approval_valid(token,turn_id,proposal["actions"][0],local_approval):
		return fail("Trusted local adjudication required.")
	approval=local_approval.duplicate(true)
	return resolve_local()

func resolve_local() -> Dictionary:
	# No network or speculative prepare in this phase.
	set_phase("mechanics_resolving","Resolving verified local action.")
	var result = resolver.resolve(campaign_id,token,proposal_request_id,turn_id,proposal,offered_refs,approval,player_text)
	if not result.get("ok",false):
		# Keep exact proposal and approval for acknowledgement retry; never
		# permit a new logical turn before lookup proves what happened.
		set_phase("mechanics_retry",str(result.get("error","Mechanical resolution unavailable.")))
		return result
	# Even a success reply is read back from SQLite before a narrator request.
	return restore_pending(true)

func restore_pending(auto_request: bool = false) -> Dictionary:
	var prior = store.receipt_by_id(campaign_id,turn_id)
	if not prior.get("ok",false) or not prior.get("found",false):
		set_phase("mechanics_retry","Receipt not yet confirmed. Retry lookup, not a new action.")
		return fail(status_text)
	var current = store.snapshot(campaign_id)
	if not current.get("ok",false) or current.get("actor_id")!=actor_id:
		set_phase("pending_narration","Receipt exists; reload campaign before narration.")
		return fail(status_text)
	if prior["receipt"]["actor_id"]!=actor_id:
		set_phase("pending_narration","Receipt actor mismatch.")
		return fail(status_text)
	receipt=prior["receipt"].duplicate(true)
	player_text=str(prior.get("player_text",""))
	token=current
	if prior.get("narration_event_id")!=null:
		if current["pending_turn_id"]==null:
			set_phase("idle","Turn already narrated.")
			return {"ok":true,"replayed":true}
		set_phase("pending_narration","Another committed turn is pending; rebind.")
		return fail(status_text)
	if current["pending_turn_id"]!=turn_id or current["revision"]!=receipt["next_revision"]:
		set_phase("pending_narration","Pending receipt revision changed; rebind before narrating.")
		return fail(status_text)
	set_phase("pending_narration","Mechanics committed. Narration can be retried without reroll.")
	if auto_request and phase=="pending_narration":
		return start_narration()
	return {"ok":true}

func start_narration() -> Dictionary:
	var restored = restore_pending()
	if not restored.get("ok",false) or phase!="pending_narration":
		return restored
	var context = refresh_scene(token)
	if not context.get("ok",false):
		set_phase("narration_failed","Persistent world context unavailable. Receipt retained.")
		return context
	candidate={}
	geography={}
	var expected = PACK.identity(token,turn_id,make_id())
	var maturity = str(token["campaign"].get("maturity_id","standard"))
	return send("narration",expected,PACK.narration_prompt(expected,maturity,PACK.public_receipt(receipt),scene,player_text),PACK.narration_schema(expected),0.8)

func start_geography() -> Dictionary:
	var latest = store.snapshot(campaign_id)
	if candidate.is_empty() or not latest.get("ok",false) or not store.matching_token(token,latest) or latest["pending_turn_id"]!=turn_id:
		set_phase("geography_failed","Narrative candidate is stale or missing.")
		return fail(status_text)
	var expected = PACK.identity(token,turn_id,make_id())
	return send("geography",expected,PACK.geography_prompt(expected,candidate["text"],scene),PACK.geo_schema(expected),0.1)

# B4 consumes this private bundle. Neither proposal nor candidate is displayed
# as canon. B4 must reconcile against current revision and atomically persist
# accepted facts + narration. The source event ID is assigned in that transaction.
func reconciliation_bundle() -> Dictionary:
	if phase!="reconcile_pending" or candidate.is_empty() or geography.is_empty():
		return {}
	return {"campaign_id":campaign_id,"actor_id":actor_id,"turn_id":turn_id,"expected_revision":token["revision"],"receipt":receipt.duplicate(true),"narration":candidate.duplicate(true),"geography":geography.duplicate(true)}

# Interim B3 text-only boundary. Explicit trusted review must verify prose
# against receipt, established world and audience. Nonempty geography cannot
# be accepted here: B4 owns atomic fact/narration reconciliation.
func accept_reviewed_text(bundle: Dictionary) -> Dictionary:
	var current = reconciliation_bundle()
	if current.is_empty() or bundle!=current or not geography["facts"].is_empty():
		return fail("Exact reviewed text-only bundle required; geography requires B4.")
	var result = store.commit_narration(campaign_id,turn_id,token["revision"],candidate["text"])
	return confirm_reconciled() if result.get("ok",false) else check_narration_ack(result)

func check_narration_ack(failure: Dictionary) -> Dictionary:
	var prior = store.receipt_by_id(campaign_id,turn_id)
	if prior.get("ok",false) and prior.get("found",false) and prior.get("narration_event_id")!=null:
		return confirm_reconciled()
	set_phase("reconcile_pending","Narration not confirmed; receipt retained.")
	return failure

# B4 calls after its guarded transaction. Verify persisted acknowledgement.
func confirm_reconciled() -> Dictionary:
	var prior = store.receipt_by_id(campaign_id,turn_id)
	var current = store.snapshot(campaign_id)
	if not prior.get("ok",false) or not prior.get("found",false) or prior.get("narration_event_id")==null or not current.get("ok",false) or current["pending_turn_id"]!=null or current["actor_id"]!=actor_id:
		return fail("Narration commit not confirmed.")
	candidate={}
	geography={}
	token=current
	set_phase("idle","Turn committed and narrated.")
	return {"ok":true,"revision":current["revision"]}

func retry() -> Dictionary:
	match phase:
		"rules_failed":
			return start_rules()
		"mechanics_retry":
			var prior = store.receipt_by_id(campaign_id,turn_id)
			if not prior.get("ok",false):
				return prior
			if prior.get("found",false):
				return restore_pending(true)
			if proposal.is_empty() or approval.is_empty():
				return fail("No locally approved action to retry; rebind or abandon.")
			return resolve_local()
		"pending_narration","narration_failed":
			return start_narration()
		"geography_failed":
			return start_geography()
		"reconcile_pending":
			return confirm_reconciled()
	return fail("No retry available.")

# Cancel never abandons an unresolved prepared roll or committed receipt.
func cancel() -> Dictionary:
	if phase in ["mechanics_resolving","mechanics_retry"] or not resolver.unresolved.is_empty():
		return fail("Reconcile the mechanical receipt before cancellation.")
	retire()
	if campaign_id.is_empty():
		return {"ok":true}
	var current = store.snapshot(campaign_id)
	if not current.get("ok",false):
		set_phase("pending_narration","Reload campaign to determine saved state.")
		return current
	if current["pending_turn_id"]!=null:
		reset_turn()
		token=current
		turn_id=current["pending_turn_id"]
		return restore_pending()
	reset_turn()
	token=current
	set_phase("idle","Uncommitted request canceled.")
	return {"ok":true}

func abandon_uncommitted() -> Dictionary:
	if phase!="mechanics_retry":
		return fail("No unresolved local action.")
	var prior = store.receipt_by_id(campaign_id,turn_id)
	if not prior.get("ok",false):
		return prior
	if prior.get("found",false):
		return restore_pending()
	if resolver.unresolved.has(campaign_id):
		var abandoned = resolver.abandon_uncommitted(campaign_id,turn_id)
		if not abandoned.get("ok",false):
			return abandoned
	reset_turn()
	set_phase("idle","Uncommitted action abandoned; no receipt existed.")
	return {"ok":true}
