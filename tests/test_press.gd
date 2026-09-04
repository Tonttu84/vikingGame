extends TestCase
## The press (docs/press-proposal.md, ruled 2026-09-05): every column is a
## duel scored on BLOOD dealt into it this round; the side winning more
## columns has the press. Uncontested columns go to the side present, and
## presence comes first: blood into a column your side does not hold wins
## nothing. Payout is the win bonus: +1 momentum for having the press, +1
## more per column of margin, and the losing line takes -1 morale at margin
## >= 2. Damage from a man whose weapon carries the no-resolution tag (the
## bow) never scores a column, ranged or melee alike; row does not matter —
## a spear's reach from the second line counts like any steel.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY
const F := Formation.FRONT
const B := Formation.BACK


func _log_has(eng: CombatEngine, needle: String) -> bool:
	for line in eng.state.battle_log:
		if line.contains(needle):
			return true
	return false


## One full round of beats, then the verdict — the shape _enemy_turn uses.
func _round(eng: CombatEngine) -> void:
	await eng._fight_phase(P)
	await eng._fight_phase(E)
	eng._resolve_press()


## A fist-fighter (1 blood a swing) pinned on his slot so the geometry
## stays exactly what the test built.
func _post(side: Character.Side, id: String) -> Character:
	var c := TestHelpers.grunt(side, id, 30, 6, 1, 3, null)
	c.pinned = 9
	return c


## The player holds `margin` uncontested columns (1..3) while column 0 is a
## fist-for-fist tie: the cleanest press of a given margin.
func _sweep_engine(margin: int) -> CombatEngine:
	var crew: Array[Character] = [_post(P, "anchor")]
	for i in margin:
		crew.append(_post(P, "p%d" % i))
	var eng := TestHelpers.engine_for({"player_field": crew, "enemy_field": [_post(E, "foe")]})
	return eng


# --- The tag ------------------------------------------------------------------

func test_the_bow_carries_the_no_resolution_tag() -> void:
	assert_false(Weapon.bow().resolves_columns, "arrows kill; they do not win columns")
	assert_true(Weapon.sword().resolves_columns, "")
	assert_true(Weapon.spear().resolves_columns, "reach from the second row is steel like any other")
	assert_true(Weapon.axe().resolves_columns, "")
	assert_true(Weapon.fists().resolves_columns, "")


# --- Column duels ---------------------------------------------------------------

func test_more_blood_into_the_column_wins_it() -> void:
	var strong := TestHelpers.grunt(P, "strong", 30, 6, 5, 3, Weapon.sword())
	var weak := TestHelpers.grunt(E, "weak", 30, 6, 3, 3, null)
	var eng := TestHelpers.engine_for({"player_field": [strong], "enemy_field": [weak]})
	eng.state.momentum = 0
	await _round(eng)
	assert_eq(eng.state.last_press.get("holder"), "player", "7 blood against 3: the column is yours")
	assert_eq(eng.state.last_press.get("margin"), 1, "one column to none")
	assert_eq(eng.state.momentum, 2, "the win bonus: +1 for the press, +1 for the one column of margin")


func test_equal_blood_is_no_result() -> void:
	var eng := TestHelpers.engine_for({"player_field": [_post(P, "a")], "enemy_field": [_post(E, "b")]})
	eng.state.momentum = 0
	await _round(eng)
	assert_eq(eng.state.last_press.get("holder"), "none", "1 against 1: nobody has the press")
	assert_eq(eng.state.momentum, 0, "and nobody is paid")


func test_only_blood_counts_a_blocked_hit_is_zero() -> void:
	var hitter := TestHelpers.grunt(P, "hitter", 30, 6, 3, 3, null)
	var wall := TestHelpers.grunt(E, "wall", 30, 6, 1, 3, null, 9)
	var eng := TestHelpers.engine_for({"player_field": [hitter], "enemy_field": [wall]})
	eng.state.momentum = 0
	hitter.block = 9
	await _round(eng)
	assert_eq(eng.state.last_press.get("holder"), "none",
			"both blows died on the guard: 0-0, steel-on-shield scores nothing")


func test_a_spear_from_the_second_row_scores() -> void:
	var spear := TestHelpers.grunt(P, "spear", 30, 6, 4, 3, Weapon.spear())
	var foe := _post(E, "foe")
	var eng := TestHelpers.engine_for({"player_field": [spear], "enemy_field": [foe]})
	TestHelpers.station(eng.state.player_formation, spear, B, 0)
	TestHelpers.cover_at(eng, P, 0)
	await _round(eng)
	assert_eq(eng.state.player_column_blood[0], 3 + 5,
			"the cover man's 3 and the covered spear's 5 reach blood are both on column 0's ledger")


func test_an_archers_blood_never_scores() -> void:
	var bow := TestHelpers.grunt(E, "bow", 30, 6, 5, 3, Weapon.bow())
	var pc := _post(P, "pc")
	var eng := TestHelpers.engine_for({"player_field": [pc], "enemy_field": [bow]})
	eng.state.momentum = 0
	await _round(eng)
	assert_eq(eng.state.enemy_column_blood[0], 0,
			"uncovered, she fights hand to hand for 6 — tagged out, none of it is on the ledger")
	assert_eq(eng.state.last_press.get("holder"), "player", "the fist's 1 blood wins the column")


func test_the_double_shot_lands_but_scores_nothing() -> void:
	var bow := TestHelpers.grunt(E, "bow", 30, 6, 2, 3, Weapon.bow())
	var mark := _post(P, "mark")
	var eng := TestHelpers.engine_for({"player_field": [mark], "enemy_field": [bow]})
	TestHelpers.station(eng.state.enemy_formation, bow, B, 3)
	TestHelpers.cover_at(eng, E, 3)
	bow.beat = 1
	eng.state.archer_marks[bow] = mark
	await _round(eng)
	assert_eq(mark.hp, 30 - 4, "both arrows bite")
	assert_eq(eng.state.enemy_column_blood[0], 0, "and none of it is on the ledger")


func test_grazes_count_in_the_column_they_land_in() -> void:
	var berserk := TestHelpers.grunt(P, "berserk", 30, 1, 5, 4, Weapon.axe())
	berserk.is_berserker = true
	var second := _post(P, "second")
	var mark := _post(E, "mark")
	var neighbor := _post(E, "neighbor")
	var eng := TestHelpers.engine_for({"player_field": [berserk, second],
			"enemy_field": [mark, neighbor]})
	await _round(eng)
	var columns: Array = eng.state.last_press.get("columns")
	assert_eq(columns[0], 1, "the main blow wins column 0")
	assert_eq(eng.state.player_column_blood[1], 1 + 2,
			"column 1: your second man's fist plus the graze that spilled there")
	assert_eq(columns[1], 1, "3 against the neighbor's 1: the graze tipped it")


# --- Presence --------------------------------------------------------------------

func test_an_uncontested_column_is_won_by_the_side_present() -> void:
	var lone := _post(P, "lone")
	var foe := _post(E, "foe")
	var eng := TestHelpers.engine_for({"player_field": [lone], "enemy_field": [foe]})
	TestHelpers.station(eng.state.player_formation, lone, F, 3)
	eng.state.momentum = 0
	await _round(eng)
	var columns: Array = eng.state.last_press.get("columns")
	assert_eq(columns[3], 1, "nobody faces him: column 3 is his, at 0 blood")
	assert_eq(columns[0], -1, "and column 0 is theirs the same way")
	assert_eq(eng.state.last_press.get("holder"), "none", "one each: no press")


func test_a_column_empty_on_both_sides_scores_nothing() -> void:
	var a := TestHelpers.grunt(P, "a", 30, 6, 5, 3, Weapon.sword())
	var eng := TestHelpers.engine_for({"player_field": [a], "enemy_field": [_post(E, "b")]})
	await _round(eng)
	var columns: Array = eng.state.last_press.get("columns")
	assert_eq(columns[1], 0, "")
	assert_eq(columns[2], 0, "")
	assert_eq(columns[3], 0, "empty deck scores for nobody")
	assert_eq(eng.state.last_press.get("margin"), 1, "only the one contested column counts")


func test_columns_are_scored_where_men_stand_after_the_beats() -> void:
	# The closing step moves him into column 2 with 0 blood dealt; nobody
	# faces him there, so it is his by presence — and column 1 stays theirs.
	var walker := TestHelpers.grunt(P, "walker", 30, 6, 3, 3, null)
	var foe := _post(E, "foe")
	var eng := TestHelpers.engine_for({"player_field": [walker], "enemy_field": [foe]})
	TestHelpers.station(eng.state.player_formation, walker, F, 3)
	TestHelpers.station(eng.state.enemy_formation, foe, F, 1)
	await eng._fight_phase(P)
	assert_eq(eng.state.player_formation.column_of(walker), 2, "he walks one column")
	await eng._fight_phase(E)
	eng._resolve_press()
	var columns: Array = eng.state.last_press.get("columns")
	assert_eq(columns[2], 1, "the column he arrived in is his alone")
	assert_eq(columns[1], -1, "theirs stays theirs")
	assert_eq(columns[3], 0, "the column he left is nobody's")


# --- The payout ------------------------------------------------------------------

func test_the_win_bonus_pays_flat_plus_margin() -> void:
	var eng := _sweep_engine(3)
	eng.state.momentum = 0
	await _round(eng)
	assert_eq(eng.state.last_press.get("margin"), 3, "three columns to none, column 0 a tie")
	assert_eq(eng.state.momentum, 1 + 3, "+1 for the press, +1 per column of margin")


func test_the_momentum_cap_still_holds() -> void:
	var eng := _sweep_engine(3)
	eng.state.momentum = BattleState.MOMENTUM_CAP - 1
	await _round(eng)
	assert_eq(eng.state.momentum, BattleState.MOMENTUM_CAP, "")


func test_the_losing_line_bleeds_morale_at_margin_two() -> void:
	var eng := _sweep_engine(2)
	var foe: Character = eng.state.enemy_formation.fielded()[0]
	var morale_before := foe.morale
	await _round(eng)
	assert_eq(foe.morale, morale_before - BattleState.PRESS_MORALE,
			"a line giving two columns loses heart")


func test_no_morale_leak_at_margin_one() -> void:
	var eng := _sweep_engine(1)
	var foe: Character = eng.state.enemy_formation.fielded()[0]
	var morale_before := foe.morale
	await _round(eng)
	assert_eq(eng.state.last_press.get("margin"), 1, "")
	assert_eq(foe.morale, morale_before, "one column is a lead, not a rout")


func test_the_enemy_press_pays_only_morale() -> void:
	var lone := _post(P, "lone")
	var eng := TestHelpers.engine_for({"player_field": [lone],
			"enemy_field": [_post(E, "e1"), _post(E, "e2"), _post(E, "e3")]})
	eng.state.momentum = 3
	var morale_before := lone.morale
	await _round(eng)
	assert_eq(eng.state.last_press.get("holder"), "enemy",
			"column 0 ties fist for fist; columns 1 and 2 are theirs by presence")
	assert_eq(eng.state.momentum, 3, "the enemy has no momentum to gain, and you lose none")
	assert_eq(lone.morale, morale_before - BattleState.PRESS_MORALE, "your line gives: -1 morale")


func test_the_morale_immune_ignore_the_press() -> void:
	var eng := _sweep_engine(2)
	var foe: Character = eng.state.enemy_formation.fielded()[0]
	foe.is_berserker = true
	var morale_before := foe.morale
	await _round(eng)
	assert_eq(foe.morale, morale_before, "berserkers do not care who has the press")


# --- Round plumbing ----------------------------------------------------------------

func test_blood_tallies_reset_each_player_turn() -> void:
	var strong := TestHelpers.grunt(P, "strong", 30, 6, 5, 3, Weapon.sword())
	var weak := TestHelpers.grunt(E, "weak", 30, 6, 1, 3, null)
	var eng := TestHelpers.engine_for({"player_field": [strong], "enemy_field": [weak]})
	await eng._fight_phase(P)
	assert_eq(eng.state.player_column_blood[0], 7, "the round's blood is on the ledger")
	eng.state.player_column_blood[0] = 99
	await eng._player_turn()
	assert_eq(eng.state.player_column_blood[0], 7,
			"a fresh turn opens a fresh ledger: only this turn's 7, never 99 + 7")


func test_the_press_resolves_before_reinforcements() -> void:
	var strong := TestHelpers.grunt(P, "strong", 30, 6, 5, 3, Weapon.sword())
	var weak := TestHelpers.grunt(E, "weak", 30, 6, 1, 3, null)
	var below := TestHelpers.grunt(E, "below", 30, 6, 1, 3, null)
	var eng := TestHelpers.engine_for({"player_field": [strong], "enemy_field": [weak],
			"enemy_reserve": [below]})
	await eng._fight_phase(P)
	await eng._enemy_turn()
	var press_at := -1
	var reinforce_at := -1
	for i in eng.state.battle_log.size():
		if press_at == -1 and eng.state.battle_log[i].contains("press"):
			press_at = i
		if reinforce_at == -1 and eng.state.battle_log[i].contains("comes up from below"):
			reinforce_at = i
	assert_true(press_at != -1, "the verdict is in the saga")
	assert_true(reinforce_at != -1, "and the reinforcement too")
	assert_true(press_at < reinforce_at, "the press is judged before fresh men fill the gaps")
