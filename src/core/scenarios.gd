class_name Scenarios
extends RefCounted
## Battle setups. The default skirmish is the v0 tuning baseline from
## docs/combat-design.md; the sim harness and tests both build from here.
## Shape: a 3-man first wave boards a surprised but larger deck watch; the
## rest of both crews feed in over the fight, their captain last.
##
## Two registered scenarios anchor balance at both ends of a raid:
## "skirmish" is day one — the starter deck and a green crew — and
## "veteran" is deep in the campaign: a bigger, better-armed crew with a
## fatter deck, boarding a jarl's warship. Crew losses are permanent once
## the raid loop lands, so tuning reads the two together: a scenario is
## not balanced by win rate alone but by what a win tends to cost.
##
## Phase B gives the sides distinct silhouettes. The raiders are breakers:
## axes and reach, a shieldman to anchor the push, an archer who feeds the
## rail volley until she is fielded. The defenders are a wall: two shieldmen
## in the watch, a bowman behind them, karl rout-fodder in the hold and the
## berserker waiting among them.


## A crewman named by the owner's convention (2026-09-06): his class and a
## first name forged by NameForge — "Spearman Olaf". The kit flag is set
## before the title is drawn, so a shieldman with a sword reads Shieldman.
## The uniques (captain, prowman, the enemy captain) are built by name and
## never come through here; the forge has their names reserved.
static func _man(id: String, given: String, side: Character.Side, hp: int, morale: int,
		strength: int, speed: int, weapon: Weapon, armor: int, kit := "") -> Character:
	var c := Character.new(id, given, side, hp, morale, strength, speed, weapon, armor)
	match kit:
		"shieldman":
			c.is_shieldman = true
		"berserker":
			c.is_berserker = true
	c.title_by_role()
	return c


static func scenario_ids() -> Array[String]:
	return ["skirmish", "veteran"]


static func by_id(p_id: String) -> Dictionary:
	match p_id:
		"skirmish": return default_skirmish()
		"veteran": return veteran_raid()
	return {}


## What the boot menu prints for each anchor: a title and one line saying
## what kind of fight it is. Empty for an id the registry does not know —
## the menu offers scenario_ids() and nothing else.
static func title(p_id: String) -> String:
	match p_id:
		"skirmish": return "The Skirmish"
		"veteran": return "The Veteran Raid"
	return ""


static func blurb(p_id: String) -> String:
	match p_id:
		"skirmish":
			return ("Day one. A green crew with the starter deck boards a surprised " +
					"but larger deck watch under Jarl Sigvard. The balance baseline.")
		"veteran":
			return ("A summer later. A bigger, blooded crew armored in plunder, with a " +
					"fatter deck and loot clogging it, hits Jarl Eirik Iron-Hand's warship. " +
					"Wins are graded by the butcher's bill.")
	return ""


## Fixed seeds: the anchors' crews are generated, but the same crew every
## time — sims, tests and the saga all speak of the same men.
const SKIRMISH_NAME_SEED := 793
const VETERAN_NAME_SEED := 1066


static func default_skirmish() -> Dictionary:
	var P := Character.Side.PLAYER
	var E := Character.Side.ENEMY
	var names := NameForge.new(SKIRMISH_NAME_SEED)
	for unique in ["Aslak", "Sten", "Sigvard"]:
		names.reserve(unique)

	var captain := Character.new("p_captain", "Captain Aslak", P, 20, 10, 4, 4, Weapon.sword(), 2)
	captain.is_captain = true

	# The prowman leads the default first wave; the captain waits on your own
	# ship (safe until sent across). First in reserve crosses first by default.
	var shieldman := _man("p_shield1", names.given(), P, 14, 7, 2, 2, Weapon.sword(), 4, "shieldman")
	var prowman := Character.new("p_prow", "Prowman Sten", P, 14, 8, 4, 3, Weapon.axe(), 1)
	prowman.is_prowman = true
	var player_field: Array[Character] = [
		prowman,
		shieldman,
		_man("p_spear1", names.given(), P, 12, 6, 3, 3, Weapon.spear(), 1),
	]
	var player_reserve: Array[Character] = [
		_man("p_axe1", names.given(), P, 12, 6, 3, 3, Weapon.axe(), 1),
		_man("p_sword1", names.given(), P, 12, 6, 3, 3, Weapon.sword(), 0),
		captain,
		_man("p_bow1", names.given_female(), P, 10, 5, 2, 3, Weapon.bow(), 0),
		_man("p_young1", names.given(), P, 10, 4, 3, 3, Weapon.sword(), 0),
	]

	var enemy_captain := Character.new("e_captain", "Jarl Sigvard", E, 30, 10, 5, 3, Weapon.sword(), 2)
	enemy_captain.is_captain = true

	# The watch auto-places front left to right, then the second line: the
	# shieldmen anchor f1/f2, the archer lands b1 behind them, covered.
	var wall1 := _man("e_shield1", names.given(), E, 14, 7, 2, 3, Weapon.sword(), 4, "shieldman")
	var wall2 := _man("e_shield2", names.given(), E, 14, 7, 2, 2, Weapon.sword(), 4, "shieldman")
	var enemy_field: Array[Character] = [
		wall1,
		wall2,
		_man("e_grunt1", names.given(), E, 12, 7, 3, 3, Weapon.spear(), 1),
		_man("e_grunt2", names.given(), E, 12, 7, 3, 2, Weapon.axe(), 1),
		_man("e_bow1", names.given(), E, 10, 6, 2, 3, Weapon.bow(), 0),
	]
	var berserker := _man("e_berserk", names.given(), E, 10, 1, 5, 4, Weapon.axe(), 0, "berserker")
	var enemy_reserve: Array[Character] = [
		_man("e_karl1", names.given(), E, 10, 4, 3, 3, Weapon.spear(), 0),
		_man("e_karl2", names.given(), E, 10, 4, 3, 3, Weapon.sword(), 0),
		_man("e_karl3", names.given(), E, 10, 4, 3, 3, Weapon.axe(), 0),
		_man("e_karl4", names.given(), E, 10, 4, 3, 3, Weapon.spear(), 0),
		berserker,
		_man("e_old1", names.given(), E, 10, 5, 2, 2, Weapon.sword(), 1),
	]

	return {
		"player_field": player_field,
		"player_reserve": player_reserve,
		"enemy_field": enemy_field,
		"enemy_reserve": enemy_reserve,
		"enemy_captain": enemy_captain,
		"captain_command": {"name": "Blood for blood", "effect": "blood_rage",
				"amount": 1, "period": 4},
		"deck": CardLibrary.starter_deck(),
		"maneuvers": CardLibrary.default_maneuvers(),
		"enemy_tactics": [
			"press_the_attack", "arrow_volley", "fear_horn", "reinforcement_surge",
			"fresh_men_forward", "shift_port", "shift_starboard", "step_up",
		],
	}


## Deep in the raid: the skirmish crew a summer later — blooded, armored in
## plunder, two men richer — against a jarl's levy warship. Same silhouettes
## on both sides (breakers vs a wall), everything a size up: the wall is
## thicker, the karls are deeper, and a berserker waits in the hold beside a
## second bowman. The balance question this scenario asks is not just "does
## the crew win?" but "how many of them are still standing when it does?".
static func veteran_raid() -> Dictionary:
	var P := Character.Side.PLAYER
	var E := Character.Side.ENEMY
	var names := NameForge.new(VETERAN_NAME_SEED)
	for unique in ["Aslak", "Sten", "Eirik"]:
		names.reserve(unique)

	var captain := Character.new("p_captain", "Captain Aslak", P, 22, 11, 5, 4, Weapon.sword(), 3)
	captain.is_captain = true

	var shieldman := _man("p_shield1", names.given(), P, 16, 8, 3, 2, Weapon.sword(), 5, "shieldman")
	var prowman := Character.new("p_prow", "Prowman Sten", P, 16, 9, 5, 3, Weapon.axe(), 2)
	prowman.is_prowman = true
	var player_field: Array[Character] = [
		prowman,
		shieldman,
		_man("p_spear1", names.given(), P, 14, 7, 4, 3, Weapon.spear(), 2),
	]
	var shieldman2 := _man("p_shield2", names.given_female(), P, 14, 7, 2, 2, Weapon.sword(), 5, "shieldman")
	var player_reserve: Array[Character] = [
		_man("p_axe1", names.given(), P, 14, 7, 4, 3, Weapon.axe(), 2),
		shieldman2,
		_man("p_sword1", names.given(), P, 14, 7, 4, 3, Weapon.sword(), 1),
		captain,
		_man("p_bow1", names.given_female(), P, 12, 6, 3, 3, Weapon.bow(), 1),
		_man("p_bow2", names.given_female(), P, 10, 5, 2, 3, Weapon.bow(), 0),
		_man("p_young1", names.given(), P, 12, 5, 3, 3, Weapon.sword(), 1),
	]

	var enemy_captain := Character.new("e_captain", "Jarl Eirik Iron-Hand", E, 36, 11, 6, 3, Weapon.sword(), 3)
	enemy_captain.is_captain = true

	var wall1 := _man("e_shield1", names.given(), E, 16, 8, 3, 3, Weapon.sword(), 5, "shieldman")
	var wall2 := _man("e_shield2", names.given(), E, 16, 8, 3, 2, Weapon.sword(), 5, "shieldman")
	var enemy_field: Array[Character] = [
		wall1,
		wall2,
		_man("e_grunt1", names.given(), E, 14, 8, 4, 3, Weapon.spear(), 2),
		_man("e_grunt2", names.given(), E, 14, 8, 4, 2, Weapon.axe(), 2),
		_man("e_bow1", names.given(), E, 12, 7, 3, 3, Weapon.bow(), 1),
	]
	var berserker := _man("e_berserk", names.given(), E, 12, 1, 6, 4, Weapon.axe(), 0, "berserker")
	var enemy_reserve: Array[Character] = [
		_man("e_karl1", names.given(), E, 11, 5, 3, 3, Weapon.spear(), 1),
		_man("e_karl2", names.given(), E, 11, 5, 3, 3, Weapon.sword(), 1),
		_man("e_karl3", names.given(), E, 11, 5, 3, 3, Weapon.axe(), 0),
		_man("e_karl4", names.given(), E, 11, 5, 3, 3, Weapon.spear(), 0),
		berserker,
		_man("e_bow2", names.given(), E, 10, 6, 2, 3, Weapon.bow(), 0),
		_man("e_old1", names.given(), E, 12, 6, 3, 2, Weapon.sword(), 2),
	]

	return {
		"player_field": player_field,
		"player_reserve": player_reserve,
		"enemy_field": enemy_field,
		"enemy_reserve": enemy_reserve,
		"enemy_captain": enemy_captain,
		"captain_command": {"name": "Iron and hunger", "effect": "blood_rage",
				"amount": 1, "period": 4},
		"deck": CardLibrary.veteran_deck(),
		"maneuvers": CardLibrary.default_maneuvers(),
		"enemy_tactics": [
			"press_the_attack", "arrow_volley", "fear_horn", "reinforcement_surge",
			"fresh_men_forward", "shift_port", "shift_starboard", "step_up",
		],
	}
