extends Node
## The caller chooses a model; discovery never spends generation quota or changes saved settings.
signal completed(ok: bool, message: String)
signal models_completed(ok: bool, models: Array, message: String)
const SETTINGS = "user://settings.cfg"
const DEFAULT_MODEL = "gemini-3.5-flash-lite"
const BASE = "https://generativelanguage.googleapis.com/v1beta/"
var request: HTTPRequest
var active = false
var mode = ""
var discovery_key = ""
var discovered: Array = []
var pages = 0
var current_key = ""
var current_model = ""
var complete_response_required = false
var response_limit = 4000

func _ready() -> void:
	request = HTTPRequest.new()
	request.use_threads = true
	request.timeout = 45.0
	request.body_size_limit = 4 * 1024 * 1024
	request.max_redirects = 0
	add_child(request)
	request.request_completed.connect(received)

func key_valid(key: String) -> bool:
	return not key.is_empty() and not key.contains("\n") and not key.contains("\r")

func list_models(key: String) -> void:
	if active:
		return
	key = key.strip_edges()
	if not key_valid(key):
		models_completed.emit(false,[],"Enter a Gemini API key first.")
		return
	active = true
	mode = "models"
	discovery_key = key
	discovered = []
	pages = 0
	list_page("")

func list_page(token: String) -> void:
	pages += 1
	var url = BASE + "models?pageSize=1000"
	if not token.is_empty():
		url += "&pageToken=" + token.uri_encode()
	var err = request.request(url,PackedStringArray(["x-goog-api-key: "+discovery_key]),HTTPClient.METHOD_GET)
	if err != OK:
		fail("Could not start model discovery.")

# Only trusted engine callers supply a schema. Plain-prose callers keep their existing payload.
static func request_payload(prompt: String, response_schema: Dictionary = {}, output_tokens: int = 2048, temperature: float = 0.8) -> Dictionary:
	var payload = {"contents":[{"role":"user","parts":[{"text":prompt}]}],"generationConfig":{"temperature":clampf(temperature,0.0,1.0),"maxOutputTokens":clampi(output_tokens,1,8192)}}
	if not response_schema.is_empty():
		payload["generationConfig"]["responseMimeType"] = "application/json"
		payload["generationConfig"]["responseJsonSchema"] = response_schema.duplicate(true)
	return payload

func generate(prompt: String, key_override: String = "", model_override: String = "", require_complete: bool = false, response_schema: Dictionary = {}, max_chars: int = 4000, output_tokens: int = 2048, temperature: float = 0.8) -> void:
	if active:
		return
	var cfg = ConfigFile.new()
	cfg.load(SETTINGS)
	var key = key_override.strip_edges() if not key_override.is_empty() else str(cfg.get_value("gemini","api_key","")).strip_edges()
	var model = model_override.strip_edges() if not model_override.is_empty() else str(cfg.get_value("gemini","model",DEFAULT_MODEL)).strip_edges()
	model = model.trim_prefix("models/")
	var valid = RegEx.new()
	valid.compile("^[A-Za-z0-9._-]+$")
	if not key_valid(key):
		completed.emit(false,"Save a Gemini API key in Settings first.")
		return
	if valid.search(model) == null:
		completed.emit(false,"Enter a valid Gemini model ID in Settings.")
		return
	var payload = request_payload(prompt,response_schema,output_tokens,temperature)
	response_limit = clampi(max_chars,1,65536)
	active = true
	mode = "generate"
	current_key = key
	current_model = model
	complete_response_required = require_complete or not response_schema.is_empty()
	var err = request.request(BASE+"models/"+model+":generateContent",PackedStringArray(["Content-Type: application/json","x-goog-api-key: "+key]),HTTPClient.METHOD_POST,JSON.stringify(payload))
	if err != OK:
		fail("Could not start Gemini request.")

func fail(message: String) -> void:
	var was_discovery = mode == "models"
	active = false
	mode = ""
	discovery_key = ""
	current_key = ""
	current_model = ""
	complete_response_required = false
	if was_discovery:
		models_completed.emit(false,[],message)
	else:
		completed.emit(false,message)

func error_message(code: int, data: Variant) -> String:
	var message = "Gemini HTTP "+str(code)+"."
	match code:
		400: message += " Check the request and model."
		401,403: message += " Check API key and permissions."
		404: message += " Model or endpoint unavailable. Discover models in Settings and test another."
		429: message += " Quota or rate limit reached."
		503: message += " Model temporarily unavailable."
	if data is Dictionary and data.get("error") is Dictionary:
		var detail = str(data["error"].get("message",""))
		for secret in [discovery_key,current_key]:
			if not secret.is_empty():
				detail = detail.replace(secret,"[redacted]")
		if not detail.is_empty():
			message += "\n"+detail.left(420)
	return message

func received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		fail("Gemini connection failed or timed out.")
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if code != 200:
		fail(error_message(code,data))
		return
	if not data is Dictionary:
		fail("Gemini returned an unreadable response.")
		return
	if mode == "models":
		var models = data.get("models",[])
		if not models is Array:
			fail("Gemini returned an invalid model list.")
			return
		for item in models:
			if not item is Dictionary or not item.get("supportedGenerationMethods",[]) is Array or not "generateContent" in item.get("supportedGenerationMethods",[]):
				continue
			var id = str(item.get("name","")).trim_prefix("models/")
			if id.begins_with("gemini-") and not id.is_empty() and not id in discovered:
				# Skip explicitly non-text generation variants; actual access is confirmed by Test Connection.
				if not ("image" in id or "audio" in id or "tts" in id or "live" in id or "robotics" in id):
					discovered.append(id)
		var token = str(data.get("nextPageToken",""))
		if not token.is_empty() and pages < 20:
			# Start the next request after HTTPRequest completes its signal.
			list_page.call_deferred(token)
			return
		if not token.is_empty():
			fail("Model discovery exceeded its page limit. Please retry.")
			return
		active = false
		mode = ""
		discovery_key = ""
		discovered.sort()
		models_completed.emit(true,discovered.duplicate(),"Found "+str(discovered.size())+" text-capable model candidates. Select one, test it, then save.")
		return
	active = false
	mode = ""
	current_key = ""
	current_model = ""
	var output = generation_text(data,complete_response_required,response_limit)
	response_limit = 4000
	complete_response_required = false
	completed.emit(output["ok"],output["message"])

# Parse the provider envelope defensively. Opening proposals must be complete,
# never truncated into an apparently valid JSON prefix. Prose callers retain their cap.
static func generation_text(data: Dictionary, require_complete: bool = false, max_chars: int = 4000) -> Dictionary:
	max_chars = clampi(max_chars,1,65536)
	var failure = {"ok":false,"message":"Gemini did not return a complete usable response. Try again or choose another model."}
	var feedback = data.get("promptFeedback",{})
	if require_complete and (not feedback is Dictionary or (feedback.has("blockReason") and feedback["blockReason"] not in ["","BLOCK_REASON_UNSPECIFIED"])):
		return failure
	var candidates = data.get("candidates",[])
	if not candidates is Array or candidates.is_empty() or not candidates[0] is Dictionary:
		return failure
	if require_complete and candidates.size()!=1:
		return failure
	var candidate: Dictionary = candidates[0]
	if require_complete and candidate.get("finishReason","") != "STOP":
		return failure
	var content = candidate.get("content")
	if not content is Dictionary:
		return failure
	var parts = content.get("parts")
	if not parts is Array:
		return failure
	var texts: PackedStringArray = []
	for part in parts:
		if not part is Dictionary:
			return failure
		# Structured opening cannot contain a tool call, executable code or media.
		# Thought text/signatures are not the response; never include them.
		if require_complete:
			if part.has("thought") and not part["thought"] is bool:
				return failure
			for key in part:
				if key not in ["text","thought","thoughtSignature"]:
					return failure
			if (part.has("text") and not part["text"] is String) or (part.has("thoughtSignature") and not part["thoughtSignature"] is String):
				return failure
			if not part.get("thought",false) and not part.has("text"):
				return failure
		if part.has("text") and not part.get("thought",false):
			if not part["text"] is String:
				return failure
			texts.append(part["text"])
	# Structured parts are chunks of a single JSON document; inserting a newline
	# can corrupt a split string or escape sequence. Preserve prose behavior.
	var separator = "" if require_complete else "\n"
	var output = separator.join(texts).strip_edges()
	if output.is_empty() or (require_complete and output.length()>max_chars):
		return failure
	return {"ok":true,"message":output.left(max_chars)}
