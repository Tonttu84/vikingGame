extends SceneTree
## End-to-end smoke test for the battle UI: boot the scene, end turns
## through the real controller path, drag-and-drop cards with synthesized
## mouse events, restart from the debug path. Needs a display for GUI input
## routing — run via scripts/ui_smoke.sh (xvfb), not --headless.

var failures: Array[String] = []
var checks := 0
## Blocks a finished (or unlucky) battle made impossible to reach — printed
## with the summary so a silently shrinking smoke run is visible.
var skipped: Array[String] = []


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append(msg)


func _drag(from: Vector2, to: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	down.global_position = from
	root.push_input(down)
	await process_frame
	var steps := 12
	for i in range(1, steps + 1):
		var m := InputEventMouseMotion.new()
		m.position = from.lerp(to, float(i) / steps)
		m.global_position = m.position
		m.relative = (to - from) / steps
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(m)
		await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = to
	up.global_position = to
	root.push_input(up)
	await process_frame


func _click(pos: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	down.global_position = pos
	root.push_input(down)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	root.push_input(up)
	await process_frame


func _init() -> void:
	call_deferred("_run")


## Only the real fighter tokens in a formation row (empty slots render too).
func _has_label_containing(node: Node, needle: String) -> bool:
	if node is Label and (node as Label).text.contains(needle):
		return true
	for child in node.get_children():
		if _has_label_containing(child, needle):
			return true
	return false


func _tokens_in(row: Node) -> Array:
	var tokens := []
	for child in row.get_children():
		if child is CharacterToken:
			tokens.append(child)
	return tokens


## Press the choose button on the picker option for the given maneuver id.
func _press_maneuver(ui, maneuver_id: String) -> void:
	for option in ui._maneuver_options.get_children():
		if option.get_meta("maneuver_id", "") == maneuver_id:
			(option.get_meta("button") as Button).pressed.emit()
			return
	failures.append("maneuver option not found: " + maneuver_id)


## The engine paces itself for animations (0.3s beats), so the smoke test
## waits on conditions, never on fixed frame counts.
func _await_until(predicate: Callable, what: String, max_frames := 300) -> void:
	for i in max_frames:
		if predicate.call():
			return
		await process_frame
	failures.append("timed out waiting for: " + what)


## Let the board settle back to waiting for the player, answering anything it
## asks on the way: the turn's opening first (the income — it moves nobody, so
## it disturbs no other check), then any pick, always taking the first lit
## option — the same move the engine falls back to for a controller that
## cannot choose — so a mandatory movement rider never parks the battle here.
func _settle(ui, max_frames := 600) -> void:
	for i in max_frames:
		if not ui._pick.is_empty():
			ui.choose_pick(ui._pick["options"][0])
			continue
		if ui._awaiting_opening:
			ui.submit_opening({"op": "income"})
			await process_frame
			continue
		if ui._awaiting_action or ui.engine.outcome != CombatEngine.Outcome.NONE:
			return
		await process_frame
	failures.append("timed out settling the board")


## Wait for the board to come back to the player, taking the income at the
## turn's opening on the way (it moves nobody, so it disturbs nothing else).
## Every "end the turn and wait" step goes through here: since the opening
## landed, the engine parks on it before it ever asks for an action.
func _await_player(ui, max_frames := 600) -> void:
	for i in max_frames:
		if ui.engine.outcome != CombatEngine.Outcome.NONE:
			return
		if not ui._pick.is_empty():
			ui.choose_pick(ui._pick["options"][0])
			continue
		if ui._awaiting_opening:
			ui.submit_opening({"op": "income"})
			await process_frame
			continue
		if ui._awaiting_action:
			return
		await process_frame
	failures.append("timed out waiting for the player's turn")


## Wait for the next turn's opening WITHOUT answering it.
func _await_opening(ui, max_frames := 600) -> void:
	for i in max_frames:
		if ui._awaiting_opening or ui.engine.outcome != CombatEngine.Outcome.NONE:
			return
		await process_frame
	failures.append("timed out waiting for the turn's opening")


func _reserve_token(ui, character: Character):
	for t in _tokens_in(ui._player_reserve_row):
		if t.character == character:
			return t
	return null


func _card_view(ui, card: CardData):
	for v in ui._hand_row.get_children():
		if v.card == card:
			return v
	return null


## --- Layout guard -----------------------------------------------------------
## The design canvas. Anything sticking out of it is invisible in the real
## window: the stretch mode scales this rectangle and nothing else, so a
## control past the edge is simply gone — which is how the End Turn button
## vanished once the rules text on a card grew long enough to inflate the
## hand row. Checked at every stage rather than once at boot, because the
## opening screen fit perfectly while the dealt hand did not.
const CANVAS := Vector2(1280, 800)


func _overflowing(node: Node, out: Array) -> void:
	if node is Control:
		var c := node as Control
		if c.is_visible_in_tree():
			var r := c.get_global_rect()
			if r.size.x > 0.0 and r.size.y > 0.0:
				var ow: float = r.end.x - CANVAS.x
				var oh: float = r.end.y - CANVAS.y
				if ow > 0.5 or oh > 0.5 or r.position.x < -0.5 or r.position.y < -0.5:
					out.append("%s (%s) rect=%.0f,%.0f %.0fx%.0f over w+%.0f h+%.0f" % [
						c.name, c.get_class(), r.position.x, r.position.y,
						r.size.x, r.size.y, maxf(0.0, ow), maxf(0.0, oh)])
		# A clipping control paints nothing outside itself, so its children
		# cannot reach the edge of the screen even when their own rect is
		# bigger — that is exactly how a long card body is contained. Check
		# the clipper, then stop: everything below it is already covered.
		if c.clip_contents:
			return
	for child in node.get_children():
		_overflowing(child, out)


## Every visible control must sit inside the design canvas at this moment.
## Two frames first: a container measured before it has been given its width
## reports the height its labels would need wrapped at zero width, which is
## enormous and not what any player ever sees.
func check_fits_canvas(ui, stage: String) -> void:
	await process_frame
	await process_frame
	var out: Array = []
	_overflowing(ui, out)
	checks += 1
	if not out.is_empty():
		failures.append("layout escapes the %dx%d canvas at %s: %s" % [
				int(CANVAS.x), int(CANVAS.y), stage,
				", ".join(PackedStringArray(out.slice(0, 4)))])


## Lighting the board must never MOVE it. Slots only become droppable once a
## card is picked up, which re-renders the board — and every element that
## sized itself from its own text (the slot's label, a token's stat line, the
## sidebar's log) shifted the formation rows sideways at that exact moment, so
## a drop aimed at a slot landed in the gap beside it. Nothing may move.
func check_lighting_does_not_move_the_board(ui) -> void:
	if ui.engine.state.hand.is_empty():
		skipped.append("the lighting-shift check (no cards in hand)")
		return
	var before := {}
	for slot in _all_slots(ui):
		before[slot.get_instance_id()] = slot.get_global_rect()
	var before_by_cell := {}
	for slot in _all_slots(ui):
		before_by_cell["%d-%d-%d" % [slot.side, slot.line, slot.col]] = slot.get_global_rect()

	# Light the board exactly as picking a card up does.
	ui.on_card_drag_started(ui.engine.state.hand[0])
	await process_frame
	await process_frame

	var moved: Array = []
	for slot in _all_slots(ui):
		var key := "%d-%d-%d" % [slot.side, slot.line, slot.col]
		if before_by_cell.has(key) and before_by_cell[key] != slot.get_global_rect():
			moved.append("%s%d %s -> %s" % [
					"F" if slot.line == Formation.FRONT else "B", slot.col + 1,
					str(before_by_cell[key]), str(slot.get_global_rect())])
	check(moved.is_empty(),
			"the board holds still when a card is picked up: " +
			", ".join(PackedStringArray(moved.slice(0, 3))))
	await check_fits_canvas(ui, "the board lit for a drag")
	# Put the board back the way a finished drag would.
	ui._drag_card = null
	ui._render()
	await process_frame


## A card face must be a fixed box no matter how much its rules text says —
## the guarantee that designing new cards cannot break the screen again.
func check_card_box_is_fixed(ui) -> void:
	# Measured in a hidden holder: a loose card face parented to the UI would
	# sit over the board and eat the mouse events the rest of this run needs.
	var holder := Control.new()
	holder.visible = false
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(holder)

	for id in CardLibrary.card_ids():
		var view := CardView.create(CardLibrary.by_id(id), ui, false)
		holder.add_child(view)
		await process_frame
		var size := view.get_combined_minimum_size()
		check(is_equal_approx(size.y, CardView.CARD_SIZE.y)
				and size.x <= CardView.CARD_SIZE.x + 0.5,
				"card %s keeps the fixed %dx%d box, got %.0fx%.0f" % [
						id, int(CardView.CARD_SIZE.x), int(CardView.CARD_SIZE.y),
						size.x, size.y])

	# Six effects and a name far longer than the design would ever ship, and
	# still the same box.
	var effects: Array[Dictionary] = [
		{"type": CardData.EffectType.DAMAGE_ENEMY_FRONT_LINE, "amount": 2},
		{"type": CardData.EffectType.DRAW, "amount": 2},
		{"type": CardData.EffectType.PLAYER_ARMOR_BONUS, "amount": 1},
		{"type": CardData.EffectType.WAR_CRY, "amount": 1},
		{"type": CardData.EffectType.GAIN_MOMENTUM, "amount": 3},
		{"type": CardData.EffectType.RIDER_PORT, "amount": 1},
	]
	var wordy := CardData.new("probe_wordy",
			"A Card Whose Name Runs On Far Longer Than Any Real One", 3,
			CardData.TargetType.NONE, effects)
	wordy.retained = true
	var view := CardView.create(wordy, ui, false)
	holder.add_child(view)
	await process_frame
	var size := view.get_combined_minimum_size()
	check(is_equal_approx(size.y, CardView.CARD_SIZE.y),
			"a wall of rules text leaves the card %d high, got %.0f" % [
					int(CardView.CARD_SIZE.y), size.y])
	check(size.x <= CardView.CARD_SIZE.x + 0.5,
			"and a very long card name does not widen it, got %.0f" % size.x)

	# The fitter itself: more text means smaller print, never a taller box.
	var short_size := CardView.fit_font_size("Draw 2 cards.", 164, 62)
	var long_size := CardView.fit_font_size("Draw 2 cards. ".repeat(40), 164, 62)
	check(long_size <= short_size,
			"the body font shrinks as the text grows (%d -> %d)" % [short_size, long_size])
	check(long_size >= CardView.BODY_FONT_FLOOR, "but never below the legible floor")

	holder.queue_free()
	await process_frame


## Hovering a card face pops the full-size readable card over the board: the
## complete rules text at reading size — the promise that whatever the small
## face clips is one mouse-rest away, never lost.
func check_card_hover_preview(ui) -> void:
	check(ui._hand_row.get_child_count() > 0, "a hand to hover over")
	if ui._hand_row.get_child_count() == 0:
		return
	var view = ui._hand_row.get_child(0)
	var card: CardData = view.card
	ui.show_card_preview(view)
	await process_frame
	check(ui._card_preview_layer.visible, "resting on a card shows the preview")
	check(_has_label_containing(ui._card_preview_layer, CardText.describe(card)),
			"the preview carries the FULL rules text, not the face's summary")
	check(_has_label_containing(ui._card_preview_layer, card.display_name),
			"and the card's name")
	check(ui._card_preview_layer.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"the preview never eats a click or a drag")
	var popup: Control = ui._card_preview_layer.get_child(0)
	check(popup.get_global_rect().end.y <= view.get_global_rect().position.y,
			"the preview sits above the hovered card, not on top of it")
	await check_fits_canvas(ui, "the hover preview open")
	ui.hide_card_preview()
	await process_frame
	check(not ui._card_preview_layer.visible, "leaving the card hides it again")

	# Picking a card up kills the preview — a drag needs the whole board.
	ui.show_card_preview(view)
	ui.on_card_drag_started(card)
	check(not ui._card_preview_layer.visible, "starting a drag hides the preview")
	ui._drag_card = null
	ui._render()
	await process_frame

	# Every card in the library gets a preview that fits the canvas — however
	# wordy — because the guarantee "clipped on the face, full on the preview"
	# has to hold for text that has not been written yet.
	for id in CardLibrary.card_ids():
		var probe := CardView.build_preview(CardLibrary.by_id(id))
		ui._card_preview_layer.add_child(probe)
		await process_frame
		var probe_size := probe.get_combined_minimum_size()
		check(probe_size.y <= CANVAS.y - 16.0 and probe_size.x <= CANVAS.x - 16.0,
				"the %s preview fits the canvas, needs %.0fx%.0f" % [id, probe_size.x, probe_size.y])
		check(_has_label_containing(probe, CardText.describe(CardLibrary.by_id(id))),
				"the %s preview holds its full text" % id)
		probe.queue_free()
	ui.hide_card_preview()
	await process_frame


## Put a card in hand for a test without pushing past the hand limit. A Feint
## can legitimately take the hand to BattleState.MAX_HAND_SIZE, so that is the
## real ceiling — but a test that stacked cards beyond even that built a hand
## the game cannot deal, and a row wider than the table it sits in.
func _put_in_hand(ui, card: CardData) -> void:
	var hand: Array = ui.engine.state.hand
	if hand.size() < BattleState.MAX_HAND_SIZE:
		hand.append(card)
		return
	for i in hand.size():
		if not hand[i].retained:
			hand[i] = card
			return
	hand[0] = card


## The widest the hand ever gets is MAX_HAND_SIZE, and it must still fit.
func check_a_full_hand_fits(ui) -> void:
	var saved: Array = ui.engine.state.hand.duplicate()
	while ui.engine.state.hand.size() < BattleState.MAX_HAND_SIZE:
		ui.engine.state.hand.append(CardLibrary.concentrated_attack())
	ui.refresh(ui.engine.state)
	await process_frame
	check(ui.engine.state.hand.size() == BattleState.MAX_HAND_SIZE,
			"a hand of %d to lay out" % BattleState.MAX_HAND_SIZE)
	check(ui._hand_row.get_combined_minimum_size().x <= BattleUI.TABLE_WIDTH + 0.5,
			"the widest legal hand still fits the table (needs %.0f of %.0f)" % [
					ui._hand_row.get_combined_minimum_size().x, BattleUI.TABLE_WIDTH])
	await check_fits_canvas(ui, "a full hand of %d cards" % BattleState.MAX_HAND_SIZE)
	ui.engine.state.hand.assign(saved)
	ui.refresh(ui.engine.state)
	await process_frame


func _all_slots(node: Node) -> Array:
	var out: Array = []
	if node is SlotPanel:
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_slots(c))
	return out


func _run() -> void:
	var scene: PackedScene = load("res://src/ui/battle_ui.tscn")
	check(scene != null, "battle scene loads")
	var ui = scene.instantiate()
	root.add_child(ui)

	# The battle parks on the maneuver picker before turn 1.
	await _await_until(func() -> bool:
		return ui.engine != null and ui._maneuver_layer.visible,
		"maneuver picker shown")
	check(ui.engine != null, "engine created")
	check(ui.engine.state.boarding_maneuver == null, "nothing auto-played before the pick")
	await check_fits_canvas(ui, "the maneuver picker")
	check(ui._maneuver_options.get_child_count() == 4,
			"4 maneuvers offered, saw %d" % ui._maneuver_options.get_child_count())
	# Pick Dawn Raid — NOT the engine's first-option fallback — to prove the
	# player's choice reaches the engine.
	_press_maneuver(ui, "dawn_raid")
	await _await_until(func() -> bool:
		return ui.engine.state.turn == 1 and ui._awaiting_opening,
		"battle running (boarding done) and asking for the turn's opening")

	# THE OPENING gates the turn: the bar is the only live control on the
	# table until it is answered — no card may be picked up, no turn ended.
	check(ui._awaiting_opening, "turn 1 opens on the forced three-way choice")
	check(ui._opening_bar.visible, "and the three-button bar is on the table")
	await check_fits_canvas(ui, "the turn's opening bar")
	check(ui._opening_bar.get_global_rect().end.x <= CANVAS.x
			and ui._opening_bar.get_global_rect().end.y <= CANVAS.y,
			"the opening bar is inside the canvas")
	var gated := true
	for v in ui._hand_row.get_children():
		if v.draggable:
			gated = false
	check(gated, "the hand is locked until the opening is answered")
	check(ui._end_turn_button.disabled, "the turn cannot be ended before the opening")
	check(not ui._awaiting_action, "and the engine has not asked for an action yet")
	for op in ["reinforce", "swap", "income"]:
		check((ui._opening_buttons[op] as Button).disabled
				== not ui._opening_options.has(op),
				"the bar offers exactly what the engine allows: " + op)
	var hand_before: int = ui.engine.state.hand.size()
	var momentum_before: int = ui.engine.state.momentum
	(ui._opening_buttons["income"] as Button).pressed.emit()
	await _await_until(func() -> bool: return ui._awaiting_action,
			"the answered opening hands the turn to the player")
	check(ui.engine.state.hand.size() == hand_before + 1,
			"the income drew its card (%d -> %d)" % [hand_before, ui.engine.state.hand.size()])
	check(ui.engine.state.momentum == momentum_before + 1, "and paid its momentum")
	check(not ui._opening_bar.visible, "the bar is gone once the opening is spent")
	var unlocked := false
	for v in ui._hand_row.get_children():
		if v.draggable:
			unlocked = true
	check(unlocked, "and the hand is live again")

	check(ui.engine.state.turn == 1, "battle started on turn 1")
	check(ui._awaiting_action, "UI is waiting for the player")
	check(not ui._maneuver_layer.visible, "picker hidden after the pick")
	check(ui.engine.state.boarding_maneuver != null
			and ui.engine.state.boarding_maneuver.id == "dawn_raid",
			"Dawn Raid is the maneuver that resolved")
	# The regression that started all this: a dealt hand used to push the End
	# Turn and Retreat buttons clean off the bottom of the canvas.
	await check_fits_canvas(ui, "turn 1 with a hand dealt")
	check(ui._end_turn_button.get_global_rect().end.y <= CANVAS.y,
			"the End Turn button is on screen, not below the canvas")
	check(ui._retreat_button.get_global_rect().end.y <= CANVAS.y,
			"the Retreat button is on screen, not below the canvas")
	await check_card_box_is_fixed(ui)
	await check_card_hover_preview(ui)
	await check_a_full_hand_fits(ui)
	check(ui.engine.state.momentum >= 4, "the maneuver surge came through (momentum %d)" % ui.engine.state.momentum)
	check(ui._hand_row.get_child_count() == 6,
			"hand shows the dealt 5 plus the opening's card, saw %d" % ui._hand_row.get_child_count())
	check(_tokens_in(ui._player_front_row).size() == 3, "first wave of 3 on their deck")
	check(ui._player_front_row.get_child_count() == 4, "the front line renders all 4 column slots")
	check(ui.engine.state.enemy_formation.size() == 2,
			"Dawn Raid caught 3 of 5 defenders below decks, saw %d fielded" % ui.engine.state.enemy_formation.size())
	check(_tokens_in(ui._enemy_front_row).size() + _tokens_in(ui._enemy_back_row).size() == 2,
			"both fielded defenders drawn in the grid")
	check(ui._momentum_pips.get_child_count() == 10, "momentum pips")

	# The forecast badges: whoever is about to bleed shows the bill, without
	# the player doing the sums. (Since the patterns slice, turn 1 can open
	# with the whole surviving watch on a guard beat — so the guaranteed
	# badge is on THEIR side, where your own men are about to land blows.)
	var badge_found := false
	for row in [ui._player_front_row, ui._enemy_front_row, ui._enemy_back_row]:
		for t in _tokens_in(row):
			if t.get_meta("forecast_hp", 0) > 0:
				badge_found = true
	check(badge_found, "a man in a contested column shows incoming damage")

	# The block layer renders: the guard is up from the first turn, so at
	# least one token on the table carries a BLK figure in its stats line.
	var block_shown := false
	for row in [ui._player_front_row, ui._enemy_front_row, ui._enemy_back_row]:
		for token in _tokens_in(row):
			if _has_label_containing(token, "BLK "):
				block_shown = true
	check(block_shown, "a raised guard shows as BLK on the token")

	# The compass: the player is told which side is which, in so many words.
	check(_has_label_containing(ui, "PORT"), "the port side is named on the table")
	check(_has_label_containing(ui, "STARBOARD"), "the starboard side is named on the table")
	check(_has_label_containing(ui, "Press if nothing changes"),
			"the projected press is on the table before the player commits a card")

	# A card with a movement rider: the punch lands, then the board asks
	# which man moves — never which way, that is printed on the card. Shield
	# Wall makes a front-liner give ground, so with a three-man first wave the
	# engine hands over a real choice, and being mandatory it offers no way out.
	var wall := CardLibrary.shield_wall()
	_put_in_hand(ui, wall)
	ui.engine.state.momentum = maxi(ui.engine.state.momentum, wall.cost)
	ui.refresh(ui.engine.state)
	var slots_before: Array = ui.engine.state.player_formation.slots.duplicate()
	ui.play_card(wall, null)
	await _await_until(func() -> bool: return not ui._pick.is_empty(),
			"the rider asks which man moves")
	check(ui._pick["prompt"].contains("Shield Wall")
			and ui._pick["prompt"].contains("give ground"),
			"the prompt names the card and the fixed movement, saw: %s"
			% ui._pick.get("prompt", ""))
	check(not ui._pick_cancel_button.visible, "a mandatory rider offers no cancel")
	check(ui._end_turn_button.disabled, "the turn cannot be ended out from under a pick")
	var lit := 0
	for t in _tokens_in(ui._player_front_row) + _tokens_in(ui._player_back_row):
		if t.highlighted():
			lit += 1
	check(lit == ui._pick["options"].size(),
			"every man the engine offered is lit (%d lit, %d offered)" % [lit, ui._pick["options"].size()])
	# One pick and the whole rider is resolved: the direction was never a
	# question, so there is no second step to answer.
	ui.choose_pick(ui._pick["options"][0])
	check(ui._pick.is_empty(), "picking the man is the whole of the rider")
	await _settle(ui)
	check(ui.engine.state.player_formation.slots != slots_before,
			"the mandatory rider actually moved a man")
	check(ui._awaiting_action, "back to waiting after the rider resolves")

	# Reinforce names the slot its man lands in: drag the card onto a lit
	# empty slot, then pick who comes over the rail.
	if ui.engine.outcome == CombatEngine.Outcome.NONE and ui._awaiting_action:
		var reinforce: CardData = null
		for c: CardData in ui.engine.state.hand:
			if c.id == "reinforce":
				reinforce = c
		if reinforce == null:
			reinforce = CardLibrary.reinforce()
			_put_in_hand(ui, reinforce)
		ui.engine.state.momentum = maxi(ui.engine.state.momentum, reinforce.cost)
		ui.refresh(ui.engine.state)
		var target_slot = null
		for child in ui._player_back_row.get_children():
			if child is SlotPanel and target_slot == null:
				target_slot = child
		check(target_slot != null, "an empty second-line slot to reinforce into")
		if target_slot != null:
			check(ui.can_drop_card_on_slot(reinforce, Character.Side.PLAYER,
					target_slot.line, target_slot.col), "the empty slot takes Reinforce")
			check(not ui.can_drop_card_on(reinforce, ui.engine.state.player_formation.fielded()[0]),
					"a card that names a slot is not dropped on a man")
			var index := Formation.slot_index(target_slot.line, target_slot.col)
			var view = _card_view(ui, reinforce)
			check(view != null and view.draggable, "the Reinforce card can be picked up")
			await _drag(view.get_global_rect().get_center(),
					target_slot.get_global_rect().get_center())
			check(not ui._pick.is_empty(), "dropping Reinforce asks who comes over")
			var crosser: Character = ui._pick["options"][0]["value"]
			check(ui._pick_cancel_button.visible, "a card pick can still be backed out of")
			ui.choose_pick(ui._pick["options"][0])
			await _settle(ui)
			check(ui.engine.state.player_formation.slots[index] == crosser,
					"the man crossed into the slot the card was dropped on")
	else:
		skipped.append("the Reinforce slot drag (battle already decided)")

	# The opening's FREE CROSSING, answered the way a player answers it: end
	# the turn, catch the next one at its opening, press Reinforce, name the
	# man, and click the lit slot with a real mouse event.
	if ui.engine.outcome == CombatEngine.Outcome.NONE and ui._awaiting_action:
		ui.submit({"op": "end"})
		await _await_opening(ui)
	if ui._awaiting_opening and ui._opening_options.has("reinforce"):
		var reserve_before: int = ui.engine.state.player_reserve.size()
		var hand_at_opening: int = ui.engine.state.hand.size()
		(ui._opening_buttons["reinforce"] as Button).pressed.emit()
		for i in 3:
			await process_frame
		check(not ui._opening_bar.visible, "the bar steps aside while its pick is open")
		var crosser: Character = null
		if not ui._pick.is_empty() and ui._pick["options"][0].get("character") != null:
			crosser = ui._pick["options"][0]["value"]
			check(ui._pick_cancel_button.visible, "the opening's pick can be backed out of")
			ui.choose_pick(ui._pick["options"][0])
			for i in 3:
				await process_frame
		var lit_slot = null
		for row in [ui._player_front_row, ui._player_back_row]:
			for child in row.get_children():
				if child is SlotPanel and lit_slot == null \
						and not child.pick_option.is_empty():
					lit_slot = child
		check(lit_slot != null, "the free slots are lit for the crossing")
		if lit_slot != null:
			var index := Formation.slot_index(lit_slot.line, lit_slot.col)
			await _click(lit_slot.get_global_rect().get_center())
			await _settle(ui)
			check(crosser == null or ui.engine.state.player_formation.slots[index] == crosser,
					"clicking the lit slot is where the free crossing put him")
			check(ui.engine.state.player_reserve.size() == reserve_before - 1,
					"one man fewer on the ship")
			check(ui.engine.state.hand.size() == hand_at_opening,
					"a free crossing draws nothing — that is what it costs")
	else:
		skipped.append("the opening's free crossing (battle already decided)")

	# End several turns; pace timers run on real frames headlessly.
	var turns_seen: Array[int] = [ui.engine.state.turn]
	for round in 3:
		if ui.engine.outcome != CombatEngine.Outcome.NONE:
			break
		ui.submit({"op": "end"})
		await _await_player(ui)
		turns_seen.append(ui.engine.state.turn)
	check(turns_seen[-1] > 1 or ui.engine.outcome != CombatEngine.Outcome.NONE,
			"turns advance through the UI controller, saw %s" % str(turns_seen))
	check(ui._log_lines_shown > 0, "battle log rendered lines")

	# Debug restart with a different seed mid-battle: back to the picker.
	var old_engine = ui.engine
	ui.battle_seed = 777
	ui.start_battle()
	await _await_until(func() -> bool:
		return ui.engine != old_engine and ui._maneuver_layer.visible,
		"restarted battle offers the maneuver picker")
	check(ui.engine != old_engine, "restart builds a fresh engine")
	_press_maneuver(ui, "grapple_rush")
	await _await_until(func() -> bool:
		return ui.engine.state.turn >= 1 and ui._awaiting_opening,
		"restarted battle asking for its opening")
	await _await_player(ui)
	check(ui.engine.state.turn >= 1, "restarted battle is running")
	check(ui._awaiting_action, "restarted battle waits for player input")

	# Roster editing through the debug panel path.
	var bad := RosterText.parse("[player field]\nGuy | flail")
	check(bad["errors"].size() >= 1, "parser reports errors for the panel")

	# The hand cycles: end a turn and the non-retained cards are replaced.
	await _await_player(ui)
	check(ui._awaiting_action, "awaiting input before the hand-cycle test")
	var old_cyclers: Array = []
	for card: CardData in ui.engine.state.hand:
		if not card.retained:
			old_cyclers.append(card)
	check(old_cyclers.size() > 0, "some non-retained cards in hand to cycle")
	ui._end_turn_button.pressed.emit()
	await _await_player(ui)
	if ui.engine.outcome == CombatEngine.Outcome.NONE:
		for card: CardData in old_cyclers:
			check(not ui.engine.state.hand.has(card),
					"non-retained card cycled out of hand: " + card.id)
		check(ui.engine.state.hand.size() == 6,
				"hand refilled to 5, plus the opening's income card")

	# Drag a targeted card onto a token (heal an ally).
	await _await_player(ui)
	var rally: CardData = null
	for c: CardData in ui.engine.state.hand:
		if c.id == "rally" and c.cost <= ui.engine.state.momentum:
			rally = c
	if rally != null:
		# Rally makes its man give ground, so the engine refuses it on anyone
		# whose second-line slot is taken. Ask it, do not guess.
		var wounded: Character = null
		for ch: Character in ui.engine.state.fielded(Character.Side.PLAYER):
			if ch.hp < ch.max_hp and ui.engine.can_play(rally, ch):
				wounded = ch
		if wounded != null:
			var hp_before := wounded.hp
			var rally_view = null
			for v in ui._hand_row.get_children():
				if v.card == rally:
					rally_view = v
			var token = null
			for t in _tokens_in(ui._player_front_row) + _tokens_in(ui._player_back_row):
				if t.character == wounded:
					token = t
			await _drag(rally_view.get_global_rect().get_center(), token.get_global_rect().get_center())
			await _settle(ui)
			check(wounded.hp > hp_before, "rally drag-dropped on a token healed it")

	# The reserve row grew a swap hint; the table must still fit the canvas
	# the stretch mode scales (project.godot: 1280x800).
	check(ui.get_combined_minimum_size().y <= 800,
			"the table still fits the 800px canvas (needs %d)" % ui.get_combined_minimum_size().y)
	check(ui.get_combined_minimum_size().x <= 1280,
			"the table still fits the 1280px canvas (needs %d)" % ui.get_combined_minimum_size().x)

	# The prow pair in the reserve row: the captain can never be committed,
	# so he is dimmed rather than eating a dead click — and the Swap that
	# brings him over is one click on the hint. Last, because it puts the
	# captain in the fight.
	await _settle(ui)
	var captain: Character = ui.engine.state.player_captain
	var prowman: Character = ui.engine.state.player_prowman
	if ui.engine.outcome == CombatEngine.Outcome.NONE and ui._awaiting_action \
			and prowman != null and ui.engine.state.player_formation.has(prowman) \
			and ui.engine.state.player_reserve.has(captain):
		var captain_token = _reserve_token(ui, captain)
		check(captain_token != null, "the waiting captain has a token in the reserve row")
		if captain_token != null:
			check(captain_token.display.get("dim", false),
					"the un-committable captain reads as dimmed")
			check(captain_token.display.get("hint", "") != "",
					"and carries his swap hint")
			var swap_card := CardLibrary.swap()
			_put_in_hand(ui, swap_card)
			ui.engine.state.momentum = maxi(ui.engine.state.momentum, swap_card.cost)
			ui.refresh(ui.engine.state)
			captain_token = _reserve_token(ui, captain)
			check(captain_token.display.get("hint_lit", false),
					"the hint lights up while a Swap is playable")
			captain_token.clicked.emit(captain)
			await _settle(ui)
			check(ui.engine.state.player_formation.has(captain),
					"clicking the lit hint traded the pair over the rail")
			check(ui.engine.state.player_reserve.has(prowman),
					"and the prowman came back aboard")
	else:
		skipped.append("the prow-pair reserve row (battle already decided)")

	# Last look, with the board as full and as lit as this run ever got it.
	await check_fits_canvas(ui, "late battle")
	# Kept to the end: this one fakes a card pick-up, and a faked drag would
	# disturb the real drag-and-drop checks above.
	await check_lighting_does_not_move_the_board(ui)

	ui.queue_free()
	for i in 3:
		await process_frame

	if failures.is_empty():
		print("UI SMOKE OK — %d checks%s" % [checks,
				"" if skipped.is_empty() else " (skipped: %s)" % ", ".join(skipped)])
		quit(0)
	else:
		for f in failures:
			print("UI SMOKE FAIL: " + f)
		quit(1)
