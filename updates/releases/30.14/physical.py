"""Persistent vertical positioning and conservative action validation; not a tactical map."""
import re

GUIDANCE = ('PHYSICAL CONTINUITY: Preserve the player spot and recorded elevations until an actual resolved move, fall, or other physical event changes them. '
    'Record elevation_changes as actor ID to feet relative to local ground (player is "player"); use null for an established elevated position of unknown height. '
    'Record the new spot when climbing, descending, flying, falling, crossing an obstacle or taking cover. Do not move the player to make combat possible. '
    'Distance zones do not remove elevation, walls, cover or concealment. An animal on the ground cannot gore a character high in a tree. '
    'Adjudicate reach, line of sight, movement capability, unseen attackers, awareness and surprise before requesting dice. '
    'A deliberate uncertain weapon attack, including an aimed dropped object, requires a saved attack roll or appropriate check BEFORE describing a hit, miss or dodge. '
    'Provide the actual target, DC and skill. Do not grant an unaware target an invented successful dodge. '
    'After a successful roll, resolve applicable damage with dice; a failed attack cannot harm its intended target. '
    'Do not narrate an attack or physical movement that the outcome sheet does not establish.')

_HIGH = re.compile(r'\b(?:high (?:up|above|in|on)|treetop|tree top|canopy|upper branches|high branches|perched (?:in|on)|aloft|on (?:the |a )?(?:roof|rooftop)|above (?:the )?ground)\b', re.I)
_GROUND = re.compile(r'\b(?:ground(?: level)?|forest floor|at the foot|at the base|street level)\b', re.I)
_AIMED = re.compile(r'\b(?:drop|release|let go of|throw|hurl|launch|shoot|fire|stab|strike|swing|slash|thrust|jab|impale|attack)\b',re.I)
_WEAPON = re.compile(r'\b(?:spear|javelin|dagger|knife|arrow|bolt|bow|crossbow|sword|axe|rock|stone|boulder|weapon|club|staff|hammer|blade|dart|brick)\b',re.I)
_DIRECTION = re.compile(r'\b(?:at|onto|on(?:to)?|towards?|into|against|through|down(?:ward|wards)?|above|targeting)\b',re.I)


def legacy_high(state):
    if _HIGH.search(state.spot or '') and not re.search(r'\b(?:under|beneath|below) (?:the )?(?:canopy|branches|tree)\b',state.spot,re.I):return True
    if _GROUND.search(state.spot or ''):return False
    # Old saves sometimes stored the position only in the last narration.
    name=re.escape(state.player.name)
    for sentence in re.split(r'[.!?\n]',state.last_narration or ''):
        if re.search(r'\b(?:'+name+r'|you)\b',sentence,re.I) and _HIGH.search(sentence) and not re.search(r'\b(?:looks?|gazes?|stares?|watches?|peers?) (?:up|towards?)\b',sentence,re.I):return True
    return False


def height(state,cid):
    if cid in state.elevations:return state.elevations[cid]
    return None if cid=='player' and legacy_high(state) else 0


def vertical_reach(state,attacker,target,reach=5):
    a,b=height(state,attacker),height(state,target)
    if a is None or b is None:return attacker==target
    return abs(a-b)<=reach


def scene(state):
    records=dict(state.elevations)
    if 'player' not in records and legacy_high(state):records['player']=None
    return 'VERTICAL POSITIONS: '+(str(records) if records else 'No exceptional elevation recorded.')+'; null means elevated, exact height unknown. Unrecorded ground creatures start at ground level. '+GUIDANCE


def update(state,r,old_location):
    if state.location!=old_location:state.elevations={'player':0}
    if "player" not in state.elevations and legacy_high(state):state.elevations["player"]=None
    if r.spot:
        if _HIGH.search(r.spot) and ('player' not in state.elevations or state.elevations['player']==0):state.elevations['player']=None
        elif _GROUND.search(r.spot):state.elevations['player']=0
    state.elevations.update(r.elevation_changes)


def aimed(text):
    # Narrow fallback only for deliberate targeted physical weapon actions.
    return bool(_AIMED.search(text) and _WEAPON.search(text) and _DIRECTION.search(text)) and not re.match(r'^(?:what|where|how|can i see)\b',text,re.I)


def valid_roll(r):
    return r.status=='INVALID' or (r.status=='ROLL_REQUIRED' and r.roll_type in ('attack','check') and r.dc is not None and bool(r.skill.strip()))


def preserve_player(state,r,text):
    """Do not accept unrequested repositioning merely to make an encounter work."""
    if height(state,'player')==0:return
    if re.search(r'\b(?:climb|descend|jump|fall|drop down|land|fly|levitate|move|walk|run|travel|teleport|misty step|leave|return|come down|get down)\b',text,re.I):return
    if re.search(r'\b(?:fall|fell|knocked|pushed|pulled|collapse|breaks|broken)\b',r.summary,re.I) and any(h.target=='player' and h.amount<0 for h in r.hp_changes):return
    r.elevation_changes.pop('player',None)
    if r.move_to:r.move_to=''
    if r.spot and not _HIGH.search(r.spot):r.spot=''


def check_aimed(r):
    if not valid_roll(r):raise ValueError('Aimed attack requires a real attack/check, skill and DC before an outcome.')


def check_success(state,r,text,outcome):
    """Require damage adjudication when a successful aimed strike targets a known creature."""
    if r.status!='VALID' or not outcome.success:return
    candidates=[n for n in state.npcs.values() if n.hp is not None and n.hp>0 and n.location==state.location and (r.target==n.id or re.search(r'\b'+re.escape(n.name)+r'\b',text,re.I))]
    if len(candidates)!=1:return
    target=candidates[0]
    if not any(h.target==target.id and h.amount<0 for h in r.hp_changes):
        raise ValueError('Successful aimed attack against '+target.name+' requires damage adjudication; do not invent a miss or dodge.')
