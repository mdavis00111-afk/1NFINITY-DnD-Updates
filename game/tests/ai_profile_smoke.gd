extends SceneTree
const MATURITY = preload("res://campaigns/maturity_profiles.gd")
const NARRATOR = preload("res://campaigns/narrator_prompt.gd")
const GEMINI = preload("res://systems/gemini.gd")
const OPENING = preload("res://campaigns/opening_scene.gd")
const STARTS = preload("res://campaigns/campaign_starts.gd")
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func run() -> void:
	var expected = OS.get_environment("INFINITY_TEST_USER_ROOT").replace("\\","/").trim_suffix("/")
	var actual = ProjectSettings.globalize_path("user://").replace("\\","/").trim_suffix("/")
	if expected.is_empty() or expected != actual or FileAccess.file_exists(MATURITY.PATH) or FileAccess.file_exists("user://players.db") or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://campaigns")):
		push_error("AI profile smoke requires an explicitly authorized disposable user directory without settings or saves.")
		quit(2)
		return
	var defaults = MATURITY.selectable_profiles()
	expect(defaults.size()==3 and defaults[0]["id"]=="family" and defaults[1]["id"]=="standard" and defaults[2]["id"]=="mature","Default IDs/order")
	expect(MATURITY.DEFAULT_ID=="standard" and MATURITY.resolve("unknown").is_empty() and MATURITY.resolve_for_narration("unknown")["id"]=="standard","Strict lookup and safe fallback")
	expect(MATURITY.needs_adult_confirmation("mature") and not MATURITY.needs_adult_confirmation("standard"),"Confirmation predicate")
	var config = ConfigFile.new()
	config.set_value("fixture","keep","unchanged")
	for role in ["Scene","Interpreter","Brief","Write-back","NPC"]:
		config.set_value("prompts",role,role+" fixture")
	config.set_value("gemini","model","gemini-fixture-only")
	expect(config.save(MATURITY.PATH)==OK,"Fixture config save")
	expect(MATURITY.save_profiles([{"id":"legacy","name":"Legacy","instructions":"Legacy guidance"}]).is_empty(),"Legacy save")
	expect(MATURITY.save_guidance("family","Custom family guidance").is_empty(),"Edit family")
	expect(MATURITY.resolve("family")["instructions"]=="Custom family guidance" and MATURITY.resolve("legacy")["instructions"]=="Legacy guidance","Edits preserved")
	expect(MATURITY.selectable_profiles().size()==3,"Legacy not selectable")
	expect(not MATURITY.save_guidance("family"," ").is_empty(),"Reject blank")
	expect(not MATURITY.save_guidance("unknown","test").is_empty(),"Reject unknown")
	expect(MATURITY.resolve("family")["instructions"]=="Custom family guidance","Invalid edit preserved")
	expect(NARRATOR.load_prompt()==NARRATOR.DEFAULT_PROMPT and NARRATOR.seed_default().is_empty(),"Default narrator")
	expect(NARRATOR.save_prompt("Custom story guidance").is_empty() and NARRATOR.seed_default().is_empty() and NARRATOR.load_prompt()=="Custom story guidance","Custom narrator preserved")
	expect(MATURITY._merge([{"id":"mature","name":"Mature","instructions":MATURITY.ORIGINAL_GUIDANCE[2]}])[2]["instructions"]==MATURITY.DEFAULTS[2]["instructions"],"Migrate unchanged stock guidance")
	expect(MATURITY.safety_settings("mature").size()==4 and MATURITY.safety_settings("mature")[0]["threshold"]=="BLOCK_NONE","Mature Python defaults")
	expect(MATURITY.safety_settings("unknown")==MATURITY.safety_settings("standard"),"Unknown campaign uses Standard thresholds")
	var thresholds = MATURITY.default_thresholds("family")
	thresholds["HARM_CATEGORY_DANGEROUS_CONTENT"]="BLOCK_LOW_AND_ABOVE"
	expect(MATURITY.save_guidance("family","Custom family guidance",thresholds).is_empty(),"Save editable thresholds with audience guidance")
	var campaign_request = GEMINI.request_payload("Fixture",{},2048,0.8,"family")
	expect(campaign_request["safetySettings"]==MATURITY.safety_settings("family") and campaign_request["safetySettings"][3]["threshold"]=="BLOCK_LOW_AND_ABOVE","Campaign transport uses saved thresholds")
	expect(not GEMINI.request_payload("Non-campaign fixture").has("safetySettings"),"Non-campaign transport keeps provider defaults")
	var provider = GEMINI.new()
	provider.active=true
	provider.mode="generate"
	provider.current_key="fixture secret"
	provider.received(HTTPRequest.RESULT_SUCCESS,400,PackedStringArray(),JSON.stringify({"error":{"message":"Schema too complex: fixture secret"}}).to_utf8_buffer())
	var diagnostic = provider.response_diagnostic()
	expect(diagnostic=={"http_status":400,"http_result":HTTPRequest.RESULT_SUCCESS,"category":"schema_rejected"},"Transport diagnostic logs code and category only")
	provider.free()

	var prompt = NARRATOR.build("family",{"outcome":"MISS"},{"type":"object"})
	expect(prompt.contains(NARRATOR.AUTHORITY) and prompt.contains("Custom story guidance") and prompt.contains("Custom family guidance") and prompt.contains("MISS") and prompt.contains("ENGINE RESPONSE SCHEMA"),"Prompt composition")
	expect(NARRATOR.build("unknown",{}).contains("[CONTENT LEVEL: Standard]"),"Unknown fallback in prompt")
	expect(MATURITY.reset_guidance("family").is_empty() and MATURITY.resolve("family")["instructions"]==defaults[0]["instructions"],"Profile reset")
	expect(NARRATOR.reset_prompt().is_empty() and NARRATOR.load_prompt()==NARRATOR.DEFAULT_PROMPT,"Narrator reset")
	expect(config.load(MATURITY.PATH)==OK and config.get_value("fixture","keep")=="unchanged" and config.get_value("prompts","NPC")=="NPC fixture","Unrelated settings preserved")
	for role in ["Scene","Interpreter","Brief","Write-back","NPC"]:
		expect(config.get_value("prompts",role,"")==role+" fixture","Prompt setting lost: "+role)
	expect(config.get_value("gemini","model","")=="gemini-fixture-only","Model setting lost")
	var plain = GEMINI.request_payload("Prose fixture")
	expect(not plain["generationConfig"].has("responseMimeType") and not plain["generationConfig"].has("responseJsonSchema"),"Prose request changed")
	for start in STARTS.STARTS:
		var start_id = str(start["id"])
		var schema = OPENING.response_schema(start_id)
		var properties = schema["properties"]
		var packet = GEMINI.request_payload(OPENING.prompt({"start_id":start_id,"maturity_id":"family","title":"Fixture campaign"}),schema)
		expect(schema["required"]==OPENING.KEYS and not schema["additionalProperties"] and properties["start_id"]["enum"]==[start_id],"Opening schema scope "+start_id)
		expect(properties["npcs"]["minItems"]==(1 if start_id in OPENING.POPULATED else 0),"Opening schema NPC bounds "+start_id)
		expect(packet["generationConfig"].get("responseMimeType")=="application/json" and packet["generationConfig"].get("responseJsonSchema")==schema and not packet.has("safetySettings"),"Structured request config "+start_id)
		expect(str(packet["contents"][0]["parts"][0]["text"]).contains("ENGINE PHASE REQUIREMENTS") and str(packet["contents"][0]["parts"][0]["text"]).contains(OPENING.PHASE_RULES),"Opening phase not trusted instruction "+start_id)
	expect(OPENING.response_schema("invalid").is_empty() and OPENING.prompt({"start_id":"invalid"}).is_empty(),"Invalid start built a request")
	# Preserve the entire pre-existing legacy capacity after introducing the built-ins.
	var legacy_profiles: Array = []
	for i in range(MATURITY.MAX_LEGACY_PROFILES-1):
		legacy_profiles.append({"id":"legacy-"+str(i),"name":"Legacy "+str(i),"instructions":"Legacy fixture"})
	expect(MATURITY.save_profiles(legacy_profiles).is_empty(),"Legacy capacity consumed by built-ins")
	expect(MATURITY.load_profiles().size()==MATURITY.MAX_LEGACY_PROFILES+3,"Legacy profiles lost during merge")
	expect(MATURITY.save_guidance("standard","Updated full-registry guidance").is_empty(),"Full registry prevented built-in edit")
	expect(MATURITY.reset_guidance("standard").is_empty(),"Full registry prevented built-in reset")
	expect(not MATURITY.save_profiles([{"id":"legacy-over-limit","name":"Over limit","instructions":"Fixture"}]).is_empty(),"Exceeded legacy capacity")
	expect(MATURITY.resolve("legacy")["instructions"]=="Legacy guidance","Existing legacy guidance lost")
	var response = {"candidates":[{"finishReason":"STOP","content":{"parts":[{"text":"{}"}]}}]}
	expect(GEMINI.generation_text(response,true)=={"ok":true,"message":"{}"},"Complete structured envelope rejected")
	response["candidates"][0]["finishReason"]="MAX_TOKENS"
	expect(not GEMINI.generation_text(response,true)["ok"],"Incomplete structured envelope accepted")
	response["candidates"][0]["finishReason"]="STOP"
	response["candidates"][0]["content"]["parts"][0]["text"]="{}".rpad(4000," ")+"extra"
	expect(not GEMINI.generation_text(response,true)["ok"],"Oversize structured envelope truncated and accepted")
	expect(not GEMINI.generation_text({"candidates":[{"content":null}]},true)["ok"],"Null provider content accepted")
	expect(not GEMINI.generation_text({"candidates":[{"finishReason":"STOP","content":{"parts":[null]}}]},true)["ok"],"Malformed provider part accepted")
	var mixed = {"candidates":[{"finishReason":"STOP","content":{"parts":[{"thought":true,"text":"hidden reasoning"},{"text":"{}"}]}}]}
	expect(GEMINI.generation_text(mixed,true)=={"ok":true,"message":"{}"},"Thought text leaked into JSON")
	mixed["candidates"][0]["content"]["parts"].append({"functionCall":{"name":"unexpected"}})
	expect(not GEMINI.generation_text(mixed,true)["ok"],"Tool call mixed into structured response")
	mixed["candidates"][0]["content"]["parts"].pop_back()
	mixed["promptFeedback"]={"blockReason":"SAFETY"}
	expect(not GEMINI.generation_text(mixed,true)["ok"],"Blocked prompt accepted")
	mixed.erase("promptFeedback")
	mixed["candidates"].append(mixed["candidates"][0].duplicate(true))
	expect(not GEMINI.generation_text(mixed,true)["ok"],"Multiple structured candidates accepted")
	var split = {"candidates":[{"finishReason":"STOP","content":{"parts":[{"text":"{\"location_name\":\"North"},{"text":" Road\"}"}]}}]}
	expect(GEMINI.generation_text(split,true).get("message")=="{\"location_name\":\"North Road\"}","Structured text chunks changed JSON")
	split["candidates"][0]["content"]["parts"][1]["unknownMedia"]={}
	expect(not GEMINI.generation_text(split,true)["ok"],"Unknown structured part field accepted")
	split["candidates"][0]["content"]["parts"][1].erase("unknownMedia")
	split["candidates"][0]["content"]["parts"].append({"thought":true,"text":42})
	expect(not GEMINI.generation_text(split,true)["ok"],"Malformed thought text accepted")
	for failure in failures:
		push_error(failure)
	print("AI profile smoke failures: ", failures.size())
	quit(0 if failures.is_empty() else 1)
