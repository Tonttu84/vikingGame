# Card Design Proposal — the real card set (phase D, card rework)

**Status: IMPLEMENTED** (everything except the jump, §4/Q6 — see the
answers below). The shipped rules now live in `docs/combat-design.md`,
"Cards = the captain's voice"; this document is kept as the reasoning behind
them. Every cost in it is still a *starting guess*, not a measured value: the
owner's standing ruling is that prices and roster HP are tuned against sims
only once the cards are real, and this document was the "make them real"
step, not the tuning step. Suite was green at 740 checks when this was
written and at 815 unit + 91 smoke when it shipped.

**The owner's answers to §5**, all final:

| | Question | Answer |
| --- | --- | --- |
| Q1 | Fixed direction, or fixed direction *and* a named mover? | **As recommended.** Direction always fixed; the mover is the card's ally target where it has one (so 0 or 1 moves and no prompt), the player's pick otherwise. |
| Q2 | Absolute or relational directions? | **Both, in registers**, exactly as §2 assigns them: perk riders (Close, Press) on the cheap cards, the coin-flip pair on the mid ones, Give Ground on the strong ones. |
| Q3 | Refuse a card whose rider cannot move? | **Yes — gate them all**, in `_effect_preconditions_met`. Battle Fury is refused on a front-liner, Rally on a second-liner or a man whose slot behind is taken, Shield Wall when nobody can retire. That is intended, not collateral. |
| Q4 | Fold Challenge into Taunt? | **Fold it.** The card, `challenge_active`, the branches in `_pick_target` and `_can_melee`, the bot's special case and the UI chip are all deleted. |
| Q5 | Trade Places at cost 2, still Retained? | **Yes to both.** The id stays `swap` so decks and debug tools do not churn; only the face and the price change. |
| Q6 | Jump: in or out? | **Deferred, not cut on principle.** If it ever ships it must be a *player-aimed* jump movement on a card that also carries a real effect — never a pure-movement card — and it lands after the numeric retune. |
| Q7 | Should riders displace? | **No.** The destination must be empty, always. A swap is a strong effect worth its own card. |
| Q8 | Equal port/starboard counts? | **Yes, enforced by a test** over both decks (starter 3/3, veteran 5/5). |
| Q9 | Do the defenders get Taunt and Drive Him Back? | **Not in this slice.** Player-side only, so the coming turn stays readable off the board. |
| Q10 | Rally restricted to fielded allies? | **Yes** — `HEAL` joins the fielded-only list in `_target_valid`. It was a live bug and started with a regression test. |

One thing was added that the proposal did not call for: naming only the enemy
on a Taunt falls back to the first man on deck who could anchor it, the way
Reinforce and Trade Places already default their second pick. The UI always
names both; the default is what keeps the card playable for a bot.

It answers the brief: **every card carries both a movement and an effect;
the movement is a FIXED direction, never "your choice of direction";
swap is an effect in its own right, not a cheap rider.**

---

## 0. What the code actually does (verified, not summarised)

Twelve engine facts this design leans on. Each is load-bearing, and several
are non-obvious enough that they change what a card is worth.

1. **Retiring inside your own column does not dodge anything.**
   `Formation.column_melee_target(col)` returns the front man *if there is
   one, else the back man*. A front-liner who steps back into an empty
   second-line slot is still the man that column's attacker hits — he has
   only given up his own swing (`_can_melee` needs FRONT or a spear).
   "Backward" is therefore a **disarm, never an escape**. Only emptying a
   whole column (both lines) dodges.
2. **A non-spear second-liner cannot melee at all** (`_can_melee`). His
   column is meaningless to him.
3. **An archer ignores columns entirely** — `_is_sniper` + `_weakest_fielded`
   pick the weakest fielded enemy anywhere. Consequence, and this is the
   central indictment of the current rider: **the today's mandatory
   `RIDER_SLIDE` is a fake cost.** With a bow or a swordsman in your second
   line and one empty neighbouring slot, "you must slide someone" costs
   nothing at all — you slide the man for whom position is meaningless. The
   owner's instinct is correct, but the disease is not only free *direction*;
   it is the free *mover*. Fixing direction alone does not cure it (see §3).
4. **`_is_sniper` requires the BACK line.** Force an enemy bow to the front
   and he stops sniping; force one backward and you have **armed** him. Any
   "push an enemy back" card must own this.
5. **A rider with no legal move is skipped in silence** (`_resolve_rider`
   returns early on an empty list). So today a *penalty* rider is
   self-neutralising: pack your grid and the price never lands.
6. **`Formation.slide` / `advance` / `retire` all require an empty
   destination**; only `swap_positions` displaces. Movement never pushes.
7. **`_close_direction` already exists** — the closing rule's "step toward
   the nearest occupied enemy column, port on a tie". It is directly
   reusable as a rider direction, at no new geometry cost.
8. **Cards that cannot do their job are refused before payment**
   (`_effect_preconditions_met`: Reinforce, Swap, Shove, Challenge). This
   is the precedent for gating a card on its rider being legal (§5, Q3).
9. **Rally can currently be played on a man on your ship.** `_target_valid`
   only forces a fielded target for `PULL_TO_RESERVE`, `EXTRA_ATTACK` and
   `SWAP` — `HEAL` is not in that list, so Rally on a reserve man heals for
   1 momentum and its rider evaporates (fact 5). A live hole.
10. **Reaction saves fire inside `_handle_death`**, on either side's turn.
    A rider on `Drag Him Back!` would open a board-pick prompt in the middle
    of the enemy fight phase. **Reaction cards must never carry riders.**
11. **`_play_card` already carries `second_target`** through to
    `_apply_effect`, and the UI already has a two-pick flow for Swap. Taunt
    needs no new controller plumbing, only a new effect.
12. **The closing rule quietly nerfed Break the Line.** A shoved man now
    walks back into contact on his own turn, so the shove costs the enemy
    one swing instead of removing him from the fight. Cost 1 for "one enemy
    loses a swing, and their auras re-pair" is now roughly fair rather than
    strong — it should keep its price and gain nothing, but the design must
    not assume the shove is still a big lever.

---

## 1. The structural rule that answers the brief

> **Every card carries exactly one movement — either on your crew (a fixed
> rider) or on theirs (the effect itself). Never both.**

That partitions the whole set into three legible families and satisfies
"every card has a movement and an effect" without stacking two moves on one
card (which would be unreadable at the table and impossible to price):

| Family | The movement is | Cards |
| --- | --- | --- |
| **Rail** | a crossing (field ↔ reserve) | Reinforce, Trade Places, Drag Him Back! |
| **Theirs** | forced on an enemy | Break the Line, Drive Him Back, Taunt |
| **Riders** | a fixed step by one of your men | everything else |

### The five fixed movements

Direction is always fixed by the card. The player never picks *which way*.

| Keyword | Meaning | Register |
| --- | --- | --- |
| **Close** | one column toward the nearest occupied enemy column (port on a tie) — the closing rule's own direction, `_close_direction` | perk |
| **Press** (forward) | second line → the empty front slot of his column | perk / setup |
| **Port** | one column toward column 0 | coin-flip cost |
| **Starboard** | one column toward column 3 | coin-flip cost |
| **Give Ground** (backward) | front → the empty second-line slot of his column | penalty |

And the pricing spine that falls out of it:

> **Perk riders on the weak cards, coin-flip riders on the mid cards,
> penalty riders on the bombs.**

A perk rider (Close, Press) is a small free upside and it accelerates
convergence, which serves the 6–10 turn goal. A coin-flip rider (Port,
Starboard) is a real, variable cost you manage *in hand* — the decision
moves from "where do I want him" to "which of these three cards fits the
board as it stands". A penalty rider (Give Ground) is the price of a strong
effect and it is genuinely painful, because of fact 1: he keeps taking hits
and stops dealing them.

### Who moves

- Card has an **ally target** → the rider moves *that man*. 0 or 1 legal
  moves; the UI's "a pick with exactly one legal option resolves itself"
  already makes this silent. No click, no ambiguity.
- Card has an **enemy or no target** → the player picks *which man*, the
  direction stays fixed. Up to 8 options instead of today's 16.

---

## 2. The proposed set

15 tactics. Costs are unmeasured proposals (see the header). "Support"
column: what the engine can already do, and the exact enum members needed
where it cannot.

### Rail family (movement = a crossing; no rider)

| Card | Cost | Effect | Movement | The decision it asks | Engine support |
| --- | --- | --- | --- | --- | --- |
| **Reinforce** *(retained)* | 1 | Field a man from your ship into a slot you choose | the crossing | Who crosses, and into which hole in the board | Already: `REINFORCE` |
| **Trade Places** *(retained)* — was `Swap` | **2** | Any two of your men trade slots (fielded↔fielded or fielded↔reserve) | the trade | Pull a broken front-liner out for a fresh one, or re-aim two men at once | Already: `SWAP` (fielded↔fielded fixed by the `_default_swap_partner` slice) |
| **Drag Him Back!** *(retained, reaction)* | 1 | Cancels a killing blow, pulls him to the ship at 1 HP | the pull | Hold it and its momentum, or spend the momentum now | Already: `PULL_TO_RESERVE` + `reaction_save`. **Must stay rider-less** (fact 10) |

The brief says every card carries a movement. These three *are* movement —
their effect is a crossing — and they are the set's only rider-less cards.
Reinforce and Trade Places are also the escape valve for the rider gate
(§5, Q3): with three rider-less cards in the deck a hand can never fully
lock.

**Trade Places at cost 2 is the brief's "swap is a strong effect"
implemented.** It also removes the current oddity where the strongest
positional tool in the game costs the same as Rally.

### Theirs family (movement = forced on the enemy; no rider)

| Card | Cost | Effect | Movement | The decision it asks | Engine support |
| --- | --- | --- | --- | --- | --- |
| **Break the Line** | 1 | Shove an enemy **front-liner** one column sideways, into an empty front slot | theirs, your chosen direction | Shove the shieldman out of the aura he is anchoring, or the berserker off your column before his wind-up fires | Already: `SHOVE` + `shove_directions()`. See fact 12 |
| **Drive Him Back** *(new)* | 2 | An enemy front-liner is driven into the second line of his column, **swapping with the man behind him** | theirs | Disarm their berserker for a turn — but their bowman gets *stronger* back there, and the man you promote may be worse for you than the one you buried | **New `EffectType.DRIVE_BACK`**; reuses `Formation.retire` / `swap_positions`. New query `can_drive_back(target)` for `_effect_preconditions_met` and the UI |
| **Taunt** *(new)* | 2 | Name an enemy and one of your men: the enemy is dragged into the **front slot of your man's column**, swapping with whoever stood there | theirs | Force the duel you want — including dragging the jarl himself onto your prowman | **New `EffectType.TAUNT`**, `target` = enemy, `second_target` = your man. Reuses `Formation.swap_positions`; `_play_card` already carries `second_target` |

**Why the shove keeps a chosen direction while your own riders do not.**
The brief's objection is that a free direction is always good and therefore
never a cost. That objection is about a *rider*, which is a price attached
to an effect. Break the Line's shove *is* the effect — the whole point of
the card is that you re-aim their formation, and taking the aim away leaves
a card that does something arbitrary to you for 1 momentum. The rule I would
write down: **you may aim what you do to them; you may not aim what an order
does to your own crew.** A shout carries a direction; a shove you place.

### Rider family

| Card | Cost | Effect | Fixed rider | The decision it asks | Engine support |
| --- | --- | --- | --- | --- | --- |
| **Feint** | 0 | Draw 2 | **Close** — a man you name presses toward the fighting | Which man you want walked into contact for free | Already `DRAW`; **new `RIDER_CLOSE`** (wraps `_close_direction`) |
| **War Cry** | 1 | +1 momentum per enemy slain this turn | **Port** | Play it for the kills you are about to make, and eat a man dragged the wrong way | Already `WAR_CRY`; **new `RIDER_PORT`** |
| **Terrifying Bellow** | 1 | 2 morale damage to every fielded enemy | **Starboard** | Break the karls for free — but your line drifts starboard while you do it | Already `MORALE_DAMAGE_ALL_ENEMIES`; **new `RIDER_STARBOARD`** |
| **Spear Volley** | 2 | 2 true damage to every enemy front-liner (ignores armour, ignores shields) | **Port** | The shieldman answer, at the price of a step you did not choose | Already `DAMAGE_ENEMY_FRONT_LINE`; `RIDER_PORT` |
| **Concentrated Attack** | 2 | Everyone who can reach the target strikes it this fight phase | **Starboard** | Who dies *now* — and whether the man you must step starboard is the one who was reaching him | Already `FOCUS_FIRE`; `RIDER_STARBOARD` |
| **Battle Fury** | 1 | An ally strikes one extra time this fight phase | **Press** — he advances into the empty front slot of his column | Play it on a second-liner and the fury arrives with him; a front-liner cannot take it at all (see the gate, §5 Q3) | Already `RIDER_ADVANCE`, renamed `RIDER_FORWARD` |
| **Push Them Back** | 2 | No enemy reinforcements next turn | **Press** — a second-liner you name advances | Buy a turn of no fresh defenders and commit a man to the front rank while it lasts | Already `BLOCK_REINFORCEMENTS`; needs `RIDER_FORWARD` generalised to untargeted (pick the man) |
| **Shield Wall** | 1 | Your side takes 2 less from every hit until your next turn; stops arrow volleys | **Give Ground** — a front-liner you name retires | The wall is standing off, not standing firm: you take the round off with one man | Already `SHIELD_WALL`; **new `RIDER_BACKWARD`**. Replaces today's `RIDER_SWAP_FIELDED` |
| **Rally** | 1 | Heal a **fielded** ally 4 | **Give Ground** — he retires into the second line | The breather the design doc keeps parking: heal him and lose his swings — **unless he carries a spear, whose reach makes the price zero** | Already `HEAL`; `RIDER_BACKWARD`; needs `HEAL` added to the fielded-only list in `_target_valid` (fact 9) |

**Rally is the set's best card, and the reason is the spear.** The penalty
rider costs a swordsman his next swings and costs a spearman nothing at all,
because reach works from the second line. That is a decision made of two
shipped rules meeting, with no new mechanism, and it rewards knowing the
kits. The same asymmetry runs through Drive Him Back from the other side:
their spearman shrugs it off, their bowman is upgraded by it.

**What is deliberately NOT in the set:** a pure movement card (loses its
slot to a real effect — the shipped ruling), an "Aim!" archer override, a
Fall Back breather (Rally is now it), and jump (§4).

### Direction balance

Port: War Cry, Spear Volley. Starboard: Terrifying Bellow, Concentrated
Attack. **This has to be maintained at deck level**, in both `starter_deck()`
and `veteran_deck()`, at equal copy counts. On a symmetric board port and
starboard have no intrinsic meaning; the only thing an imbalance does is drag
your whole crew toward one rail over a long fight, which crowds columns
(worse against cleave grazes) and empties the far ones. An unequal deck is a
silent structural bias, not flavour.

---

## 3. The fixed-direction question, honestly

**What is actually being traded.** Today `_rider_moves(RIDER_SLIDE, …)`
enumerates every fielded man × both directions: up to **16** options. The
player picks the best of 16, which by construction is never bad, which is
why the mandatory rider currently reads as a perk rather than a price.

Under the proposal:

- Card with an ally target → **0 or 1** options. The rider is a rules
  consequence, not a choice. No prompt.
- Card without one → **up to 8** options, direction fixed.

**Fixing direction alone does NOT fix the fake-cost problem.** This is the
part worth being sceptical about: with 8 movers still on offer, "slide
someone port" is answered by sliding the archer port, and by fact 3
that costs nothing whatsoever. The cure is the pairing of *fixed direction*
with a *named mover* wherever the card has a target — which is why eight of
the nine rider cards above either name their man (Rally, Battle Fury) or pay
for their freedom with a direction that can hurt.

**What the player loses, concretely.** Under "your choice", the rider is a
free micro-optimisation resolved on the board after the effect lands. Under
"fixed", the optimisation moves **into the hand**: three cards that all want
to be played this turn now differ by which way they will shove your line,
and the one that fits the board wins. That is a strictly better decision —
it is made with imperfect information (before you see the enemy's tactic
resolve), it is made among cards rather than among squares, and it makes a
hand of five feel different every turn. It also makes the deck-builder's job
real: your deck's directional mix becomes a thing you own.

**What it costs in feel.** Two things, and both are real:

1. Some plays will be *refused* or *awkward* for reasons the player did not
   cause. The mitigation is that the rules text names the direction on the
   card face, so it is never a surprise — only a constraint.
2. The board-pick UI gets used less. Rider picks with one legal option
   resolve themselves; the pick mechanism stays alive for Reinforce slots,
   Trade Places partners, the shove direction, Taunt's second pick and the
   momentum commit, so nothing shipped becomes dead code.

**Exactly which shipped cards change:**

| Card | Today | Proposed |
| --- | --- | --- |
| Spear Volley | `RIDER_SLIDE` (your choice) | `RIDER_PORT` |
| Concentrated Attack | `RIDER_SLIDE` | `RIDER_STARBOARD` |
| War Cry | `RIDER_SLIDE` | `RIDER_PORT` |
| Terrifying Bellow | `RIDER_SLIDE` | `RIDER_STARBOARD` |
| Feint | `RIDER_SLIDE` | `RIDER_CLOSE` |
| Rally | `RIDER_STEP` (either line, position-dependent) | `RIDER_BACKWARD`, target restricted to fielded |
| Battle Fury | `RIDER_ADVANCE` | `RIDER_FORWARD` (rename; same rule) |
| Shield Wall | `RIDER_SWAP_FIELDED` | `RIDER_BACKWARD` |
| Push Them Back | no rider | `RIDER_FORWARD` |
| Swap → Trade Places | cost 1 | cost 2 |
| Challenge | `CHALLENGE` | folded into Taunt (§5 Q4) |
| Break the Line, Reinforce, Drag Him Back! | — | unchanged |

**Enum churn** in `CardData.EffectType`: delete `RIDER_SLIDE`, `RIDER_STEP`,
`RIDER_SWAP_FIELDED`; rename `RIDER_ADVANCE` → `RIDER_FORWARD`; add
`RIDER_PORT`, `RIDER_STARBOARD`, `RIDER_BACKWARD`, `RIDER_CLOSE`,
`TAUNT`, `DRIVE_BACK`. Net: 4 out, 6 in.

Note `RIDER_STEP` dies for a reason worth stating: it is *fixed* (a column
has one other line, so at most one legal move) but its **direction depends
on where the man is standing** — the same card retires a front-liner and
advances a back-liner. That is exactly the kind of "reads different every
time" movement the brief is trying to eliminate.

**Files touched by the whole change:** `src/core/card.gd`,
`src/core/card_library.gd`, `src/core/combat_engine.gd`
(`_rider_moves`, `_apply_rider_move`, `_apply_effect`,
`_effect_preconditions_met`, `_target_valid`, plus new legality queries),
`src/ui/card_text.gd` (rules text + `rider_kind`), `src/ui/battle_ui.gd`
(Taunt's second pick only), and the suites `test_riders`, `test_cards`,
`test_play_queries`. **`src/ui/` is being edited by another agent right
now** — the UI half should land as its own commit after the core.

---

## 4. Jump, Taunt and Drive Him Back — the sceptical read

### Jump (two columns): recommend cutting it

Not because it is fiddly — because of geometry and because of the closing
rule.

- **It is illegal from half the board before anything is occupied.** With
  four columns, "jump starboard" exists only from columns 0 and 1; "jump
  port" only from 2 and 3. A fixed-direction jump rider would be dead
  on half your crew at all times.
- **A free-direction jump is, counter-intuitively, less free than a slide.**
  Every column has exactly one legal jump destination (0↔2, 1↔3), so
  "jump, your choice" offers each man *one* option, not two. The
  choice-of-direction argument does not even apply to it.
- **It needs a blocking ruling the geometry layer does not have.** `slide`,
  `advance` and `retire` all check the destination only. A jump would need
  an explicit "does the passed-over slot block?" decision. The consistent
  answer is destination-only, and the consistent answer is also the strong
  one.
- **It is the one movement that can re-open the stall the closing rule just
  closed.** The closing rule works because a man who misses walks one column
  per turn toward contact. A man who jumps two columns out of contact buys
  two turns of dead air for one card, and two such jumps in a fight can add
  four turns to a game that is trying to reach 6–10. Every other movement in
  the set is bounded by one column per card; jump is the exception that
  breaks the convergence guarantee.
- **It is bimodal to price.** Saving a man from a wound-up heavy cleave is
  worth a great deal; being illegal is worth nothing. Nothing sits between.

**If it must exist**, the safe shape is: an *effect* (not a rider), on one
card, at cost 2 or more, and **toward the fighting only** — "Vault the
Benches: one of your men leaps two columns toward the nearest occupied enemy
column". Converging-only jumps cannot manufacture dead air, cannot dodge a
wind-up (they run at it), and reuse `_close_direction` twice. That is the
only jump I would sign off on, and I would still ship it after the retune,
not before.

### Taunt: recommend it, with this exact ruling

**Ruling:** name an enemy `E` and one of your fielded men `U`. `E` is dragged
into the **front slot of `U`'s column** — that is `swap_positions(E, occupant)`
when that slot is taken, and a plain move when it is empty. One
`Formation.swap_positions` call covers both a same-line and a cross-line
arrival, so the geometry layer needs nothing new.

Edge cases, all of them:

- **Board edge:** never arises. The destination column is `U`'s own, so it
  is always in bounds. Taunt is the only movement in the set that cannot be
  edge-blocked.
- **Destination occupied:** they swap. That is the point of the card — you
  are not just pulling a man over, you are ejecting the one who was there
  into the duel `E` just left.
- **`E` is in their second line:** he **comes forward** to the front of
  `U`'s column. The alternative ruling (he stays on his own line) makes the
  card do nothing useful against second-liners, since their own front man
  would still shield him — a card that is dead half the time. Bringing him
  forward also gives the set two genuinely new answers: it drags their
  **archer out of sniper position** (fact 4 — a bow in the front line stops
  sniping, which is the first real counter to the aimed double shot other
  than rescuing the mark), and it hauls a second-line berserker into a column
  you have chosen to be ready for.
- **`E` is already in the front slot of `U`'s column:** no movement is
  possible, so the card is **refused before payment**, exactly as Shove and
  Challenge are today. New query `taunt_targets(second_target)` for the UI.
- **`U` is in your second line:** legal and fine — "his column" is a column,
  not a slot. It does mean you can taunt onto a column where your own front
  slot is empty; the taunted man then simply hits your second-liner. That is
  a bad play, not an illegal one.
- **Closing rule:** Taunt only ever *increases* contact — it moves an enemy
  into a column where you have a man. It can never manufacture dead air. The
  man swapped out may land in an empty column, miss, and close on his own
  turn; self-correcting, one turn.
- **Determinism:** no RNG anywhere. Both participants are named by the
  player; the swap is a single deterministic operation.
- **Deadlock:** impossible. Occupancy counts on both sides are unchanged, no
  slot is created or destroyed, and it cannot be replayed without another
  card.
- **Prow pair:** `U` may be your captain or prowman. Pulling the jarl onto
  your captain is exactly the "force a window to the captain" moment the
  design's own fun-checklist asks for once per fight, and it is a genuinely
  frightening decision because the jarl hits back.
- **Forecast:** none needed. `forecast()` reads live positions, so the new
  bill appears the moment the effect resolves.

**Cost 2**, and it should stay a singleton or near-singleton in the deck: it
is strictly stronger than the 1-cost shove (it aims at a slot rather than a
direction, and it reaches the second line).

**The one thing to watch:** Taunt plus Concentrated Attack in the same hand
is a two-card assassination — drag a man to your best column, then have
everyone who can reach him strike. That is a fine payoff for four momentum
and two cards, but it is the combo to check first if the retune shows the
player killing too fast.

### Drive Him Back: recommend it, weapon-aware

**Ruling:** an enemy **front-liner** is driven into the second line of his
own column, **swapping with the man behind him** if there is one. Displacing
is correct here precisely because this is an *effect*, not a rider — the
brief's "swaps are strong, so they are effects" cuts both ways.

- **Occupied slot behind:** swap. You have just promoted whoever was in
  their second line into the front — which may be their spearman (who was
  already reaching you) or their bowman (who now stops sniping). You choose
  the trade; you do not always like it.
- **Empty slot behind:** he retires. By fact 1 he **still takes the column's
  hits** and simply cannot answer them. A disarm, not a rescue for him.
- **Weapon-dependent, and this is the card's whole skill test:** a spearman
  is untouched (reach), a bowman is **upgraded** (he becomes a sniper), and
  everyone else is silenced for as long as he stays back there. Playing it
  on the wrong man actively helps them.
- **Board edge:** not applicable — the movement is along the line axis,
  which always has exactly two positions.
- **Target already in the second line:** refused before payment.
- **Closing rule:** unaffected; his column is unchanged, so nobody starts
  missing and nobody closes.
- **Anti-combo worth writing on the card:** driving a man back takes him out
  of `DAMAGE_ENEMY_FRONT_LINE`'s area, so Drive Him Back *protects* him from
  your own Spear Volley. Do not sequence them the wrong way.

Explicitly **not** proposed: pushing an enemy off the board or into their
reserve. The reserve is untouchable by design, and a removal effect would
collide with the reinforcement queue.

---

## 5. Open questions for the owner

Each with a recommendation. These are the real forks; the rest of the
document is downstream of them.

**Q1 — Fixed direction only, or fixed direction *and* a named mover?**
Fixing direction alone leaves up to 8 movers, and by fact 3 one of them is
usually free. **Recommendation: fixed direction always; the mover is the
card's ally target when it has one, and the player's pick otherwise.** This
makes Rally and Battle Fury fully determined (no prompt at all) while
leaving the untargeted cards a real board decision.

**Q2 — Absolute directions (port/starboard) or relational ones
(toward/away from the fighting)?** Absolute is a coin flip: on a symmetric
board, half the time port is what you wanted anyway. Relational is
deterministic *and* meaningful, and "toward the fighting" reuses
`_close_direction` for free. **Recommendation: both, in registers** —
relational perk riders (Close, Press) on the cheap cards, absolute coin-flip
riders on the mid cards, Give Ground on the strong ones. A set built only of
absolutes reads as arbitrary; a set built only of relationals has no costs
in it.

**Q3 — Should a card be REFUSED when its rider has no legal move?** Today it
is silently skipped, which means a penalty rider can be engineered away by
packing your grid (fact 5), and Battle Fury on a front-liner is strictly
better than on a back-liner. **Recommendation: yes — gate every rider in
`_effect_preconditions_met`, so a card whose rider cannot move is refused
with nothing paid.** It matches the shipped principle ("a fizzled Reinforce
would feel like theft"), it makes penalty riders honest, and it turns a
crowded board into a real constraint on your hand. Hand-lock risk is
covered by the three rider-less rail cards and by the fact that ending the
turn is always legal. If this feels too harsh in playtest, the fallback is
to gate only the penalty riders (`RIDER_BACKWARD`) and leave the perks
skippable — but that inconsistency should be a retreat, not a starting
point.

**Q4 — Fold Challenge into Taunt?** Taunt on the enemy captain *is* a
challenge, expressed as movement rather than as a targeting override.
Folding it deletes `challenge_active`, the challenge branch in `_pick_target`
and the one in `_can_melee` — a bespoke rule replaced by a general one.
**Recommendation: fold it.** The cost is honest: Challenge currently lets a
back-line captain reach across, which Taunt does not reproduce, and the
deletion touches `test_cards`, `test_column_targeting` and the forecast. The
gain is one fewer special case in the targeting core, which is worth more to
this project than one more card.

**Q5 — Trade Places (Swap) at cost 2, and does it stay Retained?**
**Recommendation: cost 2, still Retained.** Its job is the emergency
rotation of a broken front-liner, which needs to be available on the turn it
is needed, not the turn it is drawn. Raising the price is the brief's "swap
is a strong effect" made literal. The alternative — cost 2 *and* not
retained — would make it a card you draw rather than a card you hold, and
would gut the prow pair's swap, which depends on holding it.

**Q6 — Jump: in or out?** **Recommendation: out for v1**, per §4. If the
owner wants it, the converging-only "Vault the Benches" is the version I
would build, after the retune rather than before.

**Q7 — Should riders displace (swap on collision) instead of requiring an
empty slot?** It would make riders always legal and kill the Q3 problem at
the root. **Recommendation: no.** Every rider would then be a swap, which
contradicts the brief's core ruling that a swap is a strong effect worth a
card. Keep riders non-displacing and pay for it with the Q3 gate.

**Q8 — Deck composition: equal port and starboard counts?**
**Recommendation: yes, enforced by a test** in `test_cards` over
`starter_deck()` and `veteran_deck()`. Otherwise the deck has a hidden drift
toward one rail that nobody will diagnose from win rates.

**Q9 — Do the defenders get Taunt and Drive Him Back too?** Symmetry is
tempting and the enemy already has the four captain's calls as its movement
layer. **Recommendation: not in this slice.** Enemy movement is telegraphed
a turn ahead by design; a taunt that fires on their turn without a telegraph
would break the rule that the player can always read the coming turn off the
board. If it is ever added, it must arrive as a fifth captain's call with a
one-turn intent.

**Q10 — Rally restricted to fielded allies?** **Recommendation: yes** — add
`HEAL` to the fielded-only list in `_target_valid` (fact 9). Otherwise the
card's rider silently disappears whenever it is played on the ship, which is
the exact loophole this redesign exists to close. It is also a bug fix
independent of the card set, and by the project's TDD rule it starts with a
regression test.

---

## 6. Suggested implementation order (TDD, one commit per chunk)

Small enough to keep the suite green at every step, and it keeps out of
`src/ui/` until the core settles.

1. **The rider vocabulary.** New enum members, `_rider_moves` /
   `_apply_rider_move` rewritten around (direction, mover), the ally-target
   binding rule. Rewrite `test_riders` first — it is 50 checks that mostly
   assert the *old* free-direction enumeration, so expect it to shrink and
   sharpen. No card changes yet.
2. **The rider gate (Q3)** in `_effect_preconditions_met`, plus the
   `HEAL`-fielded fix (Q10). `test_play_queries` grows the new refusals.
3. **Re-rider the existing cards** per §3's table, and re-cost Trade Places.
   Run both sims and record before/after in the commit message — a
   comparison, not a target.
4. **`TAUNT`** with its legality query, plus the Challenge fold if Q4 says
   yes. New checks in `test_cards`.
5. **`DRIVE_BACK`** with its legality query.
6. **UI**: `card_text.gd` rules text for the new keywords, `rider_kind`
   names, and Taunt's second pick. After the other agent's work has landed.
7. **Only then** the numeric retune the owner has been deferring: card
   prices and roster HP against both scenario anchors, reading the cost of
   victory and turn count together.
