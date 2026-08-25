class_name Weapon
extends RefCounted
## A weapon: flat damage bonus plus one trait. See docs/combat-design.md.

enum Kind {
	NONE,   ## bare hands
	SPEAR,  ## +1 damage against a target this character was not already engaged with
	AXE,    ## ignores 2 points of the defender's armor
	SWORD,  ## plain damage bonus, no gimmick
	BOW,    ## can attack while in reserve
}

var id: String
var display_name: String
var damage_bonus: int
var kind: Weapon.Kind

func _init(p_id: String = "fists", p_name: String = "Fists", p_bonus: int = 0, p_kind: Weapon.Kind = Kind.NONE) -> void:
	id = p_id
	display_name = p_name
	damage_bonus = p_bonus
	kind = p_kind


static func fists() -> Weapon:
	return Weapon.new()


static func spear() -> Weapon:
	return Weapon.new("spear", "Spear", 1, Kind.SPEAR)


static func axe() -> Weapon:
	return Weapon.new("axe", "Axe", 1, Kind.AXE)


static func sword() -> Weapon:
	return Weapon.new("sword", "Sword", 2, Kind.SWORD)


static func bow() -> Weapon:
	return Weapon.new("bow", "Bow", 1, Kind.BOW)
