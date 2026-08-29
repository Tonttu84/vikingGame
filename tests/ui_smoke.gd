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
## asks on the way. A pick always takes the first lit option — the same move
## the engine falls back to for a controller that cannot choose — so a
## mandatory movement rider never parks the battle here.
func _settle(ui, max_frames := 600) -> void:
	for i in max_frames:
		if not ui._pick.is_empty():
			ui.choose_pick(ui._pick["options"][0])
			continue
		if ui._awaiting_action or ui.engine.outcome != CombatEngine.Outcome.NONE:
			return
		await process_frame
	failures.append("timed out settling the board")


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
	check(ui._maneuver_options.get_child_count() == 4,
			"4 maneuvers offered, saw %d" % ui._maneuver_options.get_child_count())
	# Pick Dawn Raid — NOT the engine's first-option fallback — to prove the
	# player's choice reaches the engine.
	_press_maneuver(ui, "dawn_raid")
	await _await_until(func() -> bool:
		return ui.engine.state.turn == 1 and ui._awaiting_action,
		"battle running (boarding done) and waiting for the player")

	check(ui.engine.state.turn == 1, "battle started on turn 1")
	check(ui._awaiting_action, "UI is waiting for the player")
	check(not ui._maneuver_layer.visible, "picker hidden after the pick")
	check(ui.engine.state.boarding_maneuver != null
			and ui.engine.state.boarding_maneuver.id == "dawn_raid",
			"Dawn Raid is the maneuver that resolved")
	check(ui.engine.state.momentum >= 4, "the maneuver surge came through (momentum %d)" % ui.engine.state.momentum)
	check(ui._hand_row.get_child_count() == 5, "hand shows 5 cards, saw %d" % ui._hand_row.get_child_count())
	check(_tokens_in(ui._player_front_row).size() == 3, "first wave of 3 on their deck")
	check(ui._player_front_row.get_child_count() == 4, "the front line renders all 4 column slots")
	check(ui.engine.state.enemy_formation.size() == 2,
			"Dawn Raid caught 3 of 5 defenders below decks, saw %d fielded" % ui.engine.state.enemy_formation.size())
	check(_tokens_in(ui._enemy_front_row).size() + _tokens_in(ui._enemy_back_row).size() == 2,
			"both fielded defenders drawn in the grid")
	check(ui._momentum_pips.get_child_count() == 10, "momentum pips")

	# The forecast badges: whoever stands in a contested column shows the
	# damage he is about to take, without the player doing the sums.
	var badge_found := false
	for t in _tokens_in(ui._player_front_row):
		if t.get_meta("forecast_hp", 0) > 0:
			badge_found = true
	check(badge_found, "a front-liner in a contested column shows incoming damage")

	# A card with a movement rider: the punch lands, then the board asks
	# which man moves. Shield Wall's rider trades two men on deck, so with a
	# three-man first wave the engine hands over a real choice — and being
	# mandatory, it offers no way out.
	var wall := CardLibrary.shield_wall()
	ui.engine.state.hand.append(wall)
	ui.engine.state.momentum = maxi(ui.engine.state.momentum, wall.cost)
	ui.refresh(ui.engine.state)
	var slots_before: Array = ui.engine.state.player_formation.slots.duplicate()
	ui.play_card(wall, null)
	await _await_until(func() -> bool: return not ui._pick.is_empty(),
			"the rider asks which man moves")
	check(ui._pick["prompt"].contains("Shield Wall") and ui._pick["prompt"].contains("swap"),
			"the prompt names the card and the rider, saw: %s" % ui._pick.get("prompt", ""))
	check(not ui._pick_cancel_button.visible, "a mandatory rider offers no cancel")
	check(ui._end_turn_button.disabled, "the turn cannot be ended out from under a pick")
	var lit := 0
	for t in _tokens_in(ui._player_front_row) + _tokens_in(ui._player_back_row):
		if t.highlighted():
			lit += 1
	check(lit == ui._pick["options"].size(),
			"every man the engine offered is lit (%d lit, %d offered)" % [lit, ui._pick["options"].size()])
	ui.choose_pick(ui._pick["options"][0])
	check(not ui._pick.is_empty(), "and then where he goes")
	ui.choose_pick(ui._pick["options"][0])
	await _settle(ui)
	check(ui.engine.state.player_formation.slots != slots_before,
			"the mandatory rider actually moved men")
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
			ui.engine.state.hand.append(reinforce)
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

	# Clicking a man on your own ship asks which slot he takes, and a lit slot
	# answers a real mouse click — not just the driver's shortcut.
	if ui.engine.outcome == CombatEngine.Outcome.NONE and ui._awaiting_action:
		ui.engine.state.momentum = maxi(ui.engine.state.momentum,
				BattleState.RESERVE_COMMIT_COST)
		ui.refresh(ui.engine.state)
		var crew: Character = null
		for c: Character in ui.engine.state.player_reserve:
			if crew == null and ui.engine.can_commit(c):
				crew = c
		check(crew != null, "someone on the ship can still be sent over")
		if crew != null:
			var crew_token = _reserve_token(ui, crew)
			check(crew_token != null and not crew_token.display.get("dim", false),
					"a man who can be sent over is not dimmed")
			crew_token.clicked.emit(crew)
			check(not ui._pick.is_empty(), "committing a man asks which slot he takes")
			for i in 3:
				await process_frame
			var lit_slot = null
			for row in [ui._player_front_row, ui._player_back_row]:
				for child in row.get_children():
					if child is SlotPanel and lit_slot == null \
							and not child.pick_option.is_empty():
						lit_slot = child
			check(lit_slot != null, "the free slots are lit for that pick")
			if lit_slot != null:
				var index := Formation.slot_index(lit_slot.line, lit_slot.col)
				await _click(lit_slot.get_global_rect().get_center())
				await _settle(ui)
				check(ui.engine.state.player_formation.slots[index] == crew,
						"clicking the lit slot is where he took his place")
	else:
		skipped.append("the commit slot pick (battle already decided)")

	# End several turns; pace timers run on real frames headlessly.
	var turns_seen: Array[int] = [ui.engine.state.turn]
	for round in 3:
		if ui.engine.outcome != CombatEngine.Outcome.NONE:
			break
		ui.submit({"op": "end"})
		var guard := 0
		while guard < 600 and ui.engine.outcome == CombatEngine.Outcome.NONE \
				and not ui._awaiting_action:
			guard += 1
			await process_frame
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
		return ui.engine.state.turn >= 1 and ui._awaiting_action,
		"restarted battle waiting for player input")
	check(ui.engine.state.turn >= 1, "restarted battle is running")
	check(ui._awaiting_action, "restarted battle waits for player input")

	# Roster editing through the debug panel path.
	var bad := RosterText.parse("[player field]\nGuy | flail")
	check(bad["errors"].size() >= 1, "parser reports errors for the panel")

	# The hand cycles: end a turn and the non-retained cards are replaced.
	var guard2 := 0
	while guard2 < 600 and not ui._awaiting_action:
		guard2 += 1
		await process_frame
	check(ui._awaiting_action, "awaiting input before the hand-cycle test")
	var old_cyclers: Array = []
	for card: CardData in ui.engine.state.hand:
		if not card.retained:
			old_cyclers.append(card)
	check(old_cyclers.size() > 0, "some non-retained cards in hand to cycle")
	ui._end_turn_button.pressed.emit()
	await _await_until(func() -> bool: return ui._awaiting_action,
		"next turn after the hand-cycle end-turn")
	if ui.engine.outcome == CombatEngine.Outcome.NONE:
		for card: CardData in old_cyclers:
			check(not ui.engine.state.hand.has(card),
					"non-retained card cycled out of hand: " + card.id)
		check(ui.engine.state.hand.size() == 5, "hand refilled to 5")

	# Drag a targeted card onto a token (heal an ally).
	guard2 = 0
	while guard2 < 600 and not ui._awaiting_action:
		guard2 += 1
		await process_frame
	var rally: CardData = null
	for c: CardData in ui.engine.state.hand:
		if c.id == "rally" and c.cost <= ui.engine.state.momentum:
			rally = c
	if rally != null:
		var wounded: Character = null
		for ch: Character in ui.engine.state.fielded(Character.Side.PLAYER):
			if ch.hp < ch.max_hp:
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
			ui.engine.state.hand.append(swap_card)
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
