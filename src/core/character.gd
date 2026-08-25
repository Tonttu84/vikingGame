class_name Character
extends RefCounted
## A fighter on either side of a boarding action. Deliberately small sheet:
## HP, Morale, Strength, Speed, one weapon, one armor value.

enum Side { PLAYER, ENEMY }

var id: String
var display_name: String
var side: Character.Side
var max_hp: int
var hp: int
var max_morale: int
var morale: int
var strength: int
var speed: int
var weapon: Weapon
var armor: int
var is_captain := false
var is_berserker := false  ## immune to morale damage
var shaken := false        ## routed earlier in the raid; reduced morale
## Battle-transient state.
## Engagement is held weakly: mutual A<->B engagement would otherwise form a
## RefCounted cycle and leak. The battle's rosters hold the strong references.
var engaged_with: Character:
	get:
		return _engaged_ref.get_ref() if _engaged_ref != null else null
	set(value):
		_engaged_ref = weakref(value) if value != null else null
var _engaged_ref: WeakRef = null
var bonus_attacks := 0     ## granted by cards, consumed in the next fight phase
var order_id := 0          ## spawn serial; total ordering for deterministic resolution


func _init(p_id: String, p_name: String, p_side: Character.Side, p_hp: int, p_morale: int,
		p_strength: int, p_speed: int, p_weapon: Weapon = null, p_armor: int = 0) -> void:
	id = p_id
	display_name = p_name
	side = p_side
	max_hp = p_hp
	hp = p_hp
	max_morale = p_morale
	morale = p_morale
	strength = p_strength
	speed = p_speed
	weapon = p_weapon if p_weapon != null else Weapon.fists()
	armor = p_armor


func is_alive() -> bool:
	return hp > 0


func morale_immune() -> bool:
	return is_captain or is_berserker


## Damage this character deals to `defender`, before side-wide modifiers.
## Deterministic: Strength + weapon (+1 spear on a fresh engagement) - armor
## (axe ignores 2), minimum 1.
func damage_against(defender: Character) -> int:
	var dmg := strength + weapon.damage_bonus
	if weapon.kind == Weapon.Kind.SPEAR and engaged_with != defender:
		dmg += 1
	var effective_armor := defender.armor
	if weapon.kind == Weapon.Kind.AXE:
		effective_armor = maxi(0, effective_armor - 2)
	return maxi(1, dmg - effective_armor)
