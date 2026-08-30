extends TestCase
## Role kits: hooks riding boolean flags and weapon kinds. Berserker cleave,
## the captain's leader aura, and covering-volley scaling. The shieldman's
## old kit (halving + armor aura) died with armor itself
## (docs/block-and-patterns.md); his block kit arrives with the patterns.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY
const F := Formation.FRONT
const B := Formation.BACK


func _log_has(eng: CombatEngine, needle: String) -> bool:
	for line in eng.state.battle_log:
		if line.contains(needle):
			return true
	return false


# --- Shieldman: the old hide is gone (the block kit lands with patterns) -----

func test_shieldman_no_longer_halves() -> void:
	var hitter := TestHelpers.grunt(P, "hitter", 12, 6, 5, 3, Weapon.sword())
	var shieldman := TestHelpers.grunt(E, "shieldman")
	shieldman.is_shieldman = true
	var eng := TestHelpers.engine_for({"player_field": [hitter], "enemy_field": [shieldman]})
	await eng._attack(hitter, shieldman)
	assert_eq(shieldman.hp, 12 - 7, "the full 7 (5 Str + 2 sword): his defense is block now")


func test_side_wide_softening_still_applies_to_a_shieldman() -> void:
	var e_hitter := TestHelpers.grunt(E, "e_hitter", 12, 6, 5, 3, Weapon.sword())
	var shieldman := TestHelpers.grunt(P, "shieldman")
	shieldman.is_shieldman = true
	var eng := TestHelpers.engine_for({"player_field": [shieldman], "enemy_field": [e_hitter]})
	eng.state.shield_wall_active = true
	await eng._attack(e_hitter, shieldman)
	assert_eq(shieldman.hp, 12 - 5, "7 softens to 5 behind the wall; nothing halves after")


func test_shieldman_flag_grants_no_passive_protection() -> void:
	var archer := TestHelpers.grunt(P, "archer", 10, 5, 2, 3, Weapon.bow())
	var shieldman := TestHelpers.grunt(E, "shieldman")
	shieldman.is_shieldman = true
	var eng := TestHelpers.engine_for({"player_field": [archer], "enemy_field": [shieldman]})
	TestHelpers.station(eng.state.player_formation, archer, B, 0)
	await eng._fight_phase(P)
	assert_eq(shieldman.hp, 12 - 2, "the flat 2 arrow lands whole on an unraised guard")


func test_the_old_armor_aura_is_gone() -> void:
	var hitter := TestHelpers.grunt(P, "hitter")
	var shieldman := TestHelpers.grunt(E, "shieldman")
	shieldman.is_shieldman = true
	var neighbor := TestHelpers.grunt(E, "neighbor")
	var eng := TestHelpers.engine_for({
		"player_field": [hitter],
		"enemy_field": [neighbor, shieldman],
	})
	await eng._attack(hitter, neighbor)
	assert_eq(neighbor.hp, 12 - 3,
			"full 3 Str: standing beside a shieldman is worth nothing between his guard beats")


# --- Berserker: the cleave ----------------------------------------------------

func test_berserker_cleave_grazes_the_targets_line_neighbors() -> void:
	var berserk := TestHelpers.grunt(P, "berserk", 10, 1, 5, 4, Weapon.axe())
	berserk.is_berserker = true
	var mark := TestHelpers.grunt(E, "mark", 30)
	var left := TestHelpers.grunt(E, "left")
	var right := TestHelpers.grunt(E, "right")
	var back := TestHelpers.grunt(E, "back")
	var eng := TestHelpers.engine_for({
		"player_field": [berserk],
		"enemy_field": [left, mark, right, back],
	})
	TestHelpers.station(eng.state.player_formation, berserk, F, 1)
	TestHelpers.station(eng.state.enemy_formation, back, B, 1)
	await eng._attack(berserk, mark)
	assert_eq(mark.hp, 30 - 6, "the main blow: 5 Str + 1 axe")
	assert_eq(left.hp, 12 - 2, "the cleave grazes the left neighbor for 2")
	assert_eq(right.hp, 12 - 2, "and the right neighbor")
	assert_eq(back.hp, 12, "the man behind the mark is out of the arc")


func test_plain_fighters_do_not_cleave() -> void:
	var hitter := TestHelpers.grunt(P, "hitter", 12, 6, 5, 3, Weapon.axe())
	var mark := TestHelpers.grunt(E, "mark", 30)
	var right := TestHelpers.grunt(E, "right")
	var eng := TestHelpers.engine_for({
		"player_field": [hitter],
		"enemy_field": [mark, right],
	})
	await eng._attack(hitter, mark)
	assert_eq(right.hp, 12, "only berserkers swing wide")


func test_cleave_graze_dies_on_a_raised_guard() -> void:
	var berserk := TestHelpers.grunt(P, "berserk", 10, 1, 5, 4, Weapon.axe())
	berserk.is_berserker = true
	var mark := TestHelpers.grunt(E, "mark", 30)
	var guarded := TestHelpers.grunt(E, "guarded", 12, 6, 3, 3, null, 3)
	var bare := TestHelpers.grunt(E, "bare")
	var eng := TestHelpers.engine_for({
		"player_field": [berserk],
		"enemy_field": [guarded, mark, bare],
	})
	TestHelpers.station(eng.state.player_formation, berserk, F, 1)
	await eng._attack(berserk, mark)
	# The berserker swings an axe, so the graze chews double: guard 3 pays for
	# both points of the graze and the guarded man keeps his skin.
	assert_eq(guarded.hp, 12, "3 guard swallows the 2-point graze")
	assert_eq(guarded.block, 0, "at the axe's double rate, 3 block dies to it")
	assert_eq(bare.hp, 12 - 2, "his bare neighbor takes it whole")


func test_cleave_kills_pay_the_normal_bounty() -> void:
	var berserk := TestHelpers.grunt(P, "berserk", 10, 1, 5, 4, Weapon.axe())
	berserk.is_berserker = true
	var mark := TestHelpers.grunt(E, "mark", 30)
	var dying := TestHelpers.grunt(E, "dying", 2)
	var eng := TestHelpers.engine_for({
		"player_field": [berserk],
		"enemy_field": [mark, dying],
	})
	await eng._attack(berserk, mark)
	assert_true(eng.state.enemy_dead.has(dying), "the graze finishes the wounded neighbor")
	assert_eq(eng.state.momentum, BattleState.KILL_MOMENTUM, "a kill is a kill: +2")


func test_cleave_neighbors_are_captured_before_the_blow_lands() -> void:
	var berserk := TestHelpers.grunt(P, "berserk", 10, 1, 5, 4, Weapon.axe())
	berserk.is_berserker = true
	var mark := TestHelpers.grunt(E, "mark", 3)
	var right := TestHelpers.grunt(E, "right", 12, 9)
	var eng := TestHelpers.engine_for({
		"player_field": [berserk],
		"enemy_field": [mark, right],
	})
	await eng._attack(berserk, mark)
	assert_true(eng.state.enemy_dead.has(mark), "the main blow kills the mark")
	assert_eq(right.hp, 12 - 2, "his neighbor is grazed even though the mark's slot emptied")


func test_cleave_graze_is_softened_by_the_shield_wall() -> void:
	var berserk := TestHelpers.grunt(E, "berserk", 10, 1, 5, 4, Weapon.axe())
	berserk.is_berserker = true
	var mark := TestHelpers.grunt(P, "mark", 30)
	var right := TestHelpers.grunt(P, "right")
	var eng := TestHelpers.engine_for({
		"player_field": [mark, right],
		"enemy_field": [berserk],
	})
	eng.state.shield_wall_active = true
	await eng._attack(berserk, mark)
	assert_eq(right.hp, 12 - 1, "the wall softens the graze to the minimum 1")


# --- Captain: the leader aura -------------------------------------------------

func test_captain_aura_adds_melee_damage_to_line_neighbors() -> void:
	var captain := TestHelpers.captain_of(P, "captain")
	var fighter := TestHelpers.grunt(P, "fighter")
	var mark := TestHelpers.grunt(E, "mark", 30)
	var eng := TestHelpers.engine_for({
		"player_field": [captain, fighter],
		"enemy_field": [mark],
	})
	TestHelpers.station(eng.state.enemy_formation, mark, F, 1)
	await eng._attack(fighter, mark)
	assert_eq(mark.hp, 30 - 4, "3 Str + 1 for fighting at the captain's shoulder")


func test_captain_aura_skips_himself_and_the_men_beyond_reach() -> void:
	var captain := TestHelpers.captain_of(P, "captain")
	var far_man := TestHelpers.grunt(P, "far_man")
	var mark := TestHelpers.grunt(E, "mark", 30)
	var eng := TestHelpers.engine_for({
		"player_field": [captain, far_man],
		"enemy_field": [mark],
	})
	TestHelpers.station(eng.state.player_formation, far_man, F, 3)
	TestHelpers.station(eng.state.enemy_formation, mark, F, 3)
	await eng._attack(far_man, mark)
	assert_eq(mark.hp, 30 - 3, "two columns from the captain: no aura")
	await eng._attack(captain, mark)
	assert_eq(mark.hp, 30 - 3 - 6, "4 Str + 2 sword: the captain inspires others, not himself")


func test_captain_aura_does_not_boost_snipes() -> void:
	var captain := TestHelpers.captain_of(P, "captain")
	var archer := TestHelpers.grunt(P, "archer", 10, 5, 2, 3, Weapon.bow())
	var mark := TestHelpers.grunt(E, "mark")
	var eng := TestHelpers.engine_for({
		"player_field": [captain, archer],
		"enemy_field": [mark],
	})
	TestHelpers.station(eng.state.player_formation, captain, B, 0)
	TestHelpers.station(eng.state.player_formation, archer, B, 1)
	await eng._fight_phase(P)
	assert_eq(mark.hp, 12 - 2, "the arrow stays flat 2 even at the captain's shoulder")


# --- Covering Volley: scales with the archers actually on your ship -----------

func test_covering_volley_fires_one_arrow_per_ship_archer() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var bow1 := TestHelpers.grunt(P, "bow1", 10, 5, 2, 3, Weapon.bow())
	var bow2 := TestHelpers.grunt(P, "bow2", 10, 5, 2, 3, Weapon.bow())
	var sword := TestHelpers.grunt(P, "sword", 12, 6, 3, 3, Weapon.sword())
	var e1 := TestHelpers.grunt(E, "e1", 30)
	var eng := TestHelpers.engine_for({
		"player_field": [p1],
		"player_reserve": [bow1, bow2, sword],
		"enemy_field": [e1],
	})
	eng.state.archer_support_damage = 2
	await eng._archer_support_volley()
	assert_eq(e1.hp, 30 - 4, "two bows on the rail: two arrows of 2")


func test_covering_volley_is_silent_with_no_ship_archers() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var sword := TestHelpers.grunt(P, "sword", 12, 6, 3, 3, Weapon.sword())
	var e1 := TestHelpers.grunt(E, "e1", 30)
	var eng := TestHelpers.engine_for({
		"player_field": [p1],
		"player_reserve": [sword],
		"enemy_field": [e1],
	})
	eng.state.archer_support_damage = 2
	await eng._archer_support_volley()
	assert_eq(e1.hp, 30, "no bows in reserve: the rail is silent")
	assert_false(_log_has(eng, "rail"), "and says nothing")


func test_covering_volley_reaims_at_the_weakest_between_arrows() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var bow1 := TestHelpers.grunt(P, "bow1", 10, 5, 2, 3, Weapon.bow())
	var bow2 := TestHelpers.grunt(P, "bow2", 10, 5, 2, 3, Weapon.bow())
	var e1 := TestHelpers.grunt(E, "e1", 30)
	var e2 := TestHelpers.grunt(E, "e2", 2)
	var eng := TestHelpers.engine_for({
		"player_field": [p1],
		"player_reserve": [bow1, bow2],
		"enemy_field": [e1, e2],
	})
	eng.state.archer_support_damage = 2
	await eng._archer_support_volley()
	assert_true(eng.state.enemy_dead.has(e2), "the first arrow finishes the weakest")
	assert_eq(e1.hp, 30 - 2, "the second re-aims at the man now weakest")


func test_a_fielded_archer_does_not_feed_the_volley() -> void:
	var archer := TestHelpers.grunt(P, "archer", 10, 5, 2, 3, Weapon.bow())
	var e1 := TestHelpers.grunt(E, "e1", 30)
	var eng := TestHelpers.engine_for({
		"player_field": [archer],
		"enemy_field": [e1],
	})
	eng.state.archer_support_damage = 2
	await eng._archer_support_volley()
	assert_eq(e1.hp, 30, "she is on their deck now, not your rail")
