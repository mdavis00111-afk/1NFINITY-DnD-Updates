extends SceneTree
## C2 integration smoke. All fixtures are disposable, no provider or real combat.
const BASE = preload("res://campaigns/campaign_store.gd")
const PLAYER = preload("res://players/character_store.gd")
const CAT = preload("res://rules/catalog.gd")
const SQL = preload("res://systems/sqlite.gd")
const MIGRATION = preload("res://persistence/gameplay_migration.gd")
const SESSION = preload("res://persistence/gameplay_session.gd")
const GENERATOR = preload("res://persistence/actor_generation.gd")
const LOOT = preload("res://persistence/loot_store.gd")
const STORY = preload("res://persistence/story_store.gd")
const EQUIP = preload("res://persistence/equipment_store.gd")
const QUERIES = preload("res://persistence/gameplay_queries.gd")
const UI = preload("res://gameplay/ui_intents.gd")
const WORLD = preload("res://world/world_store.gd")
var failures: Array[String] = []
var base = BASE.new()
var session = SESSION.new()
var loot = LOOT.new()
var stories = STORY.new()

func _initialize() -> void:
	run.call_deferred()

func expect(ok: bool,message: String) -> void:
	if not ok:
		failures.append(message)

func finish() -> void:
	for message in failures:
		push_error(message)
	print("C2 persistence smoke failures: ",failures.size())
	quit(0 if failures.is_empty() else 1)

func money(gp: int = 0) -> Dictionary:
	return {"cp":0,"sp":0,"ep":0,"gp":gp,"pp":0}

func master_record(id: String,equipped: bool = false) -> Dictionary:
	return {"id":id,"name":"C2 fixture adventurer","status":"ready","ruleset":CAT.RULESET,"catalog_revision":CAT.REVISION,"level":1,"ability_scores":{"str":10,"dex":14,"con":12,"int":10,"wis":12,"cha":10},"ability_modifiers":{"str":0,"dex":2,"con":1,"int":0,"wis":1,"cha":0},"proficiency_bonus":2,"proficiency_ids":[],"expertise_ids":[],"skills":{},"saving_throws":{"str":0,"dex":2,"con":1,"int":0,"wis":1,"cha":0},"equipment":{"armor_id":"","shield_id":"","weapon_ids":["dagger"] if equipped else [],"armor_penalty":false},"inventory":[{"item_id":"dagger","quantity":2,"equipped":equipped}],"coins":money(2),"carrying_capacity_lb":150,"combat":{"hp_current":7,"hp_max":8,"conditions":[],"active_effects":[],"exhaustion":0}}

func request(id: String,kind: String,args: Dictionary,version: String = "2") -> Dictionary:
	var state = session.token(id)
	return {"schema_version":version,"campaign_id":id,"actor_id":state.get("actor_id"),"expected_revision":state.get("revision"),"request_id":session.make_id(),"kind":kind,"args":args}

func clearance(req: Dictionary,scope: String) -> Dictionary:
	return {"request_id":req["request_id"],"campaign_id":req["campaign_id"],"actor_id":req["actor_id"],"expected_revision":req["expected_revision"],"scope":scope,"approved":true}

func query(id: String,kind: String,args: Dictionary,local: bool = false) -> Dictionary:
	var state = session.token(id)
	var packet = {"schema_version":"2","campaign_id":id,"expected_revision":state.get("revision"),"query_id":session.make_id(),"kind":kind,"args":args,"limit":32}
	return QUERIES.new().query_local(id,packet) if local else QUERIES.new().query_public(id,packet)

func actor_args(id: String,location: String,event_id: int,existing: Variant,name: String,kind: String = "npc") -> Dictionary:
	return {"generation_key":session.make_id(),"template_ids":["commoner" if kind=="npc" else "bandit"],"existing_actor_id":existing,"kind":kind,"name":name,"occupation":"Innkeeper" if kind=="npc" else "Bandit","location_id":location,"visibility":"player","sheet_visibility":"private","source_event_id":event_id,"possessions":[{"definition_id":"dagger","quantity":2,"equipped_slot":null,"grip":null}],"coins":money(3),"attitude":null}

func story_args(kind: String,key: String,title: String,description: String,status: String,location: String,event_id: int) -> Dictionary:
	return {"record_id":null,"identity_key":key,"kind":kind,"title":title,"description":description,"status":status,"visibility":"player","certainty":"fact","location_id":location,"parent_id":null,"source_event_id":event_id,"progress_current":null,"progress_max":null,"participants":[]}

func run() -> void:
	var expected = OS.get_environment("INFINITY_TEST_USER_ROOT").replace("\\","/").trim_suffix("/")
	var actual = ProjectSettings.globalize_path("user://").replace("\\","/").trim_suffix("/")
	if expected.is_empty() or expected!=actual or FileAccess.file_exists("user://players.db") or FileAccess.file_exists("user://settings.cfg") or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(BASE.ROOT)):
		push_error("C2 smoke requires explicitly authorized empty disposable user directory.")
		quit(2)
		return
	var players = PLAYER.new()
	var master_id = players.make_id()
	expect(players.save_record(master_record(master_id)).is_empty(),"Master fixture save failed")
	var original_master = players.load_record(master_id)
	var a = base.create_campaign("C2 first",master_id,"tavern","standard")
	var b = base.create_campaign("C2 sibling",master_id,"road","standard")
	if a.is_empty() or b.is_empty():
		expect(false,"Campaign fixtures failed")
		finish()
		return
	var id = str(a["id"])
	var at = str(a["location_id"])
	var sibling = base.gameplay_view(b["id"])
	var original_actor = base.actor_record(id)
	var legacy = base.gameplay_view(id)
	var migrated = MIGRATION.new().ensure(id)
	expect(migrated.get("ok",false) and migrated.get("migrated",false),"Migration failed: "+str(migrated.get("error","")))
	if not migrated.get("ok",false):
		finish()
		return
	var backup = SQL.run(migrated["backup"],[SQL.stmt("PRAGMA integrity_check"),SQL.stmt("SELECT value FROM meta WHERE key='gameplay_schema'")],true)
	expect(backup.get("ok",false) and backup["results"][0][0]["integrity_check"]=="ok" and backup["results"][1].is_empty(),"Pre-C2 backup invalid")
	expect(base.actor_record(id)==original_actor and not MIGRATION.new().ensure(id).get("migrated",true),"Migration rewrote actor or duplicated")
	var view = base.gameplay_view(id)
	if view.is_empty() or not view.has("interaction"):
		expect(false,"C1 authoritative view unavailable: "+base.last_error)
		finish()
		return
	expect(UI.valid_view(view["interaction"],id,a["actor_id"]) and view["interaction"]["supported_intents"].is_empty() and view["inventory"]==legacy["inventory"],"C1 view or unchanged legacy inventory invalid")
	var original_instance = view["interaction"]["inventory_instances"][0]["instance_id"]
	expect(base.gameplay_view(id)["interaction"]["inventory_instances"][0]["instance_id"]==original_instance,"Stable migrated instance regenerated")
	var opening = base.prepare_opening(id)
	if opening.is_empty():
		expect(false,"Opening unavailable after migration")
		finish()
		return
	var raw = JSON.stringify({"start_id":"tavern","location_name":"Oak Inn","atmosphere":"A quiet room.","npcs":[{"name":"Mara","occupation":"Innkeeper","attitude":0}],"world_facts":["The floor is wooden."],"thumbnail_id":"tavern"})
	expect(base.commit_opening(id,opening["previous"],raw).is_empty(),"Opening after C2 migration failed")
	expect(not base.commit_opening(id,opening["previous"],raw).is_empty(),"Opening duplicated")
	view=base.gameplay_view(id)
	var extension = view.get("interaction_extension",{})
	if extension.get("public_actors",[]).size()!=1:
		expect(false,"Opening NPC disclosure not available")
		finish()
		return
	var mara = extension["public_actors"][0]["actor_id"]
	var opening_event = int(extension["public_actors"][0]["source_event_id"])
	var args = actor_args(id,at,opening_event,mara,"Mara")
	var generate = request(id,"actor_generate",args)
	expect(not GENERATOR.new().generate(id,generate).get("ok",false),"Unreviewed generation accepted")
	var generated = GENERATOR.new().generate(id,generate,true)
	expect(generated.get("ok",false) and generated.get("result",{}).get("actor_id")==mara,"Canonical upgrade failed: "+str(generated))
	if not generated.get("ok",false):
		finish()
		return
	expect(GENERATOR.new().generate(id,generate,true).get("replayed",false),"Generation replay not settled")
	var reused = GENERATOR.new().generate(id,request(id,"actor_generate",args),true)
	expect(reused.get("ok",false) and reused.get("result",{}).get("actor_id")==mara,"Existing individual regenerated")
	var public_sheet = query(id,"actor_sheet",{"actor_id":mara})
	var local_sheet = query(id,"actor_sheet",{"actor_id":mara},true)
	expect(public_sheet.get("ok",false) and public_sheet["data"]["actors"][0]["sheet"]==null and local_sheet.get("ok",false) and local_sheet["data"]["actors"][0]["template"]["stat_block"]==GENERATOR.new().template("commoner")["block"],"Canonical block or sheet disclosure incorrect")
	var definition = {"name":"Copper Marking Stylus","category":"tool","description":"A small copper stylus.","unit_weight_lb":0.1,"cost_cp":5,"properties":["writing implement"],"charges_max":null,"attunement_required":false,"mechanical_attributes":{"damage":null,"armor_class_base":null,"range_feet":null,"physical_options":[]}}
	var define_args = {"definition":definition,"source_event_id":opening_event,"official_equivalent_id":null}
	var define = request(id,"define_custom",define_args)
	var custom = loot.define_custom(id,define,clearance(define,"custom_definition"))
	expect(custom.get("ok",false),"Custom definition failed: "+str(custom))
	if not custom.get("ok",false):
		finish()
		return
	var custom_id = custom["result"]["definition_id"]
	var again = request(id,"define_custom",define_args)
	expect(loot.define_custom(id,again,clearance(again,"custom_definition")).get("result",{}).get("definition_id")==custom_id,"Custom definition duplicated")
	var equivalent = definition.duplicate(true)
	equivalent["name"]="Dagger"
	var official = request(id,"define_custom",{"definition":equivalent,"source_event_id":opening_event,"official_equivalent_id":null})
	expect(loot.define_custom(id,official,clearance(official,"custom_definition")).get("result",{}).get("definition_id")=="dagger","Official equivalent overridden")
	expect(not query(id,"item_definition",{"definition_id":custom_id}).get("ok",false),"Unowned private custom definition leaked")
	var discovery_args = {"source_event_id":opening_event,"location_id":at,"name":"Found supplies","items":[{"definition_id":"dagger","quantity":3,"charges":null,"condition":"intact","attunement":"not_required"},{"definition_id":custom_id,"quantity":1,"charges":null,"condition":"intact","attunement":"not_required"}],"coins":money(5)}
	var discover = request(id,"loot_discover",discovery_args)
	expect(not loot.reveal_discovery(id,discover,{}).get("ok",false),"Unverified discovery revealed loot")
	var found = loot.reveal_discovery(id,discover,clearance(discover,"eligible_discovery"))
	if not found.get("ok",false):
		expect(false,"Discovery failed: "+str(found))
		finish()
		return
	var container_id = found["result"]["container_id"]
	var repeated = request(id,"loot_discover",discovery_args)
	expect(loot.reveal_discovery(id,repeated,clearance(repeated,"eligible_discovery")).get("result",{}).get("container_id")==container_id,"Discovery duplicated")
	view=base.gameplay_view(id)
	extension=view.get("interaction_extension",{})
	if extension.get("loot_containers",[]).size()!=1:
		expect(false,"Visible loot projection unavailable")
		finish()
		return
	expect(view["actor"]["coins"]==money(2) and view["inventory"][0]["quantity"]==2,"Loot transferred automatically")
	var dagger_instance = ""
	for row in extension["loot_containers"][0]["items"]:
		if row["definition_id"]=="dagger": dagger_instance=row["instance_id"]
	var pickup = request(id,"loot_pickup",{"container_id":container_id,"source_event_id":opening_event,"items":[{"instance_id":dagger_instance,"quantity":1}],"coins":money(2)})
	var trigger = SQL.run(base.path_for(id),[SQL.stmt("CREATE TRIGGER c2_fixture_reject BEFORE INSERT ON item_transfers BEGIN SELECT RAISE(ABORT,'fixture'); END")])
	expect(trigger.get("ok",false),"Rollback fixture trigger failed")
	var frozen = session.token(id)
	expect(not loot.pickup(id,pickup,clearance(pickup,"loot_transfer")).get("ok",false),"Injected failure not rejected")
	expect(session.token(id)["revision"]==frozen["revision"] and not session.settlement(id,pickup["request_id"]).get("found",false) and base.gameplay_view(id)["actor"]["coins"]==money(2),"Failed pickup partially persisted")
	expect(SQL.run(base.path_for(id),[SQL.stmt("DROP TRIGGER c2_fixture_reject")]).get("ok",false),"Rollback fixture cleanup failed")
	var collected = loot.pickup(id,pickup,clearance(pickup,"loot_transfer"))
	expect(collected.get("ok",false) and collected.get("result",{}).get("items",[]).size()==1,"Selective pickup failed")
	expect(loot.pickup(id,pickup,clearance(pickup,"loot_transfer")).get("replayed",false),"Pickup replay not idempotent")
	var take = request(id,"loot_take_all",{"container_id":container_id,"source_event_id":opening_event})
	expect(loot.pickup(id,take,clearance(take,"loot_transfer")).get("ok",false),"Take all failed")
	view=base.gameplay_view(id)
	extension=view.get("interaction_extension",{})
	expect(view["actor"]["coins"]==money(7) and extension.get("loot_containers",[]).is_empty(),"Currency/closed loot view incorrect")
	# The two pieces of the same discovered stack have identical provenance.
	# They can be consolidated, not silently merged with the original master stack.
	if collected.get("ok",false) and collected.get("result",{}).get("items",[]).size()==1:
		var piece_id = collected["result"]["items"][0]["instance_id"]
		var merge = request(id,"stack_merge",{"source_instance_id":piece_id,"destination_instance_id":dagger_instance})
		var incompatible = request(id,"stack_merge",{"source_instance_id":piece_id,"destination_instance_id":original_instance})
		var before_merge = base.gameplay_view(id)
		var before_revision = session.token(id)["revision"]
		expect(not loot.merge_stacks(id,merge,{}).get("ok",false),"Unreviewed consolidation accepted")
		expect(not loot.merge_stacks(id,incompatible,clearance(incompatible,"stack_merge")).get("ok",false),"Distinct legacy/discovery provenance merged")
		var stale_merge = merge.duplicate(true)
		stale_merge["expected_revision"]=before_revision-1
		expect(not loot.merge_stacks(id,stale_merge,clearance(stale_merge,"stack_merge")).get("ok",false),"Stale consolidation accepted")
		expect(not loot.merge_stacks(b["id"],merge,clearance(merge,"stack_merge")).get("ok",false),"Cross-campaign consolidation accepted")
		expect(SQL.run(base.path_for(id),[SQL.stmt("CREATE TRIGGER c2_fixture_merge_reject BEFORE INSERT ON item_transfers BEGIN SELECT RAISE(ABORT,'fixture merge'); END")]).get("ok",false),"Merge rollback fixture unavailable")
		expect(not loot.merge_stacks(id,merge,clearance(merge,"stack_merge")).get("ok",false),"Injected consolidation failure accepted")
		expect(session.token(id)["revision"]==before_revision and not session.settlement(id,merge["request_id"]).get("found",false) and base.gameplay_view(id)==before_merge,"Failed consolidation partially persisted")
		expect(SQL.run(base.path_for(id),[SQL.stmt("DROP TRIGGER c2_fixture_merge_reject")]).get("ok",false),"Merge rollback fixture cleanup failed")
		var merged = loot.merge_stacks(id,merge,clearance(merge,"stack_merge"))
		expect(merged.get("ok",false) and merged.get("result",{}).get("quantity")==3 and merged.get("result",{}).get("destination_instance_id")==dagger_instance,"Consolidation did not preserve surviving instance")
		if merged.get("ok",false):
			var merged_view = BASE.new().gameplay_view(id)
			var merged_items = merged_view.get("interaction_extension",{}).get("inventory_instances",[])
			var retained = false
			var retired = true
			for item in merged_items:
				if item["instance_id"]==dagger_instance and item["quantity"]==3:
					retained=true
				if item["instance_id"]==piece_id:
					retired=false
			expect(retained and retired and merged_view.get("inventory")==before_merge["inventory"] and merged_view.get("actor")==before_merge["actor"] and merged_view["interaction_extension"]["revision"]==before_revision+1,"Consolidated view lost quantity, identity or changed actor")
			var history = SQL.run(base.path_for(id),[SQL.stmt("SELECT source_instance_id,destination_instance_id,quantity FROM item_transfers WHERE request_id=?",[merge["request_id"]])],true)
			expect(history.get("ok",false) and history["results"][0].size()==1 and history["results"][0][0]["source_instance_id"]==piece_id and history["results"][0][0]["destination_instance_id"]==dagger_instance and int(history["results"][0][0]["quantity"])==1,"Merge lineage not recorded")
			expect(loot.merge_stacks(id,merge,clearance(merge,"stack_merge")).get("replayed",false) and base.gameplay_view(id)==merged_view,"Consolidation replay changed state")
			view=merged_view
			extension=view.get("interaction_extension",{})
	var new_take = request(id,"loot_take_all",{"container_id":container_id,"source_event_id":opening_event})
	expect(not loot.pickup(id,new_take,clearance(new_take,"loot_transfer")).get("ok",false),"Closed loot collected twice")
	var custom_instance = ""
	for row in extension.get("inventory_instances",[]):
		if row["definition_id"]==custom_id: custom_instance=row["instance_id"]
	var drop = request(id,"item_drop",{"instance_id":custom_instance,"quantity":1})
	var dropped = loot.drop(id,drop,clearance(drop,"drop_transfer"))
	expect(dropped.get("ok",false) and dropped.get("result",{}).get("instance_id")==custom_instance,"Whole item drop changed identity")
	if dropped.get("ok",false):
		var drop_event = session.settlement(id,drop["request_id"])["event_id"]
		var recover = request(id,"loot_take_all",{"container_id":dropped["result"]["container_id"],"source_event_id":drop_event})
		expect(loot.pickup(id,recover,clearance(recover,"loot_transfer")).get("ok",false),"Dropped possession not recoverable")
	# Future post-combat interface only: explicit committed disposable outcome
	# fixture, not a combat engine or a generated defeat.
	var enemy_req = request(id,"actor_generate",actor_args(id,at,opening_event,null,"Bram","enemy"))
	var enemy = GENERATOR.new().generate(id,enemy_req,true)
	expect(enemy.get("ok",false),"Enemy template generation failed")
	if enemy.get("ok",false):
		var eid = enemy["result"]["actor_id"]
		var enc = players.make_id()
		var owned = query(id,"inventory",{"actor_id":eid},true)
		var recoverable: Array = []
		for row in owned.get("data",{}).get("items",[]):
			recoverable.append(row["instance_id"])
		var fixture = SQL.run(base.path_for(id),[SQL.stmt("INSERT INTO encounters(id,status,payload) VALUES(?,'resolved','{}')",[enc]),SQL.stmt("INSERT INTO events(turn,game_time,kind,payload) VALUES(0,'Unstarted','encounter_outcome',?)",[JSON.stringify({"schema_version":"1","encounter_id":enc,"source_actor_id":eid,"location_id":at,"loot_eligible":true,"recoverable_instance_ids":recoverable,"recover_currency":true,"visibility":"player"})]),SQL.stmt("UPDATE world_state SET revision=revision+1 WHERE campaign_id=?",[id]),SQL.stmt("SELECT max(id) AS id FROM events")])
		expect(fixture.get("ok",false),"Outcome fixture failed")
		if fixture.get("ok",false):
			var outcome_id = int(fixture["results"][3][0]["id"])
			var reveal = request(id,"loot_outcome",{"source_event_id":outcome_id})
			expect(not loot.reveal_outcome(id,reveal,{}).get("ok",false),"Unverified outcome revealed possessions")
			var result = loot.reveal_outcome(id,reveal,clearance(reveal,"eligible_outcome"))
			expect(result.get("ok",false) and query(id,"inventory",{"actor_id":eid},true)["data"]["items"].is_empty(),"Eligible recoverable ownership not moved to loot")
			expect(base.gameplay_view(id)["actor"]["coins"]==money(7),"Outcome auto-awarded currency")
	# Quest and objective lifecycle, persistent relationship and private factors.
	var qa = story_args("quest","ledger-quest","Missing ledger","Find the missing ledger.","active",at,opening_event)
	var invalid = request(id,"story_update",qa)
	expect(not stories.update_story(id,invalid,true).get("ok",false),"Quest forced active on introduction")
	qa["status"]="offered"
	var offered = stories.update_story(id,request(id,"story_update",qa),true)
	if not offered.get("ok",false):
		expect(false,"Quest offer failed")
		finish()
		return
	var quest_id = offered["result"]["record_id"]
	qa["record_id"]=quest_id
	qa["status"]="active"
	qa["source_event_id"]=session.settlement(id,pickup["request_id"])["event_id"]
	expect(stories.update_story(id,request(id,"story_update",qa),true).get("ok",false),"Reviewed quest acceptance failed")
	var oa = story_args("objective","ledger-objective","Recover ledger","Recover both pages.","active",at,opening_event)
	oa["parent_id"]=quest_id
	oa["progress_current"]=1
	oa["progress_max"]=2
	var objective = stories.update_story(id,request(id,"story_update",oa),true)
	expect(objective.get("ok",false),"Objective failed")
	qa["status"]="completed"
	expect(not stories.update_story(id,request(id,"story_update",qa),true).get("ok",false),"Quest completed before objective")
	if objective.get("ok",false):
		oa["record_id"]=objective["result"]["record_id"]
		oa["status"]="completed"
		oa["progress_current"]=2
		expect(stories.update_story(id,request(id,"story_update",oa),true).get("ok",false),"Objective completion failed")
		expect(stories.update_story(id,request(id,"story_update",qa),true).get("ok",false),"Quest completion failed")
	var grievance = story_args("repeat_offender","mara-grievance","Recurring grievance","A prior broken promise.","open",at,opening_event)
	grievance["certainty"]="attitude"
	grievance["participants"]=[{"actor_id":mara,"role":"subject"}]
	var first = stories.update_story(id,request(id,"story_update",grievance),true)
	expect(first.get("ok",false),"Persistent factor failed")
	if first.get("ok",false):
		grievance["record_id"]=first["result"]["record_id"]
		grievance["description"]="A second unresolved disagreement."
		expect(stories.update_story(id,request(id,"story_update",grievance),true).get("ok",false),"Recurring factor update failed")
		expect(query(id,"story_history",{"record_id":grievance["record_id"]})["data"]["history"].size()==2,"Older significant factor history lost")
	var secret = story_args("debt","secret-debt","PRIVATE C2 DEBT","Unrevealed debt.","open",at,opening_event)
	secret["visibility"]="private"
	expect(stories.update_story(id,request(id,"story_update",secret),true).get("ok",false),"Private story fixture failed")
	view=base.gameplay_view(id)
	expect(not JSON.stringify(view).contains("PRIVATE C2 DEBT") and query(id,"story",{"kind":"debt","location_id":null,"participant_id":null},true)["data"]["records"].size()==1,"Private story leaked or unavailable locally")
	# Durable v1 adoption; no mechanics, no live adapter.
	var adopted = request(id,"chat",{"text":"An uncommitted fixture action."},"1")
	var logical = players.make_id()
	var rev = session.token(id)["revision"]
	expect(session.adopt(id,adopted,logical).get("status")=="accepted_pending","Durable request adoption failed")
	view=base.gameplay_view(id)
	expect(view["interaction"]["settled_request_id"]==adopted["request_id"] and view["interaction"]["phase"]=="blocked" and view["interaction"]["revision"]==rev,"Pending request view invalid")
	# Reproduce a structurally legal SQLite row whose revision contradicts its JSON.
	var original_adoption = session.settlement(id,adopted["request_id"])
	expect(original_adoption.get("ok",false),"Pending adoption unavailable")
	expect(SQL.run(base.path_for(id),[SQL.stmt("UPDATE gameplay_requests SET expected_revision=expected_revision+1 WHERE request_id=?",[adopted["request_id"]])]).get("ok",false),"Corrupt revision fixture")
	expect(not session.settlement(id,adopted["request_id"]).get("ok",false),"Relational/JSON revision mismatch accepted")
	expect(SQL.run(base.path_for(id),[SQL.stmt("UPDATE gameplay_requests SET expected_revision=? WHERE request_id=?",[adopted["expected_revision"],adopted["request_id"]])]).get("ok",false),"Restore adopted request revision")
	expect(session.settlement(id,adopted["request_id"])==original_adoption,"Restored adoption differs")
	expect(session.settle_adopted(id,adopted["request_id"],"cancelled",true).get("status")=="cancelled" and session.token(id)["revision"]==rev,"Request cancellation changed mechanics")
	expect(query(id,"overview",{}).get("ok",false) and query(id,"history",{"location_id":at,"before_event_id":null}).get("ok",false) and query(id,"geography",{"page":0}).get("ok",false),"Bounded retrieval unavailable")
	expect(query(id,"rules_search",{"category":"equipment","query":"dagger"}).get("ok",false) and query(id,"actor_template",{"template_id":"commoner"}).get("ok",false),"Pinned rules/template retrieval unavailable")
	var integrity = SQL.run(base.path_for(id),[SQL.stmt("PRAGMA integrity_check"),SQL.stmt("PRAGMA foreign_key_check"),SQL.stmt("SELECT count(*) AS n FROM movement_history")],true)
	expect(integrity.get("ok",false) and integrity["results"][0][0]["integrity_check"]=="ok" and integrity["results"][1].is_empty() and int(integrity["results"][2][0]["n"])==0,"Integrity or unauthorized movement")
	expect(base.actor_record(id)["combat"]==original_actor["combat"] and base.gameplay_view(b["id"])==sibling and players.load_record(master_id)==original_master,"Master, sibling or player combat changed")
	# Old weapon list has no hand. Preserve and require explicit local mapping.
	var equipped_master = players.make_id()
	expect(players.save_record(master_record(equipped_master,true)).is_empty(),"Equipped master fixture failed")
	var c = base.create_campaign("Legacy equipped",equipped_master,"road","standard")
	if not c.is_empty() and MIGRATION.new().ensure(c["id"]).get("ok",false):
		var unresolved = base.gameplay_view(c["id"])
		expect(not unresolved.has("interaction") and unresolved.get("interaction_extension",{}).get("equipment_review",[]).size()==1,"Invented legacy hand assignment")
		if not unresolved.get("interaction_extension",{}).get("equipment_review",[]).is_empty():
			var iid = unresolved["interaction_extension"]["equipment_review"][0]["instance_id"]
			var reconcile = request(c["id"],"reconcile_legacy_slots",{"assignments":[{"instance_id":iid,"slot":"main_hand","grip":"one_handed"}]})
			expect(EQUIP.new().reconcile_legacy_slots(c["id"],reconcile,true).get("ok",false),"Reviewed legacy hand reconciliation failed")
			var resolved = base.gameplay_view(c["id"])
			expect(resolved.has("interaction") and resolved["interaction"]["slot_assignments"]["main_hand"]==iid,"Reconciled C1 slots invalid")
	else:
		expect(false,"Legacy equipment migration fixture failed")
	# A legacy claim with zero owned rows must not be silently migrated into
	# an irreconcilable instance model. Deliberately corrupt a separate fixture
	# after B1 has been established, so C2 rollback/retry can be compared exactly.
	var missing = base.create_campaign("Legacy missing ownership",equipped_master,"road","standard")
	if missing.is_empty():
		expect(false,"Missing ownership fixture creation failed")
	else:
		var missing_id = str(missing["id"])
		var missing_path = base.path_for(missing_id)
		var wm = preload("res://world/world_migration.gd").new().ensure(missing_id)
		expect(wm.get("ok",false),"B1 migration for missing ownership fixture failed")
		if wm.get("ok",false):
			var original = SQL.run(missing_path,[SQL.stmt("SELECT actor_id,item_id,quantity,payload FROM inventory ORDER BY actor_id,item_id")],true)
			expect(original.get("ok",false) and original["results"][0].size()==1,"Missing ownership fixture inventory unavailable")
			if original.get("ok",false) and original["results"][0].size()==1:
				var item = original["results"][0][0]
				expect(SQL.run(missing_path,[SQL.stmt("DELETE FROM inventory WHERE actor_id=?",[missing["actor_id"]])]).get("ok",false),"Missing ownership fixture deletion failed")
				var before = SQL.run(missing_path,[SQL.stmt("SELECT id,payload FROM actors ORDER BY id"),SQL.stmt("SELECT * FROM world_state"),SQL.stmt("SELECT * FROM inventory ORDER BY actor_id,item_id"),SQL.stmt("SELECT value FROM meta WHERE key='gameplay_schema'"),SQL.stmt("SELECT name FROM sqlite_master WHERE type='table' AND name='item_instances'")],true)
				var refused = MIGRATION.new().ensure(missing_id)
				var after = SQL.run(missing_path,[SQL.stmt("SELECT id,payload FROM actors ORDER BY id"),SQL.stmt("SELECT * FROM world_state"),SQL.stmt("SELECT * FROM inventory ORDER BY actor_id,item_id"),SQL.stmt("SELECT value FROM meta WHERE key='gameplay_schema'"),SQL.stmt("SELECT name FROM sqlite_master WHERE type='table' AND name='item_instances'")],true)
				expect(not refused.get("ok",false) and str(refused.get("error","")).contains("Legacy weapon not owned"),"Zero-row legacy equipment claim was not rejected")
				expect(before.get("ok",false) and after.get("ok",false) and before["results"]==after["results"] and after["results"][3].is_empty() and after["results"][4].is_empty(),"Refused migration changed authoritative state or created partial schema")
				expect(SQL.run(missing_path,[SQL.stmt("INSERT INTO inventory(actor_id,item_id,quantity,payload) VALUES(?,?,CAST(? AS INTEGER),?)",[item["actor_id"],item["item_id"],item["quantity"],item["payload"]])]).get("ok",false),"Fixture repair failed")
				var repaired = MIGRATION.new().ensure(missing_id)
				expect(repaired.get("ok",false) and repaired.get("migrated",false),"C2 migration could not resume after explicit fixture repair")
				if repaired.get("ok",false):
					var once = base.gameplay_view(missing_id)
					var repeated = MIGRATION.new().ensure(missing_id)
					expect(repeated.get("ok",false) and not repeated.get("migrated",true) and base.gameplay_view(missing_id)==once,"Repeat migration changed stable repaired state")
	expect(base.gameplay_view(b["id"])==sibling and players.load_record(master_id)==original_master,"Missing ownership fixture affected sibling/master")
	finish()
