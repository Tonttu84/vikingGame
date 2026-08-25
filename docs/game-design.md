# Game Design — Sons of the North (long-term frame)

> **Status:** this document is the long-term vision. Development is
> combat-first — the authoritative, current design is
> [combat-design.md](combat-design.md) (boarding actions, momentum, permadeath),
> and battles described below are boarding actions in that system. The loops,
> loot economy, and dynasty here are the frame those fights slot into, built
> only if the combat core proves fun (see [roadmap.md](roadmap.md)).

Roguelite deckbuilder. One full playthrough (a **saga**) spans **3 generations**
of a viking family. Between sagas, historical conquests you achieved stay
unlocked and make future sagas start stronger — that's the roguelite meta layer.

## The four nested loops

```
Meta (across sagas)      — unlock historical locations, permanent boons
└─ Saga (3 generations)  — the dynasty: family, settlement, reputation
   └─ Season (one year)  — build city, manage family, outfit ship, pick a route
      └─ Raid (the run)  — the card game: sail, fight, plunder, get home alive
```

### 1. Raid loop (the core card game, ~20–40 min)

- You pick a route on the map: a chain of nodes (coastal villages, monasteries,
  towns, rival ships, storms, trading posts) ending in a target location.
  Farther targets = richer loot, worse weather, deadlier encounters.
- Your **deck = ship + crew + cargo**. Crew members and ship fittings put
  action cards into the deck; everything you loot goes into the same deck as
  cargo.
- Each node is a card encounter: battle, negotiation, storm (skill checks
  played from hand), or opportunity.
- At every node you choose: **push on or turn for home**. Loot is only
  banked when you make it back. Dying far from home is how sagas end early.

### 2. Season loop (settlement)

- Returning converts loot to **silver**. Spend it on buildings, crew wages,
  ship upgrades, family events (feasts, marriages).
- Buildings are a menu, not a city painter (deliberate — see art strategy):
  - **Longhouse** — family capacity, children events
  - **Shipyard** — hull size (deck/cargo limits), ship fitting cards
  - **Mead Hall** — quality of hireable crew
  - **Market** — better loot→silver rates, unlock compacting trades at home
  - **Temple/Hof** — blessings (one-use miracle cards)
  - **Training Ground** — teach skills to family members

### 3. Generation loop (the dynasty)

- Your captain **ages** each season. Stats drift: young = strong, reckless
  event options; old = leadership, more command cards, but injuries linger.
- **Children** are born from settlement events and choices on raids. Sons and
  daughters get random traits plus skills you teach them.
- When the captain dies (old age, or **mid-raid death** — the raid ends, crew
  limps home with a loot penalty), you pick an **heir** and play on. That's a
  generation transition. No living heir = saga over, score what you got.
- Surplus kids are the fun part:
  - **Hire them into officer roles** — family in a role gives a loyalty bonus
    over a generic hireling, and they inherit better for having sailed.
  - **Send them on side-raids** — auto-resolved from their skills; they return
    with silver, a new skill, or not at all. (Yes, one of them can come back
    with the Grilling skill. It stays in the family forever and buffs the
    Cook role. It has been quite useful.)
  - **Marry them off** — alliance bonuses, trade routes.

### 4. Meta loop (across sagas)

- **Historical conquest map**: Lindisfarne, Dublin, the Danelaw, Normandy,
  Iceland, the Faroes, Kyiv/the river routes, Miklagarð (Constantinople),
  Vinland. Each is a hard end-of-route target for a given era.
- First time any saga conquers one, it unlocks **permanently**:
  - a starting boon for future sagas (e.g. Lindisfarne → "Word of the First
    Raid": start with +1 fame and a veteran crew card), and
  - new content in the pool (new events, crew types, loot, routes).
- Meta unlocks widen options rather than raw power where possible, so early
  sagas stay winnable and late sagas stay interesting.

## The card system

Every card has: **name, type, weight, value, text/effects**.

### Card types

| Type | Source | In the deck it... |
| --- | --- | --- |
| **Action** | granted by crew & ship fittings | does things: attacks, maneuvers, repairs, intimidation |
| **Crew** | hired in Mead Hall, family | sits in an officer/rower slot; injects its action cards; can be exhausted/injured |
| **Ship fitting** | Shipyard | passive or activated: sail (draw), reinforced hull (block), figurehead (fear) |
| **Loot** | raiding | mostly **dead weight** — see below |
| **Blessing/Omen** | Temple, events | one-shot powerful effects; omens are curses you must carry |

### Loot and dead weight (the signature mechanic)

Loot goes **into your deck** and most of it does nothing when drawn — it clogs
your hand exactly like a Slay the Spire curse, except you *want* it, because
it's money. The whole raid-length tension is greed vs. deck quality:

- **Bulk loot** (grain, cloth, iron pots): low value per card, heavy. Early
  targets drop mostly bulk.
- **Compact loot** (silver, reliquaries, gems): high value, one card. Rare.
- **Trading posts** on the route let you compact: e.g. 3 bulk cards → 1
  compact card of similar total value. You pay a cut, but your deck breathes
  again. The Market building improves the rate and lets you pre-arrange deals.
- **Usable loot**: a looted sword is a playable attack card *and* sells at
  home. A looted monk **ransoms** high but has an omen effect while aboard.
  Livestock is heavy but feeds the crew (heal). Dual-use loot is the
  interesting drafting decision after every fight.
- **Cargo limit** from hull size caps total carried **weight**. Storm
  encounters can force you to jettison — choose what sinks.
- Weight also drags: total weight above a threshold gives enemy ships
  initiative and worsens storm checks. A fat ship is a slow ship.

### Officer roles

Officer slots on the ship, filled by crew or family. Each shapes the run:

| Role | Effect |
| --- | --- |
| First Mate | +1 hand size; takes over (weaker) if the captain falls |
| Navigator | reveals node types one step ahead; unlocks route shortcuts |
| Quartermaster | +cargo weight limit; 1 free compacting trade per raid |
| Cook | heal/morale each rest node; scales with (ahem) Grilling |
| Goði (priest) | reroll omens; blessing cards cost less |
| Skald | morale; crew XP bonus; writes the saga (score multiplier) |
| Berserker | not really an officer, but try telling him that; big attack cards, friendly-fire risk when morale is low |

Generic hirelings fill any role at base power. Family members bring traits,
loyalty bonuses, and continuity — your brother as First Mate is better than a
stranger, and your son as Navigator is training to be your next captain.

## Tone

Historically flavored, not historically dour. Real places, real-ish timeline
(790s → 1000s across the three generations), but the writing has room for a
legendary Grilling skill. Violence stylized, dark subjects (slavery etc.)
abstracted into "captives/ransom" rather than simulated.

## Scoring / endings

A saga ends after generation 3's captain dies (or the line dies out). The
Skald tallies: silver earned, settlement built, conquests, famous deeds,
children's fates. Score gates some meta unlocks; conquests gate the rest.
