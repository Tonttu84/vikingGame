class_name RosterText
extends RefCounted
## The debug panel's plain-text battle setup format. One character per line
## inside [section] headers; parse() builds a scenario Dictionary the engine
## accepts, serialize() writes one back out, and the two round-trip.
##
##   [player field]
##   Captain Aslak | hp 20 | morale 10 | str 4 | speed 4 | sword | armor 2 | captain
##   [enemy captain]
##   Jarl Sigvard | hp 25 | morale 10 | str 5 | speed 3 | sword | armor 2
##   [deck]
##   2x spear_volley
##   [tactics]
##   arrow_volley
##   [artifacts]
##   raven_banner
##
## Stat tokens may appear in any order and fall back to a standard grunt
## (hp 12, morale 6, str 3, speed 3, fists, armor 0) when omitted. `armor` is
## the man's guard (docs/block-and-patterns.md): the block he raises each of
## his side's turns, not a damage reduction. Flags:
## `captain` (player side; the enemy captain has its own section),
## `prowman` (player side, the captain's alternate at the prow),
## `berserker` and `shieldman`. Field sections also take a slot token —
## `f1`..`f4` for the
## front line, `b1`..`b4` for the second — naming the grid slot the man
## starts in; without one he auto-places front-left first. Lines starting
## with # and blank lines are ignored.

const CHARACTER_SECTIONS := ["player field", "player reserve", "enemy field", "enemy reserve", "enemy captain"]
const KNOWN_TACTICS := [
	"press_the_attack", "arrow_volley", "fear_horn", "reinforcement_surge",
	"fresh_men_forward", "shift_larboard", "shift_starboard", "step_up",
]
const STAT_KEYS := ["hp", "morale", "str", "speed", "armor"]
const WEAPON_NAMES := ["fists", "spear", "axe", "sword", "bow"]


## Returns {"scenario": Dictionary, "errors": Array[String]}. The scenario is
## best-effort when errors are present; callers should refuse to start a
## battle unless errors is empty.
static func parse(text: String) -> Dictionary:
	var errors: Array[String] = []
	var rosters := {}
	for section in CHARACTER_SECTIONS:
		var list: Array[Character] = []
		rosters[section] = list
	var deck: Array[CardData] = []
	var deck_section_seen := false
	var tactics: Array[String] = []
	var artifacts: Array[ArtifactData] = []
	var maneuvers: Array[CardData] = []
	var section := ""
	var serial := 0

	var lines := text.split("\n")
	for i in lines.size():
		var line := lines[i].strip_edges()
		var lineno := i + 1
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2).strip_edges().to_lower()
			if section == "deck":
				deck_section_seen = true
			elif not CHARACTER_SECTIONS.has(section) and section != "tactics" \
					and section != "artifacts" and section != "maneuvers":
				errors.append("line %d: unknown section [%s]" % [lineno, section])
				section = ""
			continue
		match section:
			"":
				errors.append("line %d: '%s' is outside any [section]" % [lineno, line])
			"deck":
				_parse_deck_line(line, lineno, deck, errors)
			"tactics":
				if KNOWN_TACTICS.has(line):
					tactics.append(line)
				else:
					errors.append("line %d: unknown tactic '%s' (known: %s)" % [lineno, line, ", ".join(KNOWN_TACTICS)])
			"artifacts":
				var artifact := ArtifactLibrary.by_id(line)
				if artifact != null:
					artifacts.append(artifact)
				else:
					errors.append("line %d: unknown artifact '%s' (known: %s)" % [lineno, line, ", ".join(ArtifactLibrary.artifact_ids())])
			"maneuvers":
				var maneuver := CardLibrary.maneuver_by_id(line)
				if maneuver != null:
					maneuvers.append(maneuver)
				else:
					errors.append("line %d: unknown maneuver '%s' (known: %s)" % [lineno, line, ", ".join(CardLibrary.maneuver_ids())])
			_:
				serial += 1
				var c := _parse_character(line, lineno, section, serial, errors)
				if c != null:
					rosters[section].append(c)

	for field_section in ["player field", "enemy field"]:
		var fielded: Array[Character] = rosters[field_section]
		if fielded.size() > Formation.SLOT_COUNT:
			errors.append("[%s] holds %d men but the grid has %d slots" %
					[field_section, fielded.size(), Formation.SLOT_COUNT])
		var claimed := {}
		for c: Character in fielded:
			if c.deploy_slot < 0:
				continue
			if claimed.has(c.deploy_slot):
				errors.append("[%s]: %s and %s both claim slot %s" % [field_section,
						claimed[c.deploy_slot], c.display_name, _slot_name(c.deploy_slot)])
			claimed[c.deploy_slot] = c.display_name

	var enemy_captains: Array[Character] = rosters["enemy captain"]
	if enemy_captains.size() > 1:
		errors.append("[enemy captain] must hold exactly one character, found %d" % enemy_captains.size())
	elif enemy_captains.is_empty():
		errors.append("no [enemy captain] section: the battle needs an enemy captain")
	# The captain may lead the boarding or wait on his own ship — either
	# section is fine, but the crew needs exactly one of him.
	var player_captains := 0
	for section_name in ["player field", "player reserve"]:
		for c: Character in rosters[section_name]:
			if c.is_captain:
				player_captains += 1
	if player_captains != 1:
		errors.append("exactly one player character (field or reserve) must carry the 'captain' flag, found %d" % player_captains)

	var scenario := {
		"player_field": rosters["player field"],
		"player_reserve": rosters["player reserve"],
		"enemy_field": rosters["enemy field"],
		"enemy_reserve": rosters["enemy reserve"],
		"enemy_captain": enemy_captains[0] if not enemy_captains.is_empty() else null,
		"deck": deck if deck_section_seen else CardLibrary.starter_deck(),
		"enemy_tactics": tactics if not tactics.is_empty() else ["press_the_attack"],
		"artifacts": artifacts,
		"maneuvers": maneuvers if not maneuvers.is_empty() else CardLibrary.default_maneuvers(),
	}
	return {"scenario": scenario, "errors": errors}


static func serialize(scenario: Dictionary) -> String:
	var out: Array[String] = []
	for pair in [["player field", "player_field"], ["player reserve", "player_reserve"]]:
		out.append("[%s]" % pair[0])
		for c: Character in scenario.get(pair[1], []):
			out.append(_character_line(c))
		out.append("")
	var enemy_captain: Character = scenario.get("enemy_captain")
	if enemy_captain != null:
		out.append("[enemy captain]")
		out.append(_character_line(enemy_captain, true))
		out.append("")
	for pair in [["enemy field", "enemy_field"], ["enemy reserve", "enemy_reserve"]]:
		out.append("[%s]" % pair[0])
		for c: Character in scenario.get(pair[1], []):
			out.append(_character_line(c))
		out.append("")
	out.append("[tactics]")
	for t: String in scenario.get("enemy_tactics", []):
		out.append(t)
	out.append("")
	var artifacts: Array = scenario.get("artifacts", [])
	if not artifacts.is_empty():
		out.append("[artifacts]")
		for a: ArtifactData in artifacts:
			out.append(a.id)
		out.append("")
	var maneuvers: Array = scenario.get("maneuvers", [])
	if not maneuvers.is_empty():
		out.append("[maneuvers]")
		for m: CardData in maneuvers:
			out.append(m.id)
		out.append("")
	out.append("[deck]")
	var order: Array[String] = []
	var counts := {}
	for card: CardData in scenario.get("deck", []):
		if not counts.has(card.id):
			order.append(card.id)
		counts[card.id] = counts.get(card.id, 0) + 1
	for id in order:
		out.append("%dx %s" % [counts[id], id] if counts[id] > 1 else id)
	out.append("")
	return "\n".join(out)


static func _character_line(c: Character, is_captain_section := false) -> String:
	var parts := [
		c.display_name,
		"hp %d" % c.max_hp,
		"morale %d" % c.max_morale,
		"str %d" % c.strength,
		"speed %d" % c.speed,
		WEAPON_NAMES[c.weapon.kind],
		"armor %d" % c.armor,
	]
	if c.is_captain and not is_captain_section:
		parts.append("captain")
	if c.is_prowman:
		parts.append("prowman")
	if c.is_berserker:
		parts.append("berserker")
	if c.is_shieldman:
		parts.append("shieldman")
	if c.deploy_slot >= 0:
		parts.append(_slot_name(c.deploy_slot))
	return " | ".join(parts)


static func _parse_character(line: String, lineno: int, section: String, serial: int,
		errors: Array[String]) -> Character:
	var fields := line.split("|")
	var name := fields[0].strip_edges()
	if name.is_empty():
		errors.append("line %d: character has no name" % lineno)
		return null
	var side := Character.Side.PLAYER if section.begins_with("player") else Character.Side.ENEMY
	var stats := {"hp": 12, "morale": 6, "str": 3, "speed": 3, "armor": 0}
	var weapon: Weapon = null
	var is_captain := false
	var is_prowman := false
	var is_berserker := false
	var is_shieldman := false
	var deploy_slot := -1
	# Token errors are reported but the character is still built with what
	# parsed, so one typo doesn't cascade into missing-captain errors.
	for f in range(1, fields.size()):
		var token := fields[f].strip_edges().to_lower()
		if token.is_empty():
			continue
		var words := token.split(" ", false)
		if words.size() == 2 and STAT_KEYS.has(words[0]):
			if words[1].is_valid_int():
				stats[words[0]] = int(words[1])
			else:
				errors.append("line %d: '%s' is not a number in '%s'" % [lineno, words[1], token])
		elif WEAPON_NAMES.has(token):
			weapon = _weapon_by_name(token)
		elif token == "captain":
			is_captain = true
		elif token == "prowman":
			is_prowman = true
		elif token == "berserker":
			is_berserker = true
		elif token == "shieldman":
			is_shieldman = true
		elif _parse_slot_token(token) != -1:
			if section == "player field" or section == "enemy field":
				deploy_slot = _parse_slot_token(token)
			else:
				errors.append("line %d: slot '%s' means nothing in [%s] — only fielded men stand on the grid" % [lineno, token, section])
		else:
			errors.append("line %d: unknown token '%s' (stats, a weapon, a slot like f2/b3, 'captain', 'prowman', 'berserker' or 'shieldman')" % [lineno, token])
	if is_captain and side == Character.Side.ENEMY:
		errors.append("line %d: the enemy captain goes in its own [enemy captain] section" % lineno)
		is_captain = false
	var id := "%s_%d" % [_slug(name), serial]
	var c := Character.new(id, name, side, stats["hp"], stats["morale"], stats["str"], stats["speed"], weapon, stats["armor"])
	c.is_captain = is_captain or section == "enemy captain"
	c.is_prowman = is_prowman and side == Character.Side.PLAYER
	c.is_berserker = is_berserker
	c.is_shieldman = is_shieldman
	c.deploy_slot = deploy_slot
	return c


## `f1`..`f4` / `b1`..`b4` -> Formation slot index, or -1 if not a slot token.
static func _parse_slot_token(token: String) -> int:
	if token.length() != 2 or not (token[0] == "f" or token[0] == "b"):
		return -1
	var col := int(token[1]) - 1
	if not token[1].is_valid_int() or col < 0 or col >= Formation.COLUMNS:
		return -1
	return Formation.slot_index(Formation.FRONT if token[0] == "f" else Formation.BACK, col)


static func _slot_name(index: int) -> String:
	@warning_ignore("integer_division")
	var line := index / Formation.COLUMNS
	return "%s%d" % ["f" if line == Formation.FRONT else "b", index % Formation.COLUMNS + 1]


static func _parse_deck_line(line: String, lineno: int, deck: Array[CardData],
		errors: Array[String]) -> void:
	var count := 1
	var id := line
	var space := line.find(" ")
	if space > 0 and line.substr(0, space).ends_with("x") \
			and line.substr(0, space).trim_suffix("x").is_valid_int():
		count = int(line.substr(0, space).trim_suffix("x"))
		id = line.substr(space + 1).strip_edges()
	var sample := CardLibrary.by_id(id)
	if sample == null:
		errors.append("line %d: unknown card id '%s' (known: %s)" % [lineno, id, ", ".join(CardLibrary.card_ids())])
		return
	for i in count:
		deck.append(CardLibrary.by_id(id))


static func _weapon_by_name(name: String) -> Weapon:
	match name:
		"spear": return Weapon.spear()
		"axe": return Weapon.axe()
		"sword": return Weapon.sword()
		"bow": return Weapon.bow()
	return Weapon.fists()


static func _slug(name: String) -> String:
	var slug := ""
	for ch in name.to_lower():
		slug += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	return slug
