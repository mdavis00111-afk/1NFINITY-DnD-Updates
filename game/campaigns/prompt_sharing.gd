extends RefCounted
## Offline prompt-only handover. No Git credentials, network, or config export.
const NARRATOR=preload("res://campaigns/narrator_prompt.gd")
const ROOT="user://prompt_sharing"
const BASE=ROOT+"/shared_base.json"
const INITIAL_COMMIT="0ddb4d650fd3582f544447f5b77e6b63aa90ab18"
const KEYS=["schema_version","role","kind","revision","base_hash","prompt_hash","prompt","source_commit","created_utc","summary"]

static func error(message: String) -> Dictionary:
	return {"ok":false,"error":message}

static func hash_valid(value: Variant,length: int) -> bool:
	if not value is String or value.length()!=length:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true

static func valid(bundle: Variant) -> bool:
	if not bundle is Dictionary or bundle.size()!=KEYS.size():
		return false
	for key in KEYS:
		if not bundle.has(key):
			return false
	return bundle["schema_version"]=="1" and bundle["role"]=="Narrator" and bundle["kind"] in ["proposal","shared"] and (bundle["revision"] is int or bundle["revision"] is float) and is_finite(float(bundle["revision"])) and floor(float(bundle["revision"]))==float(bundle["revision"]) and bundle["revision"]>=0 and bundle["revision"]<2147483647 and hash_valid(bundle["base_hash"],64) and hash_valid(bundle["prompt_hash"],64) and bundle["prompt"] is String and not bundle["prompt"].strip_edges().is_empty() and bundle["prompt"].length()<=24000 and bundle["prompt"].sha256_text()==bundle["prompt_hash"] and hash_valid(bundle["source_commit"],40) and bundle["created_utc"] is String and bundle["created_utc"].length()<=40 and bundle["summary"] is String and not bundle["summary"].strip_edges().is_empty() and bundle["summary"].length()<=500

static func initial() -> Dictionary:
	var hash=NARRATOR.DEFAULT_PROMPT.sha256_text()
	return {"schema_version":"1","role":"Narrator","kind":"shared","revision":0,"base_hash":hash,"prompt_hash":hash,"prompt":NARRATOR.DEFAULT_PROMPT,"source_commit":INITIAL_COMMIT,"created_utc":"","summary":"Pinned original Narrator guidance."}

static func read_file(path: String) -> Dictionary:
	var f=FileAccess.open(path,FileAccess.READ)
	if f==null or f.get_length()>160000:
		return error("Prompt bundle unavailable or exceeds size limit.")
	var parsed=JSON.parse_string(f.get_as_text())
	if not valid(parsed):
		return error("Invalid prompt-only bundle or hash.")
	return {"ok":true,"bundle":parsed}

static func base_record() -> Dictionary:
	if not FileAccess.file_exists(BASE):
		return {"ok":true,"bundle":initial()}
	var result=read_file(BASE)
	if not result.get("ok",false) or result["bundle"]["kind"]!="shared":
		return error("Shared base metadata invalid; preserve existing files.")
	return result

static func secret_risk(text: String) -> bool:
	# Exact saved key and common credential shapes; not a substitute for
	# human review of the prompt's personal or confidential contents.
	var config=ConfigFile.new()
	if config.load(NARRATOR.PATH)==OK:
		var key=str(config.get_value("gemini","api_key","")).strip_edges()
		if not key.is_empty() and text.contains(key):
			return true
	var regex=RegEx.new()
	regex.compile("(?i)(AIza[0-9A-Za-z_-]{20,}|gh[pousr]_[0-9A-Za-z_]{12,}|github_pat_[0-9A-Za-z_]{12,}|Bearer\\s+[0-9A-Za-z._-]{12,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)")
	return regex.search(text)!=null

static func write_unique(folder: String,prefix: String,record: Dictionary) -> Dictionary:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))!=OK:
		return error("Cannot create prompt handover folder.")
	var path=folder+"/"+prefix+"-"+Crypto.new().generate_random_bytes(12).hex_encode()+".json"
	var f=FileAccess.open(path,FileAccess.WRITE)
	if f==null:
		return error("Cannot write prompt-only file.")
	f.store_string(JSON.stringify(record,"\t"))
	f.flush()
	var result=f.get_error()
	f.close()
	return {"ok":true,"path":ProjectSettings.globalize_path(path)} if result==OK else error("Prompt-only file write failed.")

static func export_proposal(summary: String,confirmed: bool) -> Dictionary:
	if not confirmed or summary.strip_edges().is_empty() or summary.length()>500:
		return error("Explicit sharing consent and change summary required.")
	var saved=NARRATOR.load_prompt()
	if secret_risk(saved+"\n"+summary):
		return error("Credential-like content detected. Remove it before sharing.")
	var local=base_record()
	if not local.get("ok",false):
		return local
	var base=local["bundle"]
	var bundle={"schema_version":"1","role":"Narrator","kind":"proposal","revision":int(base["revision"])+1,"base_hash":base["prompt_hash"],"prompt_hash":saved.sha256_text(),"prompt":saved,"source_commit":base["source_commit"],"created_utc":Time.get_datetime_string_from_system(true)+"Z","summary":summary}
	if not valid(bundle):
		return error("Invalid prompt proposal.")
	return write_unique(ROOT+"/exports","narrator-proposal",bundle)

static func inspect_shared(path: String) -> Dictionary:
	var incoming=read_file(path)
	var current=base_record()
	if not incoming.get("ok",false):
		return incoming
	if not current.get("ok",false):
		return current
	var remote=incoming["bundle"]
	var base=current["bundle"]
	if remote["kind"]!="shared":
		return error("Lead-approved shared revision required, not an uncommitted proposal.")
	if secret_risk(remote["prompt"]+"\n"+remote["summary"]):
		return error("Credential-like content detected in imported bundle.")
	if remote["base_hash"]!=base["prompt_hash"] or remote["revision"]!=int(base["revision"])+1:
		return error("Shared base/revision conflict. Incoming file remains unchanged; Lead must reconcile ancestry.")
	var local=NARRATOR.load_prompt()
	return {"ok":true,"bundle":remote,"local_hash":local.sha256_text(),"base_hash":base["prompt_hash"],"conflict":local.sha256_text()!=base["prompt_hash"] and local.sha256_text()!=remote["prompt_hash"],"local_prompt":local}

static func apply_shared(preview: Dictionary,use_remote: bool,confirmed: bool) -> Dictionary:
	if not confirmed or not preview.get("ok",false) or not valid(preview.get("bundle")):
		return error("Explicit reviewed import required.")
	var remote=preview["bundle"]
	var current=base_record()
	var local=NARRATOR.load_prompt()
	if not current.get("ok",false) or current["bundle"]["prompt_hash"]!=preview.get("base_hash") or local.sha256_text()!=preview.get("local_hash") or remote["base_hash"]!=preview.get("base_hash") or remote["revision"]!=int(current["bundle"]["revision"])+1 or remote["kind"]!="shared":
		return error("Prompt changed since preview; reopen import.")
	# Preserve both versions locally before updating either shared metadata or
	# current prompt. The conflict archive is never an export.
	var archive=write_unique(ROOT+"/history","review",{"local_prompt":local,"previous_shared":current["bundle"],"incoming_shared":remote,"use_remote":use_remote,"reviewed_utc":Time.get_datetime_string_from_system(true)+"Z"})
	if not archive.get("ok",false):
		return archive
	if use_remote:
		var saved=NARRATOR.save_prompt(remote["prompt"])
		if not saved.is_empty():
			return error(saved)
	var temp=ROOT+"/base-"+Crypto.new().generate_random_bytes(12).hex_encode()+".tmp"
	var f=FileAccess.open(temp,FileAccess.WRITE)
	if f==null:
		return error("Prompt variants preserved; shared base update unavailable.")
	f.store_string(JSON.stringify(remote,"\t"))
	f.flush()
	var write_error=f.get_error()
	f.close()
	if write_error!=OK or DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(BASE))!=OK:
		return error("Prompt variants preserved; shared base update failed. Lead review required.")
	return {"ok":true,"message":"Shared revision recorded. Local prompt "+("updated explicitly." if use_remote else "preserved.")}

