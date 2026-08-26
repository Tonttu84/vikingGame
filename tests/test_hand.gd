extends TestCase
## The hand model: a fresh hand every turn, Retained cards that wait in hand,
## the automatic Drag Him Back! save, and the removal of scrapping.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY


func test_retain_keyword_on_the_right_cards() -> void:
	assert_true(CardLibrary.reinforce().retained, "reinforce waits for the right moment")
	assert_true(CardLibrary.swap().retained, "swap waits for the right moment")
	assert_true(CardLibrary.drag_him_back().retained, "the save waits in hand")
	assert_false(CardLibrary.spear_volley().retained, "ordinary tactics cycle")
	assert_false(CardLibrary.loot("l1", "Silver").retained, "loot cycles too")


func test_fresh_hand_every_turn() -> void:
	var eng := TestHelpers.engine_for({
		"player_field": [TestHelpers.grunt(P, "crew")],
		"deck": CardLibrary.starter_deck(),
	})
	await eng._player_turn()
	assert_eq(eng.state.hand.size(), 5, "turn 1: a hand of 5")
	var first_hand := eng.state.hand.duplicate()
	await eng._player_turn()
	assert_eq(eng.state.hand.size(), 5, "turn 2: a fresh hand of 5")
	for card: CardData in first_hand:
		if not card.retained:
			assert_false(eng.state.hand.has(card),
					"non-retained card from last turn was discarded: " + card.id)


func test_retained_cards_survive_the_discard() -> void:
	# A real deck, so the discarded card is not immediately reshuffled back in.
	var eng := TestHelpers.engine_for({
		"player_field": [TestHelpers.grunt(P, "crew")],
		"deck": CardLibrary.starter_deck(),
	})
	var keeper := CardLibrary.reinforce()
	var cycler := CardLibrary.spear_volley()
	eng.state.hand.append(keeper)
	eng.state.hand.append(cycler)
	await eng._player_turn()
	assert_true(eng.state.hand.has(keeper), "retained: still in hand")
	assert_false(eng.state.hand.has(cycler), "not retained: discarded")
	assert_true(eng.state.discard.has(cycler))


func test_retained_cards_count_toward_hand_size() -> void:
	var eng := TestHelpers.engine_for({
		"player_field": [TestHelpers.grunt(P, "crew")],
		"deck": CardLibrary.starter_deck(),
	})
	eng.state.hand.append(CardLibrary.reinforce())
	eng.state.hand.append(CardLibrary.swap())
	await eng._player_turn()
	assert_eq(eng.state.hand.size(), 5, "2 retained + 3 drawn: retaining costs draw room")


func test_drag_him_back_fires_automatically() -> void:
	var crew := TestHelpers.grunt(P, "crew", 2)
	var e1 := TestHelpers.grunt(E, "e1", 12, 6, 5, 3)
	# NoCardBot makes no decisions at all: the save must need nobody's consent.
	var eng := TestHelpers.engine_for({"player_field": [crew], "enemy_field": [e1]}, Bots.NoCardBot.new())
	eng.state.hand.append(CardLibrary.drag_him_back())
	eng.state.momentum = 1
	await eng._attack(e1, crew)
	assert_true(eng.state.player_dead.is_empty(), "the killing blow is cancelled, no prompt needed")
	assert_true(eng.state.player_reserve.has(crew), "dragged back to the ship")
	assert_eq(eng.state.momentum, 0, "the save still costs its momentum")


func test_auto_save_needs_momentum() -> void:
	var crew := TestHelpers.grunt(P, "crew", 2)
	var e1 := TestHelpers.grunt(E, "e1", 12, 6, 5, 3)
	var eng := TestHelpers.engine_for({"player_field": [crew], "enemy_field": [e1]}, Bots.NoCardBot.new())
	eng.state.hand.append(CardLibrary.drag_him_back())
	eng.state.momentum = 0
	await eng._attack(e1, crew)
	assert_true(eng.state.player_dead.has(crew), "no momentum, no miracle")


func test_scrap_action_is_gone() -> void:
	var eng := TestHelpers.engine_for({"player_field": [TestHelpers.grunt(P, "crew")]})
	var card := CardLibrary.loot("l1", "Silver")
	eng.state.hand.append(card)
	await eng._apply_action({"op": "scrap", "card": card})
	assert_true(eng.state.hand.has(card), "scrap is no longer an action")
	assert_eq(eng.state.momentum, 0, "and pays nothing")
	assert_false(eng.has_method("_scrap_card"), "the mechanic is removed, not disabled")
