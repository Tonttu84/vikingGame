extends TestCase
## The formation grid from docs/lines-redesign.md: 4 columns x 2 lines per
## side, any slot may be empty, and the movement verbs that re-arrange it.

const P := Character.Side.PLAYER


func _man(id: String) -> Character:
	return TestHelpers.grunt(P, id)


func test_starts_empty() -> void:
	var f := Formation.new()
	assert_true(f.is_empty())
	assert_eq(f.size(), 0)
	assert_false(f.is_full())
	assert_eq(f.at(Formation.FRONT, 0), null)


func test_place_and_find() -> void:
	var f := Formation.new()
	var a := _man("a")
	assert_true(f.place(a, Formation.FRONT, 2))
	assert_true(f.has(a))
	assert_eq(f.at(Formation.FRONT, 2), a)
	assert_eq(f.line_of(a), Formation.FRONT)
	assert_eq(f.column_of(a), 2)
	assert_eq(f.size(), 1)


func test_place_refuses_occupied_and_out_of_bounds() -> void:
	var f := Formation.new()
	var a := _man("a")
	var b := _man("b")
	f.place(a, Formation.FRONT, 0)
	assert_false(f.place(b, Formation.FRONT, 0), "slot taken")
	assert_false(f.place(b, Formation.FRONT, 4), "no fifth column")
	assert_false(f.place(b, -1, 0), "no such line")
	assert_false(f.place(a, Formation.BACK, 0), "a man stands in one slot only")
	assert_eq(f.size(), 1)


func test_fielded_orders_front_left_to_right_then_back() -> void:
	var f := Formation.new()
	var front3 := _man("front3")
	var back1 := _man("back1")
	var front0 := _man("front0")
	f.place(front3, Formation.FRONT, 3)
	f.place(back1, Formation.BACK, 1)
	f.place(front0, Formation.FRONT, 0)
	assert_eq(f.fielded(), [front0, front3, back1] as Array[Character])


func test_first_free_index_prefers_the_front() -> void:
	var f := Formation.new()
	assert_eq(f.first_free_index(), Formation.slot_index(Formation.FRONT, 0))
	f.place(_man("a"), Formation.FRONT, 0)
	assert_eq(f.first_free_index(), Formation.slot_index(Formation.FRONT, 1))
	for col in [1, 2, 3]:
		f.place(_man("f%d" % col), Formation.FRONT, col)
	assert_eq(f.first_free_index(), Formation.slot_index(Formation.BACK, 0),
			"full front: the second line fills next")
	for col in 4:
		f.place(_man("b%d" % col), Formation.BACK, col)
	assert_true(f.is_full())
	assert_eq(f.first_free_index(), -1)


func test_slide_moves_one_column_into_an_empty_slot() -> void:
	var f := Formation.new()
	var a := _man("a")
	var wall := _man("wall")
	f.place(a, Formation.FRONT, 1)
	f.place(wall, Formation.FRONT, 0)
	assert_false(f.slide(a, -1), "occupied: no slide")
	assert_true(f.slide(a, 1))
	assert_eq(f.column_of(a), 2)
	f.slide(a, 1)
	assert_eq(f.column_of(a), 3)
	assert_false(f.slide(a, 1), "no column 5")
	assert_false(f.slide(a, 2), "one column at a time")


func test_advance_and_retire_swap_lines_within_the_column() -> void:
	var f := Formation.new()
	var a := _man("a")
	f.place(a, Formation.BACK, 2)
	assert_true(f.advance(a))
	assert_eq(f.line_of(a), Formation.FRONT)
	assert_eq(f.column_of(a), 2, "advance keeps the column")
	assert_false(f.advance(a), "already in front")
	assert_true(f.retire(a))
	assert_eq(f.line_of(a), Formation.BACK)
	var blocker := _man("blocker")
	f.place(blocker, Formation.FRONT, 2)
	assert_false(f.advance(a), "the front slot is taken")


func test_swap_positions_trades_any_two_slots() -> void:
	var f := Formation.new()
	var a := _man("a")
	var b := _man("b")
	f.place(a, Formation.FRONT, 0)
	f.place(b, Formation.BACK, 3)
	assert_true(f.swap_positions(a, b))
	assert_eq(f.at(Formation.BACK, 3), a)
	assert_eq(f.at(Formation.FRONT, 0), b)
	assert_false(f.swap_positions(a, _man("stranger")), "both must stand in the formation")


func test_remove_empties_the_slot() -> void:
	var f := Formation.new()
	var a := _man("a")
	f.place(a, Formation.FRONT, 1)
	assert_true(f.remove(a))
	assert_false(f.has(a))
	assert_eq(f.at(Formation.FRONT, 1), null)
	assert_false(f.remove(a), "already gone")


func test_column_melee_target_is_front_first_then_back() -> void:
	var f := Formation.new()
	var front := _man("front")
	var back := _man("back")
	f.place(front, Formation.FRONT, 1)
	f.place(back, Formation.BACK, 1)
	assert_eq(f.column_melee_target(1), front, "the front man shields his second line")
	f.remove(front)
	assert_eq(f.column_melee_target(1), back, "gone: the back man is next")
	f.remove(back)
	assert_eq(f.column_melee_target(1), null, "empty column: attacks into it miss")
