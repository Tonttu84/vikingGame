class_name HumanController
extends RefCounted
## The player as a combat-engine controller: every engine decision suspends
## on a signal the battle UI emits when the player clicks. Death saves fire
## automatically in the engine, so the decisions here are the boarding
## maneuver, the turn's actions, and a played card's movement rider. One
## controller per battle; aborting (debug restart) makes every pending and
## future decision resolve instantly so the old engine unwinds and is
## dropped.

signal action_submitted(action: Dictionary)
signal maneuver_submitted(card: CardData)
signal rider_submitted(move: Dictionary)

const PACE_SECONDS := 0.3

var ui: Control  ## the BattleUI node; Nodes are not RefCounted, no cycle
var aborted := false


func _init(p_ui: Control) -> void:
	ui = p_ui


func choose_maneuver(state: BattleState, options: Array[CardData]) -> CardData:
	if aborted:
		return options[0]
	ui.on_maneuver_prompt(state, options)
	var choice: CardData = await maneuver_submitted
	return choice


## A played card's movement rider: the engine has already worked out every
## legal move and one of them MUST be taken (docs/lines-redesign.md, riders
## are mandatory), so this asks which — there is no skip and no cancel. The
## board lights up the engine's list; an empty answer (an aborted battle)
## falls back to the engine's own first move.
func choose_rider(state: BattleState, card: CardData,
		moves: Array[Dictionary]) -> Dictionary:
	if aborted:
		return moves[0]
	ui.on_rider_prompt(state, card, moves)
	var move: Dictionary = await rider_submitted
	return move if not move.is_empty() else moves[0]


func choose_action(state: BattleState) -> Dictionary:
	if aborted:
		return {"op": "retreat"}
	ui.on_player_decision_start(state)
	var action: Dictionary = await action_submitted
	return action


func pace(state: BattleState) -> void:
	if aborted:
		return
	ui.on_pace(state)
	await ui.get_tree().create_timer(PACE_SECONDS).timeout


## Unblocks whatever the engine is parked on; the retreat/false answers end
## the old battle, whose result the UI then discards as stale.
func abort() -> void:
	if aborted:
		return
	aborted = true
	maneuver_submitted.emit(null)  # engine falls back to the first maneuver
	rider_submitted.emit({})       # ... and to the first legal rider move
	action_submitted.emit({"op": "retreat"})
