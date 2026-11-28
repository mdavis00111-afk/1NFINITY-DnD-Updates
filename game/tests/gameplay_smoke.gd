extends SceneTree
## Run in explicitly authorized disposable user data; never use personal saves.
const STORE = preload("res://campaigns/campaign_store.gd")
const PLAYER = preload("res://players/character_store.gd")
const SQL = preload("res://systems/sqlite.gd")
const UI = preload("res://gameplay/game_workspace.gd")
const DICE = preload("res://gameplay/manual_dice.gd")
const DISPLAY = preload("res://gameplay/display_values.gd")
const CATALOG = preload("res://rules/catalog.gd")
const STARTS = preload("res://campaigns/campaign_starts.gd")
const INTENTS = preload("res://gameplay/ui_intents.gd")
# Synthetic instance IDs for isolated C2-contract fixtures only, never persisted.
const TEST_SWORD = "11111111111111111111111111111111"
const TEST_SHIELD = "22222222222222222222222222222222"
const TEST_GREAT = "33333333333333333333333333333333"
const TEST_RING = "44444444444444444444444444444444"
const TEST_POTION = "55555555555555555555555555555555"
const TEST_LONG = "66666666666666666666666666666666"
const TEST_QUEST = "77777777777777777777777777777777"
const TEST_DEST = "88888888888888888888888888888888"
const TEST_TURN = "99999999999999999999999999999999"
const TEST_PARTY = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const TEST_WRONG = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func settle() -> void:
	for i in range(5): await process_frame

func inside(control: Control, bounds: Rect2, context: String) -> void:
	if not is_instance_valid(control):
		expect(false,context+" control absent")
		return
	var rect=control.get_global_rect()
	expect(rect.has_area() and bounds.grow(2).encloses(rect),context+" clipped: "+str(control.get_path())+" rect="+str(rect)+" bounds="+str(bounds)+" minimum="+str(control.get_combined_minimum_size()))

func has_text(node: Node, fragment: String) -> bool:
	if node is Label or node is Button or node is RichTextLabel:
		if str(node.get("text")).contains(fragment):
			return true
	for child in node.get_children():
		if has_text(child,fragment):
			return true
	return false

func run() -> void:
	var expected = OS.get_environment("INFINITY_TEST_USER_ROOT").replace("\\","/").trim_suffix("/")
	var actual = ProjectSettings.globalize_path("user://").replace("\\","/").trim_suffix("/")
	if expected.is_empty() or expected!=actual or FileAccess.file_exists("user://players.db") or FileAccess.file_exists("user://settings.cfg") or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(STORE.ROOT)):
		push_error("Gameplay smoke requires an explicitly authorized empty disposable user directory.")
		quit(2)
		return
	var players = PLAYER.new()
	var master_id = players.make_id()
	var fixture = {"id":master_id,"name":"A Very Long Test Character Name of the Northern Lands","status":"ready","ruleset":"5e-2014-2018","race_id":"human","class_id":"wizard","level":1,"combat":{"hp_current":4,"hp_max":7,"armor_class":11,"speed_feet":30,"initiative":1,"passive_perception":12},"ability_scores":{"str":10,"dex":12,"con":12,"int":16,"wis":14,"cha":8},"ability_modifiers":{"str":0,"dex":1,"con":1,"int":3,"wis":2,"cha":-1},"proficiency_bonus":2,"coins":{"pp":0,"gp":17,"ep":0,"sp":2,"cp":0},"carried_weight_lb":6,"carrying_capacity_lb":150,"inventory":[{"item_id":"shortsword","quantity":1,"equipped":true},{"item_id":"backpack","quantity":1,"equipped":false},{"item_id":"arrow","quantity":20,"equipped":false}],"equipment":{"armor_id":"","shield_id":"shield","weapon_ids":["shortsword","backpack"]},"spellcasting":{"cantrip_ids":["fire-bolt"],"known_ids":["sleep"],"prepared_ids":["sleep"],"slots":{"1":{"maximum":2,"spent":1}},"save_dc":13,"attack_bonus":5},"skills":{"arcana":{"modifier":5,"proficient":true}}}
	var error = players.save_record(fixture)
	expect(error.is_empty(),"Master fixture save failed: "+error)
	var master = players.load_record(master_id)
	var store = STORE.new()
	var campaign = store.create_campaign("Gameplay fixture",master_id,"road","standard")
	expect(not campaign.is_empty(),"Campaign creation failed: "+store.last_error)
	if campaign.is_empty():
		finish()
		return
	var id = str(campaign["id"])
	var updated = SQL.run(store.path_for(id),[SQL.stmt("UPDATE inventory SET quantity=3 WHERE actor_id=? AND item_id='backpack'",[campaign["actor_id"]]),SQL.stmt("INSERT INTO events(turn,game_time,kind,payload) VALUES(0,?,'synopsis',?)",["Test",JSON.stringify({"text":"Not a chat event"})]),SQL.stmt("INSERT INTO events(turn,game_time,kind,payload) VALUES(0,?,'narration',?)",["Test",JSON.stringify({"text":"Committed dialogue fixture. ".repeat(120)})])])
	expect(updated.get("ok",false),"Fixture event/inventory update failed")
	var snapshot = store.gameplay_view(id)
	expect(not snapshot.is_empty() and snapshot.get("events",[]).size()==2,"Projection omitted committed events or included synopsis")
	var canonical = false
	for item in snapshot.get("inventory",[]):
		if item["item_id"]=="backpack": canonical = item["quantity"]==3
	expect(canonical,"Inventory read used stale actor payload")
	var projected = snapshot.get("actor",{})
	var load = projected.get("carried_weight_lb")
	expect(load!=null and is_equal_approx(float(load),18.38),"Current load must include three backpacks, shortsword, 20 arrows and 19 coins")
	expect(projected.get("equipment",{}).get("weapon_ids")==["shortsword"] and projected.get("equipment",{}).get("shield_id")=="","Stale or unequipped slot item displayed")
	expect(projected.get("combat")==master.get("combat") and projected.get("skills")==master.get("skills") and projected.get("spellcasting")==master.get("spellcasting") and projected.get("coins")==master.get("coins"),"Projection altered committed actor statistics")
	var catalogue = CATALOG.new()
	for pair in [["arrow",0.05],["crossbow-bolt",0.075],["blowgun-needle",0.02],["sling-bullet",0.075]]:
		var unit = DISPLAY.unit_weight(catalogue,pair[0])
		expect(unit!=null and is_equal_approx(float(unit),pair[1]),"Incorrect per-projectile weight: "+pair[0])
	var incomplete = DISPLAY.weight_summary(catalogue,[{"item_id":"missing-test-item","quantity":1}],{})
	expect(not incomplete["complete"] and incomplete["missing"].has("missing-test-item"),"Unknown weight silently treated as complete")
	expect(DISPLAY.remaining_text(2,1)=="1 / 2" and DISPLAY.remaining_text(2,2)=="0 / 2" and DISPLAY.remaining_text(2,3)=="— / 2" and DISPLAY.remaining_text(2,null)=="— / 2","Invalid slot/resource display")
	var racial_fixture = {"spellcasting":{"racial_cantrip_ids":["fire-bolt"],"racial_casting_ability":"int","save_dc":12},"ability_modifiers":{"int":3},"proficiency_bonus":2}
	expect(DISPLAY.racial_spell_text(racial_fixture).contains("Save DC 13") and DISPLAY.racial_spell_text(racial_fixture).contains("Attack +5"),"Racial spell ability incorrectly shares class DC")
	var original = snapshot.duplicate(true)
	test_intent_adapter(snapshot)
	var market = STARTS.texture_for("market")
	expect(market!=null and STARTS.texture_for("missing-art-id")!=null,"Scene artwork fallback missing")
	if market is AtlasTexture:
		expect(market.atlas!=null and Rect2(Vector2.ZERO,market.atlas.get_size()).encloses(market.region),"Market artwork crop outside texture")
	var raw_actor = store.actor_record(id)
	expect(raw_actor.get("carried_weight_lb")==6,"Read projection unexpectedly rewrote cached actor load")
	for sides in DICE.SIDES:
		for count in [1,20]:
			var roll = DICE.roll(sides,count)
			var sum = 0
			for value in roll.get("values",[]):
				expect(value>=1 and value<=sides,"Die outside range")
				sum+=value
			expect(roll.get("values",[]).size()==count and roll.get("total")==sum,"Dice total/count mismatch")
	expect(DICE.roll(7,1).is_empty() and DICE.roll(20,0).is_empty() and DICE.roll(20,21).is_empty(),"Invalid dice accepted")
	for resolution in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = resolution
		var base = Control.new()
		base.size = Vector2(resolution)
		root.add_child(base)
		var called: Array[String] = []
		var ui = UI.new()
		ui.configure(snapshot,campaign,func(): called.append("leave"),func(): called.append("settings"),func(): called.append("retry"),false)
		base.add_child(ui)
		ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await settle()
		var bounds = base.get_global_rect()
		for control in [ui.nav_bar,ui.left_panel,ui.center_panel,ui.right_panel,ui.composer,ui.send_button,ui.dice_type,ui.dice_count,ui.dice_result,ui.log_scroll]:
			inside(control,bounds,str(resolution))
		for nav_button in ui.nav_bar.get_children():
			inside(nav_button,bounds,"Navigation "+nav_button.text)
			var width = nav_button.get_theme_font("font").get_string_size(nav_button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,nav_button.get_theme_font_size("font_size")).x
			expect(width+8<=nav_button.size.x+1,"Navigation label clipped: "+nav_button.text)
		expect(not ui.composer.editable and ui.send_button.disabled,"Future action input unexpectedly active")
		expect(ui.slot_options("main_hand").size()==1 and ui.item_definition(ui.slot_options("main_hand")[0]["row"])=="shortsword","Legacy owned weapon picker fabricated or omitted a candidate")
		expect(ui.slot_options("body").is_empty() and ui.slot_options("shield").is_empty(),"Legacy empty slots fabricated owned armor/shield")
		expect(ui.legacy_slots({"item_id":"greatsword"})==["main_hand"],"Two-handed category offered as single offhand")
		ui.show_slot("body")
		await settle()
		var empty_equip = find_button(ui,"Equip / Swap")
		expect(empty_equip!=null and empty_equip.disabled,"Empty legacy slot not inspectable or mutation enabled")
		close_popups(ui)
		await settle()
		for caption in ["4 / 7","17 gp","2 sp","L1: 1 / 2"]:
			expect(has_text(ui.left_panel,caption),"Missing displayed campaign value: "+caption)
		expect(not has_text(ui.left_panel,"Passive Perception") and not has_text(ui.left_panel,"Proficiency"),"Removed statistics remain in HUD")
		ui.show_tab("Character")
		for caption in ["30 ft.","Weight: 18.38 / 150 lb","Passive Perception","Proficiency"]:
			expect(has_text(ui.right_content,caption),"Missing Character tab value: "+caption)
		ui.show_tab("Inventory")
		var columns_width = ui.left_panel.size.x+ui.center_panel.size.x+ui.right_panel.size.x
		expect(columns_width>0 and ui.center_panel.size.x>ui.left_panel.size.x and ui.center_panel.size.x>ui.right_panel.size.x,"Conversation must receive the largest column")
		expect(ui.inventory_cells.has("backpack") and ui.inventory_cells.has("shortsword"),"Normalized inventory cells missing")
		ui.select_item("backpack")
		expect(ui.inventory_detail.text.contains("Quantity: 3") and ui.inventory_detail.text.contains("Stack weight: 15 lb"),"Selected quantity or stack weight not normalized")
		expect(ui.equipped("shortsword") and not ui.equipped("backpack"),"Equipment filter not based on normalized inventory")
		ui.select_item("arrow")
		expect(ui.inventory_detail.text.contains("Unit weight: 0.05 lb") and ui.inventory_detail.text.contains("Stack weight: 1 lb") and ui.inventory_detail.text.contains("per 20"),"Ammunition display uses lot as individual")
		ui.roll_dice()
		expect(not ui.last_roll.is_empty(),"Manual UI roll failed")
		ui.dice_tool("Clear")
		expect(ui.last_roll.is_empty(),"Clear did not clear informational dice")
		var composer_ref = ui.composer
		var party_ref = ui.party_body
		for tab in ["Spells","Skills","Features","Character","Quest Log","Map","Notes","Rules","Inventory"]:
			ui.right_tabs[tab].pressed.emit()
			await settle()
			expect(ui.current_tab==tab and ui.right_content.get_child_count()>0,"Right panel switch failed")
			expect(ui.composer==composer_ref and ui.party_body==party_ref,"Tab switch rebuilt a permanent control")
			inside(ui.party_body,bounds,"Persistent party panel")
			inside(ui.send_button,bounds,"Persistent Send button")
			if tab=="Rules":
				expect(find_button(ui.right_content,"Rules (SRD)")!=null and find_button(ui.right_content,"Equipment")!=null,"Rules references missing")
			if tab=="Spells":
				expect(has_text(ui.right_content,"Class Save DC 13") and has_text(ui.right_content,"Attack +5") and has_text(ui.right_content,"Level 1 slots: 1 / 2"),"Spell statistics not displayed from actor")
			elif tab=="Skills":
				expect(has_text(ui.right_content,"◆ Arcana   +5"),"Stored skill modifier or proficiency missing")
		var menu = ui.menu_button.get_popup()
		expect(menu.item_count==8,"Compact menu entry count")
		for caption in ["Settings","Campaign"]:
			menu.id_pressed.emit(ui.MENU_ITEMS.find(caption))
		expect(called==["settings","leave"],"Navigation callbacks failed")
		# Empty and long-inventory/missing-art synthetic views exercise layout without writes.
		base.remove_child(ui)
		ui.queue_free()
		for item_count in [0,48]:
			var sparse = snapshot.duplicate(true)
			sparse["actor"]["spellcasting"]={}
			sparse["inventory"]=[]
			for i in range(item_count):
				sparse["inventory"].append({"item_id":"unmapped-long-equipment-name-"+str(i),"quantity":i+1,"equipped":false})
			sparse["campaign"]["thumbnail_id"]="missing-art-id"
			var variant_ui = UI.new()
			variant_ui.configure(sparse,campaign,func(): pass,func(): pass,func(): pass,false)
			base.add_child(variant_ui)
			variant_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			await settle()
			inside(variant_ui.right_panel,bounds,"Sparse/long inventory right panel")
			inside(variant_ui.composer,bounds,"Sparse/long inventory composer")
			expect(variant_ui.inventory_cells.size()==item_count,"Inventory cells missing")
			variant_ui.show_tab("Spells")
			await settle()
			expect(has_text(variant_ui.right_content,"No spells recorded."),"Non-caster fabricated spells")
			base.remove_child(variant_ui)
			variant_ui.queue_free()
		await test_bound_ui_fixture(snapshot,campaign,base)
		root.remove_child(base)
		base.queue_free()
		await settle()
	expect(store.gameplay_view(id)==original,"Read-only workspace changed campaign state")
	expect(store.actor_record(id)==raw_actor,"Read-only workspace changed underlying actor payload")
	# Corrupt only a separate disposable campaign, not the original/master fixture.
	var bad = store.create_campaign("Malformed fixture",master_id,"road","standard")
	expect(not bad.is_empty(),"Malformed fixture creation failed")
	if not bad.is_empty():
		var bad_id = str(bad["id"])
		var bad_path = store.path_for(bad_id)
		var bad_actor = store.actor_record(bad_id)
		var malformed = SQL.run(bad_path,[SQL.stmt("UPDATE inventory SET quantity=1.5 WHERE actor_id=? AND item_id='backpack'",[bad["actor_id"]])])
		expect(malformed.get("ok",false) and store.gameplay_view(bad_id).is_empty(),"Fractional SQL quantity silently truncated")
		var restored = SQL.run(bad_path,[SQL.stmt("UPDATE inventory SET quantity=1 WHERE actor_id=? AND item_id='backpack'",[bad["actor_id"]])])
		expect(restored.get("ok",false) and not store.gameplay_view(bad_id).is_empty(),"Valid integer quantity not readable")
		var wrong = bad_actor.duplicate(true)
		wrong["master_character_id"]="00000000000000000000000000000000"
		var wrong_identity = SQL.run(bad_path,[SQL.stmt("UPDATE actors SET payload=? WHERE id=?",[JSON.stringify(wrong),bad["actor_id"]])])
		expect(wrong_identity.get("ok",false) and store.gameplay_view(bad_id).is_empty(),"Mismatched campaign actor identity displayed")
		wrong=bad_actor.duplicate(true)
		wrong["equipment"]=null
		var wrong_shape = SQL.run(bad_path,[SQL.stmt("UPDATE actors SET payload=? WHERE id=?",[JSON.stringify(wrong),bad["actor_id"]])])
		expect(wrong_shape.get("ok",false) and store.gameplay_view(bad_id).is_empty(),"Malformed actor container displayed")
		expect(store.gameplay_view(id)==original,"Bad campaign affected sibling")
	expect(players.load_record(master_id)==master,"Workspace modified master")
	finish()

# C1 contract fixtures supplement, not replace, the real disposable SQL reads above.
# They simulate a future C2 view and capture intentions; no mock ever writes state.
func offer(slot: String,grip: String,replaced: Array = [],allowed: bool = true,warning: String = "") -> Dictionary:
	return {"slot":slot,"grip":grip,"replace_instance_ids":replaced,"available":allowed,"warning":warning}

func instance_row(id: String,definition: String,name_value: String,quantity: int,options: Array,attunement: String = "unknown") -> Dictionary:
	return {"instance_id":id,"definition_id":definition,"name":name_value,"description":"Fixture-only public details for "+name_value,"quantity":quantity,"equip_options":options,"attunement_status":attunement}

func future_fixture(snapshot: Dictionary) -> Dictionary:
	var value = snapshot.duplicate(true)
	var slots = {}
	for key in INTENTS.SLOTS:
		slots[key] = null
	slots["main_hand"] = TEST_SWORD
	slots["off_hand"] = TEST_SHIELD
	slots["shield"] = TEST_SHIELD
	value["actor"]["resources"] = {"fixture_resource":{"max":3,"spent":1}}
	value["actor"]["saving_throws"] = {"str":0,"dex":1,"con":1,"int":5,"wis":4,"cha":-1}
	value["locations"].append({"id":TEST_DEST,"name":"Disclosed fixture destination","kind":"town"})
	value["interaction"] = {
		"schema_version":"1","campaign_id":value["campaign"]["id"],"actor_id":value["actor"]["id"],"revision":7,
		"phase":"idle","pending_turn_id":null,"active_turn_id":null,"settled_request_id":null,"settled_status":null,
		"supported_intents":INTENTS.FIELDS.keys(),"status_text":"Fixture controller (no writes)",
		"slot_assignments":slots,
		"inventory_instances":[
			instance_row(TEST_SWORD,"shortsword","Fixture shortsword",1,[offer("main_hand","one_handed")]),
			instance_row(TEST_SHIELD,"shield","Fixture shield",1,[]),
			instance_row(TEST_GREAT,"greatsword","Fixture greatsword",1,[offer("main_hand","two_handed",[TEST_SWORD,TEST_SHIELD],true,"Fixture: both hands displaced.")]),
			instance_row(TEST_LONG,"longsword","Fixture versatile sword",1,[offer("main_hand","one_handed",[TEST_SWORD]),offer("main_hand","two_handed",[TEST_SWORD,TEST_SHIELD])]),
			instance_row(TEST_RING,"fixture-ring","Fixture ring",1,[offer("ring","worn")],"unattuned"),
			instance_row(TEST_POTION,"fixture-potion","Fixture potion",2,[])
		],
		"spell_options":[{"spell_id":"sleep","source":"prepared","slot_level":1,"available":true,"warning":""},{"spell_id":"sleep","source":"prepared","slot_level":2,"available":false,"warning":"Fixture slot unavailable."}],
		"preparation_options":[{"spell_id":"sleep","kind":"spell_unprepare","available":true,"warning":""},{"spell_id":"magic-missile","kind":"spell_prepare","available":true,"warning":"Fixture preparation offer."}],
		"public_quests":[{"id":TEST_QUEST,"title":"Disclosed fixture quest","description":"Fixture-only.","status":"active","source_event_id":2}],
		"party_members":[],"party_candidates":[{"actor_id":TEST_PARTY,"name":"Disclosed fixture companion","available":true,"warning":""}]
	}
	return value

func settled_view(view_value: Dictionary,id: String,phase: String = "idle",settlement: String = "committed") -> Dictionary:
	var value = view_value.duplicate(true)
	var packet = value["interaction"]
	packet["revision"] = int(packet["revision"])+1
	packet["settled_request_id"] = id
	packet["settled_status"] = settlement
	packet["phase"] = phase
	packet["active_turn_id"] = null if phase=="idle" else TEST_TURN
	packet["pending_turn_id"] = null if phase=="idle" else TEST_TURN
	return value

func test_intent_adapter(snapshot: Dictionary) -> void:
	var seen: Array = []
	var handler = func(packet: Dictionary):
		seen.append(packet.duplicate(true))
		return {"ok":true,"request_id":packet["request_id"],"message":"Fixture accepted; no write."}
	var legacy = INTENTS.new()
	legacy.configure(snapshot,handler)
	expect(not legacy.available("chat") and not legacy.request("chat",{"text":"Inspect."}).get("ok",false) and seen.is_empty(),"Legacy projection fabricated a revision or dispatched")
	var data = future_fixture(snapshot)
	var adapter = INTENTS.new()
	adapter.configure(data)
	expect(not adapter.available("equip") and not adapter.available("chat"),"Unbound future projection activated controls")
	adapter.configure(data,handler)
	expect(adapter.view_valid and adapter.available("equip"),"Valid typed view not accepted")
	var good = {
		"equip":{"instance_id":TEST_RING,"slot":"ring","grip":"worn"},
		"swap":{"instance_id":TEST_GREAT,"slot":"main_hand","grip":"two_handed","replace_instance_ids":[TEST_SWORD,TEST_SHIELD]},
		"unequip":{"instance_id":TEST_SHIELD,"slot":"shield"},
		"item_use":{"instance_id":TEST_POTION,"quantity":1,"target_id":null},
		"item_drop":{"instance_id":TEST_POTION,"quantity":2},
		"attune":{"instance_id":TEST_RING},
		"spell_prepare":{"spell_id":"magic-missile"},
		"spell_unprepare":{"spell_id":"sleep"},
		"spell_cast":{"spell_id":"sleep","source":"prepared","slot_level":1,"target_id":null},
		"skill_check":{"skill_id":"arcana"},
		"ability_check":{"ability":"int"},
		"saving_throw":{"ability":"wis"},
		"rest":{"rest_kind":"short"},
		"resource_use":{"resource_id":"fixture_resource","quantity":2},
		"level_up":{},
		"quest_interact":{"quest_id":TEST_QUEST},
		"party_add":{"member_actor_id":TEST_PARTY},
		"travel":{"destination_id":TEST_DEST},
		"chat":{"text":"  Inspect the door.  "}
	}
	for kind in good:
		expect(adapter.validate_args(kind,good[kind]),"Valid intent fixture rejected: "+kind)
	var attuned_view = data.duplicate(true)
	attuned_view["interaction"]["inventory_instances"][4]["attunement_status"]="attuned"
	expect(adapter.accept_view(attuned_view) and adapter.validate_args("unattune",{"instance_id":TEST_RING}),"Recorded attunement cannot be ended")
	expect(adapter.accept_view(data),"Same-revision fixture refresh rejected")
	expect(not adapter.validate_args("swap",{"instance_id":TEST_GREAT,"slot":"main_hand","grip":"two_handed","replace_instance_ids":[TEST_SWORD]}),"Partial two-hand swap allowed")
	expect(not adapter.validate_args("equip",{"instance_id":TEST_GREAT,"slot":"main_hand","grip":"two_handed"}),"Equip bypassed displaced items")
	expect(not adapter.validate_args("equip",{"instance_id":TEST_WRONG,"slot":"ring","grip":"worn"}),"Unowned item offered")
	expect(not adapter.validate_args("item_drop",{"instance_id":TEST_POTION,"quantity":3}),"Unowned quantity accepted")
	expect(not adapter.validate_args("unequip",{"instance_id":TEST_SWORD,"slot":"shield"}),"Unequip wrong assignment accepted")
	expect(not adapter.validate_args("spell_cast",{"spell_id":"sleep","source":"prepared","slot_level":2,"target_id":null}),"Unavailable slot choice accepted")
	expect(not adapter.validate_args("spell_prepare",{"spell_id":"unknown-spell"}),"Unoffered preparation accepted")
	expect(not adapter.validate_args("resource_use",{"resource_id":"fixture_resource","quantity":3}),"Overspent resource accepted")
	expect(not adapter.validate_args("travel",{"destination_id":TEST_WRONG}) and not adapter.validate_args("quest_interact",{"quest_id":TEST_WRONG}),"Undisclosed target accepted")
	expect(not adapter.validate_args("skill_check",{"skill_id":"arcana","dc":1}),"Arbitrary mechanical DC accepted")
	var malformed = data.duplicate(true)
	malformed["interaction"]["slot_assignments"].erase("head")
	expect(not adapter.accept_view(malformed) and not adapter.available("equip"),"Incomplete view failed open")
	expect(adapter.accept_view(data),"Valid view did not recover after invalid")
	malformed=data.duplicate(true)
	malformed["interaction"]["actor_id"]=TEST_WRONG
	expect(not adapter.accept_view(malformed) and not adapter.available("chat"),"Wrong actor view accepted")
	expect(adapter.accept_view(data),"Valid view recovery failed")
	var before = adapter.snapshot.duplicate(true)
	expect(adapter.request("swap",good["swap"]).get("ok",false),"Valid swap did not submit")
	expect(seen.size()==1 and seen[0]["args"]==good["swap"] and seen[0]["expected_revision"]==7 and seen[0]["actor_id"]==data["actor"]["id"],"Wrong typed request envelope")
	expect(adapter.snapshot==before and not adapter.available("chat") and not adapter.request("swap",good["swap"]).get("ok",false),"Optimistic state change or duplicate request")
	var pending_request = adapter.outstanding_id
	var unrelated = settled_view(data,TEST_WRONG)
	expect(adapter.accept_view(unrelated) and adapter.outstanding_id==pending_request,"Unrelated refresh unlocked request")
	var busy = settled_view(unrelated,pending_request,"busy","accepted_pending")
	expect(adapter.accept_view(busy) and adapter.outstanding_id.is_empty() and not adapter.available("chat") and adapter.available("cancel") and not adapter.available("retry"),"Pending phase guards incorrect")
	expect(not adapter.validate_args("cancel",{"turn_id":TEST_WRONG}) and adapter.validate_args("cancel",{"turn_id":TEST_TURN}),"Cancel target not guarded")
	expect(adapter.request("cancel",{"turn_id":TEST_TURN}).get("ok",false),"Cancel intention not submitted")
	var retryable = settled_view(busy,adapter.outstanding_id,"retryable","accepted_pending")
	expect(adapter.accept_view(retryable) and adapter.available("retry") and not adapter.available("chat"),"Retry phase guards incorrect")
	expect(adapter.request("retry",{"turn_id":TEST_TURN}).get("ok",false) and seen[-1]["args"]["turn_id"]==TEST_TURN,"Retry changed active turn")
	expect(not adapter.accept_view(data) and not adapter.available("retry"),"Decreasing revision failed open")
	var recovered = settled_view(retryable,adapter.outstanding_id)
	expect(adapter.accept_view(recovered) and adapter.available("chat"),"Matching settlement did not reconcile")
	var ambiguous = INTENTS.new()
	ambiguous.configure(data,func(_packet): return {})
	expect(not ambiguous.request("chat",good["chat"]).get("ok",false) and not ambiguous.outstanding_id.is_empty() and not ambiguous.available("chat"),"Unknown acknowledgment permitted duplicate delivery")
	var reconciled = settled_view(data,ambiguous.outstanding_id)
	expect(ambiguous.accept_view(reconciled) and ambiguous.available("chat"),"Unknown acknowledgment cannot be reconciled")
	var rejected = INTENTS.new()
	rejected.configure(data,func(packet): return {"ok":false,"request_id":packet["request_id"],"message":"Fixture rejected."})
	expect(not rejected.request("chat",good["chat"]).get("ok",false) and rejected.available("chat"),"Definitive rejection did not release guard")

func find_button(node: Node,caption: String) -> Button:
	if node is Button and node.text==caption:
		return node
	for child in node.get_children():
		var found = find_button(child,caption)
		if found!=null:
			return found
	return null

func close_popups(ui: Node) -> void:
	for child in ui.get_children():
		if child is Window:
			ui.remove_child(child)
			child.queue_free()

func test_bound_ui_fixture(snapshot: Dictionary,campaign: Dictionary,base: Control) -> void:
	var fixture = future_fixture(snapshot)
	var received: Array = []
	var handler = func(packet: Dictionary):
		received.append(packet.duplicate(true))
		return {"ok":true,"request_id":packet["request_id"],"message":"Fixture accepted only."}
	var ui = UI.new()
	ui.configure(fixture,campaign,func(): pass,func(): pass,func(): pass,false,"",handler)
	base.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await settle()
	expect(ui.composer.editable and not ui.send_button.disabled,"Explicit mock controller binding failed")
	expect(ui.inventory_cells.has(TEST_GREAT) and ui.inventory_cells.has(TEST_LONG) and ui.equipped(TEST_SHIELD),"Instance grid or authoritative slot missing")
	expect(ui.slot_options("main_hand").size()==4,"Grip choices not preserved")
	ui.show_slot("main_hand",TEST_GREAT)
	await settle()
	var swap = find_button(ui,"Swap")
	expect(swap!=null and not swap.disabled,"Owned two-handed swap button unavailable")
	if swap!=null and not swap.disabled:
		swap.pressed.emit()
		await settle()
		expect(received.size()==1 and received[0]["kind"]=="swap" and received[0]["args"]["replace_instance_ids"]==[TEST_SWORD,TEST_SHIELD],"Swap UI emitted wrong intent")
		expect(ui.equipped(TEST_SWORD) and not ui.equipped(TEST_GREAT) and not ui.composer.editable,"Swap changed UI before committed refresh")
		var next = settled_view(fixture,ui.intents.outstanding_id)
		next["interaction"]["slot_assignments"]["main_hand"]=TEST_GREAT
		next["interaction"]["slot_assignments"]["off_hand"]=TEST_GREAT
		next["interaction"]["slot_assignments"]["shield"]=null
		next["actor"]["combat"]["hp_current"]=5
		next["actor"]["combat"]["armor_class"]=12
		next["actor"]["coins"]["gp"]=18
		expect(ui.apply_authoritative_view(next),"Committed fixture refresh failed")
		await settle()
		expect(ui.equipped(TEST_GREAT) and not ui.equipped(TEST_SWORD) and has_text(ui,"5 / 7") and has_text(ui,"18 gp"),"HUD/equipment not refreshed from authoritative fixture")
		fixture = next
	close_popups(ui)
	await settle()
	# The following selection popups exercise their actual controls and gates.
	ui.show_spell("sleep")
	await settle()
	var cast = find_button(ui,"Cast")
	expect(cast!=null and not cast.disabled,"Offered prepared spell cast control unavailable")
	close_popups(ui)
	ui.show_check("skill_check","arcana")
	await settle()
	var check = find_button(ui,"Request check")
	expect(check!=null and not check.disabled,"Skill intention control unavailable")
	close_popups(ui)
	ui.show_resource("fixture_resource")
	await settle()
	var use = find_button(ui,"Request resource use")
	expect(use!=null and not use.disabled,"Resource intention control unavailable")
	close_popups(ui)
	ui.show_character_actions()
	await settle()
	var rest = find_button(ui,"Request short rest")
	expect(rest!=null and not rest.disabled,"Rest intention control unavailable")
	close_popups(ui)
	ui.show_quests()
	await settle()
	var pursue = find_button(ui,"Discuss / pursue selected quest")
	expect(pursue!=null and not pursue.disabled,"Disclosed quest control unavailable")
	close_popups(ui)
	await settle()
	var previous_count = received.size()
	var stale = ui.map_intention({"kind":"travel_intention","campaign_id":campaign["id"],"expected_revision":ui.intents.revision-1,"destination_id":TEST_DEST})
	expect(not stale.get("ok",false) and received.size()==previous_count,"Stale map intent reached controller")
	var original_input = "  I inspect the door.  \nThen I look inside.  "
	ui.composer.text = original_input
	ui.composer.grab_focus()
	var enter = InputEventKey.new()
	enter.pressed=true
	enter.keycode=KEY_ENTER
	root.push_input(enter,true)
	var repeat_enter = enter.duplicate() as InputEventKey
	repeat_enter.echo=true
	root.push_input(repeat_enter,true)
	await settle()
	expect(received.size()==previous_count+1 and received[-1]["kind"]=="chat" and received[-1]["args"]["text"]==original_input,"Chat altered original input")
	expect(not ui.composer.editable and ui.composer.text==original_input,"Chat draft cleared before settlement")
	var chat_id = ui.intents.outstanding_id
	if not chat_id.is_empty():
		var pending_view = settled_view(fixture,chat_id,"busy","accepted_pending")
		expect(ui.apply_authoritative_view(pending_view) and ui.composer.text==original_input and not ui.composer.editable,"Pending chat refresh cleared draft or unlocked")
		var final_view = settled_view(pending_view,chat_id)
		expect(ui.apply_authoritative_view(final_view) and ui.composer.text.is_empty() and ui.composer.editable,"Committed chat refresh did not settle draft")
	base.remove_child(ui)
	ui.queue_free()
	await settle()

func finish() -> void:
	for failure in failures: push_error(failure)
	print("Gameplay smoke failures: ",failures.size())
	quit(0 if failures.is_empty() else 1)
