extends TestCase
## The boarding redesign: maneuvers, deck-driven reinforcement (Reinforce /
## Swap), the player field cap, and the enemy captain as final reinforcement.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY


class ManeuverBot extends TestHelpers.ScriptedBot:
	var pick_id := ""

	func choose_maneuver(_state: BattleState, options: Array[CardData]) -> CardData:
		for m in options:
			if m.id == pick_id:
				return m
		return options[0]


func test_maneuver_library_builds_by_id() -> void:
	var m := CardLibrary.maneuver_by_id("grapple_rush")
	assert_true(m != null)
	assert_eq(m.id, "grapple_rush")
	assert_eq(CardLibrary.maneuver_by_id("no_such_maneuver"), null)
	for id in CardLibrary.maneuver_ids():
		var built := CardLibrary.maneuver_by_id(id)
		assert_true(built != null and built.id == id, "every maneuver id builds: " + id)


func test_default_maneuver_grants_opening_momentum() -> void:
	var crew := TestHelpers.grunt(P, "crew")
	var eng := TestHelpers.engine_for({
		"player_field": [crew],
		"maneuvers": [CardLibrary.maneuver_by_id("grapple_rush")],
	})
	await eng._boarding_phase()
	assert_eq(eng.state.momentum, 5, "the crash of the boarding is the surge")


func test_controller_chooses_the_maneuver() -> void:
	var bot := ManeuverBot.new()
	bot.pick_id = "shield_roof"
	var crew := TestHelpers.grunt(P, "crew")
	var eng := TestHelpers.engine_for({
		"player_field": [crew],
		"maneuvers": [CardLibrary.maneuver_by_id("grapple_rush"), CardLibrary.maneuver_by_id("shield_roof")],
	}, bot)
	await eng._boarding_phase()
	assert_eq(eng.state.momentum, 3, "shield roof trades surge for cover")
	assert_true(eng.state.shield_wall_active, "the roof is up for turn 1")


func test_shield_roof_survives_turn_one() -> void:
	var bot := ManeuverBot.new()
	bot.pick_id = "shield_roof"
	var crew := TestHelpers.grunt(P, "crew")
	var eng := TestHelpers.engine_for({
		"player_field": [crew],
		"maneuvers": [CardLibrary.maneuver_by_id("shield_roof")],
	}, bot)
	await eng._boarding_phase()
	eng.state.turn = 1
	await eng._player_turn()
	assert_true(eng.state.shield_wall_active, "the roof covers the crossing AND the first exchange")
	eng.state.turn = 2
	await eng._player_turn()
	assert_false(eng.state.shield_wall_active, "then it comes down as usual")


func test_maneuver_deck_stays_out_of_the_battle_deck() -> void:
	var crew := TestHelpers.grunt(P, "crew")
	var eng := TestHelpers.engine_for({
		"player_field": [crew],
		"deck": CardLibrary.starter_deck(),
		"maneuvers": [CardLibrary.maneuver_by_id("grapple_rush")],
	})
	var deck_and_hand := eng.state.deck.size() + eng.state.hand.size()
	await eng._boarding_phase()
	assert_eq(eng.state.deck.size() + eng.state.hand.size(), deck_and_hand,
			"the maneuver never enters draw pile or hand")
	assert_true(eng.state.discard.is_empty(), "nor the discard: it is set aside")


func test_no_maneuvers_means_no_surge() -> void:
	var crew := TestHelpers.grunt(P, "crew")
	var eng := TestHelpers.engine_for({"player_field": [crew]})
	await eng._boarding_phase()
	assert_eq(eng.state.momentum, 0, "bare scenarios (unit tests) start cold")


func test_screaming_charge_frightens_defenders() -> void:
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({
		"enemy_field": [e1],
		"maneuvers": [CardLibrary.maneuver_by_id("screaming_charge")],
	})
	await eng._boarding_phase()
	assert_eq(e1.morale, 5, "1 morale damage as the screamers come over the rail")


func test_reinforce_card_fields_first_reserve_by_default() -> void:
	var crew := TestHelpers.grunt(P, "crew")
	var r1 := TestHelpers.grunt(P, "r1")
	var r2 := TestHelpers.grunt(P, "r2")
	var eng := TestHelpers.engine_for({"player_field": [crew], "player_reserve": [r1, r2]})
	var card := CardLibrary.reinforce()
	eng.state.hand.append(card)
	eng.state.momentum = 1
	await eng._play_card(card, null)
	assert_true(eng.state.player_field.has(r1), "first in reserve crosses")
	assert_false(eng.state.player_reserve.has(r1))
	assert_eq(eng.state.momentum, 0)


func test_reinforce_card_honors_an_explicit_target() -> void:
	var crew := TestHelpers.grunt(P, "crew")
	var r1 := TestHelpers.grunt(P, "r1")
	var r2 := TestHelpers.grunt(P, "r2")
	var eng := TestHelpers.engine_for({"player_field": [crew], "player_reserve": [r1, r2]})
	var card := CardLibrary.reinforce()
	eng.state.hand.append(card)
	eng.state.momentum = 1
	await eng._play_card(card, r2)
	assert_true(eng.state.player_field.has(r2), "the named man crosses")
	assert_true(eng.state.player_reserve.has(r1))


func test_reinforce_refused_when_field_full_or_reserve_empty() -> void:
	var field: Array[Character] = []
	for i in BattleState.PLAYER_FIELD_CAP:
		field.append(TestHelpers.grunt(P, "p%d" % i))
	var r1 := TestHelpers.grunt(P, "r1")
	var eng := TestHelpers.engine_for({"player_field": field, "player_reserve": [r1]})
	var card := CardLibrary.reinforce()
	eng.state.hand.append(card)
	eng.state.momentum = 5
	await eng._play_card(card, null)
	assert_true(eng.state.hand.has(card), "the rail is packed: refused, card kept")
	assert_eq(eng.state.momentum, 5, "nothing paid")
	var eng2 := TestHelpers.engine_for({"player_field": [TestHelpers.grunt(P, "solo")]})
	var card2 := CardLibrary.reinforce()
	eng2.state.hand.append(card2)
	eng2.state.momentum = 5
	await eng2._play_card(card2, null)
	assert_true(eng2.state.hand.has(card2), "nobody left on the ship: refused")


func test_swap_rotates_wounded_for_fresh() -> void:
	var tired := TestHelpers.grunt(P, "tired")
	tired.hp = 3
	var e1 := TestHelpers.grunt(E, "e1", 30)
	tired.engaged_with = e1
	var fresh := TestHelpers.grunt(P, "fresh")
	var eng := TestHelpers.engine_for({
		"player_field": [tired],
		"player_reserve": [fresh],
		"enemy_field": [e1],
	})
	var card := CardLibrary.swap()
	eng.state.hand.append(card)
	eng.state.momentum = 1
	await eng._play_card(card, tired)
	assert_true(eng.state.player_reserve.has(tired), "the wounded man falls back")
	assert_true(eng.state.player_field.has(fresh), "a fresh man takes his place")
	assert_eq(tired.engaged_with, null, "no one duels from the far ship")
	assert_eq(eng.state.momentum, 0)


func test_swap_honors_explicit_second_target() -> void:
	var out := TestHelpers.grunt(P, "out")
	var r1 := TestHelpers.grunt(P, "r1")
	var r2 := TestHelpers.grunt(P, "r2")
	var eng := TestHelpers.engine_for({"player_field": [out], "player_reserve": [r1, r2]})
	var card := CardLibrary.swap()
	eng.state.hand.append(card)
	eng.state.momentum = 1
	await eng._play_card(card, out, r2)
	assert_true(eng.state.player_field.has(r2), "the chosen man crosses")
	assert_true(eng.state.player_reserve.has(r1), "not the first in line")


func test_swap_refused_without_a_reserve() -> void:
	var solo := TestHelpers.grunt(P, "solo")
	var eng := TestHelpers.engine_for({"player_field": [solo]})
	var card := CardLibrary.swap()
	eng.state.hand.append(card)
	eng.state.momentum = 1
	await eng._play_card(card, solo)
	assert_true(eng.state.hand.has(card), "no one to trade with: refused")


func test_commit_respects_the_rail_cap() -> void:
	var field: Array[Character] = []
	for i in BattleState.PLAYER_FIELD_CAP:
		field.append(TestHelpers.grunt(P, "p%d" % i))
	var r1 := TestHelpers.grunt(P, "r1")
	var eng := TestHelpers.engine_for({"player_field": field, "player_reserve": [r1]})
	eng.state.momentum = 5
	eng._commit_reserve(r1)
	assert_true(eng.state.player_reserve.has(r1), "the rail is a bottleneck")
	assert_eq(eng.state.momentum, 5)


func test_enemy_captain_is_the_final_reinforcement() -> void:
	var cap := TestHelpers.captain_of(E, "cap")
	var eng := TestHelpers.engine_for({
		"enemy_field": [TestHelpers.grunt(E, "e1")],
		"enemy_captain": cap,
	})
	eng._reinforce()
	assert_true(eng.state.enemy_field.has(cap), "empty hold, room in the line: he steps in")
	assert_true(eng.state.enemy_captain_targetable(), "and now he can be reached")


func test_enemy_captain_waits_while_reserves_remain() -> void:
	var cap := TestHelpers.captain_of(E, "cap")
	var r1 := TestHelpers.grunt(E, "r1")
	var eng := TestHelpers.engine_for({
		"enemy_field": [TestHelpers.grunt(E, "e1")],
		"enemy_reserve": [r1],
		"enemy_captain": cap,
	})
	eng._reinforce()
	assert_true(eng.state.enemy_field.has(r1), "the hold empties first")
	assert_false(eng.state.enemy_field.has(cap), "he still commands from the stern")


func test_enemy_captain_stays_back_behind_a_full_line() -> void:
	var cap := TestHelpers.captain_of(E, "cap")
	var field: Array[Character] = []
	for i in BattleState.ENEMY_FIELD_CAP:
		field.append(TestHelpers.grunt(E, "e%d" % i))
	var eng := TestHelpers.engine_for({"enemy_field": field, "enemy_captain": cap})
	eng._reinforce()
	assert_false(eng.state.enemy_field.has(cap), "no room in the line")
	assert_false(eng.state.enemy_captain_targetable(),
			"an empty hold behind a full line no longer exposes him")


func test_boarding_repulsed_when_field_empties() -> void:
	var lone := TestHelpers.grunt(P, "lone", 1)
	var brute := TestHelpers.grunt(E, "brute", 30, 10, 10, 3)
	var eng := TestHelpers.engine_for({
		"player_field": [lone],
		"player_reserve": [TestHelpers.grunt(P, "stay_home")],
		"enemy_field": [brute],
	}, Bots.NoCardBot.new())
	var result: Dictionary = await eng.run()
	assert_eq(result["outcome"], "RETREAT",
			"no boarders left on their deck = repulsed, not a 60-turn stalemate")
	assert_true(result["turns"] < 10, "and it ends promptly")


func test_fielded_enemy_captain_fights() -> void:
	var cap := TestHelpers.captain_of(E, "cap")
	var p1 := TestHelpers.grunt(P, "p1")
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_captain": cap})
	eng._reinforce()
	var order := eng._attack_order(E)
	assert_true(order.has(cap), "in the line, he swings like anyone else")
	await eng._fight_phase(E)
	assert_true(p1.hp < p1.max_hp, "and his blows land")
