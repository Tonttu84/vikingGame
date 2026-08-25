extends TestCase
## Deterministic targeting and captain exposure rules.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY


func test_keeps_current_engagement() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1")
	var e2 := TestHelpers.grunt(E, "e2")
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1, e2]})
	p1.engaged_with = e2
	assert_eq(eng._pick_target(p1), e2, "stay on your man, not the front-most")


func test_spreads_to_unengaged_enemies() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var p2 := TestHelpers.grunt(P, "p2")
	var e1 := TestHelpers.grunt(E, "e1", 30)
	var e2 := TestHelpers.grunt(E, "e2", 30)
	# Reserve present so the two-man field does not expose a (nonexistent) captain.
	var eng := TestHelpers.engine_for({"player_field": [p1, p2], "enemy_field": [e1, e2]})
	assert_eq(eng._pick_target(p1), e1, "front-most first")
	eng._attack(p1, e1)
	assert_eq(eng._pick_target(p2), e2, "second attacker takes the unengaged enemy")


func test_captain_hidden_behind_the_line() -> void:
	var cap := TestHelpers.captain_of(E, "cap")
	var eng := TestHelpers.engine_for({
		"enemy_field": [TestHelpers.grunt(E, "e1"), TestHelpers.grunt(E, "e2"), TestHelpers.grunt(E, "e3")],
		"enemy_reserve": [TestHelpers.grunt(E, "r1")],
		"enemy_captain": cap,
	})
	assert_false(eng.state.enemy_captain_targetable(), "3 fielded + reserves = protected")


func test_captain_exposed_when_line_thins() -> void:
	var cap := TestHelpers.captain_of(E, "cap")
	var eng := TestHelpers.engine_for({
		"enemy_field": [TestHelpers.grunt(E, "e1"), TestHelpers.grunt(E, "e2")],
		"enemy_reserve": [TestHelpers.grunt(E, "r1")],
		"enemy_captain": cap,
	})
	assert_true(eng.state.enemy_captain_targetable(), "field of 2 exposes him")


func test_captain_exposed_when_reserves_spent() -> void:
	var cap := TestHelpers.captain_of(E, "cap")
	var eng := TestHelpers.engine_for({
		"enemy_field": [TestHelpers.grunt(E, "e1"), TestHelpers.grunt(E, "e2"), TestHelpers.grunt(E, "e3")],
		"enemy_captain": cap,
	})
	assert_true(eng.state.enemy_captain_targetable(), "an empty reserve pool exposes him")


func test_forced_exposure() -> void:
	var cap := TestHelpers.captain_of(E, "cap")
	var eng := TestHelpers.engine_for({
		"enemy_field": [TestHelpers.grunt(E, "e1"), TestHelpers.grunt(E, "e2"), TestHelpers.grunt(E, "e3")],
		"enemy_reserve": [TestHelpers.grunt(E, "r1")],
		"enemy_captain": cap,
	})
	eng.state.captain_forced_exposed = true
	assert_true(eng.state.enemy_captain_targetable(), "Break the Line opens the window")


func test_unengaged_attacker_goes_for_exposed_captain() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var p2 := TestHelpers.grunt(P, "p2")
	var e1 := TestHelpers.grunt(E, "e1")
	var cap := TestHelpers.captain_of(E, "cap")
	var eng := TestHelpers.engine_for({
		"player_field": [p1, p2],
		"enemy_field": [e1],
		"enemy_captain": cap,
	})
	p1.engaged_with = e1
	assert_eq(eng._pick_target(p1), e1, "the engaged man finishes his fight")
	assert_eq(eng._pick_target(p2), cap, "the free man goes for the head")
