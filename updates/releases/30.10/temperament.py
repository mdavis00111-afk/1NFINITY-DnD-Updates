"""Persistent NPC temperament: role class + Python-owned d6, separate from relationship."""
import hashlib
import random
import re

PROFILES = {
    'good': ('kind', 'kind', 'compassionate', 'compassionate', 'generous', 'exceptionally benevolent'),
    'friendly': ('neutral', 'polite', 'pleasant', 'friendly', 'warm', 'exceptionally welcoming'),
    'neutral': ('rude', 'unfriendly', 'reserved', 'neutral', 'pleasant', 'friendly'),
    'unfriendly': ('reserved', 'dismissive', 'unfriendly', 'rude', 'aggressive', 'very hostile'),
    'hostile': ('cold', 'threatening', 'hostile', 'aggressive', 'cruel', 'extremely hostile'),
}

def matches(text, words):
    return any(re.search(r'\b'+re.escape(word)+r'\b', text) for word in words)

def category(npc):
    role = re.sub(r'[^a-z0-9 ]+', ' ', (npc.role or '').lower()).strip()
    monster = (npc.monster or '').lower()
    # Occupation is primary; creature type/race alone never decides morality.
    if matches(role, ('bandit','bandit captain','raider','marauder','enemy','hostile','attacker','ambusher','cultist','assassin')):
        return 'hostile'
    if matches(role, ('corrupt','criminal','thief','ruffian','smuggler','thug','extortionist')):
        return 'unfriendly'
    if matches(role, ('healer','charitable priest','charitable cleric','medic','benevolent priest')):
        return 'good'
    if matches(role, ('shopkeeper','shop keeper','storekeeper','store keeper','merchant','trader','innkeeper','inn keeper','tavern keeper','tavern wench','barmaid','bar wench','bartender','barkeep','barman','waitress','waiter','vendor','publican','blacksmith','tavern server')):
        return 'friendly'
    if matches(role, ('guard','soldier','sentry','watchman','watchwoman','farmer','labourer','laborer','traveller','traveler','patron','commoner','villager','civilian','knight','priest','cleric')):
        return 'neutral'
    if monster in ('bandit','bandit captain','cultist','cult fanatic','assassin'):
        return 'hostile'
    if monster == 'thug':return 'unfriendly'
    return 'neutral'

def initialise(state,npc,*,new=False):
    if npc.temperament_roll is not None:return npc
    group=category(npc)
    # Stable campaign/identity-derived random stream: legacy saves and retries cannot reroll the same person.
    seed=hashlib.sha256(f'1NFINITY/temperament/v1\0{state.campaign_name}\0{state.player.name}\0{npc.id}'.encode()).digest()
    roll=random.Random(int.from_bytes(seed,'big')).randint(1,6)
    npc.temperament_category=group
    npc.temperament_roll=roll
    npc.temperament=PROFILES[group][roll-1]
    if new:
        # Natural friendliness is not devotion. Combat escalation remains a separate mechanic.
        npc.attitude={'good':1,'friendly':0,'neutral':0,'unfriendly':-1,'hostile':-4}[group]
    return npc

def line(npc):
    return f'temperament {npc.temperament or "not assigned"} ({npc.temperament_category or "unknown"}; d6 {npc.temperament_roll or "?"}); current attitude {npc.attitude:+d}'

GUIDANCE = ('NPC TEMPERAMENT: Python assigns and remembers natural temperament from role and a d6. '
    'Portray the recorded temperament in dialogue, mannerisms, patience and ordinary social reactions. '
    'Current attitude is the separate relationship with this player and can change through actions. '
    'Neither kindness nor warmth implies obedience, agreement, gifts, attraction, loyalty or surrender; '
    'rudeness alone does not imply combat. Occupation is a starting tendency, not alignment or morality. '
    'Hostile enemies may negotiate or retreat when circumstances warrant. Use normal rules for social checks; '
    'do not require a roll just for ordinary civility or force NPCs to like or dislike the player. '
    'For every newly introduced individual who speaks or interacts, return a structured NPC record with their actual role, not a temperament adjective. '
    'Python selects starting attitude; do not assign starting devotion or arbitrary hostility. '
    'Explicit mechanical outcomes and established relationships take priority over natural temperament.')
