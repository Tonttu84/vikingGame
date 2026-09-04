extends TestCase
## The momentum economy: income, kill rewards, the cap.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY


func test_turn_start_income() -> void:
	var crew := TestHelpers.grunt(P, "crew")
	var eng := TestHelpers.engine_for({"player_field": [crew]})
	await eng._player_turn()
	# +1 for the turn, +1 more because the opening had nothing else to offer
	# a lone man with no ship behind him and took the income (test_turn_choice).
	assert_eq(eng.state.momentum, 2, "+1 at the start of the player turn, +1 from the opening")


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


## The old momentum commit is gone: crossing a man is the turn's opening now
## and costs no momentum at all — it costs the income you did not take
## instead. The rest of that mechanism is tested in test_turn_choice.
func test_the_opening_crossing_drains_no_momentum() -> void:
	var crew := TestHelpers.grunt(P, "crew")
	var eng := TestHelpers.engine_for({"player_field": [TestHelpers.grunt(P, "held")],
			"player_reserve": [crew]})
	eng._apply_opening({"op": "reinforce", "character": crew}, eng.opening_options())
	assert_true(eng.state.player_formation.has(crew), "he comes over for nothing")
	assert_eq(eng.state.momentum, 0, "and the bank is untouched")
