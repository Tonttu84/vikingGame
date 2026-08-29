extends SceneTree
## Headless balance harness: runs N battles and prints aggregate stats.
##
##   godot --headless -s src/sim/simulate.gd -- --n=1000 --bot=random --seed=1
##   godot --headless -s src/sim/simulate.gd -- --bot=none --verbose
##
## --bot=random (default) plays random affordable cards; --bot=none is the
## no-card baseline, which tuning should keep at a narrow loss.
## --scenario=skirmish (default) or veteran picks the balance anchor.
## --artifacts=raven_banner,serpent_prow equips artifacts for every battle.
## --maneuver=dawn_raid forces one boarding maneuver (default: bot picks).
## --verbose prints the full battle log of the first battle.
##
## Crew is permanent once the raid loop lands, so a win is not just a win:
## the report grades victories by their body count. Tune against the cost
## of winning, not the win rate alone.


func _init() -> void:
	var n := 200
	var bot_kind := "random"
	var base_seed := 1
	var verbose := false
	var artifact_ids: Array[String] = []
	var maneuver_id := ""
	var scenario_id := "skirmish"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--n="):
			n = int(arg.trim_prefix("--n="))
		elif arg.begins_with("--bot="):
			bot_kind = arg.trim_prefix("--bot=")
		elif arg.begins_with("--scenario="):
			scenario_id = arg.trim_prefix("--scenario=")
			if Scenarios.by_id(scenario_id).is_empty():
				push_error("unknown scenario '%s' (known: %s)" % [scenario_id, ", ".join(Scenarios.scenario_ids())])
				quit(2)
				return
		elif arg.begins_with("--seed="):
			base_seed = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--artifacts="):
			for id in arg.trim_prefix("--artifacts=").split(",", false):
				if ArtifactLibrary.by_id(id) == null:
					push_error("unknown artifact '%s' (known: %s)" % [id, ", ".join(ArtifactLibrary.artifact_ids())])
					quit(2)
					return
				artifact_ids.append(id)
		elif arg.begins_with("--maneuver="):
			maneuver_id = arg.trim_prefix("--maneuver=")
			if CardLibrary.maneuver_by_id(maneuver_id) == null:
				push_error("unknown maneuver '%s' (known: %s)" % [maneuver_id, ", ".join(CardLibrary.maneuver_ids())])
				quit(2)
				return
		elif arg == "--verbose":
			verbose = true

	var outcomes := {}
	var total_turns := 0
	var total_dead := 0
	var total_fled := 0
	var total_enemy_dead := 0
	var total_enemy_routed := 0
	var wins := 0
	var win_dead := 0
	var win_fled := 0
	var win_dead_counts := {}

	for i in n:
		var engine := CombatEngine.new()
		var bot_rng := RandomNumberGenerator.new()
		bot_rng.seed = base_seed + i
		var bot = Bots.NoCardBot.new() if bot_kind == "none" else Bots.RandomBot.new(bot_rng)
		if bot is Bots.RandomBot:
			bot.engine = engine  # so it asks the engine what is legal, as the UI does
		var scenario := Scenarios.by_id(scenario_id)
		var artifacts: Array[ArtifactData] = []
		for id in artifact_ids:
			artifacts.append(ArtifactLibrary.by_id(id))
		scenario["artifacts"] = artifacts
		if maneuver_id != "":
			var forced: Array[CardData] = [CardLibrary.maneuver_by_id(maneuver_id)]
			scenario["maneuvers"] = forced
		engine.setup(scenario, bot, base_seed + i)
		var result: Dictionary = await engine.run()
		if verbose and i == 0:
			for line in engine.state.battle_log:
				print(line)
			print("")
		outcomes[result["outcome"]] = outcomes.get(result["outcome"], 0) + 1
		total_turns += result["turns"]
		total_dead += result["player_dead"]
		total_fled += result["player_fled"]
		total_enemy_dead += result["enemy_dead"]
		total_enemy_routed += result["enemy_routed"]
		if result["outcome"] == "VICTORY":
			wins += 1
			win_dead += result["player_dead"]
			win_fled += result["player_fled"]
			var d: int = result["player_dead"]
			win_dead_counts[d] = win_dead_counts.get(d, 0) + 1

	print("=== %d battles | scenario=%s | bot=%s | base seed %d ===" % [n, scenario_id, bot_kind, base_seed])
	for key in ["VICTORY", "DEFEAT", "RETREAT", "STALEMATE"]:
		if outcomes.has(key):
			print("%-10s %5d  (%.1f%%)" % [key, outcomes[key], 100.0 * outcomes[key] / n])
	print("avg turns          %.1f" % (float(total_turns) / n))
	print("avg crew dead      %.2f" % (float(total_dead) / n))
	print("avg crew fled      %.2f" % (float(total_fled) / n))
	print("avg enemies slain  %.2f" % (float(total_enemy_dead) / n))
	print("avg enemies routed %.2f" % (float(total_enemy_routed) / n))
	if wins > 0:
		print("--- the cost of victory (crew losses are permanent between raids) ---")
		print("avg dead in a win  %.2f   avg fled in a win  %.2f"
				% [float(win_dead) / wins, float(win_fled) / wins])
		var dead_values: Array = win_dead_counts.keys()
		dead_values.sort()
		var parts: Array[String] = []
		for d in dead_values:
			parts.append("%d dead: %d (%.0f%%)" % [d, win_dead_counts[d], 100.0 * win_dead_counts[d] / wins])
		print("wins by body count  " + "  |  ".join(parts))
	quit(0)
