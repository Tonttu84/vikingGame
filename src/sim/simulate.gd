extends SceneTree
## Headless balance harness: runs N battles and prints aggregate stats.
##
##   godot --headless -s src/sim/simulate.gd -- --n=1000 --bot=random --seed=1
##   godot --headless -s src/sim/simulate.gd -- --bot=none --verbose
##
## --bot=random (default) plays random affordable cards; --bot=none is the
## no-card baseline, which tuning should keep at a narrow loss.
## --verbose prints the full battle log of the first battle.


func _init() -> void:
	var n := 200
	var bot_kind := "random"
	var base_seed := 1
	var verbose := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--n="):
			n = int(arg.trim_prefix("--n="))
		elif arg.begins_with("--bot="):
			bot_kind = arg.trim_prefix("--bot=")
		elif arg.begins_with("--seed="):
			base_seed = int(arg.trim_prefix("--seed="))
		elif arg == "--verbose":
			verbose = true

	var outcomes := {}
	var total_turns := 0
	var total_dead := 0
	var total_fled := 0
	var total_enemy_dead := 0
	var total_enemy_routed := 0

	for i in n:
		var engine := CombatEngine.new()
		var bot_rng := RandomNumberGenerator.new()
		bot_rng.seed = base_seed + i
		var bot = Bots.NoCardBot.new() if bot_kind == "none" else Bots.RandomBot.new(bot_rng)
		engine.setup(Scenarios.default_skirmish(), bot, base_seed + i)
		var result := engine.run()
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

	print("=== %d battles | bot=%s | base seed %d ===" % [n, bot_kind, base_seed])
	for key in ["VICTORY", "DEFEAT", "RETREAT", "STALEMATE"]:
		if outcomes.has(key):
			print("%-10s %5d  (%.1f%%)" % [key, outcomes[key], 100.0 * outcomes[key] / n])
	print("avg turns          %.1f" % (float(total_turns) / n))
	print("avg crew dead      %.2f" % (float(total_dead) / n))
	print("avg crew fled      %.2f" % (float(total_fled) / n))
	print("avg enemies slain  %.2f" % (float(total_enemy_dead) / n))
	print("avg enemies routed %.2f" % (float(total_enemy_routed) / n))
	quit(0)
