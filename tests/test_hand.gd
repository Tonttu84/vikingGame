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


## The turn refill deals to HAND_SIZE, but a card that draws (Feint) pushes
## past it mid-turn. A hand has to stop somewhere: MAX_HAND_SIZE is that
## somewhere, and a draw that would overflow simply does not happen — the
## card stays in the deck rather than being drawn and binned.
func test_draw_stops_at_the_hand_limit() -> void:
	var eng := TestHelpers.engine_for({"player_field": [TestHelpers.grunt(P, "crew")]})
	eng.state.hand.clear()
	for i in BattleState.MAX_HAND_SIZE:
		eng.state.hand.append(CardLibrary.loot("l%d" % i, "Silver"))
	for i in 4:
		eng.state.deck.append(CardLibrary.loot("d%d" % i, "Deck silver"))
	var deck_before := eng.state.deck.size()
	assert_false(eng._draw(1), "a full hand draws nothing")
	assert_eq(eng.state.hand.size(), BattleState.MAX_HAND_SIZE, "and stays at the limit")
	assert_eq(eng.state.deck.size(), deck_before, "the card is left in the deck, not binned")


func test_draw_fills_only_up_to_the_limit() -> void:
	var eng := TestHelpers.engine_for({"player_field": [TestHelpers.grunt(P, "crew")]})
	eng.state.hand.clear()
	for i in BattleState.MAX_HAND_SIZE - 1:
		eng.state.hand.append(CardLibrary.loot("l%d" % i, "Silver"))
	for i in 4:
		eng.state.deck.append(CardLibrary.loot("d%d" % i, "Deck silver"))
	assert_true(eng._draw(3), "there is room for one")
	assert_eq(eng.state.hand.size(), BattleState.MAX_HAND_SIZE,
			"and the rest of the draw is refused")


func test_the_limit_leaves_room_for_the_turn_refill_plus_a_feint() -> void:
	assert_true(BattleState.MAX_HAND_SIZE >= BattleState.HAND_SIZE + 2,
			"Feint draws 2 from a full refill; the limit must not swallow it")


func test_feint_can_push_the_hand_past_the_refill_size() -> void:
	var eng := TestHelpers.engine_for({"player_field": [TestHelpers.grunt(P, "crew")]})
	eng.state.hand.clear()
	for i in BattleState.HAND_SIZE:
		eng.state.hand.append(CardLibrary.loot("l%d" % i, "Silver"))
	for i in 4:
		eng.state.deck.append(CardLibrary.loot("d%d" % i, "Deck silver"))
	var feint := CardLibrary.feint()
	eng.state.hand.append(feint)
	eng.state.momentum = 5
	await eng._play_card(feint, null)
	assert_eq(eng.state.hand.size(), BattleState.HAND_SIZE + 2,
			"five held, the Feint leaves, two arrive")
