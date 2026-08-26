class_name Scenarios
extends RefCounted
## Battle setups. The default skirmish is the v0 tuning baseline from
## docs/combat-design.md; the sim harness and tests both build from here.
## Shape: a 3-man first wave boards a surprised but larger deck watch; the
## rest of both crews feed in over the fight, their captain last.


static func default_skirmish() -> Dictionary:
	var P := Character.Side.PLAYER
	var E := Character.Side.ENEMY

	var captain := Character.new("p_captain", "Captain Aslak", P, 20, 10, 4, 4, Weapon.sword(), 2)
	captain.is_captain = true

	# The prowman leads the default first wave; the captain waits on your own
	# ship (safe until sent across). First in reserve crosses first by default.
	var player_field: Array[Character] = [
		Character.new("p_prow", "Prowman Sten", P, 14, 8, 4, 3, Weapon.axe(), 1),
		Character.new("p_spear1", "Spearman Orm", P, 12, 6, 3, 3, Weapon.spear(), 1),
		Character.new("p_axe1", "Axeman Grim", P, 12, 6, 3, 3, Weapon.axe(), 1),
	]
	var player_reserve: Array[Character] = [
		Character.new("p_sword1", "Swordsman Kari", P, 12, 6, 3, 3, Weapon.sword(), 0),
		Character.new("p_shield1", "Shield-bearer Ulf", P, 14, 7, 2, 2, Weapon.sword(), 2),
		captain,
		Character.new("p_bow1", "Archer Sigrid", P, 10, 5, 2, 3, Weapon.bow(), 0),
		Character.new("p_young1", "Young Halfdan", P, 10, 5, 3, 3, Weapon.sword(), 0),
	]

	var enemy_captain := Character.new("e_captain", "Jarl Sigvard", E, 30, 10, 5, 3, Weapon.sword(), 2)
	enemy_captain.is_captain = true

	var enemy_field: Array[Character] = [
		Character.new("e_grunt1", "Housecarl Bran", E, 12, 7, 3, 3, Weapon.axe(), 1),
		Character.new("e_grunt2", "Housecarl Eyvind", E, 12, 7, 3, 3, Weapon.spear(), 1),
		Character.new("e_grunt3", "Housecarl Snorri", E, 12, 7, 3, 3, Weapon.sword(), 0),
		Character.new("e_grunt4", "Housecarl Vagn", E, 12, 7, 3, 2, Weapon.axe(), 1),
		Character.new("e_grunt5", "Housecarl Ref", E, 12, 7, 3, 3, Weapon.spear(), 0),
	]
	var berserker := Character.new("e_berserk", "Berserker Glum", E, 10, 1, 5, 4, Weapon.axe(), 0)
	berserker.is_berserker = true
	var enemy_reserve: Array[Character] = [
		Character.new("e_res1", "Karl Hauk", E, 12, 7, 3, 3, Weapon.spear(), 0),
		Character.new("e_res2", "Karl Geir", E, 12, 7, 3, 3, Weapon.sword(), 0),
		Character.new("e_res3", "Karl Bodvar", E, 12, 7, 3, 3, Weapon.axe(), 0),
		Character.new("e_res5", "Karl Steinn", E, 12, 7, 3, 3, Weapon.spear(), 0),
		berserker,
		Character.new("e_res4", "Old Ketil", E, 10, 5, 2, 2, Weapon.sword(), 1),
	]

	return {
		"player_field": player_field,
		"player_reserve": player_reserve,
		"enemy_field": enemy_field,
		"enemy_reserve": enemy_reserve,
		"enemy_captain": enemy_captain,
		"deck": CardLibrary.starter_deck(),
		"maneuvers": CardLibrary.default_maneuvers(),
		"enemy_tactics": ["press_the_attack", "arrow_volley", "fear_horn", "reinforcement_surge"],
	}
