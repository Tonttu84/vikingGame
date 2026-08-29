class_name CardData
extends RefCounted
## A card in the captain's tactic deck. Effects are data (type + amount),
## interpreted by CombatEngine — new cards are new combinations, not new code.

enum TargetType { NONE, ENEMY, ALLY }

enum EffectType {
	DAMAGE_ENEMY_FRONT_LINE,   ## flat damage to every enemy front-liner (ignores armor)
	MORALE_DAMAGE_ALL_ENEMIES, ## morale damage to every fielded enemy
	HEAL,                      ## heal targeted ally
	FOCUS_FIRE,                ## everyone who can reach the target strikes it this fight phase
	SHIELD_WALL,               ## your side takes -2 per hit until your next turn; blocks arrow volleys
	PULL_TO_RESERVE,           ## move targeted ally from field to reserve
	SHOVE,                     ## shove a targeted enemy front-liner one column sideways
	TAUNT,                     ## drag a named enemy into the front slot of your man's column
	DRIVE_BACK,                ## drive an enemy front-liner into the second line of his column
	BLOCK_REINFORCEMENTS,      ## enemy reinforcement step is skipped next enemy turn
	EXTRA_ATTACK,              ## targeted ally attacks one extra time this fight phase
	DRAW,                      ## draw cards
	WAR_CRY,                   ## +1 extra momentum per enemy killed this turn
	GAIN_MOMENTUM,             ## +amount momentum (boarding maneuvers, rallying cards)
	REINFORCE,                 ## field an ally from reserve (target optional; default first)
	SWAP,                      ## targeted fielded ally trades places with a reserve ally
	SEND_DEFENDERS_BELOW,      ## amount fielded enemies go to the BACK of their reserve
	DEFENDERS_FORM_UP,         ## amount enemy reserves are fielded immediately
	ARCHER_SUPPORT,            ## battle-long: each player fight phase opens with an
	                           ## arrow volley, amount true damage to the lowest-HP defender
	PLAYER_ARMOR_BONUS,        ## battle-long: your side takes -amount per hit
	ENEMY_MORALE_BONUS,        ## +amount morale (and cap) for the whole enemy crew
	# --- Movement riders (docs/card-design-proposal.md §1). A rider is listed
	# LAST in a card's effects: the punch lands, then the men move. Riders are
	# mandatory and their DIRECTION IS FIXED BY THE CARD — the player never
	# picks which way, only (on a card that does not already name an ally)
	# which man. A card whose rider has no legal move is refused before payment.
	RIDER_LARBOARD,            ## one column toward column 0, along his own line
	RIDER_STARBOARD,           ## one column toward column 3, along his own line
	RIDER_FORWARD,             ## "Press": second line into the empty front slot of his column
	RIDER_BACKWARD,            ## "Give Ground": front into the empty second-line slot
	RIDER_CLOSE,               ## one column toward the nearest occupied enemy column
}

var id: String
var display_name: String
var cost: int
var playable: bool
var is_loot: bool
var target_type: CardData.TargetType
## Array of { "type": EffectType, "amount": int }
var effects: Array[Dictionary]
## Retained cards are exempt from the end-of-turn discard: once drawn they
## wait in hand (and occupy hand space) until played.
var retained: bool = false
## Reaction-save cards (Drag Him Back!) fire AUTOMATICALLY when a killing
## blow lands on a non-captain crew member and the cost is affordable.
var reaction_save: bool = false


func _init(p_id: String, p_name: String, p_cost: int,
		p_target: CardData.TargetType, p_effects: Array[Dictionary],
		p_playable: bool = true, p_is_loot: bool = false) -> void:
	id = p_id
	display_name = p_name
	cost = p_cost
	target_type = p_target
	effects = p_effects
	playable = p_playable
	is_loot = p_is_loot
