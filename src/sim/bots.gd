class_name Bots
extends RefCounted
## Headless controllers for the sim harness and tests.


## Plays no cards at all — the "no-card baseline" floor metric from
## docs/combat-design.md. It never acts.
class NoCardBot:
	func choose_action(_state: BattleState) -> Dictionary:
		return {"op": "end"}


## Plays random affordable cards with simple deterministic target heuristics
## and random-but-legal slot placement. Deliberately dumb: it exists to
## exercise the rules and set a floor, not to play well.
class RandomBot:
	var rng: RandomNumberGenerator

	func _init(p_rng: RandomNumberGenerator) -> void:
		rng = p_rng

	func choose_maneuver(_state: BattleState, options: Array[CardData]) -> CardData:
		return options[rng.randi_range(0, options.size() - 1)]

	## Movement riders are mandatory; the bot only picks which legal move,
	## uniformly at random from its own seeded rng (never randi()).
	func choose_rider(_state: BattleState, _card: CardData,
			moves: Array[Dictionary]) -> Dictionary:
		return moves[rng.randi_range(0, moves.size() - 1)]

	func choose_action(state: BattleState) -> Dictionary:
		# Crossing men is the highest priority: play Reinforce whenever the
		# grid has room, fall back to the momentum commit if the hand lacks one.
		var crosser := _crosser_for(state)
		if not state.player_formation.is_full() and crosser != null:
			for card in state.hand:
				if card.id == "reinforce" and card.cost <= state.momentum:
					return {"op": "play", "card": card, "target": crosser,
							"slot": _random_free_slot(state)}
			if state.player_formation.size() < 3 and state.momentum >= 2:
				return {"op": "commit", "character": crosser, "slot": _random_free_slot(state)}
		var playable: Array[CardData] = []
		for card in state.hand:
			if not card.playable or card.reaction_save or card.cost > state.momentum:
				continue
			if not _card_usable(card, state):
				continue
			playable.append(card)
		if playable.is_empty():
			return {"op": "end"}
		if rng.randf() < 0.2:
			return {"op": "end"}
		var card: CardData = playable[rng.randi_range(0, playable.size() - 1)]
		return {"op": "play", "card": card, "target": _target_for(card, state)}

	## Skip cards the engine would refuse, so the bot never spins on them.
	func _card_usable(card: CardData, state: BattleState) -> bool:
		for effect in card.effects:
			if effect.get("type") == CardData.EffectType.CHALLENGE:
				if state.player_captain == null \
						or not state.player_formation.has(state.player_captain):
					return false
				if state.enemy_captain == null \
						or not state.enemy_formation.has(state.enemy_captain):
					return false
		if card.target_type != CardData.TargetType.NONE and _target_for(card, state) == null:
			return false
		return true

	func _random_free_slot(state: BattleState) -> int:
		var free: Array[int] = []
		for i in Formation.SLOT_COUNT:
			if state.player_formation.slots[i] == null:
				free.append(i)
		return -1 if free.is_empty() else free[rng.randi_range(0, free.size() - 1)]

	func _crosser_for(state: BattleState) -> Character:
		# Meleers first; an archer crosses only when no one else is left
		# (he still needs a second-line slot to matter — random placement
		# keeps the bot honest about how dumb it is). The prow pair never
		# crosses this way — the engine would refuse and the bot would spin.
		for c in state.player_reserve:
			if _pair_member(c, state):
				continue
			if c.weapon.kind != Weapon.Kind.BOW:
				return c
		for c in state.player_reserve:
			if not _pair_member(c, state):
				return c
		return null

	func _pair_member(c: Character, state: BattleState) -> bool:
		return state.player_prowman != null \
				and (c == state.player_captain or c == state.player_prowman)

	func _target_for(card: CardData, state: BattleState) -> Character:
		match card.target_type:
			CardData.TargetType.ENEMY:
				if card.id == "break_the_line":
					return _shove_target(state)
				if state.enemy_captain != null \
						and state.enemy_formation.has(state.enemy_captain):
					return state.enemy_captain
				var best: Character = null
				for c in state.fielded(Character.Side.ENEMY):
					if best == null or c.hp < best.hp:
						best = c
				return best
			CardData.TargetType.ALLY:
				var pick: Character = null
				for c in state.fielded(Character.Side.PLAYER):
					match card.id:
						"rally":
							if c.hp < c.max_hp and (pick == null or c.hp < pick.hp):
								pick = c
						"swap":
							# Only rotate someone genuinely worn down, and only
							# if there is a fresh man to bring across.
							if not c.is_captain and c.hp * 2 < c.max_hp \
									and not state.player_reserve.is_empty() \
									and (pick == null or c.hp < pick.hp):
								pick = c
						_:
							if not c.is_captain and (pick == null or c.strength > pick.strength):
								pick = c
				return pick
		return null

	## Any enemy front-liner with an open front slot beside him.
	func _shove_target(state: BattleState) -> Character:
		var f := state.enemy_formation
		for c in state.fielded(Character.Side.ENEMY):
			if f.line_of(c) != Formation.FRONT:
				continue
			var col := f.column_of(c)
			if (col > 0 and f.at(Formation.FRONT, col - 1) == null) \
					or (col < Formation.COLUMNS - 1 and f.at(Formation.FRONT, col + 1) == null):
				return c
		return null
