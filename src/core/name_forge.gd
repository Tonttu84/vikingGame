class_name NameForge
extends RefCounted
## Old Norse first names for the crews and the levies (owner's ruling
## 2026-09-06: non-uniques are "<Role> <first name>", so the game needs a well
## of first names to draw from — for the anchor rosters today, for recruits
## and enemy crews when the raid loop lands).
##
## Deterministic by construction: every draw goes through the RNG seeded at
## construction (the project's hard invariant — never randi(), never
## pick_random()). One forge never repeats a name, so two Orms never share a
## deck; past the pool it forges "<name> the Younger" rather than a blank.
## Reserve the uniques' hand-picked names first and no crewman doubles them.

const MALE: Array[String] = [
	"Arn", "Asgeir", "Bard", "Bjorn", "Bodvar", "Brand", "Dag", "Egil", "Einar",
	"Erling", "Eyvind", "Finn", "Frodi", "Gauk", "Geir", "Gest", "Gisli", "Grim",
	"Gunnar", "Hakon", "Halfdan", "Harald", "Hauk", "Helgi", "Hjalti", "Hrapp",
	"Hrolf", "Ingolf", "Ivar", "Kalf", "Kari", "Ketil", "Kjartan", "Knut",
	"Kolgrim", "Leif", "Odd", "Olaf", "Onund", "Orm", "Ottar", "Ozur", "Ragnar",
	"Rolf", "Sigurd", "Snorri", "Solvi", "Steinn", "Styr", "Svein", "Thorgil",
	"Thorkel", "Thorstein", "Toki", "Torfi", "Ulf", "Vagn", "Vali", "Vigfus",
]
const FEMALE: Array[String] = [
	"Asa", "Astrid", "Bera", "Gudrun", "Halla", "Helga", "Hild", "Ingrid",
	"Jorunn", "Ragnhild", "Runa", "Sigrid", "Solveig", "Thora", "Thordis",
	"Unn", "Yngvild",
]

var _rng := RandomNumberGenerator.new()
var _used := {}


func _init(seed_value: int) -> void:
	_rng.seed = seed_value


## A name that will not be forged: the uniques' own (Sten, Aslak, Sigvard).
func reserve(name: String) -> void:
	_used[name] = true


func given() -> String:
	return _draw(MALE)


func given_female() -> String:
	return _draw(FEMALE)


## An unused name from the pool, chosen by the seeded RNG among what is left
## so the order is fixed by the seed alone. An exhausted pool forges a
## younger namesake — the draw itself stays seeded.
func _draw(pool: Array[String]) -> String:
	var free: Array[String] = []
	for name in pool:
		if not _used.has(name):
			free.append(name)
	if free.is_empty():
		var elder: String = pool[_rng.randi_range(0, pool.size() - 1)]
		var younger := elder + " the Younger"
		_used[younger] = true
		return younger
	var name: String = free[_rng.randi_range(0, free.size() - 1)]
	_used[name] = true
	return name
