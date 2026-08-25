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

var _turn_label: Label
var _intent_title: Label
var _intent_body: Label
var _status_label: Label
var _captain_status: Label
var _enemy_captain_row: HBoxContainer
var _enemy_reserve_list: VBoxContainer
var _enemy_field_row: HBoxContainer
var _player_field_row: HBoxContainer
var _player_reserve_row: HBoxContainer
var _hand_row: HBoxContainer
var _momentum_pips: HBoxContainer
var _momentum_label: Label
var _piles_label: Label
var _scrap_zone: PanelContainer
var _scrap_label: Label
var _end_turn_button: Button
var _retreat_button: Button
var _log_text: RichTextLabel
var _reaction_dialog: ConfirmationDialog
var _rules_dialog: AcceptDialog
var _retreat_dialog: ConfirmationDialog
var _outcome_layer: Control
var _outcome_title: Label
var _outcome_body: Label
var _outcome_again: Button
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
	_log_lines_shown = 0
	_log_text.clear()
	_awaiting_action = false
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

func on_player_decision_start(state: BattleState) -> void:
	_awaiting_action = true
	_turn_label.text = "Turn %d — your move" % state.turn
	refresh(state)


func on_pace(state: BattleState) -> void:
	_turn_label.text = "Turn %d — steel rings" % state.turn
	refresh(state)


func on_reaction_prompt(state: BattleState, dying: Character) -> void:
	refresh(state)
	_reaction_dialog.dialog_text = (
			"%s is about to fall!\n\nPlay Drag Him Back! (1 momentum, %d left) " +
			"to pull them out at 1 HP?") % [dying.display_name, state.momentum]
	_reaction_dialog.popup_centered()


func submit(action: Dictionary) -> void:
	if not _awaiting_action:
		return
	_awaiting_action = false
	# Deferred so the engine resumes outside input/drag callbacks.
	_emit_action.call_deferred(action)


func _emit_action(action: Dictionary) -> void:
	controller.action_submitted.emit(action)


# --- Card drops --------------------------------------------------------------

func can_drop_card_on(card: CardData, target: Character) -> bool:
	if not _awaiting_action or not _can_pay(card):
		return false
	match card.target_type:
		CardData.TargetType.NONE:
			return true  # a token is as good a place as any to drop it
		CardData.TargetType.ENEMY:
			return _valid_enemy_target(target)
		CardData.TargetType.ALLY:
			return _valid_ally_target(card, target)
	return false


func play_card(card: CardData, target: Character) -> void:
	if card.target_type == CardData.TargetType.NONE:
		target = null
	submit({"op": "play", "card": card, "target": target})


func _can_pay(card: CardData) -> bool:
	return card.playable and card.cost <= engine.state.momentum


func _valid_enemy_target(c: Character) -> bool:
	if c.side != Character.Side.ENEMY or not c.is_alive():
		return false
	if c == engine.state.enemy_captain:
		return engine.state.enemy_captain_targetable()
	return engine.state.enemy_field.has(c)


func _valid_ally_target(card: CardData, c: Character) -> bool:
	if c.side != Character.Side.PLAYER or not c.is_alive():
		return false
	for effect in card.effects:
		match effect.get("type"):
			CardData.EffectType.PULL_TO_RESERVE:
				if not engine.state.player_field.has(c) or c.is_captain:
					return false
			CardData.EffectType.EXTRA_ATTACK:
				# Must be somewhere it can actually swing from.
				if not engine.state.player_field.has(c) \
						and not (c.weapon.kind == Weapon.Kind.BOW and engine.state.player_reserve.has(c)):
					return false
	return true


## Cards with no target can be dropped anywhere on the table.
func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("card") \
			and data["card"].target_type == CardData.TargetType.NONE \
			and _awaiting_action and _can_pay(data["card"])


func _drop_data(_at: Vector2, data: Variant) -> void:
	play_card(data["card"], null)


func _on_token_clicked(character: Character) -> void:
	if not _awaiting_action:
		return
	if engine.state.player_reserve.has(character) \
			and engine.state.momentum >= BattleState.RESERVE_COMMIT_COST:
		submit({"op": "commit", "character": character})


# --- Rendering ---------------------------------------------------------------

func refresh(state: BattleState) -> void:
	_fill_enemy_reserve(state)
	_fill_row(_enemy_field_row, state.enemy_field, false)
	_fill_row(_player_field_row, state.player_field, false)
	_fill_row(_player_reserve_row, state.player_reserve, true)
	_refresh_enemy_captain(state)
	_refresh_hand(state)
	_refresh_hud(state)
	_refresh_log(state)


func _fill_row(row: HBoxContainer, characters: Array[Character], compact: bool) -> void:
	for child in row.get_children():
		child.queue_free()
	for c in characters:
		var token := CharacterToken.create(c, self, compact)
		token.clicked.connect(_on_token_clicked)
		row.add_child(token)


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
		_enemy_reserve_list.add_child(UIPalette.label(chip, UIPalette.FONT_SMALL, UIPalette.PARCHMENT_DIM))


func _refresh_enemy_captain(state: BattleState) -> void:
	for child in _enemy_captain_row.get_children():
		child.queue_free()
	if state.enemy_captain != null:
		_enemy_captain_row.add_child(CharacterToken.create(state.enemy_captain, self, false))
	if state.enemy_captain == null or not state.enemy_captain.is_alive():
		_captain_status.text = "fallen"
		_captain_status.add_theme_color_override("font_color", UIPalette.BLOOD)
	elif state.enemy_captain_targetable():
		_captain_status.text = "EXPOSED — take him!"
		_captain_status.add_theme_color_override("font_color", UIPalette.GOLD)
	else:
		_captain_status.text = "sheltered behind his line\n(thin it to %d or empty his reserve)" \
				% BattleState.CAPTAIN_EXPOSED_FIELD_SIZE
		_captain_status.add_theme_color_override("font_color", UIPalette.PARCHMENT_DIM)
	var tactic := state.next_tactic
	_intent_title.text = "Next: " + CardText.tactic_name(tactic)
	_intent_body.text = CardText.tactic_description(tactic)


func _refresh_hand(state: BattleState) -> void:
	for child in _hand_row.get_children():
		child.queue_free()
	for card in state.hand:
		var affordable := _can_pay(card)
		var can_scrap := not state.scrapped_this_turn
		var view := CardView.create(card, self, _awaiting_action and (affordable or can_scrap), affordable)
		_hand_row.add_child(view)


func _refresh_hud(state: BattleState) -> void:
	_momentum_label.text = "Momentum %d/%d" % [state.momentum, BattleState.MOMENTUM_CAP]
	for i in _momentum_pips.get_child_count():
		var pip: ColorRect = _momentum_pips.get_child(i)
		pip.color = UIPalette.GOLD if i < state.momentum else UIPalette.SEA_LIGHT
	_piles_label.text = "Deck %d · Discard %d" % [state.deck.size(), state.discard.size()]
	_scrap_label.text = "Scrap pile\n(drop a card: +momentum)" if not state.scrapped_this_turn \
			else "Scrap pile\n(spent this turn)"
	_end_turn_button.disabled = not _awaiting_action
	_retreat_button.disabled = not _awaiting_action
	_status_label.text = " · ".join(_active_effects(state))


func _active_effects(state: BattleState) -> Array[String]:
	var chips: Array[String] = []
	if state.shield_wall_active:
		chips.append("Shield Wall up")
	if state.duel_active:
		chips.append("DUEL — captains only")
	if state.focus_target != null and state.focus_target.is_alive():
		chips.append("Focus: " + state.focus_target.display_name)
	if state.captain_forced_exposed:
		chips.append("Enemy captain exposed")
	if state.block_reinforcements:
		chips.append("Rail held — no reinforcements")
	if state.war_cry_active:
		chips.append("War Cry — kills pay double")
	if state.surge_active:
		chips.append("Enemy surge!")
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
	_outcome_body.text = "%s\n\nTurns: %d\nCrew dead: %d · fled: %d · standing: %d\nEnemies slain: %d · routed: %d" % [
			flavor.get(result["outcome"], ""), result["turns"], result["player_dead"],
			result["player_fled"], result["player_survivors"],
			result["enemy_dead"], result["enemy_routed"]]
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
	table.add_child(_build_hud())
	table.add_child(_build_hand_area())
	main.add_child(_build_log_panel())

	_build_dialogs()
	_build_outcome_layer()
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

	_enemy_field_row = HBoxContainer.new()
	_enemy_field_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_enemy_field_row.add_theme_constant_override("separation", 8)
	_enemy_field_row.custom_minimum_size.y = 100
	_enemy_field_row.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_enemy_field_row)
	return zone


func _build_player_zone() -> Control:
	var zone := PanelContainer.new()
	zone.add_theme_stylebox_override("panel", UIPalette.panel(UIPalette.SEA.darkened(0.25)))
	zone.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	zone.add_child(box)

	_player_field_row = HBoxContainer.new()
	_player_field_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_player_field_row.add_theme_constant_override("separation", 8)
	_player_field_row.custom_minimum_size.y = 100
	_player_field_row.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_player_field_row)

	var reserve_bar := HBoxContainer.new()
	reserve_bar.add_theme_constant_override("separation", 12)
	reserve_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	reserve_bar.add_child(UIPalette.label("Your reserve — click to commit (%d momentum). Bows shoot from here."
			% BattleState.RESERVE_COMMIT_COST, UIPalette.FONT_SMALL, UIPalette.PARCHMENT_DIM))
	_player_reserve_row = HBoxContainer.new()
	_player_reserve_row.add_theme_constant_override("separation", 4)
	_player_reserve_row.mouse_filter = Control.MOUSE_FILTER_PASS
	reserve_bar.add_child(_player_reserve_row)
	box.add_child(reserve_bar)
	return zone


func _build_hud() -> Control:
	var hud := HBoxContainer.new()
	hud.add_theme_constant_override("separation", 14)
	hud.mouse_filter = Control.MOUSE_FILTER_PASS

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
	hud.add_child(momentum_box)

	_scrap_zone = ScrapZone.new()
	_scrap_zone.battle_ui = self
	_scrap_zone.custom_minimum_size = Vector2(190, 52)
	_scrap_zone.add_theme_stylebox_override("panel", UIPalette.panel(UIPalette.SEA_DARK, UIPalette.IRON, 1))
	_scrap_label = UIPalette.label("Scrap pile", UIPalette.FONT_SMALL, UIPalette.PARCHMENT_DIM)
	_scrap_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrap_zone.add_child(_scrap_label)
	hud.add_child(_scrap_zone)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_PASS
	hud.add_child(spacer)

	_retreat_button = Button.new()
	_retreat_button.text = "Retreat"
	_retreat_button.pressed.connect(func() -> void: _retreat_dialog.popup_centered())
	hud.add_child(_retreat_button)
	_end_turn_button = Button.new()
	_end_turn_button.text = "End Turn — let them fight"
	_end_turn_button.custom_minimum_size = Vector2(200, 40)
	_end_turn_button.pressed.connect(func() -> void: submit({"op": "end"}))
	hud.add_child(_end_turn_button)
	return hud


func _build_hand_area() -> Control:
	_hand_row = HBoxContainer.new()
	_hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_row.add_theme_constant_override("separation", 8)
	_hand_row.custom_minimum_size.y = 124
	_hand_row.mouse_filter = Control.MOUSE_FILTER_PASS
	return _hand_row


func _build_log_panel() -> Control:
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 285
	sidebar.add_theme_constant_override("separation", 6)
	sidebar.mouse_filter = Control.MOUSE_FILTER_PASS

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
	return sidebar


func _build_dialogs() -> void:
	_reaction_dialog = ConfirmationDialog.new()
	_reaction_dialog.title = "A shield-brother falls"
	_reaction_dialog.ok_button_text = "Drag him back!"
	_reaction_dialog.cancel_button_text = "Let him die"
	_reaction_dialog.confirmed.connect(func() -> void: controller.reaction_submitted.emit(true))
	_reaction_dialog.canceled.connect(func() -> void: controller.reaction_submitted.emit(false))
	add_child(_reaction_dialog)

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


## Scrap drop target: one card a turn becomes momentum.
class ScrapZone:
	extends PanelContainer
	var battle_ui: BattleUI

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("card") \
				and battle_ui._awaiting_action \
				and not battle_ui.engine.state.scrapped_this_turn

	func _drop_data(_at: Vector2, data: Variant) -> void:
		battle_ui.submit({"op": "scrap", "card": data["card"]})
