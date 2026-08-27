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
var _enemy_back_row: HBoxContainer
var _enemy_front_row: HBoxContainer
var _player_front_row: HBoxContainer
var _player_back_row: HBoxContainer
var _player_reserve_row: HBoxContainer
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
	_turn_label.text = "The boarding — how do you come over the rail?"
	refresh(state)
	for child in _maneuver_options.get_children():
		child.queue_free()
	for maneuver in options:
		_maneuver_options.add_child(_maneuver_option(maneuver))
	_maneuver_layer.visible = true


func on_player_decision_start(state: BattleState) -> void:
	_awaiting_action = true
	_turn_label.text = "Turn %d — your move" % state.turn
	refresh(state)


func on_pace(state: BattleState) -> void:
	_turn_label.text = "Turn %d — steel rings" % state.turn
	refresh(state)


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


# --- Card drops --------------------------------------------------------------

func can_drop_card_on(card: CardData, target: Character) -> bool:
	if not _awaiting_action or not _can_pay(card):
		return false
	match card.target_type:
		CardData.TargetType.NONE:
			return true  # a token is as good a place as any to drop it
		CardData.TargetType.ENEMY:
			return _valid_enemy_target(card, target)
		CardData.TargetType.ALLY:
			return _valid_ally_target(card, target)
	return false


func play_card(card: CardData, target: Character) -> void:
	if card.target_type == CardData.TargetType.NONE:
		target = null
	submit({"op": "play", "card": card, "target": target})


func _can_pay(card: CardData) -> bool:
	return card.playable and card.cost <= engine.state.momentum


func _valid_enemy_target(card: CardData, c: Character) -> bool:
	if c.side != Character.Side.ENEMY or not c.is_alive():
		return false
	if not engine.state.enemy_formation.has(c):
		return false
	for effect in card.effects:
		if effect.get("type") == CardData.EffectType.SHOVE:
			var f := engine.state.enemy_formation
			if f.line_of(c) != Formation.FRONT:
				return false
			var col := f.column_of(c)
			var left_free := col > 0 and f.at(Formation.FRONT, col - 1) == null
			var right_free := col < Formation.COLUMNS - 1 \
					and f.at(Formation.FRONT, col + 1) == null
			if not left_free and not right_free:
				return false
	return true


func _valid_ally_target(card: CardData, c: Character) -> bool:
	if c.side != Character.Side.PLAYER or not c.is_alive():
		return false
	for effect in card.effects:
		match effect.get("type"):
			CardData.EffectType.PULL_TO_RESERVE, CardData.EffectType.EXTRA_ATTACK, \
			CardData.EffectType.SWAP:
				if not engine.state.player_formation.has(c):
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
	# One forecast per refresh: every token shows what it stands to take.
	var forecast := engine.forecast()
	_fill_enemy_reserve(state)
	_fill_line(_enemy_back_row, state.enemy_formation, Formation.BACK, forecast)
	_fill_line(_enemy_front_row, state.enemy_formation, Formation.FRONT, forecast)
	_fill_line(_player_front_row, state.player_formation, Formation.FRONT, forecast)
	_fill_line(_player_back_row, state.player_formation, Formation.BACK, forecast)
	_fill_row(_player_reserve_row, state.player_reserve, true)
	_refresh_enemy_captain(state)
	_refresh_hand(state)
	_refresh_hud(state)
	_refresh_log(state)


## One line of a formation as 4 fixed columns: a token where a man stands,
## a dim placeholder where the slot is empty (so misses read spatially).
func _fill_line(row: HBoxContainer, formation: Formation, line: int,
		forecast: Dictionary) -> void:
	for child in row.get_children():
		child.queue_free()
	for col in Formation.COLUMNS:
		var c := formation.at(line, col)
		if c != null:
			var token := CharacterToken.create(c, self, false, forecast.get(c, {}))
			token.clicked.connect(_on_token_clicked)
			row.add_child(token)
		else:
			row.add_child(_empty_slot(line, col))


func _empty_slot(line: int, col: int) -> Control:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(128, 96)
	slot.add_theme_stylebox_override("panel",
			UIPalette.panel(Color(0, 0, 0, 0.12), UIPalette.SEA_LIGHT.darkened(0.3), 1))
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag := UIPalette.label("%s%d" % ["F" if line == Formation.FRONT else "B", col + 1],
			UIPalette.FONT_SMALL, UIPalette.SEA_LIGHT)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(tag)
	return slot


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
		if c.is_shieldman:
			chip += " · shieldman"
		_enemy_reserve_list.add_child(UIPalette.label(chip, UIPalette.FONT_SMALL, UIPalette.PARCHMENT_DIM))


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
	for card in state.hand:
		var affordable := _can_pay(card)
		var view := CardView.create(card, self, _awaiting_action and affordable, affordable)
		_hand_row.add_child(view)


func _refresh_hud(state: BattleState) -> void:
	_momentum_label.text = "Momentum %d/%d" % [state.momentum, BattleState.MOMENTUM_CAP]
	for i in _momentum_pips.get_child_count():
		var pip: ColorRect = _momentum_pips.get_child(i)
		pip.color = UIPalette.GOLD if i < state.momentum else UIPalette.SEA_LIGHT
	_piles_label.text = "Deck %d · Discard %d" % [state.deck.size(), state.discard.size()]
	_end_turn_button.disabled = not _awaiting_action
	_retreat_button.disabled = not _awaiting_action
	_status_label.text = " · ".join(_active_effects(state))


func _active_effects(state: BattleState) -> Array[String]:
	var chips: Array[String] = []
	if state.shield_wall_active:
		chips.append("Shield Wall up")
	if state.challenge_active:
		chips.append("CHALLENGE — the captains seek each other")
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
	reserve_bar.add_child(UIPalette.label("Your ship — click a man to commit him (%d momentum). The reserve never fights, is never hit."
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


