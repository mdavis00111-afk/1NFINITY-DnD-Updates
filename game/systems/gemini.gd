extends Node
## One provider; character biography generation cannot change any mechanical field.
signal completed(ok: bool, message: String)
const SETTINGS = "user://settings.cfg"
const DEFAULT_MODEL = "gemini-2.5-flash"
var request: HTTPRequest
var active = false

func _ready() -> void:
	request = HTTPRequest.new()
	request.use_threads = true
	request.timeout = 45.0
	request.body_size_limit = 1024 * 1024
	add_child(request)
	request.request_completed.connect(received)

func generate(prompt: String, key_override: String = "", model_override: String = "") -> void:
	if active:
		return
	var cfg = ConfigFile.new()
	cfg.load(SETTINGS)
	var key = key_override.strip_edges() if not key_override.is_empty() else str(cfg.get_value("gemini","api_key","")).strip_edges()
	var model = model_override.strip_edges() if not model_override.is_empty() else str(cfg.get_value("gemini","model",DEFAULT_MODEL)).strip_edges()
	model = model.trim_prefix("models/")
	var valid = RegEx.new()
	valid.compile("^[A-Za-z0-9._-]+$")
	if key.is_empty() or key.contains("\n") or key.contains("\r"):
		completed.emit(false,"Save a Gemini API key in Settings first.")
		return
	if valid.search(model) == null:
		completed.emit(false,"Enter a valid Gemini model ID in Settings.")
		return
	var payload = {"contents":[{"role":"user","parts":[{"text":prompt}]}],"generationConfig":{"temperature":0.8,"maxOutputTokens":1024}}
	active = true
	var err = request.request("https://generativelanguage.googleapis.com/v1beta/models/"+model+":generateContent",PackedStringArray(["Content-Type: application/json","x-goog-api-key: "+key]),HTTPClient.METHOD_POST,JSON.stringify(payload))
	if err != OK:
		active = false
		completed.emit(false,"Could not start Gemini request.")

func received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	active = false
	if result != HTTPRequest.RESULT_SUCCESS:
		completed.emit(false,"Gemini connection failed or timed out.")
		return
	if code != 200:
		var msg = "Gemini HTTP "+str(code)+"."
		match code:
			400: msg += " Check model and request settings."
			401,403: msg += " Check API key and permissions."
			404: msg += " Check the model ID."
			429: msg += " Quota or rate limit reached."
			503: msg += " Model temporarily unavailable."
		completed.emit(false,msg)
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		completed.emit(false,"Gemini returned an unreadable response.")
		return
	var candidates = data.get("candidates",[])
	var texts: PackedStringArray = []
	if not candidates.is_empty():
		for part in candidates[0].get("content",{}).get("parts",[]):
			if part.has("text") and not part.get("thought",false):
				texts.append(str(part["text"]))
	var text = "\n".join(texts).strip_edges()
	if text.is_empty():
		completed.emit(false,"Gemini did not return a description.")
	else:
		completed.emit(true,text.left(4000))
