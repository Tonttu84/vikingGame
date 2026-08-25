extends TestCase
## Card effects, costs, and the death-cancel reaction.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY


func test_spear_volley_hits_every_fielded_enemy() -> void:
	var e1 := TestHelpers.grunt(E, "e1", 12, 6, 3, 3, null, 3)
	var e2 := TestHelpers.grunt(E, "e2")
	var eng := TestHelpers.engine_for({"enemy_field": [e1, e2]})
	var card := CardLibrary.spear_volley()
	eng.state.hand.append(card)
	eng.state.momentum = 2
	await eng._play_card(card, null)
	assert_eq(e1.hp, 10, "card damage ignores armor")
	assert_eq(e2.hp, 10)
	assert_eq(eng.state.momentum, 0, "cost 2 paid")


func test_rally_heals_capped_at_max() -> void:
	var crew := TestHelpers.grunt(P, "crew")
	crew.hp = 10
	var eng := TestHelpers.engine_for({"player_field": [crew]})
	var card := CardLibrary.rally()
	eng.state.hand.append(card)
	eng.state.momentum = 1
	await eng._play_card(card, crew)
	assert_eq(crew.hp, 12, "heal 4 capped at max HP 12")


func test_feint_draws_two() -> void:
	var eng := TestHelpers.engine_for({"deck": CardLibrary.starter_deck()})
	var card := CardLibrary.feint()
	eng.state.hand.append(card)
	var before := eng.state.hand.size()
	await eng._play_card(card, null)
	assert_eq(eng.state.hand.size(), before - 1 + 2, "feint replaces itself and draws one more")


func test_push_them_back_blocks_one_reinforcement() -> void:
	var eng := TestHelpers.engine_for({
		"enemy_reserve": [TestHelpers.grunt(E, "r1"), TestHelpers.grunt(E, "r2")],
	})
	var card := CardLibrary.push_them_back()
	eng.state.hand.append(card)
	eng.state.momentum = 2
	await eng._play_card(card, null)
	eng._reinforce()
	assert_true(eng.state.enemy_field.is_empty(), "the first reinforcement step is denied")
	eng._reinforce()
	assert_eq(eng.state.enemy_field.size(), 2, "the next one goes through")


func test_concentrated_attack_focuses_the_crew() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var p2 := TestHelpers.grunt(P, "p2")
	var e1 := TestHelpers.grunt(E, "e1", 30)
	var e2 := TestHelpers.grunt(E, "e2", 30)
	var eng := TestHelpers.engine_for({"player_field": [p1, p2], "enemy_field": [e1, e2]})
	var card := CardLibrary.concentrated_attack()
	eng.state.hand.append(card)
	eng.state.momentum = 2
	await eng._play_card(card, e2)
	await eng._fight_phase(P)
	assert_eq(e1.hp, 30, "nobody wastes a swing on the off-target")
	assert_eq(e2.hp, 30 - 3 - 3, "both unarmed grunts hit the focus target")


func test_battle_fury_grants_extra_attack() -> void:
	var p1 := TestHelpers.grunt(P, "p1", 12, 6, 3, 3, Weapon.sword(), 0)
	var e1 := TestHelpers.grunt(E, "e1", 30)
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	var card := CardLibrary.battle_fury()
	eng.state.hand.append(card)
	eng.state.momentum = 1
	await eng._play_card(card, p1)
	await eng._fight_phase(P)
	assert_eq(e1.hp, 30 - 5 - 5, "two sword swings")


func test_drag_him_back_cancels_a_killing_blow() -> void:
	var crew := TestHelpers.grunt(P, "crew", 2)
	var e1 := TestHelpers.grunt(E, "e1", 12, 6, 5, 3)
	var bot := TestHelpers.ScriptedBot.new()
	bot.save_reaction = true
	var eng := TestHelpers.engine_for({"player_field": [crew], "enemy_field": [e1]}, bot)
	eng.state.hand.append(CardLibrary.drag_him_back())
	eng.state.momentum = 1
	await eng._attack(e1, crew)
	assert_true(eng.state.player_dead.is_empty(), "the blow is cancelled")
	assert_true(eng.state.player_reserve.has(crew), "dragged back to the ship")
	assert_eq(crew.hp, 1, "at death's door")
	assert_eq(eng.state.momentum, 0, "the reaction still costs its momentum")


func test_terrifying_bellow_breaks_shaky_enemies() -> void:
	var e1 := TestHelpers.grunt(E, "e1", 12, 2)
	var e2 := TestHelpers.grunt(E, "e2", 12, 2)
	var eng := TestHelpers.engine_for({"enemy_field": [e1, e2]})
	var card := CardLibrary.terrifying_bellow()
	eng.state.hand.append(card)
	eng.state.momentum = 1
	await eng._play_card(card, null)
	assert_eq(eng.state.enemy_routed.size(), 2, "both break")
	assert_eq(eng.state.momentum, 0, "routs grant no momentum")


func test_cannot_play_unaffordable_card() -> void:
	var eng := TestHelpers.engine_for({"enemy_field": [TestHelpers.grunt(E, "e1")]})
	var card := CardLibrary.spear_volley()
	eng.state.hand.append(card)
	eng.state.momentum = 1
	await eng._play_card(card, null)
	assert_true(eng.state.hand.has(card), "cost 2 with 1 momentum: refused")
	assert_eq(eng.state.momentum, 1)


func test_loot_is_not_playable() -> void:
	var eng := TestHelpers.engine_for({})
	var card := CardLibrary.loot("l1", "Silver")
	eng.state.hand.append(card)
	eng.state.momentum = 5
	await eng._play_card(card, null)
	assert_true(eng.state.hand.has(card), "dead weight cannot be played, only scrapped")


func test_card_library_builds_cards_by_id() -> void:
	var card := CardLibrary.by_id("spear_volley")
	assert_true(card != null)
	assert_eq(card.id, "spear_volley")
	assert_eq(CardLibrary.by_id("no_such_card"), null)
	for id in CardLibrary.card_ids():
		var built := CardLibrary.by_id(id)
		assert_true(built != null and built.id == id, "every listed id builds: " + id)


func test_starter_deck_ids_all_resolve() -> void:
	for card in CardLibrary.starter_deck():
		assert_true(CardLibrary.by_id(card.id) != null, "starter card resolvable: " + card.id)
