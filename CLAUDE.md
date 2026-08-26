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

Done: the hand-model redesign — a fresh hand of 5 every turn, the Retained
keyword (Reinforce/Swap/Drag Him Back! wait in hand, eat draw room), the
automatic death-save (no reaction prompt; the engine controller contract
lost choose_reaction_save), scrapping removed everywhere (engine, bots, UI
scrap pile). Also: headless engine (momentum, morale/routs, deterministic targeting),
artifact hooks (4 artifacts), playable battle UI, and the boarding redesign —
maneuvers as strategy cards (Grapple & Rush / Dawn Raid / Covering Volley /
Careful Assault, forced-maneuver win rates 56–74% post hand-model), deck-driven reinforcement
(Reinforce/Swap), enemy captain as final reinforcement, repulsed-boarding
retreat, the maneuver picker UI (modal at battle start; smoke test picks
Dawn Raid to prove the choice reaches the engine), and the web build
(`scripts/export_web.sh` → itch.io-ready zip, single-threaded so no special
headers; CI uploads it as the `web-build` artifact; project now runs on the
Compatibility renderer everywhere). `docs/combat-design.md` has the full
rules and a playtest watchlist.

Agreed next slices, in rough priority:
1. Officer system (prowman is currently just a strong named crewman; one
   role is tied to the boarding, event rolls planned).
2. Raid loop (node route between fights, loot into the deck, wounds
   persisting, retreat-vs-push-on).

The user prefers being asked (AskUserQuestion) about real design forks with a
recommendation, rather than having them decided silently; deterministic
mechanics over RNG is a standing principle (playtest constants, never dice).
