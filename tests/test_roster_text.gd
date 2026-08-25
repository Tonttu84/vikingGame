extends TestCase
## RosterText: the debug panel's text format for editing battle setups.
## Parse builds a scenario Dictionary the engine accepts; serialize turns a
## scenario back into text, and the two round-trip.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY

const MINIMAL := """
[player field]
Captain Aslak | hp 20 | morale 10 | str 4 | speed 4 | sword | armor 2 | captain
Spearman Orm | hp 12 | morale 6 | str 3 | speed 3 | spear | armor 1

[enemy captain]
Jarl Sigvard | hp 25 | morale 10 | str 5 | speed 3 | sword | armor 2

[enemy field]
Housecarl Bran | hp 12 | morale 6 | str 3 | speed 3 | axe | armor 1
"""


func test_parses_sections_into_scenario() -> void:
	var result := RosterText.parse(MINIMAL)
	assert_eq(result["errors"], [] as Array[String], "no errors")
	var scenario: Dictionary = result["scenario"]
	assert_eq(scenario["player_field"].size(), 2)
	assert_eq(scenario["enemy_field"].size(), 1)
	assert_eq(scenario["player_reserve"].size(), 0)
	var cap: Character = scenario["enemy_captain"]
	assert_eq(cap.display_name, "Jarl Sigvard")
	assert_true(cap.is_captain, "enemy captain flagged")
	assert_eq(cap.side, E)


func test_parses_stats_weapon_and_flags() -> void:
	var result := RosterText.parse(MINIMAL)
	var aslak: Character = result["scenario"]["player_field"][0]
	assert_eq(aslak.hp, 20)
	assert_eq(aslak.morale, 10)
	assert_eq(aslak.strength, 4)
	assert_eq(aslak.speed, 4)
	assert_eq(aslak.armor, 2)
	assert_eq(aslak.weapon.kind, Weapon.Kind.SWORD)
	assert_true(aslak.is_captain)
	assert_eq(aslak.side, P)
	var orm: Character = result["scenario"]["player_field"][1]
	assert_false(orm.is_captain)
	assert_eq(orm.weapon.kind, Weapon.Kind.SPEAR)


func test_omitted_stats_use_defaults() -> void:
	var result := RosterText.parse("[player field]\nNobody | captain\n[enemy captain]\nFoe")
	assert_eq(result["errors"], [] as Array[String])
	var c: Character = result["scenario"]["player_field"][0]
	assert_eq(c.hp, 12)
	assert_eq(c.morale, 6)
	assert_eq(c.strength, 3)
	assert_eq(c.speed, 3)
	assert_eq(c.armor, 0)
	assert_eq(c.weapon.kind, Weapon.Kind.NONE)


func test_berserker_flag_and_reserves() -> void:
	var text := MINIMAL + "\n[enemy reserve]\nBerserker Glum | hp 10 | morale 1 | str 5 | speed 4 | axe | berserker\n"
	var result := RosterText.parse(text)
	assert_eq(result["errors"], [] as Array[String])
	var glum: Character = result["scenario"]["enemy_reserve"][0]
	assert_true(glum.is_berserker)
	assert_true(glum.morale_immune())


func test_deck_section_builds_deck_by_card_id() -> void:
	var text := MINIMAL + "\n[deck]\n2x spear_volley\nrally\n"
	var result := RosterText.parse(text)
	assert_eq(result["errors"], [] as Array[String])
	var deck: Array = result["scenario"]["deck"]
	assert_eq(deck.size(), 3)
	assert_eq(deck[0].id, "spear_volley")
	assert_eq(deck[1].id, "spear_volley")
	assert_eq(deck[2].id, "rally")


func test_no_deck_section_means_starter_deck() -> void:
	var result := RosterText.parse(MINIMAL)
	assert_eq(result["scenario"]["deck"].size(), CardLibrary.starter_deck().size())


func test_comments_and_blank_lines_ignored() -> void:
	var text := "# a comment\n\n[player field]\n# another\nSomeone | captain\n[enemy captain]\nFoe\n"
	var result := RosterText.parse(text)
	assert_eq(result["errors"], [] as Array[String])
	assert_eq(result["scenario"]["player_field"].size(), 1)


func test_errors_carry_line_numbers_and_do_not_crash() -> void:
	var text := "Stray Before Section\n[player field]\nOk Guy | hp 12 | captain\nBad Guy | hp twelve\nWeird | flail\n[no such section]\n[deck]\n3x not_a_card\n[enemy captain]\nFoe\n"
	var result := RosterText.parse(text)
	var errors: Array[String] = result["errors"]
	assert_eq(errors.size(), 5, "stray line, bad stat, bad token, bad section, bad card id")
	assert_true(errors[0].contains("1"), "line numbers reported")


func test_error_messages_name_the_problem() -> void:
	var result := RosterText.parse("[player field]\nGuy | flail | captain\n[enemy captain]\nFoe")
	assert_eq(result["errors"].size(), 1)
	var msg: String = result["errors"][0]
	assert_true(msg.contains("2"), "line number in message")
	assert_true(msg.contains("flail"), "offending token in message")


func test_missing_player_captain_is_an_error() -> void:
	var result := RosterText.parse("[player field]\nGuy\n[enemy captain]\nFoe")
	assert_eq(result["errors"].size(), 1)
	assert_true(result["errors"][0].contains("captain"))


func test_missing_enemy_captain_is_an_error() -> void:
	var result := RosterText.parse("[player field]\nGuy | captain")
	assert_eq(result["errors"].size(), 1)
	assert_true(result["errors"][0].contains("captain"))


func test_round_trip_default_skirmish() -> void:
	var text := RosterText.serialize(Scenarios.default_skirmish())
	var result := RosterText.parse(text)
	assert_eq(result["errors"], [] as Array[String], "serialized default skirmish parses cleanly")
	var scenario: Dictionary = result["scenario"]
	var reference := Scenarios.default_skirmish()
	for key in ["player_field", "player_reserve", "enemy_field", "enemy_reserve"]:
		assert_eq(scenario[key].size(), reference[key].size(), key + " size")
	assert_eq(scenario["deck"].size(), reference["deck"].size(), "deck size")
	assert_eq(scenario["enemy_tactics"], reference["enemy_tactics"], "tactics preserved")
	var aslak: Character = scenario["player_field"][0]
	assert_eq(aslak.display_name, "Captain Aslak")
	assert_true(aslak.is_captain)


func test_parsed_scenario_runs_a_full_battle() -> void:
	var result := RosterText.parse(RosterText.serialize(Scenarios.default_skirmish()))
	var eng := TestHelpers.engine_for(result["scenario"], Bots.NoCardBot.new(), 11)
	var summary: Dictionary = await eng.run()
	assert_true(summary["outcome"] != "NONE")
