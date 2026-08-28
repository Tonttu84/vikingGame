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
var is_captain := false    ## leader aura: line-neighbors strike +1 (CombatEngine)
var is_prowman := false    ## the captain's alternate: one of the pair must hold the field
var is_berserker := false  ## immune to morale damage; his attacks cleave (CombatEngine)
var is_shieldman := false  ## takes half damage (rounded up); aura: +1 armor to line-neighbors
var shaken := false        ## routed earlier in the raid; reduced morale
## Enemy wind-up rhythm (docs/lines-redesign.md phase C): fight phases left
## until the heavy cleave / double shot fires — 0 fires this turn, -1 = no
## rhythm (all player characters, plain fighters, the unfielded).
var windup := -1
var bonus_attacks := 0     ## granted by cards, consumed in the next fight phase
var order_id := 0          ## spawn serial; total ordering for deterministic resolution
## Setup-only hint (RosterText slot syntax): the grid slot this character is
## fielded into at battle start, -1 for auto-placement. Live position lives
## in the battle's Formation, never here.
var deploy_slot := -1


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
## Deterministic: Strength + weapon + aura bonus - armor, minimum 1. The axe
## is the aura-breaker: it ignores 2 points of worn armor AND denies the
## defender any aura armor. Aura amounts are positional; CombatEngine reads
## them off the formations and passes them in.
func damage_against(defender: Character, bonus_damage := 0, aura_armor := 0) -> int:
	var dmg := strength + weapon.damage_bonus + bonus_damage
	var effective_armor := defender.armor + aura_armor
	if weapon.kind == Weapon.Kind.AXE:
		effective_armor = maxi(0, defender.armor - 2)
	return maxi(1, dmg - effective_armor)
