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
##   choose_rider(state: BattleState, card: CardData, moves: Array[Dictionary])
##       -> Dictionary  (optional, awaited)
##     Movement riders are mandatory (docs/lines-redesign.md): the engine
##     computes every legal move for the rider and the controller picks WHICH,
##     never whether. Move shapes, one per rider type:
##       RIDER_SLIDE:        {"character": Character, "direction": int}
##                           (-1 larboard / left, +1 starboard / right)
##       RIDER_STEP,
##       RIDER_ADVANCE:      {"character": Character, "line": int}
##                           (Formation.FRONT or Formation.BACK)
##       RIDER_SWAP_FIELDED: {"a": Character, "b": Character}
##     A controller without the hook — or one answering with a move that is
##     not in the list — gets moves[0]: the first legal move in reading order
##     (front line left to right, then the second line), larboard before
##     starboard, pairs ordered by the reading order of both members.
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
		state.enemy_captain.order_id = _next_order_id()
	var deck: Array[CardData] = []
	deck.assign(scenario.get("deck", []))
	state.deck = deck
	_shuffle(state.deck)
	for c in state.fielded(Character.Side.ENEMY):
		if _windup_role(c):
			c.windup = BattleState.WINDUP_PERIOD - 1
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
	_advance_windups()
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
				if target == null or not state.player_formation.has(target):
					return false
				if not _pair_swap_legal(target, second_target):
					return false
				if second_target != null:
					if second_target == target:
						return false
					if not state.player_reserve.has(second_target) \
							and not state.player_formation.has(second_target):
						return false
				elif _default_swap_partner(target) == null:
					return false
			CardData.EffectType.SHOVE:
				if shove_directions(target).is_empty():
					return false
			CardData.EffectType.CHALLENGE:
				if state.player_captain == null \
						or not state.player_formation.has(state.player_captain):
					return false
				if state.enemy_captain == null \
						or not state.enemy_formation.has(state.enemy_captain):
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
			for effect in card.effects:
				match effect.get("type"):
					CardData.EffectType.PULL_TO_RESERVE, CardData.EffectType.EXTRA_ATTACK, \
					CardData.EffectType.SWAP:
						if not state.player_formation.has(target):
							return false
			return true
	return false


## Reserve men an ordinary crossing may take (Reinforce, the momentum commit),
## in queue order. The prow pair is not among them: they cross only by trading
## with each other (docs/combat-design.md, the prow pair).
func crossing_candidates() -> Array[Character]:
	var out: Array[Character] = []
	for c in state.player_reserve:
		if not _pair_member(c):
			out.append(c)
	return out


## Could this man be sent over by the momentum commit right now? Same guards
## _commit_reserve enforces, asked before the click instead of after.
func can_commit(c: Character) -> bool:
	return c != null and state.player_reserve.has(c) and not _pair_member(c) \
			and not state.player_formation.is_full() \
			and state.momentum >= BattleState.RESERVE_COMMIT_COST


## Everyone the fielded `target` may trade places with by Swap: his fellows on
## deck in reading order, then the men waiting on the ship. The prow pair's
## law narrows a pair member's list to his counterpart alone.
func swap_partners(target: Character) -> Array[Character]:
	var out: Array[Character] = []
	if target == null or not state.player_formation.has(target):
		return out
	for c in state.player_formation.fielded() + state.player_reserve:
		if c != target and _pair_swap_legal(target, c):
			out.append(c)
	return out


## Which way Break the Line may shove this defender: larboard (-1) before
## starboard (+1), and only from the rank at the rail into an empty slot.
func shove_directions(target: Character) -> Array[int]:
	var out: Array[int] = []
	var f := state.enemy_formation
	if target == null or not f.has(target) or f.line_of(target) != Formation.FRONT:
		return out
	var col := f.column_of(target)
	for dir: int in [-1, 1]:
		if Formation.in_bounds(Formation.FRONT, col + dir) \
				and f.at(Formation.FRONT, col + dir) == null:
			out.append(dir)
	return out


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
			var crosser := target if target != null else _default_crosser()
			state.player_reserve.erase(crosser)
			var index := slot if _slot_free(state.player_formation, slot) \
					else state.player_formation.first_free_index()
			state.player_formation.place_at_index(crosser, index)
			state.log_event("%s comes over the rail." % crosser.display_name)
		CardData.EffectType.SWAP:
			var partner := second_target if second_target != null \
					else _default_swap_partner(target)
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
		CardData.EffectType.RIDER_SLIDE, CardData.EffectType.RIDER_STEP, \
		CardData.EffectType.RIDER_ADVANCE, CardData.EffectType.RIDER_SWAP_FIELDED:
			await _resolve_rider(effect.get("type"), target, card)


# --- Movement riders ---------------------------------------------------------

## The mandatory rider (docs/lines-redesign.md): the engine lists every legal
## move and the controller picks WHICH — never whether. No legal move at all
## (a packed grid, a front-liner told to advance) is the one case a rider is
## skipped, and it passes in silence. Riders move men BETWEEN SLOTS only, so
## they never cross the rail and the prow pair's law needs no checking here.
func _resolve_rider(rider: CardData.EffectType, target: Character, card: CardData) -> void:
	var moves := _rider_moves(rider, target)
	if moves.is_empty():
		return
	var move: Dictionary = moves[0]
	if controller.has_method("choose_rider"):
		var answer = await controller.choose_rider(state, card, moves)
		if answer is Dictionary and _rider_move_offered(moves, answer):
			move = answer
	_apply_rider_move(rider, move)


## Every legal move for this rider, in reading order (front line left to
## right, then the second line), larboard before starboard, pairs ordered by
## the reading order of both members. moves[0] is what a controller gets when
## it cannot or will not choose.
func _rider_moves(rider: CardData.EffectType, target: Character) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	var formation := state.player_formation
	match rider:
		CardData.EffectType.RIDER_SLIDE:
			for c in formation.fielded():
				var line := formation.line_of(c)
				for dir in [-1, 1]:
					var col: int = formation.column_of(c) + dir
					if Formation.in_bounds(line, col) and formation.at(line, col) == null:
						moves.append({"character": c, "direction": dir})
		CardData.EffectType.RIDER_STEP, CardData.EffectType.RIDER_ADVANCE:
			if target == null or not formation.has(target):
				return moves
			var line := formation.line_of(target)
			# A column has exactly one other line, so a step is one choice at
			# most; advance is that same step, restricted to the way forward.
			if rider == CardData.EffectType.RIDER_ADVANCE and line != Formation.BACK:
				return moves
			var destination := Formation.FRONT if line == Formation.BACK else Formation.BACK
			if formation.at(destination, formation.column_of(target)) == null:
				moves.append({"character": target, "line": destination})
		CardData.EffectType.RIDER_SWAP_FIELDED:
			var men := formation.fielded()
			for i in men.size():
				for j in range(i + 1, men.size()):
					moves.append({"a": men[i], "b": men[j]})
	return moves


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
	match rider:
		CardData.EffectType.RIDER_SLIDE:
			var slider: Character = move["character"]
			var dir: int = move["direction"]
			if formation.slide(slider, dir):
				state.log_event("%s sidesteps to %s." %
						[slider.display_name, "larboard" if dir < 0 else "starboard"])
		CardData.EffectType.RIDER_STEP, CardData.EffectType.RIDER_ADVANCE:
			var stepper: Character = move["character"]
			if move["line"] == Formation.FRONT:
				if formation.advance(stepper):
					state.log_event("%s steps up into the front line." % stepper.display_name)
			elif formation.retire(stepper):
				state.log_event("%s falls back into the second line." % stepper.display_name)
		CardData.EffectType.RIDER_SWAP_FIELDED:
			var a: Character = move["a"]
			var b: Character = move["b"]
			if formation.swap_positions(a, b):
				state.log_event("%s and %s trade places." % [a.display_name, b.display_name])


## The prow pair is active whenever the roster declares a prowman: then the
## captain and the prowman move only by trading places with each other (the
## Swap card) or by the forced crossing in _pair_exit — never by Reinforce,
## the momentum commit, or a swap with ordinary crew.
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
		if c != target and _pair_swap_legal(target, c):
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


func _commit_reserve(character: Character, slot := -1) -> void:
	if not can_commit(character):
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
				if attacker.windup == 0:
					await _double_shot(attacker)
					await _pace()
					break
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
				# the swing. Dodging is placement, never dice — but it buys a
				# turn, not the fight, so he closes if he has anywhere to go.
				var step := _close_direction(attacker)
				if step != 0:
					state.formation_of(side).slide(attacker, step)
					state.log_event("%s presses toward the fighting." %
							attacker.display_name)
				else:
					state.log_event("%s swings at air — the column across is empty." %
							attacker.display_name)
				await _pace()
				break
			await _attack(attacker, target)
			await _pace()


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


## Which way a man whose column is empty steps instead of flailing at air.
## He forfeits the swing either way: dodging still costs the attacker his
## turn, so placement is still defence — but the fight now converges, and
## two survivors in different columns can no longer stand and stare until
## the turn limit. Deterministic, as every miss here is: the nearest column
## with someone to hit in it, larboard on a tie. Zero when his own line
## walls him in, or there is nobody left to close on.
func _close_direction(attacker: Character) -> int:
	var own := state.formation_of(attacker.side)
	var opposing := state.opposing_formation(attacker.side)
	var col := own.column_of(attacker)
	if col == -1:
		return 0
	var step := 0
	var nearest := Formation.COLUMNS
	for c in Formation.COLUMNS:
		if opposing.column_melee_target(c) == null:
			continue
		var distance := absi(c - col)
		if distance == 0 or distance >= nearest:
			continue
		nearest = distance
		step = -1 if c < col else 1
	if step == 0:
		return 0
	var line := own.line_of(attacker)
	if not Formation.in_bounds(line, col + step) or own.at(line, col + step) != null:
		return 0
	return step


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


func _opposing_captain(side: Character.Side) -> Character:
	return state.enemy_captain if side == Character.Side.PLAYER else state.player_captain


func _opposing_captain_fielded(side: Character.Side) -> bool:
	var cap := _opposing_captain(side)
	return cap != null and cap.is_alive() and state.opposing_formation(side).has(cap)


func _attack(attacker: Character, defender: Character) -> void:
	# The cleave's arc is set before the blow lands: the neighbors are grazed
	# even when the main target drops and his slot empties.
	var grazed := state.formation_of(defender.side).line_neighbors(defender) \
			if attacker.is_berserker else ([] as Array[Character])
	var dmg := _melee_damage(attacker, defender)
	defender.hp -= dmg
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
	victim.hp -= dmg
	state.log_event("%s's cleave grazes %s for %d (%d HP left)." %
			[attacker.display_name, victim.display_name, dmg, maxi(0, victim.hp)])
	if victim.hp <= 0:
		await _handle_death(victim)


## The aimed double shot: both arrows bound to the mark placed a turn ago.
## A mark that died, routed or was pulled back to the ship wastes the shot
## whole — rescuing the marked man is the counter-play snipes otherwise lack.
func _double_shot(archer: Character) -> void:
	var mark: Character = state.archer_marks.get(archer)
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
	var raw := attacker.damage_against(defender, _leader_bonus(attacker), _aura_armor(defender))
	# The wound-up heavy blow: the berserker's melee damage doubles on the
	# turn his counter reaches 0 (docs/lines-redesign.md phase C rulings).
	if attacker.is_berserker and attacker.windup == 0:
		raw *= 2
	return _shield_halved(_soften(raw, defender), defender)


func _snipe_damage(defender: Character) -> int:
	return _shield_halved(_soften(BattleState.ARCHER_SNIPE_DAMAGE, defender), defender)


## The cleave's spill on one neighbor — flat, doubled on the wind-up turn,
## never armored, but softened and shield-halved like any physical hit.
func _graze_damage(attacker: Character, victim: Character) -> int:
	var base := BattleState.CLEAVE_GRAZE_DAMAGE
	if attacker.windup == 0:
		base *= 2
	return _shield_halved(_soften(base, victim), victim)


## The captain's leader aura: his line-neighbors strike +1 in melee.
func _leader_bonus(attacker: Character) -> int:
	var bonus := 0
	for neighbor in state.formation_of(attacker.side).line_neighbors(attacker):
		if neighbor.is_captain:
			bonus += 1
	return bonus


## The shieldman's aura: +1 armor with a shieldman standing beside the
## defender — flat, never stacking with a second shield. Worn armor only
## helps in melee, so the aura is melee-only by construction.
func _aura_armor(defender: Character) -> int:
	for neighbor in state.formation_of(defender.side).line_neighbors(defender):
		if neighbor.is_shieldman:
			return 1
	return 0


## The shieldman's own hide: physical hits (melee, snipes, grazes) halve on
## his shield, rounded up, after every other reduction. Card and tactic true
## damage goes around the shield — volleys are the shieldman counter-play.
func _shield_halved(dmg: int, defender: Character) -> int:
	@warning_ignore("integer_division")
	return (dmg + 1) / 2 if defender.is_shieldman else dmg


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
	var out := {}
	var everyone := state.fielded(Character.Side.PLAYER) + state.fielded(Character.Side.ENEMY)
	for c in everyone:
		out[c] = {"hp": 0, "morale": 0}
	# The rail archers open your fight phase: one arrow per ship archer,
	# re-aimed between arrows against the hp these predictions already cost.
	if state.archer_support_damage > 0:
		for i in _ship_archers():
			var mark := _forecast_weakest(out)
			if mark == null:
				break
			out[mark]["hp"] += state.archer_support_damage
	# Your side strikes on current geometry: your fight phase resolves before
	# the telegraphed call re-arranges their line.
	for attacker in state.fielded(Character.Side.PLAYER):
		_forecast_attacker(attacker, out)
	# Their side strikes AFTER the call: preview it on the real grid, then
	# put every man back where he stands.
	var held: Array[Character] = state.enemy_formation.slots.duplicate()
	_apply_call(state.next_tactic)
	for attacker in state.fielded(Character.Side.ENEMY):
		_forecast_attacker(attacker, out)
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
	return out


## One attacker's contribution to the forecast bill, at his current target.
func _forecast_attacker(attacker: Character, out: Dictionary) -> void:
	if not attacker.is_alive():
		return
	if not _is_sniper(attacker) and not _can_melee(attacker):
		return
	# An aimed double shot is bound to its mark — or to nothing at all.
	if _is_sniper(attacker) and attacker.windup == 0:
		var mark: Character = state.archer_marks.get(attacker)
		if mark != null and mark.is_alive() and out.has(mark) \
				and state.opposing_formation(attacker.side).has(mark):
			out[mark]["hp"] += _snipe_damage(mark) * 2
		return
	var target := _pick_target(attacker)
	if target == null or not out.has(target):
		return
	var swings := 1 + attacker.bonus_attacks
	var dmg := _snipe_damage(target) if _is_sniper(attacker) \
			else _melee_damage(attacker, target)
	out[target]["hp"] += dmg * swings
	if attacker.is_berserker and not _is_sniper(attacker):
		for victim in state.formation_of(target.side).line_neighbors(target):
			out[victim]["hp"] += _graze_damage(attacker, victim) * swings


# --- Death, morale and routing ----------------------------------------------

func _handle_death(dead: Character) -> void:
	# Drag Him Back! fires automatically: an affordable save in hand cancels
	# the killing blow on a crew member, no prompt, no controller. Nobody
	# drags the prowman from the prow — his fall is the pair's hinge, and an
	# automatic save would chain into a forced crossing the player never chose.
	if dead.side == Character.Side.PLAYER and not dead.is_captain \
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
	state.log_event("%s leaps the rail and takes the prow himself." % captain.display_name)


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
		"fresh_men_forward", "shift_larboard", "shift_starboard", "step_up":
			var moved := _apply_call(tactic)
			match tactic:
				"fresh_men_forward":
					state.log_event("Fresh men to the front — their lines rotate!")
				"shift_larboard", "shift_starboard":
					state.log_event("The enemy line shifts %s." %
							("larboard" if tactic == "shift_larboard" else "starboard")
							if moved else "The call to shift goes up, but the line has nowhere to go.")
				"step_up":
					state.log_event("Defenders step up into the gaps in their front line."
							if moved else "The defenders hold — no gaps to fill.")
		_:
			state.log_event("The enemy presses the attack.")


## The captain's calls are formation moves (docs/lines-redesign.md phase C):
## the same verbs the player's cards use, applied to the enemy grid. Shared
## between resolution and the forecast's preview. Larboard slides toward
## column 0, starboard away. Returns whether anyone actually moved.
func _apply_call(tactic: String) -> bool:
	match tactic:
		"fresh_men_forward":
			state.enemy_formation.swap_lines()
			return not state.enemy_formation.is_empty()
		"shift_larboard":
			return state.enemy_formation.shift(-1)
		"shift_starboard":
			return state.enemy_formation.shift(1)
		"step_up":
			return state.enemy_formation.step_up()
	return false


## An enemy with a wind-up rhythm: the berserker's heavy cleave, the
## archer's aimed double shot. Player characters never carry timers —
## wind-ups are the enemy's telegraph layer (phase C ruling).
func _windup_role(c: Character) -> bool:
	return c.side == Character.Side.ENEMY \
			and (c.is_berserker or c.weapon.kind == Weapon.Kind.BOW)


## The end-of-enemy-turn tick: counters run only while fielded, restart on
## arrival and after firing (dodged or landed alike). An archer reaching 0
## locks his mark now — one full player turn of warning before the arrows.
func _advance_windups() -> void:
	for c in state.fielded(Character.Side.ENEMY):
		if not _windup_role(c):
			continue
		if c.windup <= 0:
			state.archer_marks.erase(c)
			c.windup = BattleState.WINDUP_PERIOD - 1
			continue
		c.windup -= 1
		if c.windup != 0:
			continue
		if _is_sniper(c):
			var mark := _weakest_fielded(state.player_formation)
			if mark != null:
				state.archer_marks[c] = mark
				state.log_event("%s marks %s — the next arrows are his." %
						[c.display_name, mark.display_name])
		elif c.is_berserker:
			state.log_event("%s begins the wind-up for a terrible blow." % c.display_name)


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
