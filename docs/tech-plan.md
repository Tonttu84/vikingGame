# Tech Plan

## Engine: Godot 4 (latest stable 4.x), GDScript

Godot is the right call for this game. To be clear about one thing first: no
engine has built-in "card support" — a card game is just UI nodes plus data
plus tweened animations — but Godot is arguably the *best* mainstream engine at
exactly that:

- **Control nodes** (Godot's UI system) are first-class, not an afterthought.
  A card is a scene: `PanelContainer` frame + `TextureRect` icon + `Label`s.
  Hands, piles, and shop rows are containers. Drag-and-drop is built in
  (`_get_drag_data` / `_can_drop_data` / `_drop_data`).
- **Tweens** give you the card feel (hover-lift, arc into hand, flip, shake)
  in a few lines each.
- **Resources (`.tres`)** make cards data-driven with editor support — design
  a new card by filling in a form, no code.
- **GDScript** iterates fast; **free and MIT-licensed**, no revenue strings.
- Exports to **desktop + web** trivially. A web build is great for playtesting
  (send friends a link) and for itch.io.
- Huge amount of community card-game material (Slay the Spire-like tutorials,
  open-source card frameworks) to crib from when stuck.

Alternatives considered: **Unity** — fine, but heavier, C#, licensing history,
and its UI systems are worse for this than Godot's. **Web stack (TS + Pixi)** —
viable if you were a web dev, but you'd hand-roll everything Godot gives free.
Verdict: Godot unless you have strong existing C#/web skills, and even then.

We roll our own card system rather than adopting a framework — our mechanics
(weight, cargo, dual-use loot) are custom, and the core (draw/hand/play/resolve)
is a week of work, not a project.

## Art strategy — "zero graphical talent" is fine for this genre

This design was shaped to need almost no drawn art. Three rules:

1. **Cards are graphic design, not illustration.** Frame + icon + number +
   text. Sources:
   - **game-icons.net** — ~4,000 consistent-style icons, CC-BY. It has axes,
     longships, runes, barrels, hams (Grilling skill: covered). This is the
     backbone of the whole look.
   - **Kenney.nl** — CC0 UI packs, boardgame packs, audio.
   - **Google Fonts** — one display font with a norse/carved feel for titles,
     one plain readable font for body text. Never more than two.
2. **One palette, everywhere.** Pick a 6–10 color palette (lospec.com) —
   e.g. parchment, sea-dark-blue, blood-red, iron-grey, gold — and allow no
   other colors. Consistency reads as "art direction"; variety reads as
   "programmer art".
3. **Menus over scenes.** The settlement is a building list with icons, not a
   drawn town. The map is flat polygon coastlines + node dots + a dotted
   route line on a parchment texture — that *is* the classic boardgame look,
   not a compromise. No characters are ever drawn: crew/family are a shield
   icon + name + trait tags.

If the game proves fun, commissioning card illustrations later is a
drop-in upgrade (one `illustration` field per card resource).

## Architecture

### Data-driven cards

Custom `Resource` classes, one `.tres` file per card/crew/building/event:

```gdscript
class_name CardData extends Resource
@export var id: StringName
@export var display_name: String
@export var type: Type           # ACTION, CREW, FITTING, LOOT, BLESSING, OMEN
@export var weight: int          # cargo weight (loot mostly)
@export var value: int           # silver at home
@export var icon: Texture2D
@export var effects: Array[CardEffect]   # composable, see below
```

**Effects are data, not per-card scripts.** A small keyword/effect vocabulary
(`Damage`, `Block`, `Draw`, `Heal`, `Jettison`, `Compact`, `Morale`, …), each a
tiny `CardEffect` resource with parameters, interpreted by one resolver. New
cards = new combinations of existing effects. Only truly novel mechanics add
code.

### Game state (autoload singletons)

```
Game        — app flow, scene transitions, settings
MetaState   — cross-saga unlocks (historical conquests). Saved always.
SagaState   — dynasty: family tree, settlement buildings, silver, year, era
RunState    — current raid: deck, hand, piles, cargo weight, route position
```

Save = serialize these to JSON in `user://`. Saga saved between seasons;
raids checkpoint at nodes (roguelite: one save slot, no save-scumming).

### Scene structure

```
Main
├── MainMenu / SagaSetup
├── Settlement      (season loop: buildings, family, outfitting)
├── VoyageMap       (route selection + node-to-node travel)
├── Encounter       (the card table: battle / event / trade variants)
└── RaidSummary     (loot → silver, deaths, saga log entry)
```

### Determinism & testing

- All randomness through one seeded RNG service → reproducible raids, easier
  balancing and bug reports.
- **GUT** (Godot Unit Test) on the pure-logic layer: card resolver, weight
  math, loot conversion, generation transitions. The card resolver is the one
  part of this game that must never be wrong.

### Content pipeline

Cards/events/buildings live in `data/` as `.tres` grouped by era and location.
Historical location = a folder: its event deck, loot table, boss encounter,
and unlock definition. Adding content never touches core code.
