extends TestCase
## Deterministic damage math: Str + weapon, min 1, side-wide softening.
## Armor is guard now, spent as block — that math lives in test_block.gd.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY


func test_sword_damage() -> void:
	var a := TestHelpers.grunt(P, "a", 12, 6, 3, 3, Weapon.sword(), 0)
	var d := TestHelpers.grunt(E, "d")
	assert_eq(a.damage_against(d), 5, "3 Str + 2 sword - 0 armor")


func test_raw_damage_is_never_below_one() -> void:
	var a := TestHelpers.grunt(P, "a", 12, 6, 1, 3, null, 0)
	var d := TestHelpers.grunt(E, "d", 12, 6, 3, 3, null, 5)
	assert_eq(a.damage_against(d, -4), 1,
			"whatever debuffs subtract, a swing that lands is worth at least 1 — before block")


func test_defender_sheet_no_longer_enters_the_math() -> void:
	var a := TestHelpers.grunt(P, "a", 12, 6, 3, 3, Weapon.axe(), 0)
	var d := TestHelpers.grunt(E, "d", 12, 6, 3, 3, null, 3)
	assert_eq(a.damage_against(d), 4, "3 Str + 1 axe; the 3 armor is his guard, spent as block")


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
