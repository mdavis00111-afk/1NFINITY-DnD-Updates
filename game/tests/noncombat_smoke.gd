extends SceneTree
## C3 integration tests. Disposable local saves, no live provider or combat.
const BASE=preload("res://campaigns/campaign_store.gd")
const PLAYER=preload("res://players/character_store.gd")
const CAT=preload("res://rules/catalog.gd")
const SQL=preload("res://systems/sqlite.gd")
const MIGRATION=preload("res://persistence/gameplay_migration.gd")
const SESSION=preload("res://persistence/gameplay_session.gd")
const REGISTRY=preload("res://gameplay/tool_registry.gd")
const TURN=preload("res://turns/turn_store.gd")
var failures: Array[String]=[]
var base=BASE.new()
var session=SESSION.new()
var registry=REGISTRY.new()

func _initialize() -> void:
	run.call_deferred()

func expect(ok: bool,message: String) -> void:
	if not ok:
		failures.append(message)

func finish() -> void:
	for message in failures:
		push_error(message)
	print("C3 noncombat smoke failures: ",failures.size())
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

func request(id: String,kind: String,args: Dictionary) -> Dictionary:
	var s=session.token(id)
	return {"schema_version":"2","campaign_id":id,"actor_id":s.get("actor_id"),"expected_revision":s.get("revision"),"request_id":session.make_id(),"kind":kind,"args":args}

func review(req: Dictionary,_scope: Dictionary) -> Dictionary:
	# Explicit trusted fixture review only; never use this indiscriminate test
	# approval in production. C4/C5 must verify actual context and player intent.
	var ruling: Dictionary={}
	match req["kind"]:
		"conversation": ruling={"safe_nonmechanical":true,"seconds":0,"establish_clock":false}
		"wait": ruling={"safe_nonmechanical":true,"seconds":req["args"]["seconds"],"establish_clock":session.token(req["campaign_id"])["elapsed_seconds"]==null}
		"ability_check","skill_check": ruling={"seconds":0,"establish_clock":false,"optional_features_resolved":true,"verified_circumstances":req["args"]["circumstances"],"effect_dc":null}
	return {"request_id":req["request_id"],"campaign_id":req["campaign_id"],"actor_id":req["actor_id"],"expected_revision":req["expected_revision"],"accepted":true,"ruling":ruling,"reason":"Disposable fixture context."}

func action(id: String,kind: String,args: Dictionary) -> Dictionary:
	return registry.execute(id,request(id,kind,args),review)

func items(id: String) -> Dictionary:
	var state=session.token(id)
	var q={"schema_version":"2","campaign_id":id,"expected_revision":state["revision"],"query_id":session.make_id(),"kind":"inventory","args":{"actor_id":state["actor_id"]},"limit":64}
	var data=registry.enquire(id,q)
	var map: Dictionary={}
	for row in data.get("data",{}).get("items",[]):
		map[row["definition_id"]]=row["instance_id"]
	return map

func finish_turn(id: String,req: Dictionary,result: Dictionary) -> bool:
	if not result.get("ok",false) or result.get("status")!="pending_narration":
		return false
	var state=session.token(id)
	var receipt=result["receipt"]
	var narr=TURN.new().commit_narration(id,receipt["turn_id"],int(state["revision"]),"Verified disposable fixture narration.")
	if not narr.get("ok",false):
		return false
	var rev=session.token(id)["revision"]
	var recovered=registry.recover(id,req["request_id"])
	return recovered.get("status")=="committed" and session.token(id)["revision"]==rev

func run() -> void:
	var expected=OS.get_environment("INFINITY_TEST_USER_ROOT").replace("\\","/").trim_suffix("/")
	var actual=ProjectSettings.globalize_path("user://").replace("\\","/").trim_suffix("/")
	if expected.is_empty() or expected!=actual or FileAccess.file_exists("user://players.db") or FileAccess.file_exists("user://settings.cfg") or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(BASE.ROOT)):
		push_error("C3 smoke requires authorized empty disposable user directory.")
		quit(2)
		return
	var players=PLAYER.new()
	var master=players.make_id()
	expect(players.save_record(master_record(master)).is_empty(),"Fixture master save failed")
	var original=players.load_record(master)
	var a=base.create_campaign("C3 fixture",master,"tavern","standard")
	var b=base.create_campaign("C3 sibling",master,"road","standard")
	if a.is_empty() or b.is_empty():
		expect(false,"Campaign creation failed")
		finish()
		return
	var id=a["id"]
	var sibling=base.gameplay_view(b["id"])
	var migrated=MIGRATION.new().ensure(id)
	if not migrated.get("ok",false):
		expect(false,"C2 migration failed")
		finish()
		return
	expect(registry.catalogue()["tools"].size()==50,"Registered tool count incorrect")
	var bag=items(id)
	for name in ["dagger","shield","greatsword","leather-armor","magic:potion-of-healing-common","rations-1-day"]:
		expect(bag.has(name),"Missing migrated instance: "+name)
	if bag.size()<6:
		finish()
		return
	var gear_service=preload("res://persistence/noncombat_store.gd").new()
	var gear_state=session.token(id)
	var gear_pack=gear_service.read_owned(gear_state,gear_state["actor_id"])
	if gear_pack.get("ok",false):
		var gear_actor=gear_pack["actor"]
		var calculated=gear_service.gear_stats(gear_pack,gear_actor)
		if not calculated.is_empty():
			print("Equipment saving throws raw equality: ",calculated["saving_throws"]==gear_actor["saving_throws"]," typed equality: ",session.typed_equal(calculated["saving_throws"],gear_actor["saving_throws"]))
			expect(gear_service.same_gear(calculated,gear_actor),"Equivalent persisted gear rejected")
			var wrong=gear_actor.duplicate(true)
			wrong["saving_throws"]["str"]+=1
			expect(not gear_service.same_gear(calculated,wrong),"Incorrect saving throw accepted")
			wrong=gear_actor.duplicate(true)
			wrong["saving_throws"]["str"]=str(wrong["saving_throws"]["str"])
			expect(not gear_service.same_gear(calculated,wrong),"String saving throw accepted")
		else:
			expect(false,"Gear calculation unavailable")
	else:
		expect(false,"Gear fixture read failed")
	var req=request(id,"equip",{"instance_id":bag["shield"],"slot":"shield","grip":"one_handed"})
	expect(not registry.execute(id,req,Callable()).get("ok",false),"Unreviewed equip accepted")
	var eq=registry.execute(id,req,review)
	expect(eq.get("ok",false),"Equip shield failed: "+str(eq.get("error","")))
	expect(base.actor_record(id)["combat"]["armor_class"]==14,"Shield AC wrong")
	expect(registry.execute(id,req,review).get("replayed",false),"Equip replay missing")
	var invalid_swap=action(id,"swap",{"instance_id":bag["greatsword"],"slot":"main_hand","grip":"two_handed","replace_instance_ids":[]})
	expect(not invalid_swap.get("ok",false),"Implicit displaced shield accepted")
	var swap=action(id,"swap",{"instance_id":bag["greatsword"],"slot":"main_hand","grip":"two_handed","replace_instance_ids":[bag["shield"]]})
	expect(swap.get("ok",false) and base.actor_record(id)["combat"]["armor_class"]==12,"Atomic two-hand swap or AC failed")
	var armor=action(id,"quick_equip",{"instance_id":bag["leather-armor"],"slot":"body","grip":"worn"})
	expect(armor.get("ok",false) and base.actor_record(id)["combat"]["armor_class"]==13,"Armor formula wrong")
	var actor_id=session.token(id)["actor_id"]
	var potion=request(id,"item_use",{"instance_id":bag["magic:potion-of-healing-common"],"quantity":1,"target_id":actor_id})
	var consumed=registry.execute(id,potion,review)
	expect(consumed.get("ok",false) and consumed.get("result",{}).get("rolls",[]).size()==1,"Healing potion failed")
	var replay=registry.execute(id,potion,review)
	expect(replay.get("replayed",false) and replay.get("result")==consumed.get("result"),"Potion rerolled/replayed differently")
	expect(not items(id).has("magic:potion-of-healing-common"),"Potion quantity not removed")
	var ration=action(id,"item_use",{"instance_id":bag["rations-1-day"],"quantity":1,"target_id":actor_id})
	expect(ration.get("ok",false) and not items(id).has("rations-1-day"),"Ration accounting failed")
	# Inject late actor-write failure after the settlement/event inserts.
	var resource=request(id,"resource_use",{"resource_id":"second_wind","quantity":1,"target_id":actor_id})
	var before=session.token(id)
	var fault=SQL.run(base.path_for(id),[SQL.stmt("CREATE TRIGGER c3_fixture_abort BEFORE UPDATE ON actors BEGIN SELECT RAISE(ABORT,'fixture rollback'); END")])
	expect(fault.get("ok",false),"Fault trigger failed")
	var interrupted=registry.execute(id,resource,review)
	expect(not interrupted.get("ok",false) and registry.noncombat.prepared.has(id),"Injected failure not retained for retry")
	expect(session.token(id)["revision"]==before["revision"] and base.actor_record(id)["resources"]["second_wind"]["spent"]==0,"Resource partially committed")
	var held=registry.noncombat.prepared.get(id,{}).get("result",{}).get("rolls",[])
	SQL.run(base.path_for(id),[SQL.stmt("DROP TRIGGER c3_fixture_abort")])
	var retried=registry.execute(id,resource,review)
	expect(retried.get("ok",false) and retried.get("result",{}).get("rolls",[])==held and base.actor_record(id)["resources"]["second_wind"]["spent"]==1,"Prepared retry changed dice or expenditure")
	var short=action(id,"rest",{"rest_kind":"short","hit_dice":0,"prepared_ids":null})
	expect(short.get("ok",false) and base.actor_record(id)["resources"]["second_wind"]["spent"]==0,"Short rest reset failed")
	# Source-backed object and contextual difficulty, no keyword matching.
	var evidence=SQL.run(base.path_for(id),[SQL.stmt("SELECT max(id) AS id FROM events WHERE kind='gameplay_change'")],true)
	var source_id=int(evidence["results"][0][0]["id"]) if evidence.get("ok",false) else 0
	var object=action(id,"story_update",{"record_id":null,"identity_key":"object:fixture-door","kind":"circumstance","title":"Fixture door","description":"An established unlocked door.","status":"closed","visibility":"player","certainty":"fact","location_id":session.token(id)["location_id"],"parent_id":null,"source_event_id":source_id,"progress_current":null,"progress_max":null,"participants":[]})
	expect(object.get("ok",false),"Object fact failed")
	if object.get("ok",false):
		var opened=action(id,"object_interact",{"object_id":object["result"]["record_id"],"operation":"open","source_event_id":source_id})
		expect(opened.get("ok",false) and opened.get("result",{}).get("status")=="open","Routine object open failed")
	var direct=session.token(id)
	var test_turn=session.make_id()
	var raw_action={"handler_id":"observe","target_refs":[],"reference_refs":[],"intent_text":"Fixture direct bypass attempt.","arguments":{}}
	var approval={"campaign_id":id,"actor_id":actor_id,"turn_id":test_turn,"expected_revision":direct["revision"],"action":raw_action,"ruling":{"safe_nonmechanical":true,"seconds":0,"establish_clock":false}}
	var prepared=registry.resolver.prepare(direct,test_turn,raw_action,approval)
	expect(prepared.get("ok",false) and not TURN.new().commit_receipt(id,direct,prepared.get("receipt",{}),"Fixture direct bypass attempt.").get("ok",false),"B2 bypassed C2 adoption")
	var challenge=request(id,"ability_check",{"ability":"str","skill":null,"difficulty":"medium","text":"Try the heavy latch.","source_event_id":source_id,"circumstances":[]})
	var checked=registry.execute(id,challenge,review)
	expect(checked.get("ok",false) and checked.get("receipt",{}).get("results",[{}])[0].get("dc")==15 and checked.get("receipt",{}).get("rolls",[]).size()==1,"Contextual check receipt failed")
	expect(finish_turn(id,challenge,checked),"Check settlement failed")
	var conversation=request(id,"conversation",{"text":"Good morning."})
	var result=registry.execute(id,conversation,review)
	expect(result.get("ok",false) and result.get("receipt",{}).get("rolls",[]).is_empty(),"Conversation rolled dice or failed")
	expect(not action(id,"unequip",{"instance_id":bag["leather-armor"],"slot":"body"}).get("ok",false),"Standalone equip bypassed pending narration")
	expect(finish_turn(id,conversation,result),"Receipt-backed settlement recovery failed")
	var wait=request(id,"wait",{"seconds":60,"text":"Wait one minute."})
	var waiting=registry.execute(id,wait,review)
	expect(finish_turn(id,wait,waiting),"Tracked wait failed")
	expect(action(id,"rest",{"rest_kind":"long","hit_dice":0,"prepared_ids":null}).get("ok",false),"Long rest failed")
	expect(not action(id,"rest",{"rest_kind":"long","hit_dice":0,"prepared_ids":null}).get("ok",false),"Repeat long-rest benefit accepted")
	var saved=SQL.run(base.path_for(id),[SQL.stmt("PRAGMA integrity_check"),SQL.stmt("PRAGMA foreign_key_check")],true)
	expect(saved.get("ok",false) and saved["results"][0][0]["integrity_check"]=="ok" and saved["results"][1].is_empty(),"SQL integrity failed")
	expect(players.load_record(master)==original and base.gameplay_view(b["id"])==sibling,"Master/sibling changed")
	# Separate caster fixture; explicit self-target, actual prepared spell, slot.
	var cleric=players.make_id()
	expect(players.save_record(master_record(cleric,"cleric")).is_empty(),"Caster master fixture failed")
	var c=base.create_campaign("C3 caster",cleric,"tavern","standard")
	if not c.is_empty() and MIGRATION.new().ensure(c["id"]).get("ok",false):
		var cid=c["id"]
		var cast=request(cid,"spell_cast",{"spell_id":"cure-wounds","source":"prepared","slot_level":1,"target_id":session.token(cid)["actor_id"]})
		var spell=registry.execute(cid,cast,review)
		expect(spell.get("ok",false) and base.actor_record(cid)["spellcasting"]["slots"]["1"]["spent"]==1,"Spell slot or healing failed")
		expect(registry.execute(cid,cast,review).get("replayed",false) and base.actor_record(cid)["spellcasting"]["slots"]["1"]["spent"]==1,"Spell slot spent twice")
		expect(not action(cid,"spell_cast",{"spell_id":"fireball","source":"prepared","slot_level":3,"target_id":session.token(cid)["actor_id"]}).get("ok",false),"Unsupported spell accepted")
	else:
		expect(false,"Caster campaign migration failed")
	finish()
