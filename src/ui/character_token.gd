class_name CharacterToken
extends PanelContainer
## One fighter on the board: name, HP and morale bars, stats, engagement.
## Also a drop target for cards and (in the reserve row) a commit button.

signal clicked(character: Character)

var character: Character
var battle_ui: Control
var compact := false   ## reserve rows use a smaller face
## This fighter's entry from CombatEngine.forecast(): incoming {"hp", "morale"}
## next fight phases. Empty for men off the grid — nothing can touch them.
var forecast := {}
## An enemy archer's aimed arrows are locked on this man (rescue him!).
var marked := false
## Presentation flags the table sets per refresh, all of them answers the
## engine already gave BattleUI — never judgements made here:
##   highlight: the board is asking for a pick and this man is one of them
##   dim:       he cannot be sent over at all (the prow pair's other half)
##   hint:      a line of small text under his bars (the pair's swap hint)
##   hint_lit:  that hint is available right now, not just true in principle
var display := {}


static func create(p_character: Character, p_ui: Control, p_compact := false,
		p_forecast := {}, p_marked := false, p_display := {}) -> CharacterToken:
	var token := CharacterToken.new()
	token.character = p_character
	token.battle_ui = p_ui
	token.compact = p_compact
	token.forecast = p_forecast
	token.marked = p_marked
	token.display = p_display
	token._build()
	return token


## The token is the layout's unit cell and its size is FIXED. Names, stat
## lines, wind-up counters and forecast badges all vary in width, and letting
## them set the token's size re-flowed the whole formation row every time the
## board re-rendered — so a card dragged at a slot found the board had slid
## out from under it. Content is clipped to the cell instead.
const TOKEN_SIZE := Vector2(128, 96)
const COMPACT_SIZE := Vector2(104, 64)
const PAD := 4  ## the panel style's content margin


func highlighted() -> bool:
	return display.get("highlight", false)


func _build() -> void:
	custom_minimum_size = COMPACT_SIZE if compact else TOKEN_SIZE
	var is_player := character.side == Character.Side.PLAYER
	var trim := UIPalette.GOLD if is_player else UIPalette.IRON
	if character.is_captain:
		trim = UIPalette.GOLD if is_player else UIPalette.BLOOD
	var bg := UIPalette.SEA if is_player else UIPalette.IRON_DARK
	var style := UIPalette.panel(bg, trim, 2 if character.is_captain else 1)
	# One visual language for "the board wants a pick from you": a gold rim
	# here, the same gold rim on an empty slot that would take the pick.
	if highlighted():
		style = UIPalette.panel(bg.lightened(0.08), UIPalette.GOLD, 3)
	if display.get("dim", false):
		# Greyed out, but not invisible when his one legal play is available.
		modulate = Color(1, 1, 1, 0.9 if display.get("hint_lit", false) else 0.5)
	# Tokens are the layout's unit cell: a slim margin keeps a fully lit
	# token (stats + telegraph + forecast) inside its 100px formation row.
	style.set_content_margin_all(4)
	add_theme_stylebox_override("panel", style)

	# A plain Control does not take its size from its children the way a
	# Container does, so nothing below can grow the cell.
	var holder := Control.new()
	holder.custom_minimum_size = (COMPACT_SIZE if compact else TOKEN_SIZE) \
			- Vector2(2 * PAD, 2 * PAD)
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(box)

	var name_size := UIPalette.FONT_SMALL if compact else UIPalette.FONT_BODY
	var name_label := UIPalette.label(character.display_name, name_size,
			UIPalette.PARCHMENT if is_player else UIPalette.PARCHMENT_DIM)
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	box.add_child(_bar(character.hp, character.max_hp, UIPalette.BLOOD, "HP"))
	if character.morale_immune():
		box.add_child(UIPalette.label("fearless", UIPalette.FONT_SMALL, UIPalette.PARCHMENT_DIM))
	else:
		box.add_child(_bar(character.morale, character.max_morale, UIPalette.GOLD, "MOR"))

	if not compact:
		var stats := "%s · STR %d · SPD %d" % [character.weapon.display_name, character.strength, character.speed]
		if character.block > 0:
			stats += " · BLK %d" % character.block
		var stats_label := UIPalette.label(stats, UIPalette.FONT_SMALL, UIPalette.PARCHMENT_DIM)
		stats_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		box.add_child(stats_label)
		if character.bonus_attacks > 0:
			box.add_child(UIPalette.label("+%d attack" % character.bonus_attacks,
					UIPalette.FONT_SMALL, UIPalette.PARCHMENT_DIM))
	# One status row for everything that lights up mid-battle — the telegraph
	# layer (wind-up counter, the archer's mark) and the incoming-damage
	# forecast. A single shared line, not a stack: a token must never outgrow
	# its formation row, or the rows below get pushed off the canvas.
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 6)
	status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var beat_text := _beat_text(character)
	if beat_text != "":
		status_row.add_child(UIPalette.label(beat_text, UIPalette.FONT_SMALL,
				UIPalette.BLOOD.lightened(0.45)))
	if marked:
		status_row.add_child(UIPalette.label("MARKED", UIPalette.FONT_SMALL,
				UIPalette.BLOOD.lightened(0.45)))
	if character.pinned > 0:
		status_row.add_child(UIPalette.label("PINNED %d" % character.pinned,
				UIPalette.FONT_SMALL, UIPalette.BLOOD.lightened(0.45)))
	if character.suppressed > 0:
		status_row.add_child(UIPalette.label("suppressed", UIPalette.FONT_SMALL,
				UIPalette.PARCHMENT_DIM))
	var hint: String = display.get("hint", "")
	if hint != "":
		var hint_label := UIPalette.label(hint, UIPalette.FONT_SMALL,
				UIPalette.GOLD if display.get("hint_lit", false) else UIPalette.PARCHMENT_DIM)
		hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_row.add_child(hint_label)
	_add_forecast_badge(status_row)
	if status_row.get_child_count() > 0:
		box.add_child(status_row)
	else:
		status_row.free()
	tooltip_text = _tooltip()


## The bill for standing here: incoming damage next fight phases, so the
## player reads threat off the board instead of adding it up per enemy.
func _add_forecast_badge(row: HBoxContainer) -> void:
	var incoming_hp: int = forecast.get("hp", 0)
	var incoming_morale: int = forecast.get("morale", 0)
	set_meta("forecast_hp", incoming_hp)
	set_meta("forecast_morale", incoming_morale)
	if incoming_hp <= 0 and incoming_morale <= 0:
		return
	if incoming_hp > 0:
		var hp_label := UIPalette.label("-%d HP" % incoming_hp, UIPalette.FONT_SMALL,
				UIPalette.BLOOD.lightened(0.45))
		hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(hp_label)
		if incoming_hp >= character.hp:
			var doom := UIPalette.label("DOOMED", UIPalette.FONT_SMALL, UIPalette.BLOOD.lightened(0.45))
			doom.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(doom)
	if incoming_morale > 0:
		var morale_label := UIPalette.label("-%d MOR" % incoming_morale, UIPalette.FONT_SMALL,
				UIPalette.GOLD)
		morale_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(morale_label)


func _bar(value: int, max_value: int, color: Color, tag: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag_label := UIPalette.label(tag, 9, UIPalette.PARCHMENT_DIM)
	tag_label.custom_minimum_size.x = 26
	row.add_child(tag_label)
	var bar := ProgressBar.new()
	bar.max_value = max_value
	bar.value = maxi(0, value)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", UIPalette.bar_style(UIPalette.SEA_DARK))
	bar.add_theme_stylebox_override("fill", UIPalette.bar_style(color))
	row.add_child(bar)
	var value_label := UIPalette.label("%d" % maxi(0, value), 9, UIPalette.PARCHMENT_DIM)
	value_label.custom_minimum_size.x = 16
	row.add_child(value_label)
	return row


func _tooltip() -> String:
	var lines := [
		"%s — %s" % [character.display_name, "captain" if character.is_captain else
				("prowman" if character.is_prowman else
				("berserker" if character.is_berserker else
				("shieldman" if character.is_shieldman else "fighter")))],
		"HP %d/%d · Morale %s · STR %d · SPD %d" % [
			maxi(0, character.hp), character.max_hp,
			"immune" if character.morale_immune() else "%d/%d" % [character.morale, character.max_morale],
			character.strength, character.speed],
		"Block %d (guard %d — raised again at his side's turn)" % [character.block, character.armor],
		"%s: %s" % [character.weapon.display_name, _weapon_note()],
	]
	if character.rage > 0:
		lines.append("Raging: +%d damage from the captain's commands, permanent" % character.rage)
	if character.suppressed > 0:
		lines.append("Suppressed: deals a third less for %d of his turns" % character.suppressed)
	if character.pinned > 0:
		lines.append("Pinned: cannot move for %d turns" % character.pinned)
	var note: String = display.get("note", "")
	if note != "":
		lines.append(note)
	return "\n".join(lines)


func _weapon_note() -> String:
	match character.weapon.kind:
		Weapon.Kind.SPEAR: return "reach — fights his column even from the second line"
		Weapon.Kind.AXE: return "chews 2 block per point of damage, and swings first"
		Weapon.Kind.BOW: return "from the second line: aims, then both arrows (2 dmg each) suppress the mark"
		Weapon.Kind.SWORD: return "+2 damage, no tricks"
	return "no weapon"


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(character)


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("card") \
			and battle_ui.can_drop_card_on(data["card"], character)


func _drop_data(_at: Vector2, data: Variant) -> void:
	battle_ui.play_card(data["card"], character)


## The telegraph line for a man's next beat. Plain single-beat fighters show
## nothing; a rhythm worth reading is spelled out.
static func _beat_text(character: Character) -> String:
	if character.pattern.size() <= 1:
		return ""
	match character.current_beat():
		"heavy":
			return "HEAVY BLOW NEXT"
		"aim":
			return "taking aim"
		"shoot":
			return "ARROWS AIMED"
		"guard":
			return "shield up next"
	return "strikes next"
