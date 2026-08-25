extends TestCase
## Whole-battle behavior: termination, win/loss conditions, determinism.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY


func test_full_battle_completes() -> void:
	var eng := TestHelpers.engine_for(Scenarios.default_skirmish(), Bots.NoCardBot.new(), 42)
	var result := eng.run()
	assert_true(result["outcome"] != "NONE", "the battle resolves")
	assert_true(result["turns"] <= 60)


func test_victory_when_enemy_captain_falls() -> void:
	var p1 := TestHelpers.grunt(P, "p1", 12, 6, 10, 3)
	var cap := TestHelpers.captain_of(E, "cap", 1)
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_captain": cap})
	eng._fight_phase(P)
	assert_eq(eng.outcome, CombatEngine.Outcome.VICTORY)


func test_defeat_when_player_captain_falls() -> void:
	var cap := TestHelpers.captain_of(P, "cap", 1)
	var e1 := TestHelpers.grunt(E, "e1", 12, 6, 10, 3)
	var eng := TestHelpers.engine_for({"player_field": [cap], "enemy_field": [e1]})
	eng._fight_phase(E)
	assert_eq(eng.outcome, CombatEngine.Outcome.DEFEAT)


func test_same_seed_same_battle() -> void:
	var results: Array[Dictionary] = []
	var logs: Array = []
	for i in 2:
		var bot_rng := RandomNumberGenerator.new()
		bot_rng.seed = 5
		var eng := TestHelpers.engine_for(Scenarios.default_skirmish(), Bots.RandomBot.new(bot_rng), 99)
		results.append(eng.run())
		logs.append(eng.state.battle_log)
	assert_eq(results[0], results[1], "identical summary")
	assert_eq(logs[0], logs[1], "identical turn-by-turn log")
