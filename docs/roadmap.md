# Roadmap

## Framing

This is a portfolio / AI-assisted-coding project, not a shipping game. That
changes the priorities: **the combat engine is the product**, and clean
architecture, tests, and a readable repo matter more than content volume.
The plan is combat-first — build the boarding-action engine, tune it until
it's fun, and only then decide whether any outer layer (raid map, settlement,
dynasty) gets built. Every milestone leaves the repo in a demo-able state.

## M0 — Headless combat core (1–2 weeks)

The entire combat ruleset (`docs/combat-design.md`) as pure logic with **no
UI dependency**: turn engine, momentum economy, card resolver, auto-targeting,
reinforcements, exposure rules, artifact hooks. Seeded RNG throughout.

- Runs headless: a script plays a full battle from a JSON/`.tres` setup and
  prints a turn-by-turn log.
- GUT unit tests on every rule (momentum caps, death → −2 morale, `Drag Him
  Back!` timing, captain exposure conditions).
- A dumb bot (plays random affordable cards) lets us **simulate 1,000 battles
  and print win rates** — the balance harness, and frankly the best
  interview-demo artifact in the project.
- **Done when:** the sim harness runs and the no-card baseline is a narrow
  loss at the v0 tuning numbers.

## M1 — Playable combat UI (2–3 weeks)

Godot scene on top of the core: character tokens with HP bars, hand of cards
with drag-to-play, momentum meter, enemy intent icons, reserve rows.
Placeholder art per the icon+palette strategy in `tech-plan.md`.

- Debug panel: restart with seed, edit rosters, toggle artifacts.
- **Done when:** a full boarding fight is playable with mouse only and a
  stranger understands the rules without being told.

## M2 — The fun pass (2–3 weeks, open-ended)

Tune against the "what fun means here" checklist in the combat doc.

- 25–30 cards, 6–8 enemy grunt types, 3 enemy captains with tactic decks,
  3–4 artifacts.
- Settle the control question with real playtests (autobattler + card
  override is the starting position; the 1-momentum `Order` escape hatch is
  the fallback).
- A "skirmish mode" menu: pick a scenario, fight, see results — this makes
  the project a complete, self-contained demo.
- **Decision gate:** if combat isn't fun here, iterate or stop — do not
  build outward around a weak core.

## M3+ — Outer layers (only if M2 passes, in this order)

1. **Raid loop** — a node route between fights, loot entering the deck as
   dead weight, wounds persisting, retreat-vs-push-on decisions. First outer
   layer because it directly feeds the combat deck.
2. **Artifact map hook** — conquer a historical location once → permanent
   campaign boost; revisit on later runs → benefit. (Engine hook exists
   from M0.)
3. **Settlement / dynasty / generations** — per `game-design.md`. Explicitly
   stretch content; the project is complete without it.

## Portfolio notes

- Keep commits small and message-descriptive — the git history is part of
  the exhibit.
- The headless core + sim harness demonstrates architecture and testing; the
  Godot layer demonstrates shipping. Both should be linked prominently from
  the README with screenshots/GIFs once they exist.
