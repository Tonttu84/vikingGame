class_name PickText
extends RefCounted
## What is happening, in full sentences, every time the board asks the player
## for something (owner's playtest ask, 2026-09-06: "print out what is
## happening in all cases where the player needs to select something or move
## something"). Each pick kind has one function here: what the card or rule
## just did, what is being asked, and what the click will do. Nothing is
## decided here — the lists these describe come from the engine, and this
## only puts them into words. BattleUI shows the result on an overlay that
## takes no layout space.


## "F2", "B4" — the slot names the grid prints.
static func slot_name(line: int, col: int) -> String:
	return "%s%d" % ["F" if line == Formation.FRONT else "B", col + 1]


static func slot_name_at(index: int) -> String:
	@warning_ignore("integer_division")
	return slot_name(index / Formation.COLUMNS, index % Formation.COLUMNS)


static func _names(men: Array) -> String:
	var out: Array[String] = []
	for c: Character in men:
		out.append(c.display_name)
	return ", ".join(out)


static func _slot_names(indices: Array) -> String:
	var out: Array[String] = []
	for index: int in indices:
		out.append(slot_name_at(index))
	return ", ".join(out)


const _TRADE_RULE := "A fellow on deck trades slots with him; a man on the ship takes his exact slot and he goes back aboard. A pinned man moves neither way."
const _LINES_RULE := "Front slots fight. Second-line slots cover: a spear reaches over the man in front, a bow shoots only with one, everyone else waits to press forward."


# --- A played card's movement rider ------------------------------------------

## The punch has landed and the step is due. Every offered move is described
## by its destination, because a held slot means the two men trade.
static func rider(card: CardData, moves: Array[Dictionary], formation: Formation) -> String:
	var done := CardText.summarize_effects(card)
	var text := "%s has resolved" % card.display_name
	text += (": %s" % done) if done != "" else "."
	if not text.ends_with("."):
		text += "."
	text += " Now its movement is due: one of your men must %s. That direction is printed on the card and cannot be changed; only WHICH man steps is yours to pick." \
			% CardText.rider_kind(card)
	text += " Click a lit man and he takes the step at once. There is no cancel — the step is part of the card's price."
	var lines: Array[String] = []
	for move in moves:
		lines.append(_rider_move_words(move, formation))
	if not lines.is_empty():
		text += "\n\nWhat each step would do:\n" + "\n".join(lines)
	return text


static func _rider_move_words(move: Dictionary, formation: Formation) -> String:
	var mover: Character = move["character"]
	var line := formation.line_of(mover)
	var col := formation.column_of(mover)
	var to_line := line
	var to_col := col
	if move.has("direction"):
		to_col = col + int(move["direction"])
	elif move.has("line"):
		to_line = int(move["line"])
	var occupant := formation.at(to_line, to_col)
	var verb := "steps"
	if to_line != line:
		verb = "presses forward" if to_line == Formation.FRONT else "gives ground"
	elif move.has("direction"):
		verb = "steps to port" if int(move["direction"]) < 0 else "steps to starboard"
	if occupant == null:
		return "• %s %s into the empty %s." % [mover.display_name, verb, slot_name(to_line, to_col)]
	return "• %s %s into %s and trades places with %s, who takes %s." % [
			mover.display_name, verb, slot_name(to_line, to_col), occupant.display_name,
			slot_name(line, col)]


# --- Card picks: a card wants one more thing off the board -------------------

static func card_crossing(card: CardData, slot: int, candidates: Array) -> String:
	var slot_words := "the slot you dropped it on, %s" % slot_name_at(slot) if slot >= 0 \
			else "the first free slot"
	return ("%s (cost %d) is a second crossing this turn, on top of the opening's. " +
			"Click the man on your ship who comes over the rail into %s. " +
			"Lit and ready: %s. %s Cancel puts the card back in your hand, unpaid.") % [
			card.display_name, card.cost, slot_words, _names(candidates), _LINES_RULE]


static func card_trade(card: CardData, target: Character, partners: Array) -> String:
	return ("%s (cost %d): %s will change places with the man you click. %s " +
			"Lit: %s. Cancel puts the card back in your hand, unpaid.") % [
			card.display_name, card.cost, target.display_name, _TRADE_RULE, _names(partners)]


static func card_taunt(card: CardData, target: Character, anchors: Array) -> String:
	return ("%s (cost %d): %s is called out. Click the man of yours he must answer to — " +
			"%s is dragged into the front slot of that man's column, trading with whoever " +
			"stood there, so the two of them duel next round. Lit: %s. " +
			"Cancel puts the card back in your hand, unpaid.") % [
			card.display_name, card.cost, target.display_name, target.display_name,
			_names(anchors)]


static func card_shove(card: CardData, target: Character, directions: Array) -> String:
	var ways: Array[String] = []
	for dir: int in directions:
		ways.append("port" if dir < 0 else "starboard")
	return ("%s (cost %d): %s is shoved one column sideways along his own line, into an " +
			"empty slot — click the lit one (%s). The column he leaves is empty, so your " +
			"man there swings at air unless he closes; the column he lands in fights him " +
			"instead. Cancel puts the card back in your hand, unpaid.") % [
			card.display_name, card.cost, target.display_name, " or ".join(ways)]


# --- The opening: the turn's forced three-way choice -------------------------

static func opening(turn: int, options: Array) -> String:
	var text := ("Turn %d opens on one forced choice before any card may be played. " +
			"REINFORCE: a man off your ship crosses free into a slot you pick. " +
			"SNAP: two of your men trade places, on deck or across the rail. " +
			"+1 & DRAW: the income, +1 momentum and +1 card on top of the turn's own. " +
			"The two free moves cost you exactly that income.") % turn
	var refused: Array[String] = []
	if not options.has("reinforce"):
		refused.append("Reinforce (the grid is full, or nobody on the ship may cross)")
	if not options.has("swap"):
		refused.append("Snap (no fielded man has anyone to trade with)")
	if not refused.is_empty():
		text += " Greyed out this turn: %s." % "; ".join(refused)
	return text


static func opening_crosser(turn: int, candidates: Array) -> String:
	return ("Turn %d, the opening — the free crossing. Click the man on your ship who comes " +
			"over the rail; you pick his slot next. Lit and ready: %s. Taking the crossing " +
			"forfeits the income (+1 momentum and +1 card). Cancel goes back to the " +
			"three choices.") % [turn, _names(candidates)]


static func opening_slot(character: Character, free_slots: Array) -> String:
	return ("%s crosses free. Click the lit empty slot he takes (%s). %s " +
			"He fights from the next round. Cancel goes back to choosing the man.") % [
			character.display_name, _slot_names(free_slots), _LINES_RULE]


static func opening_swapper(turn: int, swappers: Array) -> String:
	return ("Turn %d, the opening — the free snap. Click the fielded man who moves; next you " +
			"name who he changes places with, a fellow on deck or a man on the ship. " +
			"Lit: %s. Taking the snap forfeits the income (+1 momentum and +1 card). " +
			"Cancel goes back to the three choices.") % [turn, _names(swappers)]


static func opening_partner(mover: Character, partners: Array) -> String:
	return ("%s changes places with the man you click. %s Lit: %s. " +
			"Cancel goes back to choosing the man who moves.") % [
			mover.display_name, _TRADE_RULE, _names(partners)]


# --- A card in the air -------------------------------------------------------

## What the dragged card will light and why the rest stays dark.
static func drag(card: CardData) -> String:
	var text := "%s (cost %d): %s" % [card.display_name, card.cost, CardText.describe(card).replace("\n", " ")]
	if not text.ends_with("."):
		text += "."
	var has_reinforce := false
	var has_rider := false
	for effect in card.effects:
		match effect.get("type"):
			CardData.EffectType.REINFORCE:
				has_reinforce = true
			CardData.EffectType.RIDER_PORT, CardData.EffectType.RIDER_STARBOARD, \
			CardData.EffectType.RIDER_FORWARD, CardData.EffectType.RIDER_BACKWARD, \
			CardData.EffectType.RIDER_CLOSE:
				has_rider = true
	if has_reinforce:
		text += " Drop it on a lit empty slot of your own grid: that is where the man you name next will land."
	else:
		match card.target_type:
			CardData.TargetType.ENEMY:
				text += " Drop it on a lit enemy. A defender left dark is out of the card's reach: on the ship, in the wrong line for it, or pinned."
			CardData.TargetType.ALLY:
				text += " Drop it on a lit man of yours. A man left dark cannot take it: he is on the ship"
				text += ", or the step the card forces (%s) has nowhere to go from his slot." % CardText.rider_kind(card) \
						if has_rider else "."
			_:
				text += " Drop it anywhere on the table."
	if has_rider:
		text += " After the effect, one of your men must %s; the board asks which. A card whose step nobody could take is refused before it is paid for." \
				% CardText.rider_kind(card)
	return text


# --- The overlay panel -------------------------------------------------------

## The parchment panel BattleUI draws over the sidebar. Built to a KNOWN
## height the way CardView.build_preview is: an autowrapping label reports no
## usable minimum until laid out, so both blocks are measured with the font
## first. Ignores the mouse entirely — it explains, it never eats a click.
static func build_panel(title: String, body: String, width: float) -> Control:
	var panel := PanelContainer.new()
	var style := UIPalette.panel(UIPalette.PARCHMENT, UIPalette.GOLD, 2, 8)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_meta("explanation", true)
	var text_w := width - 2 * 10.0

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	var title_label := UIPalette.label(title, UIPalette.FONT_BODY, UIPalette.SEA_DARK)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	title_label.add_theme_constant_override("line_spacing", 0)
	title_label.custom_minimum_size = Vector2(text_w, _text_height(title, text_w, UIPalette.FONT_BODY))
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title_label)

	var body_label := UIPalette.label(body, UIPalette.FONT_SMALL, UIPalette.SEA_DARK.lightened(0.12))
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	body_label.add_theme_constant_override("line_spacing", 0)
	body_label.custom_minimum_size = Vector2(text_w, _text_height(body, text_w, UIPalette.FONT_SMALL))
	body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(body_label)

	panel.custom_minimum_size.x = width
	panel.size.x = width
	return panel


static func _text_height(text: String, width: float, font_size: int) -> float:
	var font := ThemeDB.fallback_font
	if font == null:
		return 0.0
	return font.get_multiline_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size).y
