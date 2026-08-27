extends TestCase
## Role kits (docs/lines-redesign.md phase B): hooks riding boolean flags and
## weapon kinds. Shieldman halving + aura, berserker cleave, the axe as the
## aura-breaker, the captain's leader aura, and covering-volley scaling.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY
const F := Formation.FRONT
const B := Formation.BACK


func _log_has(eng: CombatEngine, needle: String) -> bool:
	for line in eng.state.battle_log:
		if line.contains(needle):
			return true
	return false


# --- Shieldman: takes half, shields his neighbors ----------------------------

func test_shieldman_takes_half_melee_damage_rounded_up() -> void:
	var hitter := TestHelpers.grunt(P, "hitter", 12, 6, 5, 3, Weapon.sword())
	var shieldman := TestHelpers.grunt(E, "shieldman")
	shieldman.is_shieldman = true
	var eng := TestHelpers.engine_for({"player_field": [hitter], "enemy_field": [shieldman]})
	await eng._attack(hitter, shieldman)
	assert_eq(shieldman.hp, 12 - 4, "7 raw (5 Str + 2 sword) halves to 4, rounded up")


func test_shieldman_halving_lands_after_side_wide_softening() -> void:
	var e_hitter := TestHelpers.grunt(E, "e_hitter", 12, 6, 5, 3, Weapon.sword())
	var shieldman := TestHelpers.grunt(P, "shieldman")
	shieldman.is_shieldman = true
	var eng := TestHelpers.engine_for({"player_field": [shieldman], "enemy_field": [e_hitter]})
	eng.state.shield_wall_active = true
	await eng._attack(e_hitter, shieldman)
	assert_eq(shieldman.hp, 12 - 3, "7 softens to 5 behind the wall, THEN halves to 3")


func test_shieldman_halves_snipes_too() -> void:
	var archer := TestHelpers.grunt(P, "archer", 10, 5, 2, 3, Weapon.bow())
	var shieldman := TestHelpers.grunt(E, "shieldman")
	shieldman.is_shieldman = true
	var eng := TestHelpers.engine_for({"player_field": [archer], "enemy_field": [shieldman]})
	TestHelpers.station(eng.state.player_formation, archer, B, 0)
	await eng._fight_phase(P)
	assert_eq(shieldman.hp, 12 - 1, "the flat 2 arrow halves to 1 on the shield")


func test_shieldman_does_not_halve_true_damage() -> void:
	var shieldman := TestHelpers.grunt(E, "shieldman")
	shieldman.is_shieldman = true
	var eng := TestHelpers.engine_for({"enemy_field": [shieldman]})
	await eng._deal_true_damage(shieldman, 3)
	assert_eq(shieldman.hp, 12 - 3, "volleys are the shieldman counter-play: full 3")


func test_shieldman_aura_armors_line_neighbors() -> void:
	var hitter := TestHelpers.grunt(P, "hitter")
	var shieldman := TestHelpers.grunt(E, "shieldman")
	shieldman.is_shieldman = true
	var neighbor := TestHelpers.grunt(E, "neighbor")
	var eng := TestHelpers.engine_for({
		"player_field": [hitter],
		"enemy_field": [neighbor, shieldman],
	})
	await eng._attack(hitter, neighbor)
	assert_eq(neighbor.hp, 12 - 2, "3 Str against 0 armor + 1 aura from the man beside him")


func test_shieldman_aura_never_covers_himself() -> void:
	var hitter := TestHelpers.grunt(P, "hitter", 12, 6, 5, 3)
	var shieldman := TestHelpers.grunt(E, "shieldman")
	shieldman.is_shieldman = true
	var eng := TestHelpers.engine_for({"player_field": [hitter], "enemy_field": [shieldman]})
	await eng._attack(hitter, shieldman)
	assert_eq(shieldman.hp, 12 - 3, "5 raw halves to 3 — no self-aura shaving it to 2")


func test_shieldman_auras_do_not_stack() -> void:
	var hitter := TestHelpers.grunt(P, "hitter", 12, 6, 4, 3)
	var left_wall := TestHelpers.grunt(E, "left_wall")
	left_wall.is_shieldman = true
	var right_wall := TestHelpers.grunt(E, "right_wall")
	right_wall.is_shieldman = true
	var flanked := TestHelpers.grunt(E, "flanked")
	var eng := TestHelpers.engine_for({
		"player_field": [hitter],
		"enemy_field": [left_wall, flanked, right_wall],
	})
	TestHelpers.station(eng.state.player_formation, hitter, F, 1)
	await eng._attack(hitter, flanked)
	assert_eq(flanked.hp, 12 - 3, "flanked by two shieldmen is still just +1 armor")


func test_shieldman_aura_does_not_reach_across_lines() -> void:
	var hitter := TestHelpers.grunt(P, "hitter")
	var shieldman := TestHelpers.grunt(E, "shieldman")
	shieldman.is_shieldman = true
	var front_man := TestHelpers.grunt(E, "front_man")
	var eng := TestHelpers.engine_for({
		"player_field": [hitter],
		"enemy_field": [front_man, shieldman],
	})
	TestHelpers.station(eng.state.enemy_formation, shieldman, B, 0)
	await eng._attack(hitter, front_man)
	assert_eq(front_man.hp, 12 - 3, "the man directly behind is not a line-neighbor")


func test_axe_denies_aura_armor() -> void:
	var breaker := TestHelpers.grunt(P, "breaker", 12, 6, 3, 3, Weapon.axe())
	var shieldman := TestHelpers.grunt(E, "shieldman")
	shieldman.is_shieldman = true
	var neighbor := TestHelpers.grunt(E, "neighbor")
	var eng := TestHelpers.engine_for({
		"player_field": [breaker],
		"enemy_field": [neighbor, shieldman],
	})
	await eng._attack(breaker, neighbor)
	assert_eq(neighbor.hp, 12 - 4, "3 Str + 1 axe, the aura counts for nothing against it")


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


func test_cleave_graze_ignores_armor_but_shields_halve_it() -> void:
	var berserk := TestHelpers.grunt(P, "berserk", 10, 1, 5, 4, Weapon.axe())
	berserk.is_berserker = true
	var mark := TestHelpers.grunt(E, "mark", 30)
	var armored := TestHelpers.grunt(E, "armored", 12, 6, 3, 3, null, 3)
	var shieldman := TestHelpers.grunt(E, "shieldman")
	shieldman.is_shieldman = true
	var eng := TestHelpers.engine_for({
		"player_field": [berserk],
		"enemy_field": [armored, mark, shieldman],
	})
	TestHelpers.station(eng.state.player_formation, berserk, F, 1)
	await eng._attack(berserk, mark)
	assert_eq(armored.hp, 12 - 2, "the graze is never armored: full 2 through 3 armor")
	assert_eq(shieldman.hp, 12 - 1, "but the shieldman still halves it")


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
