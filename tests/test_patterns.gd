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


# --- Patterns: every man a rhythm, on BOTH sides -------------------------------
# (docs/block-and-patterns.md; supersedes phase C's enemy-only wind-ups)

func _berserk(side: Character.Side, id: String) -> Character:
	var c := TestHelpers.grunt(side, id, 10, 1, 5, 4, Weapon.axe())
	c.is_berserker = true
	return c


func test_roles_carry_their_patterns_on_both_sides() -> void:
	var berserk := _berserk(E, "berserk")
	var archer := TestHelpers.grunt(P, "archer", 10, 5, 2, 3, Weapon.bow())
	var shieldman := TestHelpers.grunt(E, "shieldman")
	shieldman.is_shieldman = true
	var plain := TestHelpers.grunt(P, "plain")
	var eng := TestHelpers.engine_for({
		"player_field": [archer, plain],
		"enemy_field": [berserk, shieldman],
	})
	assert_true(eng != null, "")
	assert_eq(berserk.pattern, ["attack", "attack", "heavy"], "the berserker builds to the blow")
	assert_eq(archer.pattern, ["aim", "shoot"], "your own archer keeps beats too")
	assert_eq(shieldman.pattern, ["guard", "attack"], "the shieldman plants, then swings")
	assert_eq(plain.pattern, ["attack"], "a plain fighter just fights")


func test_beats_advance_each_own_fight_phase_and_wrap() -> void:
	var berserk := _berserk(E, "berserk")
	var bystander := TestHelpers.grunt(P, "bystander", 40)
	var eng := TestHelpers.engine_for({"player_field": [bystander], "enemy_field": [berserk]})
	assert_eq(berserk.current_beat(), "attack", "a man arrives at the top of his rhythm")
	await eng._fight_phase(E)
	assert_eq(berserk.current_beat(), "attack", "second beat")
	await eng._fight_phase(P)
	assert_eq(berserk.current_beat(), "attack", "the other side's phase is not his rhythm")
	await eng._fight_phase(E)
	assert_eq(berserk.current_beat(), "heavy", "third beat: the blow is next")
	await eng._fight_phase(E)
	assert_eq(berserk.current_beat(), "attack", "spent — landed or dodged — the rhythm restarts")


func test_a_late_arrival_starts_his_rhythm_over() -> void:
	var berserk := _berserk(E, "berserk")
	var watch := TestHelpers.grunt(E, "watch")
	var eng := TestHelpers.engine_for({"enemy_field": [watch], "enemy_reserve": [berserk]})
	berserk.beat = 2
	eng._reinforce()
	assert_true(eng.state.enemy_formation.has(berserk), "he comes up from below")
	assert_eq(berserk.beat, 0, "fielded: his rhythm starts at the top")


func test_the_reserve_keeps_no_rhythm() -> void:
	var pc := TestHelpers.grunt(P, "pc", 40)
	var berserk := _berserk(E, "berserk")
	var watch := TestHelpers.grunt(E, "watch")
	var eng := TestHelpers.engine_for({
		"player_field": [pc],
		"enemy_field": [watch],
		"enemy_reserve": [berserk],
	})
	await eng._fight_phase(E)
	assert_eq(berserk.beat, 0, "below decks the beats do not march")


func test_heavy_beat_doubles_the_blow_and_the_graze() -> void:
	var berserk := _berserk(E, "berserk")
	var mark := TestHelpers.grunt(P, "mark", 30)
	var left := TestHelpers.grunt(P, "left")
	var eng := TestHelpers.engine_for({
		"player_field": [left, mark],
		"enemy_field": [berserk],
	})
	berserk.beat = 2
	await eng._attack(berserk, mark)
	assert_eq(mark.hp, 30 - 12, "the heavy blow: (5 Str + 1 axe) doubled")
	assert_eq(left.hp, 12 - 4, "the graze doubles with it")


func test_an_ordinary_beat_cleaves_normally() -> void:
	var berserk := _berserk(E, "berserk")
	var mark := TestHelpers.grunt(P, "mark", 30)
	var left := TestHelpers.grunt(P, "left")
	var eng := TestHelpers.engine_for({
		"player_field": [left, mark],
		"enemy_field": [berserk],
	})
	await eng._attack(berserk, mark)
	assert_eq(mark.hp, 30 - 6, "no heavy beat, no spike")
	assert_eq(left.hp, 12 - 2, "the ordinary graze")


# --- The archer's two beats: aim, then hit and suppress ------------------------

func test_the_aim_beat_marks_the_weakest_and_looses_nothing() -> void:
	var archer := TestHelpers.grunt(E, "archer", 10, 5, 2, 3, Weapon.bow())
	var sturdy := TestHelpers.grunt(P, "sturdy", 20)
	var weakling := TestHelpers.grunt(P, "weakling", 6)
	var eng := TestHelpers.engine_for({
		"player_field": [sturdy, weakling],
		"enemy_field": [archer],
	})
	TestHelpers.station(eng.state.enemy_formation, archer, B, 0)
	await eng._fight_phase(E)
	assert_eq(eng.state.archer_marks.get(archer), weakling, "the mark locks on the weakest")
	assert_eq(weakling.hp, 6, "no arrow flies on the aim beat")
	assert_true(_log_has(eng, "marks"), "the mark is in the saga")
	assert_eq(archer.current_beat(), "shoot", "the arrows are next")


func test_the_double_shot_hits_the_marked_man_not_the_weakest() -> void:
	var archer := TestHelpers.grunt(E, "archer", 10, 5, 2, 3, Weapon.bow())
	var marked := TestHelpers.grunt(P, "marked", 20)
	var weaker_now := TestHelpers.grunt(P, "weaker_now", 4)
	var eng := TestHelpers.engine_for({
		"player_field": [marked, weaker_now],
		"enemy_field": [archer],
	})
	TestHelpers.station(eng.state.enemy_formation, archer, B, 0)
	archer.beat = 1
	eng.state.archer_marks[archer] = marked
	await eng._fight_phase(E)
	assert_eq(marked.hp, 20 - 4, "both aimed arrows find the marked man")
	assert_eq(weaker_now.hp, 4, "the weaker man is not the mark")
	assert_false(eng.state.archer_marks.has(archer), "the mark is spent with the arrows")


func test_the_double_shot_is_wasted_when_the_mark_is_gone() -> void:
	var archer := TestHelpers.grunt(E, "archer", 10, 5, 2, 3, Weapon.bow())
	var marked := TestHelpers.grunt(P, "marked", 20)
	var stand_in := TestHelpers.grunt(P, "stand_in")
	var eng := TestHelpers.engine_for({
		"player_field": [marked, stand_in],
		"enemy_field": [archer],
	})
	TestHelpers.station(eng.state.enemy_formation, archer, B, 0)
	archer.beat = 1
	eng.state.archer_marks[archer] = marked
	eng.state.player_formation.remove(marked)
	eng.state.player_reserve.append(marked)
	await eng._fight_phase(E)
	assert_eq(marked.hp, 20, "dragged to the ship: out of reach")
	assert_eq(stand_in.hp, 12, "the aimed arrows are not re-spent on anyone else")
	assert_true(_log_has(eng, "mark is gone"), "the waste is in the saga")


func test_the_double_shot_suppresses_the_mark() -> void:
	var archer := TestHelpers.grunt(E, "archer", 10, 5, 2, 3, Weapon.bow())
	var marked := TestHelpers.grunt(P, "marked", 20, 6, 3, 3, Weapon.sword())
	var eng := TestHelpers.engine_for({
		"player_field": [marked],
		"enemy_field": [archer],
	})
	TestHelpers.station(eng.state.enemy_formation, archer, B, 0)
	archer.beat = 1
	eng.state.archer_marks[archer] = marked
	await eng._fight_phase(E)
	assert_eq(marked.suppressed, BattleState.SUPPRESS_TURNS, "hit, he is suppressed")
	assert_eq(eng._melee_damage(marked, archer), 5 - 2,
			"his 5-point swing loses a third, rounded up against him")


func test_suppression_rounds_up_against_the_dealer_and_floors_at_one() -> void:
	var weakling := TestHelpers.grunt(P, "weakling", 12, 6, 1, 3, null, 0)
	var strong := TestHelpers.grunt(P, "strong", 12, 6, 5, 3, Weapon.sword(), 0)
	var d := TestHelpers.grunt(E, "d")
	var eng := TestHelpers.engine_for({"player_field": [weakling, strong], "enemy_field": [d]})
	weakling.suppressed = 1
	strong.suppressed = 1
	assert_eq(eng._melee_damage(strong, d), 7 - 3, "7 loses ceil(7/3) = 3")
	assert_eq(eng._melee_damage(weakling, d), 1, "a 1-point swing cannot go lower")


func test_suppression_wears_off_at_his_own_turns_end() -> void:
	var marked := TestHelpers.grunt(P, "marked")
	var d := TestHelpers.grunt(E, "d")
	var eng := TestHelpers.engine_for({"player_field": [marked], "enemy_field": [d]})
	marked.suppressed = 2
	eng._tick_statuses(P)
	assert_eq(marked.suppressed, 1, "one of his turns gone")
	eng._tick_statuses(E)
	assert_eq(marked.suppressed, 1, "the other side's turns do not count")
	eng._tick_statuses(P)
	assert_eq(marked.suppressed, 0, "worn off")


func test_an_archer_in_the_front_line_just_fights() -> void:
	var archer := TestHelpers.grunt(P, "archer", 10, 5, 2, 3, Weapon.bow())
	var d := TestHelpers.grunt(E, "d")
	var eng := TestHelpers.engine_for({"player_field": [archer], "enemy_field": [d]})
	await eng._fight_phase(P)
	assert_eq(d.hp, 12 - 3, "2 Str + 1 bow, hand to hand — no aiming at the rail")
	assert_eq(archer.beat, 1, "but the rhythm marches anyway")


# --- The guard beat: the shieldman's kit ----------------------------------------

func test_guard_beat_raises_more_block_instead_of_swinging() -> void:
	var shieldman := TestHelpers.grunt(P, "shieldman", 14, 7, 2, 2, Weapon.sword(), 4)
	shieldman.is_shieldman = true
	var d := TestHelpers.grunt(E, "d")
	var eng := TestHelpers.engine_for({"player_field": [shieldman], "enemy_field": [d]})
	await eng._fight_phase(P)
	assert_eq(shieldman.block, 4 + 4, "turn-start guard plus his armor again on the beat")
	assert_eq(d.hp, 12, "the shield is planted: no swing this beat")
	assert_eq(shieldman.current_beat(), "attack", "he strikes on the next")


func test_guard_beat_shares_block_with_line_neighbors() -> void:
	var shieldman := TestHelpers.grunt(P, "shieldman", 14, 7, 2, 2, Weapon.sword(), 4)
	shieldman.is_shieldman = true
	var left := TestHelpers.grunt(P, "left")
	var behind := TestHelpers.grunt(P, "behind")
	var d := TestHelpers.grunt(E, "d")
	var eng := TestHelpers.engine_for({
		"player_field": [left, shieldman],
		"enemy_field": [d],
	})
	TestHelpers.station(eng.state.player_formation, behind, B, 1)
	await eng._fight_phase(P)
	assert_eq(left.block, BattleState.SHIELD_AURA_BLOCK, "the wall covers the man beside him")
	assert_eq(behind.block, 0, "the man directly behind is not a line-neighbor")


func test_guarding_twice_before_the_reset_stacks_within_the_turn() -> void:
	var shieldman := TestHelpers.grunt(E, "shieldman", 14, 7, 2, 2, Weapon.sword(), 3)
	shieldman.is_shieldman = true
	var eng := TestHelpers.engine_for({"enemy_field": [shieldman]})
	shieldman.block = 1
	eng._guard_beat(shieldman)
	assert_eq(shieldman.block, 1 + 3, "the beat ADDS to what is left; only the turn start resets")


# --- The forecast reads the beats ------------------------------------------------

func test_forecast_bills_the_heavy_cleave_and_the_double_shot() -> void:
	var berserk := _berserk(E, "berserk")
	var archer := TestHelpers.grunt(E, "archer", 10, 5, 2, 3, Weapon.bow())
	var mark := TestHelpers.grunt(P, "mark", 30)
	var left := TestHelpers.grunt(P, "left", 20)
	var eng := TestHelpers.engine_for({
		"player_field": [left, mark],
		"enemy_field": [berserk, archer],
	})
	TestHelpers.station(eng.state.enemy_formation, archer, B, 0)
	TestHelpers.station(eng.state.enemy_formation, berserk, F, 1)
	berserk.beat = 2
	archer.beat = 1
	eng.state.archer_marks[archer] = mark
	eng.state.next_tactic = "press_the_attack"
	var bill: Dictionary = eng.forecast()
	assert_eq(bill[mark]["hp"], 12 + 4, "the doubled blow plus both aimed arrows")
	assert_eq(bill[left]["hp"], 4, "the doubled graze reaches the man beside the mark")


func test_forecast_shows_no_arrows_for_a_lost_mark() -> void:
	var archer := TestHelpers.grunt(E, "archer", 10, 5, 2, 3, Weapon.bow())
	var survivor := TestHelpers.grunt(P, "survivor")
	var eng := TestHelpers.engine_for({
		"player_field": [survivor],
		"enemy_field": [archer],
	})
	TestHelpers.station(eng.state.enemy_formation, archer, B, 0)
	archer.beat = 1
	eng.state.next_tactic = "press_the_attack"
	var bill: Dictionary = eng.forecast()
	assert_eq(bill[survivor]["hp"], 0, "no mark to shoot: the aimed arrows go nowhere")


func test_forecast_bills_nothing_for_aim_and_guard_beats() -> void:
	var archer := TestHelpers.grunt(E, "archer", 10, 5, 2, 3, Weapon.bow())
	var shieldman := TestHelpers.grunt(E, "shieldman", 14, 7, 2, 2, Weapon.sword(), 3)
	shieldman.is_shieldman = true
	var pc := TestHelpers.grunt(P, "pc")
	var eng := TestHelpers.engine_for({
		"player_field": [pc],
		"enemy_field": [shieldman, archer],
	})
	TestHelpers.station(eng.state.enemy_formation, archer, B, 0)
	eng.state.next_tactic = "press_the_attack"
	var bill: Dictionary = eng.forecast()
	assert_eq(bill[pc]["hp"], 0, "an aiming archer and a guarding shieldman draw no blood")


func test_forecast_counts_your_own_guard_beat_against_their_blows() -> void:
	var shieldman := TestHelpers.grunt(P, "shieldman", 14, 7, 2, 2, Weapon.sword(), 3)
	shieldman.is_shieldman = true
	var hitter := TestHelpers.grunt(E, "hitter", 12, 6, 5, 3, Weapon.sword(), 0)
	var eng := TestHelpers.engine_for({"player_field": [shieldman], "enemy_field": [hitter]})
	shieldman.block = 3
	eng.state.next_tactic = "press_the_attack"
	var bill: Dictionary = eng.forecast()
	assert_eq(bill[shieldman]["hp"], 1,
			"his guard beat resolves first: 3 standing + 3 more block against the 7-point blow")
