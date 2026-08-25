extends SceneTree
## Test runner:  godot --headless -s tests/run_tests.gd
## Discovers tests/test_*.gd, runs every method starting with "test_",
## prints a summary and exits non-zero on failure.


func _init() -> void:
	var total_checks := 0
	var all_failures: Array[String] = []
	var files := DirAccess.get_files_at("res://tests")
	files.sort()
	for file in files:
		if not file.begins_with("test_") or not file.ends_with(".gd") or file == "test_case.gd":
			continue
		var suite = load("res://tests/" + file).new()
		var methods: Array[String] = []
		for m in suite.get_method_list():
			if m["name"].begins_with("test_"):
				methods.append(m["name"])
		methods.sort()
		for method in methods:
			suite.current_test = "%s::%s" % [file, method]
			suite.call(method)
		total_checks += suite.checks
		all_failures.append_array(suite.failures)
		var status := "OK  " if suite.failures.is_empty() else "FAIL"
		print("%s %-28s %d checks, %d failures" % [status, file, suite.checks, suite.failures.size()])
	print("")
	if all_failures.is_empty():
		print("All %d checks passed." % total_checks)
		quit(0)
	else:
		for f in all_failures:
			print("FAILED: " + f)
		print("%d of %d checks failed." % [all_failures.size(), total_checks])
		quit(1)
