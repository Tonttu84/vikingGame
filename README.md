# Viking Game (working title: *Sons of the North*)

A roguelite card-driven tactics game about viking boarding actions, built in
Godot 4. Your crew storms an enemy ship; you play cards from your hand —
powered by battle **momentum** — to direct the fight; the goal is to **kill
the enemy captain**. Characters are permanently lost if they fall, and if
*your* captain dies, the run ends.

This is also an **AI-assisted development portfolio project**: the point is a
well-architected, well-tested combat engine with a clean repo history, not a
shipped game. The long-term design (raids, loot-as-dead-weight, settlement,
three playable generations, historical conquest meta) exists as the frame the
combat engine is built to fit into.

## Planning documents

| Doc | Contents |
| --- | --- |
| [docs/combat-design.md](docs/combat-design.md) | **The core.** Boarding actions: momentum, cards, permadeath, reinforcements, tuning numbers |
| [docs/roadmap.md](docs/roadmap.md) | Combat-first milestones M0–M2, optional outer layers, portfolio notes |
| [docs/game-design.md](docs/game-design.md) | The long-term frame: raid loop, loot/cargo, dynasty, city, meta progression |
| [docs/tech-plan.md](docs/tech-plan.md) | Engine choice (Godot 4), data-driven architecture, art strategy for non-artists |

## Status

Planning complete for the combat core. Next: **M0**, a headless combat engine
with unit tests and a battle-simulation harness, no UI.
