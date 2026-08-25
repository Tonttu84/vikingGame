class_name CombatEngine
extends RefCounted
## The boarding-action rules engine. Headless, deterministic given a seed,
## UI-free: a controller object supplies decisions (bot, test script, or —
## later — the player through the UI).
##
## Controller contract (duck-typed):
##   choose_action(state: BattleState) -> Dictionary
##     {"op": "play", "card": CardData, "target": Character (optional)}
##     {"op": "scrap", "card": CardData}
##     {"op": "commit", "character": Character}
##     {"op": "retreat"} | {"op": "end"}
##   choose_reaction_save(state: BattleState, dying: Character) -> bool
##     asked when a non-captain fighter would die and a reaction-save card
##     (Drag Him Back!) is in hand and affordable.
##
## Both calls are awaited, so a controller may suspend (e.g. the UI waiting
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


func setup(scenario: Dictionary, p_controller, seed_value: int) -> void:
	controller = p_controller
	rng.seed = seed_value
	state = BattleState.new()
	for c: Character in scenario.get("player_field", []):
		_register(c, state.player_field)
		if c.is_captain:
			state.player_captain = c
	for c: Character in scenario.get("player_reserve", []):
		_register(c, state.player_reserve)
	for c: Character in scenario.get("enemy_field", []):
		_register(c, state.enemy_field)
	for c: Character in scenario.get("enemy_reserve", []):
		_register(c, state.enemy_reserve)
	state.enemy_captain = scenario.get("enemy_captain")
	if state.enemy_captain != null:
		state.enemy_captain.order_id = _next_order_id()
	var deck: Array[CardData] = []
	deck.assign(scenario.get("deck", []))
	state.deck = deck
	_shuffle(state.deck)
	enemy_tactics.assign(scenario.get("enemy_tactics", ["press_the_attack"]))
	state.next_tactic = _pick_tactic()
	state.artifacts.assign(scenario.get("artifacts", []))
	_apply_battle_start_artifacts()


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
						for c in state.enemy_field:
							_deal_morale_damage(c, artifact.amount)
						_check_routs(Character.Side.ENEMY)
					ArtifactData.EffectType.ALLY_MORALE_BONUS:
						for c in state.player_field:
							c.max_morale += artifact.amount
							c.morale += artifact.amount
						for c in state.player_reserve:
							c.max_morale += artifact.amount
							c.morale += artifact.amount


func run() -> Dictionary:
	while outcome == Outcome.NONE and state.turn < MAX_TURNS:
		state.turn += 1
		await _player_turn()
		if outcome == Outcome.NONE:
			await _enemy_turn()
	if outcome == Outcome.NONE:
		outcome = Outcome.STALEMATE
	return summary()


func summary() -> Dictionary:
	return {
		"outcome": Outcome.keys()[outcome],
		"turns": state.turn,
		"player_dead": state.player_dead.size(),
		"player_fled": state.player_fled.size(),
		"player_survivors": state.player_field.size() + state.player_reserve.size(),
		"enemy_dead": state.enemy_dead.size(),
		"enemy_routed": state.enemy_routed.size(),
		"momentum_left": state.momentum,
	}


# --- Turn flow ---------------------------------------------------------------

func _player_turn() -> void:
	state.scrapped_this_turn = false
	state.shield_wall_active = false
	state.war_cry_active = false
	_gain_momentum(1)
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
	state.captain_forced_exposed = false
	state.focus_target = null
	for c in state.player_field:
		c.bonus_attacks = 0
	for c in state.player_reserve:
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
	state.duel_active = false
	state.next_tactic = _pick_tactic()


# --- Player actions ----------------------------------------------------------

func _apply_action(action: Dictionary) -> void:
	match action.get("op", "end"):
		"play":
			await _play_card(action.get("card"), action.get("target"))
		"scrap":
			_scrap_card(action.get("card"))
		"commit":
			_commit_reserve(action.get("character"))
		"retreat":
			outcome = Outcome.RETREAT
			state.log_event("The crew cuts the ropes and falls back.")


func _play_card(card: CardData, target: Character) -> void:
	if card == null or not state.hand.has(card) or not card.playable:
		return
	if card.cost > state.momentum:
		return
	if card.target_type != CardData.TargetType.NONE and target == null:
		return
	state.momentum -= card.cost
	state.hand.erase(card)
	state.discard.append(card)
	state.log_event("Played %s." % card.display_name)
	for effect in card.effects:
		await _apply_effect(effect, target)
		if outcome != Outcome.NONE:
			return


func _apply_effect(effect: Dictionary, target: Character) -> void:
	var amount: int = effect.get("amount", 0)
	match effect.get("type"):
		CardData.EffectType.DAMAGE_ALL_ENEMIES:
			# Card damage is true damage: volleys and thrown cargo ignore armor.
			for c in state.enemy_field.duplicate():
				await _deal_true_damage(c, amount)
				if outcome != Outcome.NONE:
					return
		CardData.EffectType.MORALE_DAMAGE_ALL_ENEMIES:
			for c in state.enemy_field.duplicate():
				_deal_morale_damage(c, amount)
			_check_routs(Character.Side.ENEMY)
		CardData.EffectType.HEAL:
			target.hp = mini(target.max_hp, target.hp + amount)
		CardData.EffectType.FOCUS_FIRE:
			state.focus_target = target
		CardData.EffectType.SHIELD_WALL:
			state.shield_wall_active = true
		CardData.EffectType.PULL_TO_RESERVE:
			if state.player_field.has(target) and not target.is_captain:
				state.player_field.erase(target)
				state.player_reserve.append(target)
				target.engaged_with = null
		CardData.EffectType.EXPOSE_CAPTAIN:
			state.captain_forced_exposed = true
		CardData.EffectType.DUEL:
			state.duel_active = true
		CardData.EffectType.BLOCK_REINFORCEMENTS:
			state.block_reinforcements = true
		CardData.EffectType.EXTRA_ATTACK:
			target.bonus_attacks += amount
		CardData.EffectType.DRAW:
			_draw(amount)
		CardData.EffectType.WAR_CRY:
			state.war_cry_active = true


func _scrap_card(card: CardData) -> void:
	if card == null or not state.hand.has(card) or state.scrapped_this_turn:
		return
	state.scrapped_this_turn = true
	state.hand.erase(card)
	state.discard.append(card)
	_gain_momentum(card.scrap_value)
	state.log_event("Scrapped %s for %d momentum." % [card.display_name, card.scrap_value])


func _commit_reserve(character: Character) -> void:
	if character == null or not state.player_reserve.has(character):
		return
	if state.momentum < BattleState.RESERVE_COMMIT_COST:
		return
	state.momentum -= BattleState.RESERVE_COMMIT_COST
	state.player_reserve.erase(character)
	state.player_field.append(character)
	state.log_event("%s joins the boarding party." % character.display_name)


# --- Fighting ----------------------------------------------------------------

func _fight_phase(side: Character.Side) -> void:
	var attackers := _attack_order(side)
	for attacker in attackers:
		if outcome != Outcome.NONE:
			return
		if not attacker.is_alive() or not _is_deployed(attacker):
			continue
		var swings := 1 + attacker.bonus_attacks
		attacker.bonus_attacks = 0
		for i in swings:
			if outcome != Outcome.NONE or not attacker.is_alive():
				return
			var target := _pick_target(attacker)
			if target == null:
				break
			await _attack(attacker, target)
			await _pace()


## Deterministic resolution order: speed descending, spawn order as tiebreak.
## During a duel only the captains fight.
func _attack_order(side: Character.Side) -> Array[Character]:
	if state.duel_active:
		var duelist := state.player_captain if side == Character.Side.PLAYER else state.enemy_captain
		var result: Array[Character] = []
		if duelist != null:
			result.append(duelist)
		return result
	var attackers: Array[Character] = []
	attackers.append_array(state.fielded(side))
	for c in state.reserve_of(side):
		if c.weapon.kind == Weapon.Kind.BOW:
			attackers.append(c)
	if side == Character.Side.ENEMY and state.enemy_captain != null \
			and state.enemy_captain.is_alive() \
			and state.enemy_field.size() <= BattleState.CAPTAIN_EXPOSED_FIELD_SIZE:
		attackers.append(state.enemy_captain)
	attackers.sort_custom(func(a: Character, b: Character) -> bool:
		if a.speed != b.speed:
			return a.speed > b.speed
		return a.order_id < b.order_id)
	return attackers


func _is_deployed(c: Character) -> bool:
	if c == state.enemy_captain:
		return true
	if state.player_field.has(c) or state.enemy_field.has(c):
		return true
	# Bows shoot from the reserve rows.
	return c.weapon.kind == Weapon.Kind.BOW \
			and (state.player_reserve.has(c) or state.enemy_reserve.has(c))


## Deterministic targeting, published rules (docs/combat-design.md):
## duel > forced focus > kept engagement > exposed enemy captain (player side)
## > first unengaged opposing fielded character > front-most. Never random.
func _pick_target(attacker: Character) -> Character:
	if state.duel_active:
		return state.enemy_captain if attacker.side == Character.Side.PLAYER else state.player_captain
	if attacker.side == Character.Side.PLAYER and state.focus_target != null \
			and state.focus_target.is_alive() and _is_targetable_enemy(state.focus_target):
		return state.focus_target
	if _engagement_valid(attacker):
		return attacker.engaged_with
	if attacker.side == Character.Side.PLAYER and state.enemy_captain_targetable():
		return state.enemy_captain
	var opposing := state.opposing_field(attacker.side)
	for c in opposing:
		if c.is_alive() and not state.is_engaged_by(attacker.side, c):
			return c
	for c in opposing:
		if c.is_alive():
			return c
	if attacker.side == Character.Side.PLAYER and state.enemy_captain_targetable():
		return state.enemy_captain
	return null


func _is_targetable_enemy(c: Character) -> bool:
	if c == state.enemy_captain:
		return state.enemy_captain_targetable()
	return state.enemy_field.has(c)


func _engagement_valid(attacker: Character) -> bool:
	var t := attacker.engaged_with
	if t == null or not t.is_alive():
		return false
	if t.side == attacker.side:
		return false
	if t == state.enemy_captain:
		return state.enemy_captain_targetable()
	return state.opposing_field(attacker.side).has(t)


func _attack(attacker: Character, defender: Character) -> void:
	var dmg := attacker.damage_against(defender)
	if defender.side == Character.Side.PLAYER and state.shield_wall_active:
		dmg = maxi(1, dmg - 2)
	attacker.engaged_with = defender
	if defender.engaged_with == null or not defender.engaged_with.is_alive():
		defender.engaged_with = attacker
	defender.hp -= dmg
	state.log_event("%s hits %s for %d (%d HP left)." %
			[attacker.display_name, defender.display_name, dmg, maxi(0, defender.hp)])
	if defender.hp <= 0:
		await _handle_death(defender)


## Card/tactic damage that bypasses armor and engagement.
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


# --- Death, morale and routing ----------------------------------------------

func _handle_death(dead: Character) -> void:
	# Reaction window: Drag Him Back! cancels the killing blow on a crew member.
	if dead.side == Character.Side.PLAYER and not dead.is_captain and state.player_field.has(dead):
		var save := _affordable_reaction_save()
		if save != null and await controller.choose_reaction_save(state, dead):
			state.momentum -= save.cost
			state.hand.erase(save)
			state.discard.append(save)
			dead.hp = 1
			state.player_field.erase(dead)
			state.player_reserve.append(dead)
			dead.engaged_with = null
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
	state.fielded(side).erase(dead)
	state.reserve_of(side).erase(dead)
	if side == Character.Side.PLAYER:
		state.player_dead.append(dead)
	else:
		state.enemy_dead.append(dead)
		_gain_momentum(1)
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
	state.fielded(side).erase(c)
	c.shaken = true
	c.engaged_with = null
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
			for c in state.player_field.duplicate():
				await _deal_true_damage(c, 1)
				if outcome != Outcome.NONE:
					return
		"fear_horn":
			state.log_event("A war horn moans across the deck.")
			for c in state.player_field.duplicate():
				_deal_morale_damage(c, 1)
			_check_routs(Character.Side.PLAYER)
		"reinforcement_surge":
			state.surge_active = true
			state.log_event("The enemy captain roars for every hand on deck.")
		_:
			state.log_event("The enemy presses the attack.")


func _reinforce() -> void:
	if state.block_reinforcements:
		state.block_reinforcements = false
		state.log_event("Enemy reinforcements are pushed back at the rail.")
		return
	var rate := BattleState.SURGE_REINFORCE_RATE if state.surge_active else BattleState.REINFORCE_RATE
	var moved := 0
	while moved < rate and not state.enemy_reserve.is_empty() \
			and state.enemy_field.size() < BattleState.ENEMY_FIELD_CAP:
		var c: Character = state.enemy_reserve.pop_front()
		state.enemy_field.append(c)
		moved += 1
		state.log_event("%s steps over the rail." % c.display_name)


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


func _register(c: Character, into: Array[Character]) -> void:
	c.order_id = _next_order_id()
	into.append(c)


func _next_order_id() -> int:
	_order_counter += 1
	return _order_counter
