class_name HumanController
extends RefCounted
## The player as a combat-engine controller: every engine decision suspends
## on a signal the battle UI emits when the player clicks. One controller
## per battle; aborting (debug restart) makes every pending and future
## decision resolve instantly so the old engine unwinds and is dropped.

signal action_submitted(action: Dictionary)
signal reaction_submitted(save: bool)
signal maneuver_submitted(card: CardData)

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


func choose_action(state: BattleState) -> Dictionary:
	if aborted:
		return {"op": "retreat"}
	ui.on_player_decision_start(state)
	var action: Dictionary = await action_submitted
	return action


func choose_reaction_save(state: BattleState, dying: Character) -> bool:
	if aborted:
		return false
	ui.on_reaction_prompt(state, dying)
	var save: bool = await reaction_submitted
	return save


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
	action_submitted.emit({"op": "retreat"})
	reaction_submitted.emit(false)
