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

Done: **phase D chunks 1–2 — movement riders and the picking UI** (rulings
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
1. Lines redesign phase D, final chunk — the retune (docs/lines-redesign.md):
   card prices from sims, ~6–10 turn fights (riders, drag targets and the
   prow-pair polish shipped in chunks 1–2). Balance is a design
   conversation, not a subagent task; bring before/after sim numbers to
   the user. Also settle the parked SWAP default-partner wrinkle and
   harden `TestHelpers.station()` along the way.
2. Officer system, rest of it (first slice — the prow pair — shipped;
   remaining: event rolls, further officer roles).
3. Raid loop (node route between fights, loot into the deck, wounds
   persisting, retreat-vs-push-on).

The user prefers being asked (AskUserQuestion) about real design forks with a
recommendation, rather than having them decided silently; deterministic
mechanics over RNG is a standing principle (playtest constants, never dice).
