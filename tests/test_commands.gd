extends TestCase
## The captain's command (docs/block-and-patterns.md): every Nth enemy turn
## the telegraphed tactic IS the command — it replaces whatever the rotation
## would have picked, from the sterncastle or the line alike. The first
## command, blood_rage, hands every fielded defender a permanent, stacking
## +1 attack damage: the escalation that guarantees no fight locks up.
## Commands are scenario data, so later captains can carry different ones.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY

const COMMAND := {"name": "Blood for blood", "effect": "blood_rage", "amount": 1, "period": 3}


func _log_has(eng: CombatEngine, needle: String) -> bool:
	for line in eng.state.battle_log:
		if line.contains(needle):
			return true
	return false


func _commanded_engine(extra := {}) -> CombatEngine:
	var scenario := {
		"player_field": [TestHelpers.grunt(P, "pc", 40)],
		"enemy_field": [TestHelpers.grunt(E, "e1"), TestHelpers.grunt(E, "e2")],
		"enemy_reserve": [TestHelpers.grunt(E, "below")],
		"enemy_captain": TestHelpers.captain_of(E, "jarl"),
		"captain_command": COMMAND,
	}
	scenario.merge(extra, true)
	return TestHelpers.engine_for(scenario)


func test_the_command_replaces_the_rotation_every_nth_turn() -> void:
	var eng := _commanded_engine()
	assert_eq(eng._pick_tactic_for(3), "captains_order", "turn 3: the command")
	assert_eq(eng._pick_tactic_for(6), "captains_order", "turn 6: again — it never stops")
	assert_eq(eng._pick_tactic_for(2), "press_the_attack", "off the beat, the rotation runs")
	assert_eq(eng._pick_tactic_for(4), "press_the_attack", "")


func test_no_command_configured_means_no_order() -> void:
	var eng := TestHelpers.engine_for({
		"player_field": [TestHelpers.grunt(P, "pc")],
		"enemy_field": [TestHelpers.grunt(E, "e1")],
	})
	assert_eq(eng._pick_tactic_for(3), "press_the_attack",
			"bare scenarios have no captain to speak")


func test_the_command_needs_no_fielded_captain() -> void:
	var eng := _commanded_engine()
	assert_false(eng.state.enemy_formation.has(eng.state.enemy_captain),
			"the jarl still waits ashore")
	await eng._resolve_tactic("captains_order")
	assert_true(_log_has(eng, "Blood for blood"), "his voice carries from the sterncastle")


func test_blood_rage_is_permanent_and_stacks_on_the_fielded() -> void:
	var eng := _commanded_engine()
	var e1: Character = eng.state.enemy_formation.fielded()[0]
	var below: Character = eng.state.enemy_reserve[0]
	await eng._resolve_tactic("captains_order")
	await eng._resolve_tactic("captains_order")
	assert_eq(e1.rage, 2, "two commands, two stacks, forever")
	assert_eq(below.rage, 0, "a man below decks misses the speech")


func test_a_late_reinforcement_missed_the_speech() -> void:
	var eng := _commanded_engine()
	await eng._resolve_tactic("captains_order")
	var below: Character = eng.state.enemy_reserve[0]
	eng._reinforce()
	assert_true(eng.state.enemy_formation.has(below), "he comes up after the roar")
	assert_eq(below.rage, 0, "and carries none of it")


func test_rage_raises_every_blow() -> void:
	var eng := _commanded_engine()
	var e1: Character = eng.state.enemy_formation.fielded()[0]
	var pc: Character = eng.state.player_formation.fielded()[0]
	assert_eq(eng._melee_damage(e1, pc), 3, "3 Str, bare hands")
	await eng._resolve_tactic("captains_order")
	assert_eq(eng._melee_damage(e1, pc), 4, "the command rides on every swing he makes")


func test_forecast_previews_the_commanded_blows() -> void:
	var eng := _commanded_engine()
	var e1: Character = eng.state.enemy_formation.fielded()[0]
	var pc: Character = eng.state.player_formation.fielded()[0]
	eng.state.next_tactic = "captains_order"
	var bill: Dictionary = eng.forecast()
	assert_eq(bill[pc]["hp"], 4, "the order fires before they swing: 3 Str + 1 rage billed")
	assert_eq(e1.rage, 0, "the preview never rages the real man")


func test_both_anchor_scenarios_carry_the_command() -> void:
	for id in Scenarios.scenario_ids():
		var command: Dictionary = Scenarios.by_id(id).get("captain_command", {})
		assert_eq(command.get("effect"), "blood_rage", "%s: the jarl has his word" % id)
		assert_eq(command.get("period"), 4, "%s: every 4th turn" % id)
