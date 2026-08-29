extends TestCase
## The boarding redesign: maneuvers, deck-driven reinforcement (Reinforce /
## Swap), the slot grid as the fielded cap, and the enemy captain as final
## reinforcement.

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
	assert_eq(eng.state.momentum, 6, "the crash of the boarding is the surge")


func test_controller_chooses_the_maneuver() -> void:
	var bot := ManeuverBot.new()
	bot.pick_id = "careful_assault"
	var crew := TestHelpers.grunt(P, "crew")
	var eng := TestHelpers.engine_for({
		"player_field": [crew],
		"maneuvers": [CardLibrary.maneuver_by_id("grapple_rush"), CardLibrary.maneuver_by_id("careful_assault")],
	}, bot)
	await eng._boarding_phase()
	assert_eq(eng.state.momentum, 2, "careful assault trades most of the surge for protection")
	assert_eq(eng.state.player_armor_bonus, 1, "the protection is battle-long armor, not a wall")


func test_maneuver_shield_wall_survives_turn_one() -> void:
	# No stock maneuver raises a wall right now; the engine mechanism must
	# still hold for future ones, so test it with a handmade maneuver card.
	var walled := CardData.new("test_walled_landing", "Walled Landing", 0,
			CardData.TargetType.NONE,
			[{"type": CardData.EffectType.SHIELD_WALL, "amount": 2}])
	var crew := TestHelpers.grunt(P, "crew")
	var eng := TestHelpers.engine_for({
		"player_field": [crew],
		"maneuvers": [walled],
	})
	await eng._boarding_phase()
	eng.state.turn = 1
	await eng._player_turn()
	assert_true(eng.state.shield_wall_active, "the wall covers the crossing AND the first exchange")
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


func test_dawn_raid_sends_defenders_below() -> void:
	var e1 := TestHelpers.grunt(E, "e1")
	var e2 := TestHelpers.grunt(E, "e2")
	var e3 := TestHelpers.grunt(E, "e3")
	var e4 := TestHelpers.grunt(E, "e4")
	var r1 := TestHelpers.grunt(E, "r1")
	var eng := TestHelpers.engine_for({
		"enemy_field": [e1, e2, e3, e4],
		"enemy_reserve": [r1],
		"maneuvers": [CardLibrary.maneuver_by_id("dawn_raid")],
	})
	await eng._boarding_phase()
	assert_eq(eng.state.momentum, 4)
	assert_eq(eng.state.enemy_formation.size(), 1, "the surprised watch is 3 men thinner")
	assert_true(eng.state.enemy_formation.has(e1), "the front of their line stays")
	assert_eq(eng.state.enemy_reserve.size(), 4, "nobody vanishes: they went below")
	assert_eq(eng.state.enemy_reserve[0], r1,
			"the sleepers join the BACK of the queue - delayed, not deleted")
	assert_eq(e4.morale, 4, "dragged from his hammock: -2 morale")
	assert_eq(e1.morale, 6, "the man still on watch is unshaken")


func test_covering_volley_shoots_every_player_phase() -> void:
	var archer_fodder := TestHelpers.grunt(P, "p1", 12, 6, 1, 3)
	var ship_archer := TestHelpers.grunt(P, "bow1", 10, 5, 2, 3, Weapon.bow())
	var e1 := TestHelpers.grunt(E, "e1", 30)
	var e2 := TestHelpers.grunt(E, "e2", 5)
	var eng := TestHelpers.engine_for({
		"player_field": [archer_fodder],
		"player_reserve": [ship_archer],
		"enemy_field": [e1, e2],
		"maneuvers": [CardLibrary.maneuver_by_id("covering_volley")],
	})
	await eng._boarding_phase()
	assert_eq(eng.state.momentum, 2)
	await eng._fight_phase(P)
	assert_eq(e2.hp, 3, "the volley picks the lowest-HP defender, true damage")
	await eng._fight_phase(P)
	assert_eq(e2.hp, 1, "and looses again every player fight phase")


func test_careful_assault_armors_the_crew() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1", 12, 6, 3, 3, Weapon.sword(), 0)
	var eng := TestHelpers.engine_for({
		"player_field": [p1],
		"enemy_field": [e1],
		"maneuvers": [CardLibrary.maneuver_by_id("careful_assault")],
	})
	await eng._boarding_phase()
	assert_eq(eng.state.player_armor_bonus, 1)
	await eng._attack(e1, p1)
	assert_eq(p1.hp, 12 - 4, "5 damage, -1 careful armor, every hit, all battle")


func test_careful_assault_lets_defenders_form_up() -> void:
	var e1 := TestHelpers.grunt(E, "e1")
	var r1 := TestHelpers.grunt(E, "r1")
	var r2 := TestHelpers.grunt(E, "r2")
	var eng := TestHelpers.engine_for({
		"enemy_field": [e1],
		"enemy_reserve": [r1, r2],
		"maneuvers": [CardLibrary.maneuver_by_id("careful_assault")],
	})
	await eng._boarding_phase()
	assert_eq(eng.state.enemy_formation.size(), 3, "a slow crossing: two extra defenders are ready")
	assert_true(eng.state.enemy_formation.has(r1))
	assert_true(eng.state.enemy_formation.has(r2), "they take their places in the line")
	assert_eq(e1.morale, 7, "and nobody is frightened: the watch stands composed")
	assert_eq(r2.morale, 7, "the whole crew is composed")


func test_reinforce_card_fields_first_reserve_by_default() -> void:
	var crew := TestHelpers.grunt(P, "crew")
	var r1 := TestHelpers.grunt(P, "r1")
	var r2 := TestHelpers.grunt(P, "r2")
	var eng := TestHelpers.engine_for({"player_field": [crew], "player_reserve": [r1, r2]})
	var card := CardLibrary.reinforce()
	eng.state.hand.append(card)
	eng.state.momentum = 1
	await eng._play_card(card, null)
	assert_true(eng.state.player_formation.has(r1), "first in reserve crosses")
	assert_false(eng.state.player_reserve.has(r1))
	assert_eq(eng.state.momentum, 0)


func test_reinforce_card_places_into_a_chosen_slot() -> void:
	var crew := TestHelpers.grunt(P, "crew")
	var r1 := TestHelpers.grunt(P, "r1")
	var eng := TestHelpers.engine_for({"player_field": [crew], "player_reserve": [r1]})
	var card := CardLibrary.reinforce()
	eng.state.hand.append(card)
	eng.state.momentum = 1
	await eng._play_card(card, r1, null, Formation.slot_index(Formation.BACK, 2))
	assert_eq(eng.state.player_formation.at(Formation.BACK, 2), r1,
			"Reinforce fields a man into the slot you choose")


func test_reinforce_card_honors_an_explicit_target() -> void:
	var crew := TestHelpers.grunt(P, "crew")
	var r1 := TestHelpers.grunt(P, "r1")
	var r2 := TestHelpers.grunt(P, "r2")
	var eng := TestHelpers.engine_for({"player_field": [crew], "player_reserve": [r1, r2]})
	var card := CardLibrary.reinforce()
	eng.state.hand.append(card)
	eng.state.momentum = 1
	await eng._play_card(card, r2)
	assert_true(eng.state.player_formation.has(r2), "the named man crosses")
	assert_true(eng.state.player_reserve.has(r1))


func test_reinforce_refused_when_field_full_or_reserve_empty() -> void:
	var field: Array[Character] = []
	for i in Formation.SLOT_COUNT:
		field.append(TestHelpers.grunt(P, "p%d" % i))
	var r1 := TestHelpers.grunt(P, "r1")
	var eng := TestHelpers.engine_for({"player_field": field, "player_reserve": [r1]})
	var card := CardLibrary.reinforce()
	eng.state.hand.append(card)
	eng.state.momentum = 5
	await eng._play_card(card, null)
	assert_true(eng.state.hand.has(card), "every slot is taken: refused, card kept")
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
	assert_eq(eng.state.player_formation.at(Formation.FRONT, 0), fresh,
			"a fresh man takes his exact slot")
	assert_eq(eng.state.momentum, 0)


func test_swap_trades_two_fielded_men() -> void:
	var front := TestHelpers.grunt(P, "front")
	var back := TestHelpers.grunt(P, "back", 12, 6, 3, 3, Weapon.spear())
	var eng := TestHelpers.engine_for({"player_field": [front, back]})
	TestHelpers.station(eng.state.player_formation, back, Formation.BACK, 0)
	var card := CardLibrary.swap()
	eng.state.hand.append(card)
	eng.state.momentum = 1
	await eng._play_card(card, front, back)
	assert_eq(eng.state.player_formation.at(Formation.FRONT, 0), back, "they trade slots")
	assert_eq(eng.state.player_formation.at(Formation.BACK, 0), front)
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
	assert_true(eng.state.player_formation.has(r2), "the chosen man crosses")
	assert_true(eng.state.player_reserve.has(r1), "not the first in line")


func test_swap_refused_without_a_reserve() -> void:
	var solo := TestHelpers.grunt(P, "solo")
	var eng := TestHelpers.engine_for({"player_field": [solo]})
	var card := CardLibrary.swap()
	eng.state.hand.append(card)
	eng.state.momentum = 1
	await eng._play_card(card, solo)
	assert_true(eng.state.hand.has(card), "no one to trade with: refused")


## The named partner is a reserve man whenever one is waiting — the card grew
## out of field↔reserve rotation and keeps that as its unnamed default.
func test_swap_takes_the_ship_first_when_a_man_waits_there() -> void:
	var front := TestHelpers.grunt(P, "front")
	var back := TestHelpers.grunt(P, "back")
	var waiting := TestHelpers.grunt(P, "waiting")
	var eng := TestHelpers.engine_for({
		"player_field": [front, back], "player_reserve": [waiting]})
	TestHelpers.station(eng.state.player_formation, back, Formation.BACK, 0)
	var card := CardLibrary.swap()
	eng.state.hand.append(card)
	eng.state.momentum = 1
	await eng._play_card(card, front)
	assert_true(eng.state.player_formation.has(waiting), "the man on the ship comes over")
	assert_true(eng.state.player_reserve.has(front), "the named man falls back")
	assert_eq(eng.state.player_formation.at(Formation.BACK, 0), back, "his fellow stays put")


## An empty ship must not refuse a trade the rules allow: with no one left to
## cross, the unnamed partner is a fellow already on deck.
func test_swap_falls_back_to_the_deck_when_the_ship_is_empty() -> void:
	var front := TestHelpers.grunt(P, "front")
	var back := TestHelpers.grunt(P, "back")
	var eng := TestHelpers.engine_for({"player_field": [front, back]})
	TestHelpers.station(eng.state.player_formation, back, Formation.BACK, 0)
	var card := CardLibrary.swap()
	eng.state.hand.append(card)
	eng.state.momentum = 1
	await eng._play_card(card, front)
	assert_false(eng.state.hand.has(card), "a fielded trade is legal with an empty reserve")
	assert_eq(eng.state.player_formation.at(Formation.FRONT, 0), back, "they trade slots")
	assert_eq(eng.state.player_formation.at(Formation.BACK, 0), front)
	assert_eq(eng.state.momentum, 0)


func test_commit_refused_when_every_slot_is_taken() -> void:
	var field: Array[Character] = []
	for i in Formation.SLOT_COUNT:
		field.append(TestHelpers.grunt(P, "p%d" % i))
	var r1 := TestHelpers.grunt(P, "r1")
	var eng := TestHelpers.engine_for({"player_field": field, "player_reserve": [r1]})
	eng.state.momentum = 5
	eng._commit_reserve(r1)
	assert_true(eng.state.player_reserve.has(r1), "the slots themselves are the cap")
	assert_eq(eng.state.momentum, 5)


func test_enemy_captain_is_the_final_reinforcement() -> void:
	var cap := TestHelpers.captain_of(E, "cap")
	var eng := TestHelpers.engine_for({
		"enemy_field": [TestHelpers.grunt(E, "e1")],
		"enemy_captain": cap,
	})
	eng._reinforce()
	assert_true(eng.state.enemy_formation.has(cap), "empty hold, room in the line: he steps in")


func test_enemy_captain_waits_while_reserves_remain() -> void:
	var cap := TestHelpers.captain_of(E, "cap")
	var r1 := TestHelpers.grunt(E, "r1")
	var eng := TestHelpers.engine_for({
		"enemy_field": [TestHelpers.grunt(E, "e1")],
		"enemy_reserve": [r1],
		"enemy_captain": cap,
	})
	eng._reinforce()
	assert_true(eng.state.enemy_formation.has(r1), "the hold empties first")
	assert_false(eng.state.enemy_formation.has(cap), "he still commands from the stern")


func test_enemy_captain_stays_back_behind_a_full_line() -> void:
	var cap := TestHelpers.captain_of(E, "cap")
	var field: Array[Character] = []
	for i in Formation.SLOT_COUNT:
		field.append(TestHelpers.grunt(E, "e%d" % i))
	var eng := TestHelpers.engine_for({"enemy_field": field, "enemy_captain": cap})
	eng._reinforce()
	assert_false(eng.state.enemy_formation.has(cap), "no free slot: he waits below")


func test_reinforcement_fills_front_gaps_left_to_right() -> void:
	var e1 := TestHelpers.grunt(E, "e1")
	var r1 := TestHelpers.grunt(E, "r1")
	var r2 := TestHelpers.grunt(E, "r2")
	var r3 := TestHelpers.grunt(E, "r3")
	var eng := TestHelpers.engine_for({
		"enemy_field": [e1],
		"enemy_reserve": [r1, r2, r3],
	})
	TestHelpers.station(eng.state.enemy_formation, e1, Formation.FRONT, 2)
	eng._reinforce()
	assert_eq(eng.state.enemy_formation.at(Formation.FRONT, 0), r1, "leftmost front gap first")
	assert_eq(eng.state.enemy_formation.at(Formation.FRONT, 1), r2)
	eng._reinforce()
	assert_eq(eng.state.enemy_formation.at(Formation.FRONT, 3), r3, "then the next gap along")


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
