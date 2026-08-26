class_name CardText
extends RefCounted
## UI-only rules text: what a card or an enemy tactic does, in words a
## stranger can act on. No rules live here — only descriptions of them.


static func describe(card: CardData) -> String:
	if card.is_loot:
		return "Dead weight from the last raid. Scrap it for %d momentum." % card.scrap_value
	var lines: Array[String] = []
	for effect in card.effects:
		lines.append(_effect_line(effect))
	if card.reaction_save:
		lines.append("Reaction: when a fighter would fall, pay %d to drag them back at 1 HP instead." % card.cost)
	return "\n".join(lines)


static func _effect_line(effect: Dictionary) -> String:
	var amount: int = effect.get("amount", 0)
	match effect.get("type"):
		CardData.EffectType.DAMAGE_ALL_ENEMIES:
			return "Deal %d to every enemy on deck. Ignores armor." % amount
		CardData.EffectType.MORALE_DAMAGE_ALL_ENEMIES:
			return "%d morale damage to every enemy on deck." % amount
		CardData.EffectType.HEAL:
			return "Heal an ally for %d." % amount
		CardData.EffectType.FOCUS_FIRE:
			return "Every fighter you have strikes the target this fight phase."
		CardData.EffectType.SHIELD_WALL:
			return "Your side takes 2 less from every hit until your next turn. Stops arrow volleys."
		CardData.EffectType.PULL_TO_RESERVE:
			return "Pull an ally out of the fight, back to your ship."
		CardData.EffectType.EXPOSE_CAPTAIN:
			return "The enemy captain can be attacked until end of turn."
		CardData.EffectType.DUEL:
			return "Only the captains fight: yours this turn, theirs the next."
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
			return ("All battle: your rail archers open each of your fight phases with " +
					"%d true damage to the weakest fielded defender. They hold fire during a duel.") % amount
		CardData.EffectType.PLAYER_ARMOR_BONUS:
			return "All battle: your side takes %d less from every hit." % amount
		CardData.EffectType.DEFENDERS_FORM_UP:
			return "%d extra defenders have time to form up at the rail." % amount
		CardData.EffectType.ENEMY_MORALE_BONUS:
			return "The watch stands composed: every defender gains %d morale." % amount
	return ""


static func tactic_name(tactic: String) -> String:
	match tactic:
		"arrow_volley": return "Arrow Volley"
		"fear_horn": return "Fear Horn"
		"reinforcement_surge": return "Reinforcement Surge"
	return "Press the Attack"


static func tactic_description(tactic: String) -> String:
	match tactic:
		"arrow_volley":
			return "1 damage to each of your boarders. A Shield Wall stops it."
		"fear_horn":
			return "1 morale damage to each of your boarders."
		"reinforcement_surge":
			return "Up to 4 enemies step over the rail instead of 2."
	return "The enemy line simply fights."


static func rules_summary() -> String:
	return """[b]The boarding action[/b]
You are the raid captain. Your crew fights on its own — your cards are the orders you shout over the noise.

[b]Momentum[/b] powers cards: +1 each turn, +1 per enemy slain. Scrap one card a turn for its scrap value instead of playing it.

[b]Each turn[/b]: draw to 5, play cards, then both lines fight. Fastest strikes first; fighters keep hacking at whoever they are engaged with. Spears hit +1 on a fresh foe, axes ignore 2 armor, bows shoot from the reserve rows.

[b]The enemy captain[/b] is sheltered behind his line. Thin it to 2 fielded enemies, empty his reserves, or force a window with a card — then your whole crew goes for him. Kill him and his crew yields. Lose your own captain and the raid is over.

[b]Morale[/b]: every death shakes the fallen side (-2 morale on deck, captains and berserkers excepted). At 0 a fighter routs, shaking the line further. Routs win battles as surely as blood.

[b]The rail[/b]: enemies reinforce 2 per turn from their reserve. Commit your own reserve for 1 momentum each. Retreat is always on the table — a live crew beats a dead legend."""
