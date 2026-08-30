class_name Character
extends RefCounted
## A fighter on either side of a boarding action. Deliberately small sheet:
## HP, Morale, Strength, Speed, one weapon, one guard value (`armor`).

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
## The man's guard (docs/block-and-patterns.md): how much block he raises at
## battle start and at each of his side's turn starts. No stat permanently
## reduces damage any more.
var armor: int
## Turn-scoped block: absorbs physical damage point for point (the axe chews
## it at double rate), reset to `armor` when his side's turn comes round.
## True damage and morale damage go around it. CombatEngine owns the math.
var block := 0
var is_captain := false    ## leader aura: line-neighbors strike +1 (CombatEngine)
var is_prowman := false    ## the captain's alternate: one of the pair must hold the field
var is_berserker := false  ## immune to morale damage; his attacks cleave (CombatEngine)
var is_shieldman := false  ## the block kit (docs/block-and-patterns.md; lands with patterns)
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


## Raw damage this character deals to `defender`, before side-wide modifiers
## and before the defender's block chews at it. Deterministic: Strength +
## weapon + bonuses, minimum 1. Nothing on the defender's sheet reduces it —
## his defense is his block, and CombatEngine spends that where the blow lands.
func damage_against(_defender: Character, bonus_damage := 0) -> int:
	return maxi(1, strength + weapon.damage_bonus + bonus_damage)
