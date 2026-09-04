# Sons of the North — dev guide

Roguelite viking boarding-action deckbuilder in Godot 4.5. The combat rules
engine (`src/core/`) is pure headless GDScript; `docs/combat-design.md` is the
authoritative design for it. Portfolio project: architecture, tests, and a
readable git history matter more than content volume.

## Commands

```sh
scripts/test.sh                      # unit tests (230+ checks, ~2s)
scripts/sim.sh --n=500 --bot=none    # balance sim, no-card baseline
scripts/sim.sh --n=1 --verbose       # one battle's full log
scripts/ui_smoke.sh                  # boot + play the UI under xvfb (~20s)
make serve                           # web build + playtest at localhost:8060
make docker-test                     # any target inside the CI-like Linux container
```

Makefile targets wrap the scripts: `make test / sim ARGS=... / smoke / web /
serve PORT=...`.

If `godot` is missing: `make godot` downloads the portable 4.5 build into
`./bin` (Linux, Windows, macOS), or set `GODOT=/path/to/binary`. On Windows
the `make` targets work from cmd/PowerShell too (they run through Git for
Windows' bash), and `make docker-<target>` runs any target in a Linux
container. Run `godot --headless --import` once after adding new files (the
scripts do this).

## TDD — mandatory for all rules code

Every behavior change in `src/core/` or `src/sim/` follows red-green-refactor:

1. Write the failing test in `tests/test_*.gd` FIRST. Run `scripts/test.sh`
   and confirm it fails for the expected reason.
2. Implement the minimum in `src/core/` to go green.
3. Refactor if needed; suite stays green. Commit test + implementation
   together.

Bug fixes start with a regression test that reproduces the bug. Balance-only
number changes (tuning constants) don't need new tests, but run both sims and
note the before/after rates in the commit message. UI scenes (M1+) are exempt
from strict TDD — but any logic worth testing must live in `src/core`, not in
UI scripts; if a UI script grows rules, extract them into the core and test
them there.

Test suites: one file per system (`test_damage`, `test_morale`,
`test_momentum`, `test_targeting`, `test_cards`, `test_engine_flow`). New
system → new file. Runner discovers `tests/test_*.gd`; suites extend
`TestCase`, fixtures come from `tests/helpers.gd`.

## Conventions and gotchas

- **Determinism is a hard invariant.** All randomness flows through the
  engine's seeded RNG (or a bot's own seeded RNG). Never call `randi()`,
  `Array.shuffle()`, `Array.pick_random()`, or wall-clock time in core code.
  `test_same_seed_same_battle` guards this.
- **Always qualify enum types in annotations**: `var side: Character.Side`,
  never `var side: Side`, even inside the declaring class — bare enum names
  break cross-script type matching at runtime ("should be Side but is
  Character.Side").
- `Character.engaged_with` is a WeakRef-backed property: mutual engagement
  must not create RefCounted cycles. Rosters hold the strong references.
- Cards are data (`CardData` + effect dictionaries) interpreted by
  `CombatEngine._apply_effect`. Prefer new effect combinations over new
  code; new effect types need tests in `test_cards.gd`.
- Commit `.uid` files (Godot 4.4+ guidance); never commit `.godot/`.
- No model identifiers in commits, code, or comments.

## Where we are (keep this section current when finishing a work slice)

Done: **the press** (owner ruled the three open forks 2026-09-05; two
commits). Every column is a duel judged once per round after both sides'
beats, before reinforcements: presence first (a column held by one side
alone is that side's; blood into a column you do not hold wins nothing;
empty-both scores nobody), then BLOOD — only what reached flesh, melee /
heavy / grazes in the victim's column, equal is no result. The bow carries
`Weapon.resolves_columns = false` (the owner's call: a TAG, not a row rule
— a covered spear's reach from the second row counts; an archer's damage
never does, arrows or melee). The win bonus: +1 momentum for having the
press, +1 per column of margin; at margin ≥ 2 the losing line takes −1
morale a man; the enemy's press pays only your morale. `forecast_press()`
shares `_forecast_pass()` with `forecast()` (no second damage model) and
the intent panel shows "Press if nothing changes: yours 2–1 (+2) · last
round: …". Suite `test_press` (25 tests). 993 unit + 143 smoke. Sims
(n=300, random bot), before → after: skirmish 14.0% → 25.3% win / 12.6 →
13.1 turns / 1.15 → 1.46 dead in a win; veteran 26.3% → 50.3% / 15.7 →
16.5 / 1.07 → 1.03; empty decision points 36.8% → 26.8% and 38.6% →
27.0% — the second tempo engine feeds hands that used to sit idle.
RETUNE NOTE: the proposal foresaw momentum riding the cap; the constants
(PRESS_WIN_MOMENTUM 1, PRESS_MARGIN_MOMENTUM 1, PRESS_MORALE 1,
PRESS_MORALE_MARGIN 2) are the retune's first levers if it does.
Earlier: **card readability** (owner's playtest feedback, 2026-09-04): the card
faces now show CardText.summarize — one compact line per effect, rider
directions kept loud — instead of the full sentences, and resting the mouse
on a face pops a full-size preview card (CardView.build_preview, 380 wide,
14px text) over the board with the complete rules text; it replaces the old
OS tooltip on faces, sits on an overlay that ignores the mouse, hides on
drag/hand refresh, and is clamped inside the canvas. Faces grew 178x130 ->
186x148 (body font starts at 13 now), paid for by the formation rows
shrinking to the token's exact 96px and the deck zones' separation 6 -> 5 —
the table still fits the 800px canvas with ~5px to spare, so the next
vertical addition must buy its own space. Two rendering fixes worth
remembering: the body labels wrap AUTOWRAP_WORD with line_spacing 0 so
fit_font_size's measurement is exactly what renders (WORD_SMART balances
onto an extra line the measurement never counted, which clipped the last
line at 7-card widths), and build_preview measures every text block with the
font before boxing it, because an autowrapping label reports no usable
minimum height. Smoke suite grew the hover-preview checks: 937 unit + 142
smoke.
Earlier: **the battleline slice** (owner's playtest feedback, 2026-09-04; four
commits). (1) **Larboard is "port" everywhere now** — effect id RIDER_PORT,
tactic shift_port, all text; the player-facing word wins over the archaic
one. (2) **Riders swap by default**: a rider step into an occupied slot
trades the two men (Press rotates the front man back, Close trades through
your own wall); only the board's edge and a pin refuse a rider — a packed
grid no longer does, which was the rider gate's whole bite on the sim bot.
The sim now permanently prints the retune's headline metric (refused
proposals per affordable card + empty decision points), labeled as a
bot-proposal rate since random targeting counts alongside the gate.
(3) **The front line is relative**: a second-liner with nobody in the front
slot of his own column counts as front — fights, closes (and pins), and
the BOW NEEDS COVER: an uncovered archer is just a fighter (owner ruled
this explicitly). Auras and shove/drive read real positions; being
effectively front carries no boosts. Drive Him Back's edge changed and is
test-recorded: it silences only a man whose column keeps a front man, and
driving back a lone bowman arms nobody. TestHelpers.cover_at is the
fixture for covered archers. (4) **UI**: the gold rail between the decks
is the compass now — "◀ PORT ... STARBOARD ▶" named in so many words
(canvas guard forced the table separation 6 -> 5 to pay for the taller
rail); the man an open pick is ABOUT (trades with him, shoved which way)
wears a WHITE rim while pick options wear gold — selected vs selectable.
937 unit + 94 smoke checks. Sims (n=300, random bot) across the slice:
skirmish 17.7% -> 14.0% win / 12.8 -> 12.6 turns, veteran 38.0% -> 26.3% /
16.6 -> 15.7; refused proposals 41.3%/33.6%, empty decision points
36.8%/38.6% — mostly the bot's blind targeting and thin early momentum
now, not walled-in movement. The drop is relative front freeing swings on
both sides and the deeper enemy roster cashing more of them; the bot
never arranges cover. STILL UNTUNED BY DESIGN — the retune prices all of
it.
DEFERRED ruling recorded (owner, 2026-09-04, do not build yet): **all
characters get a frontline ability-or-pattern AND a rearline
ability-or-pattern, and the rearline one works only with somebody
actually in front of the character.** The relative front line and the
bow's cover requirement are the first installment of exactly this; the
per-role ability split is content design that should follow the retune.
Earlier: **the mechanics overhaul — block, patterns, the captain's word, the
pin** (docs/block-and-patterns.md is the ruling record; combat-design.md
carries the shipped tables). Four chunks, one commit each. (1) **Armor is
guard now**: block = armor at battle start and at each side's turn start,
physical damage chews block before flesh (zero blood is legal), true
damage goes around it; the axe chews 2 block per point AND swings first
(piercing was wrong with multiple attackers); the shieldman's halving and
+1-armor aura are deleted. `block_math()` is one shared static so the
forecast bills exactly what resolution draws. (2) **Patterns on BOTH
sides** (supersedes phase C's enemy-only wind-ups): berserker
attack/attack/HEAVY, bow AIM (public mark, no arrow) then SHOOT (both
arrows + SUPPRESSED: the mark deals a third less, rounded up against him,
for 2 of his turns), shieldman GUARD (armor in block again + 2 to
line-neighbors) then attack; beats advance landed or wasted alike, reset
on fielding; the plain every-turn snipe is GONE. (3) **The captain's
command** replaces the telegraphed tactic every 4th enemy turn from
anywhere, even ashore: every fielded defender gains permanent stacking +1
damage (Character.rage) — the termination guarantee; commands are
scenario data ({name, effect, amount, period}) so later captains differ.
(4) **The closing pin**: the man a closing step walks toward is pinned —
pin_count += 1, pinned += pin_count (1, then 2, then 3...), decay 1/own
turn — and while pinned NOTHING moves him: Formation's movement verbs
refuse him (the one combat fact geometry knows; calls flow through them,
a pinned column skips fresh-men-forward), riders/Trade Places/Taunt/
shoves/pulls are gated off him, and the reaction save cannot reach him —
he dies where he stands. Death/rout/arrival stay unguarded (not moves).
New suites test_block/test_commands/test_pins + test_patterns rewritten;
tokens show BLK, beat telegraphs, PINNED n, suppressed; tooltip and
rules-text copy swept of armor-era rules. 921 unit + 92 smoke checks.
Sims (n=300, random bot) across the slice, skirmish 31.0% -> 18.0% win /
14.1 -> 13.1 turns / 1.09 -> 1.28 dead-in-win; veteran 51.3% -> 34.3% /
17.3 -> 15.8 / 1.14 -> 1.07; stalemates 0%. The fall is the command
punishing a bot that cannot race the escalation plus the raiders losing
halving/piercing — intended pressure, NUMBERS STILL DELIBERATELY
UNTUNED: guard values, aura block 2, SUPPRESS_TURNS 2, period 4 and all
prices belong to the retune, which now tunes the final mechanism.
Still open from the rulings: deterministic vs seeded-random tactic
rotation; second+ captain commands are architecture-ready but have no content yet.
Earlier: **the real card set** (docs/card-design-proposal.md, now marked
IMPLEMENTED with the owner's answers to its §5; the shipped rules are
tabulated in docs/combat-design.md). **Every card carries an effect AND a
movement, and the movement's direction is printed on the card.** 15 tactics
in three families: the rail pair plus the reaction save (their movement is
the crossing), the *theirs* family (Break the Line, the new Drive Him Back,
the new Taunt — the movement is forced on an enemy), and the riders. Five
fixed rider movements — Close, Press, Port, Starboard, Give Ground —
priced in registers: perks on the cheap cards, the coin-flip pair on the mid
ones, Give Ground on the bombs. The player picks WHICH man steps, never which
way, and a card that names an ally binds the rider to him so it asks nothing
at all. Three things make that more than a rename. **The rider gate**: a card
whose movement has no legal destination is refused before payment (Battle
Fury on a front-liner, Rally on a second-liner, Shield Wall with nobody able
to retire) — the movement is part of the price, so it can no longer be
engineered away by packing your grid. **Challenge is folded into Taunt** —
dragging an enemy into the front slot of your man's column *is* a challenge,
so `challenge_active` and the captain branches in `_pick_target`/`_can_melee`
are gone and there is no targeting override left in the engine at all; a duel
is arranged by moving men. **A live bug fixed**: `HEAL` was missing from the
fielded-only list, so Rally could be spent on a man safe on the ship, where
its rider evaporated. Trade Places (was Swap) costs 2 and keeps its id.
Port and starboard counts are equal in both decks, held there by a test.
Sims (n=300, random bot) before → after: skirmish 46.3% → 31.0% win, 14.1 →
14.1 turns, 1.12 → 1.09 dead in a win; veteran 58.7% → 51.3%, 16.7 → 17.3,
0.81 → 1.14. A comparison, not a target — **the gate bites hard on a bot that
never arranges its formation on purpose**: 43–49% of the affordable cards it
holds are refused and ~35% of its decision points have nothing playable at
all. That is the headline for the retune, and it is the reason the sim bot
now asks the engine `can_play` instead of guessing (new suite `test_bots`; a
bot that proposes refused cards burns its turn and quietly distorts every
number).
815 unit + 91 smoke checks. **Prices and roster HP are still deliberately
untuned** — that is the next slice, and it now has real cards to tune.
Jump stays out: not on principle, but a fixed jump is illegal from half the
board and a jump out of contact re-opens the stall the closing rule closed;
if it ships it must be a player-aimed jump on a card that also carries a real
effect, after the retune.
Earlier: **UI robustness — nothing a card says can move the board.** The web
build was cut off: card faces sized themselves to their rules text, so phase
D's rider wording grew the card, the hand row, and pushed End Turn/Retreat
off the 800px canvas (they sat at y=806/852). Sizing a box from its own text
was the bug, so card faces, slots, tokens and the sidebar are all fixed boxes
now with content fitted or clipped into them (a wordier card renders in a
smaller font, full text on the tooltip; faces narrow so a 7-card hand still
fits). The sidebar mattered most: its width set the table's width, so
lighting the board for a drag re-centred every formation row — slot B1 jumped
x=224 → x=296 the instant a card left the hand and a drop landed in the gap
beside its target. `MAX_HAND_SIZE = 7` is now a real engine rule (the turn
refill deals 5, Feint pushes past it; an overflowing draw leaves the card in
the deck). **`scripts/ui_smoke.sh` is now the rendering guard: 90 checks**,
asserting at the picker / turn 1 / a full hand / mid-drag / late battle that
no visible control escapes the canvas (clipping-aware), both turn buttons are
on screen, every card keeps the fixed box, and the board does not move when a
card is picked up. Layout regressions from new card text are now caught by a
test instead of by playing. 747 unit + 90 smoke.
NOT verified: nobody has looked at the rebuilt web build in a browser — the
fixes are proven by measurement and tests only. `make serve` to check.
Earlier: **phase D chunk 3 — the closing rule** (ruling in
docs/lines-redesign.md): a man whose column is empty forfeits his swing and
steps one column toward the nearest column with someone in it (port on
a tie; he stays and swings at air only when his own line walls him in, and
second-liners without reach never step). Diagnosis first: 44% of all melee
swings were hitting an empty column, and sampled stalemates were twenty
straight turns of the jarl swinging at air — a termination defect, not a
balance problem, since no number lets two men in different columns reach
each other. A numeric sweep confirmed it (morale pressure and a shieldman
aura fix moved length not at all; HP ×0.65 only reached 14.6 turns). The
rule alone: skirmish 21.8 → 14.1 turns and stalemates 6.0% → 0%, veteran
20.7 → 16.7 and 5.0% → 0%, with the cost of victory improving too (1.24 →
1.12 dead in a win). Dodging keeps its meaning — the attacker still loses
the turn — but it is a tempo cost now, not a permanent nullification.
740 unit + 56 smoke checks. **Card prices and roster HP are deliberately
NOT tuned**: the user's call is to leave them until the battle mechanism
is settled and the cards are real designs rather than placeholders.
Also settled the two parked engine wrinkles: Swap's precondition and
effect now share `_default_swap_partner()`, so an empty reserve no longer
refuses a legal fielded↔fielded trade, and `TestHelpers.station()` asserts
instead of silently dropping a man onto an occupied slot.
Earlier: **phase D chunks 1–2 — movement riders and the picking UI** (rulings
in docs/lines-redesign.md): most cards carry a mandatory movement rider
resolved after the effect (Spear Volley/Concentrated Attack/War Cry/Feint/
Terrifying Bellow slide a man one column, Shield Wall trades two fielded
men, Rally steps its target a line, Battle Fury advances its target into an
empty front slot; the crossing pair, Break the Line, Challenge and Push
Them Back stay rider-less). The engine lists every legal move in reading
order and the controller picks WHICH via the awaited `choose_rider` hook —
never whether; no hook or an illegal answer gets the first legal move, only
an impossible move is skipped; riders never cross the rail, so the prow
pair's law holds. Suite `test_riders` (50 checks). Chunk 2 gave the UI its
hands: engine legality queries (`can_play`, `crossing_candidates`,
`can_commit`, `swap_partners`, `shove_directions`, `pair_swap_counterpart`
— suite `test_play_queries`, 43 checks; the UI never judges legality) feed
one board-pick mechanism (gold-lit tokens/slots, banner prompt, cancel
only for card-initiated picks) used by rider picks, Reinforce slot drops,
Swap partners, the shove direction and the momentum commit; cards light
their legal targets while dragged; a pick with exactly one legal option
resolves itself. Prow-pair polish shipped: un-committable reserve men dim,
the waiting pair half shows a swap hint that lights gold and plays Swap on
click. 717 unit + 56 smoke checks. Sims (n=300, random bot): skirmish
44.0% win / ~22 turns, veteran 61.0% — identical before/after chunk 2's
refactor; the retune to ~6–10 turn fights is phase D's open remainder.
Engine wrinkle parked for the retune chunk: SWAP with a null
second_target demands a non-pair reserve man, so an empty reserve refuses
a legal fielded↔fielded trade (UI unaffected — it always names the
partner); `TestHelpers.station()` silently drops a man onto an occupied
slot and deserves hardening.
Earlier: **the prow pair (officer system, first slice)** — rulings in
docs/combat-design.md: captain and prowman are alternates (one must hold
the field, never both; `Swap` trades them into each other's slot and
neither moves any other way); the prowman's death or rout forces the
captain across at once for 1 momentum, and an unpayable crossing is panic
= instant DEFEAT; no death-save for the prowman; RosterText token
`prowman`; rules activate only when a roster declares a prowman. Suite
`test_officers` (45 checks). Post-pair sims (n=300, random bot): skirmish
58.7% win / avg 22 turns (the forced crossing fields the captain where
the bot left him ashore), veteran 64.0%; no-card floor now dies with the
captain (64.7% defeat) instead of being repulsed. Numbers are the
mechanic speaking; phase D owns the retune. (The pair's reserve-row
dimming and swap affordance shipped with phase D chunk 2.)
Earlier: **scenario anchors & the cost of victory**: a scenario registry
(`Scenarios.scenario_ids()`/`by_id`; sim `--scenario=skirmish|veteran`) with
a second balance anchor, the veteran raid (10-man blooded crew, 39-card
deck with 5 loot, vs a jarl's 14-man warship) — suite `test_scenarios`;
ruling recorded in docs/combat-design.md: crew losses are permanent at the
campaign level (no in-battle mechanic), so the sim grades wins by body
count (avg dead in a win + wins-by-dead histogram) and tuning reads the
cost of victory, never win rate alone; the outcome screen names the fallen
and the fled, and the debug panel loads either scenario. Post-slice sims
(n=300, random bot): skirmish 41% win / 1.04 avg dead in a win / 40% of
wins bloodless; veteran 63% win / 0.88 / 53% bloodless (veteran slack
stands until phase D retunes).
Earlier: **the lines redesign phase C — enemy dynamics** (docs/lines-redesign.md,
rulings recorded there): the four captain's calls as telegraphed tactics
(fresh men forward, shift port/starboard with slide-what-can edge
pinning, step up) via new Formation verbs (`swap_lines`/`shift`/`step_up`);
enemy-only wind-ups on a visible 3-turn counter (`Character.windup`, ticked
end of enemy turn) — the berserker's heavy cleave (2× blow, graze 4, wasted
on an empty column) and the archer's locked mark (weakest boarder marked at
0, both aimed arrows hit him next turn or nothing if he's dead/routed/
rescued; `state.archer_marks`); forecast previews enemy attacks from called
positions and bills heavies/double shots; UI shows call intents, wind-up
counters, MARKED badge. Suite `test_patterns`. Post-C sims: random bot
40.0% win / 11.6% stalemate, ~27 turns (calls break the wall's grind).
Earlier: **phase B — role kits**:
shieldman (half damage rounded up applied last; +1-armor aura to
line-neighbors; RosterText `shieldman` token), berserker cleave (flat-2
graze to the target's line-neighbors, never armored), the axe denying aura
armor, the captain's leader aura (+1 melee to line-neighbors), Covering
Volley scaling per ship archer with re-aim, forecast covering grazes and
the scaled volley, and distinct default rosters (raider breakers vs a
two-shieldman defender wall with karl rout-fodder). Suite `test_kits`.
Earlier: **the lines redesign phase A** — positional combat on 4×2 slot grids
(Formation), strict-column targeting with spatial misses, spear reach,
archer auto-snipe (flat 2, second line), reserve-never-acts, the enemy
captain as a plain final reinforcement (all exposure rules deleted, along
with engagement tracking and the spear first-strike bonus), kill = +2
momentum, Break the Line repurposed as the shove and Challenge as the
cross-column captains' duel, Reinforce/Swap/commit choose slots, RosterText
slot syntax (`f1`..`b4`), the UI rendering both grids with per-token
incoming-damage forecast badges (engine `forecast()`, physical + morale).
Earlier: the hand-model redesign (fresh hand of 5, Retained keyword,
automatic death-save, scrapping removed), headless engine, artifact hooks
(4 artifacts), playable battle UI, boarding maneuvers as strategy cards,
deck-driven reinforcement, repulsed-boarding retreat, maneuver picker UI,
and the web build (`scripts/export_web.sh`; CI uploads `web-build`).
`docs/combat-design.md` has the full shipped rules; balance is deliberately
rough until C–D retune it.

Agreed next slices, in rough priority:
0. ~~**The press**~~ — RULED and BUILT (see the Done block above and
   docs/press-proposal.md's status header). Its constants join the retune's
   scope below.
1. **The numeric retune** — the slice the owner has been deferring until the
   cards were real, which they now are. Card prices and roster HP against
   both scenario anchors, reading turn count and the cost of victory
   together; the goal is ~6–10 turn fights (the closing rule got skirmish to
   14.1 and the card rework left it there at 14.2). Two things to weigh
   first, both new: **the rider gate refuses 43–49% of the affordable cards
   the random bot holds** and leaves ~35% of its decision points empty — decide
   whether that is the bot being positionally stupid (likely, and a human
   would arrange his line to keep his hand live) or the gate being too sharp,
   before moving any price. The proposal's fallback if playtest says it is
   the gate: gate only the penalty riders (`RIDER_BACKWARD`) and let the
   perks skip. And **Taunt + Concentrated Attack in one hand is a two-card
   assassination** — the combo to check first if the player kills too fast.
   Balance stays a design conversation; bring before/after sims.

   **The 2026-08-29/30 mechanics rulings are BUILT** (block, both-sides
   patterns, the captain's command, the closing pin — see the Done block
   above and docs/block-and-patterns.md; further rulings taken at build
   time: armor = guard value gained each turn, the pin denies ALL
   movement friend or foe, the archer's debuff is the one-third
   suppression). The retune therefore now prices the FINAL mechanism.
   New numbers in its scope beyond prices and HP: guard values (shieldmen
   4/5, everyone else 0-3), SHIELD_AURA_BLOCK 2, SUPPRESS_TURNS 2, the
   command's period 4 and amount 1. New questions it should read from the
   sims: does the command's escalation make the bot's late game hopeless
   (14.0%/26.3% win rates after the battleline slice say slow play and
   bare columns now lose — a human should be faster and keep cover, but
   verify), and does the guarding wall stall the early game?
   Still-open rulings, PARKED until the owner has PLAYTESTED the new
   mechanism (owner's call 2026-08-30: do not decide these for him, ask
   after he has played): (a) deterministic vs seeded-random tactic
   rotation — the command already fires on a fixed beat either way;
   (b) content for later captains' commands. Playtest entry point:
   `make serve` (also still unverified in a real browser since the
   fixed-box UI rework).
2. Officer system, rest of it (first slice — the prow pair — shipped;
   remaining: event rolls, further officer roles).
3. Raid loop (node route between fights, loot into the deck, wounds
   persisting, retreat-vs-push-on).

The user prefers being asked (AskUserQuestion) about real design forks with a
recommendation, rather than having them decided silently; deterministic
mechanics over RNG is a standing principle (playtest constants, never dice).
