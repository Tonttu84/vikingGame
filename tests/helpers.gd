class_name TestHelpers
extends RefCounted
## Fixture builders and a scripted controller for engine tests.


class ScriptedBot:
	var queue: Array = []

	func _init(actions: Array = []) -> void:
		queue = actions.duplicate()

	func choose_action(_state: BattleState) -> Dictionary:
		if queue.is_empty():
			return {"op": "end"}
		return queue.pop_front()


static func grunt(side: Character.Side, id: String, hp := 12, morale := 6,
		strength := 3, speed := 3, weapon: Weapon = null, armor := 0) -> Character:
	return Character.new(id, id, side, hp, morale, strength, speed, weapon, armor)


static func captain_of(side: Character.Side, id: String, hp := 20, strength := 4) -> Character:
	var c := Character.new(id, id, side, hp, 10, strength, 4, Weapon.sword(), 2)
	c.is_captain = true
	return c


static func engine_for(scenario: Dictionary, bot = null, seed_value := 7) -> CombatEngine:
	var e := CombatEngine.new()
	e.setup(scenario, bot if bot != null else ScriptedBot.new(), seed_value)
	return e


## Re-station a fielded character on an exact slot (tests build precise
## formations; setup() itself auto-places scenario lists in reading order).
## Refuses loudly instead of dropping the man: a slot already taken used to
## leave him nowhere, and every assertion after a fixture like that is
## measuring a formation the test never meant to build. Trade two men with
## Formation.swap_positions; this only fills a free slot.
## A man whose only job is standing in a front slot so the man behind him
## counts as covered (the relative front line). Pinned hard, so nothing —
## not even his own closing step — walks him off the slot. A pinned man
## still swings, so station him over an EMPTY opposing column whenever the
## damage sums matter.
static func cover_at(eng: CombatEngine, side: Character.Side, col: int,
		id := "cover") -> Character:
	var c := grunt(side, id)
	c.pinned = 99
	station(eng.state.formation_of(side), c, Formation.FRONT, col)
	return c


static func station(formation: Formation, c: Character, line: int, col: int) -> void:
	assert(c != null, "station(): nobody to station")
	var occupant := formation.at(line, col)
	assert(occupant == null or occupant == c,
			"station(): line %d col %d already holds %s" %
			[line, col, occupant.id if occupant != null else "<null>"])
	formation.remove(c)
	var placed := formation.place(c, line, col)
	assert(placed, "station(): could not place %s on line %d col %d" % [c.id, line, col])


## A controller that answers the turn's OPENING (docs/combat-design.md — the
## forced three-way choice at the head of every player turn) from a scripted
## queue, and remembers what it was asked. An exhausted queue answers with
## the income, exactly as a controller without the hook would.
## Holds the engine WEAKLY, like the sim bots do: the engine holds its
## controller, so a strong link back would close a RefCounted cycle.
class OpeningBot:
	var openings: Array = []
	var actions: Array = []
	## One entry per time the engine asked: the options it was legal to give.
	var asked: Array = []
	var _engine_ref: WeakRef = null
	var engine:
		set(value):
			_engine_ref = weakref(value) if value != null else null
		get:
			return _engine_ref.get_ref() if _engine_ref != null else null

	func _init(p_openings: Array = [], p_actions: Array = []) -> void:
		openings = p_openings.duplicate()
		actions = p_actions.duplicate()

	func choose_opening(_state: BattleState) -> Dictionary:
		asked.append(engine.opening_options() if engine != null else [])
		if openings.is_empty():
			return {"op": "income"}
		return openings.pop_front()

	func choose_action(_state: BattleState) -> Dictionary:
		if actions.is_empty():
			return {"op": "end"}
		return actions.pop_front()
