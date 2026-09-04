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
	## The engine whose legality queries this bot asks before it proposes a
	## play — the same questions the UI asks, so no rule is re-derived here.
	## Left unset (older harnesses) the bot falls back to its own cheap checks
	## and simply wastes an action whenever the engine refuses a card.
	## Held WEAKLY: the engine holds its controller, so a strong link back
	## would close a RefCounted cycle and leak every battle of a long sim.
	var _engine_ref: WeakRef = null
	var engine:
		set(value):
			_engine_ref = weakref(value) if value != null else null
		get:
			return _engine_ref.get_ref() if _engine_ref != null else null

	func _init(p_rng: RandomNumberGenerator) -> void:
		rng = p_rng

	func choose_maneuver(_state: BattleState, options: Array[CardData]) -> CardData:
		return options[rng.randi_range(0, options.size() - 1)]

	## Movement riders are mandatory; the bot only picks which legal move,
	## uniformly at random from its own seeded rng (never randi()).
	func choose_rider(_state: BattleState, _card: CardData,
			moves: Array[Dictionary]) -> Dictionary:
		return moves[rng.randi_range(0, moves.size() - 1)]

	## The engine's bite on this bot, measured where it lands: of the cards it
	## could AFFORD, how many were refused (the rider gate AND the bot's own
	## random targeting — a Taunt proposed at a bad anchor counts), and how
	## many decision points offered nothing at all. The retune's headline
	## metric; read it as a bot-proposal rate, not a pure gate rate.
	var affordable_seen := 0
	var gate_refused := 0
	var decision_points := 0
	var empty_decision_points := 0

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
		decision_points += 1
		for card in state.hand:
			if not card.playable or card.reaction_save or card.cost > state.momentum:
				continue
			affordable_seen += 1
			if not _card_usable(card, state):
				gate_refused += 1
				continue
			playable.append(card)
		if playable.is_empty():
			empty_decision_points += 1
			return {"op": "end"}
		if rng.randf() < 0.2:
			return {"op": "end"}
		var card: CardData = playable[rng.randi_range(0, playable.size() - 1)]
		return {"op": "play", "card": card, "target": _target_for(card, state)}

	## Skip cards the engine would refuse, so the bot never spins on them.
	## Since the rider gate landed this is not a nicety: a card can be
	## unplayable because of where your own men stand, and a bot that keeps
	## offering one burns its turn instead of making a decision.
	func _card_usable(card: CardData, state: BattleState) -> bool:
		var target := _target_for(card, state)
		if card.target_type != CardData.TargetType.NONE and target == null:
			return false
		return engine.can_play(card, target) if engine != null else true

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
