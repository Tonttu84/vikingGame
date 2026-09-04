extends TestCase
## The sim harness's controllers. The random bot is deliberately dumb — it
## exists to exercise the rules and set a floor, not to play well — but dumb
## is not the same as wrong: it must never propose a play the engine refuses.
## Since the rider gate landed, a card can be unplayable because of where your
## own men are standing, and a bot that keeps offering one turns a real
## decision into a wasted action and quietly distorts every balance number.
## The bot does not work legality out for itself; it asks the engine, exactly
## as the UI does.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY
const F := Formation.FRONT
const B := Formation.BACK


func _bot_engine(seed_value := 5) -> CombatEngine:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bot := Bots.RandomBot.new(rng)
	var eng := CombatEngine.new()
	bot.engine = eng
	eng.setup(Scenarios.default_skirmish(), bot, seed_value)
	return eng


## Four men packed into the two port columns, enemies right across from
## them: no sidestep, no press, no give-ground and nothing to close on.
## Since riders swap by default, a packed grid no longer refuses anything —
## only the board's edge and a pin do. The boxed-in crew is therefore two
## men jammed against the port rail, the rear one pinned: port is off the
## ship, Give Ground would trade with a pinned man, Press is pinned shut,
## and the enemy stands in their own column so there is nothing to close on.
func _boxed_in() -> CombatEngine:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var bot := Bots.RandomBot.new(rng)
	var eng := CombatEngine.new()
	bot.engine = eng
	var front_man := TestHelpers.grunt(P, "front_man")
	var pinned_man := TestHelpers.grunt(P, "pinned_man")
	var foe_front := TestHelpers.grunt(E, "foe_front", 30)
	var foe_back := TestHelpers.grunt(E, "foe_back", 30)
	eng.setup({"player_field": [front_man], "enemy_field": [foe_front]}, bot, 3)
	TestHelpers.station(eng.state.player_formation, pinned_man, B, 0)
	TestHelpers.station(eng.state.enemy_formation, foe_back, B, 0)
	pinned_man.pinned = 2
	eng.state.momentum = BattleState.MOMENTUM_CAP
	return eng


func test_the_random_bot_only_proposes_plays_the_engine_accepts() -> void:
	var eng := _bot_engine()
	eng.state.momentum = BattleState.MOMENTUM_CAP
	eng._draw_to_hand_size()
	for i in 30:
		if eng.outcome != CombatEngine.Outcome.NONE:
			break
		var action: Dictionary = eng.controller.choose_action(eng.state)
		if action.get("op", "end") == "end":
			break
		var card: CardData = action.get("card")
		await eng._apply_action(action)
		if card != null:
			assert_false(eng.state.hand.has(card),
					"the engine accepted the bot's %s rather than refusing it" % card.id)


func test_a_boxed_in_bot_ends_its_turn_instead_of_spinning() -> void:
	var eng := _boxed_in()
	for id in ["spear_volley", "war_cry", "shield_wall", "battle_fury", "feint"]:
		eng.state.hand.append(CardLibrary.by_id(id))
	assert_eq(eng.controller.choose_action(eng.state).get("op"), "end",
			"every rider in that hand is walled in: there is nothing to play")


## Whatever the gate refuses, the engine's own answer is the one the bot uses:
## no card legality is re-derived in src/sim.
func test_the_bot_agrees_with_the_engine_about_a_boxed_in_hand() -> void:
	var eng := _boxed_in()
	for id in ["spear_volley", "shield_wall", "feint"]:
		var card := CardLibrary.by_id(id)
		eng.state.hand.append(card)
		assert_false(eng.can_play(card), "%s has nowhere to move a man" % id)


## The turn's opening is the bot's crossing priority now, and the same rule
## holds as for cards: never propose what the engine will refuse. A refused
## opening is not a wasted action but something worse — it silently becomes
## the income, and the balance numbers would read as if the bot had chosen it.
func _opening_is_legal(eng: CombatEngine, answer: Dictionary) -> bool:
	var op: String = answer.get("op", "")
	if not eng.opening_options().has(op):
		return false
	match op:
		"reinforce":
			return eng.crossing_candidates().has(answer.get("character"))
		"swap":
			return eng.swap_partners(answer.get("character")).has(answer.get("partner"))
	return op == "income"


func test_the_random_bots_opening_is_always_one_the_engine_accepts() -> void:
	for seed_value in [2, 5, 9]:
		var eng := _bot_engine(seed_value)
		for turn in 12:
			if eng.outcome != CombatEngine.Outcome.NONE:
				break
			eng.state.turn += 1
			var answer: Dictionary = eng.controller.choose_opening(eng.state)
			assert_true(_opening_is_legal(eng, answer),
					"seed %d turn %d: the engine would refuse %s" % [seed_value, turn, str(answer)])
			eng._apply_opening(answer, eng.opening_options())
			await eng._enemy_turn()


func test_the_bot_takes_the_income_when_nothing_else_is_open() -> void:
	var eng := _boxed_in()
	# Two men jammed against the port rail, nobody on the ship: no crossing,
	# and the one unpinned man has no partner to trade with.
	assert_eq(eng.opening_options(), ["income"] as Array[String], "nothing to move")
	assert_eq(eng.controller.choose_opening(eng.state).get("op"), "income")
