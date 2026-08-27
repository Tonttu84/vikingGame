extends TestCase
## Morale: death waves, routs, cascades, immunities.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY


func test_death_shakes_the_line() -> void:
	var e1 := TestHelpers.grunt(E, "e1")
	var e2 := TestHelpers.grunt(E, "e2")
	var e3 := TestHelpers.grunt(E, "e3")
	var eng := TestHelpers.engine_for({"enemy_field": [e1, e2, e3]})
	e1.hp = 0
	await eng._handle_death(e1)
	assert_eq(e2.morale, 4, "death costs the fielded line 2 morale")
	assert_eq(e3.morale, 4)
	assert_eq(eng.state.momentum, 1, "an enemy death grants momentum")


func test_rout_at_zero_morale() -> void:
	var e1 := TestHelpers.grunt(E, "e1")
	var e2 := TestHelpers.grunt(E, "e2", 12, 2)
	var e3 := TestHelpers.grunt(E, "e3")
	var eng := TestHelpers.engine_for({"enemy_field": [e1, e2, e3]})
	e1.hp = 0
	await eng._handle_death(e1)
	assert_true(eng.state.enemy_routed.has(e2), "morale 2 - 2 = 0 routs")
	assert_false(eng.state.enemy_formation.has(e2))
	assert_true(e2.shaken)
	assert_eq(e3.morale, 3, "-2 from the death, -1 from the rout")


func test_rout_cascade() -> void:
	var e1 := TestHelpers.grunt(E, "e1")
	var e2 := TestHelpers.grunt(E, "e2", 12, 2)
	var e3 := TestHelpers.grunt(E, "e3", 12, 3)
	var eng := TestHelpers.engine_for({"enemy_field": [e1, e2, e3]})
	e1.hp = 0
	await eng._handle_death(e1)
	assert_true(eng.state.enemy_routed.has(e2))
	assert_true(eng.state.enemy_routed.has(e3), "e3 at 3 - 2 - 1 = 0 routs in the cascade")
	assert_true(eng.state.enemy_formation.is_empty())


func test_berserker_immune_to_morale() -> void:
	var e1 := TestHelpers.grunt(E, "e1")
	var berserk := TestHelpers.grunt(E, "berserk", 10, 1, 5, 4)
	berserk.is_berserker = true
	var eng := TestHelpers.engine_for({"enemy_field": [e1, berserk]})
	e1.hp = 0
	await eng._handle_death(e1)
	assert_eq(berserk.morale, 1, "berserkers do not feel fear")
	assert_true(eng.state.enemy_formation.has(berserk))


func test_captains_never_rout_and_player_routs_flee() -> void:
	var cap := TestHelpers.captain_of(P, "cap")
	var crew1 := TestHelpers.grunt(P, "crew1", 12, 1)
	var crew2 := TestHelpers.grunt(P, "crew2")
	var eng := TestHelpers.engine_for({"player_field": [cap, crew1, crew2]})
	crew2.hp = 0
	await eng._handle_death(crew2)
	assert_true(eng.state.player_fled.has(crew1), "shaken crew flees back to the ship")
	assert_true(eng.state.player_formation.has(cap), "the captain holds whatever his morale")
	assert_eq(eng.state.momentum, 0, "own deaths grant no momentum")
