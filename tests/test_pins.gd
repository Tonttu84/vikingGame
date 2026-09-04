extends TestCase
## The closing pin (docs/block-and-patterns.md): a man closed on is PINNED —
## no movement at all, by any hand, until the stacks decay. The number grows
## with each repeat (1st pin 1 turn, 2nd +2, 3rd +3...), so dodging buys
## turns at a rising price and can never become a permanent escape.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY
const F := Formation.FRONT
const B := Formation.BACK


func _log_has(eng: CombatEngine, needle: String) -> bool:
	for line in eng.state.battle_log:
		if line.contains(needle):
			return true
	return false


# --- The pin lands and grows ---------------------------------------------------

func test_the_closing_step_pins_the_man_closed_toward() -> void:
	var dodger := TestHelpers.grunt(P, "dodger")
	var closer := TestHelpers.grunt(E, "closer")
	var eng := TestHelpers.engine_for({"player_field": [dodger], "enemy_field": [closer]})
	TestHelpers.station(eng.state.player_formation, dodger, F, 0)
	TestHelpers.station(eng.state.enemy_formation, closer, F, 2)
	await eng._fight_phase(E)
	assert_eq(eng.state.enemy_formation.column_of(closer), 1, "the closer steps toward him")
	assert_eq(dodger.pinned, 1, "and the dodger is pinned where he stands")
	assert_eq(dodger.pin_count, 1, "")
	assert_true(_log_has(eng, "pinned"), "the pin is in the saga")


func test_repeat_pins_grow() -> void:
	var dodger := TestHelpers.grunt(P, "dodger")
	var eng := TestHelpers.engine_for({"player_field": [dodger]})
	eng._pin_down(dodger)
	assert_eq(dodger.pinned, 1, "first dodge: one turn")
	eng._pin_down(dodger)
	assert_eq(dodger.pinned, 3, "second: two more, on top of what stands")
	eng._pin_down(dodger)
	assert_eq(dodger.pinned, 6, "third: three more — the price keeps rising")


func test_pins_decay_one_per_own_turn() -> void:
	var dodger := TestHelpers.grunt(P, "dodger")
	var eng := TestHelpers.engine_for({"player_field": [dodger]})
	dodger.pinned = 2
	eng._tick_statuses(P)
	assert_eq(dodger.pinned, 1, "his own turn passing works one stack loose")
	eng._tick_statuses(E)
	assert_eq(dodger.pinned, 1, "the other side's turns do not count")
	eng._tick_statuses(P)
	assert_eq(dodger.pinned, 0, "free again — pin_count remembers, though")
	assert_eq(dodger.pin_count, 0, "(no pins were ever landed here, only stacks set)")


# --- While pinned, nothing moves him --------------------------------------------

func test_the_formation_verbs_refuse_a_pinned_man() -> void:
	var f := Formation.new()
	var pinned_man := TestHelpers.grunt(P, "pinned_man")
	pinned_man.pinned = 1
	var fellow := TestHelpers.grunt(P, "fellow")
	f.place(pinned_man, F, 1)
	f.place(fellow, B, 3)
	assert_false(f.slide(pinned_man, 1), "no sidestep")
	assert_false(f.retire(pinned_man), "no giving ground")
	assert_false(f.swap_positions(pinned_man, fellow), "no trading places")
	f.remove(pinned_man)
	f.place(pinned_man, B, 1)
	assert_false(f.advance(pinned_man), "no stepping up")


func test_a_pinned_man_cannot_take_the_closing_step_himself() -> void:
	var runner := TestHelpers.grunt(E, "runner")
	var pc := TestHelpers.grunt(P, "pc")
	var eng := TestHelpers.engine_for({"player_field": [pc], "enemy_field": [runner]})
	TestHelpers.station(eng.state.player_formation, pc, F, 0)
	TestHelpers.station(eng.state.enemy_formation, runner, F, 2)
	runner.pinned = 1
	await eng._fight_phase(E)
	assert_eq(eng.state.enemy_formation.column_of(runner), 2, "held fast where he stands")
	assert_true(_log_has(eng, "swings at air"), "his swing finds nothing and he cannot walk")
	assert_eq(pc.pinned, 0, "a step never taken pins nobody")


func test_the_rider_gate_refuses_a_card_whose_only_mover_is_pinned() -> void:
	var stuck := TestHelpers.grunt(P, "stuck")
	var walled := TestHelpers.grunt(P, "walled")
	var ec := TestHelpers.grunt(E, "ec")
	var eng := TestHelpers.engine_for({"player_field": [stuck, walled], "enemy_field": [ec]})
	TestHelpers.station(eng.state.player_formation, walled, F, 2)
	TestHelpers.station(eng.state.player_formation, stuck, F, 1)
	var card := CardLibrary.war_cry()  # rider: port
	eng.state.hand.append(card)
	eng.state.momentum = 5
	assert_true(eng.can_play(card), "walled cannot step port, but stuck can: playable")
	stuck.pinned = 1
	assert_false(eng.can_play(card), "the one legal mover is pinned: the movement cannot be paid")


func test_trade_places_refuses_the_pinned() -> void:
	var pinned_man := TestHelpers.grunt(P, "pinned_man")
	var fellow := TestHelpers.grunt(P, "fellow")
	var shipman := TestHelpers.grunt(P, "shipman")
	var ec := TestHelpers.grunt(E, "ec")
	var eng := TestHelpers.engine_for({
		"player_field": [pinned_man, fellow],
		"player_reserve": [shipman],
		"enemy_field": [ec],
	})
	var card := CardLibrary.swap()
	eng.state.hand.append(card)
	eng.state.momentum = 5
	pinned_man.pinned = 1
	assert_false(eng.can_play(card, pinned_man, shipman), "a pinned man trades with nobody")
	assert_true(eng.swap_partners(pinned_man).is_empty(), "the UI is offered nothing for him")
	assert_false(eng.swap_partners(fellow).has(pinned_man),
			"and nobody is offered the pinned man as a partner")
	assert_true(eng.can_play(card, fellow, shipman), "his fellows still trade freely")


func test_taunt_and_the_shoves_cannot_move_a_pinned_enemy() -> void:
	var anchor := TestHelpers.grunt(P, "anchor")
	var pinned_foe := TestHelpers.grunt(E, "pinned_foe")
	var eng := TestHelpers.engine_for({"player_field": [anchor], "enemy_field": [pinned_foe]})
	TestHelpers.station(eng.state.player_formation, anchor, F, 0)
	TestHelpers.station(eng.state.enemy_formation, pinned_foe, F, 2)
	pinned_foe.pinned = 1
	assert_false(eng.taunt_targets(anchor).has(pinned_foe), "no shout drags a pinned man")
	assert_true(eng.shove_directions(pinned_foe).is_empty(), "no shove moves him")
	assert_false(eng.can_drive_back(pinned_foe), "no drive sends him back")


func test_the_reaction_save_cannot_reach_a_pinned_man() -> void:
	var doomed := TestHelpers.grunt(P, "doomed")
	var ec := TestHelpers.grunt(E, "ec")
	var eng := TestHelpers.engine_for({"player_field": [doomed], "enemy_field": [ec]})
	eng.state.hand.append(CardLibrary.drag_him_back())
	eng.state.momentum = 5
	doomed.pinned = 1
	await eng._deal_true_damage(doomed, 99)
	assert_true(eng.state.player_dead.has(doomed), "pinned, he dies where he stands")
	assert_eq(eng.state.hand.size(), 1, "the save is not spent on a man it cannot reach")


func test_get_back_cannot_pull_a_pinned_man_off_the_deck() -> void:
	var pinned_man := TestHelpers.grunt(P, "pinned_man")
	var ec := TestHelpers.grunt(E, "ec")
	var eng := TestHelpers.engine_for({"player_field": [pinned_man], "enemy_field": [ec]})
	var card := CardLibrary.drag_him_back()
	eng.state.hand.append(card)
	eng.state.momentum = 5
	assert_true(eng.can_play(card, pinned_man), "unpinned, the pull is legal")
	pinned_man.pinned = 1
	assert_false(eng.can_play(card, pinned_man), "quitting the deck is movement too")


func test_the_captains_calls_leave_a_pinned_man_standing() -> void:
	var pinned_foe := TestHelpers.grunt(E, "pinned_foe")
	var slider := TestHelpers.grunt(E, "slider")
	var partner := TestHelpers.grunt(E, "partner")
	var eng := TestHelpers.engine_for({"enemy_field": [pinned_foe, slider, partner]})
	TestHelpers.station(eng.state.enemy_formation, partner, B, 2)
	TestHelpers.station(eng.state.enemy_formation, pinned_foe, F, 2)
	TestHelpers.station(eng.state.enemy_formation, slider, F, 0)
	pinned_foe.pinned = 1
	await eng._resolve_tactic("shift_starboard")
	assert_eq(eng.state.enemy_formation.column_of(pinned_foe), 2, "pinned at the board's heart")
	assert_eq(eng.state.enemy_formation.column_of(slider), 1, "the line shifts around him")
	assert_eq(eng.state.enemy_formation.column_of(partner), 3,
			"only HE is pinned: his unpinned back-liner slides with the call")
	TestHelpers.station(eng.state.enemy_formation, partner, B, 2)
	await eng._resolve_tactic("fresh_men_forward")
	assert_eq(eng.state.enemy_formation.at(F, 2), pinned_foe,
			"his column does not trade on fresh-men-forward")
	assert_eq(eng.state.enemy_formation.at(B, 2), partner,
			"and the man behind him cannot land in a pinned slot")


func test_death_still_removes_a_pinned_man() -> void:
	var pinned_foe := TestHelpers.grunt(E, "pinned_foe")
	var witness := TestHelpers.grunt(E, "witness")
	var eng := TestHelpers.engine_for({"enemy_field": [pinned_foe, witness]})
	pinned_foe.pinned = 3
	await eng._deal_true_damage(pinned_foe, 99)
	assert_false(eng.state.enemy_formation.has(pinned_foe), "the grave is not a move")
	assert_true(eng.state.enemy_dead.has(pinned_foe), "")
