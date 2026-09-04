extends TestCase
## Strict-column targeting (docs/lines-redesign.md): columns duel columns,
## attacks into an empty column miss, spears reach from the second line,
## archers snipe the weakest enemy anywhere, and the positional cards
## (Break the Line, Challenge) re-arrange who hits whom.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY
const F := Formation.FRONT
const B := Formation.BACK


func _log_has(eng: CombatEngine, needle: String) -> bool:
	for line in eng.state.battle_log:
		if line.contains(needle):
			return true
	return false


func test_front_liner_hits_the_front_of_his_column() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e_front := TestHelpers.grunt(E, "e_front")
	var e_back := TestHelpers.grunt(E, "e_back")
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e_front, e_back]})
	TestHelpers.station(eng.state.enemy_formation, e_back, B, 0)
	await eng._fight_phase(P)
	assert_eq(e_front.hp, 9, "the front man takes the hit")
	assert_eq(e_back.hp, 12, "his second line is shielded behind him")


func test_back_liner_takes_over_when_the_front_falls_mid_phase() -> void:
	var killer := TestHelpers.grunt(P, "killer", 12, 6, 10, 4)
	var spear := TestHelpers.grunt(P, "spear", 12, 6, 3, 3, Weapon.spear())
	var e_front := TestHelpers.grunt(E, "e_front", 5)
	var e_back := TestHelpers.grunt(E, "e_back")
	var eng := TestHelpers.engine_for({
		"player_field": [killer, spear],
		"enemy_field": [e_front, e_back],
	})
	TestHelpers.station(eng.state.player_formation, spear, B, 0)
	TestHelpers.station(eng.state.enemy_formation, e_back, B, 0)
	await eng._fight_phase(P)
	assert_true(eng.state.enemy_dead.has(e_front), "the fast man drops the front-liner")
	assert_eq(e_back.hp, 12 - 4, "the slower spear then reaches the man now nearest")


func test_attack_into_an_empty_column_lands_nothing() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	TestHelpers.station(eng.state.enemy_formation, e1, F, 1)
	await eng._fight_phase(P)
	assert_eq(e1.hp, 12, "no one stands across from p1: nobody is hit")


func test_an_empty_column_sends_him_toward_the_nearest_enemy() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	TestHelpers.station(eng.state.enemy_formation, e1, F, 2)
	await eng._fight_phase(P)
	assert_eq(eng.state.player_formation.column_of(p1), 1, "he closes one column")
	assert_eq(e1.hp, 12, "and forfeits the swing to do it")
	assert_true(_log_has(eng, "presses toward the fighting"), "the step is visible")


func test_the_step_takes_the_nearer_column() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var near := TestHelpers.grunt(E, "near")
	var far := TestHelpers.grunt(E, "far")
	var eng := TestHelpers.engine_for({
		"player_field": [p1], "enemy_field": [near, far]})
	TestHelpers.station(eng.state.player_formation, p1, F, 1)
	TestHelpers.station(eng.state.enemy_formation, near, F, 0)
	TestHelpers.station(eng.state.enemy_formation, far, F, 3)
	await eng._fight_phase(P)
	assert_eq(eng.state.player_formation.column_of(p1), 0, "one column away beats two")


func test_the_step_breaks_a_tie_to_port() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var port := TestHelpers.grunt(E, "port")
	var starboard := TestHelpers.grunt(E, "starboard")
	var eng := TestHelpers.engine_for({
		"player_field": [p1], "enemy_field": [port, starboard]})
	TestHelpers.station(eng.state.player_formation, p1, F, 1)
	TestHelpers.station(eng.state.enemy_formation, port, F, 0)
	TestHelpers.station(eng.state.enemy_formation, starboard, F, 2)
	await eng._fight_phase(P)
	assert_eq(eng.state.player_formation.column_of(p1), 0,
			"port before starboard, as everywhere else")


## A column holding only a second-liner is still worth closing on: a
## front-liner reaches past an empty front slot into the man behind it.
func test_a_column_holding_only_a_back_liner_still_draws_him() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var lurker := TestHelpers.grunt(E, "lurker")
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [lurker]})
	TestHelpers.station(eng.state.enemy_formation, lurker, B, 1)
	await eng._fight_phase(P)
	assert_eq(eng.state.player_formation.column_of(p1), 1, "he closes on the man behind")


func test_a_man_with_nowhere_to_step_still_swings_at_air() -> void:
	var blocker := TestHelpers.grunt(P, "blocker")
	var stuck := TestHelpers.grunt(P, "stuck")
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({
		"player_field": [blocker, stuck], "enemy_field": [e1]})
	TestHelpers.station(eng.state.enemy_formation, e1, F, 0)
	await eng._fight_phase(P)
	assert_eq(eng.state.player_formation.column_of(stuck), 1,
			"his fellow holds the only slot toward the fighting")
	assert_true(_log_has(eng, "swings at air"), "so the swing is wasted after all")


func test_a_covered_second_liner_without_reach_never_steps() -> void:
	var sword := TestHelpers.grunt(P, "sword", 12, 6, 3, 3, Weapon.sword())
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({"player_field": [sword], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, sword, B, 0)
	TestHelpers.cover_at(eng, P, 0)
	TestHelpers.station(eng.state.enemy_formation, e1, F, 2)
	await eng._fight_phase(P)
	assert_eq(eng.state.player_formation.column_of(sword), 0,
			"covered, he cannot reach from back there — closing would buy him nothing")


func test_a_spear_closes_from_the_second_line() -> void:
	var spear := TestHelpers.grunt(P, "spear", 12, 6, 3, 3, Weapon.spear())
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({"player_field": [spear], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, spear, B, 0)
	TestHelpers.station(eng.state.enemy_formation, e1, F, 2)
	await eng._fight_phase(P)
	assert_eq(eng.state.player_formation.column_of(spear), 1,
			"reach makes the column worth closing on")


func test_vacating_a_column_dodges_the_enemy_swing() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, p1, F, 3)
	await eng._fight_phase(E)
	assert_eq(p1.hp, 12, "their berserker hits nothing — dodging is placement")


## Dodging buys a turn, not the fight: he walks the column down and lands
## the blow once he arrives. Two survivors can no longer stand and stare.
func test_dodging_only_buys_a_turn() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, p1, F, 3)
	for i in 3:
		await eng._fight_phase(E)
	assert_eq(eng.state.enemy_formation.column_of(e1), 3,
			"three columns of deck, three turns spent crossing them")
	assert_eq(p1.hp, 12, "every one of them bought by the dodge")
	await eng._fight_phase(E)
	assert_true(p1.hp < 12, "the fourth turn he swings for real")


func test_spear_reaches_from_the_second_line() -> void:
	var spear := TestHelpers.grunt(P, "spear", 12, 6, 3, 3, Weapon.spear())
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({"player_field": [spear], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, spear, B, 0)
	await eng._fight_phase(P)
	assert_eq(e1.hp, 12 - 4, "reach: 3 Str + 1 spear from the second line")


func test_archer_marks_the_weakest_fielded_enemy_anywhere() -> void:
	var bow := TestHelpers.grunt(P, "bow", 10, 5, 2, 3, Weapon.bow())
	var e1 := TestHelpers.grunt(E, "e1")
	var e2 := TestHelpers.grunt(E, "e2", 5, 6, 3, 3, null, 0)
	var eng := TestHelpers.engine_for({"player_field": [bow], "enemy_field": [e1, e2]})
	TestHelpers.station(eng.state.player_formation, bow, B, 2)
	TestHelpers.cover_at(eng, P, 2)
	TestHelpers.station(eng.state.enemy_formation, e2, F, 3)
	await eng._fight_phase(P)
	assert_eq(eng.state.archer_marks.get(bow), e2, "the aim beat locks the lowest HP, any column")
	await eng._fight_phase(P)
	assert_eq(e2.hp, 5 - 4, "the next beat: both flat-2 arrows land")
	assert_eq(e1.hp, 12, "the healthy man is not worth an arrow")


func test_archer_mark_tiebreak_is_spawn_order() -> void:
	var bow := TestHelpers.grunt(P, "bow", 10, 5, 2, 3, Weapon.bow())
	var e1 := TestHelpers.grunt(E, "e1")
	var e2 := TestHelpers.grunt(E, "e2")
	var eng := TestHelpers.engine_for({"player_field": [bow], "enemy_field": [e1, e2]})
	TestHelpers.station(eng.state.player_formation, bow, B, 2)
	TestHelpers.cover_at(eng, P, 2)
	await eng._fight_phase(P)
	assert_eq(eng.state.archer_marks.get(bow), e1, "equal HP: the earlier spawn is marked")


func test_reserve_never_acts() -> void:
	var bow := TestHelpers.grunt(P, "bow", 10, 5, 2, 3, Weapon.bow())
	var melee := TestHelpers.grunt(P, "melee")
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({
		"player_field": [melee],
		"player_reserve": [bow],
		"enemy_field": [e1],
	})
	await eng._fight_phase(P)
	assert_eq(e1.hp, 9, "only the fielded man fought: the bow-from-reserve rule is gone")


func test_bow_in_the_front_line_fights_his_column() -> void:
	var bow := TestHelpers.grunt(P, "bow", 10, 5, 2, 3, Weapon.bow())
	var e1 := TestHelpers.grunt(E, "e1")
	var e_weak := TestHelpers.grunt(E, "e_weak", 2)
	var eng := TestHelpers.engine_for({"player_field": [bow], "enemy_field": [e1, e_weak]})
	await eng._fight_phase(P)
	assert_eq(e1.hp, 12 - 3, "in the front he melees his column: 2 Str + 1 bow")
	assert_eq(e_weak.hp, 2, "no sniping from the front line")


func test_focus_fire_strikes_through_the_column() -> void:
	var pA := TestHelpers.grunt(P, "pA")
	var pC := TestHelpers.grunt(P, "pC")
	var bow := TestHelpers.grunt(P, "bow", 10, 5, 2, 3, Weapon.bow())
	var e_front := TestHelpers.grunt(E, "e_front", 30)
	var e_weak := TestHelpers.grunt(E, "e_weak", 30)
	var eng := TestHelpers.engine_for({
		"player_field": [pC, pA, bow],
		"enemy_field": [e_front, e_weak],
	})
	TestHelpers.station(eng.state.player_formation, bow, B, 0)
	TestHelpers.station(eng.state.enemy_formation, e_weak, B, 1)
	TestHelpers.station(eng.state.enemy_formation, e_front, F, 1)
	eng.state.focus_target = e_weak
	await eng._fight_phase(P)
	assert_eq(e_weak.hp, 30 - 3, "his column's attacker strikes past the front man")
	assert_eq(eng.state.archer_marks.get(bow), e_weak,
			"the archer joins by aiming at the focus, not the weakest")
	assert_eq(e_front.hp, 30, "the front man is bypassed, not hit")
	assert_true(_log_has(eng, "swings at air"), "focus does not grant reach across columns: pC still misses")


func test_break_the_line_shoves_a_front_liner_sideways() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	TestHelpers.station(eng.state.enemy_formation, e1, F, 1)
	var card := CardLibrary.break_the_line()
	eng.state.hand.append(card)
	eng.state.momentum = card.cost
	await eng._play_card(card, e1)
	assert_eq(eng.state.enemy_formation.column_of(e1), 0, "no direction given: shoved left first")
	var card2 := CardLibrary.break_the_line()
	eng.state.hand.append(card2)
	eng.state.momentum = card2.cost
	await eng._play_card(card2, e1, null, -1, 1)
	assert_eq(eng.state.enemy_formation.column_of(e1), 1, "an explicit direction is honored")


func test_break_the_line_refused_when_no_room_to_shove() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var boxed := TestHelpers.grunt(E, "boxed")
	var left := TestHelpers.grunt(E, "left")
	var right := TestHelpers.grunt(E, "right")
	var backer := TestHelpers.grunt(E, "backer")
	var eng := TestHelpers.engine_for({
		"player_field": [p1],
		"enemy_field": [left, boxed, right, backer],
	})
	TestHelpers.station(eng.state.enemy_formation, backer, B, 0)
	var card := CardLibrary.break_the_line()
	eng.state.hand.append(card)
	eng.state.momentum = 5
	await eng._play_card(card, boxed)
	assert_true(eng.state.hand.has(card), "both neighbor slots taken: refused")
	assert_eq(eng.state.momentum, 5)
	await eng._play_card(card, backer)
	assert_true(eng.state.hand.has(card), "second-liners cannot be shoved: front-liners only")


# --- The relative front line (docs/block-and-patterns.md addendum) -------------
# An uncovered second-liner — nobody in the front slot of his own column —
# counts as standing in the front line: he fights, he takes the hits (the
# column rule always did that), and the bow needs cover to be a bow. Auras
# and the forced movements (shove, drive) stay on REAL positions.

func test_an_uncovered_second_liner_fights_his_column() -> void:
	var sword := TestHelpers.grunt(P, "sword", 12, 6, 3, 3, Weapon.sword())
	var e1 := TestHelpers.grunt(E, "e1", 30)
	var eng := TestHelpers.engine_for({"player_field": [sword], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, sword, B, 0)
	TestHelpers.station(eng.state.enemy_formation, e1, F, 0)
	await eng._fight_phase(P)
	assert_eq(e1.hp, 30 - 5, "nobody in front of him: he IS the front line, and he swings")


func test_a_covered_second_liner_without_reach_holds_his_place() -> void:
	var sword := TestHelpers.grunt(P, "sword", 12, 6, 3, 3, Weapon.sword())
	var cover := TestHelpers.grunt(P, "cover", 12, 6, 1, 2, null)
	var e1 := TestHelpers.grunt(E, "e1", 30)
	var eng := TestHelpers.engine_for({"player_field": [cover, sword], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, sword, B, 0)
	TestHelpers.station(eng.state.enemy_formation, e1, F, 0)
	await eng._fight_phase(P)
	assert_eq(e1.hp, 30 - 1, "only the cover man's fist lands: covered and reachless, he waits")


func test_an_uncovered_second_liner_closes_toward_the_fighting() -> void:
	var sword := TestHelpers.grunt(P, "sword", 12, 6, 3, 3, Weapon.sword())
	var e1 := TestHelpers.grunt(E, "e1", 30)
	var eng := TestHelpers.engine_for({"player_field": [sword], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, sword, B, 0)
	TestHelpers.station(eng.state.enemy_formation, e1, F, 2)
	await eng._fight_phase(P)
	assert_eq(eng.state.player_formation.column_of(sword), 1,
			"effectively front, his column empty of enemies: he walks the deck down")
	assert_eq(e1.pinned, 1, "and his closing step pins like any other")


func test_an_uncovered_archer_is_just_a_fighter() -> void:
	var bow := TestHelpers.grunt(P, "bow", 10, 5, 2, 3, Weapon.bow())
	var e1 := TestHelpers.grunt(E, "e1", 30)
	var eng := TestHelpers.engine_for({"player_field": [bow], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, bow, B, 0)
	TestHelpers.station(eng.state.enemy_formation, e1, F, 0)
	await eng._fight_phase(P)
	assert_eq(e1.hp, 30 - 3, "no cover, no bow work: 2 Str + 1 bow, hand to hand")
	assert_false(eng.state.archer_marks.has(bow), "and nothing is marked")


func test_cover_restores_the_bow() -> void:
	var bow := TestHelpers.grunt(P, "bow", 10, 5, 2, 3, Weapon.bow())
	var cover := TestHelpers.grunt(P, "cover")
	var e1 := TestHelpers.grunt(E, "e1", 30)
	var eng := TestHelpers.engine_for({"player_field": [cover, bow], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, bow, B, 0)
	await eng._fight_phase(P)
	assert_eq(eng.state.archer_marks.get(bow), e1, "a man in front of her: she aims again")
	assert_eq(e1.hp, 30 - 3, "the cover man's own swing still lands")


func test_relative_front_skips_the_boosts() -> void:
	var captain := TestHelpers.captain_of(P, "captain")
	var sword := TestHelpers.grunt(P, "sword", 12, 6, 3, 3, Weapon.sword())
	var e1 := TestHelpers.grunt(E, "e1", 30)
	var e2 := TestHelpers.grunt(E, "e2", 30)
	var eng := TestHelpers.engine_for({"player_field": [captain, sword],
			"enemy_field": [e1, e2]})
	TestHelpers.station(eng.state.player_formation, sword, B, 1)
	TestHelpers.station(eng.state.enemy_formation, e2, F, 1)
	await eng._fight_phase(P)
	assert_eq(e2.hp, 30 - 5, "he counts as front for the fight, but auras read REAL lines: " +
			"the captain at F0 is not his line-neighbor, no +1")


func test_forced_movement_reads_real_positions_not_relative_ones() -> void:
	var pc := TestHelpers.grunt(P, "pc")
	var lurker := TestHelpers.grunt(E, "lurker")
	var eng := TestHelpers.engine_for({"player_field": [pc], "enemy_field": [lurker]})
	TestHelpers.station(eng.state.enemy_formation, lurker, B, 1)
	assert_true(eng.shove_directions(lurker).is_empty(),
			"effectively front or not, Break the Line shoves the RANK AT THE RAIL only")
	assert_false(eng.can_drive_back(lurker), "and there is no further back to drive him")
