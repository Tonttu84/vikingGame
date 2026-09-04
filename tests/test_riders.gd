extends TestCase
## Movement riders after the card rework (docs/card-design-proposal.md §1):
## every rider carries a FIXED direction. The player never picks which way a
## man goes — only, on a card that does not already name him, WHICH man goes.
## Riders stay mandatory, resolve after the effect, and move men between slots
## only, so they never cross the rail and the prow pair's law is untouched.
##
## The five movements: Port (toward column 0), Starboard (toward column 3),
## Press (second line into the front of his column), Give Ground (front into
## the second line of his column) and Close (one column toward the nearest
## occupied enemy column). SWAPS BY DEFAULT (owner's playtest ruling,
## 2026-09-04): a step into an occupied slot trades the two men — only the
## board's edge and a pin refuse a rider now.

const P := Character.Side.PLAYER
const E := Character.Side.ENEMY
const F := Formation.FRONT
const B := Formation.BACK


## A controller that answers choose_rider with a fixed move, and records
## the list of legal moves the engine offered.
class RiderBot:
	var answer: Dictionary = {}
	var offered: Array = []

	func choose_action(_state: BattleState) -> Dictionary:
		return {"op": "end"}

	func choose_rider(_state: BattleState, _card: CardData,
			moves: Array[Dictionary]) -> Dictionary:
		offered = moves.duplicate()
		return answer


## A bare card carrying nothing but the rider under test, so the movement is
## measured on its own. TargetType.ALLY binds the rider to the target.
func _rider_card(rider: CardData.EffectType,
		target_type := CardData.TargetType.NONE) -> CardData:
	return CardData.new("probe_rider", "Probe", 0, target_type,
			[{"type": rider, "amount": 1}] as Array[Dictionary])


func _play(eng: CombatEngine, card: CardData, target: Character = null) -> void:
	eng.state.hand.append(card)
	eng.state.momentum = maxi(eng.state.momentum, card.cost)
	await eng._play_card(card, target)


func _log_index(eng: CombatEngine, needle: String) -> int:
	for i in eng.state.battle_log.size():
		if eng.state.battle_log[i].contains(needle):
			return i
	return -1


func _moves(eng: CombatEngine, card: CardData, target: Character = null) -> Array[Dictionary]:
	return eng._rider_moves(card.effects[0]["type"], card, target)


# --- Port and starboard: the coin-flip riders ----------------------------

func test_port_rider_slides_toward_column_zero() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, F, 2)
	await _play(eng, _rider_card(CardData.EffectType.RIDER_PORT))
	assert_eq(eng.state.player_formation.at(F, 1), p1, "one column toward the port rail")
	assert_true(_log_index(eng, "sidesteps to port") != -1, "the move is logged by name")


func test_port_rider_has_no_move_at_the_port_rail() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, F, 0)
	assert_eq(_moves(eng, _rider_card(CardData.EffectType.RIDER_PORT)).size(), 0,
			"the board edge is not a direction he may take")


func test_port_rider_into_an_occupied_slot_trades_the_two_men() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var p2 := TestHelpers.grunt(P, "p2")
	var eng := TestHelpers.engine_for({"player_field": [p1, p2],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, F, 0)
	TestHelpers.station(eng.state.player_formation, p2, F, 1)
	await _play(eng, _rider_card(CardData.EffectType.RIDER_PORT,
			CardData.TargetType.ALLY), p2)
	assert_eq(eng.state.player_formation.at(F, 0), p2, "swaps by default: he takes the slot")
	assert_eq(eng.state.player_formation.at(F, 1), p1, "and the man who held it takes his")
	assert_true(_log_index(eng, "trade places") != -1, "the trade is in the saga")


func test_a_rider_swap_with_a_pinned_man_is_not_offered() -> void:
	var mover := TestHelpers.grunt(P, "mover")
	var held := TestHelpers.grunt(P, "held")
	var eng := TestHelpers.engine_for({"player_field": [held, mover],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	held.pinned = 1
	assert_eq(_moves(eng, _rider_card(CardData.EffectType.RIDER_PORT,
			CardData.TargetType.ALLY), mover).size(), 0,
			"a trade moves both men, and nothing moves a pinned one")


func test_starboard_rider_slides_toward_column_three() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, B, 1)
	await _play(eng, _rider_card(CardData.EffectType.RIDER_STARBOARD))
	assert_eq(eng.state.player_formation.at(B, 2), p1, "and along his own line, not across it")


func test_starboard_rider_has_no_move_at_the_starboard_rail() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, F, 3)
	assert_eq(_moves(eng, _rider_card(CardData.EffectType.RIDER_STARBOARD)).size(), 0)


# --- Press: forward into your own column -------------------------------------

func test_forward_rider_presses_a_second_liner_into_his_own_column() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, B, 2)
	await _play(eng, _rider_card(CardData.EffectType.RIDER_FORWARD))
	assert_eq(eng.state.player_formation.at(F, 2), p1, "his own column, never a neighbour's")
	assert_true(_log_index(eng, "steps up into the front line") != -1)


func test_forward_rider_has_no_move_for_a_man_already_at_the_rail() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, F, 1)
	assert_eq(_moves(eng, _rider_card(CardData.EffectType.RIDER_FORWARD)).size(), 0,
			"forward from the front line is off the ship")


func test_forward_rider_trades_with_the_man_holding_his_front_slot() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var p2 := TestHelpers.grunt(P, "p2")
	var eng := TestHelpers.engine_for({"player_field": [p1, p2],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, B, 1)
	TestHelpers.station(eng.state.player_formation, p2, F, 1)
	await _play(eng, _rider_card(CardData.EffectType.RIDER_FORWARD,
			CardData.TargetType.ALLY), p1)
	assert_eq(eng.state.player_formation.at(F, 1), p1, "he presses forward regardless")
	assert_eq(eng.state.player_formation.at(B, 1), p2, "the man in front rotates back")


# --- Give Ground: backward into your own column ------------------------------

func test_backward_rider_retires_a_front_liner() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, F, 3)
	await _play(eng, _rider_card(CardData.EffectType.RIDER_BACKWARD))
	assert_eq(eng.state.player_formation.at(B, 3), p1)
	assert_true(_log_index(eng, "falls back into the second line") != -1)


func test_backward_rider_has_no_move_for_a_second_liner() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, B, 0)
	assert_eq(_moves(eng, _rider_card(CardData.EffectType.RIDER_BACKWARD)).size(), 0,
			"a man already off the rail has no ground left to give")


## Fact 1 of the design: retiring inside your own column is a disarm, not an
## escape. He is still the man that column's attacker hits.
func test_giving_ground_does_not_dodge_the_column() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1", 12, 6, 5, 3)
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, p1, F, 0)
	TestHelpers.station(eng.state.enemy_formation, e1, F, 0)
	await _play(eng, _rider_card(CardData.EffectType.RIDER_BACKWARD))
	assert_eq(eng.state.player_formation.at(B, 0), p1, "he has given ground")
	assert_eq(eng._pick_target(e1), p1, "and is still the only man in that column to hit")


# --- Close: the relational perk rider ----------------------------------------

func test_close_rider_steps_toward_the_nearest_occupied_enemy_column() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, p1, F, 0)
	TestHelpers.station(eng.state.enemy_formation, e1, F, 2)
	await _play(eng, _rider_card(CardData.EffectType.RIDER_CLOSE))
	assert_eq(eng.state.player_formation.at(F, 1), p1, "one column toward the fighting")
	assert_true(_log_index(eng, "presses toward the fighting") != -1)


func test_close_rider_breaks_a_tie_to_port() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1")
	var e2 := TestHelpers.grunt(E, "e2")
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1, e2]})
	TestHelpers.station(eng.state.player_formation, p1, F, 1)
	TestHelpers.station(eng.state.enemy_formation, e1, F, 0)
	TestHelpers.station(eng.state.enemy_formation, e2, F, 2)
	await _play(eng, _rider_card(CardData.EffectType.RIDER_CLOSE))
	assert_eq(eng.state.player_formation.at(F, 0), p1, "the closing rule's own tiebreak")


func test_close_rider_has_no_move_when_he_is_already_in_contact() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, p1, F, 2)
	TestHelpers.station(eng.state.enemy_formation, e1, F, 2)
	assert_eq(_moves(eng, _rider_card(CardData.EffectType.RIDER_CLOSE)).size(), 0,
			"nothing to close on: his column is the fighting")


func test_close_rider_trades_through_his_own_wall() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var p2 := TestHelpers.grunt(P, "p2")
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({"player_field": [p1, p2], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, p1, F, 0)
	TestHelpers.station(eng.state.player_formation, p2, F, 1)
	TestHelpers.station(eng.state.enemy_formation, e1, F, 3)
	await _play(eng, _rider_card(CardData.EffectType.RIDER_CLOSE,
			CardData.TargetType.ALLY), p1)
	assert_eq(eng.state.player_formation.at(F, 1), p1,
			"his fellow no longer walls him in: they trade and he is a column closer")
	assert_eq(eng.state.player_formation.at(F, 0), p2, "")


# --- Who moves: the card names him, or the player picks him ------------------

func test_an_ally_card_binds_the_rider_to_its_own_target() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var p2 := TestHelpers.grunt(P, "p2")
	var bot := RiderBot.new()
	var eng := TestHelpers.engine_for({"player_field": [p1, p2],
			"enemy_field": [TestHelpers.grunt(E, "e1")]}, bot)
	TestHelpers.station(eng.state.player_formation, p2, F, 3)
	TestHelpers.station(eng.state.player_formation, p1, F, 1)
	await _play(eng, _rider_card(CardData.EffectType.RIDER_PORT,
			CardData.TargetType.ALLY), p2)
	assert_eq(bot.offered.size(), 1, "one man, one direction: nothing to ask")
	assert_eq(eng.state.player_formation.at(F, 2), p2, "the man the card named moves")
	assert_eq(eng.state.player_formation.at(F, 1), p1, "and nobody else does")


func test_an_untargeted_card_offers_every_man_who_can_take_the_move() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var p2 := TestHelpers.grunt(P, "p2")
	var p3 := TestHelpers.grunt(P, "p3")
	var bot := RiderBot.new()
	var eng := TestHelpers.engine_for({"player_field": [p1, p2, p3],
			"enemy_field": [TestHelpers.grunt(E, "e1")]}, bot)
	TestHelpers.station(eng.state.player_formation, p2, F, 3)
	TestHelpers.station(eng.state.player_formation, p1, F, 1)
	TestHelpers.station(eng.state.player_formation, p3, B, 0)
	await _play(eng, _rider_card(CardData.EffectType.RIDER_PORT))
	assert_eq(bot.offered.size(), 2, "p3 is at the port rail already")
	assert_eq(bot.offered[0]["character"], p1, "reading order: front line left to right")
	assert_eq(bot.offered[1]["character"], p2)
	assert_eq(bot.offered[0]["direction"], -1, "and every move carries the card's own direction")


func test_the_controller_picks_which_man_never_which_way() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var p2 := TestHelpers.grunt(P, "p2")
	var bot := RiderBot.new()
	var eng := TestHelpers.engine_for({"player_field": [p1, p2],
			"enemy_field": [TestHelpers.grunt(E, "e1")]}, bot)
	TestHelpers.station(eng.state.player_formation, p2, F, 3)
	TestHelpers.station(eng.state.player_formation, p1, F, 1)
	bot.answer = {"character": p2, "direction": -1}
	await _play(eng, _rider_card(CardData.EffectType.RIDER_PORT))
	assert_eq(eng.state.player_formation.at(F, 2), p2, "the man he asked for")
	assert_eq(eng.state.player_formation.at(F, 1), p1, "the other stands fast")


func test_an_answer_that_was_never_offered_gets_the_first_legal_move() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var p2 := TestHelpers.grunt(P, "p2")
	var bot := RiderBot.new()
	var eng := TestHelpers.engine_for({"player_field": [p1, p2],
			"enemy_field": [TestHelpers.grunt(E, "e1")]}, bot)
	TestHelpers.station(eng.state.player_formation, p2, F, 3)
	TestHelpers.station(eng.state.player_formation, p1, F, 1)
	# The other way is not on the table at all, whoever asks for it.
	bot.answer = {"character": p2, "direction": 1}
	await _play(eng, _rider_card(CardData.EffectType.RIDER_PORT))
	assert_eq(eng.state.player_formation.at(F, 0), p1, "moves[0]: reading order, no free pass")
	assert_eq(eng.state.player_formation.at(F, 3), p2)


func test_the_rider_fires_without_a_controller_hook_at_all() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, F, 1)
	await _play(eng, _rider_card(CardData.EffectType.RIDER_STARBOARD))
	assert_eq(eng.state.player_formation.at(F, 2), p1, "mandatory means mandatory")


# --- Effect first, rider last ------------------------------------------------

func test_the_effect_resolves_before_the_rider() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1", 2)
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, p1, F, 1)
	var card := CardData.new("probe_volley", "Probe Volley", 0, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.DAMAGE_ENEMY_FRONT_LINE, "amount": 2},
			{"type": CardData.EffectType.RIDER_PORT, "amount": 1}] as Array[Dictionary])
	await _play(eng, card)
	var slain := _log_index(eng, "is slain")
	var stepped := _log_index(eng, "sidesteps")
	assert_true(slain != -1 and stepped != -1, "both the kill and the move happened")
	assert_true(slain < stepped, "the volley lands, THEN the man steps")


func test_rider_never_fires_when_the_card_ends_the_battle() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var jarl := TestHelpers.captain_of(E, "jarl", 2)
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_captain": jarl})
	eng.state.enemy_formation.place(jarl, F, 0)
	TestHelpers.station(eng.state.player_formation, p1, F, 1)
	var card := CardData.new("probe_volley", "Probe Volley", 0, CardData.TargetType.NONE,
			[{"type": CardData.EffectType.DAMAGE_ENEMY_FRONT_LINE, "amount": 2},
			{"type": CardData.EffectType.RIDER_PORT, "amount": 1}] as Array[Dictionary])
	await _play(eng, card)
	assert_eq(eng.outcome, CombatEngine.Outcome.VICTORY, "the volley kills their captain")
	assert_eq(eng.state.player_formation.at(F, 1), p1, "a won battle carries no rider")


# --- The shipped set: which card carries which direction ---------------------
# docs/card-design-proposal.md §2. Perk riders (Close, Press) ride the cheap
# cards, the coin-flip pair (Port, Starboard) the mid ones, Give Ground
# the strong ones. The direction is on the card face; only the man is a choice.

func test_spear_volley_steps_a_man_to_port() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, F, 2)
	await _play(eng, CardLibrary.spear_volley())
	assert_eq(eng.state.player_formation.at(F, 1), p1)


func test_war_cry_steps_a_man_to_port() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, F, 2)
	await _play(eng, CardLibrary.war_cry())
	assert_true(eng.state.war_cry_active)
	assert_eq(eng.state.player_formation.at(F, 1), p1)


func test_concentrated_attack_steps_a_man_to_starboard() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, p1, F, 2)
	await _play(eng, CardLibrary.concentrated_attack(), e1)
	assert_eq(eng.state.focus_target, e1)
	assert_eq(eng.state.player_formation.at(F, 3), p1)


func test_terrifying_bellow_steps_a_man_to_starboard() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"enemy_field": [TestHelpers.grunt(E, "e1", 12, 2)]})
	TestHelpers.station(eng.state.player_formation, p1, F, 2)
	await _play(eng, CardLibrary.terrifying_bellow())
	assert_eq(eng.state.player_formation.at(F, 3), p1)


func test_feint_closes_a_man_toward_the_fighting() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var e1 := TestHelpers.grunt(E, "e1")
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1],
			"deck": CardLibrary.starter_deck()})
	TestHelpers.station(eng.state.player_formation, p1, F, 0)
	TestHelpers.station(eng.state.enemy_formation, e1, F, 3)
	await _play(eng, CardLibrary.feint())
	assert_eq(eng.state.hand.size(), 2, "drew two, spent itself")
	assert_eq(eng.state.player_formation.at(F, 1), p1, "and walked a man into the fight for free")


## Rally's price is his swings — unless he carries a spear, whose reach makes
## the second line no cage at all. Two shipped rules meeting, no new mechanism.
func test_rally_gives_ground_with_the_man_it_heals() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	p1.hp = 6
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, F, 2)
	await _play(eng, CardLibrary.rally(), p1)
	assert_eq(p1.hp, 10, "healed 4 first")
	assert_eq(eng.state.player_formation.at(B, 2), p1, "then he falls back out of the swinging")


func test_rally_is_refused_on_a_man_who_cannot_give_ground() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	p1.hp = 6
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, B, 2)
	var card := CardLibrary.rally()
	eng.state.hand.append(card)
	eng.state.momentum = 3
	await eng._play_card(card, p1)
	assert_eq(p1.hp, 6, "a second-liner has no ground to give: refused, unhealed")
	assert_eq(eng.state.momentum, 3, "and unpaid for")


func test_shield_wall_makes_a_front_liner_give_ground() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, F, 1)
	await _play(eng, CardLibrary.shield_wall())
	assert_true(eng.state.shield_wall_active, "the wall goes up first")
	assert_eq(eng.state.player_formation.at(B, 1), p1,
			"the wall is standing off, not standing firm: one man takes the round off")


func test_push_them_back_presses_a_second_liner_forward() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"enemy_reserve": [TestHelpers.grunt(E, "r1")]})
	TestHelpers.station(eng.state.player_formation, p1, B, 1)
	await _play(eng, CardLibrary.push_them_back())
	assert_true(eng.state.block_reinforcements, "the rail is held")
	assert_eq(eng.state.player_formation.at(F, 1), p1, "and a man is committed to the front rank")


func test_battle_fury_presses_its_target_forward() -> void:
	var p1 := TestHelpers.grunt(P, "p1", 12, 6, 3, 3, Weapon.sword(), 0)
	var e1 := TestHelpers.grunt(E, "e1", 30)
	var eng := TestHelpers.engine_for({"player_field": [p1], "enemy_field": [e1]})
	TestHelpers.station(eng.state.player_formation, p1, B, 0)
	TestHelpers.station(eng.state.enemy_formation, e1, F, 0)
	await _play(eng, CardLibrary.battle_fury(), p1)
	assert_eq(eng.state.player_formation.at(F, 0), p1, "he pushes into the empty front slot")
	assert_eq(p1.bonus_attacks, 1, "the fury travels with him")
	await eng._fight_phase(P)
	assert_eq(e1.hp, 30 - 5 - 5, "two swings from his new place in the line")


func test_the_rail_cards_carry_no_rider_at_all() -> void:
	for card in [CardLibrary.reinforce(), CardLibrary.swap(), CardLibrary.drag_him_back(),
			CardLibrary.break_the_line()]:
		for effect in card.effects:
			var text := CardText._effect_line(effect)
			assert_false(text.contains("Mandatory"),
					"%s is movement in its own right; it rides on nothing" % card.id)


# --- The rail and the prow pair are untouched --------------------------------

func test_a_rider_never_reaches_over_the_rail() -> void:
	var p1 := TestHelpers.grunt(P, "p1")
	var eng := TestHelpers.engine_for({"player_field": [p1],
			"player_reserve": [TestHelpers.grunt(P, "p2")],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, p1, F, 1)
	await _play(eng, _rider_card(CardData.EffectType.RIDER_PORT))
	assert_eq(eng.state.player_reserve.size(), 1, "the man on the ship is not a candidate mover")
	assert_eq(eng.state.player_formation.size(), 1, "and nobody crossed")


func test_rider_may_move_the_fielded_prowman() -> void:
	var prow := TestHelpers.grunt(P, "prow", 14, 8, 4, 3, Weapon.axe(), 1)
	prow.is_prowman = true
	var captain := TestHelpers.captain_of(P, "aslak")
	var eng := TestHelpers.engine_for({"player_field": [prow],
			"player_reserve": [captain],
			"enemy_field": [TestHelpers.grunt(E, "e1")]})
	TestHelpers.station(eng.state.player_formation, prow, F, 1)
	await _play(eng, _rider_card(CardData.EffectType.RIDER_PORT))
	assert_eq(eng.state.player_formation.at(F, 0), prow, "the prowman sidesteps like anyone")
	assert_true(eng.state.player_reserve.has(captain), "the captain keeps his own rail")
	assert_eq(eng.outcome, CombatEngine.Outcome.NONE, "and the pair's hinge never trips")
