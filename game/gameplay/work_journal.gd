extends RefCounted
## C4 local orchestration journal in existing campaign meta. No canon revision
## change, no provider access, no new schema. CAS against exact previous bytes.
const SESSION=preload("res://persistence/gameplay_session.gd")
const TURN=preload("res://turns/turn_store.gd")
const SQL=preload("res://systems/sqlite.gd")
const DTO=preload("res://world/world_dto.gd")
const KEY="c4_work_v1"
var session=SESSION.new()

func empty(state: Dictionary) -> Dictionary:
	return {"version":"1","campaign_id":state["campaign_id"],"actor_id":state["actor_id"],"active":{},"queued":{},"last":{},"history":[],"draft":""}

func read(id: String) -> Dictionary:
	var state=session.token(id)
	if not state.get("ok",false):
		return state
	var rows=session.read(state,[SQL.stmt("SELECT value FROM meta WHERE key=?",[KEY])])
	if not rows.get("ok",false):
		return rows
	var raw: Variant=null
	var work=empty(state)
	if not rows["sets"][0].is_empty():
		raw=rows["sets"][0][0]["value"]
		var parsed=JSON.parse_string(raw)
		if not DTO.exact_keys(parsed,work.keys()) or parsed["version"]!="1" or parsed["campaign_id"]!=id or parsed["actor_id"]!=state["actor_id"] or not parsed["active"] is Dictionary or not parsed["queued"] is Dictionary or not parsed["last"] is Dictionary or not parsed["history"] is Array or parsed["history"].size()>64 or not parsed["draft"] is String or parsed["draft"].length()>2000 or raw.length()>400000:
			return session.fail("Invalid local work journal; preserve save for review.")
		work=parsed
		for slot in ["active","queued"]:
			if work[slot].is_empty():
				continue
			var intent=work[slot].get("intent")
			if not (session.request_valid(intent,"1") or session.request_valid(intent,"2")) or intent["campaign_id"]!=id or intent["actor_id"]!=state["actor_id"]:
				return session.fail("Work journal identity invalid.")
			if not work[slot].get("stage") in ["new","interpret","execute","narrate","critical","background","reconcile","post_story","retry","clarification","critical_blocked"] or not work[slot].get("tool") is Dictionary or not work[slot].get("attempt") is Dictionary:
				return session.fail("Invalid durable work phase.")
	return {"ok":true,"state":state,"raw":raw,"work":work}

func write(id: String,expected: Dictionary,work: Dictionary) -> Dictionary:
	var state: Dictionary=expected["state"]
	var raw=JSON.stringify(work)
	if state["campaign_id"]!=id or work.get("campaign_id")!=id or work.get("actor_id")!=state["actor_id"] or raw.length()>400000:
		return session.fail("Invalid bounded journal write.")
	var commands=[TURN.new().guard(state),SQL.stmt("INSERT INTO meta(key,value) VALUES('c4_journal_guard',(SELECT 'ok' WHERE (SELECT value FROM meta WHERE key=?) IS ?))",[KEY,expected["raw"]]),SQL.stmt("INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",[KEY,raw]),SQL.stmt("DELETE FROM meta WHERE key='c4_journal_guard'"),SQL.stmt("DELETE FROM meta WHERE key='turn_write_guard'")]
	SQL.run(session.path(id),commands)
	var confirmed=read(id)
	if confirmed.get("ok",false) and confirmed["raw"]==raw:
		return confirmed
	return session.fail("Work journal not confirmed; reload before continuing.")
