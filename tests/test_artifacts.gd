extends TestCase
## Artifacts: run-long passives hooked into the combat engine, plus their
## RosterText round-trip. Written first, TDD.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY


func test_library_builds_artifacts_by_id() -> void:
	var artifact := ArtifactLibrary.by_id("lindisfarne_chalice")
	assert_true(artifact != null)
	assert_eq(artifact.id, "lindisfarne_chalice")
	assert_eq(ArtifactLibrary.by_id("no_such_artifact"), null)
	for id in ArtifactLibrary.artifact_ids():
		var built := ArtifactLibrary.by_id(id)
		assert_true(built != null and built.id == id, "every listed id builds: " + id)


func test_chalice_grants_momentum_at_battle_start() -> void:
	var crew := TestHelpers.grunt(P, "crew")
	var eng := TestHelpers.engine_for({
		"player_field": [crew],
		"artifacts": [ArtifactLibrary.by_id("lindisfarne_chalice")],
	})
	assert_eq(eng.state.momentum, 1, "+1 momentum before the first turn")
	await eng._player_turn()
	assert_eq(eng.state.momentum, 3, "turn income and the opening's income stack on top")


func test_serpent_prow_frightens_the_enemy_line() -> void:
	var e1 := TestHelpers.grunt(E, "e1")
	var e2 := TestHelpers.grunt(E, "e2", 12, 1)
	var berserk := TestHelpers.grunt(E, "berserk", 10, 1)
	berserk.is_berserker = true
	var eng := TestHelpers.engine_for({
		"enemy_field": [e1, e2, berserk],
		"artifacts": [ArtifactLibrary.by_id("serpent_prow")],
	})
	assert_eq(e1.morale, 4, "1 from the prow, 1 more when e2 routs beside him")
	assert_true(eng.state.enemy_routed.has(e2), "morale 1 breaks at the sight of the prow")
	assert_eq(berserk.morale, 1, "berserkers do not feel fear")


func test_grilling_irons_feed_the_crew() -> void:
	var crew := TestHelpers.grunt(P, "crew")
	var reserve := TestHelpers.grunt(P, "reserve")
	var eng := TestHelpers.engine_for({
		"player_field": [crew],
		"player_reserve": [reserve],
		"artifacts": [ArtifactLibrary.by_id("grilling_irons")],
	})
	assert_eq(crew.morale, 7, "a well-fed crew stands taller")
	assert_eq(crew.max_morale, 7, "the bonus raises the cap, not just the current value")
	assert_eq(reserve.morale, 7, "the reserve eats too")
	assert_true(eng.state.battle_log.size() > 0)


func test_raven_banner_suppresses_first_death_wave_only() -> void:
	var cap := TestHelpers.captain_of(P, "cap")
	var crew1 := TestHelpers.grunt(P, "crew1")
	var crew2 := TestHelpers.grunt(P, "crew2")
	var crew3 := TestHelpers.grunt(P, "crew3")
	var eng := TestHelpers.engine_for({
		"player_field": [cap, crew1, crew2, crew3],
		"artifacts": [ArtifactLibrary.by_id("raven_banner")],
	})
	crew1.hp = 0
	await eng._handle_death(crew1)
	assert_eq(crew2.morale, 6, "the banner holds the line: no morale wave")
	crew2.hp = 0
	await eng._handle_death(crew2)
	assert_eq(crew3.morale, 4, "the second death hits as usual")


func test_raven_banner_ignores_enemy_deaths() -> void:
	var e1 := TestHelpers.grunt(E, "e1")
	var e2 := TestHelpers.grunt(E, "e2")
	var eng := TestHelpers.engine_for({
		"enemy_field": [e1, e2],
		"artifacts": [ArtifactLibrary.by_id("raven_banner")],
	})
	e1.hp = 0
	await eng._handle_death(e1)
	assert_eq(e2.morale, 4, "our banner does nothing for their morale")
	var cap := TestHelpers.captain_of(P, "cap")
	var crew1 := TestHelpers.grunt(P, "crew1")
	var crew2 := TestHelpers.grunt(P, "crew2")
	var eng2 := TestHelpers.engine_for({
		"player_field": [cap, crew1, crew2],
		"enemy_field": [TestHelpers.grunt(E, "e3")],
		"artifacts": [ArtifactLibrary.by_id("raven_banner")],
	})
	var e3: Character = eng2.state.fielded(E)[0]
	e3.hp = 0
	await eng2._handle_death(e3)
	crew1.hp = 0
	await eng2._handle_death(crew1)
	assert_eq(crew2.morale, 6, "an earlier enemy death does not spend the banner")


func test_roster_text_round_trips_artifacts() -> void:
	var text := """
[player field]
Captain | captain
[enemy captain]
Jarl
[artifacts]
lindisfarne_chalice
raven_banner
"""
	var parsed := RosterText.parse(text)
	assert_eq(parsed["errors"], [] as Array[String])
	var artifacts: Array = parsed["scenario"].get("artifacts", [])
	assert_eq(artifacts.size(), 2)
	assert_eq(artifacts[0].id, "lindisfarne_chalice")
	var round_trip := RosterText.parse(RosterText.serialize(parsed["scenario"]))
	assert_eq(round_trip["errors"], [] as Array[String])
	var again: Array = round_trip["scenario"].get("artifacts", [])
	assert_eq(again.size(), 2, "serialize writes the [artifacts] section back out")


func test_roster_text_rejects_unknown_artifact() -> void:
	var text := """
[player field]
Captain | captain
[enemy captain]
Jarl
[artifacts]
sword_of_a_thousand_truths
"""
	var parsed := RosterText.parse(text)
	assert_eq(parsed["errors"].size(), 1)
	assert_true(String(parsed["errors"][0]).contains("unknown artifact"))
