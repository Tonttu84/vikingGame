class_name CardText
extends RefCounted
## UI-only rules text: what a card or an enemy tactic does, in words a
## stranger can act on. No rules live here — only descriptions of them.


static func describe(card: CardData) -> String:
	if card.is_loot:
		return "Dead weight from the last raid. It clogs your draws until you sail home."
	var lines: Array[String] = []
	for effect in card.effects:
		lines.append(_effect_line(effect))
	if card.reaction_save:
		lines.append("Fires by itself: when a fighter would fall, pays %d to drag them back at 1 HP." % card.cost)
	if card.retained:
		lines.append("Retained: waits in hand instead of discarding at turn end.")
	return "\n".join(lines)


## The card face's short text: one compact line per effect, so the face stays
## readable at hand size. Full sentences (describe) belong to the hover
## preview — the face only has to be actable at a glance, never complete.
## Movement riders keep their DIRECTION loud: that word is the rules promise
## "the direction is printed on the card".
static func summarize(card: CardData) -> String:
	if card.is_loot:
		return "Dead weight. Clogs your draws until you sail home."
	var lines: Array[String] = []
	for effect in card.effects:
		lines.append(_effect_short(effect))
	if card.reaction_save:
		lines.append("Fires by itself: saves a falling fighter at 1 HP (pays %d)." % card.cost)
	return "\n".join(lines)


static func _effect_short(effect: Dictionary) -> String:
	var amount: int = effect.get("amount", 0)
	match effect.get("type"):
		CardData.EffectType.DAMAGE_ENEMY_FRONT_LINE:
			return "Deal %d to their whole front line, straight through block." % amount
		CardData.EffectType.MORALE_DAMAGE_ALL_ENEMIES:
			return "%d morale damage to every enemy on deck." % amount
		CardData.EffectType.HEAL:
			return "Heal an ally for %d." % amount
		CardData.EffectType.FOCUS_FIRE:
			return "His column + your archers all strike him now."
		CardData.EffectType.SHIELD_WALL:
			return "Your side takes 2 less per hit this turn. Stops volleys."
		CardData.EffectType.PULL_TO_RESERVE:
			return "Pull an ally back to your ship."
		CardData.EffectType.SHOVE:
			return "Shove an enemy front-liner one column sideways."
		CardData.EffectType.TAUNT:
			return "Drag an enemy to the front of your man's column."
		CardData.EffectType.DRIVE_BACK:
			return "Swap an enemy behind the man at his back — he takes blows, answers none."
		CardData.EffectType.BLOCK_REINFORCEMENTS:
			return "No enemy reinforcements next turn."
		CardData.EffectType.EXTRA_ATTACK:
			return "An ally strikes %d extra time." % amount
		CardData.EffectType.DRAW:
			return "Draw %d cards." % amount
		CardData.EffectType.WAR_CRY:
			return "+1 momentum per enemy slain this turn."
		CardData.EffectType.GAIN_MOMENTUM:
			return "Gain %d momentum." % amount
		CardData.EffectType.SEND_DEFENDERS_BELOW:
			return "%d defenders caught below decks, shaken." % amount
		CardData.EffectType.ARCHER_SUPPORT:
			return "All battle: each ship archer opens with a %d-dmg arrow." % amount
		CardData.EffectType.PLAYER_ARMOR_BONUS:
			return "All battle: your side takes %d less per hit." % amount
		CardData.EffectType.DEFENDERS_FORM_UP:
			return "%d extra defenders form up at the rail." % amount
		CardData.EffectType.ENEMY_MORALE_BONUS:
			return "Every defender gains %d morale." % amount
		CardData.EffectType.RIDER_PORT:
			return "Then a man steps to PORT."
		CardData.EffectType.RIDER_STARBOARD:
			return "Then a man steps to STARBOARD."
		CardData.EffectType.RIDER_FORWARD:
			return "Then he PRESSES to the front."
		CardData.EffectType.RIDER_BACKWARD:
			return "Then he GIVES GROUND a line back."
		CardData.EffectType.RIDER_CLOSE:
			return "Then a man CLOSES on the enemy."
	return _effect_line(effect)


## How this card is played, for the card's own footnote. Reinforce names a
## slot, the targeted cards name a man, the rest land anywhere.
static func drop_hint(card: CardData) -> String:
	for effect in card.effects:
		if effect.get("type") == CardData.EffectType.REINFORCE:
			return "drag onto an empty slot"
	match card.target_type:
		CardData.TargetType.ENEMY:
			return "drag onto an enemy"
		CardData.TargetType.ALLY:
			return "drag onto an ally"
	return ""


## The name of the movement this card's rider forces, for the prompt line
## that explains why the board is suddenly asking for a pick.
static func rider_kind(card: CardData) -> String:
	if card == null:
		return "move"
	for effect in card.effects:
		match effect.get("type"):
			CardData.EffectType.RIDER_PORT:
				return "step to port"
			CardData.EffectType.RIDER_STARBOARD:
				return "step to starboard"
			CardData.EffectType.RIDER_FORWARD:
				return "press forward"
			CardData.EffectType.RIDER_BACKWARD:
				return "give ground"
			CardData.EffectType.RIDER_CLOSE:
				return "close"
	return "move"


static func _effect_line(effect: Dictionary) -> String:
	var amount: int = effect.get("amount", 0)
	match effect.get("type"):
		CardData.EffectType.DAMAGE_ENEMY_FRONT_LINE:
			return "Deal %d to every enemy in their front line. Ignores armor." % amount
		CardData.EffectType.MORALE_DAMAGE_ALL_ENEMIES:
			return "%d morale damage to every enemy on deck." % amount
		CardData.EffectType.HEAL:
			return "Heal an ally for %d." % amount
		CardData.EffectType.FOCUS_FIRE:
			return "Everyone who can reach the target — his column, plus your archers — strikes it this fight phase."
		CardData.EffectType.SHIELD_WALL:
			return "Your side takes 2 less from every hit until your next turn. Stops arrow volleys."
		CardData.EffectType.PULL_TO_RESERVE:
			return "Pull an ally out of the fight, back to your ship."
		CardData.EffectType.SHOVE:
			return "Shove an enemy front-liner one column sideways — re-aim THEIR line."
		CardData.EffectType.TAUNT:
			return "Name a defender and one of your men: he is dragged into the front slot of your man's column, swapping with whoever stood there."
		CardData.EffectType.DRIVE_BACK:
			return "Drive an enemy front-liner into the second line of his column, swapping with the man behind him. He still takes his column's blows — he just cannot answer them."
		CardData.EffectType.BLOCK_REINFORCEMENTS:
			return "The enemy gets no reinforcements next turn."
		CardData.EffectType.EXTRA_ATTACK:
			return "An ally strikes %d extra time this fight phase." % amount
		CardData.EffectType.DRAW:
			return "Draw %d cards." % amount
		CardData.EffectType.WAR_CRY:
			return "Gain 1 extra momentum for each enemy slain this turn."
		CardData.EffectType.GAIN_MOMENTUM:
			return "Gain %d momentum." % amount
		CardData.EffectType.SEND_DEFENDERS_BELOW:
			return "%d defenders are caught below decks — back of their reserve queue, shaken." % amount
		CardData.EffectType.ARCHER_SUPPORT:
			return ("All battle: each archer still on your ship opens your fight phases " +
					"with a %d-true-damage arrow at the weakest fielded defender.") % amount
		CardData.EffectType.PLAYER_ARMOR_BONUS:
			return "All battle: your side takes %d less from every hit." % amount
		CardData.EffectType.DEFENDERS_FORM_UP:
			return "%d extra defenders have time to form up at the rail." % amount
		CardData.EffectType.ENEMY_MORALE_BONUS:
			return "The watch stands composed: every defender gains %d morale." % amount
		CardData.EffectType.RIDER_PORT:
			return "Then one of your men steps one column to PORT. Mandatory."
		CardData.EffectType.RIDER_STARBOARD:
			return "Then one of your men steps one column to STARBOARD. Mandatory."
		CardData.EffectType.RIDER_FORWARD:
			return "PRESS: then he advances into the empty front slot of his column. Mandatory."
		CardData.EffectType.RIDER_BACKWARD:
			return "GIVE GROUND: then he falls back into the empty second-line slot of his column. Mandatory."
		CardData.EffectType.RIDER_CLOSE:
			return "CLOSE: then one of your men steps one column toward the nearest enemy. Mandatory."
	return ""


static func tactic_name(tactic: String) -> String:
	match tactic:
		"captains_order": return "The Captain's Order"
		"arrow_volley": return "Arrow Volley"
		"fear_horn": return "Fear Horn"
		"reinforcement_surge": return "Reinforcement Surge"
		"fresh_men_forward": return "Fresh Men Forward"
		"shift_port": return "Shift Port"
		"shift_starboard": return "Shift Starboard"
		"step_up": return "Step Up"
	return "Press the Attack"


static func tactic_description(tactic: String) -> String:
	match tactic:
		"captains_order":
			return "Their captain roars: every fielded defender gains +1 damage, permanently. It stacks."
		"arrow_volley":
			return "1 damage to each of your boarders. A Shield Wall stops it."
		"fear_horn":
			return "1 morale damage to each of your boarders."
		"reinforcement_surge":
			return "Up to 4 enemies step over the rail instead of 2."
		"fresh_men_forward":
			return "Their front and second lines trade places before they fight."
		"shift_port":
			return "Their whole line slides one column to your left — every duel re-pairs."
		"shift_starboard":
			return "Their whole line slides one column to your right — every duel re-pairs."
		"step_up":
			return "Their back-liners step into the empty front slots of their columns."
	return "The enemy line simply fights."


static func rules_summary() -> String:
	return """[b]The boarding action[/b]
You are the raid captain. Your crew fights on its own — your cards are the orders you shout over the noise.

[b]The lines[/b]: each side fields 4 columns x 2 lines. A fighter attacks the nearest enemy in HIS OWN column — their front man first, then their second line. A whole empty column means his swing hits air: placement is targeting, and placement is defense. Spears reach from the second line; archers in the second line snipe the weakest enemy anywhere; everyone else must stand in front to fight.

[b]Momentum[/b] powers cards: +1 each turn, more for each enemy slain. Routs pay nothing — breaking men is free but earns no tempo.

[b]Each turn[/b]: your hand is discarded and redrawn to 5 — except Retained cards (Reinforce, Trade Places, Drag Him Back!), which wait in hand for their moment. Play cards — most also move one of your men, and that move is mandatory and its DIRECTION IS PRINTED ON THE CARD: port, starboard, press forward, give ground, or close on the nearest enemy. The board lights up every man who could take that step and you pick which one, never whether and never which way — and a card whose step nobody can take cannot be played at all. Then both formations fight — axes first (they chew 2 block per point of damage), then the rest by speed. Every man follows his rhythm: berserkers build to a doubled HEAVY blow, archers AIM before both arrows fly (the mark comes away suppressed, a third weaker), shieldmen raise the wall before they swing. Armor is guard: it comes back up as block at each side's turn.

[b]The press[/b]: every column is a duel. After both sides have fought, the side that drew more BLOOD in a column wins it (a blow that died on a guard is nothing; a column held by one side alone is that side's; arrows never win columns). More columns won = the press: +1 momentum for having it and +1 per column of margin, and at a margin of 2 or more the losing line loses 1 morale a man. Nothing moves — it is a verdict.

[b]The enemy captain[/b] waits at the stern, unreachable, until his hold empties — then he steps into the line himself and fights like anyone: reach him through his column, or shove his line apart. Kill him and his crew yields. Lose your own captain and the raid is over.

[b]The telegraph[/b]: the enemy's next move is always readable — his tactic or formation call shows a turn ahead, their berserker carries a visible counter to a heavy blow (double damage — dodge his column or eat it), and their archer marks his man one full turn before loosing both aimed arrows. A marked man rescued to the ship wastes the shot.

[b]Morale[/b]: every death shakes the fallen side (-2 morale on deck, captains and berserkers excepted). At 0 a fighter routs, shaking the line further. Routs win battles as surely as blood.

[b]The rail[/b]: enemies reinforce 2 per turn into their front gaps. Commit your own reserve for 1 momentum each — click the man, then the slot; the reserve itself never fights and is never hit. Your captain and his prowman are alternates: one of them always holds the field, and only Trade Places trades them, so the waiting one shows dimmed on your rail. Retreat is always on the table — a live crew beats a dead legend."""
