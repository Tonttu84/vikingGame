class_name BattleState
extends RefCounted
## All mutable state of one boarding action. Pure data + queries; the rules
## that change it live in CombatEngine.

const HAND_SIZE := 5
const MOMENTUM_CAP := 10
## The rail is a bottleneck: boarders can never outnumber this on their deck.
const PLAYER_FIELD_CAP := 5
## The defenders are home; their cap is always >= the player's.
const ENEMY_FIELD_CAP := 6
const REINFORCE_RATE := 2
const SURGE_REINFORCE_RATE := 4
const CAPTAIN_EXPOSED_FIELD_SIZE := 2
const DEATH_MORALE_HIT := 2
const ROUT_MORALE_HIT := 1
const RESERVE_COMMIT_COST := 1

var player_field: Array[Character] = []
var player_reserve: Array[Character] = []
var player_fled: Array[Character] = []
var player_dead: Array[Character] = []
var player_captain: Character = null

var enemy_field: Array[Character] = []
var enemy_reserve: Array[Character] = []
var enemy_routed: Array[Character] = []
var enemy_dead: Array[Character] = []
var enemy_captain: Character = null

var momentum := 0
var deck: Array[CardData] = []
var hand: Array[CardData] = []
var discard: Array[CardData] = []

var artifacts: Array[ArtifactData] = []
## The boarding-maneuver options for this battle and the one that was played.
var maneuvers: Array[CardData] = []
var boarding_maneuver: CardData = null
## Remaining player-side death waves the Raven Banner will swallow.
var death_wave_suppressions := 0

var turn := 0
var scrapped_this_turn := false
var shield_wall_active := false
var war_cry_active := false
var captain_forced_exposed := false
var block_reinforcements := false
var surge_active := false
var duel_active := false
var focus_target: Character = null
var next_tactic := ""

var battle_log: Array[String] = []


func log_event(msg: String) -> void:
	battle_log.append("T%d: %s" % [turn, msg])


func fielded(side: Character.Side) -> Array[Character]:
	return player_field if side == Character.Side.PLAYER else enemy_field


func opposing_field(side: Character.Side) -> Array[Character]:
	return enemy_field if side == Character.Side.PLAYER else player_field


func reserve_of(side: Character.Side) -> Array[Character]:
	return player_reserve if side == Character.Side.PLAYER else enemy_reserve


## The enemy captain can be attacked when he has stepped into the line himself
## (the final reinforcement), when their line is thin, or when a card forced a
## window. Routed enemies are off the field, so breaking morale opens the
## window just like killing does. An empty hold behind a full line does NOT
## expose him — he joins the line via reinforcement instead.
func enemy_captain_targetable() -> bool:
	if enemy_captain == null or not enemy_captain.is_alive():
		return false
	if enemy_field.has(enemy_captain):
		return true
	if captain_forced_exposed or duel_active:
		return true
	return enemy_field.size() <= CAPTAIN_EXPOSED_FIELD_SIZE


## True if some living fielded character on `side` is engaged with `target`.
func is_engaged_by(side: Character.Side, target: Character) -> bool:
	for c in fielded(side):
		if c.is_alive() and c.engaged_with == target:
			return true
	return false
