extends TestCase
## The scenario registry: the starter skirmish and the veteran raid are the
## two balance anchors — a fresh crew with the starter deck, and a blooded,
## richer crew hitting a jarl's warship. Sims and the UI pick by id.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY


func test_registry_lists_both_scenarios() -> void:
	assert_eq(Scenarios.scenario_ids(), ["skirmish", "veteran"] as Array[String])


func test_by_id_builds_every_listed_scenario() -> void:
	for id in Scenarios.scenario_ids():
		var scenario := Scenarios.by_id(id)
		for key in ["player_field", "player_reserve", "enemy_field",
				"enemy_reserve", "enemy_captain", "deck", "maneuvers", "enemy_tactics"]:
			assert_true(scenario.has(key), "%s has %s" % [id, key])
	assert_true(Scenarios.by_id("no_such_battle").is_empty(), "unknown id is empty")


func test_skirmish_id_is_the_default_skirmish() -> void:
	var by_id := Scenarios.by_id("skirmish")
	var reference := Scenarios.default_skirmish()
	assert_eq(by_id["player_field"].size(), reference["player_field"].size())
	assert_eq(by_id["deck"].size(), reference["deck"].size())


func test_veteran_crew_is_bigger_and_better_armed() -> void:
	var starter := Scenarios.default_skirmish()
	var veteran := Scenarios.veteran_raid()
	var starter_crew: int = starter["player_field"].size() + starter["player_reserve"].size()
	var veteran_crew: int = veteran["player_field"].size() + veteran["player_reserve"].size()
	assert_true(veteran_crew > starter_crew, "the blooded crew has grown")
	assert_true(veteran["deck"].size() > starter["deck"].size(), "loot and lessons: more cards")
	var starter_armor := 0
	for c: Character in starter["player_field"] + starter["player_reserve"]:
		starter_armor += c.armor
	var veteran_armor := 0
	for c: Character in veteran["player_field"] + veteran["player_reserve"]:
		veteran_armor += c.armor
	assert_true(veteran_armor > starter_armor, "veterans wear their plunder")


func test_veteran_enemy_is_a_harder_ship() -> void:
	var starter := Scenarios.default_skirmish()
	var veteran := Scenarios.veteran_raid()
	var starter_foes: int = starter["enemy_field"].size() + starter["enemy_reserve"].size()
	var veteran_foes: int = veteran["enemy_field"].size() + veteran["enemy_reserve"].size()
	assert_true(veteran_foes > starter_foes, "a jarl's warship carries more men")
	var starter_captain: Character = starter["enemy_captain"]
	var veteran_captain: Character = veteran["enemy_captain"]
	assert_true(veteran_captain.max_hp > starter_captain.max_hp, "a harder captain")
	assert_true(veteran_captain.is_captain)


func test_veteran_character_ids_are_unique() -> void:
	var veteran := Scenarios.veteran_raid()
	var seen := {}
	var all: Array = veteran["player_field"] + veteran["player_reserve"] \
			+ veteran["enemy_field"] + veteran["enemy_reserve"] + [veteran["enemy_captain"]]
	for c: Character in all:
		assert_false(seen.has(c.id), "duplicate id %s" % c.id)
		seen[c.id] = true


func test_veteran_deck_ids_all_resolve() -> void:
	for card: CardData in Scenarios.veteran_raid()["deck"]:
		assert_true(CardLibrary.by_id(card.id) != null, "veteran deck id %s resolves" % card.id)


func test_round_trip_veteran_raid() -> void:
	var text := RosterText.serialize(Scenarios.veteran_raid())
	var result := RosterText.parse(text)
	assert_eq(result["errors"], [] as Array[String], "serialized veteran raid parses cleanly")
	var scenario: Dictionary = result["scenario"]
	var reference := Scenarios.veteran_raid()
	for key in ["player_field", "player_reserve", "enemy_field", "enemy_reserve"]:
		assert_eq(scenario[key].size(), reference[key].size(), key + " size")
	assert_eq(scenario["deck"].size(), reference["deck"].size(), "deck size")


func test_veteran_battle_completes_and_counts_losses() -> void:
	var eng := TestHelpers.engine_for(Scenarios.veteran_raid(), Bots.NoCardBot.new(), 17)
	var result: Dictionary = await eng.run()
	assert_true(result["outcome"] != "NONE", "the veteran battle resolves")
	var crew: int = Scenarios.veteran_raid()["player_field"].size() \
			+ Scenarios.veteran_raid()["player_reserve"].size()
	assert_eq(result["player_dead"] + result["player_fled"] + result["player_survivors"],
			crew, "every crewman is accounted for: dead, fled or standing")


func test_veteran_same_seed_same_battle() -> void:
	var a := TestHelpers.engine_for(Scenarios.veteran_raid(), Bots.NoCardBot.new(), 5)
	var b := TestHelpers.engine_for(Scenarios.veteran_raid(), Bots.NoCardBot.new(), 5)
	await a.run()
	await b.run()
	assert_eq(a.state.battle_log, b.state.battle_log, "same seed, same veteran battle")
