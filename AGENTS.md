# Sons of the North

Roguelite viking boarding-action deckbuilder in Godot 4.5. The combat rules
engine (`src/core/`) is pure headless GDScript; `docs/combat-design.md` is the
authoritative design for it. Portfolio project: architecture, tests, and a
readable git history matter more than content volume.

## Shared rules

This project follows the owner's working agreements: https://github.com/Tonttu84/ai-workflow/blob/main/rules/working-agreements.md
(Claude Code loads them in every session through the user-level `CLAUDE.md`; other tools should read that file.)
This file holds only what is specific to this project and wins where it says so.

## Kind

**Solo**: commit to `main` and push once the local gate is green; fresh-agent
review before pushing any non-trivial change.

## Stack

- Godot 4.5, GDScript, `gl_compatibility`; single-threaded web export for itch.io.
- Tests: own runner (`tests/run_tests.gd`), balance sim, UI smoke by synthetic mouse.

## Commands

| Task | Command |
| --- | --- |
| Set up a fresh clone (commit hooks) | `make setup` |
| Get Godot if missing (portable, into `./bin`) | `make godot`, or `GODOT=/path/to/binary` |
| Run the app | `godot`, or `make serve` (web build at localhost:8060) |
| Unit tests (~20s with the import) | `make test` (`scripts/test.sh`) |
| Balance sim | `make sim ARGS="--n=500 --bot=none"`; one battle's log: `scripts/sim.sh --n=1 --verbose` |
| UI smoke (xvfb; a real window on Windows; ~35s) | `make smoke` (`scripts/ui_smoke.sh`) |
| Web build | `make web` |
| Function limits report (warnings only) | `make limits` |
| The local gate before every push | `make gate` |
| Any target in the CI-like Linux container | `make docker-<target>` |

`make gate` = unit tests, both CI sims (`--n=200`, `--bot=none` and `random`),
UI smoke, web export, limits report. No separate lint or type step: Godot
parses every script on import. Run `godot --headless --import` once after
adding files (the scripts do this).

## Tests

- TDD is mandatory for every behaviour change in `src/core/` and `src/sim/`:
  the failing test in `tests/test_*.gd` first, confirmed failing for the
  expected reason; commit test and implementation together.
- Balance-only number changes (tuning constants) need no new tests, but run
  both sims and note the before/after rates in the commit message.
- UI scripts are exempt from test-first, but any logic worth testing lives in
  `src/core`, never in UI scripts; extract it if a UI script grows rules. UI
  changes come with `tests/ui_smoke.gd` checks.
- One suite per system (`test_damage`, `test_cards`, ...); new system, new
  file. Suites in `tests/test_*.gd` extend `TestCase`; fixtures are in
  `tests/helpers.gd`.
- The UI smoke is the rendering guard: nothing visible escapes the 1280x800
  canvas, cards keep their fixed box, the board never moves on a pick-up.

## Domain rules

- **Determinism is a hard invariant.** All randomness flows through the
  engine's (or a bot's own) seeded RNG: never `randi()`, `Array.shuffle()`,
  `Array.pick_random()` or wall-clock time in core code
  (`test_same_seed_same_battle`). Design principle: deterministic mechanics
  over RNG (playtest constants, never dice).
- **The engine is the only judge of legality.** The UI and the bots ask
  (`can_play`, `opening_options`, `crossing_candidates`, `swap_partners`,
  `shove_directions`, ...); they never decide for themselves.
- **One damage model.** Resolution, `forecast()` and `forecast_press()` share
  `block_math()` and `_forecast_pass()`; never add a second.
- Cards are data (`CardData` + effect dictionaries) interpreted by
  `CombatEngine._apply_effect`. Prefer new effect combinations over new code;
  new effect types need tests in `test_cards.gd`.
- Riders never cross the rail; a pinned man is moved by nothing (Formation's
  movement verbs refuse him); the prow pair's law (captain and prowman are
  alternates) is untouched by every other move.
- Port and starboard rider counts stay equal in both decks (a test holds it).
- Balance reads the cost of victory (dead in a win), never win rate alone;
  hand play is the judge, the sims the regression guard. Balance is a design
  conversation: bring before/after sims.
- Design forks go to the owner with a recommendation, never decided silently.

## Godot and UI gotchas

- **Always qualify enum types in annotations**: `var side: Character.Side`,
  never `var side: Side`, even inside the declaring class (bare names break
  cross-script type matching at runtime).
- Card faces, slots, tokens and the sidebar are fixed boxes; text is fitted
  or clipped into them, never allowed to size its box. The canvas had ~5px of
  vertical headroom at 800px (2026-09-06): a new row must buy its own space.
- Fitted body labels use `AUTOWRAP_WORD` with `line_spacing` 0 (`WORD_SMART`
  wraps onto a line the measurement never counted). An autowrapping label
  reports no usable minimum height: measure the text with the font, once the
  theme font is in (`ready`; earlier it reads 7px too tall).
- Replaced buttons are detached at once, not only `queue_free`d: a same-frame
  press would find the stale one.
- `_begin_pick` takes the pick's explanation as a required argument.
- Commit `.uid` files (Godot 4.4+ guidance); never commit `.godot/`.
- `*.sh`, `Makefile`, `Dockerfile` and `.githooks/*` keep LF endings (`.gitattributes`).
- No model identifiers in code or comments. Commit messages end with the
  shared `Co-Authored-By: Claude ...` trailer (D7).

## Layout

`src/core/` rules engine, `src/sim/` bots and sim, `src/ui/` the table (no
rules), `tests/`, `scripts/` (behind the Makefile), `docs/` (design; `history.md`).

## Subagents

`.claude/agents/coder.md` implements settled work (tests and code for an
agreed design, refactors, UI wiring); design forks, tuning and open questions
stay in the main conversation. A stronger model for it is an escalation.

## Where we are

Current state only, rewritten in place when a slice finishes; the slice's
story goes in its commit message and, if worth keeping, atop `docs/history.md`.

- **Built:** M0 (headless core), M1 (playable UI), and M2 through the pick
  prompt on the rail (2026-09-17): real cards, block/patterns/command/pin, the
  press, the opening, classes and names, the scenario menu, an explanation at
  every pick, a fixed draw of five at the end of each turn, and no Reinforce
  card (the opening is the crossing). 1557 unit + 260 smoke checks.
- **Next, in priority:**
  1. **The numeric retune.** Read the brief in `docs/combat-design.md` first.
     Scope: card prices, roster HP, guard values, `SHIELD_AURA_BLOCK`,
     `SUPPRESS_TURNS`, the command's period and amount, the press constants,
     the Trade Places price (now the price of a SECOND trade), momentum at
     the cap, and the card flow (the fixed five plus the income's card) with
     the decks as they are (24 and 37 cards). Questions to weigh before
     moving a price are in `docs/history.md` (the rider gate's refusal rate,
     the Taunt + Concentrated Attack combo, the command's late game, the
     guarding wall's early game).
  2. Officer system, the rest (event rolls, further officer roles).
  3. Raid loop (node route, loot into the deck, persisting wounds, retreat
     or push on).
- **Parked until the owner has playtested** (his call, 2026-08-30: ask
  after he has played): deterministic vs seeded-random tactic rotation;
  content for later captains' commands.
- **Deferred, do not build yet** (owner, 2026-09-04): every character gets a
  frontline and a rearline ability-or-pattern, the rearline one only with
  somebody in front of him; after the retune. A jump card stays out until
  after the retune, and then only player-aimed on a card with a real effect.

## Decisions

`docs/decisions.md` (D1 onward).
