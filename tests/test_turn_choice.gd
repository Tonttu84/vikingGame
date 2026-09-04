extends TestCase
## THE OPENING: the forced three-way choice at the head of every player turn
## (owner's ruling 2026-09-05, docs/combat-design.md "Turn structure").
## Before a single card may be played the crew does exactly one of:
##   * a free reinforcement — a man off the ship into a slot you pick;
##   * a free swap ("snap") — two of your men trade places, fielded↔fielded
##     or fielded↔reserve;
##   * the income — +1 momentum AND +1 card, on top of the turn's own +1.
## So the two free moves cost precisely one momentum and one card of tempo,
## and neither is ever free of that price. The prow pair's law is untouched:
## the pair crosses only by trading with each other. The old momentum
## commit is gone — this replaces it.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY
const F := Formation.FRONT
const B := Formation.BACK


## Two men on the field, one waiting on the ship: reinforce, swap and income
## are all legal, so the engine has a real question to ask. The enemy fills
## all four columns with harmless meat, so that the fight phase at the end of
## the turn moves nobody: with a column empty across from him, a man closes
## toward the fighting, and these tests are about where the OPENING put him.
func _engine(openings: Array = []) -> CombatEngine:
	var bot := TestHelpers.OpeningBot.new(openings)
	var eng := CombatEngine.new()
	bot.engine = eng
	var wall: Array[Character] = []
	for col in Formation.COLUMNS:
		wall.append(TestHelpers.grunt(E, "foe%d" % col, 60, 20, 1, 3))
	eng.setup({
		"player_field": [TestHelpers.grunt(P, "crew1"), TestHelpers.grunt(P, "crew2")],
		"player_reserve": [TestHelpers.grunt(P, "crew3")],
		"enemy_field": wall,
		"deck": CardLibrary.starter_deck(),
	}, bot, 7)
	return eng


func _prowman(id := "prow") -> Character:
	var c := TestHelpers.grunt(P, id, 14, 8, 4, 3, Weapon.axe(), 1)
	c.is_prowman = true
	return c


## Prowman + one grunt on the field; captain + one grunt on the ship.
func _pair_engine(openings: Array = []) -> CombatEngine:
	var bot := TestHelpers.OpeningBot.new(openings)
	var eng := CombatEngine.new()
	bot.engine = eng
	eng.setup({
		"player_field": [_prowman(), TestHelpers.grunt(P, "crew1")],
		"player_reserve": [TestHelpers.captain_of(P, "aslak"), TestHelpers.grunt(P, "crew2")],
		"enemy_field": [TestHelpers.grunt(E, "foe1", 40)],
		"deck": CardLibrary.starter_deck(),
	}, bot, 7)
	return eng


# --- The hook itself ----------------------------------------------------------

func test_the_opening_is_asked_at_the_head_of_every_player_turn() -> void:
	var eng := _engine()
	await eng._player_turn()
	await eng._player_turn()
	var bot: TestHelpers.OpeningBot = eng.controller
	assert_eq(bot.asked.size(), 2, "asked once per player turn, never twice, never never")
	assert_eq(bot.asked[0], ["reinforce", "swap", "income"] as Array[String],
			"and asked with the options that are legal right now")


func test_the_opening_comes_before_the_cards() -> void:
	# The hand is dealt first (you choose knowing what you hold), but nothing
	# is playable until the opening is answered: the engine resolves it before
	# it ever calls choose_action.
	var eng := _engine()
	var seen := {"hand": -1, "momentum": -1}
	var bot: TestHelpers.OpeningBot = eng.controller
	bot.openings = [{"op": "income"}]
	bot.actions = []
	await eng._player_turn()
	seen["hand"] = eng.state.hand.size()
	seen["momentum"] = eng.state.momentum
	assert_eq(seen["hand"], 6, "the opening's card is in hand before the first play")
	assert_eq(seen["momentum"], 2, "and its momentum is banked")


func test_only_income_legal_never_asks() -> void:
	# One man, no ship, nobody to trade with: there is nothing to choose, and
	# a pick with one option answers itself (as everywhere else on the table).
	var bot := TestHelpers.OpeningBot.new()
	var eng := CombatEngine.new()
	bot.engine = eng
	eng.setup({"player_field": [TestHelpers.grunt(P, "crew")]}, bot, 7)
	await eng._player_turn()
	assert_true(bot.asked.is_empty(), "nothing to ask: the income resolves itself")
	assert_eq(eng.state.momentum, 2, "and it is still the income that resolved")


func test_a_controller_without_the_hook_takes_the_income() -> void:
	var eng := TestHelpers.engine_for({
		"player_field": [TestHelpers.grunt(P, "crew1")],
		"player_reserve": [TestHelpers.grunt(P, "crew2")],
		"deck": CardLibrary.starter_deck(),
	})
	await eng._player_turn()
	assert_eq(eng.state.momentum, 2, "the plain ScriptedBot answers nothing and gets the income")
	assert_eq(eng.state.player_formation.size(), 1, "no free move happens by accident")


func test_an_unknown_op_takes_the_income() -> void:
	var eng := _engine([{"op": "plunder"}])
	await eng._player_turn()
	assert_eq(eng.state.momentum, 2, "an answer the engine does not know is the income")
	assert_eq(eng.state.player_formation.size(), 2, "and nobody crossed on the strength of it")


# --- (c) The income -----------------------------------------------------------

func test_income_pays_a_momentum_and_a_card() -> void:
	var eng := _engine([{"op": "income"}])
	await eng._player_turn()
	assert_eq(eng.state.momentum, 2, "+1 turn income, +1 for the opening")
	assert_eq(eng.state.hand.size(), 6, "the refilled five plus the opening's card")


func test_income_still_obeys_the_momentum_cap() -> void:
	var eng := _engine([{"op": "income"}])
	eng.state.momentum = BattleState.MOMENTUM_CAP
	await eng._player_turn()
	assert_eq(eng.state.momentum, BattleState.MOMENTUM_CAP, "the cap is the cap")


func test_income_at_a_full_hand_leaves_the_card_in_the_deck() -> void:
	var eng := _engine([{"op": "income"}])
	for i in BattleState.MAX_HAND_SIZE:
		eng.state.hand.append(CardLibrary.reinforce())  # Retained: survives the cycle
	var deck_before := eng.state.deck.size()
	await eng._player_turn()
	assert_eq(eng.state.hand.size(), BattleState.MAX_HAND_SIZE, "seven is the ceiling")
	assert_eq(eng.state.deck.size(), deck_before, "the undealt card stays in the deck")
	assert_eq(eng.state.momentum, 2, "the momentum half of the income is paid regardless")


# --- (a) The free reinforcement -----------------------------------------------

func test_the_free_reinforcement_fields_the_named_man_on_the_picked_slot() -> void:
	var eng := _engine()
	var crosser: Character = eng.state.player_reserve[0]
	var slot := Formation.slot_index(B, 3)
	var bot: TestHelpers.OpeningBot = eng.controller
	bot.openings = [{"op": "reinforce", "character": crosser, "slot": slot}]
	await eng._player_turn()
	assert_eq(eng.state.player_formation.at(B, 3), crosser, "he takes the slot he was sent to")
	assert_true(eng.state.player_reserve.is_empty(), "and he is off the ship")
	assert_eq(eng.state.momentum, 1, "the crossing is free: only the turn's own +1")
	assert_eq(eng.state.hand.size(), 5, "and it draws nothing")


func test_the_crossing_man_starts_his_rhythm_fresh() -> void:
	var eng := _engine()
	var crosser: Character = eng.state.player_reserve[0]
	crosser.beat = 1
	var bot: TestHelpers.OpeningBot = eng.controller
	bot.openings = [{"op": "reinforce", "character": crosser}]
	await eng._player_turn()
	assert_eq(crosser.beat, 0, "a man fielded mid-battle opens his pattern from the top")


func test_a_slot_that_is_not_free_falls_back_to_the_first_one_that_is() -> void:
	var eng := _engine()
	var crosser: Character = eng.state.player_reserve[0]
	var bot: TestHelpers.OpeningBot = eng.controller
	# Slot 0 holds crew1; -1 names no slot at all. Both fall back.
	bot.openings = [{"op": "reinforce", "character": crosser, "slot": 0}]
	var expected := eng.state.player_formation.first_free_index()
	await eng._player_turn()
	assert_eq(eng.state.player_formation.slots[expected], crosser,
			"an occupied slot is no refusal — he takes the first free one")


func test_a_full_formation_drops_reinforce_from_the_options() -> void:
	var field: Array[Character] = []
	for i in Formation.SLOT_COUNT:
		field.append(TestHelpers.grunt(P, "p%d" % i))
	var bot := TestHelpers.OpeningBot.new()
	var eng := CombatEngine.new()
	bot.engine = eng
	eng.setup({"player_field": field, "player_reserve": [TestHelpers.grunt(P, "r1")]}, bot, 7)
	assert_false(eng.opening_options().has("reinforce"), "the slots themselves are the cap")


func test_an_empty_ship_drops_reinforce_from_the_options() -> void:
	var eng := TestHelpers.engine_for({"player_field": [TestHelpers.grunt(P, "crew1"),
			TestHelpers.grunt(P, "crew2")]})
	assert_false(eng.opening_options().has("reinforce"), "nobody left to send")
	assert_true(eng.opening_options().has("swap"), "but two men on deck can still trade")


func test_the_prow_pair_never_crosses_by_the_free_reinforcement() -> void:
	var eng := _pair_engine()
	var captain := eng.state.player_captain
	var bot: TestHelpers.OpeningBot = eng.controller
	bot.openings = [{"op": "reinforce", "character": captain}]
	await eng._player_turn()
	assert_true(eng.state.player_reserve.has(captain),
			"the captain crosses only by trading with his prowman")
	assert_eq(eng.state.momentum, 2, "a refused free move is the income, never a free move")
	assert_false(eng.crossing_candidates().has(captain), "and he is not on the list at all")


func test_naming_a_man_who_is_not_on_the_ship_takes_the_income() -> void:
	var eng := _engine()
	var fielded: Character = eng.state.player_formation.fielded()[0]
	var bot: TestHelpers.OpeningBot = eng.controller
	bot.openings = [{"op": "reinforce", "character": fielded}]
	await eng._player_turn()
	assert_eq(eng.state.momentum, 2, "an illegal man is an illegal answer: the income")
	assert_eq(eng.state.player_formation.size(), 2, "nobody moved")


# --- (b) The free swap --------------------------------------------------------

func test_the_free_swap_trades_two_men_on_deck() -> void:
	var eng := _engine()
	var a: Character = eng.state.player_formation.fielded()[0]
	var b: Character = eng.state.player_formation.fielded()[1]
	TestHelpers.station(eng.state.player_formation, b, B, 2)
	var bot: TestHelpers.OpeningBot = eng.controller
	bot.openings = [{"op": "swap", "character": a, "partner": b}]
	await eng._player_turn()
	assert_eq(eng.state.player_formation.at(B, 2), a, "they trade slots exactly")
	assert_eq(eng.state.player_formation.at(F, 0), b)
	assert_eq(eng.state.momentum, 1, "the snap is free: only the turn's own +1")
	assert_eq(eng.state.hand.size(), 5, "and it draws nothing")


func test_the_free_swap_trades_a_fielded_man_for_one_on_the_ship() -> void:
	var eng := _engine()
	var tired: Character = eng.state.player_formation.fielded()[0]
	var fresh: Character = eng.state.player_reserve[0]
	var line := eng.state.player_formation.line_of(tired)
	var col := eng.state.player_formation.column_of(tired)
	var bot: TestHelpers.OpeningBot = eng.controller
	bot.openings = [{"op": "swap", "character": tired, "partner": fresh}]
	await eng._player_turn()
	assert_eq(eng.state.player_formation.at(line, col), fresh, "the fresh man takes his exact slot")
	assert_true(eng.state.player_reserve.has(tired), "the tired one goes back aboard")
	assert_eq(eng.state.momentum, 1, "still free")


func test_a_pair_member_snaps_only_with_his_counterpart() -> void:
	var eng := _pair_engine()
	var prow := eng.state.player_prowman
	var crew1: Character = eng.state.player_formation.fielded()[1]
	var bot: TestHelpers.OpeningBot = eng.controller
	bot.openings = [{"op": "swap", "character": prow, "partner": crew1}]
	await eng._player_turn()
	assert_true(eng.state.player_formation.has(prow), "the prowman never trades with ordinary crew")
	assert_eq(eng.state.momentum, 2, "the refused snap is the income")


func test_the_free_swap_brings_the_captain_over_the_rail() -> void:
	var eng := _pair_engine()
	var prow := eng.state.player_prowman
	var captain := eng.state.player_captain
	var bot: TestHelpers.OpeningBot = eng.controller
	bot.openings = [{"op": "swap", "character": prow, "partner": captain}]
	await eng._player_turn()
	assert_true(eng.state.player_formation.has(captain), "the pair trades across the rail for free")
	assert_true(eng.state.player_reserve.has(prow), "and the prowman waits his turn")


func test_a_pinned_man_takes_no_snap() -> void:
	var eng := _engine()
	var a: Character = eng.state.player_formation.fielded()[0]
	var b: Character = eng.state.player_formation.fielded()[1]
	a.pinned = 2
	var bot: TestHelpers.OpeningBot = eng.controller
	bot.openings = [{"op": "swap", "character": a, "partner": b}]
	await eng._player_turn()
	assert_eq(eng.state.player_formation.fielded()[0], a, "pinned is pinned: nothing moves him")
	assert_eq(eng.state.momentum, 2, "the refused snap is the income")


func test_a_pinned_partner_takes_no_snap_either() -> void:
	var eng := _engine()
	var a: Character = eng.state.player_formation.fielded()[0]
	var b: Character = eng.state.player_formation.fielded()[1]
	b.pinned = 2
	var bot: TestHelpers.OpeningBot = eng.controller
	bot.openings = [{"op": "swap", "character": a, "partner": b}]
	await eng._player_turn()
	assert_eq(eng.state.player_formation.fielded()[1], b, "he cannot be traded off his slot")
	assert_eq(eng.state.momentum, 2, "the refused snap is the income")


func test_a_swap_with_nobody_named_takes_the_income() -> void:
	var eng := _engine()
	var a: Character = eng.state.player_formation.fielded()[0]
	var bot: TestHelpers.OpeningBot = eng.controller
	bot.openings = [{"op": "swap", "character": a}]
	await eng._player_turn()
	assert_eq(eng.state.momentum, 2, "the opening names both men or it is the income")


# --- The legality queries the table asks --------------------------------------

func test_opening_options_always_offers_the_income() -> void:
	var field: Array[Character] = []
	for i in Formation.SLOT_COUNT:
		field.append(TestHelpers.grunt(P, "p%d" % i))
	for c in field:
		c.pinned = 3
	var eng := TestHelpers.engine_for({"player_field": field})
	assert_eq(eng.opening_options(), ["income"] as Array[String],
			"a board where nothing can move still has an opening")


func test_opening_swappers_lists_the_men_with_somewhere_to_go() -> void:
	var eng := _engine()
	var ids: Array[String] = []
	for c in eng.opening_swappers():
		ids.append(c.id)
	assert_eq(ids, ["crew1", "crew2"] as Array[String], "both, in reading order")
	eng.state.player_formation.fielded()[0].pinned = 1
	ids = []
	for c in eng.opening_swappers():
		ids.append(c.id)
	assert_eq(ids, ["crew2"] as Array[String], "a pinned man is nobody's partner and takes none")


func test_the_momentum_commit_is_gone() -> void:
	var eng := _engine()
	assert_false(eng.has_method("can_commit"), "the momentum commit is replaced by the opening")
	assert_false(eng.has_method("_commit_reserve"))


# --- The paid versions still exist --------------------------------------------

func test_the_reinforce_card_is_still_a_second_crossing() -> void:
	var eng := _engine()
	var first: Character = eng.state.player_reserve[0]
	var second := TestHelpers.grunt(P, "crew4")
	eng._register(second)
	eng.state.player_reserve.append(second)
	var card := CardLibrary.reinforce()
	var bot: TestHelpers.OpeningBot = eng.controller
	bot.openings = [{"op": "reinforce", "character": first}]
	bot.actions = [{"op": "play", "card": card, "target": second}]
	eng.state.hand.append(card)
	eng.state.momentum = 5
	await eng._player_turn()
	assert_true(eng.state.player_formation.has(first), "the free crossing")
	assert_true(eng.state.player_formation.has(second), "and the card's paid one, same turn")


func test_trade_places_is_still_a_second_snap() -> void:
	var eng := _engine()
	var a: Character = eng.state.player_formation.fielded()[0]
	var b: Character = eng.state.player_formation.fielded()[1]
	var fresh: Character = eng.state.player_reserve[0]
	var card := CardLibrary.swap()
	var bot: TestHelpers.OpeningBot = eng.controller
	bot.openings = [{"op": "swap", "character": a, "partner": b}]
	bot.actions = [{"op": "play", "card": card, "target": b, "second_target": fresh}]
	eng.state.hand.append(card)
	eng.state.momentum = 5
	await eng._player_turn()
	assert_true(eng.state.player_formation.has(fresh), "the paid trade still brings a man across")
	assert_true(eng.state.player_reserve.has(b))


# --- Determinism --------------------------------------------------------------

func test_same_seed_same_battle_through_the_opening() -> void:
	var logs: Array = []
	var summaries: Array[Dictionary] = []
	for i in 2:
		var bot_rng := RandomNumberGenerator.new()
		bot_rng.seed = 11
		var bot := Bots.RandomBot.new(bot_rng)
		var eng := CombatEngine.new()
		bot.engine = eng
		eng.setup(Scenarios.default_skirmish(), bot, 123)
		summaries.append(await eng.run())
		logs.append(eng.state.battle_log)
	assert_eq(summaries[0], summaries[1], "identical summary with the opening in the loop")
	assert_eq(logs[0], logs[1], "identical turn-by-turn log")
