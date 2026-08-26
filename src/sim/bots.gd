class_name Bots
extends RefCounted
## Headless controllers for the sim harness and tests.


## Plays no cards at all — the "no-card baseline" floor metric from
## docs/combat-design.md. It never acts.
class NoCardBot:
	func choose_action(_state: BattleState) -> Dictionary:
		return {"op": "end"}


## Plays random affordable cards with simple deterministic target heuristics.
## Deliberately dumb: it exists to exercise the rules and set a floor, not to
## play well.
class RandomBot:
	var rng: RandomNumberGenerator

	func _init(p_rng: RandomNumberGenerator) -> void:
		rng = p_rng

	func choose_maneuver(_state: BattleState, options: Array[CardData]) -> CardData:
		return options[rng.randi_range(0, options.size() - 1)]

	func choose_action(state: BattleState) -> Dictionary:
		# Crossing men is the highest priority: play Reinforce whenever the
		# rail has room, fall back to the momentum commit if the hand lacks one.
		var can_cross := state.player_field.size() < BattleState.PLAYER_FIELD_CAP \
				and _has_meleer_in_reserve(state)
		if can_cross:
			for card in state.hand:
				if card.id == "reinforce" and card.cost <= state.momentum:
					return {"op": "play", "card": card, "target": _crosser_for(state)}
			if state.player_field.size() < 3 and state.momentum >= 2:
				return {"op": "commit", "character": _crosser_for(state)}
		var playable: Array[CardData] = []
		for card in state.hand:
			if not card.playable or card.reaction_save or card.cost > state.momentum:
				continue
			if card.target_type != CardData.TargetType.NONE and _target_for(card, state) == null:
				continue
			playable.append(card)
		if playable.is_empty():
			return {"op": "end"}
		if rng.randf() < 0.2:
			return {"op": "end"}
		var card: CardData = playable[rng.randi_range(0, playable.size() - 1)]
		return {"op": "play", "card": card, "target": _target_for(card, state)}

	func _has_meleer_in_reserve(state: BattleState) -> bool:
		return _crosser_for(state) != null

	func _crosser_for(state: BattleState) -> Character:
		for c in state.player_reserve:
			if c.weapon.kind != Weapon.Kind.BOW:
				return c
		return null

	func _target_for(card: CardData, state: BattleState) -> Character:
		match card.target_type:
			CardData.TargetType.ENEMY:
				if state.enemy_captain_targetable():
					return state.enemy_captain
				var best: Character = null
				for c in state.enemy_field:
					if best == null or c.hp < best.hp:
						best = c
				return best
			CardData.TargetType.ALLY:
				var pick: Character = null
				for c in state.player_field:
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
