extends TestCase
## Card effects, costs, and the death-cancel reaction.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY


## Narrowed by the movement riders (phase D): the volley falls on the rank at
## the rail only. Its rider lives in tests/test_riders.gd.
func test_spear_volley_hits_the_whole_enemy_front_line() -> void:
	var e1 := TestHelpers.grunt(E, "e1", 12, 6, 3, 3, null, 3)
	var e2 := TestHelpers.grunt(E, "e2")
	var e3 := TestHelpers.grunt(E, "e3")
	var thrower := TestHelpers.grunt(P, "thrower")
	var eng := TestHelpers.engine_for({"player_field": [thrower], "enemy_field": [e1, e2, e3]})
	TestHelpers.station(eng.state.enemy_formation, e3, Formation.BACK, 0)
	# Somebody has to be able to take the card's port step, or it is refused.
	TestHelpers.station(eng.state.player_formation, thrower, Formation.FRONT, 1)
	var card := CardLibrary.spear_volley()
	eng.state.hand.append(card)
	eng.state.momentum = 2
	await eng._play_card(card, null)
	assert_eq(e1.hp, 10, "card damage ignores armor")
	assert_eq(e2.hp, 10, "every front-liner, not just one column")
	assert_eq(e3.hp, 12, "the second line is spared")
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
	var scout := TestHelpers.grunt(P, "scout")
	var eng := TestHelpers.engine_for({"deck": CardLibrary.starter_deck(),
		"player_field": [scout], "enemy_field": [TestHelpers.grunt(E, "e1")]})
	# Feint's Close rider needs somewhere to close: their man is two columns off.
	TestHelpers.station(eng.state.enemy_formation, eng.state.fielded(E)[0], Formation.FRONT, 2)
	var card := CardLibrary.feint()
	eng.state.hand.append(card)
	var before := eng.state.hand.size()
	await eng._play_card(card, null)
	assert_eq(eng.state.hand.size(), before - 1 + 2, "feint replaces itself and draws one more")


func test_push_them_back_blocks_one_reinforcement() -> void:
	var runner := TestHelpers.grunt(P, "runner")
	var eng := TestHelpers.engine_for({
		"player_field": [runner],
		"enemy_reserve": [TestHelpers.grunt(E, "r1"), TestHelpers.grunt(E, "r2")],
	})
	# Its Press rider needs a second-liner with an empty slot in front of him.
	TestHelpers.station(eng.state.player_formation, runner, Formation.BACK, 0)
	var card := CardLibrary.push_them_back()
	eng.state.hand.append(card)
	eng.state.momentum = 2
	await eng._play_card(card, null)
	eng._reinforce()
	assert_true(eng.state.enemy_formation.is_empty(), "the first reinforcement step is denied")
	eng._reinforce()
	assert_eq(eng.state.enemy_formation.size(), 2, "the next one goes through")


## The card's movement rider (phase D) must take the only move on the board:
## p3 sidesteps out of his empty column, and the focused column stands as it
## was — the rider is mandatory, not free.
class PickP3Bot:
	var mover: Character

	func choose_action(_state: BattleState) -> Dictionary:
		return {"op": "end"}

	func choose_rider(_state: BattleState, _card: CardData,
			moves: Array[Dictionary]) -> Dictionary:
		for move in moves:
			if move.get("character") == mover:
				return move
		return {}


func test_concentrated_attack_focuses_everyone_in_reach() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var p2 := TestHelpers.grunt(P, "p2")
	var p3 := TestHelpers.grunt(P, "p3")
	var e1 := TestHelpers.grunt(E, "e1", 30)
	var e2 := TestHelpers.grunt(E, "e2", 30)
	var bot := PickP3Bot.new()
	bot.mover = p3
	var eng := TestHelpers.engine_for({"player_field": [p1, p2, p3], "enemy_field": [e1, e2]},
			bot)
	TestHelpers.station(eng.state.enemy_formation, e2, Formation.BACK, 1)
	TestHelpers.station(eng.state.enemy_formation, e1, Formation.FRONT, 1)
	var card := CardLibrary.concentrated_attack()
	eng.state.hand.append(card)
	eng.state.momentum = 2
	await eng._play_card(card, e2)
	assert_eq(eng.state.player_formation.at(Formation.FRONT, 1), p2,
			"the rider was steered to the idle column: the focusing attacker stands fast")
	await eng._fight_phase(P)
	assert_eq(e2.hp, 30 - 3, "his column's attacker strikes past the front man")
	assert_eq(e1.hp, 30, "the shielding front-liner is bypassed")


## Battle Fury's Press rider is part of its price: it is playable only on a
## second-liner with room in front of him, and the fury arrives with him.
func test_battle_fury_grants_extra_attack() -> void:
	var p1 := TestHelpers.grunt(P, "p1", 12, 6, 3, 3, Weapon.sword(), 0)
	var e1 := TestHelpers.grunt(E, "e1", 30)
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, p1, Formation.BACK, 0)
	var card := CardLibrary.battle_fury()
	eng.state.hand.append(card)
	eng.state.momentum = 1
	await eng._play_card(card, p1)
	assert_eq(eng.state.player_formation.at(Formation.FRONT, 0), p1, "he presses forward with it")
	await eng._fight_phase(P)
	assert_eq(e1.hp, 30 - 5 - 5, "two sword swings")


func test_drag_him_back_cancels_a_killing_blow() -> void:
	var crew := TestHelpers.grunt(P, "crew", 2)
	var e1 := TestHelpers.grunt(E, "e1", 12, 6, 5, 3)
	var eng := TestHelpers.engine_for({"player_field": [crew], "enemy_field": [e1]})
	eng.state.hand.append(CardLibrary.drag_him_back())
	eng.state.momentum = 1
	await eng._attack(e1, crew)
	assert_true(eng.state.player_dead.is_empty(), "the blow is cancelled")
	assert_true(eng.state.player_reserve.has(crew), "dragged back to the ship")
	assert_eq(crew.hp, 1, "at death's door")
	assert_eq(eng.state.momentum, 0, "the automatic save still costs its momentum")


func test_terrifying_bellow_breaks_shaky_enemies() -> void:
	var e1 := TestHelpers.grunt(E, "e1", 12, 2)
	var e2 := TestHelpers.grunt(E, "e2", 12, 2)
	var roarer := TestHelpers.grunt(P, "roarer")
	var eng := TestHelpers.engine_for({"player_field": [roarer], "enemy_field": [e1, e2]})
	var card := CardLibrary.terrifying_bellow()
	eng.state.hand.append(card)
	eng.state.momentum = 1
	await eng._play_card(card, null)
	assert_eq(eng.state.enemy_routed.size(), 2, "both break")
	assert_eq(eng.state.momentum, 0, "routs grant no momentum")


# --- Taunt: you name the duel ------------------------------------------------
# docs/card-design-proposal.md §4. Name an enemy and one of your men: he is
# dragged into the FRONT SLOT OF YOUR MAN'S COLUMN, swapping with whoever
# stood there. The destination is your own column, so it is always in bounds —
# Taunt is the one movement in the set that cannot be edge-blocked.

func _taunt(eng: CombatEngine, target: Character, anchor: Character = null) -> CardData:
	var card := CardLibrary.taunt()
	eng.state.hand.append(card)
	eng.state.momentum = maxi(eng.state.momentum, card.cost)
	await eng._play_card(card, target, anchor)
	return card


func test_taunt_drags_an_enemy_into_an_empty_slot_across_from_your_man() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, p1, Formation.FRONT, 3)
	TestHelpers.station(eng.state.enemy_formation, e1, Formation.FRONT, 0)
	await _taunt(eng, e1, p1)
	assert_eq(eng.state.enemy_formation.at(Formation.FRONT, 3), e1,
			"he answers the shout and comes to the column you chose")
	assert_eq(eng.state.momentum, 0, "cost 2 paid")


func test_taunt_ejects_the_man_who_stood_there() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var wanted := TestHelpers.grunt(E, "wanted")
	var standing := TestHelpers.grunt(E, "standing")
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"enemy_field": [wanted, standing]})
	TestHelpers.station(eng.state.player_formation, p1, Formation.FRONT, 1)
	TestHelpers.station(eng.state.enemy_formation, wanted, Formation.FRONT, 3)
	TestHelpers.station(eng.state.enemy_formation, standing, Formation.FRONT, 1)
	await _taunt(eng, wanted, p1)
	assert_eq(eng.state.enemy_formation.at(Formation.FRONT, 1), wanted, "they trade slots")
	assert_eq(eng.state.enemy_formation.at(Formation.FRONT, 3), standing,
			"the man who was in the way is thrown into the duel the other just left")


func test_taunt_hauls_a_second_liner_forward() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var hiding := TestHelpers.grunt(E, "hiding")
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [hiding]})
	TestHelpers.station(eng.state.player_formation, p1, Formation.FRONT, 2)
	TestHelpers.station(eng.state.enemy_formation, hiding, Formation.BACK, 0)
	await _taunt(eng, hiding, p1)
	assert_eq(eng.state.enemy_formation.at(Formation.FRONT, 2), hiding,
			"the second line is no refuge: he comes forward, not merely across")


## Fact 4 of the design: an archer snipes only from the second line. Dragging
## their bow to the rail is the first counter to the aimed double shot that is
## not "rescue the man he marked".
func test_taunt_takes_a_bowman_out_of_sniping_position() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var bow := TestHelpers.grunt(E, "bow", 12, 6, 3, 3, Weapon.bow())
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [bow]})
	TestHelpers.station(eng.state.player_formation, p1, Formation.FRONT, 2)
	TestHelpers.station(eng.state.enemy_formation, bow, Formation.BACK, 0)
	assert_true(eng._is_sniper(bow), "back line with a bow: he is picking off your weakest")
	await _taunt(eng, bow, p1)
	assert_false(eng._is_sniper(bow), "at the rail he is just a man with the wrong weapon")


func test_taunt_may_be_anchored_on_a_man_in_your_own_second_line() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, p1, Formation.BACK, 1)
	TestHelpers.station(eng.state.enemy_formation, e1, Formation.FRONT, 3)
	await _taunt(eng, e1, p1)
	assert_eq(eng.state.enemy_formation.at(Formation.FRONT, 1), e1,
			"'his column' is a column, not a slot — a bad play, not an illegal one")


func test_taunt_is_refused_when_the_man_already_stands_there() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, p1, Formation.FRONT, 2)
	TestHelpers.station(eng.state.enemy_formation, e1, Formation.FRONT, 2)
	eng.state.momentum = 5
	var card := await _taunt(eng, e1, p1)
	assert_true(eng.state.hand.has(card), "no movement is possible: refused, card kept")
	assert_eq(eng.state.momentum, 5, "nothing paid")


func test_taunt_leaves_the_reserve_alone() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1")
	var waiting := TestHelpers.grunt(P, "waiting")
	var eng := TestHelpers.engine_for({"player_field": [p1], "player_reserve": [waiting],
			"enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, p1, Formation.FRONT, 3)
	eng.state.momentum = 5
	var card := await _taunt(eng, e1, waiting)
	assert_true(eng.state.hand.has(card), "a man on your own ship anchors nothing")
	assert_eq(eng.state.momentum, 5)


# --- Drive Him Back: a disarm, and a trade you do not always like -----------
# docs/card-design-proposal.md §4. An enemy front-liner is driven into the
# second line of his own column, swapping with the man behind him.

func _drive(eng: CombatEngine, target: Character) -> CardData:
	var card := CardLibrary.drive_him_back()
	eng.state.hand.append(card)
	eng.state.momentum = maxi(eng.state.momentum, card.cost)
	await eng._play_card(card, target)
	return card


func test_drive_him_back_swaps_with_the_man_behind_him() -> void:
	var driven := TestHelpers.grunt(E, "driven")
	var behind := TestHelpers.grunt(E, "behind")
	var eng := TestHelpers.engine_for({"player_field": [TestHelpers.grunt(P, "p1")],
			"enemy_field": [driven, behind]})
	TestHelpers.station(eng.state.enemy_formation, behind, Formation.BACK, 1)
	TestHelpers.station(eng.state.enemy_formation, driven, Formation.FRONT, 1)
	await _drive(eng, driven)
	assert_eq(eng.state.enemy_formation.at(Formation.BACK, 1), driven)
	assert_eq(eng.state.enemy_formation.at(Formation.FRONT, 1), behind,
			"you promoted whoever was standing behind him — your choice, not always your friend")


func test_drive_him_back_retires_him_into_an_empty_slot() -> void:
	var driven := TestHelpers.grunt(E, "driven")
	var eng := TestHelpers.engine_for({"player_field": [TestHelpers.grunt(P, "p1")],
			"enemy_field": [driven]})
	TestHelpers.station(eng.state.enemy_formation, driven, Formation.FRONT, 2)
	await _drive(eng, driven)
	assert_eq(eng.state.enemy_formation.at(Formation.BACK, 2), driven)
	assert_eq(eng.state.enemy_formation.at(Formation.FRONT, 2), null)


## Fact 1 again, from their side: falling back inside your own column is a
## disarm, never an escape. He still takes the column's hits — he just cannot
## answer them.
func test_a_driven_man_still_takes_his_column_s_blows() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var driven := TestHelpers.grunt(E, "driven", 30, 6, 3, 3, Weapon.sword())
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [driven]})
	TestHelpers.station(eng.state.player_formation, p1, Formation.FRONT, 0)
	TestHelpers.station(eng.state.enemy_formation, driven, Formation.FRONT, 0)
	await _drive(eng, driven)
	assert_eq(eng.state.enemy_formation.column_melee_target(0), driven,
			"an empty front slot does not shield the man behind it")
	var hp_before := driven.hp
	await eng._fight_phase(P)
	assert_true(driven.hp < hp_before, "your man still reaches him")
	assert_false(eng._can_melee(driven), "and he has no swing to answer with")


## The card's whole skill test: it silences a swordsman and ARMS a bowman,
## because sniping is a second-line privilege.
func test_driving_a_bowman_back_upgrades_him() -> void:
	var bow := TestHelpers.grunt(E, "bow", 12, 6, 3, 3, Weapon.bow())
	var eng := TestHelpers.engine_for({"player_field": [TestHelpers.grunt(P, "p1")],
			"enemy_field": [bow]})
	TestHelpers.station(eng.state.enemy_formation, bow, Formation.FRONT, 3)
	assert_false(eng._is_sniper(bow), "at the rail he is a man with the wrong weapon")
	await _drive(eng, bow)
	assert_true(eng._is_sniper(bow), "driven back he starts picking off your weakest — play it on the wrong man and you help them")


func test_drive_him_back_is_refused_on_a_second_liner() -> void:
	var hiding := TestHelpers.grunt(E, "hiding")
	var eng := TestHelpers.engine_for({"player_field": [TestHelpers.grunt(P, "p1")],
			"enemy_field": [hiding]})
	TestHelpers.station(eng.state.enemy_formation, hiding, Formation.BACK, 1)
	eng.state.momentum = 5
	var card := await _drive(eng, hiding)
	assert_true(eng.state.hand.has(card), "he is already off the rail: refused, card kept")
	assert_eq(eng.state.momentum, 5, "nothing paid")
	assert_eq(eng.state.enemy_formation.at(Formation.BACK, 1), hiding)


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
	assert_true(eng.state.hand.has(card), "dead weight cannot be played; it just clogs the draw")


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


## Trade Places is the strongest positional tool in the game: any two of your
## men, on deck or on the ship. It is priced as an effect, not as a rider.
func test_trade_places_is_a_two_momentum_card_and_still_retained() -> void:
	var card := CardLibrary.swap()
	assert_eq(card.id, "swap", "the id is deck data; only the face changed")
	assert_eq(card.display_name, "Trade Places")
	assert_eq(card.cost, 2)
	assert_true(card.retained, "its job is the emergency rotation, on the turn it is needed")


## Port and starboard have no intrinsic meaning on a symmetric board, so
## an unequal deck is not flavour — it is a silent structural drift of your
## whole crew toward one rail (docs/card-design-proposal.md §2).
func test_both_decks_pull_equally_to_port_and_starboard() -> void:
	for deck_name in ["starter", "veteran"]:
		var deck: Array[CardData] = CardLibrary.starter_deck() if deck_name == "starter" \
				else CardLibrary.veteran_deck()
		var port := 0
		var starboard := 0
		for card in deck:
			for effect in card.effects:
				match effect.get("type"):
					CardData.EffectType.RIDER_PORT:
						port += 1
					CardData.EffectType.RIDER_STARBOARD:
						starboard += 1
		assert_true(port > 0, "%s deck carries the coin-flip riders at all" % deck_name)
		assert_eq(port, starboard,
				"%s deck: %d port vs %d starboard" % [deck_name, port, starboard])
