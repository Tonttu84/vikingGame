extends TestCase
## Classes (owner's ruling 2026-09-06): every man on both sides has a role,
## derived from the same flags and weapon kind the kits already ride — no
## second source of truth. The uniques (captain, prowman, the enemy captain)
## keep their own names; everyone else is titled by his role and a first
## name, "Spearman Olaf", and the table shows the role on every token.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY


func test_the_role_follows_the_kit_flags_first() -> void:
	var captain := TestHelpers.captain_of(P, "cap")
	assert_eq(captain.role_label(), "Captain", "")
	var prow := TestHelpers.grunt(P, "prow", 14, 8, 4, 3, Weapon.axe())
	prow.is_prowman = true
	assert_eq(prow.role_label(), "Prowman", "the prowman is a role, whatever he carries")
	var berserk := TestHelpers.grunt(E, "berserk", 10, 1, 5, 4, Weapon.axe())
	berserk.is_berserker = true
	assert_eq(berserk.role_label(), "Berserker", "")
	var wall := TestHelpers.grunt(E, "wall", 14, 7, 2, 3, Weapon.sword())
	wall.is_shieldman = true
	assert_eq(wall.role_label(), "Shieldman", "the shield names him, not the sword in his other hand")


func test_the_role_follows_the_weapon_for_everyone_else() -> void:
	assert_eq(TestHelpers.grunt(P, "a", 12, 6, 3, 3, Weapon.spear()).role_label(), "Spearman", "")
	assert_eq(TestHelpers.grunt(P, "b", 12, 6, 3, 3, Weapon.axe()).role_label(), "Axeman", "")
	assert_eq(TestHelpers.grunt(P, "c", 12, 6, 3, 3, Weapon.sword()).role_label(), "Swordsman", "")
	assert_eq(TestHelpers.grunt(E, "d", 12, 6, 3, 3, Weapon.bow()).role_label(), "Archer", "")
	assert_eq(TestHelpers.grunt(E, "e").role_label(), "Karl", "bare hands: a karl, the rout-fodder of the hold")


func test_the_enemy_captain_is_a_captain_by_role() -> void:
	var jarl := TestHelpers.captain_of(E, "Jarl Sigvard")
	assert_eq(jarl.role_label(), "Captain", "his name carries the jarldom; his class is the captaincy")


func test_title_by_role_names_a_man_by_class_and_first_name() -> void:
	var olaf := TestHelpers.grunt(P, "p1", 12, 6, 3, 3, Weapon.spear())
	olaf.given_name = "Olaf"
	olaf.title_by_role()
	assert_eq(olaf.display_name, "Spearman Olaf", "the convention the owner asked for")
	assert_eq(olaf.short_name(), "Olaf", "and the table can show just the first name under the class")
	assert_true(olaf.is_titled_by_role(), "")


func test_the_constructor_name_is_the_given_name_until_titled() -> void:
	var c := TestHelpers.grunt(P, "p1", 12, 6, 3, 3, Weapon.sword())
	assert_eq(c.given_name, "p1", "the name he was built with")
	assert_eq(c.display_name, "p1", "untitled, the two are the same")
	assert_false(c.is_titled_by_role(), "")
	assert_eq(c.short_name(), "p1", "a man not titled by role shows his whole name")


func test_uniques_keep_their_own_names() -> void:
	var sten := Character.new("p_prow", "Prowman Sten", P, 14, 8, 4, 3, Weapon.axe(), 1)
	sten.is_prowman = true
	assert_eq(sten.display_name, "Prowman Sten", "")
	assert_eq(sten.short_name(), "Prowman Sten", "nobody rebuilt his name from a class")
	var jarl := Character.new("e_captain", "Jarl Eirik Iron-Hand", E, 36, 11, 6, 3, Weapon.sword(), 3)
	jarl.is_captain = true
	assert_eq(jarl.short_name(), "Jarl Eirik Iron-Hand", "the jarl's name is his own")
