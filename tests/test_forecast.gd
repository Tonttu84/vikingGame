extends TestCase
## The incoming-damage forecast: what every fielded man stands to take in
## the coming fight phases — physical and morale — computed from current
## placements and the telegraphed tactic, so the player never has to add
## it up by squinting at the board. Deterministic, single pass: mid-phase
## deaths are counted as one wave each but cascades and saves are not
## chained — it is a preview of intent, not a simulation.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY
const F := Formation.FRONT
const B := Formation.BACK


func test_column_duel_shows_both_sides() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1", 12, 6, 4, 3)
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	var fc := eng.forecast()
	assert_eq(fc[e1]["hp"], 3, "p1's swing next fight phase")
	assert_eq(fc[p1]["hp"], 4, "e1's answer in theirs")
	assert_eq(fc[p1]["morale"], 0, "nothing threatens morale yet")


func test_empty_column_forecasts_no_damage() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, p1, F, 3)
	var fc := eng.forecast()
	assert_eq(fc[p1]["hp"], 0, "their man swings at air")
	assert_eq(fc[e1]["hp"], 0, "and so does yours")


func test_reach_snipe_and_rail_arrows_are_counted() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e_front := TestHelpers.grunt(E, "e_front", 12, 6, 4, 3)
	var e_spear := TestHelpers.grunt(E, "e_spear", 12, 6, 3, 3, Weapon.spear())
	var e_bow := TestHelpers.grunt(E, "e_bow", 12, 6, 2, 3, Weapon.bow())
	var eng := TestHelpers.engine_for({
		"player_field": [p1],
		"enemy_field": [e_front, e_spear, e_bow],
	})
	TestHelpers.station(eng.state.enemy_formation, e_spear, B, 0)
	TestHelpers.station(eng.state.enemy_formation, e_bow, B, 3)
	p1.hp = 11  # wounded: their archer's mark, and still the column's target
	e_bow.beat = 1
	eng.state.archer_marks[e_bow] = p1
	var fc := eng.forecast()
	assert_eq(fc[p1]["hp"], 4 + 4 + 4, "front man + spear reach + both aimed arrows add up")


func test_telegraphed_arrow_volley_and_shield_wall() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var p2 := TestHelpers.grunt(P, "p2")
	var e1 := TestHelpers.grunt(E, "e1", 12, 6, 4, 3)
	var eng := TestHelpers.engine_for({"player_field": [p1, p2], "enemy_field": [e1]})
	eng.state.next_tactic = "arrow_volley"
	var fc := eng.forecast()
	assert_eq(fc[p1]["hp"], 4 + 1, "the telegraphed volley is part of the bill")
	assert_eq(fc[p2]["hp"], 1, "even for the man no one duels")
	eng.state.shield_wall_active = true
	fc = eng.forecast()
	assert_eq(fc[p1]["hp"], 2, "the wall blocks the volley and blunts the melee hit")
	assert_eq(fc[p2]["hp"], 0)


func test_telegraphed_fear_horn_shows_morale_damage() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var cap := TestHelpers.captain_of(P, "cap")
	var eng := TestHelpers.engine_for({"player_field": [p1, cap]})
	eng.state.next_tactic = "fear_horn"
	var fc := eng.forecast()
	assert_eq(fc[p1]["morale"], 1, "the horn is telegraphed like any tactic")
	assert_eq(fc[cap]["morale"], 0, "captains do not feel fear")


func test_predicted_kills_forecast_the_morale_wave() -> void:
	var strong := TestHelpers.grunt(P, "strong", 12, 6, 10, 3)
	var e_doomed := TestHelpers.grunt(E, "e_doomed", 5)
	var e_witness := TestHelpers.grunt(E, "e_witness")
	var eng := TestHelpers.engine_for({
		"player_field": [strong],
		"enemy_field": [e_doomed, e_witness],
	})
	var fc := eng.forecast()
	assert_true(fc[e_doomed]["hp"] >= e_doomed.hp, "the column kills him on paper")
	assert_eq(fc[e_witness]["morale"], BattleState.DEATH_MORALE_HIT,
			"his death will shake the men beside him")


func test_bonus_attacks_multiply_the_forecast() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1", 30)
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	p1.bonus_attacks = 1
	var fc := eng.forecast()
	assert_eq(fc[e1]["hp"], 6, "Battle Fury's extra swing is already on the bill")


func test_cleave_grazes_are_on_the_bill() -> void:
	var berserk := TestHelpers.grunt(E, "berserk", 10, 1, 5, 4, Weapon.axe())
	berserk.is_berserker = true
	var mark := TestHelpers.grunt(P, "mark", 30)
	var left := TestHelpers.grunt(P, "left")
	var right := TestHelpers.grunt(P, "right")
	var eng := TestHelpers.engine_for({
		"player_field": [left, mark, right],
		"enemy_field": [berserk],
	})
	TestHelpers.station(eng.state.enemy_formation, berserk, F, 1)
	var fc := eng.forecast()
	assert_eq(fc[mark]["hp"], 6, "the main blow")
	assert_eq(fc[left]["hp"], 2, "the graze on the left neighbor is forecast")
	assert_eq(fc[right]["hp"], 2, "and on the right")


func test_rail_volley_forecast_scales_and_reaims() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var bow1 := TestHelpers.grunt(P, "bow1", 10, 5, 2, 3, Weapon.bow())
	var bow2 := TestHelpers.grunt(P, "bow2", 10, 5, 2, 3, Weapon.bow())
	var e1 := TestHelpers.grunt(E, "e1", 30)
	var e2 := TestHelpers.grunt(E, "e2", 2)
	var eng := TestHelpers.engine_for({
		"player_field": [p1],
		"player_reserve": [bow1, bow2],
		"enemy_field": [e1, e2],
	})
	TestHelpers.station(eng.state.enemy_formation, e2, F, 2)
	eng.state.archer_support_damage = 2
	var fc := eng.forecast()
	assert_eq(fc[e2]["hp"], 2, "the first arrow already kills the weakest on paper")
	assert_eq(fc[e1]["hp"], 3 + 2, "so the second is forecast onto the next weakest, atop p1's swing")


func test_rail_volley_forecast_is_zero_with_no_ship_archers() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1", 30)
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	TestHelpers.station(eng.state.enemy_formation, e1, F, 1)
	eng.state.archer_support_damage = 2
	var fc := eng.forecast()
	assert_eq(fc[e1]["hp"], 0, "a silent rail forecasts nothing")
