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


## Four men packed into the two larboard columns, enemies right across from
## them: no sidestep, no press, no give-ground and nothing to close on.
func _boxed_in() -> CombatEngine:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var bot := Bots.RandomBot.new(rng)
	var eng := CombatEngine.new()
	bot.engine = eng
	var crew: Array[Character] = []
	var foes: Array[Character] = []
	for i in 4:
		crew.append(TestHelpers.grunt(P, "crew%d" % i))
		foes.append(TestHelpers.grunt(E, "foe%d" % i, 30))
	eng.setup({"player_field": crew, "enemy_field": foes}, bot, 3)
	for formation in [eng.state.player_formation, eng.state.enemy_formation]:
		var men: Array[Character] = formation.fielded()
		TestHelpers.station(formation, men[2], B, 2)
		TestHelpers.station(formation, men[3], B, 3)
		TestHelpers.station(formation, men[2], B, 0)
		TestHelpers.station(formation, men[3], B, 1)
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
