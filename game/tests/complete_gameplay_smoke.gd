extends SceneTree
## C4 development controller + actual workspace + C2/C3/B4 persistence.
## Only the semantic adapter and trusted local reviewers are fixtures.
const BASE=preload("res://campaigns/campaign_store.gd")
const PLAYER=preload("res://players/character_store.gd")
const CAT=preload("res://rules/catalog.gd")
const MIGRATION=preload("res://persistence/gameplay_migration.gd")
const SESSION=preload("res://persistence/gameplay_session.gd")
const REG=preload("res://gameplay/tool_registry.gd")
const TURN=preload("res://turns/turn_store.gd")
const PACK=preload("res://turns/agent_packets.gd")
const CTRL=preload("res://gameplay/complete_controller.gd")
const WORKSPACE=preload("res://gameplay/game_workspace.gd")
var base=BASE.new()
var session=SESSION.new()
var failures: Array[String]=[]
var packet: Dictionary={}
var ctrl
var workspace
const PROSE="The innkeeper mentions a bridge."

func _initialize() -> void:
	run.call_deferred()

func expect(ok: bool,message: String) -> bool:
	if not ok:
		failures.append(message)
	return ok

func finish() -> void:
	for message in failures:
		push_error(message)
	print("C4 complete gameplay smoke failures: ",failures.size())
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

func review(req: Dictionary,_scope: Dictionary,_intent: Dictionary={}) -> Dictionary:
	var allowed=req["kind"] in ["equip","loot_discover","loot_pickup","loot_take_all","item_use","resource_use","rest","conversation","story_update","actor_generate","spell_cast"]
	var ruling={}
	if req["kind"]=="conversation":
		ruling={"safe_nonmechanical":true,"seconds":0,"establish_clock":false}
	return {"request_id":req["request_id"],"campaign_id":req["campaign_id"],"actor_id":req["actor_id"],"expected_revision":req["expected_revision"],"accepted":allowed,"ruling":ruling,"reason":"Authorized disposable fixture only."}

func review_prose(candidate: Dictionary,claims: Array,receipt: Dictionary,_scene: Dictionary) -> bool:
	return candidate.get("text")==PROSE and claims.size()==1 and claims[0].get("evidence")==PROSE and PACK.committed_receipt_usable(receipt)

func capture(_stage: String,p: Dictionary) -> void:
	packet=p.duplicate(true)

func bind(id: String) -> bool:
	packet={}
	ctrl=CTRL.new()
	root.add_child(ctrl)
	ctrl.semantic_requested.connect(capture)
	if not expect(ctrl.bind_campaign(id,review,review_prose).get("ok",false),"Controller bind failed"):
		return false
	workspace=WORKSPACE.new()
	if not expect(ctrl.mount_workspace(workspace,Callable(),Callable()).get("ok",false),"Workspace mount failed"):
		return false
	root.add_child(workspace)
	return true

func pump(stage: String) -> bool:
	for i in range(40):
		await process_frame
		if stage=="idle" and ctrl.active().is_empty() and ctrl.view.get("interaction_extension",{}).get("phase")=="idle":
			return true
		if stage!="idle" and ctrl.active().get("stage")==stage and packet.get("identity")==ctrl.inflight and not ctrl.inflight.is_empty():
			return true
	return expect(false,"Expected stage "+stage+"; got "+str(ctrl.active().get("stage"))+" / "+ctrl.status)

func setup_action(id: String,kind: String,args: Dictionary) -> Dictionary:
	var state=session.token(id)
	var req={"schema_version":"2","campaign_id":id,"actor_id":state["actor_id"],"expected_revision":state["revision"],"request_id":session.make_id(),"kind":kind,"args":args}
	return REG.new().execute(id,req,func(r,s): return review(r,s,{}))

func instance(id: String) -> String:
	for item in ctrl.view.get("interaction_extension",{}).get("inventory_instances",[]):
		if item["definition_id"]==id:
			return item["instance_id"]
	return ""

func choice(kind: String,args: Dictionary) -> bool:
	if not expect(workspace.dev_submit(kind,args).get("ok",false),"Workspace submit "+kind):
		return false
	return await pump("idle")

func run() -> void:
	var expected=OS.get_environment("INFINITY_TEST_USER_ROOT").replace("\\","/").trim_suffix("/")
	var actual=ProjectSettings.globalize_path("user://").replace("\\","/").trim_suffix("/")
	if expected.is_empty() or expected!=actual or FileAccess.file_exists("user://players.db") or FileAccess.file_exists("user://settings.cfg") or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(BASE.ROOT)):
		push_error("C4 smoke requires an explicitly authorized empty disposable user directory.")
		quit(2)
		return
	var players=PLAYER.new()
	var master=players.make_id()
	if not expect(players.save_record(master_record(master)).is_empty(),"Fixture master save"):
		finish()
		return
	var original=players.load_record(master)
	var a=base.create_campaign("C4 fixture",master,"tavern","standard")
	var b=base.create_campaign("C4 sibling",master,"road","standard")
	if not expect(not a.is_empty() and not b.is_empty(),"Campaign creation"):
		finish()
		return
	var id=a["id"]
	var sibling=base.gameplay_view(b["id"])
	if not expect(MIGRATION.new().ensure(id).get("ok",false),"Migration"):
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
	var ext=base.gameplay_view(id).get("interaction_extension",{})
	var actors=ext.get("public_actors",[])
	if not expect(actors.size()==1,"Disclosed NPC"):
		finish()
		return
	var mara=actors[0]["actor_id"]
	var event=int(actors[0]["source_event_id"])
	var at=session.token(id)["location_id"]
	var found=setup_action(id,"loot_discover",{"source_event_id":event,"location_id":at,"name":"Found supplies","items":[{"definition_id":"dagger","quantity":3,"charges":null,"condition":"intact","attunement":"not_required"}],"coins":money(5)})
	if not expect(found.get("ok",false),"Real loot discovery: "+str(found)):
		finish()
		return
	if not bind(id):
		finish()
		return
	expect(ctrl.enquiry("actor_sheet",{"actor_id":mara}).get("ok",false),"Disclosed actor inspection")
	if not await choice("equip",{"instance_id":instance("shield"),"slot":"shield","grip":"one_handed"}):
		finish()
		return
	expect(ctrl.view["actor"]["combat"]["armor_class"]==14 and workspace.actor["combat"]["armor_class"]==14,"Committed AC refresh")
	var loot=ctrl.view["interaction_extension"]["loot_containers"]
	if not expect(loot.size()==1 and not loot[0]["items"].is_empty(),"Actual loot projection"):
		finish()
		return
	var box=loot[0]
	if not await choice("loot_pickup",{"container_id":box["container_id"],"source_event_id":event,"items":[{"instance_id":box["items"][0]["instance_id"],"quantity":1}],"coins":money(2)}):
		finish()
		return
	expect(workspace.actor["coins"]["gp"]==7,"Selected coin pickup")
	if not await choice("loot_take_all",{"container_id":box["container_id"],"source_event_id":event}):
		finish()
		return
	expect(workspace.actor["coins"]["gp"]==10 and ctrl.view["interaction_extension"]["loot_containers"].is_empty(),"Take all committed projection")
	if not await choice("item_use",{"instance_id":instance("magic:potion-of-healing-common"),"quantity":1,"target_id":ctrl.actor_id}):
		finish()
		return
	expect(workspace.actor["combat"]["hp_current"]>4 and instance("magic:potion-of-healing-common").is_empty(),"Potion committed HP and inventory")
	if not await choice("resource_use",{"resource_id":"second_wind","quantity":1,"target_id":ctrl.actor_id}):
		finish()
		return
	expect(workspace.actor["resources"]["second_wind"]["spent"]==1,"Resource expenditure")
	if not await choice("rest",{"rest_kind":"short","hit_dice":0,"prepared_ids":null}):
		finish()
		return
	expect(workspace.actor["resources"]["second_wind"]["spent"]==0,"Rest resource refresh")
	workspace.composer.text="What lies beyond the inn?"
	workspace.submit_chat()
	if not await pump("interpret"):
		finish()
		return
	var intent_id=packet["identity"]["request_id"]
	expect(packet["data"]["intent"]["args"]["text"]=="What lies beyond the inn?","Natural text exact")
	expect(ctrl.receive(packet["identity"],{"kind":"conversation","args":{"text":"What lies beyond the inn?"}}).get("ok",false),"Mock interpretation")
	if not await pump("narrate"):
		finish()
		return
	var turn_id=packet["data"]["turn_id"]
	var receipt=TURN.new().receipt_by_id(id,turn_id)
	expect(receipt.get("found",false),"Committed mechanical receipt")
	var stale=packet["identity"].duplicate(true)
	expect(ctrl.provider_failed(stale).get("ok",false),"Provider failure")
	expect(ctrl.retry().get("ok",false),"Retry committed turn")
	if not await pump("narrate"):
		finish()
		return
	expect(not ctrl.receive(stale,{"text":PROSE}).get("ok",false),"Late reply rejected")
	expect(ctrl.receive(packet["identity"],{"text":PROSE}).get("ok",false),"Candidate")
	if not await pump("critical"):
		finish()
		return
	expect(ctrl.view["interaction_extension"]["reviewed_preview"].is_empty(),"Unreviewed prose hidden")
	expect(ctrl.receive(packet["identity"],{"claims":[{"kind":"description","evidence":PROSE,"proposal":null}]}).get("ok",false),"Critical review")
	if not await pump("background"):
		finish()
		return
	expect(ctrl.view["interaction_extension"]["reviewed_preview"]==PROSE,"Early reviewed preview")
	workspace.composer.text="Ask about the bridge."
	workspace.submit_chat()
	await process_frame
	expect(ctrl.view["interaction_extension"]["queued_text"]=="Ask about the bridge.","Queued text durable")
	expect(not workspace.dev_submit("chat",{"text":"A second queued action"},"1").get("ok",false),"Second queue rejected")
	expect(ctrl.save_draft("A separate draft").get("ok",false),"Draft save")
	var old_background=packet["identity"].duplicate(true)
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	await process_frame
	if not bind(id) or not await pump("background"):
		finish()
		return
	expect(ctrl.view["interaction_extension"]["queued_text"]=="Ask about the bridge." and ctrl.view["interaction_extension"]["draft"]=="A separate draft","Reopen queue and draft")
	expect(not ctrl.receive(old_background,{}).get("ok",false),"Old session response rejected")
	var geo=PACK.identity(session.token(id),turn_id,packet["identity"]["attempt_id"])
	geo["source_event_id"]=null
	geo["facts"]=[]
	var story={"record_id":null,"identity_key":"bridge-rumour","kind":"unresolved_event","title":"Bridge rumour","description":PROSE,"status":"open","visibility":"player","certainty":"rumour","location_id":at,"parent_id":null,"progress_current":null,"progress_max":null,"participants":[]}
	expect(ctrl.receive(packet["identity"],{"geography":geo,"story":[{"evidence":PROSE,"args":story}]}).get("ok",false),"Background interpretation")
	if not await pump("interpret"):
		finish()
		return
	expect(packet["data"]["intent"]["args"]["text"]=="Ask about the bridge." and packet["identity"]["revision"]>old_background["revision"],"Queued action fresh revision")
	expect(TURN.new().receipt_by_id(id,turn_id).get("receipt")==receipt.get("receipt"),"No repeated committed mechanics")
	expect(session.settlement(id,intent_id).get("status")=="committed","Adopted settlement confirmed")
	expect(ctrl.receive(packet["identity"],{"status":"unsupported","message":"Fixture unsupported."}).get("ok",false),"Unsupported reply")
	expect(ctrl.cancel().get("ok",false),"Cancel uncommitted queued intent")
	await process_frame
	expect(ctrl.enquiry("overview",{}).get("ok",false),"Persistent overview")
	expect(players.load_record(master)==original and base.gameplay_view(b["id"])==sibling,"Master and sibling isolation")
	ctrl.close_session()
	workspace.queue_free()
	ctrl.queue_free()
	finish()
