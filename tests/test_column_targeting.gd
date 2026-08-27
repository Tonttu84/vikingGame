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


func test_attack_into_an_empty_column_misses() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	TestHelpers.station(eng.state.enemy_formation, e1, F, 1)
	await eng._fight_phase(P)
	assert_eq(e1.hp, 12, "no one stands across from p1: nobody is hit")
	assert_true(_log_has(eng, "swings at air"), "the miss is spatial and visible")


func test_vacating_a_column_dodges_the_enemy_swing() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, p1, F, 3)
	await eng._fight_phase(E)
	assert_eq(p1.hp, 12, "their berserker hits nothing — dodging is placement")


func test_spear_reaches_from_the_second_line() -> void:
	var spear := TestHelpers.grunt(P, "spear", 12, 6, 3, 3, Weapon.spear())
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({"player_field": [spear], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, spear, B, 0)
	await eng._fight_phase(P)
	assert_eq(e1.hp, 12 - 4, "reach: 3 Str + 1 spear from the second line")


func test_other_weapons_cannot_melee_from_the_second_line() -> void:
	var sword := TestHelpers.grunt(P, "sword", 12, 6, 3, 3, Weapon.sword())
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({"player_field": [sword], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, sword, B, 0)
	await eng._fight_phase(P)
	assert_eq(e1.hp, 12, "a sword in the second line holds his place")
	assert_false(_log_has(eng, "swings at air"), "he is not swinging — he simply cannot reach")


func test_archer_snipes_the_weakest_fielded_enemy_anywhere() -> void:
	var bow := TestHelpers.grunt(P, "bow", 10, 5, 2, 3, Weapon.bow())
	var e1 := TestHelpers.grunt(E, "e1")
	var e2 := TestHelpers.grunt(E, "e2", 5, 6, 3, 3, null, 3)
	var eng := TestHelpers.engine_for({"player_field": [bow], "enemy_field": [e1, e2]})
	TestHelpers.station(eng.state.player_formation, bow, B, 0)
	TestHelpers.station(eng.state.enemy_formation, e2, F, 3)
	await eng._fight_phase(P)
	assert_eq(e2.hp, 3, "lowest HP, any column, armor ignored: flat 2")
	assert_eq(e1.hp, 12, "the healthy man is not worth an arrow")


func test_archer_snipe_tiebreak_is_spawn_order() -> void:
	var bow := TestHelpers.grunt(P, "bow", 10, 5, 2, 3, Weapon.bow())
	var e1 := TestHelpers.grunt(E, "e1")
	var e2 := TestHelpers.grunt(E, "e2")
	var eng := TestHelpers.engine_for({"player_field": [bow], "enemy_field": [e1, e2]})
	TestHelpers.station(eng.state.player_formation, bow, B, 0)
	await eng._fight_phase(P)
	assert_eq(e1.hp, 10, "equal HP: the earlier spawn is hit")
	assert_eq(e2.hp, 12)


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
	TestHelpers.station(eng.state.player_formation, bow, B, 3)
	TestHelpers.station(eng.state.enemy_formation, e_weak, B, 1)
	TestHelpers.station(eng.state.enemy_formation, e_front, F, 1)
	eng.state.focus_target = e_weak
	await eng._fight_phase(P)
	assert_eq(e_weak.hp, 30 - 3 - 2, "his column's attacker strikes past the front man; the archer joins")
	assert_eq(e_front.hp, 30, "the front man is bypassed, not hit")
	assert_true(_log_has(eng, "swings at air"), "focus does not grant reach across columns: pC still misses")


func test_challenge_makes_fielded_captains_trade_blows() -> void:
	var pcap := TestHelpers.captain_of(P, "pcap")
	var p1 := TestHelpers.grunt(P, "p1")
	var ecap := TestHelpers.captain_of(E, "ecap", 30)
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({
		"player_field": [pcap, p1],
		"enemy_field": [e1],
		"enemy_captain": ecap,
	})
	TestHelpers.station(eng.state.player_formation, p1, F, 1)
	TestHelpers.station(eng.state.enemy_formation, e1, F, 1)
	eng.state.enemy_formation.place(ecap, F, 3)
	var card := CardLibrary.challenge()
	eng.state.hand.append(card)
	eng.state.momentum = card.cost
	await eng._play_card(card, null)
	assert_true(eng.state.challenge_active, "the gauntlet is down")
	await eng._fight_phase(P)
	assert_eq(ecap.hp, 30 - 4, "your captain strikes theirs across the columns")
	assert_eq(e1.hp, 12 - 4, "everyone else fights his column as usual (+1: he stands at the captain's shoulder)")
	await eng._enemy_turn()
	assert_eq(pcap.hp, 20 - 4, "their captain answers in their fight phase")
	assert_false(eng.state.challenge_active, "the challenge is spent after their answer")


func test_challenge_refused_unless_both_captains_are_fielded() -> void:
	var pcap := TestHelpers.captain_of(P, "pcap")
	var ecap := TestHelpers.captain_of(E, "ecap", 30)
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({
		"player_field": [pcap],
		"enemy_field": [e1],
		"enemy_captain": ecap,
	})
	var card := CardLibrary.challenge()
	eng.state.hand.append(card)
	eng.state.momentum = 5
	await eng._play_card(card, null)
	assert_true(eng.state.hand.has(card), "their captain still waits below: refused, card kept")
	assert_eq(eng.state.momentum, 5, "nothing paid")
	assert_false(eng.state.challenge_active)


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
