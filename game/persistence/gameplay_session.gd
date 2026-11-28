extends RefCounted
## Trusted local persistence service. No provider-facing generic SQL endpoint.
## All C2 writes use one canonical world revision and durable request settlement.
const SQL = preload("res://systems/sqlite.gd")
const BASE = preload("res://campaigns/campaign_store.gd")
const TURN = preload("res://turns/turn_store.gd")
const WORLD = preload("res://world/world_store.gd")
const DTO = preload("res://world/world_dto.gd")
const UI = preload("res://gameplay/ui_intents.gd")
const EVENT = "(SELECT event_id FROM gameplay_requests WHERE request_id=?)"
const VERSION = "2"
# Local trusted adapter only. Default C2 administrative operations take no time.
var action_seconds: int = 0

func fail(message: String) -> Dictionary:
	return {"ok":false,"error":message}

func make_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

func path(id: String) -> String:
	return BASE.new().path_for(id)

func token(id: String) -> Dictionary:
	return TURN.new().snapshot(id,true)

func read(state: Dictionary, statements: Array) -> Dictionary:
	return WORLD.new().read_sets(state,statements)

func request_valid(request: Variant,version: String = VERSION) -> bool:
	return DTO.exact_keys(request,["schema_version","campaign_id","actor_id","expected_revision","request_id","kind","args"]) and request["schema_version"]==version and DTO.id_valid(request["campaign_id"]) and DTO.id_valid(request["actor_id"]) and DTO.id_valid(request["request_id"]) and DTO.whole(request["expected_revision"],0,DTO.MAX_INT-2) and DTO.bounded_text(request["kind"],80) and request["args"] is Dictionary and json_safe(request) and JSON.stringify(request,"",true,true).length()<=65536

# Compare requests in the same JSON representation used by durable storage.
# Godot JSON decodes numbers as floats, including nested integer operands.
func same_request(a: Dictionary,b: Dictionary) -> bool:
	var left = JSON.new()
	var right = JSON.new()
	if not request_valid(a,str(a.get("schema_version",""))) or not request_valid(b,str(b.get("schema_version",""))):
		return false
	if not a["schema_version"] in ["1","2"] or not b["schema_version"] in ["1","2"]:
		return false
	if not json_safe(a) or not json_safe(b):
		return false
	if left.parse(JSON.stringify(a,"",true,true))!=OK or right.parse(JSON.stringify(b,"",true,true))!=OK:
		return false
	return left.data is Dictionary and right.data is Dictionary and left.data==right.data

# Reject values that JSON cannot represent losslessly as request operands.
func json_safe(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_INT, TYPE_FLOAT:
			return is_finite(float(value)) and absf(float(value))<=9007199254740991.0
		TYPE_ARRAY:
			for item in value:
				if not json_safe(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if not key is String or not json_safe(value[key]):
					return false
			return true
	return false

func settlement(id: String,request_id: String) -> Dictionary:
	if not DTO.id_valid(request_id):
		return fail("Invalid request identity.")
	var state = token(id)
	if not state.get("ok",false):
		return state
	var readback = read(state,[SQL.stmt("SELECT * FROM gameplay_requests WHERE request_id=? AND actor_id=?",[request_id,state["actor_id"]])])
	if not readback.get("ok",false):
		return readback
	if readback["sets"][0].is_empty():
		return {"ok":true,"found":false}
	var row: Dictionary = readback["sets"][0][0]
	var request = JSON.parse_string(row["request_payload"])
	var result = JSON.parse_string(row["result_payload"])
	if not (request_valid(request,"1") or request_valid(request,"2")) or not result is Dictionary or request["request_id"]!=request_id or request["campaign_id"]!=id or request["actor_id"]!=state["actor_id"] or request["kind"]!=row["kind"]:
		return fail("Corrupt request settlement.")
	# The persisted request and its relational settlement must agree. A failed
	# read is not evidence of absence and cannot authorize replay or another roll.
	var expected_revision = DTO.sql_int(row["expected_revision"])
	var settled_revision = DTO.sql_int(row["settled_revision"])
	var event_id = DTO.sql_int(row["event_id"])
	var logical = row["logical_turn_id"]
	var status = row["status"]
	if expected_revision==null or expected_revision!=request["expected_revision"] or settled_revision==null or settled_revision<expected_revision or settled_revision>state["revision"] or (logical!=null and not DTO.id_valid(logical)) or not status in ["accepted_pending","committed","rejected","cancelled"]:
		return fail("Request settlement revision or identity mismatch.")
	if status=="accepted_pending" and (logical==null or settled_revision!=expected_revision or row["event_id"]!=null):
		return fail("Invalid pending request settlement.")
	if status=="committed" and (event_id==null or event_id<1 or (logical!=null and (result.get("turn_id")!=logical or result.get("narration_event_id")!=event_id))):
		return fail("Committed request provenance mismatch.")
	if status in ["rejected","cancelled"] and row["event_id"]!=null:
		return fail("Invalid terminal request settlement.")
	return {"ok":true,"found":true,"request":request,"status":status,"logical_turn_id":logical,"revision":settled_revision,"event_id":event_id,"result":result}

# All mutations are only called with locally validated, already adjudicated
# requests. Merely constructing an envelope does not establish authorization.
func begin(id: String,request: Dictionary,kind: String,fields: Array) -> Dictionary:
	if not request_valid(request) or request["campaign_id"]!=id or request["kind"]!=kind or not DTO.exact_keys(request["args"],fields):
		return fail("Invalid C2 request envelope.")
	var state = token(id)
	if not state.get("ok",false):
		return state
	if request["actor_id"]!=state["actor_id"]:
		return fail("Wrong controlled actor.")
	var prior = settlement(id,request["request_id"])
	if not prior.get("ok",false):
		return prior
	if prior.get("found",false):
		if not same_request(prior["request"],request):
			return fail("Request ID already used with different arguments.")
		return {"ok":true,"replayed":true,"settlement":prior,"result":prior["result"]}
	if state["revision"]!=request["expected_revision"] or state["pending_turn_id"]!=null:
		return fail("Stale revision or committed narration pending.")
	var busy = read(state,[SQL.stmt("SELECT request_id FROM gameplay_requests WHERE status='accepted_pending' LIMIT 1")])
	if not busy.get("ok",false) or not busy["sets"][0].is_empty():
		return fail("Another request is pending.")
	return {"ok":true,"state":state,"request":request}

func source(state: Dictionary,event_id: Variant) -> Dictionary:
	if not DTO.whole(event_id,1):
		return {}
	var r = read(state,[SQL.stmt("SELECT id,kind,turn,payload FROM events WHERE id=?",[int(event_id)])])
	if not r.get("ok",false) or r["sets"][0].size()!=1:
		return {}
	var row: Dictionary = r["sets"][0][0]
	row["data"]=JSON.parse_string(row["payload"])
	return row if row["data"] is Dictionary else {}

func public_source(event: Dictionary) -> bool:
	var data = event.get("data",{})
	return event.get("kind") in ["campaign_created","narration","mechanical_receipt","gameplay_change"] and data is Dictionary and data.get("visibility","player")=="player"

# Private helper, commands are built ONLY by reviewed local code. No external
# request accepts SQL, actor patches or raw effects.
func _commit(context: Dictionary,commands: Array,result_data: Dictionary,message: String,visibility: String = "player") -> Dictionary:
	var state: Dictionary = context["state"]
	var request: Dictionary = context["request"]
	var id = state["campaign_id"]
	var rid = request["request_id"]
	if not visibility in ["player","private"] or not DTO.bounded_text(message,4000) or not DTO.whole(state["revision"],0,DTO.MAX_INT-2):
		return fail("Invalid local event.")
	var turn = TURN.new()
	var batch: Array = [turn.guard(state)]
	batch.append_array(turn.inventory_guards(state))
	batch.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('c2_request_guard',(SELECT 'ok' WHERE EXISTS(SELECT 1 FROM meta WHERE key='gameplay_schema' AND value='1') AND NOT EXISTS(SELECT 1 FROM gameplay_requests WHERE status='accepted_pending' OR request_id=?)))",[rid]))
	if not DTO.whole(action_seconds,0,86400) or (state["elapsed_seconds"]!=null and not DTO.whole(int(state["elapsed_seconds"])+action_seconds)):
		return fail("Invalid deterministic action duration.")
	var elapsed = null if state["elapsed_seconds"]==null else int(state["elapsed_seconds"])+action_seconds
	var game_time = "Unspecified" if elapsed==null else "Elapsed "+str(elapsed)+" seconds (tracked epoch)"
	if action_seconds>0:
		result_data=result_data.duplicate(true)
		result_data["elapsed_seconds"]=action_seconds
	batch.append(SQL.stmt("INSERT INTO events(turn,game_time,kind,payload) VALUES(?,?,'gameplay_change',?)",[state["turn"],game_time,JSON.stringify({"request_id":rid,"kind":request["kind"],"text":message,"visibility":visibility,"location_id":state["location_id"]})]))
	batch.append(SQL.stmt("INSERT INTO gameplay_requests(request_id,actor_id,kind,expected_revision,status,request_payload,result_payload,settled_revision,event_id) VALUES(?,?,?,?,'committed',?,?,?,last_insert_rowid())",[rid,state["actor_id"],request["kind"],state["revision"],JSON.stringify(request,"",true,true),JSON.stringify(result_data,"",true,true),state["revision"]+1]))
	batch.append_array(commands)
	batch.append(SQL.stmt("UPDATE world_state SET revision=revision+1,elapsed_seconds=? WHERE campaign_id=?",[elapsed,id]))
	batch.append(SQL.stmt("DELETE FROM meta WHERE key='c2_request_guard'"))
	batch.append(SQL.stmt("DELETE FROM meta WHERE key='turn_write_guard'"))
	var saved = SQL.run(path(id),batch)
	if not saved.get("ok",false):
		var prior = settlement(id,rid)
		if prior.get("found",false) and same_request(prior["request"],request) and prior["status"]=="committed":
			return {"ok":true,"replayed":true,"result":prior["result"],"revision":prior["revision"]}
		return fail("Transaction rejected or unconfirmed; look up request before retry.")
	var confirmed=settlement(id,rid)
	if not confirmed.get("found",false) or not same_request(confirmed["request"],request) or confirmed["status"]!="committed":
		return fail("Transaction acknowledged but settlement readback unavailable; recover by request ID. "+str(confirmed.get("error","Request identity or status mismatch.")))
	return {"ok":true,"replayed":false,"result":confirmed["result"],"revision":confirmed["revision"],"event_id":confirmed["event_id"]}

# C3/C4 durable adoption only. A local controller must first validate the exact
# v1 intent and assign a logical turn. This does not run mechanics or narrate.
func adopt(id: String,request: Dictionary,turn_id: String) -> Dictionary:
	if not request_valid(request,"1") or not UI.FIELDS.has(request["kind"]) or not DTO.exact_keys(request["args"],UI.FIELDS[request["kind"]]) or request["kind"] in ["retry","cancel"]:
		return fail("Invalid local adoption.")
	return _adopt(id,request,turn_id)

# C3 registry calls this only after exact semantic tool validation. This is
# not a generic provider endpoint or proof of player intent.
func adopt_tool(id: String,request: Dictionary,turn_id: String) -> Dictionary:
	if not request_valid(request) or not request["kind"] in ["ability_check","skill_check","saving_throw","observe","conversation","wait","move","travel","object_check"]:
		return fail("Not a registered adopted mechanical action.")
	return _adopt(id,request,turn_id)

func _adopt(id: String,request: Dictionary,turn_id: String) -> Dictionary:
	if request["campaign_id"]!=id or not DTO.id_valid(turn_id):
		return fail("Invalid adoption identity.")
	var state = token(id)
	if not state.get("ok",false) or request["actor_id"]!=state.get("actor_id"):
		return fail("Campaign or actor unavailable.")
	var prior = settlement(id,request["request_id"])
	if not prior.get("ok",false):
		return prior
	if prior.get("found",false):
		return prior if same_request(prior["request"],request) and prior["logical_turn_id"]==turn_id else fail("Request already bound.")
	if state["revision"]!=request["expected_revision"] or state["pending_turn_id"]!=null:
		return fail("Cannot adopt stale or pending request.")
	var batch = [TURN.new().guard(state),SQL.stmt("INSERT INTO meta(key,value) VALUES('c2_adopt_guard',(SELECT 'ok' WHERE NOT EXISTS(SELECT 1 FROM gameplay_requests WHERE status='accepted_pending' OR logical_turn_id=?) AND NOT EXISTS(SELECT 1 FROM turn_receipts WHERE turn_id=?)))",[turn_id,turn_id]),SQL.stmt("INSERT INTO gameplay_requests(request_id,actor_id,kind,expected_revision,logical_turn_id,status,request_payload,result_payload,settled_revision) VALUES(?,?,?,?,?,'accepted_pending',?,'{}',?)",[request["request_id"],state["actor_id"],request["kind"],state["revision"],turn_id,JSON.stringify(request,"",true,true),state["revision"]]),SQL.stmt("DELETE FROM meta WHERE key='c2_adopt_guard'"),SQL.stmt("DELETE FROM meta WHERE key='turn_write_guard'")]
	var saved = SQL.run(path(id),batch)
	var confirmed = settlement(id,request["request_id"])
	if confirmed.get("found",false) and same_request(confirmed["request"],request) and confirmed["logical_turn_id"]==turn_id:
		return confirmed
	return fail("Adoption not confirmed; reconcile request before resolving.") if not saved.get("ok",false) else fail("Adoption readback unavailable.")

func adoption_binding(id: String,request_id: String,turn_id: String) -> Dictionary:
	var prior = settlement(id,request_id)
	if not prior.get("found",false) or prior["status"]!="accepted_pending" or prior["logical_turn_id"]!=turn_id:
		return fail("Exact pending adoption unavailable.")
	var state = token(id)
	if not state.get("ok",false):
		return state
	var result = read(state,[SQL.stmt("SELECT request_payload FROM gameplay_requests WHERE request_id=? AND status='accepted_pending' AND logical_turn_id=?",[request_id,turn_id])])
	if not result.get("ok",false) or result["sets"][0].size()!=1:
		return fail("Adoption readback changed.")
	return {"ok":true,"binding":{"request_id":request_id,"request_payload":result["sets"][0][0]["request_payload"]}}

# Receipt-backed final settlement; no second outcome or revision increment.
# Cancellation/rejection is only permitted after the trusted controller proves
# there is no prepared/ambiguous receipt in memory, and durable SQL agrees.
func settle_adopted(id: String,request_id: String,status: String,local_no_prepared: bool = false) -> Dictionary:
	if not status in ["committed","rejected","cancelled"]:
		return fail("Invalid settlement status.")
	var prior = settlement(id,request_id)
	if not prior.get("found",false):
		return fail("Adopted request unavailable.")
	if prior["status"]!="accepted_pending":
		return prior if prior["status"]==status else fail("Terminal settlement is immutable.")
	var state = token(id)
	if not state.get("ok",false) or not DTO.id_valid(prior["logical_turn_id"]):
		return fail("Adopted turn unavailable.")
	var turn_id = prior["logical_turn_id"]
	var event_id: Variant = null
	var receipt = TURN.new().receipt_by_id(id,turn_id)
	if not receipt.get("ok",false):
		return receipt
	var result_data: Dictionary = {}
	if status=="committed":
		if not receipt.get("found",false) or receipt.get("narration_event_id")==null or state["pending_turn_id"]!=null or receipt["receipt"]["prior_revision"]!=prior["request"]["expected_revision"]:
			return fail("Committed narrated receipt not established.")
		event_id=receipt["narration_event_id"]
		result_data={"turn_id":turn_id,"narration_event_id":event_id}
	elif not local_no_prepared or receipt.get("found",false) or state["pending_turn_id"]!=null:
		return fail("Cannot discard a prepared or committed outcome.")
	var batch = [TURN.new().guard(state),SQL.stmt("INSERT INTO meta(key,value) VALUES('c2_settle_guard',(SELECT 'ok' FROM gameplay_requests WHERE request_id=? AND logical_turn_id=? AND status='accepted_pending' AND actor_id=?))",[request_id,turn_id,state["actor_id"]])]
	if status=="committed":
		batch.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('c2_receipt_guard',(SELECT 'ok' FROM turn_narrations WHERE turn_id=? AND event_id=?))",[turn_id,event_id]))
	else:
		batch.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('c2_receipt_guard',(SELECT 'ok' WHERE NOT EXISTS(SELECT 1 FROM turn_receipts WHERE turn_id=?)))",[turn_id]))
	batch.append(SQL.stmt("UPDATE gameplay_requests SET status=?,result_payload=?,settled_revision=?,event_id=? WHERE request_id=?",[status,JSON.stringify(result_data,"",true,true),state["revision"],event_id,request_id]))
	for key in ["c2_settle_guard","c2_receipt_guard","turn_write_guard"]:
		batch.append(SQL.stmt("DELETE FROM meta WHERE key=?",[key]))
	SQL.run(path(id),batch)
	var confirmed = settlement(id,request_id)
	return confirmed if confirmed.get("found",false) and confirmed["status"]==status else fail("Settlement not confirmed; retry lookup.")


# Successful idempotent identity reuse with a NEW request ID still gets a
# durable settlement, but does not create a false narrative event or revision.
func _reuse(ctx: Dictionary,result_data: Dictionary,event_id: Variant) -> Dictionary:
	var state: Dictionary = ctx["state"]
	var request: Dictionary = ctx["request"]
	if not DTO.whole(event_id,1) or source(state,event_id).is_empty():
		return fail("Reuse provenance unavailable.")
	var batch = [TURN.new().guard(state),SQL.stmt("INSERT INTO meta(key,value) VALUES('c2_reuse_guard',(SELECT 'ok' WHERE NOT EXISTS(SELECT 1 FROM gameplay_requests WHERE status='accepted_pending' OR request_id=?)))",[request["request_id"]]),SQL.stmt("INSERT INTO gameplay_requests(request_id,actor_id,kind,expected_revision,status,request_payload,result_payload,settled_revision,event_id) VALUES(?,?,?,?,'committed',?,?,?,?)",[request["request_id"],state["actor_id"],request["kind"],state["revision"],JSON.stringify(request,"",true,true),JSON.stringify(result_data,"",true,true),state["revision"],int(event_id)]),SQL.stmt("DELETE FROM meta WHERE key='c2_reuse_guard'"),SQL.stmt("DELETE FROM meta WHERE key='turn_write_guard'")]
	SQL.run(path(state["campaign_id"]),batch)
	var prior = settlement(state["campaign_id"],request["request_id"])
	if prior.get("found",false) and same_request(prior["request"],request) and prior["status"]=="committed":
		return {"ok":true,"replayed":true,"result":prior["result"],"revision":prior["revision"]}
	return fail("Reuse settlement not confirmed.")
