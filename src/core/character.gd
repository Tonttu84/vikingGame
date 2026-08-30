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
var is_shieldman := false  ## the block kit: guards, and shares block when he does
var shaken := false        ## routed earlier in the raid; reduced morale
## The man's rhythm (docs/block-and-patterns.md): a cycle of beats performed
## one per own fight phase, BOTH sides. Roles map to patterns at registration
## (default_pattern); `beat` indexes the cycle and restarts on fielding.
var pattern: Array[String] = []
var beat := 0
## SUPPRESSED (the aimed double shot's debuff): while > 0, every damage
## packet he deals loses a third, rounded up against him. Own-turn-ends left.
var suppressed := 0
## The captain's command in his blood (docs/block-and-patterns.md): permanent
## bonus attack damage from every blood_rage order he stood on deck for.
var rage := 0
## PINNED (the closing rule's teeth): while > 0 this man cannot move, by any
## hand — the formation verbs refuse him and every card is gated off him.
## Decays 1 per own turn; each repeat pin lands pin_count MORE stacks, so
## dodging buys turns at a rising price. pin_count never decays in-battle.
var pinned := 0
var pin_count := 0
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


## The role's rhythm. The berserker builds to the heavy blow, the bow aims
## before it kills, the shieldman plants before he swings, everyone else
## just fights. One beat per own fight phase, on both sides of the deck.
func default_pattern() -> Array[String]:
	if is_berserker:
		return ["attack", "attack", "heavy"]
	if weapon.kind == Weapon.Kind.BOW:
		return ["aim", "shoot"]
	if is_shieldman:
		return ["guard", "attack"]
	return ["attack"]


func current_beat() -> String:
	return "attack" if pattern.is_empty() else pattern[beat % pattern.size()]


func advance_beat() -> void:
	if not pattern.is_empty():
		beat = (beat + 1) % pattern.size()


func morale_immune() -> bool:
	return is_captain or is_berserker


## Raw damage this character deals to `defender`, before side-wide modifiers
## and before the defender's block chews at it. Deterministic: Strength +
## weapon + bonuses, minimum 1. Nothing on the defender's sheet reduces it —
## his defense is his block, and CombatEngine spends that where the blow lands.
func damage_against(_defender: Character, bonus_damage := 0) -> int:
	return maxi(1, strength + weapon.damage_bonus + rage + bonus_damage)
