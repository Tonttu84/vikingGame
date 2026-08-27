class_name CombatEngine
extends RefCounted
## The boarding-action rules engine. Headless, deterministic given a seed,
## UI-free: a controller object supplies decisions (bot, test script, or —
## later — the player through the UI).
##
## Controller contract (duck-typed):
##   choose_action(state: BattleState) -> Dictionary
##     {"op": "play", "card": CardData, "target": Character (optional),
##      "second_target": Character (optional), "slot": int (optional),
##      "direction": int (optional, Break the Line)}
##     {"op": "commit", "character": Character, "slot": int (optional)}
##     {"op": "retreat"} | {"op": "end"}
##
## Reaction saves (Drag Him Back!) need no controller: they fire
## automatically when a killing blow lands on a non-captain crew member,
## the card is in hand, and its cost is affordable.
##
## choose_action is awaited, so a controller may suspend (e.g. the UI waiting
## for a click); bots that return immediately keep working unchanged. A
## controller may also expose an optional pace(state) hook — awaited after
## each resolution step (attack, tactic, reinforcement) so a UI can animate
## the battle instead of resolving it in one frame.

enum Outcome { NONE, VICTORY, DEFEAT, RETREAT, STALEMATE }

const MAX_TURNS := 60
const MAX_ACTIONS_PER_TURN := 50

var state: BattleState
var controller
var rng := RandomNumberGenerator.new()
var outcome: Outcome = Outcome.NONE
var enemy_tactics: Array[String] = []
var _order_counter := 0
var _maneuver_shield := false


func setup(scenario: Dictionary, p_controller, seed_value: int) -> void:
	controller = p_controller
	rng.seed = seed_value
	state = BattleState.new()
	for c: Character in scenario.get("player_field", []):
		_register(c)
		_auto_field(c)
	for c: Character in scenario.get("player_reserve", []):
		_register(c)
		state.player_reserve.append(c)
	for c: Character in scenario.get("enemy_field", []):
		_register(c)
		_auto_field(c)
	for c: Character in scenario.get("enemy_reserve", []):
		_register(c)
		state.enemy_reserve.append(c)
	for c: Character in state.fielded(Character.Side.PLAYER) + state.player_reserve:
		if c.is_captain:
			state.player_captain = c
	state.enemy_captain = scenario.get("enemy_captain")
	if state.enemy_captain != null:
		state.enemy_captain.order_id = _next_order_id()
	var deck: Array[CardData] = []
	deck.assign(scenario.get("deck", []))
	state.deck = deck
	_shuffle(state.deck)
	enemy_tactics.assign(scenario.get("enemy_tactics", ["press_the_attack"]))
	state.next_tactic = _pick_tactic()
	state.maneuvers.assign(scenario.get("maneuvers", []))
	state.artifacts.assign(scenario.get("artifacts", []))
	_apply_battle_start_artifacts()


## The boarding opens every battle: one free maneuver card from its own tiny
## deck (then set aside), chosen by the controller — functionally a menu. The
## maneuver carries the opening momentum surge; no maneuvers configured (bare
## test scenarios) means no surge.
func _boarding_phase() -> void:
	if state.maneuvers.is_empty():
		return
	var choice: CardData = state.maneuvers[0]
	if controller.has_method("choose_maneuver"):
		choice = await controller.choose_maneuver(state, state.maneuvers)
		if choice == null or not state.maneuvers.has(choice):
			choice = state.maneuvers[0]
	state.boarding_maneuver = choice
	state.log_event("Boarding: %s!" % choice.display_name)
	for effect in choice.effects:
		await _apply_effect(effect, null)
		if outcome != Outcome.NONE:
			return
	# A shield wall raised during the crossing covers the first exchange too:
	# it survives turn 1's start-of-turn cleanup, unlike a card-raised wall.
	_maneuver_shield = state.shield_wall_active
	await _pace()


func _apply_battle_start_artifacts() -> void:
	for artifact in state.artifacts:
		match artifact.hook:
			ArtifactData.Hook.ALLY_DEATH_WAVE:
				if artifact.effect_type == ArtifactData.EffectType.SUPPRESS_WAVE:
					state.death_wave_suppressions += artifact.amount
			ArtifactData.Hook.BATTLE_START:
				state.log_event("%s: %s" % [artifact.display_name, artifact.description])
				match artifact.effect_type:
					ArtifactData.EffectType.GAIN_MOMENTUM:
						_gain_momentum(artifact.amount)
					ArtifactData.EffectType.ENEMY_MORALE_DAMAGE:
						for c in state.fielded(Character.Side.ENEMY):
							_deal_morale_damage(c, artifact.amount)
						_check_routs(Character.Side.ENEMY)
					ArtifactData.EffectType.ALLY_MORALE_BONUS:
						for c in state.fielded(Character.Side.PLAYER) + state.player_reserve:
							c.max_morale += artifact.amount
							c.morale += artifact.amount


func run() -> Dictionary:
	await _boarding_phase()
	while outcome == Outcome.NONE and state.turn < MAX_TURNS:
		state.turn += 1
		await _player_turn()
		_check_repulsed()
		if outcome == Outcome.NONE:
			await _enemy_turn()
		_check_repulsed()
	if outcome == Outcome.NONE:
		outcome = Outcome.STALEMATE
	return summary()


## No boarders left on their deck means the boarding failed: the survivors on
## your own ship cut the ropes. A retreat, not a defeat — the crew lives.
func _check_repulsed() -> void:
	if outcome == Outcome.NONE and state.player_formation.is_empty():
		outcome = Outcome.RETREAT
		state.log_event("The boarding is repulsed; the ropes are cut.")


func summary() -> Dictionary:
	return {
		"outcome": Outcome.keys()[outcome],
		"turns": state.turn,
		"player_dead": state.player_dead.size(),
		"player_fled": state.player_fled.size(),
		"player_survivors": state.player_formation.size() + state.player_reserve.size(),
		"enemy_dead": state.enemy_dead.size(),
		"enemy_routed": state.enemy_routed.size(),
		"momentum_left": state.momentum,
	}


# --- Turn flow ---------------------------------------------------------------

func _player_turn() -> void:
	if _maneuver_shield:
		_maneuver_shield = false
	else:
		state.shield_wall_active = false
	state.war_cry_active = false
	_gain_momentum(1)
	# A fresh hand every turn: everything not Retained is discarded, then the
	# hand refills to size. Retained cards wait in hand and eat draw room.
	for card in state.hand.duplicate():
		if not card.retained:
			state.hand.erase(card)
			state.discard.append(card)
	_draw_to_hand_size()
	var actions := 0
	while outcome == Outcome.NONE and actions < MAX_ACTIONS_PER_TURN:
		actions += 1
		var action: Dictionary = await controller.choose_action(state)
		if action.get("op", "end") == "end":
			break
		await _apply_action(action)
	if outcome == Outcome.NONE:
		await _fight_phase(Character.Side.PLAYER)
	state.focus_target = null
	for c in state.fielded(Character.Side.PLAYER) + state.player_reserve:
		c.bonus_attacks = 0


func _enemy_turn() -> void:
	await _resolve_tactic(state.next_tactic)
	await _pace()
	if outcome != Outcome.NONE:
		return
	await _fight_phase(Character.Side.ENEMY)
	if outcome != Outcome.NONE:
		return
	_reinforce()
	await _pace()
	state.surge_active = false
	state.challenge_active = false
	state.next_tactic = _pick_tactic()


# --- Player actions ----------------------------------------------------------

func _apply_action(action: Dictionary) -> void:
	match action.get("op", "end"):
		"play":
			await _play_card(action.get("card"), action.get("target"),
					action.get("second_target"), action.get("slot", -1),
					action.get("direction", 0))
		"commit":
			_commit_reserve(action.get("character"), action.get("slot", -1))
		"retreat":
			outcome = Outcome.RETREAT
			state.log_event("The crew cuts the ropes and falls back.")


func _play_card(card: CardData, target: Character, second_target: Character = null,
		slot := -1, direction := 0) -> void:
	if card == null or not state.hand.has(card) or not card.playable:
		return
	if card.cost > state.momentum:
		return
	if card.target_type != CardData.TargetType.NONE and target == null:
		return
	if not _effect_preconditions_met(card, target, second_target):
		return
	state.momentum -= card.cost
	state.hand.erase(card)
	state.discard.append(card)
	state.log_event("Played %s." % card.display_name)
	for effect in card.effects:
		await _apply_effect(effect, target, second_target, slot, direction)
		if outcome != Outcome.NONE:
			return


## Cards are refused outright (card kept, nothing paid) when they cannot do
## their job — a fizzled Reinforce or Challenge would feel like theft.
func _effect_preconditions_met(card: CardData, target: Character,
		second_target: Character = null) -> bool:
	for effect in card.effects:
		match effect.get("type"):
			CardData.EffectType.REINFORCE:
				if state.player_formation.is_full():
					return false
				if state.player_reserve.is_empty():
					return false
				if target != null and not state.player_reserve.has(target):
					return false
			CardData.EffectType.SWAP:
				if target == null or not state.player_formation.has(target):
					return false
				if second_target != null:
					if second_target == target:
						return false
					if not state.player_reserve.has(second_target) \
							and not state.player_formation.has(second_target):
						return false
				elif state.player_reserve.is_empty():
					return false
			CardData.EffectType.SHOVE:
				if target == null or state.enemy_formation.line_of(target) != Formation.FRONT:
					return false
				var col := state.enemy_formation.column_of(target)
				var left_free := col > 0 \
						and state.enemy_formation.at(Formation.FRONT, col - 1) == null
				var right_free := col < Formation.COLUMNS - 1 \
						and state.enemy_formation.at(Formation.FRONT, col + 1) == null
				if not left_free and not right_free:
					return false
			CardData.EffectType.CHALLENGE:
				if state.player_captain == null \
						or not state.player_formation.has(state.player_captain):
					return false
				if state.enemy_captain == null \
						or not state.enemy_formation.has(state.enemy_captain):
					return false
	return true


func _apply_effect(effect: Dictionary, target: Character, second_target: Character = null,
		slot := -1, direction := 0) -> void:
	var amount: int = effect.get("amount", 0)
	match effect.get("type"):
		CardData.EffectType.DAMAGE_ALL_ENEMIES:
			# Card damage is true damage: volleys and thrown cargo ignore armor.
			for c in state.fielded(Character.Side.ENEMY):
				await _deal_true_damage(c, amount)
				if outcome != Outcome.NONE:
					return
		CardData.EffectType.MORALE_DAMAGE_ALL_ENEMIES:
			for c in state.fielded(Character.Side.ENEMY):
				_deal_morale_damage(c, amount)
			_check_routs(Character.Side.ENEMY)
		CardData.EffectType.HEAL:
			target.hp = mini(target.max_hp, target.hp + amount)
		CardData.EffectType.FOCUS_FIRE:
			state.focus_target = target
		CardData.EffectType.SHIELD_WALL:
			state.shield_wall_active = true
		CardData.EffectType.PULL_TO_RESERVE:
			if state.player_formation.has(target) and not target.is_captain:
				state.player_formation.remove(target)
				state.player_reserve.append(target)
		CardData.EffectType.SHOVE:
			var dir := clampi(direction, -1, 1)
			if dir == 0 or not state.enemy_formation.slide(target, dir):
				if not state.enemy_formation.slide(target, -1):
					state.enemy_formation.slide(target, 1)
			state.log_event("%s is shoved out of his column." % target.display_name)
		CardData.EffectType.CHALLENGE:
			state.challenge_active = true
			state.log_event("%s calls %s out across the deck!" %
					[state.player_captain.display_name, state.enemy_captain.display_name])
		CardData.EffectType.BLOCK_REINFORCEMENTS:
			state.block_reinforcements = true
		CardData.EffectType.EXTRA_ATTACK:
			target.bonus_attacks += amount
		CardData.EffectType.DRAW:
			_draw(amount)
		CardData.EffectType.WAR_CRY:
			state.war_cry_active = true
		CardData.EffectType.GAIN_MOMENTUM:
			_gain_momentum(amount)
		CardData.EffectType.SEND_DEFENDERS_BELOW:
			for i in amount:
				var defenders := state.fielded(Character.Side.ENEMY)
				if defenders.size() <= 1:
					break
				var sleeper: Character = defenders[defenders.size() - 1]
				state.enemy_formation.remove(sleeper)
				state.enemy_reserve.append(sleeper)
				# Dragged from their hammocks: they return to the fight shaken.
				if not sleeper.morale_immune():
					sleeper.morale = maxi(1, sleeper.morale - 2)
				state.log_event("%s is caught below decks by the surprise." % sleeper.display_name)
		CardData.EffectType.DEFENDERS_FORM_UP:
			for i in amount:
				if state.enemy_reserve.is_empty() or state.enemy_formation.is_full():
					break
				var ready: Character = state.enemy_reserve.pop_front()
				state.enemy_formation.place_at_index(ready, state.enemy_formation.first_free_index())
				state.log_event("%s has time to form up against the slow crossing." % ready.display_name)
		CardData.EffectType.ARCHER_SUPPORT:
			state.archer_support_damage = amount
			state.log_event("Your archers hold the rail, bows drawn.")
		CardData.EffectType.PLAYER_ARMOR_BONUS:
			state.player_armor_bonus += amount
		CardData.EffectType.ENEMY_MORALE_BONUS:
			for c in state.fielded(Character.Side.ENEMY) + state.enemy_reserve:
				if not c.morale_immune():
					c.max_morale += amount
					c.morale += amount
		CardData.EffectType.REINFORCE:
			var crosser := target if target != null else state.player_reserve[0]
			state.player_reserve.erase(crosser)
			var index := slot if _slot_free(state.player_formation, slot) \
					else state.player_formation.first_free_index()
			state.player_formation.place_at_index(crosser, index)
			state.log_event("%s comes over the rail." % crosser.display_name)
		CardData.EffectType.SWAP:
			var partner := second_target
			if partner == null:
				partner = state.player_reserve[0]
			if state.player_formation.has(partner):
				state.player_formation.swap_positions(target, partner)
				state.log_event("%s and %s trade places." %
						[target.display_name, partner.display_name])
			else:
				var line := state.player_formation.line_of(target)
				var col := state.player_formation.column_of(target)
				state.player_formation.remove(target)
				state.player_reserve.append(target)
				state.player_reserve.erase(partner)
				state.player_formation.place(partner, line, col)
				state.log_event("%s falls back; %s takes his place." %
						[target.display_name, partner.display_name])


func _commit_reserve(character: Character, slot := -1) -> void:
	if character == null or not state.player_reserve.has(character):
		return
	if state.player_formation.is_full():
		return
	if state.momentum < BattleState.RESERVE_COMMIT_COST:
		return
	state.momentum -= BattleState.RESERVE_COMMIT_COST
	state.player_reserve.erase(character)
	var index := slot if _slot_free(state.player_formation, slot) \
			else state.player_formation.first_free_index()
	state.player_formation.place_at_index(character, index)
	state.log_event("%s joins the boarding party." % character.display_name)


# --- Fighting ----------------------------------------------------------------

func _fight_phase(side: Character.Side) -> void:
	if side == Character.Side.PLAYER:
		await _archer_support_volley()
		if outcome != Outcome.NONE:
			return
	var attackers := _attack_order(side)
	for attacker in attackers:
		if outcome != Outcome.NONE:
			return
		if not attacker.is_alive() or not state.formation_of(side).has(attacker):
			continue
		var swings := 1 + attacker.bonus_attacks
		attacker.bonus_attacks = 0
		for i in swings:
			if outcome != Outcome.NONE or not attacker.is_alive():
				return
			if _is_sniper(attacker):
				var mark := _pick_target(attacker)
				if mark == null:
					break
				await _snipe(attacker, mark)
				await _pace()
				continue
			if not _can_melee(attacker):
				break  # a second-liner without reach holds his place, quietly
			var target := _pick_target(attacker)
			if target == null:
				# The miss is spatial and deterministic: an empty column eats
				# the swing. Dodging is placement, never dice.
				state.log_event("%s swings at air — the column across is empty." %
						attacker.display_name)
				await _pace()
				break
			await _attack(attacker, target)
			await _pace()


## Covering Volley: the archers on your rail open every player fight phase
## with true damage to the lowest-HP fielded defender (spawn-order tiebreak).
func _archer_support_volley() -> void:
	if state.archer_support_damage <= 0:
		return
	var target := _weakest_fielded(state.enemy_formation)
	if target == null:
		return
	state.log_event("Arrows from your rail find %s." % target.display_name)
	await _deal_true_damage(target, state.archer_support_damage)
	await _pace()


## Deterministic resolution order: speed descending, spawn order as tiebreak.
## Only fielded men act — the reserve can never fight, never be hit.
func _attack_order(side: Character.Side) -> Array[Character]:
	var attackers := state.fielded(side)
	attackers.sort_custom(func(a: Character, b: Character) -> bool:
		if a.speed != b.speed:
			return a.speed > b.speed
		return a.order_id < b.order_id)
	return attackers


## Deterministic targeting, published rules (docs/lines-redesign.md):
## a challenged captain goes for the other captain; snipers pick the weakest
## fielded enemy anywhere; melee hits the nearest occupied slot in its own
## column — front first, then their second line, empty column = miss (null).
## Focus fire redirects everyone who can reach the target (same column for
## melee, anywhere for snipers). Never random.
func _pick_target(attacker: Character) -> Character:
	var own := state.formation_of(attacker.side)
	var opposing := state.opposing_formation(attacker.side)
	if state.challenge_active and attacker.is_captain and _opposing_captain_fielded(attacker.side):
		return _opposing_captain(attacker.side)
	if _is_sniper(attacker):
		if _focus_valid(attacker):
			return state.focus_target
		return _weakest_fielded(opposing)
	if not _can_melee(attacker):
		return null
	var col := own.column_of(attacker)
	if _focus_valid(attacker) and opposing.column_of(state.focus_target) == col:
		return state.focus_target
	return opposing.column_melee_target(col)


## An archer earning his keep: in the second line with a bow.
func _is_sniper(c: Character) -> bool:
	return c.weapon.kind == Weapon.Kind.BOW \
			and state.formation_of(c.side).line_of(c) == Formation.BACK


## Front-liners fight their column; spears reach over their front man; a
## challenged captain reaches the other captain from anywhere.
func _can_melee(c: Character) -> bool:
	if state.challenge_active and c.is_captain and _opposing_captain_fielded(c.side):
		return true
	var line := state.formation_of(c.side).line_of(c)
	if line == Formation.FRONT:
		return true
	return line == Formation.BACK and c.weapon.kind == Weapon.Kind.SPEAR


func _focus_valid(attacker: Character) -> bool:
	return attacker.side == Character.Side.PLAYER and state.focus_target != null \
			and state.focus_target.is_alive() and state.enemy_formation.has(state.focus_target)


func _weakest_fielded(formation: Formation) -> Character:
	var weakest: Character = null
	for c in formation.fielded():
		if c.is_alive() and (weakest == null or c.hp < weakest.hp \
				or (c.hp == weakest.hp and c.order_id < weakest.order_id)):
			weakest = c
	return weakest


func _opposing_captain(side: Character.Side) -> Character:
	return state.enemy_captain if side == Character.Side.PLAYER else state.player_captain


func _opposing_captain_fielded(side: Character.Side) -> bool:
	var cap := _opposing_captain(side)
	return cap != null and cap.is_alive() and state.opposing_formation(side).has(cap)


func _attack(attacker: Character, defender: Character) -> void:
	var dmg := _melee_damage(attacker, defender)
	defender.hp -= dmg
	state.log_event("%s hits %s for %d (%d HP left)." %
			[attacker.display_name, defender.display_name, dmg, maxi(0, defender.hp)])
	if defender.hp <= 0:
		await _handle_death(defender)


## The archer's arrow: flat LOW damage, armor and columns ignored — the one
## attack placement cannot dodge. Side-wide protections still soften it.
func _snipe(attacker: Character, defender: Character) -> void:
	var dmg := _snipe_damage(defender)
	defender.hp -= dmg
	state.log_event("%s's arrow finds %s for %d (%d HP left)." %
			[attacker.display_name, defender.display_name, dmg, maxi(0, defender.hp)])
	if defender.hp <= 0:
		await _handle_death(defender)


func _melee_damage(attacker: Character, defender: Character) -> int:
	return _soften(attacker.damage_against(defender), defender)


func _snipe_damage(defender: Character) -> int:
	return _soften(BattleState.ARCHER_SNIPE_DAMAGE, defender)


## Side-wide protections (shield wall, careful advance) soften every hit
## the player's side takes, to a minimum of 1.
func _soften(dmg: int, defender: Character) -> int:
	if defender.side != Character.Side.PLAYER:
		return dmg
	if state.shield_wall_active:
		dmg = maxi(1, dmg - 2)
	if state.player_armor_bonus > 0:
		dmg = maxi(1, dmg - state.player_armor_bonus)
	return dmg


## Card/tactic damage that bypasses armor and columns.
func _deal_true_damage(c: Character, amount: int) -> void:
	if amount <= 0 or not c.is_alive():
		return
	if c.side == Character.Side.PLAYER and state.shield_wall_active:
		state.log_event("The shield wall turns the volley away from %s." % c.display_name)
		return
	c.hp -= amount
	state.log_event("%s takes %d (%d HP left)." % [c.display_name, amount, maxi(0, c.hp)])
	if c.hp <= 0:
		await _handle_death(c)


func _deal_morale_damage(c: Character, amount: int) -> void:
	if c.morale_immune() or not c.is_alive():
		return
	c.morale -= amount


# --- Forecast ----------------------------------------------------------------

## What every fielded man stands to take in the coming fight phases, given
## current placements, active effects and the telegraphed tactic:
## {Character: {"hp": int, "morale": int}}. Deterministic and side-effect
## free, built on the same targeting and damage rules the phases resolve
## with. Single pass — each predicted death counts as one morale wave, but
## cascades, rout shocks and reaction saves are not chained: it is a
## preview of intent, not a simulation.
func forecast() -> Dictionary:
	var out := {}
	var everyone := state.fielded(Character.Side.PLAYER) + state.fielded(Character.Side.ENEMY)
	for c in everyone:
		out[c] = {"hp": 0, "morale": 0}
	# The rail archers open your fight phase.
	if state.archer_support_damage > 0:
		var mark := _weakest_fielded(state.enemy_formation)
		if mark != null:
			out[mark]["hp"] += state.archer_support_damage
	# Every fielded attacker, at his current target.
	for attacker in everyone:
		if not attacker.is_alive():
			continue
		if not _is_sniper(attacker) and not _can_melee(attacker):
			continue
		var target := _pick_target(attacker)
		if target == null or not out.has(target):
			continue
		var dmg := _snipe_damage(target) if _is_sniper(attacker) \
				else _melee_damage(attacker, target)
		out[target]["hp"] += dmg * (1 + attacker.bonus_attacks)
	# The telegraphed tactic is part of the bill.
	match state.next_tactic:
		"arrow_volley":
			if not state.shield_wall_active:
				for c in state.fielded(Character.Side.PLAYER):
					out[c]["hp"] += 1
		"fear_horn":
			for c in state.fielded(Character.Side.PLAYER):
				if not c.morale_immune():
					out[c]["morale"] += 1
	# Deaths shake the line: one wave per man these totals already kill.
	for side in [Character.Side.PLAYER, Character.Side.ENEMY]:
		var waves := 0
		for c in state.fielded(side):
			if out[c]["hp"] >= c.hp:
				waves += 1
		if side == Character.Side.PLAYER:
			waves = maxi(0, waves - state.death_wave_suppressions)
		if waves == 0:
			continue
		for c in state.fielded(side):
			if out[c]["hp"] < c.hp and not c.morale_immune():
				out[c]["morale"] += waves * BattleState.DEATH_MORALE_HIT
	return out


# --- Death, morale and routing ----------------------------------------------

func _handle_death(dead: Character) -> void:
	# Drag Him Back! fires automatically: an affordable save in hand cancels
	# the killing blow on a crew member, no prompt, no controller.
	if dead.side == Character.Side.PLAYER and not dead.is_captain \
			and state.player_formation.has(dead):
		var save := _affordable_reaction_save()
		if save != null:
			state.momentum -= save.cost
			state.hand.erase(save)
			state.discard.append(save)
			dead.hp = 1
			state.player_formation.remove(dead)
			state.player_reserve.append(dead)
			state.log_event("%s is dragged back to the ship at death's door." % dead.display_name)
			return
	if dead.is_captain and dead.side == Character.Side.PLAYER:
		outcome = Outcome.DEFEAT
		state.log_event("The captain falls. The raid is over.")
		return
	if dead == state.enemy_captain:
		outcome = Outcome.VICTORY
		state.log_event("The enemy captain falls; his crew throws down its arms.")
		return
	var side := dead.side
	state.formation_of(side).remove(dead)
	state.reserve_of(side).erase(dead)
	if side == Character.Side.PLAYER:
		state.player_dead.append(dead)
	else:
		state.enemy_dead.append(dead)
		_gain_momentum(BattleState.KILL_MOMENTUM)
		if state.war_cry_active:
			_gain_momentum(1)
	state.log_event("%s is slain." % dead.display_name)
	_morale_wave(side, BattleState.DEATH_MORALE_HIT)


## An allied death shakes every fielded character on that side; routs can
## cascade (each rout costs the remaining line another point). The Raven
## Banner (SUPPRESS_WAVE) swallows the first player-side wave(s) whole.
func _morale_wave(side: Character.Side, amount: int) -> void:
	if side == Character.Side.PLAYER and state.death_wave_suppressions > 0:
		state.death_wave_suppressions -= 1
		state.log_event("The raven banner holds the line.")
		return
	for c in state.fielded(side):
		_deal_morale_damage(c, amount)
	_check_routs(side)


func _check_routs(side: Character.Side) -> void:
	var routed := true
	while routed:
		routed = false
		for c in state.fielded(side):
			if c.morale <= 0 and not c.morale_immune():
				_rout(c)
				routed = true
				break


func _rout(c: Character) -> void:
	var side := c.side
	state.formation_of(side).remove(c)
	c.shaken = true
	if side == Character.Side.PLAYER:
		state.player_fled.append(c)
		state.log_event("%s breaks and flees back to the ship." % c.display_name)
	else:
		state.enemy_routed.append(c)
		state.log_event("%s panics and dives overboard." % c.display_name)
	for other in state.fielded(side):
		_deal_morale_damage(other, BattleState.ROUT_MORALE_HIT)


# --- Enemy tactics and reinforcements ----------------------------------------

func _pick_tactic() -> String:
	if enemy_tactics.is_empty():
		return "press_the_attack"
	return enemy_tactics[rng.randi_range(0, enemy_tactics.size() - 1)]


func _resolve_tactic(tactic: String) -> void:
	match tactic:
		"arrow_volley":
			if state.shield_wall_active:
				state.log_event("Enemy arrows rattle off the shield wall.")
				return
			state.log_event("Arrows fall on the boarding party.")
			for c in state.fielded(Character.Side.PLAYER):
				await _deal_true_damage(c, 1)
				if outcome != Outcome.NONE:
					return
		"fear_horn":
			state.log_event("A war horn moans across the deck.")
			for c in state.fielded(Character.Side.PLAYER):
				_deal_morale_damage(c, 1)
			_check_routs(Character.Side.PLAYER)
		"reinforcement_surge":
			state.surge_active = true
			state.log_event("The enemy captain roars for every hand on deck.")
		_:
			state.log_event("The enemy presses the attack.")


## Reinforcements choose their slots deterministically: front gaps left to
## right, then the second line (Formation.first_free_index).
func _reinforce() -> void:
	if state.block_reinforcements:
		state.block_reinforcements = false
		state.log_event("Enemy reinforcements are pushed back at the rail.")
		return
	var rate := BattleState.SURGE_REINFORCE_RATE if state.surge_active else BattleState.REINFORCE_RATE
	var moved := 0
	while moved < rate and not state.enemy_reserve.is_empty() \
			and not state.enemy_formation.is_full():
		var c: Character = state.enemy_reserve.pop_front()
		state.enemy_formation.place_at_index(c, state.enemy_formation.first_free_index())
		moved += 1
		state.log_event("%s comes up from below decks." % c.display_name)
	# The captain is the final reinforcement: he steps in himself only when
	# the hold was already empty when this step began (moved == 0), so there
	# is always one full turn between the last man up and the jarl himself.
	if moved == 0 and state.enemy_reserve.is_empty() \
			and state.enemy_captain != null and state.enemy_captain.is_alive() \
			and not state.enemy_formation.has(state.enemy_captain) \
			and not state.enemy_formation.is_full():
		state.enemy_formation.place_at_index(state.enemy_captain,
				state.enemy_formation.first_free_index())
		state.log_event("%s himself steps into the line!" % state.enemy_captain.display_name)


# --- Helpers -----------------------------------------------------------------

func _pace() -> void:
	if controller.has_method("pace"):
		await controller.pace(state)


func _gain_momentum(amount: int) -> void:
	state.momentum = mini(BattleState.MOMENTUM_CAP, state.momentum + amount)


func _draw_to_hand_size() -> void:
	while state.hand.size() < BattleState.HAND_SIZE:
		if not _draw(1):
			break


func _draw(amount: int) -> bool:
	var drew_any := false
	for i in amount:
		if state.deck.is_empty():
			if state.discard.is_empty():
				return drew_any
			state.deck.append_array(state.discard)
			state.discard.clear()
			_shuffle(state.deck)
		state.hand.append(state.deck.pop_back())
		drew_any = true
	return drew_any


func _affordable_reaction_save() -> CardData:
	for card in state.hand:
		if card.reaction_save and card.cost <= state.momentum:
			return card
	return null


func _shuffle(cards: Array[CardData]) -> void:
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cards[i]
		cards[i] = cards[j]
		cards[j] = tmp


func _slot_free(formation: Formation, index: int) -> bool:
	return index >= 0 and index < Formation.SLOT_COUNT and formation.slots[index] == null


func _register(c: Character) -> void:
	c.order_id = _next_order_id()


## Field a scenario character: his deploy_slot hint if it names a free slot,
## else reading order (front left to right, then the second line); overflow
## waits in reserve.
func _auto_field(c: Character) -> void:
	var formation := state.formation_of(c.side)
	if _slot_free(formation, c.deploy_slot):
		formation.place_at_index(c, c.deploy_slot)
		return
	if formation.is_full():
		state.reserve_of(c.side).append(c)
		return
	formation.place_at_index(c, formation.first_free_index())


func _next_order_id() -> int:
	_order_counter += 1
	return _order_counter
