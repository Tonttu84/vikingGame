extends TestCase
## Enemy dynamics (docs/lines-redesign.md phase C): the captain's calls,
## per-role wind-ups and the telegraph plumbing that lets the player read
## them. Everything deterministic — fixed timers and formation verbs, no dice.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY
const F := Formation.FRONT
const B := Formation.BACK


func _log_has(eng: CombatEngine, needle: String) -> bool:
	for line in eng.state.battle_log:
		if line.contains(needle):
			return true
	return false


# --- Formation verbs: the moves the calls are made of -------------------------

func test_swap_lines_trades_front_and_back_in_every_column() -> void:
	var f := Formation.new()
	var front_man := TestHelpers.grunt(E, "front_man")
	var back_man := TestHelpers.grunt(E, "back_man")
	var loner := TestHelpers.grunt(E, "loner")
	f.place(front_man, F, 0)
	f.place(back_man, B, 0)
	f.place(loner, F, 2)
	f.swap_lines()
	assert_eq(f.at(B, 0), front_man, "the front man rotates back")
	assert_eq(f.at(F, 0), back_man, "the fresh man steps forward")
	assert_eq(f.at(B, 2), loner, "a man without a partner still changes lines")
	assert_eq(f.at(F, 2), null, "his old slot empties")


func test_shift_slides_both_lines_one_column() -> void:
	var f := Formation.new()
	var front_man := TestHelpers.grunt(E, "front_man")
	var back_man := TestHelpers.grunt(E, "back_man")
	f.place(front_man, F, 1)
	f.place(back_man, B, 2)
	assert_true(f.shift(1), "someone moved")
	assert_eq(f.at(F, 2), front_man, "the front line slides starboard")
	assert_eq(f.at(B, 3), back_man, "and the second line with it")


func test_shift_moves_what_can_and_pins_the_edge() -> void:
	var f := Formation.new()
	var edge := TestHelpers.grunt(E, "edge")
	var follower := TestHelpers.grunt(E, "follower")
	var free_man := TestHelpers.grunt(E, "free_man")
	f.place(edge, F, 3)
	f.place(follower, F, 2)
	f.place(free_man, F, 0)
	assert_true(f.shift(1), "part of the line still moves")
	assert_eq(f.at(F, 3), edge, "the edge man is pinned at the rail")
	assert_eq(f.at(F, 2), follower, "and pins the man behind him")
	assert_eq(f.at(F, 1), free_man, "the man with room slides")


func test_shift_of_a_full_line_does_not_move() -> void:
	var f := Formation.new()
	var men: Array[Character] = []
	for col in Formation.COLUMNS:
		var c := TestHelpers.grunt(E, "man%d" % col)
		men.append(c)
		f.place(c, F, col)
	assert_false(f.shift(-1), "a full line has nowhere to go")
	for col in Formation.COLUMNS:
		assert_eq(f.at(F, col), men[col], "nobody moved")


func test_step_up_fills_empty_front_slots_from_the_same_column() -> void:
	var f := Formation.new()
	var stepper := TestHelpers.grunt(E, "stepper")
	var covered := TestHelpers.grunt(E, "covered")
	var cover := TestHelpers.grunt(E, "cover")
	f.place(stepper, B, 1)
	f.place(cover, F, 2)
	f.place(covered, B, 2)
	assert_true(f.step_up(), "someone stepped up")
	assert_eq(f.at(F, 1), stepper, "the open column's back man steps forward")
	assert_eq(f.at(B, 2), covered, "a covered man holds his place")


func test_step_up_with_a_full_front_changes_nothing() -> void:
	var f := Formation.new()
	for col in Formation.COLUMNS:
		f.place(TestHelpers.grunt(E, "f%d" % col), F, col)
	var back_man := TestHelpers.grunt(E, "back_man")
	f.place(back_man, B, 0)
	assert_false(f.step_up(), "no gaps to fill")
	assert_eq(f.at(B, 0), back_man, "the second line stands fast")


# --- Captain's calls: telegraphed like any tactic, resolved before they fight --

func test_fresh_men_forward_rotates_the_enemy_lines() -> void:
	var tired := TestHelpers.grunt(E, "tired")
	var fresh := TestHelpers.grunt(E, "fresh")
	var eng := TestHelpers.engine_for({"enemy_field": [tired, fresh]})
	TestHelpers.station(eng.state.enemy_formation, fresh, B, 0)
	await eng._resolve_tactic("fresh_men_forward")
	assert_eq(eng.state.enemy_formation.at(F, 0), fresh, "the fresh man steps forward")
	assert_eq(eng.state.enemy_formation.at(B, 0), tired, "the tired man rotates back")
	assert_true(_log_has(eng, "Fresh men"), "the call is in the saga")


func test_shift_calls_slide_the_enemy_line_each_way() -> void:
	var mover := TestHelpers.grunt(E, "mover")
	var eng := TestHelpers.engine_for({"enemy_field": [mover]})
	TestHelpers.station(eng.state.enemy_formation, mover, F, 1)
	await eng._resolve_tactic("shift_starboard")
	assert_eq(eng.state.enemy_formation.column_of(mover), 2, "starboard slides up a column")
	await eng._resolve_tactic("shift_larboard")
	assert_eq(eng.state.enemy_formation.column_of(mover), 1, "larboard slides back down")


func test_step_up_call_fills_their_front_gaps() -> void:
	var lurker := TestHelpers.grunt(E, "lurker")
	var eng := TestHelpers.engine_for({"enemy_field": [lurker]})
	TestHelpers.station(eng.state.enemy_formation, lurker, B, 2)
	await eng._resolve_tactic("step_up")
	assert_eq(eng.state.enemy_formation.at(F, 2), lurker, "the back man steps into the gap")


# --- Telegraph plumbing: the forecast reads the called move -------------------

func test_forecast_previews_enemy_attacks_from_their_called_positions() -> void:
	var my_man := TestHelpers.grunt(P, "my_man")
	var hitter := TestHelpers.grunt(E, "hitter", 12, 6, 3, 3, Weapon.sword())
	var eng := TestHelpers.engine_for({"player_field": [my_man], "enemy_field": [hitter]})
	TestHelpers.station(eng.state.player_formation, my_man, F, 1)
	TestHelpers.station(eng.state.enemy_formation, hitter, F, 0)
	eng.state.next_tactic = "shift_starboard"
	var bill: Dictionary = eng.forecast()
	assert_eq(bill[my_man]["hp"], 5, "after the shift he stands across from me: 3 Str + 2 sword")
	assert_eq(eng.state.enemy_formation.column_of(hitter), 0,
			"the preview never moves the real line")


func test_forecast_keeps_your_own_attacks_on_current_geometry() -> void:
	var my_man := TestHelpers.grunt(P, "my_man", 12, 6, 3, 3, Weapon.sword())
	var dodger := TestHelpers.grunt(E, "dodger")
	var eng := TestHelpers.engine_for({"player_field": [my_man], "enemy_field": [dodger]})
	eng.state.next_tactic = "shift_starboard"
	var bill: Dictionary = eng.forecast()
	assert_eq(bill[dodger]["hp"], 5, "your fight resolves before the call: you still reach him")
	assert_eq(bill[my_man]["hp"], 0, "but his answer comes from the shifted column, hitting air")


# --- Reinforcement slot choice: deterministic, captain last -------------------

func test_reinforcements_fill_front_gaps_left_to_right() -> void:
	var a := TestHelpers.grunt(E, "a")
	var b := TestHelpers.grunt(E, "b")
	var r1 := TestHelpers.grunt(E, "r1")
	var r2 := TestHelpers.grunt(E, "r2")
	var eng := TestHelpers.engine_for({"enemy_field": [a, b], "enemy_reserve": [r1, r2]})
	TestHelpers.station(eng.state.enemy_formation, b, F, 2)
	eng._reinforce()
	assert_eq(eng.state.enemy_formation.at(F, 1), r1, "the first man up takes the leftmost gap")
	assert_eq(eng.state.enemy_formation.at(F, 3), r2, "the second the next")


func test_the_captain_waits_one_full_turn_after_the_hold_empties() -> void:
	var watch := TestHelpers.grunt(E, "watch")
	var last_man := TestHelpers.grunt(E, "last_man")
	var jarl := TestHelpers.captain_of(E, "jarl")
	var eng := TestHelpers.engine_for({
		"enemy_field": [watch],
		"enemy_reserve": [last_man],
		"enemy_captain": jarl,
	})
	eng._reinforce()
	assert_true(eng.state.enemy_formation.has(last_man), "the last man comes up")
	assert_false(eng.state.enemy_formation.has(jarl), "the jarl is not on his heels")
	eng._reinforce()
	assert_true(eng.state.enemy_formation.has(jarl), "he steps in the turn after")
