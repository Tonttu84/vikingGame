extends SceneTree
## End-to-end smoke test for the battle UI: boot the scene, end turns
## through the real controller path, drag-and-drop cards with synthesized
## mouse events, restart from the debug path. Needs a display for GUI input
## routing — run via scripts/ui_smoke.sh (xvfb), not --headless.

var failures: Array[String] = []


func check(cond: bool, msg: String) -> void:
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


func _init() -> void:
	call_deferred("_run")


## The engine paces itself for animations (0.3s beats), so the smoke test
## waits on conditions, never on fixed frame counts.
func _await_until(predicate: Callable, what: String, max_frames := 300) -> void:
	for i in max_frames:
		if predicate.call():
			return
		await process_frame
	failures.append("timed out waiting for: " + what)


func _run() -> void:
	var scene: PackedScene = load("res://src/ui/battle_ui.tscn")
	check(scene != null, "battle scene loads")
	var ui = scene.instantiate()
	root.add_child(ui)
	await _await_until(func() -> bool:
		return ui.engine != null and ui.engine.state.turn == 1 and ui._awaiting_action,
		"battle running (boarding done) and waiting for the player")

	check(ui.engine != null, "engine created")
	check(ui.engine.state.turn == 1, "battle started on turn 1")
	check(ui._awaiting_action, "UI is waiting for the player")
	check(ui.engine.state.boarding_maneuver != null, "a boarding maneuver was played")
	check(ui.engine.state.momentum >= 4, "the maneuver surge came through (momentum %d)" % ui.engine.state.momentum)
	check(ui._hand_row.get_child_count() == 5, "hand shows 5 cards, saw %d" % ui._hand_row.get_child_count())
	check(ui._player_field_row.get_child_count() == 3, "first wave of 3 on their deck")
	check(ui._enemy_field_row.get_child_count() == 5, "5 surprised defenders fielded")
	check(ui._momentum_pips.get_child_count() == 10, "momentum pips")

	# Play a no-target card if one is affordable, exercising the drop path.
	var played := false
	for card: CardData in ui.engine.state.hand.duplicate():
		if card.playable and card.target_type == CardData.TargetType.NONE \
				and card.cost <= ui.engine.state.momentum:
			ui.play_card(card, null)
			played = true
			break
	if played:
		for i in 10:
			await process_frame
		check(ui._awaiting_action, "back to waiting after a card resolves")

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

	# Debug restart with a different seed mid-battle.
	var old_engine = ui.engine
	ui.battle_seed = 777
	ui.start_battle()
	await _await_until(func() -> bool:
		return ui.engine != old_engine and ui.engine.state.turn >= 1,
		"restarted battle running")
	check(ui.engine != old_engine, "restart builds a fresh engine")
	check(ui.engine.state.turn >= 1, "restarted battle is running")
	await _await_until(func() -> bool: return ui._awaiting_action,
		"restarted battle waiting for player input")
	check(ui._awaiting_action, "restarted battle waits for player input")

	# Roster editing through the debug panel path.
	var bad := RosterText.parse("[player field]\nGuy | flail")
	check(bad["errors"].size() >= 1, "parser reports errors for the panel")

	# Real drag-and-drop with synthesized mouse events: scrap a card.
	var guard2 := 0
	while guard2 < 600 and not ui._awaiting_action:
		guard2 += 1
		await process_frame
	check(ui._awaiting_action, "awaiting input before drag test")
	var hand_before: int = ui.engine.state.hand.size()
	var momentum_before: int = ui.engine.state.momentum
	var card_view = ui._hand_row.get_child(0)
	var scrap_value: int = card_view.card.scrap_value
	var from: Vector2 = card_view.get_global_rect().get_center()
	var to: Vector2 = ui._scrap_zone.get_global_rect().get_center()
	await _drag(from, to)
	for i in 10:
		await process_frame
	check(ui.engine.state.hand.size() == hand_before - 1,
			"drag to scrap removed a card from hand (%d -> %d)" % [hand_before, ui.engine.state.hand.size()])
	check(ui.engine.state.momentum == momentum_before + scrap_value,
			"scrap paid %d momentum" % scrap_value)
	check(ui.engine.state.scrapped_this_turn, "scrap flag set")

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
		for ch: Character in ui.engine.state.player_field:
			if ch.hp < ch.max_hp:
				wounded = ch
		if wounded != null:
			var hp_before := wounded.hp
			var rally_view = null
			for v in ui._hand_row.get_children():
				if v.card == rally:
					rally_view = v
			var token = null
			for t in ui._player_field_row.get_children():
				if t.character == wounded:
					token = t
			await _drag(rally_view.get_global_rect().get_center(), token.get_global_rect().get_center())
			for i in 10:
				await process_frame
			check(wounded.hp > hp_before, "rally drag-dropped on a token healed it")

	ui.queue_free()
	for i in 3:
		await process_frame

	if failures.is_empty():
		print("UI SMOKE OK")
		quit(0)
	else:
		for f in failures:
			print("UI SMOKE FAIL: " + f)
		quit(1)
