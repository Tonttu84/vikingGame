extends TestCase
## The prow pair (officer system, first slice): the captain and the prowman
## are alternates. One of the pair must stand on the field; they trade
## places only with each other (the Swap card), never with ordinary crew,
## and neither crosses by Reinforce or the turn's free opening. When the
## prowman leaves the field for good — slain or broken — the captain leaps
## the rail himself for 1 momentum; if the crew cannot pay, panic takes
## them and the battle is lost. Rulings from playtest discussion 2026-08-28.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY


func _prowman(id := "prow") -> Character:
	var c := TestHelpers.grunt(P, id, 14, 8, 4, 3, Weapon.axe(), 1)
	c.is_prowman = true
	return c


## Prowman + one grunt on the field; captain + one grunt in reserve.
func _pair_engine(momentum := 0) -> CombatEngine:
	var eng := TestHelpers.engine_for({
		"player_field": [_prowman(), TestHelpers.grunt(P, "crew1")],
		"player_reserve": [TestHelpers.captain_of(P, "aslak"), TestHelpers.grunt(P, "crew2")],
		"enemy_field": [TestHelpers.grunt(E, "foe1")],
	})
	eng.state.momentum = momentum
	return eng


func _swap_in_hand(eng: CombatEngine) -> CardData:
	var card := CardLibrary.swap()
	eng.state.hand.append(card)
	return card


func test_setup_finds_the_prowman() -> void:
	var eng := _pair_engine()
	assert_true(eng.state.player_prowman != null and eng.state.player_prowman.is_prowman)


func test_captain_cannot_take_the_free_crossing_while_the_pair_stands() -> void:
	var eng := _pair_engine(5)
	var captain := eng.state.player_captain
	eng._apply_opening({"op": "reinforce", "character": captain}, eng.opening_options())
	assert_true(eng.state.player_reserve.has(captain),
			"the captain never crosses by the opening's free reinforcement")
	assert_eq(eng.state.momentum, 6, "the refused free move fell back to the income")


func test_reinforce_default_crosser_skips_the_captain() -> void:
	var eng := _pair_engine(5)
	var card := CardData.new("reinforce", "Reinforce", 1, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.REINFORCE, "amount": 1}])
	eng.state.hand.append(card)
	await eng._play_card(card, null)
	assert_false(eng.state.player_formation.has(eng.state.player_captain),
			"the captain is skipped even at the head of the reserve queue")
	var crew2: Character = eng.state.player_reserve[0] if not eng.state.player_reserve.is_empty() else null
	assert_true(crew2 == eng.state.player_captain, "only the captain is left ashore")


func test_reinforce_refuses_the_captain_as_explicit_target() -> void:
	var eng := _pair_engine(5)
	var card := CardData.new("reinforce", "Reinforce", 1, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.REINFORCE, "amount": 1}])
	eng.state.hand.append(card)
	await eng._play_card(card, eng.state.player_captain)
	assert_true(eng.state.hand.has(card), "refused outright — card kept")
	assert_eq(eng.state.momentum, 5, "nothing paid")
	assert_true(eng.state.player_reserve.has(eng.state.player_captain))


func test_swap_trades_prowman_for_captain() -> void:
	var eng := _pair_engine(3)
	var prow := eng.state.player_prowman
	var captain := eng.state.player_captain
	var line := eng.state.player_formation.line_of(prow)
	var col := eng.state.player_formation.column_of(prow)
	var card := _swap_in_hand(eng)
	await eng._play_card(card, prow)
	assert_true(eng.state.player_formation.has(captain), "the captain takes the prow")
	assert_eq(eng.state.player_formation.line_of(captain), line)
	assert_eq(eng.state.player_formation.column_of(captain), col)
	assert_true(eng.state.player_reserve.has(prow), "the prowman falls back to the ship")
	assert_eq(eng.state.momentum, 1, "Trade Places is paid as usual")


func test_swap_back_brings_the_prowman_again() -> void:
	var eng := _pair_engine(4)
	await eng._play_card(_swap_in_hand(eng), eng.state.player_prowman)
	await eng._play_card(_swap_in_hand(eng), eng.state.player_captain)
	assert_true(eng.state.player_formation.has(eng.state.player_prowman))
	assert_true(eng.state.player_reserve.has(eng.state.player_captain))


func test_pair_never_swaps_with_ordinary_crew() -> void:
	var eng := _pair_engine(5)
	var prow := eng.state.player_prowman
	var crew2: Character = null
	for c: Character in eng.state.player_reserve:
		if not c.is_captain:
			crew2 = c
	var card := _swap_in_hand(eng)
	await eng._play_card(card, prow, crew2)
	assert_true(eng.state.hand.has(card), "prowman for a karl — refused, card kept")
	assert_true(eng.state.player_formation.has(prow))
	var card2 := _swap_in_hand(eng)
	var crew1: Character = null
	for c: Character in eng.state.fielded(P):
		if not c.is_prowman:
			crew1 = c
	await eng._play_card(card2, crew1, eng.state.player_captain)
	assert_true(eng.state.hand.has(card2), "a karl for the captain — refused too")
	assert_true(eng.state.player_reserve.has(eng.state.player_captain))


func test_ordinary_swap_still_works_and_skips_the_pair_by_default() -> void:
	var eng := _pair_engine(5)
	var crew1: Character = null
	for c: Character in eng.state.fielded(P):
		if not c.is_prowman:
			crew1 = c
	# Reserve queue is [captain, crew2]: the default partner must skip him.
	await eng._play_card(_swap_in_hand(eng), crew1)
	assert_true(eng.state.player_reserve.has(eng.state.player_captain),
			"the captain is never the default swap partner")
	assert_true(eng.state.player_reserve.has(crew1), "crew1 fell back")
	assert_false(eng.state.player_formation.has(eng.state.player_captain))


func test_prowman_slain_forces_the_captain_in_for_one_momentum() -> void:
	var eng := _pair_engine(2)
	var prow := eng.state.player_prowman
	var captain := eng.state.player_captain
	var line := eng.state.player_formation.line_of(prow)
	var col := eng.state.player_formation.column_of(prow)
	prow.hp = 0
	await eng._handle_death(prow)
	assert_true(eng.state.player_dead.has(prow))
	assert_true(eng.state.player_formation.has(captain), "the captain leaps the rail at once")
	assert_eq(eng.state.player_formation.line_of(captain), line, "into the prowman's own slot")
	assert_eq(eng.state.player_formation.column_of(captain), col)
	assert_eq(eng.state.momentum, 1, "the crossing costs 1 momentum")
	assert_eq(eng.outcome, CombatEngine.Outcome.NONE, "the fight goes on")


func test_prowman_routed_forces_the_captain_in_too() -> void:
	var eng := _pair_engine(1)
	var prow := eng.state.player_prowman
	prow.morale = 0
	eng._check_routs(P)
	assert_true(eng.state.player_fled.has(prow))
	assert_true(eng.state.player_formation.has(eng.state.player_captain))
	assert_eq(eng.state.momentum, 0)


func test_prowman_slain_with_no_momentum_is_panic_and_defeat() -> void:
	var eng := _pair_engine(0)
	var prow := eng.state.player_prowman
	prow.hp = 0
	await eng._handle_death(prow)
	assert_eq(eng.outcome, CombatEngine.Outcome.DEFEAT,
			"no one at the prow and nothing left to answer — panic takes the crew")
	assert_true(eng.state.player_reserve.has(eng.state.player_captain),
			"the captain never made it across")


func test_no_one_drags_the_prowman_back() -> void:
	var eng := _pair_engine(5)
	var save := CardLibrary.drag_him_back()
	eng.state.hand.append(save)
	var prow := eng.state.player_prowman
	prow.hp = 0
	await eng._handle_death(prow)
	assert_true(eng.state.player_dead.has(prow),
			"the death save never fires for the prowman — his fall changes the battle")
	assert_true(eng.state.hand.has(save), "the save stays in hand")
	assert_true(eng.state.player_formation.has(eng.state.player_captain))


func test_sole_captain_can_never_leave_the_field() -> void:
	var eng := _pair_engine(5)
	var prow := eng.state.player_prowman
	prow.hp = 0
	await eng._handle_death(prow)
	var captain := eng.state.player_captain
	var card := _swap_in_hand(eng)
	await eng._play_card(card, captain)
	assert_true(eng.state.player_formation.has(captain),
			"with the prowman dead there is no counterpart — the captain holds the prow")
	assert_true(eng.state.hand.has(card))


func test_rosters_without_a_prowman_keep_the_old_rules() -> void:
	var eng := TestHelpers.engine_for({
		"player_field": [TestHelpers.grunt(P, "crew1")],
		"player_reserve": [TestHelpers.captain_of(P, "aslak")],
	})
	eng.state.momentum = 2
	eng._apply_opening({"op": "reinforce", "character": eng.state.player_captain},
			eng.opening_options())
	assert_true(eng.state.player_formation.has(eng.state.player_captain),
			"no prowman declared: the captain may still be sent across")


func test_default_scenarios_field_a_prowman() -> void:
	for id in Scenarios.scenario_ids():
		var scenario := Scenarios.by_id(id)
		var prowmen := 0
		for c: Character in scenario["player_field"]:
			if c.is_prowman:
				prowmen += 1
		assert_eq(prowmen, 1, "%s fields exactly one prowman in the first wave" % id)


func test_prowman_round_trips_roster_text() -> void:
	var text := RosterText.serialize(Scenarios.default_skirmish())
	assert_true(text.contains("prowman"), "the role token is written out")
	var result := RosterText.parse(text)
	assert_eq(result["errors"], [] as Array[String])
	var sten: Character = result["scenario"]["player_field"][0]
	assert_true(sten.is_prowman, "and read back in")


func test_pair_battle_still_resolves() -> void:
	var eng := TestHelpers.engine_for(Scenarios.default_skirmish(), Bots.NoCardBot.new(), 23)
	var result: Dictionary = await eng.run()
	assert_true(result["outcome"] != "NONE")
