class_name BattleUI
extends Control
## The boarding-action table (M1): two ship halves with fighter tokens, a
## hand of drag-to-play cards, momentum, enemy intent and the saga log.
## All rules live in CombatEngine — this scene only renders BattleState and
## turns clicks into controller actions.

var engine: CombatEngine
var controller: HumanController
var battle_seed := 1
var roster_source := ""
var _awaiting_action := false
var _log_lines_shown := 0
## The banner line the top bar shows when the board is not asking for a pick.
var _turn_text := "Turn 1"
## The one pick the board is waiting on, or {} — see _begin_pick. Card picks
## (who crosses, who trades places, which way a man is shoved, who a taunted
## defender answers to) and the engine's mandatory movement riders share this
## single mechanism and its gold rim.
##   {"prompt": String, "options": Array[Dictionary], "cancellable": bool,
##    "on_choice": Callable}
## and each option is {"value": Variant} plus either "character" (light up his
## token) or "side"/"line"/"col" (light up that empty slot), with an optional
## "label" the slot prints.
var _pick := {}
## The card currently in the air, so every place it may land lights up.
var _drag_card: CardData = null

var _turn_label: Label
var _intent_title: Label
var _intent_body: Label
var _status_label: Label
var _captain_status: Label
var _enemy_captain_row: HBoxContainer
var _enemy_reserve_list: VBoxContainer
var _enemy_back_row: HBoxContainer
var _enemy_front_row: HBoxContainer
var _player_front_row: HBoxContainer
var _player_back_row: HBoxContainer
var _player_reserve_row: HBoxContainer
const SIDEBAR_WIDTH := 285
const HAND_SEPARATION := 8
## What the board column is given once the margins and the sidebar have taken
## their share of the 1280-wide canvas: 1280 - 2*10 margin - 285 - 10 gap.
const TABLE_WIDTH := 965.0

var _hand_row: HBoxContainer
var _momentum_pips: HBoxContainer
var _momentum_label: Label
var _piles_label: Label
var _end_turn_button: Button
var _retreat_button: Button
var _log_text: RichTextLabel
var _rules_dialog: AcceptDialog
var _retreat_dialog: ConfirmationDialog
var _outcome_layer: Control
var _outcome_title: Label
var _outcome_body: Label
var _outcome_again: Button
var _maneuver_layer: Control
var _maneuver_options: HBoxContainer
var _pick_cancel_button: Button
var _debug_panel: DebugPanel


func _ready() -> void:
	roster_source = RosterText.serialize(Scenarios.default_skirmish())
	_build_layout()
	start_battle()


# --- Battle lifecycle --------------------------------------------------------

func start_battle() -> void:
	if controller != null:
		controller.abort()
	var parsed := RosterText.parse(roster_source)
	if not parsed["errors"].is_empty():
		_debug_panel.show_errors(parsed["errors"])
		return
	_outcome_layer.visible = false
	_maneuver_layer.visible = false
	_log_lines_shown = 0
	_log_text.clear()
	_awaiting_action = false
	_pick = {}
	_drag_card = null
	engine = CombatEngine.new()
	controller = HumanController.new(self)
	engine.setup(parsed["scenario"], controller, battle_seed)
	_log_text.append_text("[color=#c9a227]Seed %d. The ships are lashed together.[/color]\n" % battle_seed)
	_run_battle()


func _run_battle() -> void:
	var my_engine := engine
	var my_controller := controller
	var result: Dictionary = await my_engine.run()
	if my_engine != engine or my_controller.aborted:
		return  # aborted by a restart or exit; result is stale
	refresh(engine.state)
	_show_outcome(result)


## Unwind a parked battle so no suspended coroutine outlives the scene.
func _exit_tree() -> void:
	if controller != null:
		controller.abort()


# --- Controller callbacks (engine is parked awaiting our signals) ------------

func on_maneuver_prompt(state: BattleState, options: Array[CardData]) -> void:
	_turn_text = "The boarding — how do you come over the rail?"
	refresh(state)
	for child in _maneuver_options.get_children():
		child.queue_free()
	for maneuver in options:
		_maneuver_options.add_child(_maneuver_option(maneuver))
	_maneuver_layer.visible = true


func on_player_decision_start(state: BattleState) -> void:
	_awaiting_action = true
	_turn_text = "Turn %d — your move" % state.turn
	refresh(state)


func on_pace(state: BattleState) -> void:
	_turn_text = "Turn %d — steel rings" % state.turn
	refresh(state)


## A played card's rider has come due. The direction is the card's and is
## printed on its face, so there is exactly one thing left to settle and one
## step to settle it in: WHICH man takes it. Every man who can light up; the
## engine already worked out that they can, and a card whose step nobody could
## take never reached here — it was refused before it was paid for. A card
## that names an ally offers one move, which the pick mechanism resolves by
## itself without a click.
func on_rider_prompt(state: BattleState, card: CardData, moves: Array[Dictionary]) -> void:
	refresh(state)
	var options: Array[Dictionary] = []
	for move in moves:
		options.append(_token_option(move["character"], move))
	_begin_pick("%s — %s: which man?" % [card.display_name, CardText.rider_kind(card)],
			options, false, func(move: Dictionary) -> void: _submit_rider(move))


func _submit_rider(move: Dictionary) -> void:
	# Deferred so the engine resumes outside the click callback.
	_emit_rider.call_deferred(move)


func _emit_rider(move: Dictionary) -> void:
	controller.rider_submitted.emit(move)


func submit(action: Dictionary) -> void:
	if not _awaiting_action:
		return
	_awaiting_action = false
	# Deferred so the engine resumes outside input/drag callbacks.
	_emit_action.call_deferred(action)


func _emit_action(action: Dictionary) -> void:
	controller.action_submitted.emit(action)


func _pick_maneuver(card: CardData) -> void:
	if not _maneuver_layer.visible:
		return
	_maneuver_layer.visible = false
	# Deferred so the engine resumes outside the button-pressed callback.
	_emit_maneuver.call_deferred(card)


func _emit_maneuver(card: CardData) -> void:
	controller.maneuver_submitted.emit(card)


# --- Picks: one gold rim for everything the board asks of you ----------------
# Card picks (who comes over, who trades places, which way a man is shoved)
# and the engine's mandatory movement riders share this one mechanism. The
# options always come from the engine; this only lights them up.

## Ask for one choice off the board. A single option answers itself — there
## is nothing to choose — and an empty list means the caller had nothing to
## ask (an impossible rider never gets here; the engine skips it in silence).
func _begin_pick(prompt: String, options: Array[Dictionary], cancellable: bool,
		on_choice: Callable) -> void:
	if options.is_empty():
		return
	if options.size() == 1:
		on_choice.call(options[0]["value"])
		_render()
		return
	_pick = {"prompt": prompt, "options": options, "cancellable": cancellable,
			"on_choice": on_choice}
	_render()


## The player picked. The choice may open the next step of the same chain
## (the man, then where he goes); either way the board is redrawn.
func choose_pick(option: Dictionary) -> void:
	if _pick.is_empty():
		return
	var on_choice: Callable = _pick["on_choice"]
	_pick = {}
	on_choice.call(option["value"])
	_render()


## Backing out of a card that has not been played yet. Movement riders are
## mandatory (docs/lines-redesign.md) and never offer this.
func cancel_pick() -> void:
	if _pick.is_empty() or not _pick.get("cancellable", false):
		return
	_pick = {}
	_render()


func _render() -> void:
	if engine != null:
		refresh(engine.state)


func _token_option(c: Character, value: Variant) -> Dictionary:
	return {"character": c, "value": value}


func _slot_option(side: Character.Side, line: int, col: int, value: Variant,
		label := "here") -> Dictionary:
	return {"character": null, "side": side, "line": line, "col": col,
			"value": value, "label": label}


func _slot_option_at(side: Character.Side, index: int, value: Variant,
		label := "here") -> Dictionary:
	@warning_ignore("integer_division")
	var line := index / Formation.COLUMNS
	return _slot_option(side, line, index % Formation.COLUMNS, value, label)


func _pick_option_for_character(c: Character) -> Dictionary:
	for option: Dictionary in _pick.get("options", []):
		if option.get("character") == c:
			return option
	return {}


func _pick_option_for_slot(side: Character.Side, line: int, col: int) -> Dictionary:
	for option: Dictionary in _pick.get("options", []):
		if option.get("character") == null and option.get("side") == side \
				and option.get("line") == line and option.get("col") == col:
			return option
	return {}


## Is this man lit right now — one of the pending pick's options, or a legal
## landing place for the card in the air?
func _highlighted(c: Character) -> bool:
	if not _pick.is_empty():
		return not _pick_option_for_character(c).is_empty()
	return _drag_card != null and can_drop_card_on(_drag_card, c)


# --- Card drops --------------------------------------------------------------

## Every legality question here goes to the engine; the UI only asks about
## the card's own data (which gesture it wants) and renders the answer.
func can_drop_card_on(card: CardData, target: Character) -> bool:
	if not _ready_for_a_card(card):
		return false
	if card.target_type == CardData.TargetType.NONE:
		# The untargeted cards land on anyone — except those that name a slot.
		return not _card_has(card, CardData.EffectType.REINFORCE) and engine.can_play(card)
	if _card_has(card, CardData.EffectType.SWAP):
		# Swap always leaves here with a partner named, so ask about the play
		# that will actually be submitted rather than the engine's default.
		for partner in engine.swap_partners(target):
			if engine.can_play(card, target, partner):
				return true
		return false
	return engine.can_play(card, target)


## Reinforce names the slot its man lands in, so it drops on empty ground.
func can_drop_card_on_slot(card: CardData, side: Character.Side, line: int, col: int) -> bool:
	if not _ready_for_a_card(card):
		return false
	if side != Character.Side.PLAYER or not _card_has(card, CardData.EffectType.REINFORCE):
		return false
	if engine.state.player_formation.at(line, col) != null:
		return false
	return engine.can_play(card)


func _ready_for_a_card(card: CardData) -> bool:
	return card != null and _awaiting_action and _pick.is_empty() and engine != null


## Does the card carry this effect at all? A question about its own data —
## whether the play is legal is still the engine's to answer.
func _card_has(card: CardData, effect_type: CardData.EffectType) -> bool:
	for effect in card.effects:
		if effect.get("type") == effect_type:
			return true
	return false


func play_card(card: CardData, target: Character) -> void:
	if card.target_type == CardData.TargetType.NONE:
		target = null
	_begin_card_play(card, target, -1)


func play_card_on_slot(card: CardData, slot: int) -> void:
	_begin_card_play(card, null, slot)


## Some cards want one more thing off the board before they are played: who
## comes over the rail, who trades places, which way a man is shoved. Each
## step lights up the engine's own list, and the action is submitted only
## once every pick is in — so cancelling costs nothing.
func _begin_card_play(card: CardData, target: Character, slot: int) -> void:
	var action := {"op": "play", "card": card, "target": target, "slot": slot}
	if _card_has(card, CardData.EffectType.REINFORCE):
		var options: Array[Dictionary] = []
		for c in engine.crossing_candidates():
			options.append(_token_option(c, c))
		_begin_pick("%s — who comes over the rail?" % card.display_name, options, true,
				func(crosser: Character) -> void:
					action["target"] = crosser
					submit(action))
		return
	if _card_has(card, CardData.EffectType.SWAP):
		var options: Array[Dictionary] = []
		for c in engine.swap_partners(target):
			options.append(_token_option(c, c))
		_begin_pick("%s — who trades places with %s?" % [card.display_name, target.display_name],
				options, true,
				func(partner: Character) -> void:
					action["second_target"] = partner
					submit(action))
		return
	if _card_has(card, CardData.EffectType.TAUNT):
		# The shout names two men: the defender it is aimed at (already the
		# drop target) and the man of yours he is dragged across to. The engine
		# says which of your men that could be — never this scene.
		var options: Array[Dictionary] = []
		for c in engine.state.player_formation.fielded():
			if engine.taunt_targets(c).has(target):
				options.append(_token_option(c, c))
		_begin_pick("%s — who does %s answer to?" % [card.display_name, target.display_name],
				options, true,
				func(anchor: Character) -> void:
					action["second_target"] = anchor
					submit(action))
		return
	if _card_has(card, CardData.EffectType.SHOVE):
		var options: Array[Dictionary] = []
		var col := engine.state.enemy_formation.column_of(target)
		for dir: int in engine.shove_directions(target):
			options.append(_slot_option(Character.Side.ENEMY, Formation.FRONT, col + dir,
					dir, "larboard" if dir < 0 else "starboard"))
		_begin_pick("%s — which way is %s shoved?" % [card.display_name, target.display_name],
				options, true,
				func(dir: int) -> void:
					action["direction"] = dir
					submit(action))
		return
	submit(action)


## Cards with no target can be dropped anywhere on the table.
func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.has("card")):
		return false
	var card: CardData = data["card"]
	return card.target_type == CardData.TargetType.NONE \
			and not _card_has(card, CardData.EffectType.REINFORCE) \
			and _ready_for_a_card(card) and engine.can_play(card)


func _drop_data(_at: Vector2, data: Variant) -> void:
	play_card(data["card"], null)


## The whole board answers a card leaving the hand: every man and every slot
## that could take it lights up until the drag ends.
func on_card_drag_started(card: CardData) -> void:
	_drag_card = card
	_render()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _drag_card != null:
		_drag_card = null
		_render()


func _on_token_clicked(character: Character) -> void:
	if not _pick.is_empty():
		var option := _pick_option_for_character(character)
		if not option.is_empty():
			choose_pick(option)
		return
	if not _awaiting_action:
		return
	# The waiting half of the prow pair has exactly one way onto the deck:
	# clicking him plays the Swap that trades him for his counterpart.
	var swap_card := _pair_swap_card(character)
	if swap_card != null:
		submit({"op": "play", "card": swap_card,
				"target": engine.pair_swap_counterpart(character),
				"second_target": character})
		return
	if engine.can_commit(character):
		_begin_commit(character)


## Where a committed man takes his place: every free slot lights up.
func _begin_commit(character: Character) -> void:
	var options: Array[Dictionary] = []
	for index in engine.state.player_formation.free_indices():
		options.append(_slot_option_at(Character.Side.PLAYER, index, index))
	_begin_pick("%s comes over for %d momentum — into which slot?" %
			[character.display_name, BattleState.RESERVE_COMMIT_COST], options, true,
			func(index: int) -> void:
				submit({"op": "commit", "character": character, "slot": index}))


## The Swap in hand that would bring this waiting pair member across right
## now — the engine rules on the play, we only find the card.
func _pair_swap_card(waiting: Character) -> CardData:
	if engine == null:
		return null
	var counterpart := engine.pair_swap_counterpart(waiting)
	if counterpart == null:
		return null
	for card in engine.state.hand:
		if _card_has(card, CardData.EffectType.SWAP) \
				and engine.can_play(card, counterpart, waiting):
			return card
	return null


# --- Rendering ---------------------------------------------------------------

func refresh(state: BattleState) -> void:
	# One forecast per refresh: every token shows what it stands to take.
	var forecast := engine.forecast()
	_fill_enemy_reserve(state)
	_fill_line(_enemy_back_row, state.enemy_formation, Character.Side.ENEMY,
			Formation.BACK, forecast)
	_fill_line(_enemy_front_row, state.enemy_formation, Character.Side.ENEMY,
			Formation.FRONT, forecast)
	_fill_line(_player_front_row, state.player_formation, Character.Side.PLAYER,
			Formation.FRONT, forecast)
	_fill_line(_player_back_row, state.player_formation, Character.Side.PLAYER,
			Formation.BACK, forecast)
	_fill_player_reserve(state)
	_refresh_enemy_captain(state)
	# Never rebuild the hand while a card is in the air: freeing the view
	# being dragged would cancel the gesture under the player's hand.
	if _drag_card == null:
		_refresh_hand(state)
	_refresh_hud(state)
	_refresh_log(state)


## One line of a formation as 4 fixed columns: a token where a man stands,
## a placeholder where the slot is empty (so misses read spatially) — and
## that placeholder lights up when the board wants a pick there.
func _fill_line(row: HBoxContainer, formation: Formation, side: Character.Side,
		line: int, forecast: Dictionary) -> void:
	for child in row.get_children():
		child.queue_free()
	for col in Formation.COLUMNS:
		var c := formation.at(line, col)
		if c != null:
			var display := {"highlight": _highlighted(c)}
			var token := CharacterToken.create(c, self, false, forecast.get(c, {}),
					engine.state.archer_marks.values().has(c), display)
			token.clicked.connect(_on_token_clicked)
			row.add_child(token)
		else:
			row.add_child(_empty_slot(side, line, col))


func _empty_slot(side: Character.Side, line: int, col: int) -> Control:
	var droppable := _drag_card != null and can_drop_card_on_slot(_drag_card, side, line, col)
	return SlotPanel.create(self, side, line, col, _pick_option_for_slot(side, line, col),
			droppable)


## Your own ship's rail. A man who can be sent over is bright and clickable;
## the prow pair's waiting half never can be (docs/combat-design.md — captain
## and prowman are alternates), so he is dimmed instead of eating a dead
## click, and carries the one move he does have: the trade with the
## counterpart holding the field.
func _fill_player_reserve(state: BattleState) -> void:
	for child in _player_reserve_row.get_children():
		child.queue_free()
	for c in state.player_reserve:
		var display := {"highlight": _highlighted(c)}
		var counterpart := engine.pair_swap_counterpart(c)
		if counterpart != null:
			var ready := _pair_swap_card(c) != null
			display["dim"] = true
			display["hint_lit"] = ready
			display["hint"] = "click: swap" if ready else "swap only"
			display["note"] = "Never crosses by himself: Swap trades him with %s." \
					% counterpart.display_name
		elif not engine.can_commit(c):
			display["dim"] = true
		var token := CharacterToken.create(c, self, true, {}, false, display)
		token.clicked.connect(_on_token_clicked)
		_player_reserve_row.add_child(token)


func _fill_enemy_reserve(state: BattleState) -> void:
	for child in _enemy_reserve_list.get_children():
		child.queue_free()
	if state.enemy_reserve.is_empty():
		_enemy_reserve_list.add_child(UIPalette.label("empty — their captain stands alone",
				UIPalette.FONT_SMALL, UIPalette.GOLD))
		return
	for c in state.enemy_reserve:
		var chip := "%s — %d HP · %s" % [c.display_name, c.hp, c.weapon.display_name]
		if c.is_berserker:
			chip += " · berserker"
		if c.is_shieldman:
			chip += " · shieldman"
		var chip_label := UIPalette.label(chip, UIPalette.FONT_SMALL, UIPalette.PARCHMENT_DIM)
		# Ellipsize instead of widening the sidebar past the canvas edge.
		chip_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		chip_label.tooltip_text = chip
		chip_label.mouse_filter = Control.MOUSE_FILTER_STOP
		_enemy_reserve_list.add_child(chip_label)


func _refresh_enemy_captain(state: BattleState) -> void:
	for child in _enemy_captain_row.get_children():
		child.queue_free()
	var fielded := state.enemy_captain != null \
			and state.enemy_formation.has(state.enemy_captain)
	if state.enemy_captain != null and not fielded and state.enemy_captain.is_alive():
		# Off the board he waits by his stern post; fielded, he stands in the grid.
		_enemy_captain_row.add_child(CharacterToken.create(state.enemy_captain, self, true))
	if state.enemy_captain == null or not state.enemy_captain.is_alive():
		_captain_status.text = "fallen"
		_captain_status.add_theme_color_override("font_color", UIPalette.BLOOD)
	elif fielded:
		_captain_status.text = "IN THE LINE — reach him through his column!"
		_captain_status.add_theme_color_override("font_color", UIPalette.GOLD)
	else:
		_captain_status.text = "commands from the stern — he steps in\nhimself once his hold is empty"
		_captain_status.add_theme_color_override("font_color", UIPalette.PARCHMENT_DIM)
	var tactic := state.next_tactic
	_intent_title.text = "Next: " + CardText.tactic_name(tactic)
	_intent_body.text = CardText.tactic_description(tactic)


func _refresh_hand(state: BattleState) -> void:
	for child in _hand_row.get_children():
		child.queue_free()
	# A Feint can take the hand past the turn's five, so the faces narrow to
	# whatever fits rather than the row growing wider than the table.
	var card_width := CardView.width_for(state.hand.size(), TABLE_WIDTH, HAND_SEPARATION)
	for card in state.hand:
		var affordable := _affordable(card)
		var draggable := _awaiting_action and _pick.is_empty() and affordable
		var view := CardView.create(card, self, draggable, affordable, card_width)
		_hand_row.add_child(view)


## Enough momentum in the bank for this card — what dims a card face. Whether
## it can actually be played (and on whom) is engine.can_play's answer.
func _affordable(card: CardData) -> bool:
	return card.playable and card.cost <= engine.state.momentum


func _refresh_hud(state: BattleState) -> void:
	var picking := not _pick.is_empty()
	# The banner doubles as the prompt line: while the board is asking for a
	# pick it says which card asked and what it wants.
	_turn_label.text = _pick["prompt"] if picking else _turn_text
	_turn_label.add_theme_color_override("font_color",
			UIPalette.GOLD if picking else UIPalette.PARCHMENT)
	_pick_cancel_button.visible = picking and _pick.get("cancellable", false)
	_momentum_label.text = "Momentum %d/%d" % [state.momentum, BattleState.MOMENTUM_CAP]
	for i in _momentum_pips.get_child_count():
		var pip: ColorRect = _momentum_pips.get_child(i)
		pip.color = UIPalette.GOLD if i < state.momentum else UIPalette.SEA_LIGHT
	_piles_label.text = "Deck %d · Discard %d" % [state.deck.size(), state.discard.size()]
	_end_turn_button.disabled = not _awaiting_action or picking
	_retreat_button.disabled = not _awaiting_action or picking
	_status_label.text = " · ".join(_active_effects(state))


func _active_effects(state: BattleState) -> Array[String]:
	var chips: Array[String] = []
	if state.shield_wall_active:
		chips.append("Shield Wall up")
	if state.focus_target != null and state.focus_target.is_alive():
		chips.append("Focus: " + state.focus_target.display_name)
	if state.block_reinforcements:
		chips.append("Rail held — no reinforcements")
	if state.war_cry_active:
		chips.append("War Cry — kills pay double")
	if state.surge_active:
		chips.append("Enemy surge!")
	if state.archer_support_damage > 0:
		chips.append("Archers on the rail")
	if state.player_armor_bonus > 0:
		chips.append("Careful advance — hits softened")
	return chips


func _refresh_log(state: BattleState) -> void:
	while _log_lines_shown < state.battle_log.size():
		var line := state.battle_log[_log_lines_shown]
		_log_lines_shown += 1
		_log_text.append_text("[color=#e8d8b0]%s[/color]\n" % line.replace("[", "[lb]"))


func _show_outcome(result: Dictionary) -> void:
	var titles := {
		"VICTORY": "VICTORY",
		"DEFEAT": "THE CAPTAIN FALLS",
		"RETREAT": "RETREAT",
		"STALEMATE": "STALEMATE",
	}
	var flavor := {
		"VICTORY": "The enemy crew throws down its arms. The ship is yours.",
		"DEFEAT": "Without its captain the raid is over.",
		"RETREAT": "You cut the ropes and live to raid again.",
		"STALEMATE": "Both crews stand bloodied at the rail. Nothing is settled.",
	}
	_outcome_title.text = titles.get(result["outcome"], result["outcome"])
	var body := "%s\n\nTurns: %d\nCrew dead: %d · fled: %d · standing: %d\nEnemies slain: %d · routed: %d" % [
			flavor.get(result["outcome"], ""), result["turns"], result["player_dead"],
			result["player_fled"], result["player_survivors"],
			result["enemy_dead"], result["enemy_routed"]]
	# The butcher's bill by name: crew is permanent once the raid loop lands,
	# so the outcome screen already treats every death as a lasting loss.
	if not engine.state.player_dead.is_empty():
		var fallen: Array[String] = []
		for c: Character in engine.state.player_dead:
			fallen.append(c.display_name)
		body += "\n\nThe fallen: %s." % ", ".join(fallen)
	if not engine.state.player_fled.is_empty():
		var fled: Array[String] = []
		for c: Character in engine.state.player_fled:
			fled.append(c.display_name)
		body += "\nFled, shaken: %s." % ", ".join(fled)
	_outcome_body.text = body
	_outcome_again.text = "Fight again (seed %d)" % battle_seed
	_outcome_layer.visible = true


# --- Layout ------------------------------------------------------------------

func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UIPalette.SEA_DARK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(margin)

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 10)
	main.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(main)

	var table := VBoxContainer.new()
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("separation", 6)
	table.mouse_filter = Control.MOUSE_FILTER_PASS
	main.add_child(table)

	table.add_child(_build_top_bar())
	table.add_child(_build_enemy_zone())
	var rail := ColorRect.new()
	rail.color = UIPalette.GOLD
	rail.custom_minimum_size.y = 3
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	table.add_child(rail)
	table.add_child(_build_player_zone())
	table.add_child(_build_bottom_strip())
	main.add_child(_build_log_panel())

	_build_dialogs()
	_build_outcome_layer()
	_build_maneuver_layer()
	_debug_panel = DebugPanel.create(self)
	add_child(_debug_panel)


func _build_top_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	_turn_label = UIPalette.label("Turn 1", UIPalette.FONT_TITLE, UIPalette.PARCHMENT)
	_turn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_turn_label)
	_status_label = UIPalette.label("", UIPalette.FONT_BODY, UIPalette.GOLD)
	bar.add_child(_status_label)
	# Only card picks may be backed out of; a movement rider never shows this.
	_pick_cancel_button = Button.new()
	_pick_cancel_button.text = "Cancel"
	_pick_cancel_button.visible = false
	_pick_cancel_button.pressed.connect(cancel_pick)
	bar.add_child(_pick_cancel_button)
	var rules := Button.new()
	rules.text = "How it works"
	rules.pressed.connect(func() -> void: _rules_dialog.popup_centered())
	bar.add_child(rules)
	var debug := Button.new()
	debug.text = "Debug"
	debug.pressed.connect(func() -> void: _debug_panel.visible = not _debug_panel.visible)
	bar.add_child(debug)
	return bar


func _build_enemy_zone() -> Control:
	var zone := PanelContainer.new()
	zone.add_theme_stylebox_override("panel", UIPalette.panel(UIPalette.IRON_DARK.darkened(0.2)))
	zone.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	zone.add_child(box)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	top.mouse_filter = Control.MOUSE_FILTER_PASS
	_enemy_captain_row = HBoxContainer.new()
	_enemy_captain_row.mouse_filter = Control.MOUSE_FILTER_PASS
	top.add_child(_enemy_captain_row)
	_captain_status = UIPalette.label("", UIPalette.FONT_SMALL, UIPalette.PARCHMENT_DIM)
	_captain_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_captain_status)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_PASS
	top.add_child(spacer)
	var intent := VBoxContainer.new()
	intent.mouse_filter = Control.MOUSE_FILTER_PASS
	_intent_title = UIPalette.label("", UIPalette.FONT_BODY, UIPalette.BLOOD.lightened(0.35))
	intent.add_child(_intent_title)
	_intent_body = UIPalette.label("", UIPalette.FONT_SMALL, UIPalette.PARCHMENT_DIM)
	intent.add_child(_intent_body)
	top.add_child(intent)
	box.add_child(top)

	_enemy_back_row = _formation_row()
	box.add_child(_enemy_back_row)
	_enemy_front_row = _formation_row()
	box.add_child(_enemy_front_row)
	return zone


## A formation line: 4 fixed columns so the same column always lines up
## vertically with the opposing line it duels.
func _formation_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size.y = 100
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	return row


func _build_player_zone() -> Control:
	var zone := PanelContainer.new()
	zone.add_theme_stylebox_override("panel", UIPalette.panel(UIPalette.SEA.darkened(0.25)))
	zone.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	zone.add_child(box)

	_player_front_row = _formation_row()
	box.add_child(_player_front_row)
	_player_back_row = _formation_row()
	box.add_child(_player_back_row)

	var reserve_bar := HBoxContainer.new()
	reserve_bar.add_theme_constant_override("separation", 12)
	reserve_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	var hint := UIPalette.label(
			"Your ship — click a man to commit him (%d momentum), then pick his slot. A dimmed man cannot cross. The reserve never fights, is never hit."
			% BattleState.RESERVE_COMMIT_COST, UIPalette.FONT_SMALL, UIPalette.PARCHMENT_DIM)
	# Wrapped, not one long line: an unwrapped label here forces the whole
	# table wider than the reference canvas and shoves the sidebar off it.
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 180
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reserve_bar.add_child(hint)
	_player_reserve_row = HBoxContainer.new()
	_player_reserve_row.add_theme_constant_override("separation", 4)
	_player_reserve_row.mouse_filter = Control.MOUSE_FILTER_PASS
	reserve_bar.add_child(_player_reserve_row)
	box.add_child(reserve_bar)
	return zone


## The hand owns the whole bottom row of the table: five card faces need
## the full width, so momentum and the turn buttons live in the sidebar.
## The vertical budget of the reference canvas is the scarce thing — the
## stretch mode scales whatever fits it into any window.
func _build_bottom_strip() -> Control:
	_hand_row = HBoxContainer.new()
	_hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_row.add_theme_constant_override("separation", HAND_SEPARATION)
	_hand_row.custom_minimum_size.y = CardView.CARD_SIZE.y
	_hand_row.mouse_filter = Control.MOUSE_FILTER_PASS
	return _hand_row


func _build_log_panel() -> Control:
	# The sidebar is a FIXED column. It sits beside the board, so anything
	# that widens it — a long log line, one more chip in the enemy reserve —
	# narrows the table and re-centres every formation row. That is how the
	# board used to slide sideways the instant a card was picked up, leaving
	# a drop aimed at a slot to land in the gap beside it. A plain Control
	# does not take its width from its children, so nothing in here can move
	# the board.
	var column := Control.new()
	column.custom_minimum_size.x = SIDEBAR_WIDTH
	column.clip_contents = true
	column.mouse_filter = Control.MOUSE_FILTER_PASS

	var sidebar := VBoxContainer.new()
	sidebar.set_anchors_preset(Control.PRESET_FULL_RECT)
	sidebar.add_theme_constant_override("separation", 6)
	sidebar.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(sidebar)

	var reserve_panel := PanelContainer.new()
	reserve_panel.add_theme_stylebox_override("panel", UIPalette.panel(UIPalette.IRON_DARK.darkened(0.2)))
	reserve_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var reserve_box := VBoxContainer.new()
	reserve_box.mouse_filter = Control.MOUSE_FILTER_PASS
	reserve_box.add_child(UIPalette.label("Enemy reserve — %d board per turn" % BattleState.REINFORCE_RATE,
			UIPalette.FONT_BODY, UIPalette.PARCHMENT_DIM))
	_enemy_reserve_list = VBoxContainer.new()
	_enemy_reserve_list.add_theme_constant_override("separation", 1)
	_enemy_reserve_list.mouse_filter = Control.MOUSE_FILTER_PASS
	reserve_box.add_child(_enemy_reserve_list)
	reserve_panel.add_child(reserve_box)
	sidebar.add_child(reserve_panel)

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UIPalette.panel(UIPalette.SEA.darkened(0.35)))
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(box)
	box.add_child(UIPalette.label("The saga so far", UIPalette.FONT_BODY, UIPalette.GOLD))
	_log_text = RichTextLabel.new()
	_log_text.bbcode_enabled = true
	_log_text.scroll_following = true
	_log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_text.add_theme_font_size_override("normal_font_size", UIPalette.FONT_SMALL)
	box.add_child(_log_text)
	sidebar.add_child(panel)

	# Momentum and the turn buttons live at the foot of the sidebar: a full
	# hand of five cards owns the entire bottom strip, so neither can sit
	# beside it without pushing this very sidebar off the canvas.
	var momentum_box := VBoxContainer.new()
	momentum_box.mouse_filter = Control.MOUSE_FILTER_PASS
	_momentum_label = UIPalette.label("Momentum 0/10", UIPalette.FONT_BODY, UIPalette.GOLD)
	momentum_box.add_child(_momentum_label)
	_momentum_pips = HBoxContainer.new()
	_momentum_pips.add_theme_constant_override("separation", 3)
	_momentum_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in BattleState.MOMENTUM_CAP:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(14, 14)
		pip.color = UIPalette.SEA_LIGHT
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_momentum_pips.add_child(pip)
	momentum_box.add_child(_momentum_pips)
	_piles_label = UIPalette.label("", UIPalette.FONT_SMALL, UIPalette.PARCHMENT_DIM)
	momentum_box.add_child(_piles_label)
	sidebar.add_child(momentum_box)

	_end_turn_button = Button.new()
	_end_turn_button.text = "End Turn — let them fight"
	_end_turn_button.custom_minimum_size = Vector2(0, 40)
	_end_turn_button.pressed.connect(func() -> void: submit({"op": "end"}))
	sidebar.add_child(_end_turn_button)
	_retreat_button = Button.new()
	_retreat_button.text = "Retreat"
	_retreat_button.pressed.connect(func() -> void: _retreat_dialog.popup_centered())
	sidebar.add_child(_retreat_button)
	return column


func _build_dialogs() -> void:
	_retreat_dialog = ConfirmationDialog.new()
	_retreat_dialog.title = "Cut the ropes?"
	_retreat_dialog.dialog_text = "Fall back to the ship and end the raid?\nEveryone still standing gets out."
	_retreat_dialog.ok_button_text = "Retreat"
	_retreat_dialog.confirmed.connect(func() -> void: submit({"op": "retreat"}))
	add_child(_retreat_dialog)

	_rules_dialog = AcceptDialog.new()
	_rules_dialog.title = "How the boarding action works"
	var rules_text := RichTextLabel.new()
	rules_text.bbcode_enabled = true
	rules_text.text = CardText.rules_summary()
	rules_text.custom_minimum_size = Vector2(520, 420)
	_rules_dialog.add_child(rules_text)
	add_child(_rules_dialog)


func _build_outcome_layer() -> void:
	_outcome_layer = Control.new()
	_outcome_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_outcome_layer.visible = false
	add_child(_outcome_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_outcome_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_outcome_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIPalette.panel(UIPalette.SEA, UIPalette.GOLD, 2, 10))
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_outcome_title = UIPalette.label("", 26, UIPalette.GOLD)
	_outcome_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_outcome_title)
	_outcome_body = UIPalette.label("", UIPalette.FONT_BODY, UIPalette.PARCHMENT)
	_outcome_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# The butcher's bill lists names; wrap rather than outgrow the canvas.
	_outcome_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_outcome_body.custom_minimum_size.x = 520
	box.add_child(_outcome_body)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	_outcome_again = Button.new()
	_outcome_again.pressed.connect(start_battle)
	buttons.add_child(_outcome_again)
	var new_seed := Button.new()
	new_seed.text = "New seed"
	new_seed.pressed.connect(func() -> void:
		battle_seed += 1
		_debug_panel.sync_seed(battle_seed)
		start_battle())
	buttons.add_child(new_seed)
	box.add_child(buttons)


## The boarding maneuver is chosen before turn 1 on a modal layer: one panel
## per maneuver, whole battle visible dimmed behind it. Options are rebuilt
## from the engine's list each battle, so unlocking maneuvers later is free.
func _build_maneuver_layer() -> void:
	_maneuver_layer = Control.new()
	_maneuver_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_maneuver_layer.visible = false
	add_child(_maneuver_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_maneuver_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_maneuver_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIPalette.panel(UIPalette.SEA, UIPalette.GOLD, 2, 10))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := UIPalette.label("How do you come over the rail?", 26, UIPalette.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle := UIPalette.label(
			"The maneuver sets your opening surge — and how the whole battle plays.",
			UIPalette.FONT_BODY, UIPalette.PARCHMENT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	_maneuver_options = HBoxContainer.new()
	_maneuver_options.alignment = BoxContainer.ALIGNMENT_CENTER
	_maneuver_options.add_theme_constant_override("separation", 10)
	box.add_child(_maneuver_options)


func _maneuver_option(maneuver: CardData) -> Control:
	var option := PanelContainer.new()
	var style := UIPalette.panel(UIPalette.PARCHMENT, UIPalette.GOLD, 2, 8)
	style.set_content_margin_all(10)
	option.add_theme_stylebox_override("panel", style)
	option.custom_minimum_size = Vector2(230, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	option.add_child(box)
	var name_label := UIPalette.label(maneuver.display_name, UIPalette.FONT_TITLE, UIPalette.SEA_DARK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_label)
	var body := UIPalette.label(CardText.describe(maneuver), UIPalette.FONT_SMALL,
			UIPalette.SEA_DARK.lightened(0.12))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	var choose := Button.new()
	choose.text = "Board this way"
	choose.pressed.connect(func() -> void: _pick_maneuver(maneuver))
	box.add_child(choose)
	# The smoke test finds options by id and presses their button.
	option.set_meta("maneuver_id", maneuver.id)
	option.set_meta("button", choose)
	return option


