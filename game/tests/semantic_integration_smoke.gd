extends SceneTree
## C5 actual controller, registry, SQLite and prompt workflow. Only transport
## is mocked. Actual C5b semantic review/context policy runs locally.
const BASE=preload("res://campaigns/campaign_store.gd")
const PLAYER=preload("res://players/character_store.gd")
const CAT=preload("res://rules/catalog.gd")
const SESSION=preload("res://persistence/gameplay_session.gd")
const SQL=preload("res://systems/sqlite.gd")
const MIGRATION=preload("res://persistence/gameplay_migration.gd")
const CTRL=preload("res://gameplay/semantic_controller.gd")
const WORKSPACE=preload("res://gameplay/game_workspace.gd")
const PACK=preload("res://turns/agent_packets.gd")
const RECON=preload("res://world/geography_reconciler.gd")
const GENERATOR=preload("res://persistence/actor_generation.gd")
const REG=preload("res://gameplay/tool_registry.gd")
const NARRATOR=preload("res://campaigns/narrator_prompt.gd")
const SHARE=preload("res://campaigns/prompt_sharing.gd")
const PROSE="The shield settles against your arm. Mara laughs. \"That suits you,\" she says, polishing a cup. An abandoned carved amber tally lies on the counter, free to take. Mara offers two gold pieces for your help."
const TALK="Mara leans forward, her voice dropping. \"The bridge? A mason named Orrin built it.\" She stares into the hearth, as though remembering an old argument."
const ACCEPT="I accept the two gold pieces Mara offers."
const PROPOSED="Mara places two gold pieces into your hand."
const PENDING="Mara holds out two gold pieces. \"For your trouble,\" she says."
const TRANSFERRED="Mara smiles as the two gold pieces pass to you. \"A debt paid,\" she says."
const DECLINE="I decline her offer."
const DECLINED="Mara nods. \"Fair enough.\" She puts her purse away."
const ACCEPT_ITEM="I accept one of Mara’s daggers."
const ITEM_PROPOSED="Mara hands you one of her daggers."
const ITEM_PENDING="Mara holds out one of her daggers for you."
const ITEM_SETTLED="Mara passes the dagger across. \"Keep it sharp,\" she says."
const INPUT="I lift that shield onto my arm."
var base=BASE.new()
var session=SESSION.new()
var ctrl
var workspace
var failures: Array[String]=[]
var outbound: Array=[]

# Pause only scheduling, never replace production authorization or persistence.
class FixtureController extends "res://gameplay/semantic_controller.gd":
	var pause_discovery=false
	var pause_reconcile=false
	func reconcile(job: Dictionary,receipt: Dictionary,known: Array) -> void:
		if not pause_reconcile:
			super.reconcile(job,receipt,known)
	func process_story() -> void:
		if not pause_discovery:
			super.process_story()
	func step_discovery() -> void:
		super.process_story()

class MockTransport:
	extends Node
	signal completed(ok: bool,message: String)
	var prompt=""
	var supplied_schema: Dictionary={}
	var cancelled=false
	var recorder: Callable
	func generate(value: String,_key: String="",_model: String="",_complete: bool=false,_schema: Dictionary={},_chars: int=4000,_tokens: int=2048,_temperature: float=0.8) -> void:
		prompt=value
		supplied_schema=_schema.duplicate(true)
		if recorder.is_valid():
			recorder.call(value)
	func cancel_generation() -> void:
		cancelled=true
	func reply(value: Variant) -> void:
		completed.emit(true,value if value is String else JSON.stringify(value))

func _initialize() -> void:
	run.call_deferred()

func expect(ok: bool,message: String) -> bool:
	if not ok:
		failures.append(message)
	return ok

func finish() -> void:
	for failure in failures:
		push_error(failure)
	print("C5 semantic integration failures: ",failures.size())
	quit(0 if failures.is_empty() else 1)

func master_record(id: String,role: String="fighter") -> Dictionary:
	var slots: Dictionary={}
	for level in range(1,10):
		slots[str(level)]={"maximum":2 if role=="cleric" and level==1 else 0,"spent":0}
	var profs=["simple-weapons","light-armor","medium-armor","shields"]
	if role=="fighter":
		profs.append_array(["martial-weapons","heavy-armor","saving-throw-str","saving-throw-con"])
	else:
		profs.append_array(["saving-throw-wis","saving-throw-cha"])
	var saves={"str":2 if role=="fighter" else 0,"dex":2,"con":3 if role=="fighter" else 1,"int":0,"wis":1 if role=="fighter" else 3,"cha":0 if role=="fighter" else 2}
	return {"id":id,"name":"C3 fixture "+role,"status":"ready","ruleset":CAT.RULESET,"catalog_revision":CAT.REVISION,"level":1,"race_id":"human","class_id":role,"subclass_id":"","ability_scores":{"str":10,"dex":14,"con":12,"int":10,"wis":12,"cha":10},"ability_modifiers":{"str":0,"dex":2,"con":1,"int":0,"wis":1,"cha":0},"proficiency_bonus":2,"proficiency_ids":profs,"expertise_ids":[],"skills":{},"saving_throws":saves,"equipment":{"armor_id":"","shield_id":"","weapon_ids":[],"armor_penalty":false},"attacks":[],"inventory":[{"item_id":"dagger","quantity":2,"equipped":false},{"item_id":"shield","quantity":1,"equipped":false},{"item_id":"greatsword","quantity":1,"equipped":false},{"item_id":"leather-armor","quantity":1,"equipped":false},{"item_id":"magic:potion-of-healing-common","quantity":1,"equipped":false},{"item_id":"rations-1-day","quantity":1,"equipped":false}],"coins":{"cp":0,"sp":0,"ep":0,"gp":5,"pp":0},"carrying_capacity_lb":150,"combat":{"hp_current":4,"hp_max":11 if role=="fighter" else 9,"hp_temp":0,"conditions":[],"active_effects":[],"exhaustion":0,"armor_class":12,"speed_feet":30,"size":"Medium","passive_perception":11,"hit_die":10 if role=="fighter" else 8,"hit_dice_total":1,"hit_dice_spent":0},"resources":{"second_wind":{"max":1,"spent":0,"reset":"short_or_long_rest"}} if role=="fighter" else {},"spellcasting":{"ability":"wis" if role=="cleric" else "","slots":slots,"pact_magic":false,"concentration":null,"attack_bonus":3 if role=="cleric" else null,"save_dc":11 if role=="cleric" else null,"known_ids":[],"prepared_ids":["cure-wounds","healing-word"] if role=="cleric" else [],"always_prepared_ids":[],"cantrip_ids":[],"racial_cantrip_ids":[]},"review_required":[]}


func money(gp: int) -> Dictionary:
	return {"cp":0,"sp":0,"ep":0,"gp":gp,"pp":0}


func factory() -> Node:
	var mock=MockTransport.new()
	mock.recorder=func(value: String): outbound.append({"stage":ctrl.inflight.get("stage"),"prompt":value})
	return mock

func bind(id: String) -> bool:
	ctrl=FixtureController.new()
	root.add_child(ctrl)
	if not expect(ctrl.bind_ai(id,Callable(),Callable(),factory).get("ok",false),"Explicit C5 binding failed"):
		return false
	workspace=WORKSPACE.new()
	if not expect(ctrl.mount_workspace(workspace,Callable(),Callable()).get("ok",false),"Actual workspace mount"):
		return false
	root.add_child(workspace)
	return true

func pump(stage: String,after_serial: int=-1) -> bool:
	for i in range(60):
		await process_frame
		if stage=="idle" and ctrl.active().is_empty() and ctrl.view.get("interaction_extension",{}).get("phase")=="idle":
			return true
		if stage!="idle" and ctrl.inflight.get("stage")==stage and is_instance_valid(ctrl.adapter.transport) and not ctrl.adapter.transport.prompt.is_empty() and ctrl.adapter.serial>after_serial:
			return true
	print("SEMANTIC_QA pump_timeout expected=",stage," active=",ctrl.active().get("stage","none")," inflight=",ctrl.inflight.get("stage","none")," calls=",outbound.size()," tool=",ctrl.active().get("tool",{}).get("kind","none")," staged=",ctrl.active().get("story_request",{}).get("kind","none"))
	return expect(false,"Expected "+stage+"; got "+str(ctrl.active().get("stage"))+" / "+ctrl.status)

func reply(value: Variant) -> void:
	ctrl.adapter.transport.reply(value)

func claim(kind: String,evidence: String,proposal: Variant=null,refs: Array=[]) -> Dictionary:
	return {"kind":kind,"evidence":evidence,"proposal":proposal,"refs":refs}

func report(text: String,claims: Array) -> Dictionary:
	return {"candidate_hash":text.sha256_text(),"coverage":[{"start":0,"end":text.length()}],"claims":claims}

func review_twice(text: String,claims: Array) -> bool:
	if not await pump("critical"):
		return false
	var serial=ctrl.adapter.serial
	reply(report(text,claims))
	if not await pump("critical",serial):
		return false
	expect(ctrl.view["interaction_extension"]["reviewed_preview"].is_empty(),"First pass never confirms prose")
	reply(report(text,claims))
	return await pump("background")

func assess(original: String,source_id: Variant=null,evidence: String="",ruling: Dictionary={}) -> void:
	var sources: Array=[]
	if source_id!=null:
		sources.append({"event_id":source_id,"evidence":evidence})
	reply({"disposition":"supported","intent_evidence":original,"context":sources,"ruling":ruling,"reason":"Fixture semantic assessment; local policy and registered tools remain authoritative."})

func geography() -> Dictionary:
	var identity=PACK.identity(session.token(ctrl.campaign_id),ctrl.active()["turn_id"],ctrl.inflight["attempt_id"])
	identity["source_event_id"]=null
	identity["facts"]=[]
	return identity

func prompt_fixture() -> void:
	var cfg=ConfigFile.new()
	cfg.set_value("gemini","api_key","fixture-local-key-not-shared")
	cfg.set_value("prompts","Scene","Fixture scene")
	expect(cfg.save(NARRATOR.PATH)==OK,"Fixture settings save")
	expect(NARRATOR.save_prompt("Local creative prompt.").is_empty(),"Local prompt save")
	expect(not SHARE.export_proposal("test",false).get("ok",false),"Export without consent blocked")
	var exported=SHARE.export_proposal("Fixture change",true)
	if not expect(exported.get("ok",false),"Prompt-only export"):
		return
	var read=SHARE.read_file(exported["path"])
	if not expect(read.get("ok",false) and not FileAccess.get_file_as_string(exported["path"]).contains("fixture-local-key-not-shared"),"Export schema and no key"):
		return
	var remote=read["bundle"].duplicate(true)
	remote["kind"]="shared"
	remote["source_commit"]="1111111111111111111111111111111111111111"
	remote["prompt"]="Lead-reviewed creative prompt."
	remote["prompt_hash"]=remote["prompt"].sha256_text()
	var shared=SHARE.write_unique(SHARE.ROOT+"/fixture","shared",remote)
	if not expect(shared.get("ok",false),"Shared fixture write"):
		return
	var inspected=SHARE.inspect_shared(shared["path"])
	expect(inspected.get("conflict",false),"Local versus shared conflict detected")
	expect(not SHARE.apply_shared(inspected,true,false).get("ok",false),"Unconfirmed replacement rejected")
	expect(SHARE.apply_shared(inspected,false,true).get("ok",false),"Keep-local conflict resolution")
	expect(NARRATOR.load_prompt()=="Local creative prompt.","Local customization retained")
	cfg.load(NARRATOR.PATH)
	expect(cfg.get_value("gemini","api_key")=="fixture-local-key-not-shared" and cfg.get_value("prompts","Scene")=="Fixture scene","Other settings preserved")
	expect(not SHARE.inspect_shared(shared["path"]).get("ok",false),"Stale shared revision rejected")

func run() -> void:
	var expected=OS.get_environment("INFINITY_TEST_USER_ROOT").replace("\\","/").trim_suffix("/")
	var actual=ProjectSettings.globalize_path("user://").replace("\\","/").trim_suffix("/")
	if expected.is_empty() or expected!=actual or FileAccess.file_exists("user://players.db") or FileAccess.file_exists("user://settings.cfg") or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(BASE.ROOT)):
		push_error("C5 fixture requires explicitly authorized empty disposable user directory.")
		quit(2)
		return
	prompt_fixture()
	expect(not session.same_request(null,{}) and not session.same_request({},null) and not session.same_request("invalid",{}),"Absent or malformed staged request fails closed")
	var players=PLAYER.new()
	var master=players.make_id()
	if not expect(players.save_record(master_record(master,"cleric" if "--dm-first" in OS.get_cmdline_user_args() else "fighter")).is_empty(),"Master fixture"):
		finish()
		return
	var original=players.load_record(master)
	var a=base.create_campaign("C5 fixture",master,"tavern","standard")
	var b=base.create_campaign("C5 sibling",master,"road","standard")
	if not expect(not a.is_empty() and not b.is_empty(),"Campaign fixture"):
		finish()
		return
	var id=a["id"]
	var sibling=base.gameplay_view(b["id"])
	if not expect(MIGRATION.new().ensure(id).get("ok",false),"C2 migration"):
		finish()
		return
	var opening=base.prepare_opening(id)
	if opening.is_empty():
		expect(false,"Opening unavailable")
		finish()
		return
	var raw=JSON.stringify({"start_id":"tavern","location_name":"Oak Inn","atmosphere":"A quiet room.","npcs":[{"name":"Mara","occupation":"Innkeeper","attitude":0}],"world_facts":["The floor is wooden."],"thumbnail_id":"tavern"})
	if not expect(base.commit_opening(id,opening["previous"],raw).is_empty(),"Opening"):
		finish()
		return
	var local=base.gameplay_view(id)["interaction_extension"]["public_actors"]
	if not expect(local.size()==1,"Disclosed local NPC"):
		finish()
		return
	var mara=local[0]["actor_id"]
	var opening_event=int(local[0]["source_event_id"])
	var state=session.token(id)
	var npc_args={"generation_key":session.make_id(),"template_ids":["commoner"],"existing_actor_id":mara,"kind":"npc","name":"Mara","occupation":"Innkeeper","location_id":state["location_id"],"visibility":"player","sheet_visibility":"private","source_event_id":opening_event,"possessions":[{"definition_id":"dagger","quantity":2,"equipped_slot":null,"grip":null}],"coins":money(3),"attitude":null}
	var npc_req={"schema_version":"2","campaign_id":id,"actor_id":state["actor_id"],"expected_revision":state["revision"],"request_id":session.make_id(),"kind":"actor_generate","args":npc_args}
	if not expect(GENERATOR.new().generate(id,npc_req,true).get("ok",false),"Canonical disposable NPC upgrade"):
		finish()
		return
	if not bind(id):
		finish()
		return
	var shield=""
	for item in ctrl.view["interaction_extension"]["inventory_instances"]:
		if item["definition_id"]=="shield":
			shield=item["instance_id"]
	if not expect(not shield.is_empty(),"Owned shield"):
		finish()
		return
	if "--menu-shortcuts" in OS.get_cmdline_user_args():
		ctrl.close_session()
		workspace.queue_free()
		ctrl.queue_free()
		await menu_shortcuts_case(id)
		finish()
		return
	if "--transport-retry" in OS.get_cmdline_user_args():
		await transport_retry_case(id)
		ctrl.close_session()
		workspace.queue_free()
		ctrl.queue_free()
		finish()
		return
	if "--chat-recovery" in OS.get_cmdline_user_args():
		await chat_recovery_case(id)
		ctrl.close_session()
		workspace.queue_free()
		ctrl.queue_free()
		finish()
		return
	if "--provider-format" in OS.get_cmdline_user_args():
		await provider_format_case(id)
		expect(players.load_record(master)==original and base.gameplay_view(b["id"])==sibling,"Independent master and sibling saves unchanged")
		ctrl.close_session()
		workspace.queue_free()
		ctrl.queue_free()
		finish()
		return
	if "--typed-invite" in OS.get_cmdline_user_args():
		await typed_invite_case(id,mara)
		ctrl.close_session()
		workspace.queue_free()
		ctrl.queue_free()
		finish()
		return
	if "--dm-map" in OS.get_cmdline_user_args():
		await persistent_npc_location(id)
		ctrl.close_session()
		workspace.queue_free()
		ctrl.queue_free()
		finish()
		return
	if "--conditional-check" in OS.get_cmdline_user_args():
		await conditional_check_case(id)
		ctrl.close_session()
		workspace.queue_free()
		ctrl.queue_free()
		finish()
		return
	if "--dm-first" in OS.get_cmdline_user_args():
		await dm_first_case(id)
		expect(players.load_record(master)==original and base.gameplay_view(b["id"])==sibling,"DM first save isolation")
		ctrl.close_session()
		workspace.queue_free()
		ctrl.queue_free()
		finish()
		return
	if "--context-pipeline" in OS.get_cmdline_user_args():
		await context_pipeline_case(id,mara,shield)
		expect(players.load_record(master)==original and base.gameplay_view(b["id"])==sibling,"Master and sibling isolation")
		ctrl.close_session()
		workspace.queue_free()
		ctrl.queue_free()
		finish()
		return
	await interrupted_consumption(id)
	await duplicate_response_cases(id,b["id"])
	await legacy_recovery_cases(id)
	await request_count_cases(id,shield)
	await authority_cases(id,shield)
	await persistent_npc_location(id)
	await geography_discovery_case(id)
	await discovery_negative_cases(id,b["id"])
	await duplicate_world_envelope(id)
	await candidate_reopen(id)
	await actor_generation_reopen(id)
	await legacy_unsettled_authorization(id)
	await context_memory_case(id,b["id"])
	expect(players.load_record(master)==original and base.gameplay_view(b["id"])==sibling,"Master and sibling isolation")
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	finish()

func menu_shortcuts_case(id: String) -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var installed_log = game.install_root().path_join("game.log")
	expect(game.game_log_path()==installed_log and game.read_recent_log(installed_log).contains("Godot Engine"),"Copy log reads the installed engine log")
	var large_path = "user://log-copy-fixture.log"
	var log_file = FileAccess.open(large_path,FileAccess.WRITE)
	log_file.store_string("older entry\n"+"x".repeat(2*game.LOG_COPY_LIMIT)+"\nLatest log line.\n")
	log_file.close()
	expect(game.read_recent_log(large_path)=="Latest log line.\n" and game.read_recent_log("user://missing-log.log").is_empty(),"Copy log reads a bounded tail and handles a missing log")
	game.settings_campaign_id=id
	game.show_screen("Game Workspace")
	await process_frame
	await process_frame
	var campaign = game.campaign_screen
	if not expect(is_instance_valid(campaign.workspace) and is_instance_valid(campaign.gameplay_controller),"Main menu opens a saved campaign"):
		game.queue_free()
		return
	var current = campaign.workspace
	var toolbar = current.nav_bar.get_global_rect()
	var log_button = game.copy_log_button.get_global_rect()
	expect(log_button.end.x <= game.size.x and not toolbar.intersects(log_button),"Workspace toolbar and top-right Copy log button do not overlap")
	var click = InputEventMouseButton.new()
	click.position=log_button.get_center()
	click.button_index=MOUSE_BUTTON_LEFT
	click.pressed=true
	root.push_input(click,true)
	var release = click.duplicate() as InputEventMouseButton
	release.pressed=false
	root.push_input(release,true)
	expect(game.copy_log_button.text=="Copied","The top-right button is clickable from the workspace")
	var escape = InputEventKey.new()
	escape.pressed=true
	escape.keycode=KEY_ESCAPE
	current.composer.text="Keep this draft after Esc."
	current.composer.grab_focus()
	current.local_pending_id="unconfirmed"
	root.push_input(escape,true)
	await process_frame
	expect(game.active_screen=="Game Workspace","Esc preserves the workspace when delivery is unconfirmed")
	current.local_pending_id=""
	current.composer.grab_focus()
	root.push_input(escape,true)
	await process_frame
	expect(game.active_screen=="Main","Esc from the focused composer returns to the main menu")
	game.settings_campaign_id=id
	game.show_screen("Game Workspace")
	await process_frame
	await process_frame
	expect(game.campaign_screen.workspace.composer.text=="Keep this draft after Esc.","Reopened campaign restores the exact draft")
	game.queue_free()

func transport_retry_case(id: String) -> void:
	var before = SQL.metrics()["calls"]
	expect(ctrl.reload(),"Independent bounded journal read")
	var journal_reads = SQL.metrics()["calls"]-before
	before=SQL.metrics()["calls"]
	ctrl.advance()
	expect(SQL.metrics()["calls"]-before==journal_reads,"Idle tick reads the journal once")
	var intent = pipeline_intent(id,"hello")
	expect(ctrl.submit(intent).get("ok",false),"Submit hello")
	if not await pump("interpret"):
		return
	reply({})
	if not await pump("narrate"):
		return
	var initial = ctrl.inspect_dm_packet()
	ctrl.adapter.transport.completed.emit(false,"Gemini HTTP 400. Fixture transport rejection.")
	for _i in range(40):
		await process_frame
		if ctrl.active().get("stage")=="retry":
			break
	if not expect(ctrl.active().get("stage")=="retry" and not session.settlement(id,intent["request_id"]).get("found",false),"Transport failure holds hello before mechanics"):
		return
	expect(ctrl.retry().get("ok",false),"Retry uncommitted narration")
	if not await pump("narrate"):
		return
	var retry_packet = ctrl.inspect_dm_packet()
	expect(outbound.size()==3 and retry_packet["player_text"]=="hello" and retry_packet["outbound"]["attempt_id"]!=initial["outbound"]["attempt_id"],"Retry refreshes attempt without translating or settling twice")
	var state = session.token(id)
	var bumped = SQL.run(session.path(id),[SQL.stmt("UPDATE world_state SET revision=revision+1 WHERE campaign_id=?",[id])])
	expect(bumped.get("ok",false),"Simulate intervening canonical revision")
	expect(ctrl.retry().get("ok",false),"Revise only the unresolved lookup context")
	if not await pump("interpret"):
		return
	expect(ctrl.adapter.payload["intent"]["args"]["text"]=="hello" and ctrl.inflight["revision"]==state["revision"]+1,"Stale unresolved retry rereads facts at live revision")
	reply({})
	if not await pump("narrate"):
		return
	reply({"text":"The innkeeper says hello."})
	if not await pump("idle"):
		return
	expect(session.settlement(id,intent["request_id"]).get("status")=="committed" and outbound.size()==5,"Recovered original request commits once")

func chat_recovery_case(id: String) -> void:
	var calls = outbound.size()
	var initial = session.token(id)
	workspace.composer.text="A request that the provider will fail."
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	reply("Malformed provider text")
	for _i in range(40):
		await process_frame
		if ctrl.active().get("stage")=="retry":
			break
	if not expect(ctrl.active().get("stage")=="retry","Failed request is waiting for recovery"):
		return
	workspace.composer.text="hello"
	workspace.submit_chat()
	await process_frame
	expect(ctrl.data["work"]["queued"].get("intent",{}).get("args",{}).get("text")=="hello","Hello is durably queued while previous request needs recovery")
	workspace.composer.text="keep this unsent draft"
	workspace.submit_chat()
	expect(workspace.get_node_or_null("TurnProcessing")!=null and workspace.status.text.contains("queued"),"A blocked Enter explains the queue and opens recovery")
	expect(workspace.composer.text=="keep this unsent draft" and outbound.size()==calls+1,"Blocked chat keeps the draft and sends no request")
	expect(ctrl.cancel().get("ok",false),"Cancel only the uncommitted failed turn")
	await process_frame
	expect(session.token(id)["revision"]==initial["revision"] and ctrl.view["interaction_extension"]["queue_wait"],"Cancel preserves saved hello without mutating the game")
	expect(ctrl.retry().get("ok",false),"Retry resumes the existing queue when no active turn remains")
	if not await pump("interpret"):
		return
	expect(ctrl.adapter.payload["intent"]["args"]["text"]=="hello","Recovered hello keeps exact input")
	reply({})
	if not await pump("narrate"):
		return
	expect(ctrl.inspect_dm_packet().get("player_text")=="hello","The DM receives the exact hello")
	reply({"text":"The innkeeper looks up. Hello, traveler."})
	if not await pump("idle"):
		return
	expect(outbound.size()==calls+3 and workspace.can_intent("chat"),"Hello completes with two calls and the composer accepts more input")

func provider_format_case(id: String) -> void:
	var inputs = ["Hello.","I look around.","What can I see?","I ask the innkeeper about the town.","I sit down and have a conversation."]
	for index in range(inputs.size()):
		var intent = pipeline_intent(id,inputs[index])
		var calls = outbound.size()
		expect(ctrl.submit(intent).get("ok",false),"Natural input submitted")
		if not await pump("interpret"):
			return
		var schema: Dictionary = ctrl.adapter.transport.supplied_schema
		expect(schema["properties"].has("items") and schema.get("required",[]).is_empty(),"Translator transport schema accepts empty lookup object")
		reply({})
		if not await pump("narrate"):
			return
		var packet = ctrl.inspect_dm_packet()
		var attempt = ctrl.inflight.duplicate(true)
		expect(packet.get("player_text")==inputs[index] and packet["outbound"]["sha256"]==outbound.back()["prompt"].sha256_text() and packet["outbound"]["attempt_id"]==attempt["attempt_id"],"Exact command, prompt hash and attempt survive to DM")
		var dm_schema: Dictionary = ctrl.adapter.transport.supplied_schema
		expect(dm_schema.get("type")=="object" and not dm_schema.has("anyOf") and dm_schema["properties"]["geography"]=={"type":"object"} and dm_schema["properties"].has("check"),"DM provider gets a compact stage-specific schema")
		var text = "The innkeeper turns toward the table."
		var response = {"text":text}
		if index==1:
			response.merge({"geography":{"facts":[{"kind":"unsupported"}]},"story":[{}],"discoveries":[{}]})
		if index==2:
			response=combined(text)
		reply(response)
		if not await pump("idle"):
			return
		var settled = session.settlement(id,intent["request_id"])
		var token = session.token(id)
		var source = session.source(token,settled.get("event_id"))
		expect(settled.get("status")=="committed" and source.get("data",{}).get("text")==text and outbound.size()-calls==2,"Prose commits in two calls with or without optional world data")
		expect(not ctrl.receive(attempt,response).get("ok",false) and session.token(id)["revision"]==token["revision"],"Duplicate response cannot mutate settled turn")
	var guarded = pipeline_intent(id,"I ask whether the road is open.")
	expect(ctrl.submit(guarded).get("ok",false),"Consequential response test submitted")
	if not await pump("interpret"):
		return
	reply({})
	if not await pump("narrate"):
		return
	var before = session.token(id)
	reply({"text":"The party is in another town.","requires_world_update":true,"geography":{}})
	for _i in range(40):
		await process_frame
		if ctrl.active().get("stage")=="retry":
			break
	expect(ctrl.active().get("stage")=="retry" and session.token(id)["revision"]==before["revision"],"Invalid consequential proposal holds before any commit")

func typed_invite_case(id: String,mara: String) -> void:
	var original = "  I invite Mara to join my party.  "
	var before = session.token(id)
	var calls = outbound.size()
	workspace.composer.text=original
	workspace.submit_chat()
	if not await pump("narrate"):
		return
	var packet = ctrl.inspect_dm_packet()
	expect(packet.get("player_text")==original and packet.get("lookup_facts",[])[0]["invited_npc"]["id"]==mara,"Typed invitation reaches DM with exact command and visible NPC")
	expect(outbound.size()-calls==1 and outbound.back()["stage"]=="narrate","Invitation uses one provider call")
	reply(combined("Mara smiles. ‘Thanks, but I’m staying here tonight.’"))
	if not await pump("idle"):
		return
	var after = session.token(id)
	var rows = SQL.run(session.path(id),[SQL.stmt("SELECT actor_id FROM party_members WHERE actor_id=? AND status='member'",[mara])],true)
	expect(after["actor"]==before["actor"] and rows.get("ok",false) and rows["results"][0].is_empty(),"Invitation settles without changing the actor or roster")
	expect(outbound.size()-calls==1,"No second provider call after NPC responds")

func conditional_check_case(id: String) -> void:
	var intent = pipeline_intent(id,"I try to work out what the inn's carved emblem represents.")
	var start = outbound.size()
	expect(ctrl.submit(intent).get("ok",false),"Conditional check accepted")
	if not await pump("interpret"):
		return
	reply({})
	if not await pump("narrate"):
		return
	ctrl.pause_reconcile=true
	var check = {"ability":"int","skill":null,"difficulty":"nearly_impossible"}
	var branches = {"success":"The pattern clicks into place.","failure":"The pattern remains puzzling."}
	reply({"check":check,"branches":branches})
	for _i in range(60):
		await process_frame
		if ctrl.active().get("stage")=="reconcile":
			break
	if not expect(ctrl.active().get("stage")=="reconcile","Selected branch staged from durable roll"):
		return
	var pending = session.settlement(id,intent["request_id"])
	var stored = ctrl.registry.resolver.store.receipt_by_id(id,pending["logical_turn_id"])
	if not expect(stored.get("found",false) and stored["receipt"]["rolls"].size()==1,"One durable roll"):
		return
	var chosen = stored["receipt"]["results"][0]["outcome"]
	expect(ctrl.active()["candidate"]["text"]==branches[chosen] and outbound.size()-start==2,"Verified check selects the matching prose in two calls")
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	await process_frame
	if not bind(id) or not await pump("idle"):
		return
	var after = ctrl.registry.resolver.store.receipt_by_id(id,pending["logical_turn_id"])
	expect(after["receipt"]==stored["receipt"] and outbound.size()-start==2,"Reopening preserves the roll and uses no extra provider call")
	var settled = session.settlement(id,intent["request_id"])
	var event = session.source(session.token(id),settled["event_id"])
	expect(event.get("data",{}).get("text")==branches[chosen],"Only the chosen branch enters narration history")

	intent=pipeline_intent(id,"I try to remember who designed the emblem.")
	start=outbound.size()
	expect(ctrl.submit(intent).get("ok",false),"Check-only request accepted")
	if not await pump("interpret"):
		return
	reply({})
	if not await pump("narrate"):
		return
	var serial = ctrl.adapter.serial
	reply({"check":check})
	if not await pump("narrate",serial):
		return
	var packet = ctrl.inspect_dm_packet()
	expect(packet.get("receipt",{}).get("rolls",[]).size()==1 and outbound.size()-start==3,"Check-only path returns the verified roll to a third call")
	reply(combined("The carving offers no clear answer."))
	await pump("idle")

func dm_first_case(id: String) -> void:
	var before = session.token(id)
	var command = "I cast Mage Hand and use it to carry my knife and cut the rope."
	var request = pipeline_intent(id,command)
	var calls = outbound.size()
	expect(ctrl.submit(request).get("ok",false),"Unstructured spell command accepted")
	if not await pump("interpret"):
		return
	expect(not ctrl.adapter.payload.has("catalogue") and ctrl.adapter.payload["intent"]["args"]["text"]==command,"Translator receives exact command without action catalogue")
	reply({"spells":["Mage Hand"],"items":["knife"]})
	if not await pump("idle"):
		return
	expect(outbound.size()==calls+1 and ctrl.status.contains("knife") and session.token(id)["revision"]==before["revision"],"Missing item locally rejected without DM")
	var missing_spell = pipeline_intent(id,"I cast Mage Hand.")
	calls=outbound.size()
	expect(ctrl.submit(missing_spell).get("ok",false),"Unavailable spell submitted")
	if not await pump("interpret"):
		return
	reply({"spells":["Mage Hand"]})
	if not await pump("idle"):
		return
	expect(outbound.size()==calls+1 and ctrl.status.contains("Mage Hand"),"Unavailable spell denied locally")
	var talk = pipeline_intent(id,"  What if I could cast Mage Hand?  ")
	calls=outbound.size()
	expect(ctrl.submit(talk).get("ok",false),"Hypothetical accepted")
	if not await pump("interpret"):
		return
	reply({"spells":["Mage Hand"]})
	if not await pump("narrate"):
		return
	var packet = ctrl.inspect_dm_packet()
	if not expect(not packet.is_empty() and packet["unresolved_intent"],"DM receives the unresolved packet"):
		return
	expect(packet["player_text"]==talk["args"]["text"] and not packet.has("receipt") and session.token(id)["revision"]==before["revision"],"Exact command reaches DM before mechanics")
	expect(packet["lookup_facts"][0]["records"][0]["index"]=="mage-hand" and not packet["lookup_facts"][0]["access"]["slot_required"],"Pinned Mage Hand cantrip has no slot requirement")
	expect(packet["outbound"]["sha256"]==outbound.back()["prompt"].sha256_text(),"DM prompt hash exact")
	reply(combined("Mara smiles at the idea."))
	if not await pump("idle"):
		return
	expect(outbound.size()==calls+2 and session.token(id)["actor"]==before["actor"],"Hypothetical settles with no mechanics or extra calls")
	var ration: Dictionary = {}
	for item in ctrl.view["interaction_extension"]["inventory_instances"]:
		if item["definition_id"]=="rations-1-day":
			ration=item
	if not expect(not ration.is_empty(),"Ration available"):
		return
	var use = pipeline_intent(id,"I eat my "+ration["name"])
	calls=outbound.size()
	expect(ctrl.submit(use).get("ok",false),"Item action accepted")
	if not await pump("interpret"):
		return
	reply({"items":[ration["name"]]})
	if not await pump("narrate"):
		return
	var serial = ctrl.adapter.serial
	reply({"mechanics":{"kind":"item_use","args":{"instance_id":ration["instance_id"],"quantity":1,"target_id":before["actor_id"]}}})
	if not await pump("narrate",serial):
		return
	packet=ctrl.inspect_dm_packet()
	expect(packet.get("settlement",{}).get("result",{}).get("consumed")==1 and outbound.size()==calls+3,"DM receives actual item settlement")
	reply(combined("The ration tastes of dried grain."))
	if not await pump("idle"):
		return
	expect(session.settlement(id,use["request_id"]).get("result",{}).get("consumed")==1,"One durable consumption")
	var cast = pipeline_intent(id,"I cast Cure Wounds on myself.")
	var spell = {"spell_id":"cure-wounds","source":"prepared","slot_level":1,"target_id":before["actor_id"]}
	calls=outbound.size()
	var prior_spent = session.token(id)["actor"]["spellcasting"]["slots"]["1"]["spent"]
	expect(ctrl.submit(cast).get("ok",false),"Leveled cast submitted")
	if not await pump("interpret"):
		return
	reply({"spells":["Cure Wounds"]})
	if not await pump("narrate"):
		return
	expect(session.token(id)["actor"]["spellcasting"]["slots"]["1"]["spent"]==prior_spent,"Spell lookup does not debit a slot")
	serial=ctrl.adapter.serial
	reply({"mechanics":{"kind":"spell_cast","args":spell}})
	if not await pump("narrate",serial):
		return
	var leased = ctrl.inspect_dm_packet()
	var settled = session.settlement(id,cast["request_id"])
	expect(leased.get("settlement",{}).get("result",{}).get("rolls",[]).size()==1 and settled["result"]["slot_spent"]==prior_spent+1 and outbound.size()==calls+3,"Leveled cast produces a local roll and one debit")
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	await process_frame
	if not bind(id) or not await pump("narrate"):
		return
	expect(session.settlement(id,cast["request_id"])==settled and ctrl.inspect_dm_packet().get("settlement",{}).get("result",{})==settled["result"],"Recovered cast preserves receipt, roll and slot debit")
	reply(combined("The healing magic settles."))
	if not await pump("idle"):
		return
	await pipeline_inscription_case(id)


# Focused v0.0.30 mode. The legacy suite includes older provider contracts.
func context_pipeline_case(id: String,mara: String,shield: String) -> void:
	var legacy_rules = ctrl.context_builder.rules({"settlement":{"result":{"rule_refs":["movement"]}},"selected_context":[],"situational_context":{}},"equip")
	expect(legacy_rules.get("ok",false) and legacy_rules["records"].any(func(row): return row["id"]=="movement"),"Legacy equipment settlement rule string still resolves")
	var state = session.token(id)
	var original = "  I ask Mara about the Oak Inn.  "
	var intent = {"schema_version":"1","campaign_id":id,"actor_id":state["actor_id"],"request_id":session.make_id(),"expected_revision":state["revision"],"kind":"chat","args":{"text":original}}
	var counter = ctrl.context_builder.memory_reads
	var scene_counter = ctrl.scene_reads
	var calls = outbound.size()
	expect(ctrl.submit(intent).get("ok",false),"Exact command accepted")
	if not await pump("interpret"):
		return
	var input = ctrl.adapter.payload
	expect(input["intent"]["args"]["text"]==original and input["revision"]==state["revision"],"Exact command and revision reach interpreter")
	expect(input["references"]["npcs"].any(func(npc): return npc["id"]==mara) and input["references"]["inventory"].any(func(item): return item["instance_id"]==shield) and input["references"]["locations"].any(func(place): return place["id"]==state["location_id"]),"Public NPC, location and owned item IDs included")
	expect(not input.has("rules") and not input.has("character") and not input.has("story") and not input.has("recent_moves") and not input.has("scene"),"Comprehensive fields excluded")
	expect(ctrl.context_builder.memory_reads==counter and ctrl.scene_reads==scene_counter,"No DM context reads before first response")
	var lookups = [
		{"kind":"rule_record","args":{"category":"spells","id":"cure-wounds"},"limit":1},
		{"kind":"rule_record","args":{"category":"skills","id":"persuasion"},"limit":1},
		{"kind":"actors","args":{"location_id":state["location_id"]},"limit":4}
	]
	var envelope = {"kind":"conversation","args":{"text":original},"queries":lookups}
	var stale = ctrl.inflight.duplicate(true)
	stale["revision"]+=1
	expect(not ctrl.receive_interpreter_envelope(stale,envelope).get("ok",false),"Stale envelope rejected")
	reply(envelope)
	if not await pump("narrate"):
		return
	var packet = ctrl.inspect_dm_packet()
	if not expect(not packet.is_empty(),"Completed packet inspectable during dispatch"):
		return
	var outbound_prompt: String = outbound.back()["prompt"]
	expect(packet["player_text"]==original and packet["binding"]["intent_request_id"]==intent["request_id"],"DM original input and intent binding")
	expect(packet["outbound"]["prompt"]==outbound_prompt and packet["outbound"]["sha256"]==outbound_prompt.sha256_text(),"Inspected instructions and outbound prompt are identical")
	expect(outbound_prompt.contains(NARRATOR.load_prompt()) and outbound_prompt.contains("WORLD UPDATE SCHEMA"),"Existing DM instructions and response contract")
	expect(packet["selected_context"].size()==lookups.size() and outbound_prompt.contains("cure-wounds") and outbound_prompt.contains("persuasion"),"All requested lookup records reach DM")
	expect(packet["rules"].any(func(row): return row["id"]=="time"),"Engine attaches mandatory omitted time rule")
	expect(outbound.size()-calls==2 and outbound[calls]["stage"]=="interpret" and outbound[calls+1]["stage"]=="narrate","Exactly one interpreter and one narration transport call")
	reply(combined("Mara nods quietly."))
	if not await pump("idle"):
		return
	expect(ctrl.inspect_dm_packet().is_empty(),"Settled packet is unavailable as an active attempt")

	for case in [
		{"response":{"status":"clarification","message":"Which item?"},"stage":"clarification"},
		{"response":{"kind":"conversation","args":{"text":"Invented"},"queries":[{"kind":"unknown","args":{},"limit":1}]},"stage":"clarification"},
		{"response":{"kind":"equip","args":{"instance_id":shield,"slot":"ring","grip":"worn"},"queries":[]},"stage":"idle"}
	]:
		var before = session.token(id)
		var attempt = intent.duplicate(true)
		attempt["expected_revision"]=before["revision"]
		attempt["request_id"]=session.make_id()
		calls=outbound.size()
		expect(ctrl.submit(attempt).get("ok",false),"Negative route submitted")
		if not await pump("interpret"):
			return
		reply(case["response"])
		for _i in range(30):
			await process_frame
			if ctrl.active().get("stage","idle")==case["stage"]:
				break
		expect(ctrl.active().get("stage","idle")==case["stage"] and outbound.size()-calls==1 and session.token(id)["revision"]==before["revision"],"Ambiguous, invalid or illegal response does not reach DM or mutate state")
		if not ctrl.active().is_empty():
			expect(ctrl.cancel().get("ok",false),"Cancel unresolved negative test")
			if not await pump("idle"):
				return

	# First action settles, second action starts from the new revision. Reopen
	# in the middle to exercise durable receipt and selected query recovery.
	var sequence = pipeline_intent(id,"I ask Mara about the inn and eat a ration.")
	var ration = ""
	for item in ctrl.view["interaction_extension"]["inventory_instances"]:
		if item["definition_id"]=="rations-1-day":
			ration=item["instance_id"]
	if not expect(not ration.is_empty(),"Ration fixture available"):
		return
	var sequence_calls = outbound.size()
	expect(ctrl.submit(sequence).get("ok",false),"Dependent sequence accepted")
	if not await pump("interpret"):
		return
	reply({"steps":[{"kind":"conversation","args":{"text":"Ask"}},{"kind":"item_use","args":{"instance_id":ration,"quantity":1,"target_id":state["actor_id"]}}],"queries":[lookups[0],{"kind":"item_definition","args":{"definition_id":"rations-1-day"},"limit":1}]})
	if not await pump("narrate"):
		return
	var serial = ctrl.adapter.serial
	reply(combined("Mara gestures toward the hearth."))
	if not await pump("narrate",serial):
		return
	var later = ctrl.inspect_dm_packet()
	if not expect(not later.is_empty() and later["recent_outcomes"].size()==1,"Dependent packet contains one verified predecessor"):
		return
	expect(later["recent_outcomes"][0].has("receipt") and later["selected_context"][0]["revision"]==sequence["expected_revision"],"Earlier receipt and historical enquiry revision retained")
	expect(later.get("settlement",{}).get("result",{}).get("consumed")==1 and later["selected_context"].size()==2 and later["rules"].any(func(row): return row["category"]=="equipment" and row["id"]=="rations-1-day"),"Ration settlement, requested item lookup and pinned item rule reach DM")
	expect(outbound.size()-sequence_calls==3,"Two dependent turns share one interpreter call")
	var before_restart = session.token(id)
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	await process_frame
	if not bind(id) or not await pump("narrate"):
		return
	var rebuilt = ctrl.inspect_dm_packet()
	expect(not rebuilt.is_empty() and rebuilt["binding"]==later["binding"] and session.token(id)["revision"]==before_restart["revision"],"Interrupted narration rebuilds packet from same committed turn")
	expect(outbound.size()-sequence_calls==4 and outbound.back()["stage"]=="narrate","Restart retries narration only")
	reply(combined("The ration tastes of dried grain."))
	if not await pump("idle"):
		return
	await pipeline_inscription_case(id)

func pipeline_intent(id: String,text: String) -> Dictionary:
	var state = session.token(id)
	return {"schema_version":"1","campaign_id":id,"actor_id":state["actor_id"],"request_id":session.make_id(),"expected_revision":state["revision"],"kind":"chat","args":{"text":text}}

func pipeline_inscription_case(id: String) -> void:
	# Insert an owned custom definition and its existing inventory mirror in
	# the disposable fixture. The production inspection transaction stays real.
	var state = session.token(id)
	var actor = state["actor_id"]
	var definition = "custom-pipeline-token"
	var instance = session.make_id()
	var event = state["turn"]
	var seeds = SQL.run(session.path(id),[
		SQL.stmt("INSERT INTO events(turn,game_time,kind,payload) VALUES(?,?,'gameplay_change',?)",[event,"Unspecified",JSON.stringify({"text":"A fixture token is present.","visibility":"player"})]),
		SQL.stmt("INSERT INTO item_definitions(id,origin,name,unit_weight_lb,attributes,source_event_id) VALUES(?,'custom','Amber Token',0,?,last_insert_rowid())",[definition,JSON.stringify({"name":"Amber Token","category":"object","description":"A polished amber token."})]),
		SQL.stmt("INSERT INTO item_instances(id,definition_id,actor_id,quantity,condition,attunement,provenance) VALUES(?,?,?,1,'intact','not_required','{}')",[instance,definition,actor]),
		SQL.stmt("INSERT INTO inventory(actor_id,item_id,quantity,payload) VALUES(?,?,1,?)",[actor,definition,JSON.stringify({"item_id":definition,"quantity":1,"equipped":false})]),
		SQL.stmt("UPDATE world_state SET revision=revision+1 WHERE campaign_id=?",[id])
	])
	if not expect(seeds.get("ok",false),"Custom inscription fixture seed"):
		return
	ctrl.refresh()
	for already_saved in [false,true]:
		var calls = outbound.size()
		var intent = pipeline_intent(id,"Read the inscription on Amber Token")
		expect(ctrl.submit(intent).get("ok",false),"Inscription requested")
		if not await pump("interpret"):
			return
		reply({"items":["Amber Token"]} if "--dm-first" in OS.get_cmdline_user_args() else {"kind":"inspect_inscription","args":{"instance_id":instance},"queries":[]})
		if not already_saved:
			if not await pump("attribute"):
				return
			reply({"inscription":"Morning tide"})
		if not await pump("idle"):
			return
		expect(outbound.size()-calls==(1 if already_saved else 2) and ctrl.status.contains("Morning tide"),"Inscription uses one bounded proposal only on first read and no narration")

func persistent_npc_location(id: String) -> void:
	var before=durable_snapshot(id)
	var calls=outbound.size()
	var input="I ask Mara about the nearby village and the people here."
	workspace.composer.text=input
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	reply({"world":["Oak Inn"]} if "--dm-map" in OS.get_cmdline_user_args() else {"kind":"conversation","args":{"text":input}})
	if not await pump("narrate"):
		return
	var location_id=session.token(id)["location_id"]
	var place_evidence="Mara describes Willowfen, a village. Willowfen lies north of Oak Inn. The Willow Road connects Oak Inn and Willowfen."
	var npc_evidence="Tessa, the weaver, is here."
	var response=combined(place_evidence+" "+npc_evidence)
	response["geography"]["facts"]=[
		{"kind":"place","subject":{"id":null,"local_key":"willowfen"},"name":"Willowfen","place_kind":"village","parent":null,"region":null,"position":null,"precision":"provisional","uncertainty_miles":null,"elevation_feet":null,"terrain":null,"footprint":[],"population":null,"occupancy":"unknown","asset_id":null,"description":null,"visibility":"player","evidence":place_evidence},
		{"kind":"npc_description","subject":{"id":null,"local_key":"tessa"},"location":{"id":location_id,"local_key":null},"name":"Tessa","occupation":"weaver","visibility":"player","evidence":npc_evidence}
	]
	if "--dm-map" in OS.get_cmdline_user_args():
		expect(outbound.back()["prompt"].contains("Map updates belong in geography.facts"),"Existing map function is explicit in the DM prompt")
		var origin = {"id":location_id,"local_key":null}
		var village = {"id":null,"local_key":"willowfen"}
		response["geography"]["facts"].append({"kind":"relationship","from":origin,"to":village,"relation_kind":"relative","direction":"north","distance_miles":null,"precision":"provisional","visibility":"player","evidence":"Willowfen lies north of Oak Inn."})
		response["geography"]["facts"].append({"kind":"route","subject":{"id":null,"local_key":"willow-road"},"from":origin,"to":village,"name":"Willow Road","route_kind":"road","precision":"provisional","distance_miles":null,"points":[],"visibility":"player","evidence":"The Willow Road connects Oak Inn and Willowfen."})
	reply(response)
	if not await pump("idle"):
		return
	expect(outbound.size()-calls==2,"Persistent world turn exactly two provider requests")
	var after=durable_snapshot(id)
	expect(after["actor"]==before["actor"] and after["owned"]==before["owned"],"Descriptive world creation preserves player mechanics")
	var statements=[
		SQL.stmt("SELECT l.id,l.kind,w.source_event_id FROM locations l JOIN world_places w ON w.location_id=l.id WHERE l.name=?",["Willowfen"]),
		SQL.stmt("SELECT a.id,a.location_id,a.payload,w.source_event_id FROM actors a JOIN world_links w ON w.actor_id=a.id WHERE a.kind='npc' AND json_extract(a.payload,'$.name')=?",["Tessa"])
	]
	var persisted=SQL.run(base.path_for(id),statements,true)
	if not expect(persisted.get("ok",false),"Read campaign-local persisted world records"):
		return
	var results=persisted.get("results",[])
	if not expect(results.size()==2,"World record query results"):
		return
	var places: Array=results[0]
	var npcs: Array=results[1]
	if not expect(places.size()==1 and npcs.size()==1,"Exactly one persisted village and NPC"):
		return
	expect(not str(places[0]["id"]).is_empty() and places[0]["kind"]=="village" and places[0]["source_event_id"]!=null,"Village stable identity and committed source")
	expect(not str(npcs[0]["id"]).is_empty() and npcs[0]["location_id"]==location_id and npcs[0]["source_event_id"]!=null,"NPC stable identity and local campaign source")
	var npc=JSON.parse_string(npcs[0]["payload"])
	expect(npc is Dictionary and npc.get("id")==npcs[0]["id"] and npc.get("occupation")=="weaver","NPC persisted identity and occupation")
	expect(SQL.run(base.path_for(id),statements,true)==persisted,"World identities stable on independent SQLite read")
	if "--dm-map" in OS.get_cmdline_user_args():
		var map = preload("res://world/world_store.gd").new().map_view(id)
		if not expect(map.get("ok",false),"Read committed Godot map"):
			return
		var village_id = places[0]["id"]
		expect(map["locations"].any(func(row): return row["id"]==village_id and row["status"]=="reported" and row["x"]==null),"Reported place appears on map while coordinates remain unresolved")
		expect(map["routes"].any(func(row): return row["name"]=="Willow Road" and row["to_id"]==village_id),"Same-reply route reaches the committed map")
		expect(map["relationships"].any(func(row): return row["to_id"]==village_id and row["direction"]=="north"),"Same-reply relative direction reaches the committed map")
		expect(session.token(id)["location_id"]==location_id,"Map update does not move the player")
		var groups = preload("res://cartography/map_model.gd").relative_neighbors(map)
		expect(groups.get(Vector2.UP,[]).any(func(row): return row["id"]==village_id),"Reported location is available north of the party in the unscaled sketch")


func geography_discovery_case(id: String) -> void:
	var rows=SQL.run(base.path_for(id),[SQL.stmt("SELECT id FROM locations WHERE name=?",["Willowfen"])],true)
	if not expect(rows.get("ok",false) and rows["results"][0].size()==1,"Existing named location"):
		return
	var village=rows["results"][0][0]["id"]
	var location=session.token(id)["location_id"]
	var before=durable_snapshot(id)
	var calls=outbound.size()
	var input="I ask about the road and look at the counter."
	workspace.composer.text=input
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	reply({"kind":"conversation","args":{"text":input}})
	if not await pump("narrate"):
		return
	var evidence="An abandoned carved amber tally lies on the counter, free to take."
	var relation="Willowfen lies north of Oak Inn."
	var road="The Willow Road connects Oak Inn and Willowfen."
	var response=combined(relation+" "+road+" "+evidence)
	var from={"id":location,"local_key":null}
	var to={"id":village,"local_key":null}
	response["geography"]["facts"]=[
		{"kind":"relationship","from":from,"to":to,"relation_kind":"relative","direction":"north","distance_miles":null,"precision":"provisional","visibility":"player","evidence":relation},
		{"kind":"route","subject":{"id":null,"local_key":"willow-road"},"from":from,"to":to,"name":"Willow Road","route_kind":"road","precision":"provisional","distance_miles":null,"points":[],"visibility":"player","evidence":road}
	]
	var definition={"name":"Carved amber tally","category":"gear","description":"A carved amber tally.","unit_weight_lb":0.1,"cost_cp":1,"properties":[],"charges_max":null,"attunement_required":false}
	response["discoveries"]=[
		{"kind":"define_custom","evidence":evidence,"args":{"definition":definition,"official_equivalent_id":null}},
		{"kind":"loot_discover","evidence":evidence,"args":{"location_id":location,"name":"Counter discovery","items":[{"definition_id":"@0","quantity":1,"charges":null,"condition":"intact","attunement":"not_required"}],"coins":money(0)}}
	]
	var identity=ctrl.inflight.duplicate(true)
	reply(response)
	if not await pump("idle"):
		return
	var db=discovery_db_snapshot(id)
	await rejected_response(id,identity,response,false,"Duplicate definition and discovery response")
	expect(discovery_db_snapshot(id)==db,"Duplicate definition/discovery did not change persisted rows")
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	await process_frame
	if not bind(id):
		return
	await wait_frames()
	expect(discovery_db_snapshot(id)==db,"Controller reopening preserves world, loot and event identities")
	expect(outbound.size()-calls==2,"Geography and discovery exactly two provider calls")
	var after=durable_snapshot(id)
	expect(after["actor"]==before["actor"] and after["owned"]==before["owned"],"Discovery does not grant resources")
	var persisted=SQL.run(base.path_for(id),[
		SQL.stmt("SELECT l.id,l.x,l.y,d.status FROM locations l JOIN world_discovery d ON d.location_id=l.id WHERE l.name=?",["Willowfen"]),
		SQL.stmt("SELECT from_id,to_id,direction FROM geographic_relationships WHERE from_id=? AND to_id=?",[location,village]),
		SQL.stmt("SELECT r.from_id,r.to_id,d.status FROM world_routes r JOIN world_discovery d ON d.route_id=r.id WHERE r.name=?",["Willow Road"]),
		SQL.stmt("SELECT request_id,request_payload,result_payload FROM gameplay_requests WHERE kind IN ('define_custom','loot_discover') AND status='committed' ORDER BY settled_revision")
	],true)
	if not expect(persisted.get("ok",false),"Persisted geography and discovery query"):
		return
	var result=persisted["results"]
	if not expect(result[0].size()==1 and result[1].size()==1 and result[2].size()==1 and result[3].size()==2,"Exact persisted world and discovery rows"):
		return
	expect(result[0][0]["id"]==village and result[0][0]["x"]==null and result[0][0]["y"]==null and result[0][0]["status"]=="reported","Stable reported village with unknown coordinates")
	expect(result[1][0]["direction"]=="north" and result[2][0]["from_id"]==location and result[2][0]["to_id"]==village and result[2][0]["status"]=="reported","Persisted relationship and untraveled route")
	var defined=JSON.parse_string(result[3][0]["result_payload"])
	var request=JSON.parse_string(result[3][1]["request_payload"])
	var settlement=session.settlement(id,result[3][1]["request_id"])
	expect(request["args"]["items"][0]["definition_id"]==defined["definition_id"] and request["args"]["location_id"]==location,"Proposal-local definition resolves to persistent ID at current location")
	expect(settlement.get("request")==request and request["campaign_id"]==id and request["request_id"]==result[3][1]["request_id"],"Exact durable transformed request")
	var source=session.source(session.token(id),request["args"]["source_event_id"])
	expect(source.get("kind")=="narration" and str(source.get("data",{}).get("text","")).contains(evidence),"Discovery binds committed narrative evidence")
	var loot=ctrl.view["interaction_extension"]["loot_containers"]
	expect(loot.size()==1 and loot[0]["items"][0]["name"]=="Carved amber tally","Discovered item remains in local loot")

func discovery_db_snapshot(id: String) -> Dictionary:
	return SQL.run(base.path_for(id),[
		SQL.stmt("SELECT * FROM gameplay_requests ORDER BY request_id"),
		SQL.stmt("SELECT * FROM locations ORDER BY id"),
		SQL.stmt("SELECT * FROM world_places ORDER BY location_id"),
		SQL.stmt("SELECT * FROM world_routes ORDER BY id"),
		SQL.stmt("SELECT * FROM actors ORDER BY id"),
		SQL.stmt("SELECT * FROM geographic_relationships ORDER BY id"),
		SQL.stmt("SELECT * FROM world_discovery ORDER BY id"),
		SQL.stmt("SELECT * FROM item_definitions ORDER BY id"),
		SQL.stmt("SELECT * FROM item_instances ORDER BY id"),
		SQL.stmt("SELECT * FROM loot_containers ORDER BY id"),
		SQL.stmt("SELECT * FROM events ORDER BY id"),
		SQL.stmt("SELECT * FROM story_history ORDER BY id")
	],true)

func discovery_negative_cases(id: String,sibling_id: String) -> void:
	var input="I look at the shelf."
	var evidence="A discarded copper token rests on the shelf."
	var location=session.token(id)["location_id"]
	var definition={"name":"Shelf copper token","category":"gear","description":"A copper token.","unit_weight_lb":0.1,"cost_cp":1,"properties":[],"charges_max":null,"attunement_required":false}
	var start=outbound.size()
	workspace.composer.text=input
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	reply({"kind":"conversation","args":{"text":input}})
	if not await pump("narrate"):
		return
	ctrl.pause_discovery=true
	var response=combined(evidence)
	response["discoveries"]=[
		{"kind":"define_custom","evidence":evidence,"args":{"definition":definition,"official_equivalent_id":null}},
		{"kind":"loot_discover","evidence":evidence,"args":{"location_id":location,"name":"Shelf discovery","items":[{"definition_id":"@0","quantity":1,"charges":null,"condition":"intact","attunement":"not_required"}],"coins":money(0)}}
	]
	reply(response)
	await wait_frames()
	if not expect(ctrl.active().get("stage")=="post_story","Pause at committed narration"):
		return
	ctrl.step_discovery()
	await wait_frames()
	var original=ctrl.active().duplicate(true)
	if not expect(original.get("discovery_index")==1 and original.get("discovery_receipts",{}).has("0"),"First definition committed with provenance"):
		return
	var state=session.token(id)
	var rid=session.make_id()
	var args=ctrl.discovery_arguments(original,state,1,rid)
	if not expect(not args.is_empty(),"Legitimate transformed arguments reconstruct"):
		return
	var request=ctrl.tool_for(original["intent"],state,"loot_discover",args)
	request["request_id"]=rid
	original["story_request"]=request
	for label in ["forged provenance","item identifier","quantity","currency","location","source","cross campaign","legacy provenance"]:
		var job=original.duplicate(true)
		var req=job["story_request"]
		match label:
			"forged provenance":
				job["discovery_receipts"]["0"]["request_id"]=session.make_id()
			"item identifier":
				req["args"]["items"][0]["definition_id"]="dagger"
			"quantity":
				req["args"]["items"][0]["quantity"]=2
			"currency":
				req["args"]["coins"]["gp"]=10
			"location":
				req["args"]["location_id"]=session.make_id()
			"source":
				req["args"]["source_event_id"]=0
			"cross campaign":
				job["discovery_receipts"]["0"]["campaign_id"]=sibling_id
			"legacy provenance":
				job.erase("discovery_receipts")
		if not expect(ctrl.update_active(job),label+" persist disposable pending fixture"):
			return
		var before=durable_snapshot(id)
		var db=discovery_db_snapshot(id)
		var calls=outbound.size()
		expect(not ctrl.discovery_request_valid(req,job,session.token(id)),label+" shared validator rejects")
		ctrl.step_discovery()
		await wait_frames()
		var after=durable_snapshot(id)
		expect(after["actor"]==before["actor"] and after["owned"]==before["owned"] and after["revision"]==before["revision"],label+" resources and revision unchanged")
		expect(discovery_db_snapshot(id)==db,label+" no new settlement or world row")
		expect(after["view"].get("interaction_extension",{}).get("loot_containers")==before["view"].get("interaction_extension",{}).get("loot_containers"),label+" loot unchanged")
		expect(ctrl.active().get("discovery_index")==1 and ctrl.active().get("stage")=="retry",label+" cursor retained")
		expect(outbound.size()==calls,label+" no provider request")
	# Even genuine older narration cannot replace the exact action's source.
	var earlier=SQL.run(base.path_for(id),[SQL.stmt("SELECT id,payload FROM events WHERE kind='narration' AND id<>? AND json_extract(payload,'$.text') LIKE '%amber tally%' ORDER BY id DESC LIMIT 1",[original["narration_event_id"]])],true)
	if not expect(earlier.get("ok",false) and earlier["results"][0].size()==1,"Unrelated committed narration fixture"):
		return
	var wrong_source=original.duplicate(true)
	wrong_source["narration_event_id"]=int(earlier["results"][0][0]["id"])
	expect(not ctrl.committed_job_source(wrong_source,state),"Unrelated committed narration cannot authorize deferred work")
	if not expect(ctrl.update_active(wrong_source),"Persist unrelated narration pointer fixture"):
		return
	var source_db=discovery_db_snapshot(id)
	var source_calls=outbound.size()
	ctrl.step_discovery()
	await wait_frames()
	expect(ctrl.active().get("stage")=="retry" and ctrl.active().get("discovery_index")==1 and discovery_db_snapshot(id)==source_db and outbound.size()==source_calls,"Wrong source stopped before deferred writes")
	# A committed SQL row with the right ID but altered request is not a receipt.
	var altered=request.duplicate(true)
	altered["args"]["items"][0]["quantity"]=2
	var forged=SQL.run(base.path_for(id),[SQL.stmt("INSERT INTO gameplay_requests(request_id,actor_id,kind,expected_revision,status,request_payload,result_payload,settled_revision,event_id) VALUES(?,?,?,?,'committed',?,?,?,?)",[rid,request["actor_id"],request["kind"],request["expected_revision"],JSON.stringify(altered),JSON.stringify({}),request["expected_revision"],request["args"]["source_event_id"]])])
	if not expect(forged.get("ok",false),"Inject mismatched SQL settlement"):
		return
	if not expect(ctrl.update_active(original),"Persist pending request against forged settlement"):
		return
	var forged_before=durable_snapshot(id)
	var forged_db=discovery_db_snapshot(id)
	var forged_calls=outbound.size()
	ctrl.step_discovery()
	await wait_frames()
	expect(ctrl.active().get("stage")=="retry" and ctrl.active().get("discovery_index")==1,"Forged settlement cannot advance cursor")
	expect(durable_snapshot(id)==forged_before and discovery_db_snapshot(id)==forged_db,"Forged settlement cannot mutate authoritative state")
	expect(outbound.size()==forged_calls,"Forged settlement triggers no provider call")
	if not expect(SQL.run(base.path_for(id),[SQL.stmt("DELETE FROM gameplay_requests WHERE request_id=?",[rid])]).get("ok",false),"Remove disposable forged settlement"):
		return
	if not expect(ctrl.update_active(original),"Restore exact legitimate pending discovery"):
		return
	ctrl.step_discovery()
	await wait_frames()
	if not expect(ctrl.active().get("discovery_index")==2,"Legitimate discovery advances once"):
		return
	var settled=ctrl.active().duplicate(true)
	var before=durable_snapshot(id)
	var db=discovery_db_snapshot(id)
	# Replaying the exact already committed request must reconcile without a write.
	if not expect(ctrl.update_active(original),"Replay exact committed discovery"):
		return
	ctrl.step_discovery()
	await wait_frames()
	expect(ctrl.active().get("discovery_index")==2,"Duplicate reconciles exact cursor")
	expect(discovery_db_snapshot(id)==db and session.token(id)["revision"]==before["revision"],"Duplicate creates no settlement or world record")
	expect(REG.new().noncombat.read_owned(session.token(id),ctrl.actor_id)==before["owned"],"Duplicate grants no resources")
	expect(outbound.size()-start==2,"All discovery processing uses original two calls")
	ctrl.pause_discovery=false
	ctrl.step_discovery()
	await pump("idle")

func duplicate_world_envelope(id: String) -> void:
	var input="I ask about the nearby hamlets."
	var evidence="Mara describes Ashbrook, a village."
	var npc="Nell, the baker, is here."
	var calls=outbound.size()
	workspace.composer.text=input
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	reply({"kind":"conversation","args":{"text":input}})
	if not await pump("narrate"):
		return
	var identity=ctrl.inflight.duplicate(true)
	var response=combined(evidence+" "+npc)
	response["geography"]["facts"]=[
		{"kind":"place","subject":{"id":null,"local_key":"ashbrook"},"name":"Ashbrook","place_kind":"village","parent":null,"region":null,"position":null,"precision":"provisional","uncertainty_miles":null,"elevation_feet":null,"terrain":null,"footprint":[],"population":null,"occupancy":"unknown","asset_id":null,"description":null,"visibility":"player","evidence":evidence},
		{"kind":"npc_description","subject":{"id":null,"local_key":"nell"},"location":{"id":session.token(id)["location_id"],"local_key":null},"name":"Nell","occupation":"baker","visibility":"player","evidence":npc}
	]
	reply(response)
	if not await pump("idle"):
		return
	var db=discovery_db_snapshot(id)
	var counts=SQL.run(base.path_for(id),[
		SQL.stmt("SELECT id FROM locations WHERE name='Ashbrook'"),
		SQL.stmt("SELECT id FROM actors WHERE kind='npc' AND json_extract(payload,'$.name')='Nell'")
	],true)
	expect(counts.get("ok",false) and counts["results"][0].size()==1 and counts["results"][1].size()==1,"Structured response creates one village and NPC")
	await rejected_response(id,identity,response,false,"Duplicate structured world envelope")
	expect(discovery_db_snapshot(id)==db,"Duplicate structured envelope preserves persisted world rows")
	expect(outbound.size()-calls==2,"Structured duplicate no extra provider calls")

func candidate_reopen(id: String) -> void:
	var input="I ask Mara to describe the bridge again."
	var calls=outbound.size()
	workspace.composer.text=input
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	reply({"kind":"conversation","args":{"text":input}})
	if not await pump("narrate"):
		return
	ctrl.pause_reconcile=true
	var response=combined(TALK)
	reply(response)
	await wait_frames()
	if not expect(ctrl.active().get("stage")=="reconcile","Valid combined candidate persisted before reconciliation"):
		return
	var candidate=ctrl.active().duplicate(true)
	var hash_int=ctrl.canonical_outcome_hash({"roll":17,"nested":[2,{"spent":1}]})
	expect(not hash_int.is_empty() and hash_int==ctrl.canonical_outcome_hash({"roll":17.0,"nested":[2.0,{"spent":1.0}]}),"Outcome hash survives numeric JSON representation")
	expect(hash_int!=ctrl.canonical_outcome_hash({"roll":18,"nested":[2,{"spent":1}]}) and hash_int!=ctrl.canonical_outcome_hash({"roll":"17","nested":[2,{"spent":1}]}),"Outcome hash rejects changed roll and string coercion")
	var before=durable_snapshot(id)
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	await process_frame
	if not bind(id) or not await pump("idle"):
		return
	expect(outbound.size()-calls==2,"Persisted candidate reconciled locally without another AI request")
	expect(session.token(id)["actor"]==before["actor"] and REG.new().noncombat.read_owned(session.token(id),ctrl.actor_id)==before["owned"],"Candidate recovery does not repeat mechanical changes")
	var result=session.settlement(id,candidate["tool"]["request_id"])
	expect(result.get("status")=="committed" and result.get("event_id")!=null,"Candidate recovery settled original receipt")

func actor_generation_reopen(id: String) -> void:
	var input="I look around the inn."
	var evidence="A cooper named Darrin stands beside the hearth."
	var calls=outbound.size()
	workspace.composer.text=input
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	reply({"kind":"conversation","args":{"text":input}})
	if not await pump("narrate"):
		return
	ctrl.pause_discovery=true
	var response=combined(evidence)
	response["discoveries"]=[{"kind":"actor_generate","evidence":evidence,"args":{"template_ids":["commoner"],"existing_actor_id":null,"kind":"npc","name":"Darrin","occupation":"cooper","location_id":session.token(id)["location_id"],"visibility":"player","sheet_visibility":"private","possessions":[],"coins":money(0),"attitude":null}}]
	reply(response)
	await wait_frames()
	if not expect(ctrl.active().get("stage")=="post_story","Actor generation staged after committed narration"):
		return
	var job=ctrl.active().duplicate(true)
	var state=session.token(id)
	var rid=session.make_id()
	var args=ctrl.discovery_arguments(job,state,0,rid)
	if not expect(not args.is_empty(),"Actor generation reconstructs exact request"):
		return
	var req=ctrl.tool_for(job["intent"],state,"actor_generate",args)
	req["request_id"]=rid
	job["story_request"]=req
	if not expect(ctrl.update_active(job) and ctrl.prepare_review(req,"post_story"),"Persist and authorize actor generation"):
		return
	# Real registry transaction, deliberately stop before cursor acknowledgement.
	var created=ctrl.registry.execute(id,req,ctrl.review_tool)
	var settled=session.settlement(id,rid)
	if not expect(created.get("ok",false) and settled.get("status")=="committed","Actor generation committed before interrupted cursor"):
		return
	var db=discovery_db_snapshot(id)
	var actor_id=settled["result"]["actor_id"]
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	await process_frame
	if not bind(id) or not await pump("idle"):
		return
	expect(discovery_db_snapshot(id)==db and session.settlement(id,rid)==settled,"Interrupted actor generation reused exact settlement")
	var rows=SQL.run(base.path_for(id),[SQL.stmt("SELECT actor_id FROM actor_instances WHERE generation_key=?",[rid])],true)
	expect(rows.get("ok",false) and rows["results"][0].size()==1 and rows["results"][0][0]["actor_id"]==actor_id,"Recovered actor has original persistent identity")
	expect(outbound.size()-calls==2,"Actor recovery requires no extra provider requests")

func legacy_unsettled_authorization(id: String) -> void:
	var state=session.token(id)
	var intent={"schema_version":"1","campaign_id":id,"actor_id":state["actor_id"],"expected_revision":state["revision"],"request_id":session.make_id(),"kind":"chat","args":{"text":"I wait one minute."}}
	var req=ctrl.tool_for(intent,state,"wait",{"seconds":60,"text":intent["args"]["text"]})
	var job={"intent":intent,"stage":"execute","tool":req,"attempt":{},"context_review":{"request":req,"revision":state["revision"],"attempt_id":session.make_id(),"report":{"disposition":"supported","intent_evidence":intent["args"]["text"],"context":[],"ruling":{"safe_nonmechanical":true,"seconds":60,"establish_clock":false},"reason":"Legacy assessment fixture."}}}
	expect(ctrl.policy.validate_assessment(req,job["context_review"]["report"],job,state).get("ok",false),"Legacy fixture otherwise has valid ruling shape")
	if not expect(ctrl.update_active(job),"Persist unsettled legacy authorization"):
		return
	var before=durable_snapshot(id)
	var calls=outbound.size()
	ctrl.advance()
	await wait_frames()
	expect(ctrl.active().get("stage")=="clarification" and durable_snapshot(id)==before and outbound.size()==calls,"Unsettled legacy report cannot authorize a write")
	expect(not session.settlement(id,req["request_id"]).get("found",false),"No settlement created from legacy authorization")
	ctrl.cancel()
	await pump("idle")

func context_memory_case(id: String,sibling_id: String) -> void:
	var builder=ctrl.context_builder
	var state=session.token(id)
	var first=builder.memory(state,session)
	if not expect(first.get("ok",false) and first["moves"].size()==10 and not first["recap"].is_empty(),"Ten completed moves and persisted recap"):
		return
	var reads=builder.memory_reads
	var metrics=SQL.metrics()
	expect(builder.memory(state,session)==first and builder.memory_reads==reads and SQL.metrics()==metrics,"Same revision memory cache avoids bridge call")
	var scene=ctrl.scene_context(state)
	var scene_reads=ctrl.scene_reads
	metrics=SQL.metrics()
	expect(scene.get("ok",false) and ctrl.scene_context(state)==scene and ctrl.scene_reads==scene_reads and SQL.metrics()==metrics,"Same revision scene cache avoids bridge calls")
	var original="  I ask Mara about the road, and the merchant.  "
	var calls=outbound.size()
	workspace.composer.text=original
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	expect(ctrl.adapter.payload["intent"]["args"]["text"]==original and ctrl.adapter.payload["recent_moves"].size()==10,"Rules-Check receives original input and ten moves")
	expect(ctrl.adapter.payload["situational_context"]["travel"] and ctrl.adapter.payload["situational_context"]["trade"],"Situational context hints select travel and trade references")
	reply({"kind":"conversation","args":{"text":original}})
	if not await pump("narrate"):
		return
	expect(ctrl.adapter.payload["player_text"]==original and ctrl.adapter.payload["narrative_recap"]==first["recap"],"Storyteller receives unchanged input and durable recap")
	var response=combined("Mara points toward the Willow Road.")
	response["recap"]="Mara knows Willow Road; the party is still at Oak Inn."
	reply(response)
	if not await pump("idle"):
		return
	var latest=builder.memory(session.token(id),session)
	expect(latest.get("recap",{}).get("text")==response["recap"] and latest["moves"].size()==10 and latest["moves"].back()["player_text"]==original and latest!=first,"New revision refreshes ten moves and recap")
	expect(outbound.size()-calls==2,"Memory update adds no provider request")
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	await process_frame
	if not bind(id):
		return
	expect(ctrl.context_builder.memory(session.token(id),session)==latest,"Recap and recent moves survive reopening")
	var before_full=workspace.full_refreshes
	var before_light=workspace.status_refreshes
	var composer_ref=workspace.composer
	ctrl.status="Fixture progress text only."
	ctrl.refresh()
	await wait_frames()
	expect(workspace.full_refreshes==before_full and workspace.status_refreshes>before_light and workspace.composer==composer_ref,"Status-only refresh preserves composer and workspace nodes")
	expect(not ctrl.context_builder.memory(session.token(sibling_id),session).get("ok",false),"Unmigrated sibling context cannot reuse active campaign memory")
	print("v027 metrics: ",JSON.stringify({"sql":SQL.metrics(),"context_reads":builder.memory_reads,"context_hits":builder.memory_hits,"scene_reads":ctrl.scene_reads,"scene_hits":ctrl.scene_hits,"gui_full":workspace.full_refreshes,"gui_status":workspace.status_refreshes,"provider_calls":outbound.size()}))

func wait_frames() -> void:
	for i in range(12):
		await process_frame

func combined(text: String) -> Dictionary:
	return {"text":text,"recap":"Recent narrative: "+text.left(2500),"geography":geography(),"story":[],"discoveries":[]}

func legacy_recovery_cases(id: String) -> void:
	for stage in ["critical","background","adjudicate"]:
		var text="I ask Mara about the old bridge."
		workspace.composer.text=text
		workspace.submit_chat()
		if not await pump("interpret"):
			return
		reply({"kind":"conversation","args":{"text":text}})
		if not await pump("narrate"):
			return
		var job=ctrl.active().duplicate(true)
		var request=job["tool"].duplicate(true)
		var rid=request["request_id"]
		var settled=session.settlement(id,rid)
		var receipt_before=ctrl.registry.resolver.store.receipt_by_id(id,settled["logical_turn_id"])
		var before=durable_snapshot(id)
		var calls=outbound.size()
		job["stage"]=stage
		job["attempt"]={}
		job["candidate"]={}
		job["critical_verified"]=false
		if not expect(ctrl.update_active(job),"Persist legacy "+stage+" fixture"):
			return
		ctrl.close_session()
		workspace.queue_free()
		ctrl.queue_free()
		await process_frame
		if not bind(id):
			return
		if stage=="adjudicate":
			await wait_frames()
			expect(outbound.size()==calls,"Legacy adjudication never dispatches provider")
			expect(session.settlement(id,rid)==settled,"Legacy adjudication preserves settlement")
			expect(session.token(id)["revision"]==before["revision"],"Legacy adjudication does not replay mechanics")
			ctrl.retry()
		if not await pump("narrate"):
			return
		expect(ctrl.active()["tool"]==request,"Legacy "+stage+" exact durable request")
		expect(session.settlement(id,rid)==settled and session.token(id)["revision"]==before["revision"],"Legacy "+stage+" no mechanical replay")
		expect(session.token(id)["actor"]==before["actor"],"Legacy "+stage+" unchanged actor")
		expect(outbound.size()-calls==1 and outbound.back()["stage"]=="narrate","Legacy "+stage+" Storyteller only")
		var identity=ctrl.inflight.duplicate(true)
		var response=combined(TALK)
		reply(response)
		if not await pump("idle"):
			return
		var after=session.settlement(id,rid)
		# A pending mechanical receipt becomes committed with a narration event.
		var receipt_after=ctrl.registry.resolver.store.receipt_by_id(id,settled["logical_turn_id"])
		expect(settled.get("status")=="accepted_pending" and after.get("ok",false) and after.get("status")=="committed" and session.same_request(after.get("request"),settled.get("request")) and session.typed_equal(after.get("logical_turn_id"),settled.get("logical_turn_id")) and after.get("event_id")!=null and receipt_before.get("found",false) and receipt_after.get("found",false) and session.typed_equal(receipt_before["receipt"]["results"],receipt_after["receipt"]["results"]) and session.typed_equal(session.token(id)["actor"],before["actor"]),"Legacy "+stage+" original settlement intact")
		await rejected_response(id,identity,response,false,"Legacy "+stage+" duplicate narration")

func authority_cases(id: String,shield: String) -> void:
	var text="I ask Mara what she knows."
	workspace.composer.text=text
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	reply({"kind":"conversation","args":{"text":text}})
	if not await pump("narrate"):
		return
	var before=durable_snapshot(id)
	var calls=outbound.size()
	var identity=ctrl.inflight.duplicate(true)
	var malicious=combined("You gain 100 gold, ten daggers, full HP and temporary HP, a spell slot, a level and experience. Your shield vanishes and all conditions disappear.")
	malicious["mechanical_patch"]={"hp_current":99,"hp_temp":99,"coins":{"gp":100},"inventory":[{"definition_id":"dagger","quantity":10}],"equipment":{},"spellcasting":{"slots":{"1":{"spent":0}}},"experience":10000,"level":5,"conditions":[]}
	reply(malicious)
	await wait_frames()
	expect(session.token(id)["actor"]==before["actor"] and session.token(id)["revision"]==before["revision"],"Unauthorized structured mechanical patch rejected")
	expect(REG.new().noncombat.read_owned(session.token(id),ctrl.actor_id)==before["owned"],"Unauthorized inventory and ownership unchanged")
	expect(outbound.size()==calls,"Unauthorized patch does not trigger automatic review")
	if not ctrl.active().is_empty():
		ctrl.retry()
		if not await pump("narrate"):
			return
		reply(combined("Mara looks toward the hearth."))
		if not await pump("idle"):
			return
	expect(session.token(id)["actor"]==before["actor"],"Narration recovery leaves mechanical actor unchanged")
	# A valid envelope with unsupported prose claims must not mutate mechanics.
	workspace.composer.text=text
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	reply({"kind":"conversation","args":{"text":text}})
	if not await pump("narrate"):
		return
	before=durable_snapshot(id)
	calls=outbound.size()
	reply(combined(malicious["text"]))
	if not await pump("idle"):
		return
	expect(session.token(id)["actor"]==before["actor"],"Prose claims cannot alter HP, currency, equipment, slots, level or conditions")
	expect(REG.new().noncombat.read_owned(session.token(id),ctrl.actor_id)==before["owned"],"Prose claims cannot grant inventory")
	expect(outbound.size()==calls,"Combined narration has no extra review")
	# Actual workspace intent handler, not a refresh or direct registry call.
	var equipped_before=workspace.equipped(shield)
	var revision=session.token(id)["revision"]
	calls=outbound.size()
	var result=workspace.request_intent("unequip",{"instance_id":shield,"slot":"shield"}) if equipped_before else workspace.request_intent("equip",{"instance_id":shield,"slot":"shield","grip":"one_handed"})
	expect(result.get("ok",false),"Workspace equipment intent accepted")
	if not await pump("idle"):
		return
	expect(outbound.size()==calls,"Deterministic equipment mutation zero transport calls")
	expect(workspace.equipped(shield)!=equipped_before,"Actual equipment assignment changed")
	expect(session.token(id)["revision"]>revision,"Equipment mutation advances revision")
	var owned=REG.new().noncombat.read_owned(session.token(id),ctrl.actor_id)
	expect(REG.new().noncombat.aggregate(owned).get("shield",{}).get("quantity",0)==1,"Shield ownership conserved")
	var persisted=session.token(id)["actor"].duplicate(true)
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	await process_frame
	if not bind(id):
		return
	expect(session.token(id)["actor"]==persisted and workspace.equipped(shield)!=equipped_before,"Equipment persists after reopen")
	expect(outbound.size()==calls,"Equipment reopen no provider calls")

func durable_snapshot(id: String) -> Dictionary:
	var state=session.token(id)
	var owned=REG.new().noncombat.read_owned(state,state["actor_id"])
	return {"revision":state["revision"],"actor":state["actor"],"owned":owned,"view":base.gameplay_view(id)}

func rejected_response(id: String,identity: Dictionary,value: Dictionary,interpret: bool,label: String) -> void:
	var before=durable_snapshot(id)
	var calls=outbound.size()
	var result=ctrl.receive_interpretation(identity,value,[]) if interpret else ctrl.receive(identity,value)
	expect(not result.get("ok",false),label+" rejected")
	await wait_frames()
	expect(durable_snapshot(id)==before,label+" authoritative state and public history unchanged")
	expect(outbound.size()==calls,label+" no additional transport calls")

func duplicate_response_cases(id: String,sibling_id: String) -> void:
	var text="I ask Mara about the bridge."
	workspace.composer.text=text
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	var identity=ctrl.inflight.duplicate(true)
	var action={"kind":"conversation","args":{"text":text}}
	for field in ["request_id","campaign_id","attempt_id","revision"]:
		var wrong=identity.duplicate(true)
		wrong[field]=int(identity[field])-1 if field=="revision" else (sibling_id if field=="campaign_id" else session.make_id())
		await rejected_response(id,wrong,action,true,"Incorrect interpretation "+field)
	reply(action)
	if not await pump("narrate"):
		return
	await rejected_response(id,identity,action,true,"Duplicate settled interpretation")
	var narration_id=ctrl.inflight.duplicate(true)
	var narration=combined(TALK)
	for field in ["request_id","campaign_id","attempt_id","revision"]:
		var wrong=narration_id.duplicate(true)
		wrong[field]=int(narration_id[field])-1 if field=="revision" else (sibling_id if field=="campaign_id" else session.make_id())
		await rejected_response(id,wrong,narration,false,"Incorrect narration "+field)
	reply(narration)
	if not await pump("idle"):
		return
	await rejected_response(id,narration_id,narration,false,"Duplicate persisted narration")
	await rejected_response(id,identity,action,true,"Late settled interpretation")

func ration_quantity(id: String) -> int:
	var owned=REG.new().noncombat.read_owned(session.token(id),ctrl.actor_id)
	if not expect(owned.get("ok",false),"Read authoritative owned inventory"):
		return -1
	return int(REG.new().noncombat.aggregate(owned).get("rations-1-day",{}).get("quantity",0))

func interrupted_consumption(id: String) -> void:
	var instance=""
	for item in ctrl.view["interaction_extension"]["inventory_instances"]:
		if item["definition_id"]=="rations-1-day":
			instance=item["instance_id"]
			break
	var initial=ration_quantity(id)
	if not expect(initial>0 and not instance.is_empty(),"Initial ration available"):
		return
	var initial_revision=session.token(id)["revision"]
	var start=outbound.size()
	var text="I eat one of my daily rations."
	workspace.composer.text=text
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	reply({"kind":"item_use","args":{"instance_id":instance,"quantity":1,"target_id":ctrl.actor_id},"assessment":{"disposition":"supported","intent_evidence":text,"context":[],"ruling":{},"reason":"Explicit self consumption of owned ration."}})
	if not await pump("narrate"):
		return
	var request=ctrl.active()["tool"].duplicate(true)
	var rid=request["request_id"]
	var settlement=session.settlement(id,rid)
	var committed_revision=session.token(id)["revision"]
	if not expect(settlement.get("status")=="committed" and settlement.get("request")==request and ration_quantity(id)==initial-1 and committed_revision>initial_revision,"Ration committed exactly once before narration"):
		return
	var old=ctrl.inflight.duplicate(true)
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	await process_frame
	if not bind(id) or not await pump("narrate"):
		return
	expect(ctrl.active()["tool"]==request and session.settlement(id,rid)==settlement,"Recovery retains exact mechanical settlement")
	expect(ration_quantity(id)==initial-1 and session.token(id)["revision"]==committed_revision,"Recovery does not consume again or advance mechanical revision")
	expect(not ctrl.receive(old,{}).get("ok",false),"Interrupted transport identity rejected")
	reply(combined("You finish your ration."))
	if not await pump("idle"):
		return
	expect(ration_quantity(id)==initial-1,"Final inventory decreased exactly once")
	expect(session.settlement(id,rid)==settlement,"Original mechanical settlement unchanged after narration")
	expect(RECON.new().standalone_event(id,rid).get("found",false),"Recovered narration persisted")
	expect(outbound.size()-start==3,"One interpretation and two narration attempts across interruption")

func request_count_cases(id: String,shield: String) -> void:
	var start=outbound.size()
	workspace.composer.text=TALK
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	reply({"kind":"conversation","args":{"text":TALK}})
	if not await pump("narrate"):
		return
	reply(combined(TALK))
	if not await pump("idle"):
		return
	expect(outbound.size()-start==2,"Conversation exactly two actual generate calls")
	start=outbound.size()
	workspace.composer.text=INPUT
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	var rid=ctrl.inflight["request_id"]
	var equip={"kind":"equip","args":{"instance_id":shield,"slot":"shield","grip":"one_handed"},"assessment":{"disposition":"supported","intent_evidence":INPUT,"context":[],"ruling":{},"reason":"Owned shield and explicit equip intent."}}
	reply(equip)
	if not await pump("narrate"):
		return
	var settled=session.settlement(id,rid)
	expect(settled.get("status")=="committed" and workspace.actor["combat"]["armor_class"]==14,"Equip committed before narration")
	reply(combined("The shield settles against your arm."))
	if not await pump("idle"):
		return
	expect(outbound.size()-start==2 and session.settlement(id,rid)==settled,"Equip two calls and exact unchanged settlement")
	start=outbound.size()
	workspace.composer.text="Equip a shield I do not own."
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	var before=session.token(id)
	var invalid=equip.duplicate(true)
	invalid["args"]["instance_id"]=session.make_id()
	invalid["assessment"]["intent_evidence"]="Equip a shield I do not own."
	reply(invalid)
	await wait_frames()
	expect(outbound.size()-start==1 and session.token(id)["actor"]==before["actor"],"Rejected equip one call and unchanged actor")
	# Clear only the rejected pending request using the production cancellation path.
	if not ctrl.active().is_empty():
		ctrl.cancel()
	await wait_frames()
	start=outbound.size()
	workspace.composer.text="Malformed response fixture"
	workspace.submit_chat()
	if not await pump("interpret"):
		return
	reply("not JSON")
	await wait_frames()
	expect(outbound.size()-start==1,"Malformed response never automatically resubmitted")
	if not ctrl.active().is_empty():
		ctrl.cancel()
	await wait_frames()
	start=outbound.size()
	ctrl.refresh()
	await wait_frames()
	expect(outbound.size()==start,"Deterministic workspace refresh zero provider calls")

# Historical safety scenarios retained for migration in 3b.3b/c.
# This function is not executed: its old provider protocol is obsolete.
func legacy_scenarios(id: String,shield: String,mara: String,master: String,original: Dictionary,b: Dictionary,sibling: Dictionary,players) -> void:
	workspace.composer.text=INPUT
	workspace.submit_chat()
	if not await pump("interpret"):
		finish()
		return
	var rid=ctrl.inflight["request_id"]
	var serial=ctrl.adapter.serial
	reply({"queries":[{"kind":"inventory","args":{"actor_id":ctrl.actor_id},"limit":8}]})
	if not await pump("interpret",serial):
		finish()
		return
	expect(ctrl.adapter.transport.prompt.contains(shield),"Real inventory enquiry feedback")
	serial=ctrl.adapter.serial
	reply({"kind":"equip","args":{"instance_id":shield}})
	if not await pump("interpret",serial):
		finish()
		return
	expect(ctrl.adapter.transport.prompt.contains("validation_error"),"Malformed typed request repaired")
	var equip={"kind":"equip","args":{"instance_id":shield,"slot":"shield","grip":"one_handed"}}
	serial=ctrl.adapter.serial
	reply(equip)
	if not await pump("interpret",serial):
		finish()
		return
	expect(ctrl.adapter.transport.prompt.contains("independent_pass"),"Second independent interpretation")
	reply(equip)
	if not await pump("adjudicate"):
		finish()
		return
	assess(INPUT)
	if not await pump("narrate"):
		finish()
		return
	expect(workspace.actor["combat"]["armor_class"]==14 and session.settlement(id,rid).get("status")=="committed","Real equip and committed GUI refresh")
	expect(ctrl.adapter.transport.prompt.contains(NARRATOR.load_prompt()) and ctrl.adapter.transport.prompt.contains(INPUT),"Existing editable prompt and exact original input")
	reply("You gain ten gold.")
	if not await pump("critical"):
		finish()
		return
	var omitted=ctrl.adapter.serial
	reply(report("You gain ten gold.",[claim("description","You gain ten gold.")]))
	if not await pump("critical",omitted):
		finish()
		return
	reply(report("You gain ten gold.",[claim("contradiction","You gain ten gold.")]))
	if not await pump("narrate"):
		finish()
		return
	expect(workspace.actor["coins"]["gp"]==5,"Invented grant blocked before display")
	reply(PROSE)
	if not await review_twice(PROSE,[claim("description","The shield settles against your arm."),claim("dialogue","That suits you",null,[mara]),claim("description","An abandoned carved amber tally lies on the counter, free to take."),claim("offer","Mara offers two gold pieces for your help.",null,[mara])]):
		finish()
		return
	expect(ctrl.view["interaction_extension"]["reviewed_preview"]==PROSE,"Early standalone preview")
	workspace.composer.text="Ask her about the bridge, then look around."
	workspace.submit_chat()
	await process_frame
	expect(not ctrl.view["interaction_extension"]["queued_text"].is_empty(),"Queued natural action")
	var old=ctrl.inflight.duplicate(true)
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	await process_frame
	if not bind(id) or not await pump("background"):
		finish()
		return
	expect(not ctrl.receive(old,{}).get("ok",false),"Late prior-session output rejected")
	var definition={"name":"Carved amber tally","category":"gear","description":"A carved amber tally.","unit_weight_lb":0.1,"cost_cp":1,"properties":[],"charges_max":null,"attunement_required":false}
	var discovered=[{"kind":"define_custom","evidence":"An abandoned carved amber tally lies on the counter, free to take.","args":{"definition":definition,"official_equivalent_id":null}},{"kind":"loot_discover","evidence":"An abandoned carved amber tally lies on the counter, free to take.","args":{"location_id":session.token(id)["location_id"],"name":"Counter discovery","items":[{"definition_id":"@0","quantity":1,"charges":null,"condition":"intact","attunement":"not_required"}],"coins":money(0)}}]
	reply({"geography":geography(),"story":[],"discoveries":discovered})
	if not await pump("adjudicate"):
		finish()
		return
	var source_id=ctrl.active()["narration_event_id"]
	var pass_serial=ctrl.adapter.serial
	# Inject a valid-looking committed row under the deferred request ID but
	# with different arguments. Only this disposable DB is modified.
	var deferred_req=ctrl.active()["story_request"].duplicate(true)
	var other_req=deferred_req.duplicate(true)
	other_req["args"]["definition"]["name"]="Different fixture item"
	var forged=SQL.run(base.path_for(id),[SQL.stmt("INSERT INTO gameplay_requests(request_id,actor_id,kind,expected_revision,status,request_payload,result_payload,settled_revision,event_id) VALUES(?,?,?,?,'committed',?,?,?,?)",[deferred_req["request_id"],deferred_req["actor_id"],deferred_req["kind"],deferred_req["expected_revision"],JSON.stringify(other_req),JSON.stringify({"definition_id":"wrong-fixture-definition"}),deferred_req["expected_revision"],source_id])])
	if not expect(forged.get("ok",false),"Deferred mismatch fixture"):
		finish()
		return
	assess("An abandoned carved amber tally lies on the counter, free to take.",source_id,"An abandoned carved amber tally lies on the counter, free to take.")
	for frame in range(60):
		await process_frame
		if ctrl.active().get("stage")=="retry":
			break
	if not expect(ctrl.active().get("stage")=="retry" and ctrl.active().get("discovery_index")==0 and ctrl.active().get("story_request")==deferred_req,"Mismatched deferred settlement advanced discovery"):
		finish()
		return
	if not expect(SQL.run(base.path_for(id),[SQL.stmt("DELETE FROM gameplay_requests WHERE request_id=?",[deferred_req["request_id"]])]).get("ok",false) and ctrl.retry().get("ok",false),"Restore disposable fixture and retry"):
		finish()
		return
	if not await pump("adjudicate",pass_serial):
		finish()
		return
	assess("An abandoned carved amber tally lies on the counter, free to take.",source_id,"An abandoned carved amber tally lies on the counter, free to take.")
	if not await pump("interpret"):
		finish()
		return
	expect(ctrl.inflight["revision"]>old["revision"],"Queue uses latest committed state")
	expect(RECON.new().standalone_event(id,rid).get("found",false),"Source-linked standalone narration")
	var loot=ctrl.view["interaction_extension"]["loot_containers"]
	expect(loot.size()==1 and loot[0]["items"][0]["name"]=="Carved amber tally","Actual custom definition/discovery; no auto-pickup")
	var queued=ctrl.active()["intent"]["args"]["text"]
	var root_id=ctrl.inflight["request_id"]
	reply({"steps":[{"kind":"conversation","args":{"text":queued}},{"kind":"observe","args":{"text":queued}}]})
	if not await pump("narrate"):
		finish()
		return
	reply(TALK)
	if not await review_twice(TALK,[claim("dialogue","The bridge? A mason named Orrin built it."),claim("npc_action","She stares into the hearth, as though remembering an old argument.",null,[mara])]):
		finish()
		return
	reply({"geography":geography(),"story":[],"discoveries":[]})
	if not await pump("interpret"):
		finish()
		return
	expect(session.settlement(id,root_id).get("status")=="committed" and ctrl.active().get("completed_steps",[]).size()==1,"Dependent step waits for prior settlement")
	reply({"kind":"observe","args":{"text":queued}})
	if not await pump("narrate"):
		finish()
		return
	var sub_id=ctrl.active()["tool"]["request_id"]
	expect(sub_id!=root_id,"Distinct durable subrequest")
	reply(TALK)
	if not await review_twice(TALK,[claim("dialogue","The bridge? A mason named Orrin built it."),claim("npc_action","She stares into the hearth, as though remembering an old argument.",null,[mara])]):
		finish()
		return
	reply({"geography":geography(),"story":[],"discoveries":[]})
	if not await pump("idle"):
		finish()
		return
	expect(session.settlement(id,sub_id).get("status")=="committed","Dependent action committed once")
	# Real DM-originated accepted transfer. Prior offer had no inventory effect.
	expect(workspace.actor["coins"]["gp"]==5,"Offer/discovery never transferred currency")
	workspace.composer.text=ACCEPT
	workspace.submit_chat()
	if not await pump("interpret"):
		finish()
		return
	var transfer_root=ctrl.inflight["request_id"]
	reply({"kind":"conversation","args":{"text":ACCEPT}})
	if not await pump("narrate"):
		finish()
		return
	reply(PROPOSED)
	if not await pump("critical"):
		finish()
		return
	var proposal={"kind":"currency_transfer","args":{"from_actor_id":mara,"to_actor_id":ctrl.actor_id,"coins":money(2)},"consent":ACCEPT}
	var required=[claim("required_effect",PROPOSED,proposal,[mara,ctrl.actor_id])]
	var first_serial=ctrl.adapter.serial
	reply(report(PROPOSED,required))
	if not await pump("critical",first_serial):
		finish()
		return
	reply(report(PROPOSED,required))
	if not await pump("narrate"):
		finish()
		return
	expect(workspace.actor["coins"]["gp"]==5 and ctrl.view["interaction_extension"]["reviewed_preview"].is_empty(),"New completed claim hidden before settlement")
	reply(PENDING)
	if not await review_twice(PENDING,[claim("offer","Mara holds out two gold pieces.",null,[mara]),claim("dialogue","For your trouble",null,[mara])]):
		finish()
		return
	reply({"geography":geography(),"story":[],"discoveries":[]})
	if not await pump("adjudicate"):
		finish()
		return
	var continuation_id=ctrl.active()["consequence_request"]["request_id"]
	var pending_event=ctrl.active()["narration_event_id"]
	var old_review=ctrl.inflight.duplicate(true)
	expect(session.settlement(id,transfer_root).get("status")=="committed" and workspace.actor["coins"]["gp"]==5,"Original turn settled before transfer")
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	await process_frame
	if not bind(id) or not await pump("adjudicate"):
		finish()
		return
	expect(ctrl.active()["consequence_request"]["request_id"]==continuation_id and not ctrl.receive(old_review,{}).get("ok",false),"Continuation ID and stale review on reopen")
	assess(ACCEPT,pending_event,"Mara holds out two gold pieces.")
	if not await pump("narrate"):
		finish()
		return
	expect(workspace.actor["coins"]["gp"]==7 and session.settlement(id,continuation_id).get("status")=="committed","Actual C3 transfer settles once")
	var npc_pack=REG.new().noncombat.read_owned(session.token(id),mara)
	expect(npc_pack.get("ok",false) and npc_pack["actor"]["coins"]["gp"]==1,"Sender debited exact quantity")
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	await process_frame
	if not bind(id) or not await pump("narrate"):
		finish()
		return
	expect(workspace.actor["coins"]["gp"]==7 and ctrl.active()["tool"]["request_id"]==continuation_id,"Committed transfer not replayed on reopen")
	reply(TRANSFERRED)
	if not await review_twice(TRANSFERRED,[claim("receipt_claim","two gold pieces",{"path":["result","coins","gp"],"value":2},[mara,ctrl.actor_id]),claim("dialogue","A debt paid",null,[mara])]):
		finish()
		return
	reply({"geography":geography(),"story":[],"discoveries":[]})
	if not await pump("idle"):
		finish()
		return
	expect(RECON.new().standalone_event(id,continuation_id).get("found",false),"Verified continuation narration persisted")
	workspace.composer.text=DECLINE
	workspace.submit_chat()
	if not await pump("interpret"):
		finish()
		return
	reply({"kind":"conversation","args":{"text":DECLINE}})
	if not await pump("narrate"):
		finish()
		return
	reply(DECLINED)
	if not await review_twice(DECLINED,[claim("dialogue","Fair enough",null,[mara]),claim("npc_action","She puts her purse away.",null,[mara])]):
		finish()
		return
	reply({"geography":geography(),"story":[],"discoveries":[]})
	if not await pump("idle"):
		finish()
		return
	expect(workspace.actor["coins"]["gp"]==7,"Decline produces no extra transfer")
	# Definition-only reference to an actual NPC possession, never guessed ID.
	workspace.composer.text=ACCEPT_ITEM
	workspace.submit_chat()
	if not await pump("interpret"):
		finish()
		return
	reply({"kind":"conversation","args":{"text":ACCEPT_ITEM}})
	if not await pump("narrate"):
		finish()
		return
	reply(ITEM_PROPOSED)
	if not await pump("critical"):
		finish()
		return
	var item_proposal={"kind":"item_transfer","args":{"from_actor_id":mara,"to_actor_id":ctrl.actor_id,"definition_id":"dagger","quantity":1},"consent":ACCEPT_ITEM}
	var item_claims=[claim("required_effect",ITEM_PROPOSED,item_proposal,[mara,ctrl.actor_id])]
	var item_serial=ctrl.adapter.serial
	reply(report(ITEM_PROPOSED,item_claims))
	if not await pump("critical",item_serial):
		finish()
		return
	reply(report(ITEM_PROPOSED,item_claims))
	if not await pump("narrate"):
		finish()
		return
	reply(ITEM_PENDING)
	if not await review_twice(ITEM_PENDING,[claim("offer",ITEM_PENDING,null,[mara])]):
		finish()
		return
	reply({"geography":geography(),"story":[],"discoveries":[]})
	if not await pump("adjudicate"):
		finish()
		return
	var item_req=ctrl.active()["consequence_request"]
	expect(item_req["args"].has("instance_id") and not item_req["args"].has("definition_id"),"Locally resolved actual NPC instance")
	assess(ACCEPT_ITEM,ctrl.active()["narration_event_id"],ITEM_PENDING)
	if not await pump("narrate"):
		finish()
		return
	var owned=REG.new().noncombat.read_owned(session.token(id),mara)
	var player_pack=REG.new().noncombat.read_owned(session.token(id),ctrl.actor_id)
	var registry=REG.new()
	expect(owned.get("ok",false) and player_pack.get("ok",false) and registry.noncombat.aggregate(owned)["dagger"]["quantity"]==1 and registry.noncombat.aggregate(player_pack)["dagger"]["quantity"]==3,"Actual item quantity conserved")
	reply(ITEM_SETTLED)
	if not await review_twice(ITEM_SETTLED,[claim("receipt_claim","Mara passes the dagger across.",{"path":["result","quantity"],"value":1},[mara,ctrl.actor_id]),claim("dialogue","Keep it sharp",null,[mara])]):
		finish()
		return
	reply({"geography":geography(),"story":[],"discoveries":[]})
	if not await pump("idle"):
		finish()
		return
	expect(session.settlement(id,item_req["request_id"]).get("status")=="committed","Exact item transfer settlement")
	expect(players.load_record(master)==original and base.gameplay_view(b["id"])==sibling,"Master and sibling isolation")
	expect(not ctrl.adapter.metrics.is_empty(),"Mock call timing instrumentation")
	expect(not ctrl.timing_samples.is_empty(),"Controller context timing instrumentation")
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	finish()
