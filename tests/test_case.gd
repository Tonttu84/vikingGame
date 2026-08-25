class_name TestCase
extends RefCounted
## Minimal assertion collector. The runner sets the current method name and
## calls every method starting with "test_"; failures are gathered, not fatal.

var failures: Array[String] = []
var checks := 0
var current_test := ""


func assert_true(condition: bool, message: String = "") -> void:
	checks += 1
	if not condition:
		failures.append("%s: expected true. %s" % [current_test, message])


func assert_false(condition: bool, message: String = "") -> void:
	assert_true(not condition, message)


func assert_eq(actual, expected, message: String = "") -> void:
	checks += 1
	if actual != expected:
		failures.append("%s: got %s, expected %s. %s" % [current_test, str(actual), str(expected), message])
