class_name CardLibrary
extends RefCounted
## The v0 card vocabulary from docs/combat-design.md, built in code for the
## headless milestone. Migrates to .tres resources when the Godot UI lands.


static func spear_volley() -> CardData:
	return CardData.new("spear_volley", "Spear Volley", 2, 1, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.DAMAGE_ALL_ENEMIES, "amount": 2}])


static func concentrated_attack() -> CardData:
	return CardData.new("concentrated_attack", "Concentrated Attack", 2, 1, CardData.TargetType.ENEMY,
			[{"type": CardData.EffectType.FOCUS_FIRE, "amount": 0}])


static func shield_wall() -> CardData:
	return CardData.new("shield_wall", "Shield Wall", 1, 1, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.SHIELD_WALL, "amount": 2}])


static func rally() -> CardData:
	return CardData.new("rally", "Rally", 1, 0, CardData.TargetType.ALLY,
			[{"type": CardData.EffectType.HEAL, "amount": 4}])


static func drag_him_back() -> CardData:
	var card := CardData.new("drag_him_back", "Drag Him Back!", 1, 0, CardData.TargetType.ALLY,
			[{"type": CardData.EffectType.PULL_TO_RESERVE, "amount": 0}])
	card.reaction_save = true
	return card


static func break_the_line() -> CardData:
	return CardData.new("break_the_line", "Break the Line", 3, 1, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.EXPOSE_CAPTAIN, "amount": 0}])


static func challenge() -> CardData:
	return CardData.new("challenge", "Challenge", 3, 1, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.DUEL, "amount": 0}])


static func push_them_back() -> CardData:
	return CardData.new("push_them_back", "Push Them Back", 2, 1, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.BLOCK_REINFORCEMENTS, "amount": 0}])


static func battle_fury() -> CardData:
	return CardData.new("battle_fury", "Battle Fury", 1, 0, CardData.TargetType.ALLY,
			[{"type": CardData.EffectType.EXTRA_ATTACK, "amount": 1}])


static func feint() -> CardData:
	return CardData.new("feint", "Feint", 0, 0, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.DRAW, "amount": 2}])


static func war_cry() -> CardData:
	return CardData.new("war_cry", "War Cry", 1, 0, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.WAR_CRY, "amount": 1}])


static func terrifying_bellow() -> CardData:
	return CardData.new("terrifying_bellow", "Terrifying Bellow", 1, 0, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.MORALE_DAMAGE_ALL_ENEMIES, "amount": 2}])


static func loot(p_id: String, p_name: String, p_scrap: int = 1) -> CardData:
	return CardData.new(p_id, p_name, 0, p_scrap, CardData.TargetType.NONE,
			[] as Array[Dictionary], false, true)


## Every buildable card id, for by_id lookups and the debug roster editor.
static func card_ids() -> Array[String]:
	return [
		"spear_volley", "concentrated_attack", "shield_wall", "rally",
		"drag_him_back", "break_the_line", "challenge", "push_them_back",
		"battle_fury", "feint", "war_cry", "terrifying_bellow",
		"loot_silver_a", "loot_silver_b", "loot_cauldron",
	]


static func by_id(p_id: String) -> CardData:
	match p_id:
		"spear_volley": return spear_volley()
		"concentrated_attack": return concentrated_attack()
		"shield_wall": return shield_wall()
		"rally": return rally()
		"drag_him_back": return drag_him_back()
		"break_the_line": return break_the_line()
		"challenge": return challenge()
		"push_them_back": return push_them_back()
		"battle_fury": return battle_fury()
		"feint": return feint()
		"war_cry": return war_cry()
		"terrifying_bellow": return terrifying_bellow()
		"loot_silver_a": return loot("loot_silver_a", "Plundered Silver")
		"loot_silver_b": return loot("loot_silver_b", "Plundered Silver")
		"loot_cauldron": return loot("loot_cauldron", "Iron Cauldron")
	return null


## The v0 starter deck: 19 tactics + 3 pieces of loot clogging it.
static func starter_deck() -> Array[CardData]:
	var deck: Array[CardData] = []
	for i in 2:
		deck.append(spear_volley())
		deck.append(concentrated_attack())
		deck.append(shield_wall())
		deck.append(rally())
		deck.append(battle_fury())
		deck.append(feint())
	deck.append(drag_him_back())
	deck.append(break_the_line())
	deck.append(challenge())
	deck.append(push_them_back())
	deck.append(war_cry())
	deck.append(terrifying_bellow())
	deck.append(loot("loot_silver_a", "Plundered Silver"))
	deck.append(loot("loot_silver_b", "Plundered Silver"))
	deck.append(loot("loot_cauldron", "Iron Cauldron"))
	return deck
