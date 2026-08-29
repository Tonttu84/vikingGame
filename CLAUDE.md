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
```

Makefile targets wrap the scripts: `make test / sim ARGS=... / smoke / web /
serve PORT=...`.

If `godot` is missing (fresh container): download 4.5-stable linux from
GitHub releases, unzip to /usr/local/bin/godot. Run `godot --headless
--import` once after adding new files (the scripts do this).

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

Done: **UI robustness — nothing a card says can move the board.** The web
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
steps one column toward the nearest column with someone in it (larboard on
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
(fresh men forward, shift larboard/starboard with slide-what-can edge
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
1. Card design — the real cards, replacing the placeholder set. There is now
   a written proposal at **docs/card-design-proposal.md** against the owner's
   brief: every card carries BOTH an effect and a movement, and the movement
   is FIXED (move left/right/forward/back), never player-chosen, because a
   free direction is always good and so never a cost. Read its two findings
   first: fixing the direction alone does NOT fix the cost (the mandatory
   slide is answered by moving the archer, for whom position means nothing —
   the free *mover* is half the problem), and it recommends cutting
   two-column jumps (a fixed jump is illegal from half a 4-column board, and
   jumping out of contact can re-open the stall the closing rule just
   closed). It also rules Taunt in full and flags a REAL BUG: Rally can
   currently be played on a man in reserve (HEAL is missing from the
   fielded-only list in `_target_valid`) — fix starts with a regression test.
   Only once the cards are real does the numeric retune mean anything: card
   prices and roster HP are the last mile to ~6–10 turn fights (the closing
   rule got skirmish to 14.1), and the user has explicitly deferred them
   until then. Balance stays a design conversation; bring before/after sims.

   **Deferred design decisions the owner has already made** (do not
   re-litigate, do not build yet; rulings refined 2026-08-29):
   - The enemy captain gets an order granting **+1 attack damage to every
     enemy on the board** — the eventual guarantee that combats cannot lock
     up. RULED: it fires by **replacing the tactic rotation every Nth
     turn** (so it escalates even while the captain waits ashore); whether
     the rotation is deterministic or random is still open.
   - Later captains get **different commands**, not just the one.
   - **Every unit gets a pattern**: e.g. block then attack; the berserker
     basic/basic/heavy; archers aim, then hit + debuff. (The enemy wind-up
     system in phase C is the seed of this.) RULED: patterns apply to
     **BOTH sides** — your own crew follows its beats too; this supersedes
     phase C's enemy-only wind-up ruling.
   - **Armour becomes Slay-the-Spire block**: shields that prevent damage
     for that turn only, replacing armour that permanently reduces it.
     RULED: the **shieldman loses his half-damage rule** — he becomes the
     block kit (block-then-attack with a high guard value; his aura becomes
     shared block on his blocking beats, and true-damage volleys still go
     around block as his counter-play). The **axe does NOT pierce block**
     (piercing is wrong with multiple attackers: the ignored block would
     still stop everyone else) — instead **axes deal extra damage TO
     block**, and **axes strike first** in the fight order so the
     block-chewing lands while block is up. The fate of the `armor N`
     sheet stat (repurpose as guard value vs delete) is still open.
   - **Closing punishes the dodger**: when a man steps because his column
     is empty (the shipped closing rule), the character he is closing
     toward is **immobilized with a growing number** — a stacking
     movement-denial so repeated dodging is a delaying tactic, never a
     permanent escape. Details open: exactly which moves immobilize
     blocks, and how the stacks decay.
2. Officer system, rest of it (first slice — the prow pair — shipped;
   remaining: event rolls, further officer roles).
3. Raid loop (node route between fights, loot into the deck, wounds
   persisting, retreat-vs-push-on).

The user prefers being asked (AskUserQuestion) about real design forks with a
recommendation, rather than having them decided silently; deterministic
mechanics over RNG is a standing principle (playtest constants, never dice).
