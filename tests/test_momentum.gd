extends TestCase
## The momentum economy: income, kill rewards, cap, commits.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY


func test_turn_start_income() -> void:
	var crew := TestHelpers.grunt(P, "crew")
	var eng := TestHelpers.engine_for({"player_field": [crew]})
	await eng._player_turn()
	assert_eq(eng.state.momentum, 1, "+1 at the start of the player turn")


func test_kill_grants_momentum() -> void:
	var strong := TestHelpers.grunt(P, "strong", 12, 6, 10, 3)
	var weak := TestHelpers.grunt(E, "weak", 1, 6)
	var eng := TestHelpers.engine_for({"player_field": [strong], "enemy_field": [weak]})
	await eng._fight_phase(P)
	assert_eq(eng.state.momentum, 2, "+2 for the kill — sniping the right man is the tempo engine")


func test_war_cry_doubles_kill_income() -> void:
	var strong := TestHelpers.grunt(P, "strong", 12, 6, 10, 3)
	var weak := TestHelpers.grunt(E, "weak", 1, 6)
	var eng := TestHelpers.engine_for({"player_field": [strong], "enemy_field": [weak]})
	eng.state.war_cry_active = true
	await eng._fight_phase(P)
	assert_eq(eng.state.momentum, 3, "war cry adds +1 on top of the kill bounty")


func test_momentum_cap() -> void:
	var eng := TestHelpers.engine_for({})
	eng._gain_momentum(25)
	assert_eq(eng.state.momentum, 10, "capped at 10")


func test_commit_reserve_costs_momentum() -> void:
	var crew := TestHelpers.grunt(P, "crew")
	var eng := TestHelpers.engine_for({"player_reserve": [crew]})
	eng._commit_reserve(crew)
	assert_true(eng.state.player_reserve.has(crew), "no momentum, no commit")
	eng.state.momentum = 1
	eng._commit_reserve(crew)
	assert_true(eng.state.player_formation.has(crew))
	assert_eq(eng.state.momentum, 0)
