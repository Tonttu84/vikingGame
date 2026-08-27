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
static func station(formation: Formation, c: Character, line: int, col: int) -> void:
	formation.remove(c)
	formation.place(c, line, col)
