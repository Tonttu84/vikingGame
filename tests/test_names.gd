extends TestCase
## NameForge: Old Norse first names for the crews and the levies, drawn
## through a seeded RNG (determinism is a hard invariant) and never repeated
## within one forge, so two Orms never share a deck. The uniques' hand-picked
## names are reserved so a generated crewman cannot double them.


func test_the_same_seed_forges_the_same_names() -> void:
	var a := NameForge.new(7)
	var b := NameForge.new(7)
	var first: Array[String] = []
	var second: Array[String] = []
	for i in 6:
		first.append(a.given())
		second.append(b.given())
	assert_eq(first, second, "seeded: the crew is the same crew every time")
	assert_true(NameForge.new(8).given() != first[0] or NameForge.new(9).given() != first[0],
			"and a different seed is a different crew")


func test_a_forge_never_repeats_a_name_while_the_pool_lasts() -> void:
	var forge := NameForge.new(3)
	var seen := {}
	for i in NameForge.MALE.size():
		var name := forge.given()
		assert_false(seen.has(name), "%s was already forged" % name)
		seen[name] = true
	assert_eq(seen.size(), NameForge.MALE.size(), "every name in the pool came out exactly once")


func test_an_exhausted_pool_forges_younger_namesakes() -> void:
	var forge := NameForge.new(3)
	for i in NameForge.MALE.size():
		forge.given()
	var extra := forge.given()
	assert_true(extra.ends_with(" the Younger"), "past the pool: a namesake, never a blank")
	assert_true(NameForge.MALE.has(extra.trim_suffix(" the Younger")), "built from a real name")


func test_reserved_names_are_never_forged() -> void:
	var forge := NameForge.new(5)
	forge.reserve("Sten")
	forge.reserve("Aslak")
	for i in NameForge.MALE.size() - 2:
		var name := forge.given()
		assert_true(name != "Sten" and name != "Aslak", "%s: the uniques' names are theirs alone" % name)


func test_the_women_of_the_crew_have_their_own_pool() -> void:
	var forge := NameForge.new(11)
	var name := forge.given_female()
	assert_true(NameForge.FEMALE.has(name), "")
	assert_false(NameForge.MALE.has(name), "the pools do not overlap")
	var seen := {}
	for i in NameForge.FEMALE.size() - 1:
		var next := forge.given_female()
		assert_false(seen.has(next) or next == name, "no repeats among the women either")
		seen[next] = true


func test_every_pool_name_is_a_single_word() -> void:
	for name in NameForge.MALE + NameForge.FEMALE:
		assert_false(name.contains(" "), "%s: the convention wants '<Role> <first name>'" % name)
