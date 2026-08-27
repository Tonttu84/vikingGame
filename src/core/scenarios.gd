class_name Scenarios
extends RefCounted
## Battle setups. The default skirmish is the v0 tuning baseline from
## docs/combat-design.md; the sim harness and tests both build from here.
## Shape: a 3-man first wave boards a surprised but larger deck watch; the
## rest of both crews feed in over the fight, their captain last.
##
## Phase B gives the sides distinct silhouettes. The raiders are breakers:
## axes and reach, a shieldman to anchor the push, an archer who feeds the
## rail volley until she is fielded. The defenders are a wall: two shieldmen
## in the watch, a bowman behind them, karl rout-fodder in the hold and the
## berserker waiting among them.


static func default_skirmish() -> Dictionary:
	var P := Character.Side.PLAYER
	var E := Character.Side.ENEMY

	var captain := Character.new("p_captain", "Captain Aslak", P, 20, 10, 4, 4, Weapon.sword(), 2)
	captain.is_captain = true

	# The prowman leads the default first wave; the captain waits on your own
	# ship (safe until sent across). First in reserve crosses first by default.
	var shieldman := Character.new("p_shield1", "Shield-bearer Ulf", P, 14, 7, 2, 2, Weapon.sword(), 2)
	shieldman.is_shieldman = true
	var player_field: Array[Character] = [
		Character.new("p_prow", "Prowman Sten", P, 14, 8, 4, 3, Weapon.axe(), 1),
		shieldman,
		Character.new("p_spear1", "Spearman Orm", P, 12, 6, 3, 3, Weapon.spear(), 1),
	]
	var player_reserve: Array[Character] = [
		Character.new("p_axe1", "Axeman Grim", P, 12, 6, 3, 3, Weapon.axe(), 1),
		Character.new("p_sword1", "Swordsman Kari", P, 12, 6, 3, 3, Weapon.sword(), 0),
		captain,
		Character.new("p_bow1", "Archer Sigrid", P, 10, 5, 2, 3, Weapon.bow(), 0),
		Character.new("p_young1", "Young Halfdan", P, 10, 4, 3, 3, Weapon.sword(), 0),
	]

	var enemy_captain := Character.new("e_captain", "Jarl Sigvard", E, 30, 10, 5, 3, Weapon.sword(), 2)
	enemy_captain.is_captain = true

	# The watch auto-places front left to right, then the second line: the
	# shieldmen anchor f1/f2, the bowman lands b1 behind them and snipes.
	var wall1 := Character.new("e_shield1", "Housecarl Bran", E, 14, 7, 2, 3, Weapon.sword(), 2)
	wall1.is_shieldman = true
	var wall2 := Character.new("e_shield2", "Housecarl Eyvind", E, 14, 7, 2, 2, Weapon.sword(), 2)
	wall2.is_shieldman = true
	var enemy_field: Array[Character] = [
		wall1,
		wall2,
		Character.new("e_grunt1", "Housecarl Snorri", E, 12, 7, 3, 3, Weapon.spear(), 1),
		Character.new("e_grunt2", "Housecarl Vagn", E, 12, 7, 3, 2, Weapon.axe(), 1),
		Character.new("e_bow1", "Bowman Kalf", E, 10, 6, 2, 3, Weapon.bow(), 0),
	]
	var berserker := Character.new("e_berserk", "Berserker Glum", E, 10, 1, 5, 4, Weapon.axe(), 0)
	berserker.is_berserker = true
	var enemy_reserve: Array[Character] = [
		Character.new("e_karl1", "Karl Hauk", E, 10, 4, 3, 3, Weapon.spear(), 0),
		Character.new("e_karl2", "Karl Geir", E, 10, 4, 3, 3, Weapon.sword(), 0),
		Character.new("e_karl3", "Karl Bodvar", E, 10, 4, 3, 3, Weapon.axe(), 0),
		Character.new("e_karl4", "Karl Steinn", E, 10, 4, 3, 3, Weapon.spear(), 0),
		berserker,
		Character.new("e_old1", "Old Ketil", E, 10, 5, 2, 2, Weapon.sword(), 1),
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
