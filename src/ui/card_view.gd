class_name CardView
extends PanelContainer
## One card in the hand: cost, name, rules text; drag it onto the deck (or a
## fighter, for targeted cards) to play it.

var card: CardData
var battle_ui: Control
var draggable := false  ## can be picked up to play
var bright := true      ## affordable right now; dimmed otherwise


static func create(p_card: CardData, p_ui: Control, p_draggable: bool, p_bright := true) -> CardView:
	var view := CardView.new()
	view.card = p_card
	view.battle_ui = p_ui
	view.draggable = p_draggable
	view.bright = p_bright
	view._build()
	return view


func _build() -> void:
	custom_minimum_size = Vector2(148, 118)
	var face := UIPalette.PARCHMENT if bright else UIPalette.PARCHMENT_DIM
	var border := UIPalette.GOLD if bright else UIPalette.IRON
	var style := UIPalette.panel(face, border, 2, 8)
	style.set_content_margin_all(7)
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cost := UIPalette.label("%d" % card.cost if card.playable else "—", UIPalette.FONT_TITLE, UIPalette.SEA_DARK)
	var cost_panel := PanelContainer.new()
	cost_panel.add_theme_stylebox_override("panel", UIPalette.panel(UIPalette.GOLD, Color.TRANSPARENT, 0, 10))
	cost_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_panel.add_child(cost)
	top.add_child(cost_panel)
	var name_label := UIPalette.label(card.display_name, UIPalette.FONT_BODY, UIPalette.SEA_DARK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(name_label)
	box.add_child(top)

	var body := UIPalette.label(CardText.describe(card), UIPalette.FONT_SMALL, UIPalette.SEA_DARK.lightened(0.12))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(body)

	var foot_text := "retained" if card.retained else "discards at turn end"
	var gesture := CardText.drop_hint(card)
	if gesture != "":
		foot_text = gesture + " · " + foot_text
	var foot := UIPalette.label(foot_text, 9, UIPalette.SEA_LIGHT)
	# The footnote must never set the card's width — ellipsize past the edge.
	foot.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(foot)


func _get_drag_data(_at: Vector2) -> Variant:
	if not draggable:
		return null
	var preview := CardView.create(card, battle_ui, true)
	preview.modulate.a = 0.85
	preview.rotation_degrees = 3.0
	set_drag_preview(preview)
	# The table lights every legal target for this card while it is in the air.
	battle_ui.on_card_drag_started(card)
	return {"card": card}
