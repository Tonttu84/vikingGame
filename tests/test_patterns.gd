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
