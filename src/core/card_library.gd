class_name CardLibrary
extends RefCounted
## The v0 card vocabulary from docs/combat-design.md, built in code for the
## headless milestone. Migrates to .tres resources when the Godot UI lands.


static func spear_volley() -> CardData:
	return CardData.new("spear_volley", "Spear Volley", 2, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.DAMAGE_ALL_ENEMIES, "amount": 2}])


static func concentrated_attack() -> CardData:
	return CardData.new("concentrated_attack", "Concentrated Attack", 2, CardData.TargetType.ENEMY,
			[{"type": CardData.EffectType.FOCUS_FIRE, "amount": 0}])


static func shield_wall() -> CardData:
	return CardData.new("shield_wall", "Shield Wall", 1, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.SHIELD_WALL, "amount": 2}])


static func rally() -> CardData:
	return CardData.new("rally", "Rally", 1, CardData.TargetType.ALLY,
			[{"type": CardData.EffectType.HEAL, "amount": 4}])


static func drag_him_back() -> CardData:
	var card := CardData.new("drag_him_back", "Drag Him Back!", 1, CardData.TargetType.ALLY,
			[{"type": CardData.EffectType.PULL_TO_RESERVE, "amount": 0}])
	card.reaction_save = true
	card.retained = true
	return card


static func break_the_line() -> CardData:
	# Repurposed by the lines redesign: you re-aim THEIR formation — shove a
	# front-liner out of his column (out of his duel, into a worse one).
	return CardData.new("break_the_line", "Break the Line", 1, CardData.TargetType.ENEMY,
			[{"type": CardData.EffectType.SHOVE, "amount": 1}])


static func challenge() -> CardData:
	# Repurposed: only while both captains are fielded — they attack each
	# other this round regardless of columns. Everyone else fights on.
	return CardData.new("challenge", "Challenge", 2, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.CHALLENGE, "amount": 0}])


static func push_them_back() -> CardData:
	return CardData.new("push_them_back", "Push Them Back", 2, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.BLOCK_REINFORCEMENTS, "amount": 0}])


static func battle_fury() -> CardData:
	return CardData.new("battle_fury", "Battle Fury", 1, CardData.TargetType.ALLY,
			[{"type": CardData.EffectType.EXTRA_ATTACK, "amount": 1}])


static func feint() -> CardData:
	return CardData.new("feint", "Feint", 0, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.DRAW, "amount": 2}])


static func war_cry() -> CardData:
	return CardData.new("war_cry", "War Cry", 1, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.WAR_CRY, "amount": 1}])


static func terrifying_bellow() -> CardData:
	return CardData.new("terrifying_bellow", "Terrifying Bellow", 1, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.MORALE_DAMAGE_ALL_ENEMIES, "amount": 2}])


static func reinforce() -> CardData:
	var card := CardData.new("reinforce", "Reinforce", 1, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.REINFORCE, "amount": 1}])
	card.retained = true
	return card


static func swap() -> CardData:
	var card := CardData.new("swap", "Swap", 1, CardData.TargetType.ALLY,
			[{"type": CardData.EffectType.SWAP, "amount": 1}])
	card.retained = true
	return card


static func loot(p_id: String, p_name: String) -> CardData:
	return CardData.new(p_id, p_name, 0, CardData.TargetType.NONE,
			[] as Array[Dictionary], false, true)


# --- Boarding maneuvers -------------------------------------------------------
# Free opening cards from their own tiny deck, set aside once played. They are
# never valid in the battle deck: functionally a menu, code-wise cards.

static func grapple_rush() -> CardData:
	return CardData.new("grapple_rush", "Grapple & Rush", 0, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.GAIN_MOMENTUM, "amount": 6}])


static func dawn_raid() -> CardData:
	return CardData.new("dawn_raid", "Dawn Raid", 0, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.GAIN_MOMENTUM, "amount": 4},
			{"type": CardData.EffectType.SEND_DEFENDERS_BELOW, "amount": 3}])


static func covering_volley() -> CardData:
	return CardData.new("covering_volley", "Covering Volley", 0, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.GAIN_MOMENTUM, "amount": 2},
			{"type": CardData.EffectType.ARCHER_SUPPORT, "amount": 2}])


static func careful_assault() -> CardData:
	# A shieldwall-like bonus that lasts the whole battle: -1 damage on every
	# hit your side takes. The price: a small surge, extra defenders ready at
	# the rail, and nobody is frightened by a slow, orderly assault — the
	# watch stands composed (+1 morale), blunting the rout cascades.
	return CardData.new("careful_assault", "Careful Assault", 0, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.GAIN_MOMENTUM, "amount": 2},
			{"type": CardData.EffectType.PLAYER_ARMOR_BONUS, "amount": 1},
			{"type": CardData.EffectType.DEFENDERS_FORM_UP, "amount": 2},
			{"type": CardData.EffectType.ENEMY_MORALE_BONUS, "amount": 1}])


static func maneuver_ids() -> Array[String]:
	return ["grapple_rush", "dawn_raid", "covering_volley", "careful_assault"]


static func maneuver_by_id(p_id: String) -> CardData:
	match p_id:
		"grapple_rush": return grapple_rush()
		"dawn_raid": return dawn_raid()
		"covering_volley": return covering_volley()
		"careful_assault": return careful_assault()
	return null


static func default_maneuvers() -> Array[CardData]:
	var maneuvers: Array[CardData] = []
	for id in maneuver_ids():
		maneuvers.append(maneuver_by_id(id))
	return maneuvers


## Every buildable card id, for by_id lookups and the debug roster editor.
static func card_ids() -> Array[String]:
	return [
		"spear_volley", "concentrated_attack", "shield_wall", "rally",
		"drag_him_back", "break_the_line", "challenge", "push_them_back",
		"battle_fury", "feint", "war_cry", "terrifying_bellow",
		"reinforce", "swap",
		"loot_silver_a", "loot_silver_b", "loot_cauldron",
		"loot_arm_ring", "loot_tapestry",
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
		"reinforce": return reinforce()
		"swap": return swap()
		"loot_silver_a": return loot("loot_silver_a", "Plundered Silver")
		"loot_silver_b": return loot("loot_silver_b", "Plundered Silver")
		"loot_cauldron": return loot("loot_cauldron", "Iron Cauldron")
		"loot_arm_ring": return loot("loot_arm_ring", "Golden Arm-Ring")
		"loot_tapestry": return loot("loot_tapestry", "Frankish Tapestry")
	return null


## The v0 starter deck: 24 tactics + 3 pieces of loot clogging it. Crossing
## the rail lives in the deck, so Reinforce/Swap are well represented.
static func starter_deck() -> Array[CardData]:
	var deck: Array[CardData] = []
	for i in 3:
		deck.append(reinforce())
	for i in 2:
		deck.append(spear_volley())
		deck.append(concentrated_attack())
		deck.append(shield_wall())
		deck.append(rally())
		deck.append(battle_fury())
		deck.append(feint())
		deck.append(swap())
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


## The veteran raid's deck: the starter vocabulary a summer of raiding later.
## 34 tactics — deeper on the rail (Reinforce/Swap) and the punch cards — and
## 5 pieces of loot: success clogs the deck, that's the roguelite bargain.
static func veteran_deck() -> Array[CardData]:
	var deck: Array[CardData] = []
	for i in 4:
		deck.append(reinforce())
	for i in 3:
		deck.append(swap())
		deck.append(spear_volley())
		deck.append(concentrated_attack())
		deck.append(shield_wall())
		deck.append(battle_fury())
	for i in 2:
		deck.append(rally())
		deck.append(feint())
		deck.append(drag_him_back())
		deck.append(challenge())
		deck.append(break_the_line())
		deck.append(push_them_back())
		deck.append(war_cry())
	deck.append(terrifying_bellow())
	deck.append(loot("loot_silver_a", "Plundered Silver"))
	deck.append(loot("loot_silver_b", "Plundered Silver"))
	deck.append(loot("loot_cauldron", "Iron Cauldron"))
	deck.append(loot("loot_arm_ring", "Golden Arm-Ring"))
	deck.append(loot("loot_tapestry", "Frankish Tapestry"))
	return deck
