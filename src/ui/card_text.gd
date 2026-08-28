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
		CardData.EffectType.CHALLENGE:
			return "Both captains must be in the line: they attack each other this round, columns be damned."
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
		CardData.EffectType.RIDER_SLIDE:
			return "Then slide one of your men one column, larboard or starboard (must move if you can)."
		CardData.EffectType.RIDER_STEP:
			return "Then he steps to the other line of his column, forward or back (must move if he can)."
		CardData.EffectType.RIDER_ADVANCE:
			return "Then he advances into the empty front slot of his column (must move if he can)."
		CardData.EffectType.RIDER_SWAP_FIELDED:
			return "Then two of your men on deck trade slots (must move if you can)."
	return ""


static func tactic_name(tactic: String) -> String:
	match tactic:
		"arrow_volley": return "Arrow Volley"
		"fear_horn": return "Fear Horn"
		"reinforcement_surge": return "Reinforcement Surge"
		"fresh_men_forward": return "Fresh Men Forward"
		"shift_larboard": return "Shift Larboard"
		"shift_starboard": return "Shift Starboard"
		"step_up": return "Step Up"
	return "Press the Attack"


static func tactic_description(tactic: String) -> String:
	match tactic:
		"arrow_volley":
			return "1 damage to each of your boarders. A Shield Wall stops it."
		"fear_horn":
			return "1 morale damage to each of your boarders."
		"reinforcement_surge":
			return "Up to 4 enemies step over the rail instead of 2."
		"fresh_men_forward":
			return "Their front and second lines trade places before they fight."
		"shift_larboard":
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

[b]Each turn[/b]: your hand is discarded and redrawn to 5 — except Retained cards (Reinforce, Swap, Drag Him Back!), which wait in hand for their moment. Play cards — most also move your men — then both formations fight, fastest first. Axes ignore 2 armor.

[b]The enemy captain[/b] waits at the stern, unreachable, until his hold empties — then he steps into the line himself and fights like anyone: reach him through his column, or shove his line apart. Kill him and his crew yields. Lose your own captain and the raid is over.

[b]The telegraph[/b]: the enemy's next move is always readable — his tactic or formation call shows a turn ahead, their berserker carries a visible counter to a heavy blow (double damage — dodge his column or eat it), and their archer marks his man one full turn before loosing both aimed arrows. A marked man rescued to the ship wastes the shot.

[b]Morale[/b]: every death shakes the fallen side (-2 morale on deck, captains and berserkers excepted). At 0 a fighter routs, shaking the line further. Routs win battles as surely as blood.

[b]The rail[/b]: enemies reinforce 2 per turn into their front gaps. Commit your own reserve for 1 momentum each; the reserve itself never fights and is never hit. Retreat is always on the table — a live crew beats a dead legend."""
