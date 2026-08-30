extends TestCase
## Turn-scoped block replaces armor (docs/block-and-patterns.md): guard is
## raised at battle start and at each side's own turn start, physical damage
## chews it before flesh, true damage goes around it, axes chew it at double
## rate and swing first so the chewing lands while there is block to chew.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY


# --- Guard: where block comes from --------------------------------------------

func test_battle_opens_with_every_guard_up() -> void:
	var pc := TestHelpers.grunt(P, "pc", 12, 6, 3, 3, null, 2)
	var ec := TestHelpers.grunt(E, "ec", 12, 6, 3, 3, null, 3)
	var eng := TestHelpers.engine_for({"player_field": [pc], "enemy_field": [ec]})
	assert_eq(pc.block, 2, "armor is the guard a man starts with")
	assert_eq(ec.block, 3, "both sides board with shields already up")
	assert_true(eng != null, "")


func test_guard_resets_to_armor_at_own_turn_start() -> void:
	var pc := TestHelpers.grunt(P, "pc", 12, 6, 3, 3, null, 2)
	var ec := TestHelpers.grunt(E, "ec", 12, 6, 3, 3, null, 3)
	var eng := TestHelpers.engine_for({"player_field": [pc], "enemy_field": [ec]})
	pc.block = 0
	ec.block = 9
	eng._raise_guard(P)
	assert_eq(pc.block, 2, "a spent guard comes back up at his side's turn")
	assert_eq(ec.block, 9, "the other side's guard is untouched")
	eng._raise_guard(E)
	assert_eq(ec.block, 3, "leftover block does not bank — it resets to armor")


func test_reserve_men_keep_their_guard_out_of_the_refresh() -> void:
	var pc := TestHelpers.grunt(P, "pc")
	var waiting := TestHelpers.grunt(P, "waiting", 12, 6, 3, 3, null, 2)
	var ec := TestHelpers.grunt(E, "ec")
	var eng := TestHelpers.engine_for(
			{"player_field": [pc], "player_reserve": [waiting], "enemy_field": [ec]})
	waiting.block = 0
	eng._raise_guard(P)
	assert_eq(waiting.block, 0, "only fielded men raise the guard — nobody swings at the reserve")


# --- The sheet: armor no longer subtracts from damage --------------------------

func test_armor_does_not_reduce_damage_any_more() -> void:
	var a := TestHelpers.grunt(P, "a", 12, 6, 3, 3, Weapon.sword(), 0)
	var d := TestHelpers.grunt(E, "d", 12, 6, 3, 3, null, 3)
	assert_eq(a.damage_against(d), 5, "3 Str + 2 sword; the 3 armor is guard now, not reduction")


func test_axe_lost_its_armor_piercing() -> void:
	var a := TestHelpers.grunt(P, "a", 12, 6, 3, 3, Weapon.axe(), 0)
	var d := TestHelpers.grunt(E, "d", 12, 6, 3, 3, null, 3)
	assert_eq(a.damage_against(d), 4, "3 Str + 1 axe, plain — the axe's trait moved to block-chewing")


# --- Block absorbs physical damage ---------------------------------------------

func test_block_chews_a_melee_hit_before_flesh() -> void:
	var a := TestHelpers.grunt(P, "a", 12, 6, 3, 3, Weapon.sword(), 0)
	var d := TestHelpers.grunt(E, "d")
	var eng := TestHelpers.engine_for({"player_field": [a], "enemy_field": [d]})
	d.block = 3
	await eng._attack(a, d)
	assert_eq(d.block, 0, "the 5-point blow eats all 3 block")
	assert_eq(d.hp, 12 - 2, "only the remainder wounds")


func test_a_fully_blocked_hit_draws_no_blood() -> void:
	var a := TestHelpers.grunt(P, "a", 12, 6, 1, 3, null, 0)
	var d := TestHelpers.grunt(E, "d")
	var eng := TestHelpers.engine_for({"player_field": [a], "enemy_field": [d]})
	d.block = 4
	await eng._attack(a, d)
	assert_eq(d.hp, 12, "zero is a legal result now — min 1 lives on the raw damage, before block")
	assert_eq(d.block, 3, "the fist's 1 point came off the guard")


func test_snipes_are_blocked_too() -> void:
	var archer := TestHelpers.grunt(P, "archer", 10, 5, 2, 3, Weapon.bow(), 0)
	var d := TestHelpers.grunt(E, "d")
	var eng := TestHelpers.engine_for({"player_field": [archer], "enemy_field": [d]})
	d.block = 2
	await eng._snipe(archer, d)
	assert_eq(d.hp, 12, "the flat 2 arrow dies on 2 block — blocking is the answer placement never was")
	assert_eq(d.block, 0, "")


func test_cleave_graze_is_blocked() -> void:
	var berserk := TestHelpers.grunt(P, "berserk", 10, 1, 5, 4, Weapon.sword(), 0)
	berserk.is_berserker = true
	var mark := TestHelpers.grunt(E, "mark")
	var neighbor := TestHelpers.grunt(E, "neighbor")
	var eng := TestHelpers.engine_for(
			{"player_field": [berserk], "enemy_field": [mark, neighbor]})
	neighbor.block = 1
	await eng._attack(berserk, mark)
	assert_eq(neighbor.hp, 12 - 1, "the flat 2 graze loses 1 to the guard")


func test_true_damage_goes_around_block() -> void:
	var pc := TestHelpers.grunt(P, "pc")
	var d := TestHelpers.grunt(E, "d")
	var eng := TestHelpers.engine_for({"player_field": [pc], "enemy_field": [d]})
	d.block = 5
	await eng._deal_true_damage(d, 3)
	assert_eq(d.hp, 12 - 3, "volleys ignore block exactly as they ignored armor")
	assert_eq(d.block, 5, "and leave the guard standing")


# --- The axe: chews block at double rate, swings first --------------------------

func test_axe_destroys_two_block_per_point() -> void:
	var a := TestHelpers.grunt(P, "a", 12, 6, 3, 3, Weapon.axe(), 0)
	var d := TestHelpers.grunt(E, "d")
	var eng := TestHelpers.engine_for({"player_field": [a], "enemy_field": [d]})
	d.block = 6
	await eng._attack(a, d)
	assert_eq(d.block, 0, "the axe's 4 points could chew 8 — all 6 block dies")
	assert_eq(d.hp, 12 - 1, "3 of its points paid for the block; the last one cuts")


func test_axe_against_odd_block_rounds_in_the_axes_favor() -> void:
	var a := TestHelpers.grunt(P, "a", 12, 6, 3, 3, Weapon.axe(), 0)
	var d := TestHelpers.grunt(E, "d")
	var eng := TestHelpers.engine_for({"player_field": [a], "enemy_field": [d]})
	d.block = 3
	await eng._attack(a, d)
	assert_eq(d.block, 0, "")
	assert_eq(d.hp, 12 - 2, "3 block costs the axe ceil(3/2)=2 points; 2 of 4 still cut")


func test_axe_with_no_block_to_chew_is_a_plain_weapon() -> void:
	var a := TestHelpers.grunt(P, "a", 12, 6, 3, 3, Weapon.axe(), 0)
	var d := TestHelpers.grunt(E, "d")
	var eng := TestHelpers.engine_for({"player_field": [a], "enemy_field": [d]})
	await eng._attack(a, d)
	assert_eq(d.hp, 12 - 4, "3 Str + 1 axe, nothing to chew")


func test_axes_swing_first_in_the_fight_order() -> void:
	var axeman := TestHelpers.grunt(P, "axeman", 12, 6, 3, 2, Weapon.axe(), 0)
	var swordsman := TestHelpers.grunt(P, "swordsman", 12, 6, 3, 4, Weapon.sword(), 0)
	var spearman := TestHelpers.grunt(P, "spearman", 12, 6, 3, 3, Weapon.spear(), 0)
	var ec := TestHelpers.grunt(E, "ec")
	var eng := TestHelpers.engine_for(
			{"player_field": [swordsman, spearman, axeman], "enemy_field": [ec]})
	var order := eng._attack_order(P)
	assert_eq(order[0], axeman, "the slow axeman still swings first — his job is the block")
	assert_eq(order[1], swordsman, "then the rest by speed")
	assert_eq(order[2], spearman, "")


func test_two_axes_order_by_speed_between_them() -> void:
	var slow_axe := TestHelpers.grunt(P, "slow_axe", 12, 6, 3, 2, Weapon.axe(), 0)
	var fast_axe := TestHelpers.grunt(P, "fast_axe", 12, 6, 3, 4, Weapon.axe(), 0)
	var ec := TestHelpers.grunt(E, "ec")
	var eng := TestHelpers.engine_for(
			{"player_field": [slow_axe, fast_axe], "enemy_field": [ec]})
	var order := eng._attack_order(P)
	assert_eq(order[0], fast_axe, "")
	assert_eq(order[1], slow_axe, "")


# --- The forecast bills blood, not steel-on-shield ------------------------------

func test_forecast_spends_defender_block() -> void:
	var a := TestHelpers.grunt(P, "a", 12, 6, 3, 3, Weapon.sword(), 0)
	var d := TestHelpers.grunt(E, "d")
	var eng := TestHelpers.engine_for({"player_field": [a], "enemy_field": [d]})
	d.block = 3
	var bill: Dictionary = eng.forecast()
	assert_eq(bill[d]["hp"], 2, "5 predicted, 3 dies on the guard, the bill shows 2 blood")


func test_forecast_chews_double_for_a_predicted_axe() -> void:
	var a := TestHelpers.grunt(P, "a", 12, 6, 3, 3, Weapon.axe(), 0)
	var d := TestHelpers.grunt(E, "d")
	var eng := TestHelpers.engine_for({"player_field": [a], "enemy_field": [d]})
	d.block = 6
	var bill: Dictionary = eng.forecast()
	assert_eq(bill[d]["hp"], 1, "the same math resolution uses: 6 block costs 3 points, 1 cuts")
