extends "res://native_engine.gd"

# An explicit movement action, never an automatic teleport to the target.
func dispatch(op: String,q: Dictionary) -> Dictionary:
	if op!="approach": return await super.dispatch(op,q)
	if state.is_empty() or active!=str(q.get("slug","")): return error("Open a campaign first.")
	if state.player.dead or state.pending_roll!=null or state.combat==null: return error("Finish the pending action first.")
	var c: Dictionary=state.combat
	if c.initiative[int(c.turn)]!="player" or str(c.get("awaiting_companion",""))!="": return error("Wait for your turn.")
	var id: String=str(q.get("target",""))
	var n: Dictionary=actor(id)
	if not c.zones.has(id) or n.is_empty() or n.get("dead",false): return error("Choose a living enemy.")
	if c.zones[id]=="engaged": return error("Already within melee range.")
	if c.zones[id]!="near" or not can_reach("player",id,5): return error("Cannot reach this target with ordinary ground movement.")
	if int(c.get("movement_round",0))==int(c.round): return error("Movement already used this round.")
	if int(state.player.speed)<15: return error("Insufficient movement.")
	for condition in state.player.get("conditions",[]):
		if str(condition).to_lower() in ["grappled","restrained","paralyzed","stunned","unconscious"]: return error("Your condition prevents movement.")
	var backup: Dictionary=state.duplicate(true)
	c.zones[id]="engaged"
	c.movement_round=int(c.round)
	var out: Dictionary=finish("I approach "+str(n.name),"You move into melee reach of "+str(n.name)+". Your action is still available.",0)
	if out.has("error"): state=backup
	return out

func local_attack(action: String,target: String) -> Dictionary:
	if not "unarmed strike" in action.to_lower(): return super.local_attack(action,target)
	var n: Dictionary=actor(target)
	if target=="player" or n.is_empty() or n.get("dead",false) or n.location!=state.location: return error("Choose a living target present in the scene.")
	if not can_reach("player",target,5): return error("Target is outside melee reach.")
	if state.combat!=null and state.combat.zones.get(target,"near")!="engaged": return error("Approach the target first.")
	var strength: int=stat_mod(state.player,"STR")
	return make_pending(action,{"native_kind":"weapon","roll_type":"attack","skill":"Unarmed strike","reason":"Unarmed attack against "+str(n.name),"dc":int(n.ac),"advantage":"normal","target":target,"bonus":strength+prof(state.player),"damage":"fixed:"+str(maxi(0,1+strength))})

func dice(expr: String,crit: bool=false,extra: int=0) -> Dictionary:
	if expr.begins_with("fixed:"):
		var amount: int=maxi(0,int(expr.trim_prefix("fixed:")))
		return {"total":amount,"text":"Unarmed strike: %d bludgeoning damage (fixed; no damage die)"%amount}
	return super.dice(expr,crit,extra)
