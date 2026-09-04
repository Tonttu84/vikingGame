class_name CardView
extends PanelContainer
## One card in the hand: cost, name, rules text; drag it onto the deck (or a
## fighter, for targeted cards) to play it.
##
## A card face is a FIXED box, and the text is fitted to the box rather than
## the box to the text. New cards get designed and rules text grows; before
## this, a long enough description grew the card, which grew the hand row,
## which pushed the End Turn button clean off the bottom of the screen. Now
## the body picks the largest font size that fits its panel, falls back to
## clipping with the full text on the hover preview, and nothing a card can
## say moves the layout by a single pixel.
##
## The face shows CardText.summarize — the short lines. The full sentences
## live on the hover preview (build_preview), a full-size readable card the
## table pops over the board whenever the mouse rests on a face.

const CARD_SIZE := Vector2(186, 148)
const PAD := 7        ## panel content margin
const GAP := 3        ## separation between header, body and footnote
const HEADER_H := 36  ## cost chip beside the (wrapping) card name
const FOOT_H := 12
const BODY_FONT_FLOOR := 8

const PREVIEW_WIDTH := 380.0
const PREVIEW_FONT := 14

var card: CardData
var battle_ui: Control
## Card faces narrow when the hand is large — a Feint can push it to
## BattleState.MAX_HAND_SIZE — so the row always fits the table it sits in.
var width := CARD_SIZE.x
var draggable := false  ## can be picked up to play
var bright := true      ## affordable right now; dimmed otherwise


static func create(p_card: CardData, p_ui: Control, p_draggable: bool,
		p_bright := true, p_width := CARD_SIZE.x) -> CardView:
	var view := CardView.new()
	view.card = p_card
	view.battle_ui = p_ui
	view.draggable = p_draggable
	view.bright = p_bright
	view.width = p_width
	view._build()
	return view


## The widest each face may be so that `count` of them fit `row_width`.
static func width_for(count: int, row_width: float, separation: float) -> float:
	if count <= 0:
		return CARD_SIZE.x
	var each := (row_width - separation * (count - 1)) / count
	return minf(CARD_SIZE.x, maxf(56.0, each))


## The largest size from `start` down to the floor whose wrapped text fits
## the box, so more words mean smaller print instead of a broken layout.
static func fit_font_size(text: String, width: float, height: float,
		start := UIPalette.FONT_BODY, floor_size := BODY_FONT_FLOOR) -> int:
	var font := ThemeDB.fallback_font
	if font == null:
		return floor_size
	for size in range(start, floor_size - 1, -1):
		var measured := font.get_multiline_string_size(
				text, HORIZONTAL_ALIGNMENT_LEFT, width, size)
		if measured.y <= height:
			return size
	return floor_size


## A fixed-height slot. Plain Controls do not take their minimum size from
## their children the way Containers do, so whatever is dropped in here can
## never grow the card — it is clipped instead.
static func _slot(height: float) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(0, height)
	box.clip_contents = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


func _build() -> void:
	custom_minimum_size = Vector2(width, CARD_SIZE.y)
	var face := UIPalette.PARCHMENT if bright else UIPalette.PARCHMENT_DIM
	var border := UIPalette.GOLD if bright else UIPalette.IRON
	var style := UIPalette.panel(face, border, 2, 8)
	style.set_content_margin_all(PAD)
	add_theme_stylebox_override("panel", style)

	# The face carries the short lines; resting the mouse on it pops the
	# full-size preview, which replaces the old OS tooltip (two floating
	# copies of the same rules would fight over the same square of screen).
	var body_text := CardText.summarize(card)
	mouse_entered.connect(func() -> void: battle_ui.show_card_preview(self))
	mouse_exited.connect(func() -> void: battle_ui.hide_card_preview())

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", GAP)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	# --- header: cost chip + name -------------------------------------------
	var header := _slot(HEADER_H)
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_FULL_RECT)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cost := UIPalette.label("%d" % card.cost if card.playable else "—",
			UIPalette.FONT_TITLE, UIPalette.SEA_DARK)
	var cost_panel := PanelContainer.new()
	cost_panel.add_theme_stylebox_override("panel",
			UIPalette.panel(UIPalette.GOLD, Color.TRANSPARENT, 0, 10))
	cost_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_panel.add_child(cost)
	top.add_child(cost_panel)
	var name_label := UIPalette.label(card.display_name, UIPalette.FONT_BODY, UIPalette.SEA_DARK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(name_label)
	header.add_child(top)
	box.add_child(header)

	# --- body: the rules text, shrunk to fit --------------------------------
	var body_h := CARD_SIZE.y - 2 * PAD - HEADER_H - FOOT_H - 2 * GAP
	var body_w := width - 2 * PAD
	var body_slot := _slot(body_h)
	body_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body := UIPalette.label(body_text,
			fit_font_size(body_text, body_w, body_h),
			UIPalette.SEA_DARK.lightened(0.12))
	# Wrap and space EXACTLY as fit_font_size measures: greedy word wrap, no
	# extra line spacing. The smart balancer breaks one line more than the
	# measurement counts, and that phantom line was clipped off the bottom.
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.add_theme_constant_override("line_spacing", 0)
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_slot.add_child(body)
	box.add_child(body_slot)

	# --- footnote -----------------------------------------------------------
	var foot_text := "retained" if card.retained else "discards at turn end"
	var gesture := CardText.drop_hint(card)
	if gesture != "":
		foot_text = gesture + " · " + foot_text
	var foot_slot := _slot(FOOT_H)
	var foot := UIPalette.label(foot_text, 9, UIPalette.SEA_LIGHT)
	# The footnote must never set the card's width — ellipsize past the edge.
	foot.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	foot.set_anchors_preset(Control.PRESET_FULL_RECT)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot_slot.add_child(foot)
	box.add_child(foot_slot)


func _get_drag_data(_at: Vector2) -> Variant:
	if not draggable:
		return null
	battle_ui.hide_card_preview()
	var preview := CardView.create(card, battle_ui, true)
	preview.modulate.a = 0.85
	preview.rotation_degrees = 3.0
	set_drag_preview(preview)
	# The table lights every legal target for this card while it is in the air.
	battle_ui.on_card_drag_started(card)
	return {"card": card}


# --- The hover preview -------------------------------------------------------

## The full-size readable card: same face, full sentences, nothing clipped.
## An overlay the table positions, so it is built to a KNOWN height — an
## autowrapping label reports no useful minimum until it has been laid out,
## so every text block is measured with the font first and boxed to that.
static func build_preview(card: CardData) -> Control:
	var panel := PanelContainer.new()
	var style := UIPalette.panel(UIPalette.PARCHMENT, UIPalette.GOLD, 2, 8)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var text_w := PREVIEW_WIDTH - 2 * 12.0
	var body_text := CardText.describe(card)
	var foot_text := "retained" if card.retained else "discards at turn end"
	var gesture := CardText.drop_hint(card)
	if gesture != "":
		foot_text = gesture + " · " + foot_text

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cost := UIPalette.label("%d" % card.cost if card.playable else "—",
			UIPalette.FONT_TITLE, UIPalette.SEA_DARK)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cost_panel := PanelContainer.new()
	cost_panel.add_theme_stylebox_override("panel",
			UIPalette.panel(UIPalette.GOLD, Color.TRANSPARENT, 0, 10))
	cost_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost_panel.add_child(cost)
	top.add_child(cost_panel)
	var name_w := text_w - 48.0  # minus the cost chip and the row gap
	var name_label := UIPalette.label(card.display_name, UIPalette.FONT_TITLE, UIPalette.SEA_DARK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(name_w,
			_text_height(card.display_name, name_w, UIPalette.FONT_TITLE))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(name_label)
	box.add_child(top)

	var body := UIPalette.label(body_text, PREVIEW_FONT, UIPalette.SEA_DARK.lightened(0.12))
	# Greedy wrap and zero line spacing, so the measured height is the truth.
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.add_theme_constant_override("line_spacing", 0)
	body.custom_minimum_size = Vector2(text_w, _text_height(body_text, text_w, PREVIEW_FONT))
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(body)

	var foot := UIPalette.label(foot_text, UIPalette.FONT_SMALL, UIPalette.SEA_LIGHT)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.custom_minimum_size = Vector2(text_w,
			_text_height(foot_text, text_w, UIPalette.FONT_SMALL))
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(foot)

	panel.custom_minimum_size.x = PREVIEW_WIDTH
	return panel


static func _text_height(text: String, width: float, font_size: int) -> float:
	var font := ThemeDB.fallback_font
	if font == null:
		return 0.0
	return font.get_multiline_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size).y
