extends SceneTree
const MATURITY = preload("res://campaigns/maturity_profiles.gd")
const NARRATOR = preload("res://campaigns/narrator_prompt.gd")
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
	config.set_value("prompts","NPC","NPC fixture")
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
	var prompt = NARRATOR.build("family",{"outcome":"MISS"},{"type":"object"})
	expect(prompt.contains(NARRATOR.AUTHORITY) and prompt.contains("Custom story guidance") and prompt.contains("Custom family guidance") and prompt.contains("MISS") and prompt.contains("ENGINE RESPONSE SCHEMA"),"Prompt composition")
	expect(NARRATOR.build("unknown",{}).contains("[CONTENT LEVEL: Standard]"),"Unknown fallback in prompt")
	expect(MATURITY.reset_guidance("family").is_empty() and MATURITY.resolve("family")["instructions"]==defaults[0]["instructions"],"Profile reset")
	expect(NARRATOR.reset_prompt().is_empty() and NARRATOR.load_prompt()==NARRATOR.DEFAULT_PROMPT,"Narrator reset")
	expect(config.load(MATURITY.PATH)==OK and config.get_value("fixture","keep")=="unchanged" and config.get_value("prompts","NPC")=="NPC fixture","Unrelated settings preserved")
	for failure in failures:
		push_error(failure)
	print("AI profile smoke failures: ", failures.size())
	quit(0 if failures.is_empty() else 1)
