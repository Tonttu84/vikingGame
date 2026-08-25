# Roadmap

## The scope warning (read first)

As designed, this is three games in a trenchcoat: a deckbuilder, a dynasty
sim, and a city builder. The design already contains the scope control —
**the card raid is the game; everything else is menus** — but the build order
below is what actually enforces it. Each milestone ends in something playable.
Do not start the next one early; the graveyard of solo roguelites is full of
projects that built the meta layer before the core loop was fun.

## M0 — Card table skeleton (1–2 weeks)

- Godot project, folder layout, `CardData`/`CardEffect` resources.
- Draw pile → hand → play → discard, with drag-and-drop and hover tweens.
- One enemy with an intent, damage/block effects. Placeholder rects + icons.
- **Done when:** you can win or lose a single fight and it feels okay to click.

## M1 — One raid, vertical slice (3–4 weeks)

- Route of 5–6 nodes: 2 fights, an event, a storm (skill check), a trading
  post, a target village. Push-on-or-go-home choice at each node.
- Loot cards with weight/value, cargo limit, deck clogging, compacting trade,
  one dual-use weapon, jettison in the storm.
- Raid summary: survive → loot becomes a silver number.
- **Done when:** a stranger plays one raid and makes at least one interesting
  greed decision. This milestone proves or kills the game's signature
  mechanic — if dead weight isn't fun here, redesign before building on it.

## M2 — Season loop (2–3 weeks)

- Settlement screen: 4 buildings (Longhouse, Shipyard, Mead Hall, Market)
  as a menu. Silver spends. Crew hiring with officer slots (First Mate,
  Navigator, Quartermaster, Cook).
- Multiple raids per saga, escalating routes. Save/load.
- **Done when:** "one more season" pull exists across 3+ raids.

## M3 — Dynasty (3–4 weeks)

- Captain aging, injuries, death (in bed and mid-raid), heir succession.
- Children: birth events, traits, teachable skills, family members in officer
  roles, side-raids (auto-resolved), the family skill pool. Grilling.
- Three-generation saga structure with era shifts and final scoring.
- **Done when:** losing a captain mid-raid feels like a story beat, not a
  game over.

## M4 — Meta layer (2–3 weeks)

- Conquest map with 5–6 historical locations across the eras (Lindisfarne,
  Dublin, Danelaw, Normandy, Miklagarð, Vinland), each with a distinct
  end-of-route challenge, unlock boon, and content injection.
- Cross-saga persistence, saga scoring, unlock presentation.
- **Done when:** finishing a saga makes you immediately start the next one.

## M5 — Content & polish (ongoing)

- Content pass: fill each location's decks/events to target counts.
- Art pass within the icon+palette system; audio (Kenney/freesound); juice
  (screenshake, card whooshes); balance from playtest telemetry.
- itch.io web build for playtesting.

## Rough content targets for a 1.0-ish

- ~80–100 action/fitting cards, ~40 loot cards, ~25 crew archetypes
- ~15 traits, ~12 skills, ~60 events, 6 historical locations, 8 buildings
