extends "res://combat_engine.gd"
## Native rules port. Every mechanical result is recorded before optional narration.
const HEAL_DICE={"Cure Wounds":8,"Healing Word":4,"Mass Cure Wounds":8,"Mass Healing Word":4,"Prayer of Healing":8}
const AREA_SPELLS=["Sleep","Acid Splash","Burning Hands","Cone of Cold","Fireball","Flame Strike","Ice Storm","Lightning Bolt","Shatter","Thunderwave","Mass Cure Wounds","Mass Healing Word","Prayer of Healing"]
const UPCAST={"Burning Hands":[1],"Cone of Cold":[1],"Fireball":[1],"Guiding Bolt":[1],"Inflict Wounds":[1],"Ice Storm":[1,0],"Lightning Bolt":[1],"Shatter":[1],"Thunderwave":[1]}
const TIMED={"Mage Armor":28800,"Comprehend Languages":3600,"Detect Magic":600}
const TEMPERAMENTS={
	"good":["kind","kind","compassionate","compassionate","generous","exceptionally benevolent"],
	"friendly":["neutral","polite","pleasant","friendly","warm","exceptionally welcoming"],
	"neutral":["rude","unfriendly","reserved","neutral","pleasant","friendly"],
	"unfriendly":["reserved","dismissive","unfriendly","rude","aggressive","very hostile"],
	"hostile":["cold","threatening","hostile","aggressive","cruel","extremely hostile"]}
const BASE_ATTITUDE={"good":1,"friendly":0,"neutral":0,"unfriendly":-1,"hostile":-4}

func role_category(n: Dictionary) -> String:
	var role=" "+str(n.get("role","")).to_lower()+" "
	for group in [["hostile",["bandit","raider","marauder","cultist","assassin","ambusher"]],["unfriendly",["criminal","smuggler","thug","extortionist"]],["good",["healer","medic","charitable priest"]],["friendly",["merchant","trader","shopkeeper","innkeeper","bartender","blacksmith","vendor","waiter","barmaid"]]]:
		for word in group[1]:
			if str(word) in role: return group[0]
	if str(n.get("monster","")).to_lower() in ["bandit","bandit captain","cultist","cult fanatic","assassin"]: return "hostile"
	if str(n.get("monster","")).to_lower()=="thug": return "unfriendly"
	return "neutral"

func record_temperament(n: Dictionary, fresh: bool):
	if int(n.get("temperament_roll",0) if n.get("temperament_roll")!=null else 0) in [1,2,3,4,5,6]: return
	var group=role_category(n)
	var seed=(str(state.get("campaign_name",""))+"|"+str(state.get("player",{}).get("name",""))+"|"+str(n.id)).sha256_text()
	var result=1+posmod(seed.left(7).hex_to_int(),6)
	n.temperament_category=group
	n.temperament_roll=result
	n.temperament=TEMPERAMENTS[group][result-1]
	if fresh: n.attitude=int(BASE_ATTITUDE[group])

func npc_defaults(data: Dictionary) -> Dictionary:
	var n=super.npc_defaults(data)
	if not n.is_empty(): record_temperament(n,true)
	return n

func context(action: String) -> Dictionary:
	var c=super.context(action)
	var relevant: Array=[]
	var tokens=action.to_lower().replace("."," ").replace(","," ").split(" ",false)
	var older: Array=state.history.slice(0,maxi(0,state.history.size()-20))
	for i in range(older.size()-1,-1,-1):
		var entry: Dictionary=older[i]
		var text=(str(entry.get("player_input",""))+" "+str(entry.get("outcome",""))).to_lower()
		var matched=false
		for word in tokens:
			if word.length()>3 and word in text: matched=true;break
		if matched:
			relevant.append(entry)
			if relevant.size()>=8:break
	c.relevant_history=relevant
	c.active_effects=state.get("effects",[])
	c.environment_objects=state.get("objects",{})
	c.world_guidance="Temperament is not loyalty or devotion. Preserve independent NPC goals, ordinary populated places, and established physical facts. No forced quests or automatic fame."
	return c

func call_ai(system: String, context: Dictionary, temperature: float=0.0) -> Dictionary:
	var extra=""
	if "Rules Lawyer" in system:
		extra="\nAdditional optional fields on resolved social/world actions: attitude_changes {existing NPC id: -1, 0 or +1} for justified relationship changes; objects [{id,name,description}] for persistent local non-mechanical scenery; companion_join existing NPC id only for an explicit successful recruitment. An NPC's native temperament is separate from attitude. Do not force an encounter or recruit anyone automatically."
	return await super.call_ai(system+extra,context,temperature)

func apply_world(plan: Dictionary, action: String, allow_position: bool) -> String:
	var previous=str(state.location)
	var result=super.apply_world(plan,action,allow_position)
	if previous!=str(state.location):
		for id in state.npcs:
			var companion=state.npcs[id]
			if companion.get("companion",false) and not companion.dead and companion.location==previous:companion.location=state.location
	var changes=plan.get("attitude_changes",{})
	if changes is Dictionary:
		for id in changes:
			if state.npcs.has(id) and state.npcs[id].location==state.location and not state.npcs[id].dead and (changes[id] is float or changes[id] is int):
				state.npcs[id].attitude=clampi(int(state.npcs[id].attitude)+clampi(int(changes[id]),-1,1),-5,5)
	# An actual hostile intervention may begin combat; temperament alone cannot force it.
	var hostile=plan.get("hostile",[])
	if hostile is Array:
		for id in hostile:
			if state.npcs.has(id) and state.npcs[id].location==state.location and not state.npcs[id].companion:
				state.npcs[id].attitude=mini(-3,int(state.npcs[id].attitude))
	var objects=plan.get("objects",[])
	if objects is Array:
		for row in objects.slice(0,8):
			if not row is Dictionary:continue
			var id=str(row.get("id",""))
			if safe_id(id) and not state.objects.has(id) and str(row.get("name",""))!="":
				state.objects[id]={"name":str(row.name).left(80),"description":str(row.get("description","")).left(500),"location":state.location}
	var join=str(plan.get("companion_join",""))
	var low=action.to_lower()
	if state.combat==null and state.npcs.has(join) and ("join" in low or "recruit" in low or "accompany" in low):
		var n: Dictionary=state.npcs[join]
		if n.location==state.location and not n.dead and int(n.attitude)>=2:
			n.companion=true;n.combat_control="assisted"
	return result

func snapshot(s: Dictionary,id: String) -> Dictionary:
	var out=super.snapshot(s,id)
	out.effects=s.get("effects",[])
	return out

func legacy_player(p: Dictionary) -> bool:
	for key in ["name","race","char_class","background","level","hp","max_hp","ac","gold","attributes","inventory","equipped","slots","cantrips","spellbook","prepared","skill_profs","save_profs","expertise","conditions","used_features","speed"]:
		if not p.has(key):return false
	if not book.classes.has(str(p.char_class)) or not book.races.has(str(p.race)) or not book.backgrounds.has(str(p.background)):return false
	if not p.attributes is Dictionary or not p.equipped is Dictionary:return false
	for a in ATTRS:
		if not p.attributes.has(a) or not (p.attributes[a] is int or p.attributes[a] is float):return false
	for key in ["inventory","slots","cantrips","spellbook","prepared","skill_profs","save_profs","expertise","conditions","used_features"]:
		if not p[key] is Array:return false
	if int(p.hp)<0 or int(p.max_hp)<1 or int(p.hp)>int(p.max_hp) or int(p.level)<1 or int(p.level)>20:return false
	for item_data in p.inventory:
		if not item_data is Dictionary or not item_data.has("name") or not item_data.has("qty") or not item_data.has("place") or not item_data.has("weight_lb"):return false
	for slot in p.slots:
		if not slot is Dictionary or not slot.has("level") or not slot.has("used") or not slot.has("total") or int(slot.used)<0 or int(slot.used)>int(slot.total):return false
	for name in p.cantrips+p.spellbook+p.prepared:
		if spell_info(str(name)).is_empty():return false
	p.dead=bool(p.get("dead",false)) or int(p.hp)==0
	if p.dead:p.hp=0
	for key in ["description","gender","portrait","fighting_style"]:
		if not p.has(key):p[key]=""
	for key in ["traits","languages","tool_profs"]:
		if not p.has(key):p[key]=[]
	if not p.has("hit_dice_spent"):p.hit_dice_spent=0
	if not p.has("xp"):p.xp=0
	return true

func import_legacy(path: String) -> Dictionary:
	if not path.to_lower().ends_with(".json") or not FileAccess.file_exists(path):return error("Choose an existing JSON save file.")
	var f=FileAccess.open(path,FileAccess.READ)
	if f==null:return error("Cannot open source save.")
	if f.get_length()>16*1024*1024:f.close();return error("Source exceeds 16 MB.")
	var raw=JSON.parse_string(f.get_as_text());f.close()
	if not raw is Dictionary:return error("Not a recognised JSON save.")
	if raw.has("player"):
		if raw.get("pending_roll")!=null or raw.get("combat")!=null or raw.get("narration_retry")!=null or not raw.get("effects",[]).is_empty():return error("Finish combat, pending rolls and active effects in the old game before importing.")
		var p=raw.player
		if not p is Dictionary or not legacy_player(p):return error("Unsupported legacy character.")
		for key in ["campaign_name","world_seconds","places","npcs","location","history","opened","turn"]:
			if not raw.has(key):return error("Legacy save missing "+key+".")
		if not raw.places is Dictionary or not raw.npcs is Dictionary or not raw.history is Array:return error("Unsupported legacy world data.")
		for id in raw.npcs:
			var n=raw.npcs[id]
			if not n is Dictionary or not safe_id(str(id)) or str(n.get("id",""))!=str(id) or n.get("hp")==null or n.get("max_hp")==null or n.get("ac")==null or not monsters.has(str(n.get("monster","")).to_lower()):return error("Legacy NPC has unresolved statistics: "+str(id))
		var converted=new_state(p,str(raw.campaign_name),str(raw.get("starting_place","City")),str(raw.get("content","standard")))
		for key in converted:
			if key in raw and key not in ["native_schema","schema_version","pending_roll","combat","effects","narration_retry"]:converted[key]=raw[key]
		converted.native_schema=1
		converted.schema_version=2
		if converted.journal.is_empty():
			for entry in converted.history:
				if entry is Dictionary:converted.journal.append({"action":str(entry.get("player_input","")),"result":str(entry.get("outcome",""))})
		if converted.journal.is_empty() and str(converted.last_narration)!="":converted.journal.append({"action":"","result":str(converted.last_narration)})
		if raw.get("last_long_rest")!=null:converted.player.last_long_rest=int(raw.last_long_rest)
		var id=unique_id(str(converted.campaign_name),root.path_join("saves"),"/state.json")
		if not write_json(campaign_path(id),converted):return error("Could not write the imported copy.")
		return {"imported":"campaign","slug":id}
	if not legacy_player(raw):return error("Unrecognised or unsupported character file.")
	var id=unique_id(str(raw.name),root.path_join("characters"),".json")
	if not write_json(character_path(id),raw):return error("Could not write imported character.")
	return {"imported":"character","slug":id}

func dispatch(op: String,q: Dictionary) -> Dictionary:
	if op=="import_legacy":return import_legacy(str(q.get("path","")))
	if op=="appearance" or op=="key":
		var backup=cfg.duplicate(true)
		if op=="appearance":
			var bg=str(q.get("background","varied"))
			if not bg in ["varied","castle","forest","lake","ruins"]:return error("Unknown background.")
			cfg.background=bg;cfg.journal_size=clampi(int(q.get("journal_size",18)),14,24)
		else:
			var key=str(q.get("key","")).strip_edges()
			var model=str(q.get("model","")).strip_edges()
			if model=="":return error("Enter a model name.")
			if key!="":cfg.key=key
			if str(cfg.get("key",""))=="":return error("Enter a Gemini key.")
			cfg.model=model
		if not write_json(root.path_join("settings.json"),cfg):cfg=backup;return error("Settings could not be saved.")
		return {"connected":str(cfg.get("key",""))!="","model":cfg.get("model","gemini-3.5-flash-lite")}
	if op=="diagnostics":
		return {"version":read_json("res://release.json",{}).get("version","unknown"),"native":true,"configured":str(cfg.get("key",""))!="","model":cfg.get("model",""),"rules":book.classes.size(),"spells":spells.size(),"monsters":monsters.size(),"save_folder":root}
	if op=="companion_action":
		if state.is_empty() or active!=str(q.get("slug","")) or state.combat==null or state.player.dead or state.pending_roll!=null:return error("No companion turn is pending.")
		var cid=str(q.get("cid",""))
		if cid!=str(state.combat.get("awaiting_companion","")) or cid=="":return error("Not this companion's turn.")
		var target=str(q.get("target",""))
		var selected=str(q.get("action",""))
		var backup=state.duplicate(true)
		var facts=""
		if selected=="Hold":facts=str(actor(cid).name)+" holds position."
		else:
			if not state.combat.zones.has(target) or actor(target).get("dead",true):return error("Choose a living enemy.")
			var hit=companion_strike(cid,target,selected)
			if hit.has("error"):return hit
			facts=str(hit.text)
		state.combat.awaiting_companion=""
		facts+="\n"+enemy_turns(true)
		return commit_action(backup,"",facts,0)
	if op=="load":
		var out=await super.dispatch(op,q)
		if not out.has("error"):
			for id in state.npcs:record_temperament(state.npcs[id],false)
			save_state()
			return snapshot(state,active)
		return out
	return await super.dispatch(op,q)

func commit_action(backup: Dictionary,action: String,facts: String,seconds: int) -> Dictionary:
	var out=finish(action,facts,seconds)
	if out.has("error"):state=backup
	return out

func rest_action(action: String,long_rest: bool) -> Dictionary:
	if state.combat!=null:return error("Cannot rest during combat.")
	var p: Dictionary=state.player
	var level=int(p.level)
	var backup=state.duplicate(true)
	if long_rest:
		var last=int(p.get("last_long_rest",-86400))
		if int(state.world_seconds)+28800-last<86400:return error("Only one long-rest benefit per 24 hours.")
		p.hp=int(p.max_hp)
		p.hit_dice_spent=maxi(0,int(p.get("hit_dice_spent",0))-maxi(1,floori(level/2.0)))
		p.used_features=[]
		for slot in p.slots:slot.used=0
		p.last_long_rest=int(state.world_seconds)+28800
		return commit_action(backup,action,"Long rest completed. HP and spell slots restored; recovered up to half your Hit Dice.",28800)
	var re=RegEx.new();re.compile("(?i)spend\\s+(\\d+)\\s+hit\\s+dic(?:e|e?s?)")
	var hit=re.search(action)
	var count=int(hit.get_string(1)) if hit!=null else 0
	if count>level-int(p.get("hit_dice_spent",0)):return error("Insufficient unspent Hit Dice.")
	var facts=["Short rest completed (1 hour)."]
	var hd=int(book.classes[p.char_class].hit_die)
	for i in range(count):
		if int(p.hp)>=int(p.max_hp):break
		var dr=dice("1d%d%+d"%[hd,stat_mod(p,"CON")])
		var before=int(p.hp)
		p.hp=mini(int(p.max_hp),before+int(dr.total))
		p.hit_dice_spent=int(p.get("hit_dice_spent",0))+1
		facts.append(str(dr.text)+"; recovered "+str(int(p.hp)-before)+" HP.")
	for feature in ["Second Wind","Action Surge"]:p.used_features.erase(feature)
	facts.append("Hit Dice remaining: "+str(level-int(p.hit_dice_spent)))
	return commit_action(backup,action,"\n".join(facts),3600)

func bonus_available() -> bool:
	return state.combat==null or int(state.combat.get("bonus_round",0))!=int(state.combat.round)

func spend_bonus():
	if state.combat!=null:state.combat.bonus_round=int(state.combat.round)

func feature_action(action: String) -> Dictionary:
	var p=state.player
	var low=action.to_lower()
	if "second wind" in low:
		if p.char_class!="Fighter" or "Second Wind" in p.used_features or not bonus_available():return error("Second Wind is not available.")
		return make_pending(action,{"native_kind":"second_wind","roll_type":"healing","skill":"Second Wind","reason":"Roll 1d10 + Fighter level for healing","bonus":int(p.level)})
	if "arcane recovery" in low:
		if p.char_class!="Wizard" or "Arcane Recovery" in p.used_features or state.combat!=null:return error("Arcane Recovery is not available.")
		# Recovery must be declared during the short rest, not at an arbitrary later time.
		return error("Use 'I take a short rest and recover level 1 slots' to declare Arcane Recovery.")
	return error("This class feature is not ported yet.")

func adjudicate(action: String,opening: bool=false) -> Dictionary:
	if opening:return await super.adjudicate(action,true)
	if state.player.dead or state.pending_roll!=null:return error("Finish the current action first.")
	if state.combat!=null and (str(state.combat.get("awaiting_companion",""))!="" or str(state.combat.initiative[int(state.combat.turn)])!="player"):return error("It is not your turn.")
	if incapacitated(state.player):
		var incapacitated_action=action.to_lower().strip_edges()
		if incapacitated_action=="i end my turn" and state.combat!=null:return commit_action(state.duplicate(true),action,enemy_turns(true),6)
		if incapacitated_action.begins_with("i wait") and state.combat==null:
			return commit_action(state.duplicate(true),action,"Time passes while you are incapacitated.",wait_seconds(action))
		return error("You are incapacitated. End your turn or wait outside combat.")
	var low=action.to_lower().strip_edges()
	if low.begins_with("i take a short rest") or low.begins_with("short rest"):
		if "recover" in low:return arcane_rest(action)
		return rest_action(action,false)
	if low.begins_with("i take a long rest") or low=="long rest":return rest_action(action,true)
	if low.begins_with("i use second wind") or low.begins_with("i use arcane recovery"):return feature_action(action)
	if low=="i end my turn" and state.combat!=null:return commit_action(state.duplicate(true),action,enemy_turns(true),6)
	if low in ["i disengage","i dash away","i move away"] and state.combat!=null:return retreat(action,low)
	if low=="i dash" and state.combat!=null:return error("Choose a direction: dash away, or approach a selected target.")
	if low.begins_with("i cast ") or low.begins_with("cast "):
		var sp=declared_spell(action)
		if sp.is_empty():return error("Unknown spell. No slot spent.")
		return await port_spell(action,sp)
	if ("punch" in low or "kick" in low) and target_from_action(action)!="":
		return local_attack("I attack "+str(actor(target_from_action(action)).get("name","target"))+" (ID "+target_from_action(action)+") with Unarmed strike.",target_from_action(action))
	return await super.adjudicate(action,false)

func arcane_rest(action: String) -> Dictionary:
	var p=state.player
	if state.combat!=null or p.char_class!="Wizard" or "Arcane Recovery" in p.used_features:return error("Arcane Recovery is not available.")
	var re=RegEx.new();re.compile("(?i)recover level ([1-5]) slots?")
	var m=re.search(action)
	if m==null:return error("Specify the slot level to recover (1–5).")
	var level=int(m.get_string(1))
	var budget=ceili(int(p.level)/2.0)
	if level>budget:return error("Slot level exceeds the Arcane Recovery budget.")
	var pool_index=-1
	for i in range(p.slots.size()):
		if int(p.slots[i].level)==level and int(p.slots[i].used)>0:pool_index=i;break
	if pool_index<0:return error("No spent slot of that level.")
	var backup=state.duplicate(true)
	var pool=p.slots[pool_index]
	var count=mini(int(pool.used),floori(float(budget)/level))
	pool.used=int(pool.used)-count
	p.used_features.append("Arcane Recovery")
	return commit_action(backup,action,"Short rest: Arcane Recovery restored %d level %d slot(s)."%[count,level],3600)

func incapacitated(n: Dictionary) -> bool:
	for condition in n.get("conditions",[]):
		if str(condition).to_lower() in ["unconscious","incapacitated","paralyzed","stunned","petrified"]:return true
	return false

func actor_range(id: String,feet: int) -> bool:
	if id=="player":return true
	var n=actor(id)
	if n.is_empty() or n.get("dead",false) or n.get("location","")!=state.location:return false
	if not can_reach("player",id,feet):return false
	if state.combat!=null and state.combat.zones.has(id):
		var dist=int({"engaged":5,"near":30,"far":60}.get(state.combat.zones[id],60))
		if dist>feet:return false
	return true

func port_spell(action: String,sp: Dictionary) -> Dictionary:
	var p=state.player
	var name=str(sp.name)
	var base_level=int(sp.level)
	var low=action.to_lower()
	var ritual="as a ritual" in low
	if ritual and (not "ritual" in str(sp.get("casting_time","")).to_lower() or state.combat!=null):return error("This ritual is unavailable now.")
	var known=p.cantrips if base_level==0 else (p.spellbook if ritual and p.char_class=="Wizard" else p.prepared)
	if not name in known:return error("Spell is not known or prepared.")
	if name=="Prayer of Healing" and state.combat!=null:return error("This spell takes ten minutes to cast.")
	var bonus_action="bonus action" in str(sp.casting_time)
	if bonus_action and not bonus_available():return error("Bonus action already spent.")
	var slot_level=base_level
	var re=RegEx.new();re.compile("(?i)(?:at|using|with) (?:a )?(?:level ([1-9])|([1-9])(?:st|nd|rd|th)[ -]level)")
	var chosen=re.search(action)
	if chosen!=null:slot_level=int(chosen.get_string(1) if chosen.get_string(1)!="" else chosen.get_string(2))
	if slot_level<base_level or (base_level==0 and slot_level!=0):return error("Invalid slot level.")
	var eff: Dictionary=sp.get("effect",{})
	var kind=str(eff.get("kind","none"))
	if name not in HEAL_DICE and name!="Sleep" and name not in TIMED and (kind not in ["attack","save","auto"] or eff.get("damage",[]).is_empty()):return error("This spell's effect is not ported. No slot spent.")
	if slot_level>base_level and name not in HEAL_DICE and name not in UPCAST and name not in ["Sleep","Magic Missile"]:return error("This spell's upcast rule is not ported. No slot spent.")
	var pool=-1
	if base_level>0 and not ritual:
		for i in range(p.slots.size()):
			if int(p.slots[i].level)==slot_level and int(p.slots[i].used)<int(p.slots[i].total):pool=i;break
		if pool<0:return error("No available spell slot of level "+str(slot_level)+".")
	var casting=str(book.classes[p.char_class].casting)
	var ability_bonus=stat_mod(p,casting)
	var target=target_from_action(action)
	if "myself" in low or "targeting self" in low:target="player"
	var rtext=str(sp.range).to_lower()
	if rtext=="self":target="player"
	var radius=5 if "touch" in rtext else 120
	var range_re=RegEx.new();range_re.compile("(\\d+)[ -](?:feet|foot)")
	var match_range=range_re.search(rtext)
	if match_range!=null:radius=int(match_range.get_string(1))
	var ids: Array=[]
	if name in AREA_SPELLS:
		var c=context(action)
		c.spell={"name":name,"range":sp.range,"description":sp.text}
		var geometry=await call_ai("Area adjudicator: return JSON {valid:bool,targets:[existing actor IDs including player when affected],reason:string}. Establish the affected creatures for the requested spell area using only the recorded scene, coarse distance zones and elevation. Do not invent precise positions, omit allies caught in the area, choose a new player action, roll dice or decide success. If the geometry is ambiguous, return valid:false and explain what the player needs to specify. For healing areas include only explicitly selected creatures. Use player as the caster ID.",c)
		if geometry.has("error"):return geometry
		if geometry.get("valid",false)!=true or not geometry.get("targets") is Array:return error(str(geometry.get("reason","Specify the affected area.")))
		for raw_id in geometry.targets:
			var id=str(raw_id)
			if id not in ids:ids.append(id)
		if ids.is_empty() or ids.size()>30:return error("No valid affected creatures.")
		if name=="Acid Splash" and ids.size()>2:return error("Acid Splash targets at most two adjacent creatures.")
		if name in HEAL_DICE and ids.size()>6:return error("This spell affects at most six creatures.")
		# Point range is distinct from effect radius; geometry adjudicator handles the latter.
		for id in ids:
			if not actor_range(id,radius+40):return error("An area target is outside known range or absent.")
	else:
		if target=="" or not actor_range(target,radius):return error("Specify a living target in range (use 'myself' for self).")
		ids=[target]
	if name=="Mage Armor":
		for id in ids:
			if actor(id).get("equipped",{}).get("ARMOR")!=null:return error("Mage Armor requires a willing unarmoured target.")
		if ids!=["player"]:return error("Mage Armor on NPCs is not ported yet.")
	if name in TIMED and ids!=["player"]:return error("This utility effect currently supports the player only.")
	var type="healing" if name in HEAL_DICE else "pool" if name=="Sleep" else "effect" if name in TIMED else "attack" if kind=="attack" else "damage"
	return make_pending(action,{"native_kind":"ported_spell","roll_type":type,"skill":name,"reason":"Resolve "+name+" • "+str(ids.size())+" affected creature(s)","spell":name,"target":str(ids[0]),"targets":ids,"dc":8+ability_bonus+prof(p),"bonus":ability_bonus,"pool":pool,"slot_level":slot_level,"ritual":ritual,"bonus_action":bonus_action})

func spell_damage_expression(sp: Dictionary,entry: Dictionary,index: int,level: int) -> String:
	var re=RegEx.new();re.compile("^(\\d+)d(\\d+)([+-]\\d+)?$")
	var m=re.search(str(entry.expr))
	if m==null:return ""
	var count=int(m.get_string(1))
	var sides=int(m.get_string(2))
	var bonus=int(m.get_string(3))
	if int(sp.level)==0:count*=1+int(state.player.level>=5)+int(state.player.level>=11)+int(state.player.level>=17)
	elif sp.name=="Magic Missile":count=level+2;bonus=count
	else:
		var ups=UPCAST.get(sp.name,[])
		if index<ups.size():count+=int(ups[index])*(level-int(sp.level))
	return "%dd%d%+d"%[count,sides,bonus]

func monster_save(id: String,ability: String) -> int:
	var n=actor(id)
	if id=="player":return save_bonus(n,ability)
	var m=monsters.get(str(n.get("monster","")).to_lower(),{})
	var re=RegEx.new();re.compile("(?i)"+ability.left(1)+ability.substr(1).to_lower()+"\\s+([+-]\\d+)")
	var found=re.search(str(m.get("saves","")))
	return int(found.get_string(1)) if found!=null else stat_mod(n,ability)

func typed_damage(id: String,amount: int,kind: String) -> int:
	var n=actor(id)
	var m=monsters.get(str(n.get("monster","")).to_lower(),{})
	# Exact unconditional entries only; do not guess conditional magic-weapon resistance.
	for k in ["immunities","resistances","vulnerabilities"]:
		for entry in str(m.get(k,"")).to_lower().split(",",false):
			if entry.strip_edges()==kind.to_lower():
				if k=="immunities":return 0
				if k=="resistances":amount=floori(amount/2.0)
				if k=="vulnerabilities":amount*=2
	return amount

func sleep_immune(id: String) -> bool:
	var n=actor(id)
	if id=="player":return "elf" in str(n.race).to_lower()
	var m=monsters.get(str(n.get("monster","")).to_lower(),{})
	return "undead" in str(m.get("size_type","")).to_lower() or "charmed" in str(m.get("condition_immunities","")).to_lower() or "unconscious" in str(m.get("condition_immunities","")).to_lower() or "fey ancestry" in str(m.get("traits",[])).to_lower()

func expire_effects(at: int):
	var keep: Array=[]
	for e in state.get("effects",[]):
		if not e is Dictionary or not e.has("expires"):keep.append(e);continue
		if int(e.expires)>at:keep.append(e);continue
		var n=actor(str(e.get("target","")))
		if not n.is_empty() and e.get("spell","")=="Sleep":n.conditions.erase("unconscious")
	state.effects=keep
	state.player.ac=armour_class(state.player)
	for e in keep:
		if e is Dictionary and e.get("spell")=="Mage Armor" and e.get("target")=="player" and state.player.equipped.get("ARMOR")==null:state.player.ac=maxi(int(state.player.ac),13+stat_mod(state.player,"DEX")+(2 if state.player.equipped.get("OFF_HAND")=="Shield" else 0))

func finish(action: String,message: String,advance: int=0) -> Dictionary:
	expire_effects(int(state.world_seconds)+maxi(0,advance))
	return super.finish(action,message,advance)

func damage_actor(id: String,amount: int) -> String:
	if amount<=0:return str(actor(id).get("name",id))+" takes no damage."
	var facts=super.damage_actor(id,amount)
	var keep: Array=[]
	for e in state.get("effects",[]):
		if not e is Dictionary:keep.append(e);continue
		if e.get("spell")=="Sleep" and e.get("target")==id:
			actor(id).conditions.erase("unconscious")
			facts+="\n"+str(actor(id).name)+" wakes from Sleep."
			continue
		if e.get("concentration",false) and e.get("caster")==id:
			var save=d20(monster_save(id,"CON"),"normal",maxi(10,floori(amount/2.0)))
			facts+="\nConcentration: "+str(save.text)
			if not save.success or actor(id).get("dead",false):facts+="\nConcentration ends.";continue
		keep.append(e)
	state.effects=keep
	return facts

func resolve_pending() -> Dictionary:
	var pending=state.pending_roll
	if not pending is Dictionary:return error("No pending roll.")
	if pending.get("native_kind") not in ["ported_spell","second_wind"]:return await super.resolve_pending()
	var backup=state.duplicate(true)
	var action=str(pending.action)
	var facts: Array=[]
	if pending.native_kind=="second_wind":
		if not bonus_available() or "Second Wind" in state.player.used_features:return error("Second Wind is no longer available.")
		var dr=dice("1d10+%d"%int(state.player.level))
		var before=int(state.player.hp)
		state.player.hp=mini(int(state.player.max_hp),before+int(dr.total))
		state.player.used_features.append("Second Wind")
		spend_bonus()
		state.pending_roll=null
		return commit_action(backup,action,str(dr.text)+"; Second Wind restores "+str(int(state.player.hp)-before)+" HP.",0 if state.combat!=null else 6)
	var sp=spell_info(str(pending.spell))
	var name=str(sp.name)
	var ids: Array=pending.targets
	var slot_level=int(pending.slot_level)
	var pool=int(pending.pool)
	if pool>=0 and (pool>=state.player.slots.size() or int(state.player.slots[pool].used)>=int(state.player.slots[pool].total)):return error("Reserved slot is no longer available.")
	if pending.bonus_action and not bonus_available():return error("Bonus action unavailable.")
	for id in ids:
		if actor(id).is_empty() or actor(id).get("dead",false):return error("A saved spell target is no longer available.")
	var hostile: Array=[]
	if name in HEAL_DICE:
		var count=int({"Mass Cure Wounds":3,"Prayer of Healing":2}.get(name,1))+slot_level-int(sp.level)
		var dr=dice("%dd%d%+d"%[count,int(HEAL_DICE[name]),int(pending.bonus)])
		facts.append(str(dr.text))
		for id in ids:
			var n=actor(id);var before=int(n.hp)
			n.hp=mini(int(n.max_hp),before+maxi(0,int(dr.total)))
			facts.append(str(n.name)+" recovers "+str(int(n.hp)-before)+" HP.")
	elif name=="Sleep":
		var dr=dice("%dd8"%(5+2*(slot_level-1)))
		var remaining=int(dr.total)
		facts.append("Sleep pool: "+str(dr.text))
		var ordered=ids.duplicate()
		ordered.sort_custom(func(a,b):return int(actor(a).hp)<int(actor(b).hp))
		for id in ordered:
			var n=actor(id)
			if sleep_immune(id):facts.append(str(n.name)+" is immune to magical sleep.");continue
			if int(n.hp)>remaining:continue
			remaining-=int(n.hp)
			if not "unconscious" in n.conditions:n.conditions.append("unconscious")
			state.effects.append({"spell":"Sleep","caster":"player","target":id,"expires":int(state.world_seconds)+60,"concentration":false})
			facts.append(str(n.name)+" falls asleep (up to one minute).")
			if id!="player":hostile.append(id)
	elif name in TIMED:
		var concentration="concentration" in str(sp.duration).to_lower()
		var keep: Array=[]
		for e in state.effects:
			if not e is Dictionary:keep.append(e);continue
			if e.get("caster")=="player" and ((concentration and e.get("concentration",false)) or e.get("spell")==name):continue
			keep.append(e)
		state.effects=keep
		state.effects.append({"spell":name,"caster":"player","target":"player","expires":int(state.world_seconds)+int(TIMED[name])+(600 if pending.ritual else 0),"concentration":concentration})
		facts.append(name+" is active: "+str(sp.duration)+".")
	else:
		var eff: Dictionary=sp.effect
		var critical=false
		var hit=true
		if eff.kind=="attack":
			var n=actor(ids[0])
			var roll_result=d20(int(pending.bonus)+prof(state.player),"normal",int(n.ac),true)
			facts.append(str(roll_result.text));hit=roll_result.success;critical=int(roll_result.natural)==20
		var components: Array=[]
		if hit:
			for i in range(eff.damage.size()):
				var expr=spell_damage_expression(sp,eff.damage[i],i,slot_level)
				var dr=dice(expr,critical)
				if dr.has("error"):state=backup;return dr
				facts.append(str(eff.damage[i].type)+": "+str(dr.text))
				components.append({"type":str(eff.damage[i].type),"total":int(dr.total)})
		for id in ids:
			if id!="player":hostile.append(id)
			if not hit:continue
			var half=false
			if eff.kind=="save":
				var sr=d20(monster_save(id,str(eff.ability)),"normal",int(pending.dc))
				facts.append(str(actor(id).name)+" save: "+str(sr.text))
				if sr.success and not eff.get("half",false):continue
				half=sr.success
			var total=0
			for component in components:total+=typed_damage(id,floori(int(component.total)/2.0) if half else int(component.total),str(component.type))
			facts.append(damage_actor(id,total))
	if pool>=0:state.player.slots[pool].used=int(state.player.slots[pool].used)+1
	expire_effects(int(state.world_seconds))
	if pending.bonus_action:spend_bonus()
	state.pending_roll=null
	var living: Array=[]
	for id in hostile:
		if not actor(id).get("dead",true):
			actor(id).attitude=-5
			if not actor(id).get("companion",false):living.append(id)
	if state.combat==null and not living.is_empty():facts.append(begin_combat(living))
	elif state.combat!=null and not pending.bonus_action:facts.append(enemy_turns(true))
	end_if_finished()
	var advance=600 if pending.ritual or name=="Prayer of Healing" else 0 if pending.bonus_action and state.combat!=null else 6
	var resolved=commit_action(backup,action,"\n".join(facts),advance)
	if resolved.has("error"):return resolved
	var narration=await narrator(action,"\n".join(facts))
	if narration!="\n".join(facts):
		state.last_narration=narration
		state.journal[-1].result="\n".join(facts)+"\n\n"+narration
		state.history[-1].outcome=state.journal[-1].result.left(2000)
		save_state()
		resolved=snapshot(state,active)
		resolved.result=state.journal[-1].result
	return resolved

func begin_combat(ids: Array) -> String:
	if state.combat!=null:return ""
	var scores={"player":rng.randi_range(1,20)+stat_mod(state.player,"DEX")}
	var zones: Dictionary={}
	for id in ids:
		var n=actor(str(id))
		if n.is_empty() or n.get("dead",false) or n.get("companion",false) or n.get("location","")!=state.location or int(n.get("attitude",0))>-3:continue
		scores[id]=rng.randi_range(1,20)+stat_mod(n,"DEX")
		zones[id]="near"
	if zones.is_empty():return ""
	var allies: Array=[]
	for id in state.npcs:
		var n=state.npcs[id]
		if n.companion and not n.dead and n.location==state.location:
			allies.append(id);scores[id]=rng.randi_range(1,20)+stat_mod(n,"DEX")
	var order=scores.keys()
	order.sort_custom(func(a,b):return int(scores[a])>int(scores[b]))
	state.combat={"round":1,"initiative":order,"initiative_scores":scores,"zones":zones,"allies":allies,"turn":0,"started":true,"awaiting_companion":"","player_dodging":false,"movement_round":0,"bonus_round":0}
	return "Initiative: "+str(scores)+"\n"+enemy_turns(false)

func monster_attack(id: String,target: String,attack: Dictionary,advantage: String="normal") -> String:
	var n=actor(id)
	var victim=actor(target)
	if n.is_empty() or victim.is_empty() or victim.get("dead",false) or incapacitated(n):return ""
	var r=d20(int(attack.to_hit),advantage,int(victim.ac),true)
	var facts=str(n.name)+" — "+str(attack.name)+": "+str(r.text)
	if r.success:
		var damage=0
		for component in attack.damage:
			var dr=dice(str(component.expr),int(r.natural)==20)
			if dr.has("total"):
				facts+="\n"+str(dr.text)
				damage+=typed_damage(target,int(dr.total),str(component.type))
		facts+="\n"+damage_actor(target,damage)
	return facts

func companion_strike(id: String,target: String,selected: String="") -> Dictionary:
	var n=actor(id)
	if n.is_empty() or n.get("dead",false) or incapacitated(n):return error("Companion cannot act.")
	var attacks=monsters.get(str(n.monster).to_lower(),{}).get("attacks",[])
	for a in attacks:
		if selected!="" and str(a.name)!=selected:continue
		# Companion-relative horizontal geometry is not yet recorded; only
		# allow nearby grounded melee or explicitly ranged attacks.
		var reach=int(a.get("reach",5)) if a.get("melee",false) else 60
		if not can_reach(id,target,reach):continue
		if state.combat.zones.get(target,"near")=="far" and a.get("melee",false):continue
		return {"text":monster_attack(id,target,a)}
	return error("No available attack in reach.")

func enemy_turns(advance_player: bool) -> String:
	if end_if_finished():return ""
	var c=state.combat
	var lines: Array=[]
	if advance_player:c.turn=int(c.turn)+1
	var guard=0
	while guard<c.initiative.size()+1 and not state.player.dead:
		guard+=1
		if end_if_finished():break
		if int(c.turn)>=c.initiative.size():c.turn=0;c.round=int(c.round)+1
		var id=str(c.initiative[int(c.turn)])
		if id=="player":c.player_dodging=false;break
		var n=actor(id)
		if n.is_empty() or n.get("dead",false):c.turn=int(c.turn)+1;continue
		if incapacitated(n):lines.append(str(n.name)+" cannot act while incapacitated.");c.turn=int(c.turn)+1;continue
		if n.get("companion",false) and id in c.get("allies",[]):
			if n.get("combat_control","assisted")=="manual":c.awaiting_companion=id;break
			for target in c.zones:
				if actor(target).get("dead",true):continue
				var result=companion_strike(id,target)
				if not result.has("error"):lines.append(result.text);break
		else:
			var m=monsters.get(str(n.monster).to_lower(),{})
			var selected: Dictionary={}
			for attack in m.get("attacks",[]):
				if attack.get("melee",false) and can_reach(id,"player",int(attack.get("reach",5))):
					var speed_re=RegEx.new();speed_re.compile("^(\\d+)")
					var speed_match=speed_re.search(str(m.get("speed","0")))
					var speed=int(speed_match.get_string(1)) if speed_match!=null else 0
					var zone=str(c.zones.get(id,"near"))
					if zone=="far" and speed<55:
						if speed>=25:c.zones[id]="near";lines.append(str(n.name)+" closes some distance.")
						continue
					if zone=="near" and speed<25:continue
					c.zones[id]="engaged";selected=attack;break
				if attack.get("ranged",false):
					var rd=attack.get("range")
					if rd is Array and not rd.is_empty() and can_reach(id,"player",int(rd[0])) and int({"engaged":5,"near":30,"far":60}.get(c.zones.get(id,"near"),60))<=int(rd[0]):selected=attack
			if selected.is_empty():lines.append(str(n.name)+" cannot make a confirmed attack from its position.")
			else:
				var adv="disadvantage" if c.player_dodging else "normal"
				lines.append(monster_attack(id,"player",selected,adv))
		c.turn=int(c.turn)+1
	end_if_finished()
	return "\n".join(lines)

func retreat(action: String,low: String) -> Dictionary:
	var c=state.combat
	var backup=state.duplicate(true)
	if int(c.get("movement_round",0))==int(c.round):return error("Movement already used this round.")
	if int(state.player.speed)*(2 if low=="i dash away" else 1)<25:return error("Insufficient movement to leave the current distance zone.")
	for condition in state.player.conditions:
		if str(condition).to_lower() in ["grappled","restrained","paralyzed","stunned","unconscious"]:return error("Your condition prevents movement.")
	var lines: Array=[]
	for id in c.zones:
		var n=actor(id)
		if n.get("dead",true):continue
		if c.zones[id]=="engaged" and low!="i disengage" and not incapacitated(n) and int(n.get("reaction_round",0))!=int(c.round):
			for a in monsters.get(str(n.monster).to_lower(),{}).get("attacks",[]):
				if a.get("melee",false) and can_reach(id,"player",int(a.get("reach",5))):
					n.reaction_round=int(c.round)
					lines.append("Opportunity attack:\n"+monster_attack(id,"player",a))
					break
		if state.player.dead:break
		c.zones[id]="far" if low=="i dash away" or c.zones[id]!="engaged" else "near"
	c.movement_round=int(c.round)
	lines.append("You move away." if not state.player.dead else "Your adventure ends.")
	if low!="i move away" or state.player.dead:lines.append(enemy_turns(true))
	return commit_action(backup,action,"\n".join(lines),6 if low!="i move away" else 0)
