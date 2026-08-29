extends TestCase
## The legality queries the table asks before it offers a play. The UI must
## never work out for itself what is legal — it highlights what the engine
## says is available (a card's drop targets, who may cross, who may trade
## places, which way a man can be shoved) and submits nothing else.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY


func _engine(momentum := 5) -> CombatEngine:
	var eng := TestHelpers.engine_for({
		"player_field": [TestHelpers.grunt(P, "crew1"), TestHelpers.grunt(P, "crew2")],
		"player_reserve": [TestHelpers.grunt(P, "crew3")],
		"enemy_field": [TestHelpers.grunt(E, "foe1"), TestHelpers.grunt(E, "foe2")],
	})
	eng.state.momentum = momentum
	return eng


func _prowman(id := "prow") -> Character:
	var c := TestHelpers.grunt(P, id, 14, 8, 4, 3, Weapon.axe(), 1)
	c.is_prowman = true
	return c


## Prowman + one grunt on the field; captain + one grunt in reserve.
func _pair_engine(momentum := 5) -> CombatEngine:
	var eng := TestHelpers.engine_for({
		"player_field": [_prowman(), TestHelpers.grunt(P, "crew1")],
		"player_reserve": [TestHelpers.captain_of(P, "aslak"), TestHelpers.grunt(P, "crew2")],
		"enemy_field": [TestHelpers.grunt(E, "foe1")],
	})
	eng.state.momentum = momentum
	return eng


func _in_hand(eng: CombatEngine, card: CardData) -> CardData:
	eng.state.hand.append(card)
	return card


# --- can_play ----------------------------------------------------------------

func test_can_play_rejects_a_card_that_is_not_in_hand() -> void:
	var eng := _engine()
	assert_false(eng.can_play(CardLibrary.war_cry()), "a card off the table is not playable")


func test_can_play_rejects_an_unaffordable_card() -> void:
	var eng := _engine(0)
	var card := _in_hand(eng, CardLibrary.war_cry())
	assert_false(eng.can_play(card), "no momentum, no play")


func test_can_play_accepts_an_affordable_untargeted_card() -> void:
	var eng := _engine()
	var card := _in_hand(eng, CardLibrary.war_cry())
	assert_true(eng.can_play(card))


func test_can_play_rejects_a_target_for_an_untargeted_card() -> void:
	var eng := _engine()
	var card := _in_hand(eng, CardLibrary.war_cry())
	assert_false(eng.can_play(card, eng.state.player_formation.fielded()[0]),
			"War Cry takes nobody as its target")


func test_can_play_requires_a_target_for_a_targeted_card() -> void:
	var eng := _engine()
	var card := _in_hand(eng, CardLibrary.rally())
	assert_false(eng.can_play(card), "Rally needs a man to rally")


func test_can_play_refuses_an_ally_card_on_an_enemy() -> void:
	var eng := _engine()
	var card := _in_hand(eng, CardLibrary.rally())
	assert_false(eng.can_play(card, eng.state.enemy_formation.fielded()[0]))
	assert_true(eng.can_play(card, eng.state.player_formation.fielded()[0]))


func test_can_play_refuses_an_enemy_card_on_an_ally() -> void:
	var eng := _engine()
	var card := _in_hand(eng, CardLibrary.concentrated_attack())
	assert_false(eng.can_play(card, eng.state.player_formation.fielded()[0]))
	assert_true(eng.can_play(card, eng.state.enemy_formation.fielded()[0]))


func test_can_play_refuses_a_dead_target() -> void:
	var eng := _engine()
	var card := _in_hand(eng, CardLibrary.concentrated_attack())
	var foe := eng.state.enemy_formation.fielded()[0]
	foe.hp = 0
	assert_false(eng.can_play(card, foe))


func test_can_play_wants_battle_fury_on_a_man_who_is_actually_fighting() -> void:
	var eng := _engine()
	var card := _in_hand(eng, CardLibrary.battle_fury())
	assert_false(eng.can_play(card, eng.state.player_reserve[0]),
			"the reserve never fights; furying a man on your own ship does nothing")
	assert_true(eng.can_play(card, eng.state.player_formation.fielded()[0]))


func test_can_play_reads_the_shove_precondition() -> void:
	var eng := _engine()
	var card := _in_hand(eng, CardLibrary.break_the_line())
	var f := eng.state.enemy_formation
	var foe := f.fielded()[0]
	var other := f.fielded()[1]
	TestHelpers.station(f, other, Formation.BACK, 3)
	TestHelpers.station(f, foe, Formation.FRONT, 1)
	assert_true(eng.can_play(card, foe), "room to either side")
	TestHelpers.station(f, foe, Formation.FRONT, 0)
	TestHelpers.station(f, other, Formation.FRONT, 1)
	assert_false(eng.can_play(card, foe), "edge on one side, a man on the other")


func test_can_play_reads_the_prow_pair_law() -> void:
	var eng := _pair_engine()
	var card := _in_hand(eng, CardLibrary.swap())
	var prowman := eng.state.player_prowman
	var crew1 := eng.state.player_formation.fielded()[1]
	assert_true(eng.can_play(card, prowman), "the fielded prowman trades with his captain")
	assert_false(eng.can_play(card, prowman, crew1),
			"never with ordinary crew")


# --- Who may cross, who may be committed --------------------------------------

func test_crossing_candidates_skips_the_pair() -> void:
	var eng := _pair_engine()
	var names: Array[String] = []
	for c in eng.crossing_candidates():
		names.append(c.id)
	assert_eq(names, ["crew2"] as Array[String], "the captain never crosses by Reinforce")


func test_crossing_candidates_lists_the_reserve_in_order() -> void:
	var eng := _engine()
	assert_eq(eng.crossing_candidates().size(), 1)
	assert_eq(eng.crossing_candidates()[0], eng.state.player_reserve[0])


func test_can_commit_needs_the_momentum() -> void:
	var eng := _engine(0)
	assert_false(eng.can_commit(eng.state.player_reserve[0]), "unaffordable")
	eng.state.momentum = BattleState.RESERVE_COMMIT_COST
	assert_true(eng.can_commit(eng.state.player_reserve[0]))


func test_can_commit_refuses_a_pair_member() -> void:
	var eng := _pair_engine()
	assert_false(eng.can_commit(eng.state.player_captain),
			"the captain crosses only by trading with his prowman")
	assert_true(eng.can_commit(eng.state.player_reserve[1]), "ordinary crew still cross")


func test_can_commit_refuses_a_man_already_on_the_field() -> void:
	var eng := _engine()
	assert_false(eng.can_commit(eng.state.player_formation.fielded()[0]))
	assert_false(eng.can_commit(null))


func test_can_commit_refuses_when_the_grid_is_full() -> void:
	var eng := _engine()
	var f := eng.state.player_formation
	for i in Formation.SLOT_COUNT:
		if f.slots[i] == null:
			f.slots[i] = TestHelpers.grunt(P, "filler%d" % i)
	assert_false(eng.can_commit(eng.state.player_reserve[0]), "no room at the rail")


# --- Swap partners and shove directions ---------------------------------------

func test_swap_partners_lists_the_field_then_the_reserve() -> void:
	var eng := _engine()
	var target := eng.state.player_formation.fielded()[0]
	var partners: Array[Character] = eng.swap_partners(target)
	var ids: Array[String] = []
	for c in partners:
		ids.append(c.id)
	assert_eq(ids, ["crew2", "crew3"] as Array[String],
			"his fellow on deck first, then the man on the ship")


func test_swap_partners_of_a_man_not_on_the_field_is_empty() -> void:
	var eng := _engine()
	assert_eq(eng.swap_partners(eng.state.player_reserve[0]).size(), 0)
	assert_eq(eng.swap_partners(null).size(), 0)


func test_swap_partners_of_a_pair_member_is_his_counterpart_alone() -> void:
	var eng := _pair_engine()
	var partners: Array[Character] = eng.swap_partners(eng.state.player_prowman)
	assert_eq(partners.size(), 1)
	assert_eq(partners[0], eng.state.player_captain)


func test_swap_partners_of_ordinary_crew_excludes_the_pair() -> void:
	var eng := _pair_engine()
	var crew1 := eng.state.player_formation.fielded()[1]
	for c in eng.swap_partners(crew1):
		assert_false(c == eng.state.player_captain or c == eng.state.player_prowman,
				"ordinary crew never trade with the pair")


func test_pair_swap_counterpart_names_the_man_on_the_field() -> void:
	var eng := _pair_engine()
	assert_eq(eng.pair_swap_counterpart(eng.state.player_captain), eng.state.player_prowman,
			"the waiting captain's Swap goes on the prowman")
	assert_eq(eng.pair_swap_counterpart(eng.state.player_reserve[1]), null,
			"ordinary crew have no counterpart")
	assert_eq(eng.pair_swap_counterpart(eng.state.player_prowman), null,
			"the fielded half is not the one asking")


func test_pair_swap_counterpart_is_null_without_a_prowman() -> void:
	var eng := _engine()
	assert_eq(eng.pair_swap_counterpart(eng.state.player_reserve[0]), null)


func test_shove_directions_lists_larboard_before_starboard() -> void:
	var eng := _engine()
	var f := eng.state.enemy_formation
	var foe := f.fielded()[0]
	var other := f.fielded()[1]
	TestHelpers.station(f, other, Formation.BACK, 3)
	TestHelpers.station(f, foe, Formation.FRONT, 1)
	assert_eq(eng.shove_directions(foe), [-1, 1] as Array[int])


func test_shove_directions_drops_a_blocked_side() -> void:
	var eng := _engine()
	var f := eng.state.enemy_formation
	var foe := f.fielded()[0]
	var other := f.fielded()[1]
	TestHelpers.station(f, other, Formation.BACK, 0)
	TestHelpers.station(f, foe, Formation.FRONT, 1)
	TestHelpers.station(f, other, Formation.FRONT, 0)
	assert_eq(eng.shove_directions(foe), [1] as Array[int], "larboard is taken")


func test_shove_directions_of_a_second_liner_is_empty() -> void:
	var eng := _engine()
	var f := eng.state.enemy_formation
	var foe := f.fielded()[0]
	TestHelpers.station(f, foe, Formation.BACK, 1)
	assert_eq(eng.shove_directions(foe).size(), 0, "the shove only reaches the rank at the rail")
	assert_eq(eng.shove_directions(null).size(), 0)


# --- Free slots ---------------------------------------------------------------

func test_free_indices_reads_front_line_first() -> void:
	var f := Formation.new()
	f.place(TestHelpers.grunt(P, "a"), Formation.FRONT, 0)
	f.place(TestHelpers.grunt(P, "b"), Formation.BACK, 2)
	assert_eq(f.free_indices(), [1, 2, 3, 4, 5, 7] as Array[int])


func test_free_indices_of_a_full_grid_is_empty() -> void:
	var f := Formation.new()
	for i in Formation.SLOT_COUNT:
		f.slots[i] = TestHelpers.grunt(P, "x%d" % i)
	assert_eq(f.free_indices().size(), 0)
	assert_eq(Formation.new().free_indices().size(), Formation.SLOT_COUNT)
