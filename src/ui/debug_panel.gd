class_name DebugPanel
extends PanelContainer
## M1 debug drawer: restart with a chosen seed, edit the whole battle setup
## (rosters, deck, tactics) as RosterText and apply it. Hidden until the
## Debug button toggles it.

var battle_ui: BattleUI
var _seed_spin: SpinBox
var _roster_edit: TextEdit
var _errors_label: Label


static func create(p_ui: BattleUI) -> DebugPanel:
	var panel := DebugPanel.new()
	panel.battle_ui = p_ui
	panel._build()
	return panel


func _build() -> void:
	visible = false
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = -470
	offset_right = 0
	add_theme_stylebox_override("panel", UIPalette.panel(UIPalette.SEA_DARK.lightened(0.03), UIPalette.GOLD, 1))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	var top := HBoxContainer.new()
	var title := UIPalette.label("Debug", UIPalette.FONT_TITLE, UIPalette.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void: visible = false)
	top.add_child(close)
	box.add_child(top)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 6)
	seed_row.add_child(UIPalette.label("Seed", UIPalette.FONT_BODY))
	_seed_spin = SpinBox.new()
	_seed_spin.min_value = 0
	_seed_spin.max_value = 999999999
	_seed_spin.value = battle_ui.battle_seed
	seed_row.add_child(_seed_spin)
	var restart := Button.new()
	restart.text = "Restart battle"
	restart.pressed.connect(_on_restart)
	seed_row.add_child(restart)
	box.add_child(seed_row)

	box.add_child(UIPalette.label("Battle setup — same seed replays the same battle:",
			UIPalette.FONT_SMALL, UIPalette.PARCHMENT_DIM))
	_roster_edit = TextEdit.new()
	_roster_edit.text = battle_ui.roster_source
	_roster_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_roster_edit.add_theme_font_size_override("font_size", 12)
	box.add_child(_roster_edit)

	var apply := Button.new()
	apply.text = "Apply setup & restart"
	apply.pressed.connect(_on_apply)
	box.add_child(apply)

	_errors_label = UIPalette.label("", UIPalette.FONT_SMALL, UIPalette.BLOOD.lightened(0.35))
	_errors_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_errors_label)


func sync_seed(value: int) -> void:
	_seed_spin.value = value


func show_errors(errors: Array[String]) -> void:
	visible = true
	_errors_label.text = "\n".join(errors)


func _on_restart() -> void:
	battle_ui.battle_seed = int(_seed_spin.value)
	battle_ui.start_battle()


func _on_apply() -> void:
	var parsed := RosterText.parse(_roster_edit.text)
	if not parsed["errors"].is_empty():
		show_errors(parsed["errors"])
		return
	_errors_label.text = ""
	battle_ui.roster_source = _roster_edit.text
	battle_ui.battle_seed = int(_seed_spin.value)
	battle_ui.start_battle()
