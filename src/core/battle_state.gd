class_name BattleState
extends RefCounted
## All mutable state of one boarding action. Pure data + queries; the rules
## that change it live in CombatEngine.

const HAND_SIZE := 5
## The turn refill deals HAND_SIZE, but cards that draw (Feint) push past it
## mid-turn, so the hand needs a ceiling of its own — both as a rule and so
## the table can be laid out for a known worst case. Room for a full refill
## plus the biggest draw in the set.
const MAX_HAND_SIZE := 7
const MOMENTUM_CAP := 10
const REINFORCE_RATE := 2
const SURGE_REINFORCE_RATE := 4
const DEATH_MORALE_HIT := 2
const ROUT_MORALE_HIT := 1
const RESERVE_COMMIT_COST := 1
## Kills pay double income: sniping the right man is the tempo engine.
## Routs still pay nothing — breaking men is free but earns no momentum.
const KILL_MOMENTUM := 2
## Fielded archers finish and harass; they do not carry. Flat, armor ignored.
const ARCHER_SNIPE_DAMAGE := 2
## The berserker's swing spills onto the target's line-neighbors: flat, never
## armored, but softened and shield-halved like any physical hit.
const CLEAVE_GRAZE_DAMAGE := 2
## The prow pair: when the prowman leaves the field for good the captain
## leaps the rail himself for this price — and if the crew cannot pay,
## panic takes them and the battle is lost outright.
const PAIR_ENTRY_COST := 1
## Enemy wind-up rhythm: the heavy cleave and the aimed double shot fire
## every 3rd enemy fight phase (visible counter 2, 1, 0 — fires at 0).
const WINDUP_PERIOD := 3

## Where everyone stands (docs/lines-redesign.md): 4 columns x 2 lines per
## side. The slots themselves are the fielded cap; the rail bottleneck is the
## crossing rate (Reinforce/Swap/commit), not a standing limit.
var player_formation := Formation.new()
var player_reserve: Array[Character] = []
var player_fled: Array[Character] = []
var player_dead: Array[Character] = []
var player_captain: Character = null
## The captain's alternate (docs/combat-design.md, the prow pair). Null when
## the roster declares no prowman — then the old free-crossing rules hold.
var player_prowman: Character = null

var enemy_formation := Formation.new()
var enemy_reserve: Array[Character] = []
var enemy_routed: Array[Character] = []
var enemy_dead: Array[Character] = []
## Reachable like anyone else once fielded — and he fields himself as the
## final reinforcement, after the hold has emptied.
var enemy_captain: Character = null

var momentum := 0
var deck: Array[CardData] = []
var hand: Array[CardData] = []
var discard: Array[CardData] = []

var artifacts: Array[ArtifactData] = []
## The boarding-maneuver options for this battle and the one that was played.
var maneuvers: Array[CardData] = []
var boarding_maneuver: CardData = null
## Battle-long maneuver effects: arrows from your rail each player fight
## phase (0 = none), and flat damage reduction for your whole side.
var archer_support_damage := 0
var player_armor_bonus := 0
## Remaining player-side death waves the Raven Banner will swallow.
var death_wave_suppressions := 0

var turn := 0
var shield_wall_active := false
var war_cry_active := false
var block_reinforcements := false
var surge_active := false
var focus_target: Character = null
var next_tactic := ""
## Locked marks: enemy archer -> the boarder his aimed double shot is bound
## to. Placed one turn ahead when his counter reaches 0; a mark that dies,
## routs or leaves the field wastes the shot.
var archer_marks := {}

var battle_log: Array[String] = []


func log_event(msg: String) -> void:
	battle_log.append("T%d: %s" % [turn, msg])


func formation_of(side: Character.Side) -> Formation:
	return player_formation if side == Character.Side.PLAYER else enemy_formation


func opposing_formation(side: Character.Side) -> Formation:
	return enemy_formation if side == Character.Side.PLAYER else player_formation


## Snapshot of one side's fielded characters in reading order (front left to
## right, then the second line). Mutations go through the formation itself.
func fielded(side: Character.Side) -> Array[Character]:
	return formation_of(side).fielded()


func reserve_of(side: Character.Side) -> Array[Character]:
	return player_reserve if side == Character.Side.PLAYER else enemy_reserve
