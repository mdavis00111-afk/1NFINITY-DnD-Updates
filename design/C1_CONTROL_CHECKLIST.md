# C1 complete gameplay control-to-handler checklist
Scope: existing gameplay workspace and its character/quest/reference/map windows; no redesign of character creator, campaign manager or settings. Source audit at 7a6ecb3 plus final dynamic-gating correction. The production caller remains unbound. Every state-changing gameplay control below is an intention, not an implemented mechanical outcome. Codes: R = actual read/local navigation; M = existing informational manual dice; B1 = already existing scoped annotation API; I = C1 typed interface, disabled at production confirm until supported controller; X = explicit unavailable, future contract.

## Top navigation and main character HUD
| Existing control or display | C1 source handler / input | Status and required follow-up |
|---|---|---|
| Game | navigate → show_tab Inventory | R |
| Character | show_character → full_character_sheet (campaign copy), scroll, reference popups, Rest & advancement | R/I; actor projection C2, rest/level-up C3 |
| Inventory / Spells / Skills | navigate → respective right panel | R; no mutation |
| Quest Log | show_quests | R/I; B4 disclosed local fallback, C2 full public quests, quest_interact C3/C4 |
| Map | show_map → MapWindow | R/I; B1 MapView; travel below |
| Campaign | request_leave → existing campaign callback | R; unresolved request lock; C4 controller-aware exit/resume |
| Settings | request_settings → existing settings callback | R; unresolved request lock; C4 pending transport policy; no Gemini change |
| Portrait, name, race, level, class | build_left / actor read | R; C2 consistent committed actor/portrait |
| HP current/max red strip, AC, speed, initiative | stat / actor.combat | R; C2 committed refresh; C3 owns HP/AC/timing |
| Six ability cells, proficiency, passive perception | actor read | R; checks via Skills, no stat editing |
| Head / Cloak / Body / Hands / Feet | slot_card → show_slot canonical slot | R/I; current assignment + owned candidates; C2 all slots, C3 timing/compatibility |
| Neck / Ring / Accessory / Belt / Shield | slot_card → show_slot canonical slot | R/I; same |
| Central weapon / silhouette button | show_equipped_weapons → main_hand / off_hand / shield | R/I; legacy combined weapons without invented hand assignment |
| Empty and occupied slot picker | show_slot: ItemList, selection, owned quantity, details, grip, displacement/warnings | R; catalogue-level legacy browse, C2 actual instance options |
| Equip / Swap confirmation | equip / swap (atomic instance, slot, grip, all displaced IDs) | I; 03 instance/slot transaction, 02 eligibility/proficiency/action timing |
| Unequip confirmation | unequip(instance_id,slot) | I; 03 assignment, 02 timing/conflicts |
| Coins all denominations / weight and missing-weight tooltip | actor.coins / display_values.load_text | R; C2 actual state and authoritative weight; C3 transactions/encumbrance |
| Stored equipment warnings | existing display_warnings tooltip | R; do not recompute authoritative AC |

## Inventory, spells, skills, character, resources and party
| Control | Handler | Status / backend need |
|---|---|---|
| Right tabs Inventory / Spells / Skills / Features / Notes | show_tab | R |
| All Items / Equipped filter | build_inventory, equipped | R; real normalized stacks or actual instance assignments |
| Six-column item grid, item selection, quantity, equipped badge | select_item by stable instance or legacy item_id | R; instance IDs only for mutations |
| Blank display cells | disabled, no action | X decorative, never inventory |
| Selected item details / cost / properties / weight / charges / attunement | select_item / authoritative definition or legacy catalogue reference | R; 03 custom definition/instance details |
| Equip | equip_from_inventory → compatible slot selector → show_slot | R/I; exact equip/swap confirmation above |
| Use / Drop | item_quantity_popup, quantity spinner bounded by owned quantity; confirm item_use / item_drop | I; 03 ownership/charges/transfer; 02 legal effects, targets and timing; null target unselected |
| More / Choose equipment slot | show_item_more / equip_from_inventory | R/I |
| Attune / End attunement | attune / unattune only actual recorded status and instance | I; C2 state; C3 attunement eligibility/rest |
| Class DC/attack, racial stats, slots/pact remaining | build_spells, actor.spellcasting | R; C2 actual slots/known/prepared state |
| Spell list (cantrips/racial/known/spellbook/prepared/always prepared/additional offered choices) | show_spell, actual catalogue or offered selection | R/I; no invented spells |
| Prepare / Unprepare | offered preparation_options, spell_prepare / spell_unprepare | I; C2 state; C3 class/rest constraints |
| Cast source/level selector, Cast button | spell_options; spell_cast(spell_id,source,slot_level,target_id:null) | I; 02 resource/timing/target/effect/ritual/concentration, 03 state; C4 decision flow |
| Skill rows | show_check → skill_check | R/I; stored modifier only, 02 contextual challenge and RAW |
| Saving throw rows | show_check → saving_throw | R/I; 02 decides if applicable |
| Ability check rows | show_check → ability_check | R/I; no local dice/DC |
| Class/racial feature rows, background detail | reference_row / catalogue | R; feature-specific mechanics through supported resource/action handlers, not direct effects |
| Condition rows | reference_row → conditions catalogue | R; 03/02 actual condition projection/effects |
| Resource row / quantity / Request resource use | show_resource → resource_use | R/I; bounded actual max/spent; 03 resource account, 02 effect/timing |
| Rest & advancement (Features and character popup) | show_character_actions | R/I |
| Short rest / Long rest | rest(rest_kind) | I; 03 clock and resources; 02 eligibility/RAW |
| Review level-up eligibility | level_up({}) | I; 03 XP/choices; 02 eligibility/advancement |
| Notes tab | established local facts, actor identity/personality/backstory/notes | R; no direct canonical editing |
| Party card portrait/name/level/HP | actual controlled actor or optional disclosed companion read model | R; C2 members |
| Empty party slots / + Add | show_party_picker → party_add(member_actor_id) if offered | I; disabled with no candidate/controller; 03 membership, 02 consent/control; no invented companion |
| Party overflow | show_party_roster | R; display only, not mechanical cap |
| Full character sheet identity/race/class/background/alignment/subclass, ability and save/skill rows | full_character_sheet reference buttons via existing callback | R; unchanged read-only reference presentation |
| Full sheet attacks/equipment, features/traits/background, spell lists, proficiencies/languages, conditions | existing ref_button/text_ref catalogue callbacks | R; actual state refresh; no direct attack/HP/slot edit in sheet |
| Character scroll, popup close | native scroll/dialog | R; no write |

## Chat, committed events, opening and reference controls
| Control | Handler | Status / backend need |
|---|---|---|
| Scene art/banner/location | existing scenery and committed current location | R; art provisional, not world state |
| Chat log / scroll to latest | normalized committed events; dice_tool Log | R; 03 public player_action/mechanical_summary events needed; no candidate output |
| Generate Opening / existing retry | original request_opening callback | existing scoped opening flow, preserved; opening guard and pending checks |
| Turn / Retry | show_turn_controls, controller public phase/status | R/I |
| Retry active turn | retry(turn_id) | I; only retryable and exact active turn; B3 existing receipt/retry lifecycle C4 |
| Cancel / reconcile | cancel(turn_id) | I; only controller capability and active phase; no committed receipt discard |
| Composer input / Enter / Send | submit_chat → chat(text unchanged) | I; unbound/disabled production; C2/03 and C3/02 typed controller, C4 fixture binding, C5/04 semantic AI later |
| Status/error/pending text | show_status, popup_status, refresh_intent_controls | R; no optimistic outcome, invalid/ambiguous request locks |
| Save & Exit | request_leave → existing leave callback | R; committed data already saved, C4 pending reconciliation |
| Dice sides selector / quantity spinner / Roll | manual_dice.roll, local display | M; deliberately NOT a mechanical result or persistent event |
| Dice result details/tooltip, Clear | manual result popup / dice_tool Clear | M; no campaign change |
| Rules shortcut (dice bar) | show_reference_index | R |
| Six Quick References: Actions, Conditions, Rules (SRD), Combat, Spells, Equipment | show_reference_index; search and selection, catalogue describe | R; no mechanics |
| Reference dialogs search/list/close | catalogue browse / AcceptDialog | R |

## World atlas controls (existing A2 preserved)
| Control | Handler | Status / backend need |
|---|---|---|
| Refresh | refresh_map, B1 MapView revision/pagination | R; no migration |
| Fullscreen / Restore / Close | toggle_fullscreen / queue_free | R; full game viewport |
| World overview / regional selector / Open region | change_region, canvas.set_region, open_region | R; actual membership, no invented local frames |
| Find / Enter search / All known locations | search_locations / populate_locations | R; B1 visible alias/name query only |
| Location list selection / activation; canvas marker/region selection | select_location / focus_selected / select_region_info | R; actual disclosed detail, unresolved name only |
| Zoom in / out / mouse wheel | canvas.zoom | R; pointer/centre scaling |
| Drag pan / overview / Centre party / Centre selected | canvas pan, fit, focus_party, focus_selected | R; accepted positions only |
| Measure toolbar / two positioned locations | toggle_measure / measure_pick | R; straight-line miles/uncertainty, not actual path |
| Layers tab, 12 checkboxes, legend, Journal/History tabs | set_layer / tabs, illustrated legend | R; toggle art never reveals private geography |
| Travel history toolbar / list | populate_history | R; committed movement only |
| Add note toolbar / note editor / Save annotation | show_note_editor / save_annotation → B1 add_annotation | B1; existing actor-scoped noncanon write, no movement or revision change; preserve |
| Erase annotation | disabled, no B1 delete API | X; 03 future reviewed delete_annotation(campaign,actor,annotation_id) with visibility/ownership/ack guards; do not fabricate deletion |
| Travel intention | MapView same revision + visible destination → map_intention → travel | I; disabled unbound, mismatch/pending; 02 authoritative route/travel/encounters, 03 atomic receipt and position/path |
| Parchment/compass/fog/scale/red actual path | existing renderer | R; no generation/AI; no global surveyed area denominator |
| Future settlement/interior/tactical map drilldown | not available in current B1 MapView | X; 03 coordinate-frame/geometry projection, later approved renderer and 02 tactical rules |

## Required C2/C3/C4 completion checklist
- 03: same-transaction interaction view, revision/phase/request settlement, stable item definition/instance IDs, normalized owned quantities/equipment/charges/attunement, all canonical slot assignments, actual offered compatibility and public warnings, public full quest/party/location/events and actor/resource/spell projections; durable idempotency, isolation, migration/rollback, no master writes.
- 02: handler registry and exact arguments above, revalidate all offers/ownership/displaced IDs, equip timing and grip/armour proficiency consequences, attunement, drop/use/transactions, spell eligibility and resource/condition effects, checks/saves/contextual rulings, rest/time, advancement, quest/party consequences and travel; receipt authority, no double roll. Explicit unsupported handlers rather than automatic success.
- 01/lead C4: bind trusted controller only after C2/C3, implement actual pending-decision/choice/target transport and UI, publish settled public view and preserve user drafts, handle receipt resume/cancel/retry/save/exit/settings, actual mock-provider end-to-end interactions; do not activate unreviewed live composer or travel. 
- 04 C5: semantic AI work only after linkage; no Gemini changes in C1.
- 05/06: native import, actual disposable gameplay/cartography/world tests, Windows bridge/rollback and rendered 1280×720/1920×1080 acceptance. Tests authored, not run here. Static source/tree and independent replacement SVG proof executed (see TESTING.md).
