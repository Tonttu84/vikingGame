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
##     {"op": "retreat"} | {"op": "end"}
##
##   choose_opening(state: BattleState) -> Dictionary  (optional, awaited)
##     THE OPENING (docs/combat-design.md, turn structure): every player turn
##     begins with one forced choice, and nothing else is playable until it is
##     made. Answer shapes:
##       {"op": "reinforce", "character": Character, "slot": int (optional)}
##         — a free crossing; an occupied or absent slot takes the first free
##           one in reading order.
##       {"op": "swap", "character": Character, "partner": Character}
##         — a free trade ("snap"); `character` is fielded, `partner` comes
##           from swap_partners(character) — his fellows on deck or the men
##           on the ship. The prow pair's law is unchanged.
##       {"op": "income"} — +1 momentum AND +1 card, on top of the turn's own
##         +1: which is exactly what the two free moves cost in tempo.
##     Ask opening_options() for what is legal now (income always is) and
##     opening_swappers() for who can take the snap. When the income is the
##     ONLY legal answer the engine takes it without asking, as any pick with
##     one option resolves itself. A controller without the hook, an unknown
##     op, or an illegal man gets the income: never a free move by accident.
##
##   choose_rider(state: BattleState, card: CardData, moves: Array[Dictionary])
##       -> Dictionary  (optional, awaited)
##     Movement riders are mandatory and their direction is fixed by the card
##     (docs/card-design-proposal.md §1): the engine computes every legal move
##     and the controller picks WHICH MAN, never whether and never which way.
##     A card that names an ally binds the rider to him, so it offers 0 or 1
##     moves and nothing is asked. Move shapes:
##       RIDER_PORT, RIDER_STARBOARD,
##       RIDER_CLOSE:        {"character": Character, "direction": int}
##                           (-1 port / left, +1 starboard / right)
##       RIDER_FORWARD,
##       RIDER_BACKWARD:     {"character": Character, "line": int}
##                           (Formation.FRONT or Formation.BACK)
##     A controller without the hook — or one answering with a move that is
##     not in the list — gets moves[0]: the first legal move in reading order
##     (front line left to right, then the second line).
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
		if c.is_prowman:
			state.player_prowman = c
	state.enemy_captain = scenario.get("enemy_captain")
	if state.enemy_captain != null:
		_register(state.enemy_captain)
	var deck: Array[CardData] = []
	deck.assign(scenario.get("deck", []))
	state.deck = deck
	_shuffle(state.deck)
	enemy_tactics.assign(scenario.get("enemy_tactics", ["press_the_attack"]))
	state.captain_command = scenario.get("captain_command", {})
	state.next_tactic = _pick_tactic_for(1)
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
		await _apply_effect(effect, null, null, -1, 0, choice)
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
	_raise_guard(Character.Side.PLAYER)
	_reset_press()
	_gain_momentum(1)
	# A fresh hand every turn: everything not Retained is discarded, then the
	# hand refills to size. Retained cards wait in hand and eat draw room.
	for card in state.hand.duplicate():
		if not card.retained:
			state.hand.erase(card)
			state.discard.append(card)
	_draw_to_hand_size()
	# The hand is dealt BEFORE the opening — you choose knowing what you hold
	# — but nothing in it may be played until the opening has been answered.
	await _opening_choice()
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
	_tick_statuses(Character.Side.PLAYER)


# --- The opening: one forced choice at the head of every player turn ---------
# Owner's ruling 2026-09-05 (docs/combat-design.md, turn structure). It
# replaces the old momentum commit: the crossing is free now, and the price
# is the tempo you did not take instead — because the third option pays a
# momentum and a card. Reinforce and Trade Places remain as the PAID second
# crossing and second trade in the same turn.

func _opening_choice() -> void:
	var options := opening_options()
	# One legal answer is no question at all: it resolves itself, exactly as
	# a board pick with a single lit option does.
	if options.size() == 1 or not controller.has_method("choose_opening"):
		_opening_income()
		return
	var answer: Dictionary = await controller.choose_opening(state)
	_apply_opening(answer if answer != null else {}, options)


## Resolve the controller's answer. Anything the rules do not allow — an op
## that is not on offer, a man who is not on the ship, a partner Swap would
## refuse — falls back to the income: the opening must never hand out a free
## move nobody was entitled to, and the income is always legal.
func _apply_opening(answer: Dictionary, options: Array[String]) -> void:
	var op: String = str(answer.get("op", "income"))
	if not options.has(op):
		op = "income"
	match op:
		"reinforce":
			var crosser: Character = answer.get("character")
			if crosser == null or not crossing_candidates().has(crosser):
				_opening_income()
				return
			state.log_event("The opening: a free crossing.")
			_cross_reserve(crosser, answer.get("slot", -1))
		"swap":
			var mover: Character = answer.get("character")
			var partner: Character = answer.get("partner")
			if mover == null or partner == null or not swap_partners(mover).has(partner):
				_opening_income()
				return
			state.log_event("The opening: a free trade.")
			_swap_men(mover, partner)
		_:
			_opening_income()


func _opening_income() -> void:
	_gain_momentum(1)
	_draw(1)
	state.log_event("The opening: the crew gathers itself (+1 momentum, +1 card).")


## What the opening may legally be answered with, in the order the table
## offers it. The income is always among them — a line that cannot move a
## single man still has an opening to take.
func opening_options() -> Array[String]:
	var out: Array[String] = []
	if not state.player_formation.is_full() and not crossing_candidates().is_empty():
		out.append("reinforce")
	if not opening_swappers().is_empty():
		out.append("swap")
	out.append("income")
	return out


## The fielded men with somewhere to trade to: whoever swap_partners() can
## still offer a partner for. A pinned man takes no snap and is nobody's.
func opening_swappers() -> Array[Character]:
	var out: Array[Character] = []
	for c in state.player_formation.fielded():
		if not swap_partners(c).is_empty():
			out.append(c)
	return out


func _enemy_turn() -> void:
	_raise_guard(Character.Side.ENEMY)
	await _resolve_tactic(state.next_tactic)
	await _pace()
	if outcome != Outcome.NONE:
		return
	await _fight_phase(Character.Side.ENEMY)
	if outcome != Outcome.NONE:
		return
	_resolve_press()
	if outcome != Outcome.NONE:
		return
	await _pace()
	_reinforce()
	await _pace()
	_tick_statuses(Character.Side.ENEMY)
	state.surge_active = false
	state.next_tactic = _pick_tactic_for(state.turn + 1)


# --- Player actions ----------------------------------------------------------

func _apply_action(action: Dictionary) -> void:
	match action.get("op", "end"):
		"play":
			await _play_card(action.get("card"), action.get("target"),
					action.get("second_target"), action.get("slot", -1),
					action.get("direction", 0))
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
		await _apply_effect(effect, target, second_target, slot, direction, card)
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
				if target == null and _default_crosser() == null:
					return false
				if target != null and (not state.player_reserve.has(target) or _pair_member(target)):
					return false
			CardData.EffectType.SWAP:
				if target == null or target.pinned > 0 \
						or not state.player_formation.has(target):
					return false
				if not _pair_swap_legal(target, second_target):
					return false
				if second_target != null:
					if second_target == target or second_target.pinned > 0:
						return false
					if not state.player_reserve.has(second_target) \
							and not state.player_formation.has(second_target):
						return false
				elif _default_swap_partner(target) == null:
					return false
			# Quitting the deck is movement too: no pull reaches a pinned man.
			CardData.EffectType.PULL_TO_RESERVE:
				if target != null and target.pinned > 0:
					return false
			CardData.EffectType.SHOVE:
				if shove_directions(target).is_empty():
					return false
			CardData.EffectType.TAUNT:
				var anchor := second_target if second_target != null \
						else _default_taunt_anchor(target)
				if anchor == null or not taunt_targets(anchor).has(target):
					return false
			CardData.EffectType.DRIVE_BACK:
				if not can_drive_back(target):
					return false
			# The rider gate (docs/card-design-proposal.md §5 Q3): the movement
			# is part of the price, so a card whose rider cannot move is refused
			# before payment rather than fizzling. It makes the penalty riders
			# honest — you cannot engineer them away by packing your grid — and
			# turns a crowded deck into a real constraint on your hand.
			CardData.EffectType.RIDER_PORT, CardData.EffectType.RIDER_STARBOARD, \
			CardData.EffectType.RIDER_FORWARD, CardData.EffectType.RIDER_BACKWARD, \
			CardData.EffectType.RIDER_CLOSE:
				if _rider_moves(effect.get("type"), card, target).is_empty():
					return false
	return true


# --- Legality queries: what the table may offer the player --------------------
# The UI never works legality out for itself. It asks here, lights up what
# comes back and submits nothing else; these are pure queries, no state moves.

## Would this play be accepted right now? The guards _play_card applies, plus
## the target sanity a click can get wrong — the wrong side, a dead man, a man
## the effect cannot reach where he stands.
func can_play(card: CardData, target: Character = null,
		second_target: Character = null) -> bool:
	if card == null or not state.hand.has(card) or not card.playable:
		return false
	if card.cost > state.momentum:
		return false
	if not _target_valid(card, target):
		return false
	return _effect_preconditions_met(card, target, second_target)


func _target_valid(card: CardData, target: Character) -> bool:
	match card.target_type:
		CardData.TargetType.NONE:
			return target == null
		CardData.TargetType.ENEMY:
			if target == null or target.side != Character.Side.ENEMY or not target.is_alive():
				return false
			return state.enemy_formation.has(target)
		CardData.TargetType.ALLY:
			if target == null or target.side != Character.Side.PLAYER or not target.is_alive():
				return false
			# Some effects only mean anything to a man in the fight itself.
			# HEAL is among them: a breather taken safe on the ship is not the
			# decision Rally asks for, and its rider would have nothing to ride
			# on — the card would silently lose half of itself.
			for effect in card.effects:
				match effect.get("type"):
					CardData.EffectType.PULL_TO_RESERVE, CardData.EffectType.EXTRA_ATTACK, \
					CardData.EffectType.SWAP, CardData.EffectType.HEAL:
						if not state.player_formation.has(target):
							return false
			return true
	return false


## Reserve men an ordinary crossing may take (the turn's opening, Reinforce),
## in queue order. The prow pair is not among them: they cross only by trading
## with each other (docs/combat-design.md, the prow pair).
func crossing_candidates() -> Array[Character]:
	var out: Array[Character] = []
	for c in state.player_reserve:
		if not _pair_member(c):
			out.append(c)
	return out


## Everyone the fielded `target` may trade places with by Swap: his fellows on
## deck in reading order, then the men waiting on the ship. The prow pair's
## law narrows a pair member's list to his counterpart alone.
func swap_partners(target: Character) -> Array[Character]:
	var out: Array[Character] = []
	if target == null or target.pinned > 0 or not state.player_formation.has(target):
		return out
	for c in state.player_formation.fielded() + state.player_reserve:
		if c != target and c.pinned == 0 and _pair_swap_legal(target, c):
			out.append(c)
	return out


## Which way Break the Line may shove this defender: port (-1) before
## starboard (+1), and only from the rank at the rail into an empty slot.
func shove_directions(target: Character) -> Array[int]:
	var out: Array[int] = []
	var f := state.enemy_formation
	if target == null or target.pinned > 0 \
			or not f.has(target) or f.line_of(target) != Formation.FRONT:
		return out
	var col := f.column_of(target)
	for dir: int in [-1, 1]:
		if Formation.in_bounds(Formation.FRONT, col + dir) \
				and f.at(Formation.FRONT, col + dir) == null:
			out.append(dir)
	return out


## Can this defender be driven off the rail? Only the rank at the rail can be:
## a man already in their second line has nowhere further back to go. He keeps
## taking his column's blows either way (Formation.column_melee_target) — the
## card disarms him, it does not hide him.
func can_drive_back(target: Character) -> bool:
	return target != null and target.pinned == 0 \
			and state.enemy_formation.has(target) \
			and state.enemy_formation.line_of(target) == Formation.FRONT


## Everyone Taunt could drag onto this man's column: every fielded defender
## except the one already standing in its front slot, who has nowhere to come
## from. The destination is your own column, so the board edge never enters
## into it — Taunt is the one movement in the set that cannot be edge-blocked.
func taunt_targets(anchor: Character) -> Array[Character]:
	var out: Array[Character] = []
	if anchor == null or not state.player_formation.has(anchor):
		return out
	var col := state.player_formation.column_of(anchor)
	for c in state.enemy_formation.fielded():
		if c != state.enemy_formation.at(Formation.FRONT, col) and c.pinned == 0:
			out.append(c)
	return out


## Who a Taunt is shouted across to when the controller names only the enemy:
## the first man on deck, in reading order, whose column that enemy is not
## already standing in front of. Null means the card cannot be played at all.
func _default_taunt_anchor(target: Character) -> Character:
	for c in state.player_formation.fielded():
		if taunt_targets(c).has(target):
			return c
	return null


## The man a waiting pair member would trade places with — his counterpart,
## and only while that counterpart is the one holding the field. Null for
## everyone else: ordinary crew have no counterpart, and the fielded half is
## not the one asking.
func pair_swap_counterpart(c: Character) -> Character:
	if c == null or not _pair_member(c) or not state.player_reserve.has(c):
		return null
	var counterpart := state.player_captain if c == state.player_prowman \
			else state.player_prowman
	if counterpart == null or not state.player_formation.has(counterpart):
		return null
	return counterpart


func _apply_effect(effect: Dictionary, target: Character, second_target: Character = null,
		slot := -1, direction := 0, card: CardData = null) -> void:
	var amount: int = effect.get("amount", 0)
	match effect.get("type"):
		CardData.EffectType.DAMAGE_ENEMY_FRONT_LINE:
			# Card damage is true damage: volleys and thrown cargo ignore armor.
			# The volley falls on the rank at the rail; their second line
			# stands behind the front men's shields.
			for col in Formation.COLUMNS:
				var front := state.enemy_formation.at(Formation.FRONT, col)
				if front == null:
					continue
				await _deal_true_damage(front, amount)
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
		CardData.EffectType.TAUNT:
			# Movement IS the effect here, so it may displace where a rider may
			# not: the man who was standing in the way is thrown into the duel
			# the taunted man just left. One column, always in bounds.
			var anchor := second_target if second_target != null \
					else _default_taunt_anchor(target)
			var col := state.player_formation.column_of(anchor)
			var standing := state.enemy_formation.at(Formation.FRONT, col)
			if standing != null:
				state.enemy_formation.swap_positions(target, standing)
			else:
				state.enemy_formation.remove(target)
				state.enemy_formation.place(target, Formation.FRONT, col)
			state.log_event("%s answers the shout and squares up against %s." %
					[target.display_name, anchor.display_name])
		CardData.EffectType.DRIVE_BACK:
			# Movement is the effect again, so it displaces: the man who was
			# behind him is promoted into the rank at the rail. Along the line
			# axis, which always has exactly two positions — no edge case.
			var col := state.enemy_formation.column_of(target)
			var behind := state.enemy_formation.at(Formation.BACK, col)
			if behind != null:
				state.enemy_formation.swap_positions(target, behind)
			else:
				state.enemy_formation.retire(target)
			state.log_event("%s is driven back out of the rank at the rail." % target.display_name)
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
				ready.beat = 0
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
			_cross_reserve(target if target != null else _default_crosser(), slot)
		CardData.EffectType.SWAP:
			_swap_men(target, second_target if second_target != null \
					else _default_swap_partner(target))
		CardData.EffectType.RIDER_PORT, CardData.EffectType.RIDER_STARBOARD, \
		CardData.EffectType.RIDER_FORWARD, CardData.EffectType.RIDER_BACKWARD, \
		CardData.EffectType.RIDER_CLOSE:
			await _resolve_rider(effect.get("type"), target, card)


# --- Movement riders ---------------------------------------------------------

## The mandatory rider (docs/card-design-proposal.md §1): the DIRECTION is the
## card's, fixed; the engine lists every man who can take that step and the
## controller picks WHICH — never whether, and never which way. Riders move men
## BETWEEN SLOTS only, so they never cross the rail and the prow pair's law
## needs no checking here. An empty list cannot normally reach this: the card
## is refused before payment when its rider has nowhere to go.
func _resolve_rider(rider: CardData.EffectType, target: Character, card: CardData) -> void:
	var moves := _rider_moves(rider, card, target)
	if moves.is_empty():
		return
	var move: Dictionary = moves[0]
	if controller.has_method("choose_rider"):
		var answer = await controller.choose_rider(state, card, moves)
		if answer is Dictionary and _rider_move_offered(moves, answer):
			move = answer
	_apply_rider_move(rider, move)


## Every legal move for this rider, in reading order (front line left to right,
## then the second line). moves[0] is what a controller gets when it cannot or
## will not choose.
func _rider_moves(rider: CardData.EffectType, card: CardData,
		target: Character) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	for mover in _rider_movers(card, target):
		var move := _rider_move_for(rider, mover)
		if not move.is_empty():
			moves.append(move)
	return moves


## Who the rider may move. A card that already names an ally moves THAT man and
## nobody else — 0 or 1 legal moves, so the controller is never asked. Any
## other card offers every man on deck, and the pick is which of them steps.
func _rider_movers(card: CardData, target: Character) -> Array[Character]:
	var formation := state.player_formation
	if card != null and card.target_type == CardData.TargetType.ALLY:
		if target == null or not formation.has(target):
			return [] as Array[Character]
		return [target] as Array[Character]
	return formation.fielded()


## This man's one move under this rider, or {} when the step is off the board,
## blocked by a pin, or (Close) toward nothing. Riders SWAP BY DEFAULT
## (owner's playtest ruling, 2026-09-04): a step into an occupied slot
## trades the two men, so only the board's edge and a pin — on either man,
## a trade moves both — refuse a rider now.
func _rider_move_for(rider: CardData.EffectType, mover: Character) -> Dictionary:
	var formation := state.player_formation
	var line := formation.line_of(mover)
	var col := formation.column_of(mover)
	if line == -1 or mover.pinned > 0:
		return {}
	match rider:
		CardData.EffectType.RIDER_PORT:
			return _rider_slide_move(mover, line, col, -1)
		CardData.EffectType.RIDER_STARBOARD:
			return _rider_slide_move(mover, line, col, 1)
		CardData.EffectType.RIDER_CLOSE:
			# The closing rule's direction — but where the automatic step
			# refuses an occupied slot, the card trades through it.
			var manned := _nearest_manned_column(mover)
			if manned == -1:
				return {}
			return _rider_slide_move(mover, line, col, -1 if manned < col else 1)
		CardData.EffectType.RIDER_FORWARD:
			if line != Formation.BACK or _pin_blocks(formation.at(Formation.FRONT, col)):
				return {}
			return {"character": mover, "line": Formation.FRONT}
		CardData.EffectType.RIDER_BACKWARD:
			if line != Formation.FRONT or _pin_blocks(formation.at(Formation.BACK, col)):
				return {}
			return {"character": mover, "line": Formation.BACK}
	return {}


func _rider_slide_move(mover: Character, line: int, col: int, dir: int) -> Dictionary:
	if not Formation.in_bounds(line, col + dir) \
			or _pin_blocks(state.player_formation.at(line, col + dir)):
		return {}
	return {"character": mover, "direction": dir}


## An empty slot never blocks; an occupied one only blocks when its holder
## is pinned — the trade would have to move him.
static func _pin_blocks(occupant: Character) -> bool:
	return occupant != null and occupant.pinned > 0


## Is the controller's answer one of the moves offered? Compared field by
## field: the same man and the same destination is the same move.
func _rider_move_offered(moves: Array[Dictionary], answer: Dictionary) -> bool:
	for move in moves:
		var same := true
		for key in move:
			if answer.get(key) != move[key]:
				same = false
				break
		if same:
			return true
	return false


func _apply_rider_move(rider: CardData.EffectType, move: Dictionary) -> void:
	var formation := state.player_formation
	var mover: Character = move["character"]
	var line: int = move["line"] if move.has("line") else formation.line_of(mover)
	var step: int = move["direction"] if move.has("direction") else 0
	var col := formation.column_of(mover) + step
	var occupant := formation.at(line, col)
	if occupant != null:
		if formation.swap_positions(mover, occupant):
			state.log_event("%s and %s trade places." %
					[mover.display_name, occupant.display_name])
		return
	if move.has("direction"):
		if not formation.slide(mover, move["direction"]):
			return
		if rider == CardData.EffectType.RIDER_CLOSE:
			state.log_event("%s presses toward the fighting." % mover.display_name)
		else:
			state.log_event("%s sidesteps to %s." %
					[mover.display_name, "port" if move["direction"] < 0 else "starboard"])
	elif line == Formation.FRONT:
		if formation.advance(mover):
			state.log_event("%s steps up into the front line." % mover.display_name)
	elif formation.retire(mover):
		state.log_event("%s falls back into the second line." % mover.display_name)


## The prow pair is active whenever the roster declares a prowman: then the
## captain and the prowman move only by trading places with each other (the
## Swap card, or the turn's free opening trade) or by the forced crossing in
## _pair_exit — never by Reinforce, the opening's free crossing, or a swap
## with ordinary crew.
func _pair_member(c: Character) -> bool:
	return state.player_prowman != null \
			and (c == state.player_captain or c == state.player_prowman)


## First reserve man an ordinary crossing may take — pair members are not it.
func _default_crosser() -> Character:
	var candidates := crossing_candidates()
	return candidates[0] if not candidates.is_empty() else null


## Who a Swap trades with when the controller names only the target. A pair
## member gets his counterpart and nobody else; ordinary crew take the first
## man off the ship, since the card grew out of field↔reserve rotation — but
## an empty ship falls back to a fellow on deck rather than refusing a trade
## the rules allow. Null means there is genuinely no one, and the card is
## refused before it is paid for.
func _default_swap_partner(target: Character) -> Character:
	if _pair_member(target):
		return state.player_captain if target == state.player_prowman \
				else state.player_prowman
	var crosser := _default_crosser()
	if crosser != null:
		return crosser
	for c in state.player_formation.fielded():
		if c != target and c.pinned == 0 and _pair_swap_legal(target, c):
			return c
	return null


## Swap legality around the pair: a pair member trades only with his
## counterpart, who must be alive and waiting in reserve; ordinary crew
## never trade with a pair member.
func _pair_swap_legal(target: Character, second_target: Character) -> bool:
	if state.player_prowman == null:
		return true
	if _pair_member(target):
		var counterpart := state.player_captain if target == state.player_prowman \
				else state.player_prowman
		if counterpart == null or not counterpart.is_alive() \
				or not state.player_reserve.has(counterpart):
			return false
		return second_target == null or second_target == counterpart
	return second_target == null or not _pair_member(second_target)


## The rail crossing itself, shared by the turn's opening and the Reinforce
## card: a man off the ship takes the slot he was sent to, or — when that one
## is taken or none was named — the first free slot in reading order. A man
## fielded mid-battle opens his pattern from the top.
func _cross_reserve(crosser: Character, slot := -1) -> void:
	state.player_reserve.erase(crosser)
	var index := slot if _slot_free(state.player_formation, slot) \
			else state.player_formation.first_free_index()
	state.player_formation.place_at_index(crosser, index)
	crosser.beat = 0
	state.log_event("%s comes over the rail." % crosser.display_name)


## Two of your men change places, shared by the turn's opening and the Trade
## Places card: on deck they exchange slots, across the rail the fielded man
## goes back aboard and the other takes his exact slot.
func _swap_men(mover: Character, partner: Character) -> void:
	if state.player_formation.has(partner):
		state.player_formation.swap_positions(mover, partner)
		state.log_event("%s and %s trade places." %
				[mover.display_name, partner.display_name])
		return
	var line := state.player_formation.line_of(mover)
	var col := state.player_formation.column_of(mover)
	state.player_formation.remove(mover)
	state.player_reserve.append(mover)
	state.player_reserve.erase(partner)
	state.player_formation.place(partner, line, col)
	partner.beat = 0
	state.log_event("%s falls back; %s takes his place." %
			[mover.display_name, partner.display_name])


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
		await _resolve_beat(attacker)
		if outcome != Outcome.NONE:
			return
		# The rhythm marches — landed, blocked, wasted or walked alike.
		attacker.advance_beat()


## One man's fight-phase action, by his current beat (docs/block-and-patterns.md).
## The sniper beats only mean anything in the second line with the bow — an
## archer standing at the rail is just a fighter, whatever his rhythm says.
func _resolve_beat(attacker: Character) -> void:
	match attacker.current_beat():
		"guard":
			_guard_beat(attacker)
			await _pace()
			return
		"aim":
			if _is_sniper(attacker):
				_aim_beat(attacker)
				await _pace()
				return
		"shoot":
			if _is_sniper(attacker):
				await _double_shot(attacker)
				await _pace()
				return
	await _melee_beat(attacker)


func _melee_beat(attacker: Character) -> void:
	var swings := 1 + attacker.bonus_attacks
	attacker.bonus_attacks = 0
	for i in swings:
		if outcome != Outcome.NONE or not attacker.is_alive():
			return
		if not _can_melee(attacker):
			return  # a second-liner without reach holds his place, quietly
		var target := _pick_target(attacker)
		if target == null:
			# The miss is spatial and deterministic: an empty column eats
			# the swing. Dodging is placement, never dice — but it buys a
			# turn, not the fight, so he closes if he has anywhere to go —
			# and the man he closes toward is PINNED where he stands
			# (docs/block-and-patterns.md): dodging has a rising price.
			var step := _close_direction(attacker)
			if step != 0 and state.formation_of(attacker.side).slide(attacker, step):
				state.log_event("%s presses toward the fighting." %
						attacker.display_name)
				var dodger := state.opposing_formation(attacker.side) \
						.column_melee_target(_nearest_manned_column(attacker))
				if dodger != null:
					_pin_down(dodger)
			else:
				state.log_event("%s swings at air — the column across is empty." %
						attacker.display_name)
			await _pace()
			return
		await _attack(attacker, target)
		await _pace()


## The guard beat: no swing — he plants the shield and raises his armor in
## block AGAIN, on top of whatever stands. Only the shieldman's planted
## shield is a wall: his line-neighbors gain block with him.
func _guard_beat(guard_man: Character) -> void:
	guard_man.block += guard_man.armor
	state.log_event("%s plants his shield (%d block)." %
			[guard_man.display_name, guard_man.block])
	if not guard_man.is_shieldman:
		return
	for neighbor in state.formation_of(guard_man.side).line_neighbors(guard_man):
		neighbor.block += BattleState.SHIELD_AURA_BLOCK
		state.log_event("The wall covers %s (%d block)." %
				[neighbor.display_name, neighbor.block])


## The aim beat: the mark locks — the weakest fielded opponent, or the
## focus-fire target while one stands — and nothing is loosed. One full
## turn of warning, and the mark is public.
func _aim_beat(archer: Character) -> void:
	var mark := state.focus_target if _focus_valid(archer) \
			else _weakest_fielded(state.opposing_formation(archer.side))
	if mark == null:
		state.archer_marks.erase(archer)
		return
	state.archer_marks[archer] = mark
	state.log_event("%s marks %s — the next arrows are his." %
			[archer.display_name, mark.display_name])


## Covering Volley: the archers still on your ship open every player fight
## phase with one arrow each — true damage to the lowest-HP fielded defender
## (spawn-order tiebreak), re-aiming between arrows. Field your archer and
## the rail loses her arrow; zero ship archers means a silent rail.
func _archer_support_volley() -> void:
	if state.archer_support_damage <= 0:
		return
	for i in _ship_archers():
		if outcome != Outcome.NONE:
			return
		var target := _weakest_fielded(state.enemy_formation)
		if target == null:
			return
		state.log_event("Arrows from your rail find %s." % target.display_name)
		await _deal_true_damage(target, state.archer_support_damage)
		await _pace()


func _ship_archers() -> int:
	var count := 0
	for c in state.player_reserve:
		if c.weapon.kind == Weapon.Kind.BOW:
			count += 1
	return count


## Deterministic resolution order: axes first (their block-chewing must land
## while there is block to chew), then everyone else; within each group speed
## descending, spawn order as tiebreak. Only fielded men act — the reserve
## can never fight, never be hit.
func _attack_order(side: Character.Side) -> Array[Character]:
	var attackers := state.fielded(side)
	attackers.sort_custom(func(a: Character, b: Character) -> bool:
		var a_axe := a.weapon.kind == Weapon.Kind.AXE
		var b_axe := b.weapon.kind == Weapon.Kind.AXE
		if a_axe != b_axe:
			return a_axe
		if a.speed != b.speed:
			return a.speed > b.speed
		return a.order_id < b.order_id)
	return attackers


## Deterministic melee targeting, published rules (docs/lines-redesign.md):
## the nearest occupied slot in the attacker's own column — front first, then
## their second line, empty column = miss (null). Focus fire redirects a man
## whose column holds the target. Never random. There is no targeting
## override left in the engine: a duel is arranged by moving men (Taunt),
## not by suspending the column rule; the bow's targeting lives in its aim
## beat, not here.
func _pick_target(attacker: Character) -> Character:
	var own := state.formation_of(attacker.side)
	var opposing := state.opposing_formation(attacker.side)
	if not _can_melee(attacker):
		return null
	var col := own.column_of(attacker)
	if _focus_valid(attacker) and opposing.column_of(state.focus_target) == col:
		return state.focus_target
	return opposing.column_melee_target(col)


## Which way a man whose column is empty steps instead of flailing at air.
## He forfeits the swing either way: dodging still costs the attacker his
## turn, so placement is still defence — but the fight now converges, and
## two survivors in different columns can no longer stand and stare until
## the turn limit. Deterministic, as every miss here is: the nearest column
## with someone to hit in it, port on a tie. Zero when his own line
## walls him in, or there is nobody left to close on.
func _close_direction(attacker: Character) -> int:
	var own := state.formation_of(attacker.side)
	var col := own.column_of(attacker)
	var manned := _nearest_manned_column(attacker)
	if col == -1 or manned == -1 or attacker.pinned > 0:
		return 0
	var step := -1 if manned < col else 1
	var line := own.line_of(attacker)
	if not Formation.in_bounds(line, col + step) or own.at(line, col + step) != null:
		return 0
	return step


## The column the closing rule walks a man toward: the nearest opposing
## column with someone to hit in it, port on a tie; -1 for his own
## column or an empty opposing board.
func _nearest_manned_column(attacker: Character) -> int:
	var col := state.formation_of(attacker.side).column_of(attacker)
	var opposing := state.opposing_formation(attacker.side)
	if col == -1:
		return -1
	var manned := -1
	var nearest := Formation.COLUMNS
	for c in Formation.COLUMNS:
		if opposing.column_melee_target(c) == null:
			continue
		var distance := absi(c - col)
		if distance == 0 or distance >= nearest:
			continue
		nearest = distance
		manned = c
	return manned


## The closing rule's teeth (docs/block-and-patterns.md): each pin lands
## pin_count MORE stacks than nothing — 1, then 2, then 3 — and pin_count
## never decays in-battle, so every further dodge costs more than the last.
func _pin_down(dodger: Character) -> void:
	dodger.pin_count += 1
	dodger.pinned += dodger.pin_count
	state.log_event("%s is pinned where he stands (%d)." %
			[dodger.display_name, dodger.pinned])


## The relative front line (docs/block-and-patterns.md addendum): a
## second-liner with nobody in the front slot of his own column counts as
## standing in the front line. The column rule always let the blows find
## him; now his find them back — and the bow needs cover to be a bow.
## Auras and the forced movements read REAL positions, never relative ones.
func _covered(c: Character) -> bool:
	var formation := state.formation_of(c.side)
	return formation.line_of(c) == Formation.BACK \
			and formation.at(Formation.FRONT, formation.column_of(c)) != null


## An archer earning his keep: in the second line with a bow, AND a man in
## front of him — uncovered, he counts as front and fights hand to hand.
func _is_sniper(c: Character) -> bool:
	return c.weapon.kind == Weapon.Kind.BOW and _covered(c)


## Front-liners — actual or relative — fight their column; a covered spear
## still reaches over his front man.
func _can_melee(c: Character) -> bool:
	var line := state.formation_of(c.side).line_of(c)
	if line == Formation.FRONT:
		return true
	if line != Formation.BACK:
		return false
	return not _covered(c) or c.weapon.kind == Weapon.Kind.SPEAR


func _focus_valid(attacker: Character) -> bool:
	return attacker.side == Character.Side.PLAYER and state.focus_target != null \
			and state.focus_target.is_alive() and state.enemy_formation.has(state.focus_target)


## Forecast-side re-aim: the weakest fielded defender by the hp he would
## have left after the damage already predicted, skipping men the tally
## already kills (resolution removes them before the next arrow looses).
func _forecast_weakest(predicted: Dictionary) -> Character:
	var weakest: Character = null
	var weakest_left := 0
	for c in state.enemy_formation.fielded():
		var left: int = c.hp - predicted[c]["hp"]
		if left <= 0:
			continue
		if weakest == null or left < weakest_left \
				or (left == weakest_left and c.order_id < weakest.order_id):
			weakest = c
			weakest_left = left
	return weakest


func _weakest_fielded(formation: Formation) -> Character:
	var weakest: Character = null
	for c in formation.fielded():
		if c.is_alive() and (weakest == null or c.hp < weakest.hp \
				or (c.hp == weakest.hp and c.order_id < weakest.order_id)):
			weakest = c
	return weakest


func _attack(attacker: Character, defender: Character) -> void:
	# The cleave's arc is set before the blow lands: the neighbors are grazed
	# even when the main target drops and his slot empties.
	var grazed := state.formation_of(defender.side).line_neighbors(defender) \
			if attacker.is_berserker else ([] as Array[Character])
	var dmg := _melee_damage(attacker, defender)
	var wounded := _chew_block(attacker.weapon.kind, defender, dmg)
	_tally_blood(attacker, defender, wounded)
	defender.hp -= wounded
	if wounded < dmg:
		state.log_event("%s hits %s for %d — %d dies on the guard (%d HP left)." %
				[attacker.display_name, defender.display_name, dmg, dmg - wounded,
				maxi(0, defender.hp)])
	else:
		state.log_event("%s hits %s for %d (%d HP left)." %
				[attacker.display_name, defender.display_name, dmg, maxi(0, defender.hp)])
	if defender.hp <= 0:
		await _handle_death(defender)
	for victim in grazed:
		if outcome != Outcome.NONE:
			return
		await _cleave_graze(attacker, victim)


## The berserker's swing spills over: flat damage to the target's
## line-neighbors, never armored, but softened and shield-halved. A man who
## routed or died mid-swing is already out of the arc.
func _cleave_graze(attacker: Character, victim: Character) -> void:
	if not victim.is_alive() or not state.formation_of(victim.side).has(victim):
		return
	var dmg := _graze_damage(attacker, victim)
	var wounded := _chew_block(attacker.weapon.kind, victim, dmg)
	_tally_blood(attacker, victim, wounded)
	victim.hp -= wounded
	state.log_event("%s's cleave grazes %s for %d (%d HP left)." %
			[attacker.display_name, victim.display_name, wounded, maxi(0, victim.hp)])
	if victim.hp <= 0:
		await _handle_death(victim)


## The shoot beat: both arrows bound to the mark placed a beat ago, and a
## mark still standing after them is SUPPRESSED — his blows lose a third.
## A mark that died, routed or was pulled back to the ship wastes the shot
## whole — rescuing the marked man is the counter-play arrows otherwise
## lack. The mark is spent with the arrows either way.
func _double_shot(archer: Character) -> void:
	var mark: Character = state.archer_marks.get(archer)
	state.archer_marks.erase(archer)
	if mark == null or not mark.is_alive() \
			or not state.opposing_formation(archer.side).has(mark):
		state.log_event("%s's aimed arrows find nothing — the mark is gone." %
				archer.display_name)
		return
	state.log_event("%s looses both aimed arrows at %s!" %
			[archer.display_name, mark.display_name])
	for i in 2:
		if outcome != Outcome.NONE or not mark.is_alive() \
				or not state.opposing_formation(archer.side).has(mark):
			return
		await _snipe(archer, mark)
	if outcome == Outcome.NONE and mark.is_alive() \
			and state.opposing_formation(archer.side).has(mark):
		mark.suppressed = BattleState.SUPPRESS_TURNS
		state.log_event("%s is suppressed — his blows lose their weight." %
				mark.display_name)


## The archer's arrow: flat LOW damage, armor and columns ignored — the one
## attack placement cannot dodge. Side-wide protections still soften it.
func _snipe(attacker: Character, defender: Character) -> void:
	var dmg := _snipe_damage(attacker, defender)
	var wounded := _chew_block(attacker.weapon.kind, defender, dmg)
	_tally_blood(attacker, defender, wounded)
	defender.hp -= wounded
	if wounded < dmg:
		state.log_event("%s's arrow rattles off %s's guard%s." %
				[attacker.display_name, defender.display_name,
				"" if wounded == 0 else " but still bites for %d" % wounded])
	else:
		state.log_event("%s's arrow finds %s for %d (%d HP left)." %
				[attacker.display_name, defender.display_name, wounded, maxi(0, defender.hp)])
	if defender.hp <= 0:
		await _handle_death(defender)


func _melee_damage(attacker: Character, defender: Character) -> int:
	var raw := attacker.damage_against(defender, _leader_bonus(attacker))
	# The heavy beat: the berserker's blow doubles when his rhythm peaks.
	if attacker.current_beat() == "heavy":
		raw *= 2
	return _soften(_suppression_cut(attacker, raw), defender)


func _snipe_damage(attacker: Character, defender: Character) -> int:
	return _soften(_suppression_cut(attacker, BattleState.ARCHER_SNIPE_DAMAGE), defender)


## The cleave's spill on one neighbor — flat, doubled on the heavy beat,
## softened and blocked like any physical hit.
func _graze_damage(attacker: Character, victim: Character) -> int:
	var base := BattleState.CLEAVE_GRAZE_DAMAGE
	if attacker.current_beat() == "heavy":
		base *= 2
	return _soften(_suppression_cut(attacker, base), victim)


## SUPPRESSED (docs/block-and-patterns.md): every damage packet the mark
## deals loses a third, rounded up against him — never below 1.
func _suppression_cut(attacker: Character, dmg: int) -> int:
	if attacker.suppressed <= 0:
		return dmg
	@warning_ignore("integer_division")
	return maxi(1, dmg - (dmg + 2) / 3)


## End-of-own-turn decay for timed statuses, fielded and reserve alike —
## time passes for a man dragged home too.
func _tick_statuses(side: Character.Side) -> void:
	for c in state.fielded(side) + state.reserve_of(side):
		c.suppressed = maxi(0, c.suppressed - 1)
		c.pinned = maxi(0, c.pinned - 1)


## The captain's leader aura: his line-neighbors strike +1 in melee.
func _leader_bonus(attacker: Character) -> int:
	var bonus := 0
	for neighbor in state.formation_of(attacker.side).line_neighbors(attacker):
		if neighbor.is_captain:
			bonus += 1
	return bonus


## Guard up (docs/block-and-patterns.md): at the start of a side's turn every
## fielded man's block resets to his armor — leftover block does not bank,
## and only the fielded raise it: nobody swings at the reserve.
func _raise_guard(side: Character.Side) -> void:
	for c in state.fielded(side):
		c.block = c.armor


## The one place block arithmetic lives, shared by resolution and the
## forecast so the bill on a token is the same math the blow resolves with.
## Physical damage is absorbed point for point — except the axe, whose every
## point destroys TWO block (and the block swallows it at that rate), so the
## axeman's job is opening a guarded man for the swords behind him.
## Pure: returns {"destroyed": block lost, "wounded": damage reaching flesh}.
static func block_math(kind: Weapon.Kind, block: int, dmg: int) -> Dictionary:
	if block <= 0 or dmg <= 0:
		return {"destroyed": 0, "wounded": maxi(0, dmg)}
	if kind == Weapon.Kind.AXE:
		var destroyed := mini(block, dmg * 2)
		@warning_ignore("integer_division")
		return {"destroyed": destroyed, "wounded": dmg - (destroyed + 1) / 2}
	var absorbed := mini(block, dmg)
	return {"destroyed": absorbed, "wounded": dmg - absorbed}


## Spend the defender's block against one physical hit; returns what wounds.
func _chew_block(kind: Weapon.Kind, defender: Character, dmg: int) -> int:
	var bill := block_math(kind, defender.block, dmg)
	defender.block -= bill["destroyed"]
	return bill["wounded"]


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
## current placements, active effects and the telegraphed tactic — including
## a telegraphed captain's call: enemy attacks are previewed from the
## positions the call will put them in:
## {Character: {"hp": int, "morale": int}}. Deterministic and side-effect
## free, built on the same targeting and damage rules the phases resolve
## with. Single pass — each predicted death counts as one morale wave, but
## cascades, rout shocks and reaction saves are not chained: it is a
## preview of intent, not a simulation.
func forecast() -> Dictionary:
	return _forecast_pass()["bill"]


## The press the table would judge if nothing changed (docs/press-proposal.md):
## the same shape as state.last_press, from the same pass as forecast() —
## your blows on current geometry, theirs from their called positions, and
## presence judged there too. Side-effect free like forecast().
func forecast_press() -> Dictionary:
	var pass_result := _forecast_pass()
	var blood: Dictionary = pass_result["blood"]
	var theirs: Array = pass_result["enemy_presence"]
	var columns: Array[int] = []
	var player_wins := 0
	var enemy_wins := 0
	for col in Formation.COLUMNS:
		var yours := state.player_formation.at(Formation.FRONT, col) != null \
				or state.player_formation.at(Formation.BACK, col) != null
		var verdict := _verdict(yours, theirs[col], blood["player"][col], blood["enemy"][col])
		columns.append(verdict)
		if verdict > 0:
			player_wins += 1
		elif verdict < 0:
			enemy_wins += 1
	return _press_summary(columns, player_wins, enemy_wins)


## One pass of predicted blows, shared by forecast() and forecast_press():
## {"bill": {Character: {"hp", "morale"}}, "blood": {"player": [4], "enemy":
## [4]} — the press ledger those blows would write —, "enemy_presence":
## [4 bools] where their line stands after the telegraphed call}.
func _forecast_pass() -> Dictionary:
	var out := {}
	var guard := {}
	var blood := {"player": [0, 0, 0, 0], "enemy": [0, 0, 0, 0]}
	var everyone := state.fielded(Character.Side.PLAYER) + state.fielded(Character.Side.ENEMY)
	for c in everyone:
		out[c] = {"hp": 0, "morale": 0}
		guard[c] = c.block
	# The rail archers open your fight phase: one arrow per ship archer,
	# re-aimed between arrows against the hp these predictions already cost.
	if state.archer_support_damage > 0:
		for i in _ship_archers():
			var mark := _forecast_weakest(out)
			if mark == null:
				break
			out[mark]["hp"] += state.archer_support_damage
	# Your side strikes on current geometry: your fight phase resolves before
	# the telegraphed call re-arranges their line. Axes first, both sides, so
	# the predicted block spend follows the resolution order.
	for attacker in _attack_order(Character.Side.PLAYER):
		_forecast_attacker(attacker, out, guard, blood)
	# Their side strikes AFTER the call: preview it on the real grid, then
	# put every man back where he stands. A telegraphed captain's order fires
	# before they swing, so the preview rages them for the pass and un-rages
	# them after — the real men are never touched.
	var held: Array[Character] = state.enemy_formation.slots.duplicate()
	var preview_rage: int = state.captain_command.get("amount", 1) \
			if state.next_tactic == "captains_order" \
			and state.captain_command.get("effect", "") == "blood_rage" else 0
	_apply_call(state.next_tactic)
	for c in state.fielded(Character.Side.ENEMY):
		c.rage += preview_rage
	for attacker in _attack_order(Character.Side.ENEMY):
		_forecast_attacker(attacker, out, guard, blood)
	var enemy_presence: Array[bool] = []
	for col in Formation.COLUMNS:
		enemy_presence.append(state.enemy_formation.at(Formation.FRONT, col) != null \
				or state.enemy_formation.at(Formation.BACK, col) != null)
	for c in state.fielded(Character.Side.ENEMY):
		c.rage -= preview_rage
	state.enemy_formation.slots = held
	# The telegraphed tactic's direct damage is part of the bill.
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
	return {"bill": out, "blood": blood, "enemy_presence": enemy_presence}


## One attacker's contribution to the forecast bill, at his current target.
## `guard` is the running block ledger: predicted hits chew it with the same
## block_math resolution uses, so the bill on a token is blood, not
## steel-on-shield.
func _forecast_attacker(attacker: Character, out: Dictionary, guard: Dictionary,
		blood: Dictionary) -> void:
	if not attacker.is_alive():
		return
	match attacker.current_beat():
		"guard":
			# No blow — and a player-side guard beat raises the ledger before
			# the enemy phase spends it (your fight phase resolves first; an
			# enemy guard beat lands after your hits, so it covers nothing
			# inside this forecast's window).
			if guard.has(attacker):
				guard[attacker] += attacker.armor
			if attacker.is_shieldman:
				for neighbor in state.formation_of(attacker.side).line_neighbors(attacker):
					if guard.has(neighbor):
						guard[neighbor] += BattleState.SHIELD_AURA_BLOCK
			return
		"aim":
			if _is_sniper(attacker):
				return  # the mark locks, nothing is loosed
		"shoot":
			if _is_sniper(attacker):
				# The aimed double shot is bound to its mark — or to nothing.
				var mark: Character = state.archer_marks.get(attacker)
				if mark != null and mark.is_alive() and out.has(mark) \
						and state.opposing_formation(attacker.side).has(mark):
					for i in 2:
						_forecast_hit(attacker, mark, _snipe_damage(attacker, mark), out, guard, blood)
				return
	if not _can_melee(attacker):
		return
	var target := _pick_target(attacker)
	if target == null or not out.has(target):
		return
	var swings := 1 + attacker.bonus_attacks
	for i in swings:
		_forecast_hit(attacker, target, _melee_damage(attacker, target), out, guard, blood)
		if attacker.is_berserker:
			for victim in state.formation_of(target.side).line_neighbors(target):
				if out.has(victim):
					_forecast_hit(attacker, victim, _graze_damage(attacker, victim), out, guard, blood)


## One predicted physical hit: spend the ledger's block, bill the blood —
## and write it on the press ledger by the same rule resolution uses.
func _forecast_hit(attacker: Character, defender: Character, dmg: int,
		out: Dictionary, guard: Dictionary, blood: Dictionary) -> void:
	var bill := block_math(attacker.weapon.kind, guard[defender], dmg)
	guard[defender] -= bill["destroyed"]
	out[defender]["hp"] += bill["wounded"]
	if bill["wounded"] <= 0 or not attacker.weapon.resolves_columns:
		return
	var col := state.formation_of(defender.side).column_of(defender)
	if col != -1:
		blood["player" if attacker.side == Character.Side.PLAYER else "enemy"][col] += bill["wounded"]


# --- Death, morale and routing ----------------------------------------------

func _handle_death(dead: Character) -> void:
	# Drag Him Back! fires automatically: an affordable save in hand cancels
	# the killing blow on a crew member, no prompt, no controller. Nobody
	# drags the prowman from the prow — his fall is the pair's hinge, and an
	# automatic save would chain into a forced crossing the player never chose.
	if dead.side == Character.Side.PLAYER and not dead.is_captain \
			and dead.pinned == 0 \
			and not _pair_member(dead) and state.player_formation.has(dead):
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
	var was_fielded := state.formation_of(side).has(dead)
	var line := state.formation_of(side).line_of(dead) if was_fielded else -1
	var col := state.formation_of(side).column_of(dead) if was_fielded else -1
	state.formation_of(side).remove(dead)
	state.reserve_of(side).erase(dead)
	state.archer_marks.erase(dead)
	if side == Character.Side.PLAYER:
		state.player_dead.append(dead)
	else:
		state.enemy_dead.append(dead)
		_gain_momentum(BattleState.KILL_MOMENTUM)
		if state.war_cry_active:
			_gain_momentum(1)
	state.log_event("%s is slain." % dead.display_name)
	if dead == state.player_prowman and was_fielded:
		_pair_exit(line, col)
		if outcome != Outcome.NONE:
			return
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
	var line := state.formation_of(side).line_of(c)
	var col := state.formation_of(side).column_of(c)
	state.formation_of(side).remove(c)
	state.archer_marks.erase(c)
	c.shaken = true
	if side == Character.Side.PLAYER:
		state.player_fled.append(c)
		state.log_event("%s breaks and flees back to the ship." % c.display_name)
	else:
		state.enemy_routed.append(c)
		state.log_event("%s panics and dives overboard." % c.display_name)
	if c == state.player_prowman:
		_pair_exit(line, col)
		if outcome != Outcome.NONE:
			return
	for other in state.fielded(side):
		_deal_morale_damage(other, BattleState.ROUT_MORALE_HIT)


## The prow pair's hinge: the prowman has left the field for good, so the
## captain must hold it — one of the pair always does. He crosses at once
## into the vacated slot for PAIR_ENTRY_COST momentum; a crew too spent to
## answer loses its nerve on the spot.
func _pair_exit(line: int, col: int) -> void:
	var captain := state.player_captain
	if captain == null or not captain.is_alive() \
			or not state.player_reserve.has(captain):
		return
	if state.momentum < BattleState.PAIR_ENTRY_COST:
		outcome = Outcome.DEFEAT
		state.log_event("No one holds the prow and no strength is left to answer — panic takes the crew.")
		return
	state.momentum -= BattleState.PAIR_ENTRY_COST
	state.player_reserve.erase(captain)
	if line >= 0 and state.player_formation.at(line, col) == null:
		state.player_formation.place(captain, line, col)
	else:
		state.player_formation.place_at_index(captain, state.player_formation.first_free_index())
	captain.beat = 0
	state.log_event("%s leaps the rail and takes the prow himself." % captain.display_name)


# --- The press (docs/press-proposal.md) ---------------------------------------
# Every column is a duel scored on the blood dealt into it this round; the
# side winning more columns has the press. Judged once per round after both
# sides' beats, before reinforcements. A verdict, never a shove.

func _reset_press() -> void:
	for col in Formation.COLUMNS:
		state.player_column_blood[col] = 0
		state.enemy_column_blood[col] = 0


## Blood onto the ledger: what reached flesh, in the column the defender
## stood in when the blow landed, unless the weapon is tagged out of the
## press (the bow). Read before the blow lands — a dead man's column is
## the one he died in.
func _tally_blood(attacker: Character, defender: Character, wounded: int) -> void:
	if wounded <= 0 or not attacker.weapon.resolves_columns:
		return
	var col := state.formation_of(defender.side).column_of(defender)
	if col == -1:
		return
	if attacker.side == Character.Side.PLAYER:
		state.player_column_blood[col] += wounded
	else:
		state.enemy_column_blood[col] += wounded


## One column's verdict, where men stand now: +1 yours, -1 theirs, 0 none.
## Presence comes first — a column held by one side only is that side's
## (the man facing nobody already lost his swing; holding it is what he
## contributes), and blood into a column you do not hold wins nothing.
## Both present: more blood wins, equal is no result.
func _column_verdict(col: int, player_blood: int, enemy_blood: int) -> int:
	var yours := state.player_formation.at(Formation.FRONT, col) != null \
			or state.player_formation.at(Formation.BACK, col) != null
	var theirs := state.enemy_formation.at(Formation.FRONT, col) != null \
			or state.enemy_formation.at(Formation.BACK, col) != null
	return _verdict(yours, theirs, player_blood, enemy_blood)


static func _verdict(yours: bool, theirs: bool, player_blood: int, enemy_blood: int) -> int:
	if yours and not theirs:
		return 1
	if theirs and not yours:
		return -1
	if not yours and not theirs:
		return 0
	return signi(player_blood - enemy_blood)


## The press summary in state.last_press's shape, payout computed but not
## paid — resolution pays it, the forecast only shows it.
static func _press_summary(columns: Array[int], player_wins: int, enemy_wins: int) -> Dictionary:
	var margin := absi(player_wins - enemy_wins)
	var holder := "none"
	if player_wins > enemy_wins:
		holder = "player"
	elif enemy_wins > player_wins:
		holder = "enemy"
	var paid := 0
	if holder == "player":
		paid = BattleState.PRESS_WIN_MOMENTUM + margin * BattleState.PRESS_MARGIN_MOMENTUM
	return {"columns": columns, "player_wins": player_wins, "enemy_wins": enemy_wins,
			"margin": margin, "holder": holder, "momentum": paid}


## The round's judgment and the win bonus (owner's ruling): the side with
## more columns has the press; the player is paid PRESS_WIN_MOMENTUM for
## having it plus PRESS_MARGIN_MOMENTUM per column of margin; at
## PRESS_MORALE_MARGIN the losing line takes PRESS_MORALE on every fielded
## man. The enemy has no momentum, so its press pays only your morale.
func _resolve_press() -> void:
	var columns: Array[int] = []
	var player_wins := 0
	var enemy_wins := 0
	for col in Formation.COLUMNS:
		var verdict := _column_verdict(col, state.player_column_blood[col],
				state.enemy_column_blood[col])
		columns.append(verdict)
		if verdict > 0:
			player_wins += 1
		elif verdict < 0:
			enemy_wins += 1
	state.last_press = _press_summary(columns, player_wins, enemy_wins)
	var holder: String = state.last_press["holder"]
	var margin: int = state.last_press["margin"]
	var paid: int = state.last_press["momentum"]
	if paid > 0:
		_gain_momentum(paid)
	match holder:
		"player":
			state.log_event("The press is yours: %d columns to %d (+%d momentum)." %
					[player_wins, enemy_wins, paid])
		"enemy":
			state.log_event("The press is theirs: %d columns to %d." % [enemy_wins, player_wins])
		_:
			state.log_event("The line holds even: %d columns each — no press." % player_wins)
	if holder == "none" or margin < BattleState.PRESS_MORALE_MARGIN:
		return
	var losing := Character.Side.ENEMY if holder == "player" else Character.Side.PLAYER
	for c in state.fielded(losing):
		_deal_morale_damage(c, BattleState.PRESS_MORALE)
	state.log_event("The %s line gives ground in its heart." %
			("enemy" if losing == Character.Side.ENEMY else "boarding"))
	_check_routs(losing)


# --- Enemy tactics and reinforcements ----------------------------------------

## The telegraph for a given turn: every period-th enemy turn the captain's
## command replaces whatever the rotation would have picked — from the
## sterncastle or the line alike, so a full locked board cannot silence the
## escalation. Off the beat, the rotation runs (seeded-random for now; a
## fixed cycle is an open ruling).
func _pick_tactic_for(turn: int) -> String:
	var period: int = state.captain_command.get("period", 0)
	if period > 0 and turn % period == 0 \
			and state.enemy_captain != null and state.enemy_captain.is_alive():
		return "captains_order"
	return _pick_tactic()


func _pick_tactic() -> String:
	if enemy_tactics.is_empty():
		return "press_the_attack"
	return enemy_tactics[rng.randi_range(0, enemy_tactics.size() - 1)]


func _resolve_tactic(tactic: String) -> void:
	match tactic:
		"captains_order":
			_resolve_command()
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
		"fresh_men_forward", "shift_port", "shift_starboard", "step_up":
			var moved := _apply_call(tactic)
			match tactic:
				"fresh_men_forward":
					state.log_event("Fresh men to the front — their lines rotate!")
				"shift_port", "shift_starboard":
					state.log_event("The enemy line shifts %s." %
							("port" if tactic == "shift_port" else "starboard")
							if moved else "The call to shift goes up, but the line has nowhere to go.")
				"step_up":
					state.log_event("Defenders step up into the gaps in their front line."
							if moved else "The defenders hold — no gaps to fill.")
		_:
			state.log_event("The enemy presses the attack.")


## The captain's command (docs/block-and-patterns.md): dispatched on the
## scenario's effect id, so later captains carry different words. blood_rage:
## every fielded defender gains a permanent, stacking +amount attack damage —
## men below decks miss the speech, and what a man has heard he keeps.
func _resolve_command() -> void:
	var command := state.captain_command
	match command.get("effect", ""):
		"blood_rage":
			var amount: int = command.get("amount", 1)
			for c in state.fielded(Character.Side.ENEMY):
				c.rage += amount
			state.log_event("%s roars from the stern — %s! Every defender strikes +%d, and the rage does not fade." %
					[state.enemy_captain.display_name, command.get("name", "the command"), amount])


## The captain's calls are formation moves (docs/lines-redesign.md phase C):
## the same verbs the player's cards use, applied to the enemy grid. Shared
## between resolution and the forecast's preview. Port slides toward
## column 0, starboard away. Returns whether anyone actually moved.
func _apply_call(tactic: String) -> bool:
	match tactic:
		"fresh_men_forward":
			state.enemy_formation.swap_lines()
			return not state.enemy_formation.is_empty()
		"shift_port":
			return state.enemy_formation.shift(-1)
		"shift_starboard":
			return state.enemy_formation.shift(1)
		"step_up":
			return state.enemy_formation.step_up()
	return false


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
		c.beat = 0
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
		state.enemy_captain.beat = 0
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
		# A full hand refuses the card rather than drawing and binning it:
		# it stays in the deck and comes round again.
		if state.hand.size() >= BattleState.MAX_HAND_SIZE:
			return drew_any
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
	# The battle opens with every guard up; a man crossing later carries the
	# guard he boarded with (dents included) until his side's next turn start.
	c.block = c.armor
	# A scenario may hand a man a custom rhythm; everyone else gets his role's.
	if c.pattern.is_empty():
		c.pattern = c.default_pattern()


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
