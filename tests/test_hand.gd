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


## Remembers what the hand looked like each time the engine asked for a play.
class HandWatcher extends TestHelpers.ScriptedBot:
	var hands_seen: Array[int] = []

	func choose_action(state: BattleState) -> Dictionary:
		hands_seen.append(state.hand.size())
		return super.choose_action(state)


## A deck with nothing Retained in it, so a hand's size is the deal alone.
func _cycling_deck(n := 16) -> Array:
	var deck := []
	for i in n:
		deck.append(CardLibrary.loot("silver%d" % i, "Silver"))
	return deck


func test_fresh_hand_every_turn() -> void:
	var eng := TestHelpers.engine_for({
		"player_field": [TestHelpers.grunt(P, "crew")],
		"deck": _cycling_deck(),
	})
	# The hand cycles at the END of the turn: what a turn leaves behind is the
	# fresh five you hold through the enemy's turn. (With a lone man and no
	# ship the income is the only opening, so its card is drawn and, unplayed,
	# discarded again within the same turn.)
	await eng._player_turn()
	assert_eq(eng.state.hand.size(), 5, "turn 1 ends on a fresh hand of 5")
	var first_hand := eng.state.hand.duplicate()
	await eng._player_turn()
	assert_eq(eng.state.hand.size(), 5, "turn 2: a fresh hand, same size")
	for card: CardData in first_hand:
		if not card.retained:
			assert_false(eng.state.hand.has(card),
					"non-retained card from last turn was discarded: " + card.id)


## Owner's ruling 2026-09-06: the refill is "draw 5 at the end of the turn",
## and the draw itself stops at a full hand. It is NOT a top-up to 5, so a
## Retained card waiting in hand costs no draw — that was the bug he felt.
func test_the_refill_is_a_fixed_draw_not_a_top_up() -> void:
	var eng := TestHelpers.engine_for({
		"player_field": [TestHelpers.grunt(P, "crew")],
		"deck": CardLibrary.starter_deck(),
	})
	var keepers := [CardLibrary.reinforce(), CardLibrary.swap()]
	for k in keepers:
		eng.state.hand.append(k)
	await eng._player_turn()
	assert_eq(eng.state.hand.size(), 7, "2 retained + 5 drawn: retaining costs no draw")
	for k in keepers:
		assert_true(eng.state.hand.has(k), "the retained card is still there: " + k.id)


func test_the_refill_stops_at_the_hand_ceiling() -> void:
	var eng := TestHelpers.engine_for({
		"player_field": [TestHelpers.grunt(P, "crew")],
		"deck": CardLibrary.starter_deck(),
	})
	var keepers := [CardLibrary.reinforce(), CardLibrary.swap(), CardLibrary.drag_him_back()]
	for k in keepers:
		eng.state.hand.append(k)
	await eng._player_turn()
	assert_eq(eng.state.hand.size(), BattleState.MAX_HAND_SIZE,
			"3 retained + 4 of the 5: the ceiling stops the draw, nothing is binned")
	for k in keepers:
		assert_true(eng.state.hand.has(k), "the retained card is still there: " + k.id)


func test_the_hand_cycles_at_the_end_of_the_turn_not_the_start() -> void:
	var bot := HandWatcher.new()
	var eng := TestHelpers.engine_for({
		"player_field": [TestHelpers.grunt(P, "crew")],
		"deck": CardLibrary.starter_deck(),
	}, bot)
	# An empty hand going in: the start of the turn deals nothing of its own
	# (only the opening's income adds a card), and the turn ENDS on the fresh
	# five, with the unplayed income card in the discard.
	await eng._player_turn()
	assert_eq(bot.hands_seen, [1] as Array[int],
			"during the turn: only the income's card — no start-of-turn refill")
	assert_eq(eng.state.hand.size(), 5, "the turn ends on the fresh five")
	assert_eq(eng.state.discard.size(), 1, "and the unplayed income card was discarded")


func test_the_first_hand_is_dealt_with_the_boarding() -> void:
	# The whole battle through run(): the first hand comes with the boarding,
	# and every later turn opens on the five the previous turn drew — plus
	# the income's card, the only opening a lone man without a ship has.
	var bot := HandWatcher.new()
	var eng := TestHelpers.engine_for({
		"player_field": [TestHelpers.grunt(P, "crew")],
		"enemy_field": [TestHelpers.grunt(E, "e1")],
		"deck": _cycling_deck(),
	}, bot)
	await eng.run()
	assert_true(bot.hands_seen.size() >= 2, "the battle ran at least two turns")
	assert_eq(bot.hands_seen[0], 6, "turn 1: the boarding's five plus the income's card")
	assert_eq(bot.hands_seen[1], 6, "turn 2: last turn's five plus the income's card")


func test_a_retained_card_held_over_rides_on_top_of_the_deal() -> void:
	# The starter deck carries Retained cards; one drawn at a turn's end is
	# still there after the next turn's cycle, and it costs that cycle nothing.
	var eng := TestHelpers.engine_for({
		"player_field": [TestHelpers.grunt(P, "crew")],
		"deck": _cycling_deck(),
	})
	var keeper := CardLibrary.reinforce()
	# Second from the top: the opening's income takes the top card, so the
	# turn's end-cycle is what draws the keeper.
	eng.state.deck.insert(eng.state.deck.size() - 1, keeper)
	await eng._player_turn()
	assert_true(eng.state.hand.has(keeper), "drawn at the turn's end")
	await eng._player_turn()
	assert_true(eng.state.hand.has(keeper), "held over: still in hand after the next cycle")
	assert_eq(eng.state.hand.size(), 6, "and the next deal is a full five beside it")


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


## The turn's end draws HAND_SIZE, but a card that draws (Feint) pushes
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
	var crew := TestHelpers.grunt(P, "crew")
	var eng := TestHelpers.engine_for({"player_field": [crew],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	# The Feint's Close rider must have a step to take, or the card is refused.
	TestHelpers.station(eng.state.enemy_formation, eng.state.fielded(E)[0], Formation.FRONT, 2)
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
