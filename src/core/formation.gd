class_name Formation
extends RefCounted
## One side's fighting formation: 4 columns x 2 lines of slots, any of which
## may be empty (docs/lines-redesign.md). Pure geometry — who stands where and
## the legal ways to re-arrange them — plus the ONE combat fact geometry must
## know (docs/block-and-patterns.md): a PINNED man does not move. Every
## movement verb refuses him here, so no card, call or step can miss the
## rule; placement and removal stay unguarded — arriving, dying and routing
## are not moves. All other combat meaning lives in CombatEngine.
##
## Slots hold the strong references to fielded characters, alongside the
## reserve/dead/routed arrays in BattleState.

const COLUMNS := 4
const FRONT := 0  ## the line at the rail, nearest the enemy
const BACK := 1   ## the second line
const SLOT_COUNT := COLUMNS * 2

## Index = line * COLUMNS + column; null = empty slot.
var slots: Array[Character] = []


func _init() -> void:
	slots.resize(SLOT_COUNT)


static func slot_index(line: int, col: int) -> int:
	return line * COLUMNS + col


static func in_bounds(line: int, col: int) -> bool:
	return (line == FRONT or line == BACK) and col >= 0 and col < COLUMNS


func at(line: int, col: int) -> Character:
	return slots[slot_index(line, col)] if in_bounds(line, col) else null


func has(c: Character) -> bool:
	return _index_of(c) != -1


func line_of(c: Character) -> int:
	var i := _index_of(c)
	@warning_ignore("integer_division")
	return -1 if i == -1 else i / COLUMNS


func column_of(c: Character) -> int:
	var i := _index_of(c)
	return -1 if i == -1 else i % COLUMNS


## Fielded characters in reading order: front left to right, then back.
func fielded() -> Array[Character]:
	var out: Array[Character] = []
	for c in slots:
		if c != null:
			out.append(c)
	return out


func size() -> int:
	return fielded().size()


func is_empty() -> bool:
	return size() == 0


func is_full() -> bool:
	return size() == SLOT_COUNT


## Where a man is fielded when nobody chooses: front gaps left to right, then
## the second line. -1 when every slot is taken.
func first_free_index() -> int:
	for i in SLOT_COUNT:
		if slots[i] == null:
			return i
	return -1


## Every empty slot in reading order — the destinations a crossing may pick.
func free_indices() -> Array[int]:
	var out: Array[int] = []
	for i in SLOT_COUNT:
		if slots[i] == null:
			out.append(i)
	return out


# --- Movement verbs (bool = the move was legal and happened) ------------------

func place(c: Character, line: int, col: int) -> bool:
	if not in_bounds(line, col) or at(line, col) != null or has(c):
		return false
	slots[slot_index(line, col)] = c
	return true


func place_at_index(c: Character, index: int) -> bool:
	if index < 0 or index >= SLOT_COUNT:
		return false
	@warning_ignore("integer_division")
	return place(c, index / COLUMNS, index % COLUMNS)


func remove(c: Character) -> bool:
	var i := _index_of(c)
	if i == -1:
		return false
	slots[i] = null
	return true


## One column left (-1) or right (+1) within the same line.
func slide(c: Character, direction: int) -> bool:
	if absi(direction) != 1:
		return false
	return _move_to(c, line_of(c), column_of(c) + direction)


## Step from the second line into the front of the same column.
func advance(c: Character) -> bool:
	if line_of(c) != BACK:
		return false
	return _move_to(c, FRONT, column_of(c))


## Step from the front back into the second line of the same column.
func retire(c: Character) -> bool:
	if line_of(c) != FRONT:
		return false
	return _move_to(c, BACK, column_of(c))


## Fresh men forward: front and second line trade places, column by column.
## Empty slots trade too — a man without a partner still changes lines. A
## column holding a pinned man does not trade: his partner would have
## nowhere to land but the pinned man's slot.
func swap_lines() -> void:
	for col in COLUMNS:
		var fi := slot_index(FRONT, col)
		var bi := slot_index(BACK, col)
		if _pinned_here(slots[fi]) or _pinned_here(slots[bi]):
			continue
		var tmp := slots[fi]
		slots[fi] = slots[bi]
		slots[bi] = tmp


## The whole formation slides one column (-1 toward column 0, +1 away),
## both lines. Processed from the leading edge: every man whose destination
## is free moves, men pinned at the board edge stay — and pin the men behind
## them. A completely full line does not move. Returns whether anyone moved.
func shift(direction: int) -> bool:
	if absi(direction) != 1:
		return false
	var moved := false
	for line in [FRONT, BACK]:
		var cols := range(COLUMNS - 1, -1, -1) if direction == 1 else range(COLUMNS)
		for col in cols:
			var c := at(line, col)
			if c != null and _move_to(c, line, col + direction):
				moved = true
	return moved


## Step up: back-liners fill the empty front slot of their own column,
## left to right. Returns whether anyone stepped.
func step_up() -> bool:
	var moved := false
	for col in COLUMNS:
		var c := at(BACK, col)
		if c != null and at(FRONT, col) == null and advance(c):
			moved = true
	return moved


func swap_positions(a: Character, b: Character) -> bool:
	var ia := _index_of(a)
	var ib := _index_of(b)
	if ia == -1 or ib == -1 or a == b or _pinned_here(a) or _pinned_here(b):
		return false
	slots[ia] = b
	slots[ib] = a
	return true


# --- Combat queries -----------------------------------------------------------

## Adjacency = same line, neighboring column: the men auras and cleaves touch.
func line_neighbors(c: Character) -> Array[Character]:
	var out: Array[Character] = []
	var line := line_of(c)
	if line == -1:
		return out
	for col in [column_of(c) - 1, column_of(c) + 1]:
		var neighbor := at(line, col)
		if neighbor != null:
			out.append(neighbor)
	return out

## The man an enemy attacking into this column hits: the front-liner shields
## the second line; a whole empty column means the swing finds no one.
func column_melee_target(col: int) -> Character:
	var front := at(FRONT, col)
	return front if front != null else at(BACK, col)


func _index_of(c: Character) -> int:
	return slots.find(c) if c != null else -1


static func _pinned_here(c: Character) -> bool:
	return c != null and c.pinned > 0


func _move_to(c: Character, line: int, col: int) -> bool:
	if _pinned_here(c) or not has(c) or not in_bounds(line, col) or at(line, col) != null:
		return false
	slots[_index_of(c)] = null
	slots[slot_index(line, col)] = c
	return true
