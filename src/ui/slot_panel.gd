class_name SlotPanel
extends PanelContainer
## One empty slot on a formation grid. Normally a dim placeholder that only
## marks the column, so misses read spatially; when the board wants a pick —
## a card being dragged that names a slot, or a pending choice — it lights up
## and becomes the target of the click or the drop.
##
## It never decides anything: the option it answers is handed to it by
## BattleUI, which got it from the engine.

const SLOT_SIZE := Vector2(128, 96)
const PAD := 8  ## the panel style's content margin

var battle_ui: Control
var side: Character.Side
var line: int
var col: int
## The pending pick this slot would answer ({} when the board is not asking).
var pick_option := {}
## A card is being dragged right now and this slot is a legal place for it.
var droppable := false


static func create(p_ui: Control, p_side: Character.Side, p_line: int, p_col: int,
		p_pick_option := {}, p_droppable := false) -> SlotPanel:
	var slot := SlotPanel.new()
	slot.battle_ui = p_ui
	slot.side = p_side
	slot.line = p_line
	slot.col = p_col
	slot.pick_option = p_pick_option
	slot.droppable = p_droppable
	slot._build()
	return slot


func _build() -> void:
	custom_minimum_size = SLOT_SIZE
	var lit := droppable or not pick_option.is_empty()
	if lit:
		add_theme_stylebox_override("panel",
				UIPalette.panel(Color(0.79, 0.64, 0.15, 0.18), UIPalette.GOLD, 2))
		mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		add_theme_stylebox_override("panel",
				UIPalette.panel(Color(0, 0, 0, 0.12), UIPalette.SEA_LIGHT.darkened(0.3), 1))
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	# A fixed box, lit or not. The label a lit slot gains names a man, and
	# letting that name set the slot's size moved the whole formation row
	# sideways the instant a card was picked up — so the drop landed in the
	# gap beside the slot it was aimed at. Plain Controls do not take their
	# size from their children, so nothing written here can move the board.
	var holder := Control.new()
	holder.custom_minimum_size = SLOT_SIZE - Vector2(2 * PAD, 2 * PAD)
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(box)
	var tag := UIPalette.label("%s%d" % ["F" if line == Formation.FRONT else "B", col + 1],
			UIPalette.FONT_SMALL, UIPalette.GOLD if lit else UIPalette.SEA_LIGHT)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tag)
	if lit:
		var here := UIPalette.label(pick_option.get("label", "here"),
				UIPalette.FONT_SMALL, UIPalette.PARCHMENT)
		here.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		here.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		here.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(here)


func _gui_input(event: InputEvent) -> void:
	if pick_option.is_empty():
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		battle_ui.choose_pick(pick_option)


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("card") \
			and battle_ui.can_drop_card_on_slot(data["card"], side, line, col)


func _drop_data(_at: Vector2, data: Variant) -> void:
	battle_ui.play_card_on_slot(data["card"], Formation.slot_index(line, col))
