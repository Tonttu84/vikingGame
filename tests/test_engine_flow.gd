extends TestCase
## Whole-battle behavior: termination, win/loss conditions, determinism,
## and the async controller contract the UI relies on.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY


## A controller that suspends on player input, like the UI does: every
## decision waits on a signal before ending the turn.
class AsyncBot:
	signal decided
	var decisions_awaited := 0

	func choose_action(_state: BattleState) -> Dictionary:
		decisions_awaited += 1
		await decided
		return {"op": "end"}

	func choose_reaction_save(_state: BattleState, _dying: Character) -> bool:
		return false


## A bot exposing the optional pace() hook the UI uses to animate steps.
class PacedBot:
	var paces := 0

	func choose_action(_state: BattleState) -> Dictionary:
		return {"op": "end"}

	func choose_reaction_save(_state: BattleState, _dying: Character) -> bool:
		return false

	func pace(_state: BattleState) -> void:
		paces += 1


func test_full_battle_completes() -> void:
	var eng := TestHelpers.engine_for(Scenarios.default_skirmish(), Bots.NoCardBot.new(), 42)
	var result: Dictionary = await eng.run()
	assert_true(result["outcome"] != "NONE", "the battle resolves")
	assert_true(result["turns"] <= 60)


func test_victory_when_enemy_captain_falls() -> void:
	var p1 := TestHelpers.grunt(P, "p1", 12, 6, 10, 3)
	var cap := TestHelpers.captain_of(E, "cap", 1)
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_captain": cap})
	await eng._fight_phase(P)
	assert_eq(eng.outcome, CombatEngine.Outcome.VICTORY)


func test_defeat_when_player_captain_falls() -> void:
	var cap := TestHelpers.captain_of(P, "cap", 1)
	var e1 := TestHelpers.grunt(E, "e1", 12, 6, 10, 3)
	var eng := TestHelpers.engine_for({"player_field": [cap], "enemy_field": [e1]})
	await eng._fight_phase(E)
	assert_eq(eng.outcome, CombatEngine.Outcome.DEFEAT)


func test_engine_suspends_until_async_controller_decides() -> void:
	var bot := AsyncBot.new()
	var eng := TestHelpers.engine_for(Scenarios.default_skirmish(), bot, 42)
	eng.call("run")
	assert_eq(bot.decisions_awaited, 1, "engine is parked on the first decision, not barreling ahead")
	var guard := 0
	while eng.outcome == CombatEngine.Outcome.NONE and guard < 500:
		guard += 1
		bot.decided.emit()
	assert_true(eng.outcome != CombatEngine.Outcome.NONE, "battle resolves once input arrives")


func test_engine_paces_controllers_that_ask_for_it() -> void:
	var bot := PacedBot.new()
	var eng := TestHelpers.engine_for(Scenarios.default_skirmish(), bot, 42)
	eng.call("run")
	assert_true(bot.paces > 0, "pace() is awaited between resolution steps")


func test_same_seed_same_battle() -> void:
	var results: Array[Dictionary] = []
	var logs: Array = []
	for i in 2:
		var bot_rng := RandomNumberGenerator.new()
		bot_rng.seed = 5
		var eng := TestHelpers.engine_for(Scenarios.default_skirmish(), Bots.RandomBot.new(bot_rng), 99)
		results.append(await eng.run())
		logs.append(eng.state.battle_log)
	assert_eq(results[0], results[1], "identical summary")
	assert_eq(logs[0], logs[1], "identical turn-by-turn log")
