extends TestCase
## Deterministic damage math: Str + weapon - armor, min 1, weapon traits.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY


func test_sword_damage() -> void:
	var a := TestHelpers.grunt(P, "a", 12, 6, 3, 3, Weapon.sword(), 0)
	var d := TestHelpers.grunt(E, "d")
	assert_eq(a.damage_against(d), 5, "3 Str + 2 sword - 0 armor")


func test_minimum_damage_is_one() -> void:
	var a := TestHelpers.grunt(P, "a", 12, 6, 1, 3, null, 0)
	var d := TestHelpers.grunt(E, "d", 12, 6, 3, 3, null, 5)
	assert_eq(a.damage_against(d), 1, "armor can never zero out a hit")


func test_axe_ignores_two_armor() -> void:
	var a := TestHelpers.grunt(P, "a", 12, 6, 3, 3, Weapon.axe(), 0)
	var d := TestHelpers.grunt(E, "d", 12, 6, 3, 3, null, 3)
	assert_eq(a.damage_against(d), 3, "3 Str + 1 axe - (3-2) armor")


func test_spear_damage_is_plain() -> void:
	var a := TestHelpers.grunt(P, "a", 12, 6, 3, 3, Weapon.spear(), 0)
	var d := TestHelpers.grunt(E, "d")
	assert_eq(a.damage_against(d), 4,
			"3 Str + 1 spear; the spear's identity is reach, not a first-strike bonus")


func test_shield_wall_reduces_melee_hits() -> void:
	var pc := TestHelpers.grunt(P, "pc")
	var ec := TestHelpers.grunt(E, "ec", 12, 6, 3, 3, Weapon.sword(), 0)
	var eng := TestHelpers.engine_for({"player_field": [pc], "enemy_field": [ec]})
	eng.state.shield_wall_active = true
	await eng._attack(ec, pc)
	assert_eq(pc.hp, 12 - 3, "5 damage reduced by 2 behind the wall")
