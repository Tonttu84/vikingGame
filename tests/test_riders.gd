extends TestCase
## Movement riders (docs/lines-redesign.md, "Cards: movement rides on
## effects", phase D chunk 1). Most cards carry a movement rider after their
## punch: effect first, rider last. Riders are MANDATORY — when any legal
## move exists one must be taken; the controller picks which, never whether.
## A controller without the choose_rider hook (or answering illegally) gets
## the first legal move in reading order. Riders reposition inside the grid
## only: they never cross the rail, so the prow pair's law is untouched.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY
const F := Formation.FRONT
const B := Formation.BACK


## A controller that answers choose_rider with a fixed move, and records
## the list of legal moves the engine offered.
class RiderBot:
	var answer: Dictionary = {}
	var offered: Array = []

	func choose_action(_state: BattleState) -> Dictionary:
		return {"op": "end"}

	func choose_rider(_state: BattleState, _card: CardData,
			moves: Array[Dictionary]) -> Dictionary:
		offered = moves.duplicate()
		return answer


func _play(eng: CombatEngine, card: CardData, target: Character = null) -> void:
	eng.state.hand.append(card)
	eng.state.momentum = maxi(eng.state.momentum, card.cost)
	await eng._play_card(card, target)


func _log_index(eng: CombatEngine, needle: String) -> int:
	for i in eng.state.battle_log.size():
		if eng.state.battle_log[i].contains(needle):
			return i
	return -1


# --- Spear Volley narrows to the front line ----------------------------------

func test_spear_volley_hits_only_the_enemy_front_line() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1", 12, 6, 3, 3, null, 3)
	var e2 := TestHelpers.grunt(E, "e2")
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1, e2]})
	TestHelpers.station(eng.state.enemy_formation, e1, F, 0)
	TestHelpers.station(eng.state.enemy_formation, e2, B, 0)
	await _play(eng, CardLibrary.spear_volley())
	assert_eq(e1.hp, 10, "the front-liner eats the volley; card damage ignores armor")
	assert_eq(e2.hp, 12, "the second line is under the shields of the front rank")


# --- Mandatory: the rider fires without a hook -------------------------------

func test_rider_moves_a_man_even_without_the_controller_hook() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, F, 1)
	await _play(eng, CardLibrary.spear_volley())
	assert_eq(eng.state.player_formation.at(F, 0), p1,
			"no choose_rider: the first legal move in reading order, larboard first")
	assert_true(_log_index(eng, "sidesteps") != -1, "the move is logged")


func test_rider_is_skipped_silently_when_no_move_is_legal() -> void:
	var crew: Array[Character] = []
	for i in Formation.SLOT_COUNT:
		crew.append(TestHelpers.grunt(P, "p%d" % i))
	var eng := TestHelpers.engine_for({"player_field": crew,
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	var slots := eng.state.player_formation.slots.duplicate()
	await _play(eng, CardLibrary.war_cry())
	assert_true(eng.state.war_cry_active, "the card still does its job")
	assert_eq(eng.state.momentum, 0, "and is still paid for")
	for i in Formation.SLOT_COUNT:
		assert_eq(eng.state.player_formation.slots[i], slots[i],
				"a full grid has nowhere to slide")
	assert_eq(_log_index(eng, "sidesteps"), -1, "an impossible rider says nothing")


# --- Effect first, rider last ------------------------------------------------

func test_the_effect_resolves_before_the_rider() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1", 2)
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, p1, F, 1)
	await _play(eng, CardLibrary.spear_volley())
	var slain := _log_index(eng, "is slain")
	var stepped := _log_index(eng, "sidesteps")
	assert_true(slain != -1 and stepped != -1, "both the kill and the move happened")
	assert_true(slain < stepped, "the volley lands, THEN the man steps")


func test_rider_never_fires_when_the_card_ends_the_battle() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var jarl := TestHelpers.captain_of(E, "jarl", 2)
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_captain": jarl})
	eng.state.enemy_formation.place(jarl, F, 0)
	TestHelpers.station(eng.state.player_formation, p1, F, 1)
	await _play(eng, CardLibrary.spear_volley())
	assert_eq(eng.outcome, CombatEngine.Outcome.VICTORY, "the volley kills their captain")
	assert_eq(eng.state.player_formation.at(F, 1), p1, "a won battle carries no rider")


# --- The controller chooses which move ---------------------------------------

func test_controller_choice_is_respected() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var bot := RiderBot.new()
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"enemy_field": [TestHelpers.grunt(E, "e1")]}, bot)
	TestHelpers.station(eng.state.player_formation, p1, F, 1)
	bot.answer = {"character": p1, "direction": 1}
	await _play(eng, CardLibrary.feint())
	assert_eq(eng.state.player_formation.at(F, 2), p1, "starboard, as the controller asked")
	assert_eq(bot.offered.size(), 2, "both directions were on offer")


func test_illegal_controller_answer_falls_back_to_the_first_legal_move() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var p2 := TestHelpers.grunt(P, "p2")
	var bot := RiderBot.new()
	var eng := TestHelpers.engine_for({"player_field": [p1, p2],
			"enemy_field": [TestHelpers.grunt(E, "e1")]}, bot)
	TestHelpers.station(eng.state.player_formation, p2, F, 2)
	TestHelpers.station(eng.state.player_formation, p1, F, 1)
	# p1 cannot go starboard — p2 stands there.
	bot.answer = {"character": p1, "direction": 1}
	await _play(eng, CardLibrary.feint())
	assert_eq(eng.state.player_formation.at(F, 0), p1,
			"an illegal answer gets the first legal move, not a free pass")
	assert_eq(eng.state.player_formation.at(F, 2), p2, "and nobody else moves")


# --- Step: the healed man changes lines --------------------------------------

func test_rally_rider_retires_a_front_liner() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	p1.hp = 6
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, F, 2)
	await _play(eng, CardLibrary.rally(), p1)
	assert_eq(p1.hp, 10, "healed 4 first")
	assert_eq(eng.state.player_formation.at(B, 2), p1, "then he steps back into the second line")


func test_rally_rider_advances_a_back_liner() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	p1.hp = 6
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, B, 2)
	await _play(eng, CardLibrary.rally(), p1)
	assert_eq(eng.state.player_formation.at(F, 2), p1, "the other line is forward from back here")


func test_step_rider_is_skipped_when_his_column_is_stacked() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var p2 := TestHelpers.grunt(P, "p2")
	p1.hp = 6
	var eng := TestHelpers.engine_for({"player_field": [p1, p2],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, F, 2)
	TestHelpers.station(eng.state.player_formation, p2, B, 2)
	await _play(eng, CardLibrary.rally(), p1)
	assert_eq(p1.hp, 10, "the heal still lands")
	assert_eq(eng.state.player_formation.at(F, 2), p1, "his own column is stacked: nowhere to step")


# --- Advance: the furious man walks forward ----------------------------------

func test_battle_fury_rider_advances_a_back_liner_with_his_fury() -> void:
	var p1 := TestHelpers.grunt(P, "p1", 12, 6, 3, 3, Weapon.sword(), 0)
	var e1 := TestHelpers.grunt(E, "e1", 30)
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, p1, B, 0)
	TestHelpers.station(eng.state.enemy_formation, e1, F, 0)
	await _play(eng, CardLibrary.battle_fury(), p1)
	assert_eq(eng.state.player_formation.at(F, 0), p1, "he pushes into the empty front slot")
	assert_eq(p1.bonus_attacks, 1, "the fury travels with him")
	await eng._fight_phase(P)
	assert_eq(e1.hp, 30 - 5 - 5, "two swings from his new place in the line")


func test_advance_rider_has_no_legal_move_for_a_front_liner() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, F, 0)
	await _play(eng, CardLibrary.battle_fury(), p1)
	assert_eq(eng.state.player_formation.at(F, 0), p1, "already at the rail: he stays")
	assert_eq(p1.bonus_attacks, 1, "the card still gives its extra swing")


# --- Swap: two men on deck trade slots ---------------------------------------

func test_shield_wall_rider_trades_two_fielded_men() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var p2 := TestHelpers.grunt(P, "p2")
	var eng := TestHelpers.engine_for({"player_field": [p1, p2],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, F, 0)
	TestHelpers.station(eng.state.player_formation, p2, B, 2)
	await _play(eng, CardLibrary.shield_wall())
	assert_true(eng.state.shield_wall_active, "the wall goes up first")
	assert_eq(eng.state.player_formation.at(B, 2), p1, "exact slots trade")
	assert_eq(eng.state.player_formation.at(F, 0), p2)


func test_swap_rider_needs_two_men_on_deck() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"player_reserve": [TestHelpers.grunt(P, "p2")],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, F, 0)
	await _play(eng, CardLibrary.shield_wall())
	assert_true(eng.state.shield_wall_active, "the card still plays")
	assert_eq(eng.state.player_formation.at(F, 0), p1, "one man alone trades with nobody")
	assert_eq(eng.state.player_reserve.size(), 1, "and the rider never reaches over the rail")


func test_swap_rider_offers_pairs_in_reading_order() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var p2 := TestHelpers.grunt(P, "p2")
	var p3 := TestHelpers.grunt(P, "p3")
	var bot := RiderBot.new()
	var eng := TestHelpers.engine_for({"player_field": [p1, p2, p3],
			"enemy_field": [TestHelpers.grunt(E, "e1")]}, bot)
	TestHelpers.station(eng.state.player_formation, p1, F, 0)
	TestHelpers.station(eng.state.player_formation, p2, F, 1)
	TestHelpers.station(eng.state.player_formation, p3, B, 0)
	await _play(eng, CardLibrary.shield_wall())
	assert_eq(bot.offered.size(), 3, "three men make three pairs")
	assert_eq(bot.offered[0]["a"], p1, "reading order for both members")
	assert_eq(bot.offered[0]["b"], p2)
	assert_eq(eng.state.player_formation.at(F, 0), p2,
			"an empty answer is illegal: the first pair trades")


# --- The prow pair is untouched ----------------------------------------------

func test_rider_may_move_the_fielded_prowman() -> void:
	var prow := TestHelpers.grunt(P, "prow", 14, 8, 4, 3, Weapon.axe(), 1)
	prow.is_prowman = true
	var captain := TestHelpers.captain_of(P, "aslak")
	var eng := TestHelpers.engine_for({"player_field": [prow],
			"player_reserve": [captain],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, prow, F, 1)
	await _play(eng, CardLibrary.war_cry())
	assert_eq(eng.state.player_formation.at(F, 0), prow, "the prowman sidesteps like anyone")
	assert_true(eng.state.player_reserve.has(captain), "the captain keeps his own rail")
	assert_eq(eng.state.player_formation.size(), 1, "nobody crossed the rail")
	assert_eq(eng.outcome, CombatEngine.Outcome.NONE, "and the pair's hinge never trips")


# --- Card text ---------------------------------------------------------------

func test_rider_cards_say_they_move_you() -> void:
	assert_true(CardText.describe(CardLibrary.spear_volley()).contains("slide"),
			"the volley advertises its rider")
	assert_true(CardText.describe(CardLibrary.war_cry()).contains("must move"),
			"and that the move is not optional")
	assert_false(CardText.describe(CardLibrary.reinforce()).contains("slide"),
			"the crossing pair carries no rider")
