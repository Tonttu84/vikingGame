# Combat Design — Boarding Actions

This is the core of the game and the first (possibly only) thing we build.
Everything else in `game-design.md` is the long-term frame around it.

## Fantasy & win condition

Two ships lashed together, your crew boards theirs. **Kill their captain** and
the rest surrender — the fight is a decapitation strike, not a wipe-out.
Characters are central and **permanently lost if they die**. If **your**
captain dies, the run is over. There is always a **retreat** option (cut the
ropes, fall back to your ship): you keep your survivors, lose the prize and
some momentum-related reward. Permadeath needs a coward's exit to be fair.

## The battlefield: a boarding, not a pitched line

Keep v0 flat and readable — no grid, no lanes yet — but the shape of the
fight is a boarding action: a small first wave over the rail into a larger,
surprised crew, then both sides feeding men in.

- **Your side:** a small **first wave** (e.g. 3, chosen before the fight) on
  their deck, the rest of the crew in **reserve** on your own ship. The rail
  is a bottleneck: your field is capped (e.g. 5) — you can never stack their
  deck with your whole crew at once.
- **Their side:** the defenders are home, so they always field **more than
  you** at the start (e.g. 5 on deck against your 3) but not their full
  strength — the watch was surprised. The rest come up from below decks: a
  **reserve pool** (e.g. 5) refilling their line at a fixed rate (2/turn now;
  whether 1 or 2 feels right is a playtest question, never a die roll) up to
  their deck's cap (e.g. 6, always ≥ yours).
- **The enemy captain is the final reinforcement.** He commands from the
  stern while he has men to send; when the hold is empty and his line has
  room, he steps into it himself — attackable, and attacking. Before that he
  can only be reached when his line thins to ≤ 2 or a card forces a window
  (`Break the Line`, a duel). The old "exposed when reserves are spent" rule
  is gone: behind a full line he is safe even with an empty hold.
- Your reinforcements flow **through the deck**: `Reinforce` fields a man
  from your ship, `Swap` rotates a wounded fighter out for a fresh one (also
  how the captain trades places with his prowman — see officers). The
  1-momentum commit action remains as a slow fallback so a bad hand never
  strands the first wave alone; whether it survives playtesting is open.

Lanes (2–3 gangplanks with separate fronts) are a v2 idea if the flat field
feels too mushy. Don't build them speculatively.

## The boarding maneuver

Every battle opens with one free **boarding maneuver** — how you come over
the rail. Mechanically it is a card (same data, same effect resolver) from a
separate tiny deck that is set aside once played: functionally a menu,
code-wise a card, so unlocking new maneuvers later (crew, ship fittings,
conquests) is just adding cards to that deck. The maneuver is also where the
opening **momentum surge** comes from — the crash of the boarding IS your
starting momentum:

Maneuvers are strategies, not stat packets — each changes how the whole
battle plays (one plain-bonus option is allowed):

| Maneuver | Effect |
| --- | --- |
| Grapple & Rush | +5 momentum. The vanilla crash. |
| Dawn Raid | +4 momentum; 3 defenders are caught below decks — they rejoin the BACK of their reserve queue, shaken (−2 morale). Their line is briefly thinner than your wave. |
| Covering Volley | +2 momentum; your archers hold your rail: every player fight phase opens with 2 true damage to the lowest-HP fielded defender, all battle. They hold fire during a duel. |
| Careful Assault | +2 momentum; a shieldwall-like discipline: your side takes −1 damage from every hit, all battle. Drawback: 2 extra defenders have time to form up (their deck — this may crowd past their field cap) and the watch stands composed (+1 morale, blunting rout cascades). |

The choice is deliberate and deterministic (no draw): pick the maneuver that
fits this enemy. Forced-maneuver sims (400 battles each, random bot) sit at
63.8 / 65.2 / 67.5 / 73.2% — close enough that no pick is trivial, and the
bot understates the real differences since it can't exploit synergies (a
human bursts Dawn Raid's briefly-exposed captain on turn 1).

## Officers and the prowman (planned)

A few named characters will carry officer roles with outsized effects; the
one that matters to boarding is the **prowman** (stafnbúi — the prow warrior
who led the charge). You choose who leads the boarding: the captain up front
fights and inspires but can die there — game over; the prowman up front
keeps the captain safe on your ship at the cost of his presence. `Swap`
trades them mid-fight. HP does not fully heal between a raid's battles, so
both men's health is managed across the whole raid. (v0: the prowman is just
a strong named crewman and Swap already works; the formal officer system
with event rolls comes later.)

## Turn structure

```
BOARDING (once)
  0. Choose and resolve a boarding maneuver (free card from its own deck).
PLAYER TURN
  1. Gain +1 momentum. Draw up to hand size (5).
  2. Play any number of cards (pay momentum), and/or
     discard cards for their scrap value (see momentum).
  3. Commit a reserve to the field (costs 1 momentum), optional fallback.
  4. Fight: all characters resolve attacks (see character control).
ENEMY TURN
  5. Enemy tactic resolves (was telegraphed as an intent last turn).
  6. Enemy characters attack.
  7. Reinforce from below decks (the captain last); reveal next tactic.
```

## Momentum (the resource)

Momentum is battle tempo — a snowball resource that rewards aggression. The
boarding maneuver supplies a large opening surge (see above): you start the
fight rich and act from strength, exactly as a boarder should.

- **+1** at the start of your turn.
- **+1** per enemy your side kills (including on the enemy's turn).
- **Carries over** between turns, **cap 10**. No reset — killing sprees bank
  into big turns.
- Losing a character costs **no momentum** — that pain flows through the
  morale system instead (next section). Momentum stays pure tempo: kills and
  turns feed it, nothing drains it.
- **Discard for momentum:** once per turn you may discard cards for their
  printed **scrap value** instead of playing them. Tactic cards scrap for
  0–1. **Loot cards scrap for 1** — so the loot clogging your deck has a use
  in a desperate moment, but it's deliberately mediocre (you're literally
  throwing cargo around to buy time).

Tuning lever: if snowballing makes won fights unloseable, add decay (lose 1
momentum per turn above 5) — but try without it first; "unstoppable once
rolling" is on-fantasy for a boarding action.

## Morale (the second track)

Every character has **Morale** alongside HP. HP is the body; morale is the
will to stay on that deck — and it makes both sides breakable, not just
killable.

- **Morale damage** comes from: an allied death (−2 to every fielded
  character on that side), a rout (−1 to remaining fielded allies — this is
  what lets a line collapse in an avalanche), and fear effects (war cries,
  the dragon figurehead, cards).
- A character at **0 morale routs** and leaves the field. Not dead: enemies
  dive overboard or surrender; your fighters fall back to your ship, alive
  but **Shaken** (reduced morale) for the rest of the raid.
- **Kill vs. break is a real tradeoff:** kills feed your momentum engine,
  routs don't — fear tactics clear the deck faster and without bloodying
  your crew, but starve your card economy.
- Routed enemies count as off the field for **captain exposure** — breaking
  their line is the second road to their captain, alongside killing through
  it.
- **Captains never rout.** Yours fights to the death (that's the game-over
  rule); theirs stands his ground when his crew breaks.
- Berserkers are immune to morale damage. Of course they are.

## Cards = the captain's voice

You are the captain shouting orders; the deck is your tactical vocabulary.
Cards come from your captain's skills, crew abilities, ship fittings, and
(dead weight) loot. Starter vocabulary, ~15 cards for v0:

| Card | Cost | Effect |
| --- | --- | --- |
| Spear Volley | 2 | 2 damage to every fielded enemy |
| Concentrated Attack | 2 | All your characters strike one target this turn |
| Shield Wall | 1 | Your side takes −2 damage per hit until your next turn |
| Rally | 1 | Heal a character 4 |
| Drag Him Back! | 1 | Pull a character to reserve; cancel their death if played in response to a killing blow (the permadeath safety valve — expensive to have, priceless to use) |
| Break the Line | 3 | Enemy captain is exposed until end of turn |
| Challenge | 3 | Your captain and theirs duel 1v1 this round; no one else may interfere |
| Push Them Back | 2 | No enemy reinforcements next turn |
| Battle Fury | 1 | A character attacks twice this turn |
| Feint | 0 | Draw 2 cards |
| Terrifying Bellow | 1 | 2 morale damage to every fielded enemy |
| Reinforce | 1 | Field a man from your ship (default: first in reserve) |
| Swap | 1 | A fielded fighter trades places with one on your ship |
| War Cry | 1 | +1 momentum per enemy killed this turn (stacks the snowball) |

Design rules: damage cards should rarely beat just letting characters fight —
cards **bend** the fight (tempo, protection, targeting, windows), they don't
replace it. Death prevention must exist but be scarce.

## Character control: autobattler with card override (adopted — on probation)

Decision: **autobattler bodies, card-controlled battle** — adopted for v0,
explicitly to be validated in M2 playtests (see the watchlist at the end).

- **Targeting is deterministic and instant.** Every character always has a
  target, assigned by fixed, published priority: keep your current
  engagement → otherwise the front-most open enemy slot → lowest HP as
  tiebreak. Who gets hit is never lucky or unlucky; targeting RNG would
  undermine the no-dice rule below. Predictable AI is a feature — you plan
  around it like a puzzle, and the sim harness can verify it.
- **All player agency flows through cards.** Want focus fire? That's
  `Concentrated Attack`. Want someone safe? `Drag Him Back!`. This makes the
  hand genuinely matter every turn (if you could freely order everyone, half
  the card pool would be redundant), keeps turns fast, and scales to bigger
  fights without micromanagement.
- Escape hatch if playtests feel uncontrollable: add a generic `Order`
  ability — pay 1 momentum to retarget one character. Cheap to add, and its
  price keeps cards primary. Do **not** start with free full control; you
  can't walk that back later.

## Characters

Deliberately small sheet — the mechanics budget is spent elsewhere:

- **HP** (10–20). Wounds persist between battles in a raid; heal at home.
- **Morale** (5–10). Veterans high, fresh hands low; Shaken from a previous
  rout lowers it for the rest of the raid.
- **Strength** — base damage.
- **Speed** — attack resolution order (fast units can kill before being hit).
- **Weapon** (1 slot): damage + one trait. Spear: strikes first when newly
  engaged. Axe: ignores 2 armor. Sword: +1 damage, no gimmick. Bow: hits
  from reserve. Looted weapons are equippable *or* sellable.
- **Armor** (1 slot): flat damage reduction 1–3; heaviest armor −1 speed.
- **One personality trait** (later, for the dynasty layer): coward, fury,
  loyal — hooks for events and AI quirks. Not in v0.

Damage = attacker Strength + weapon − defender armor, minimum 1. No misses,
no crit RNG in v0 — deterministic combat makes permadeath feel fair and the
engine testable; randomness lives in cards drawn and enemy tactics.

## Enemy design

An enemy boarding roster is data: `{captain, field_cap, reserves[], tactics[]}`.

- **Grunts** differentiate by the same weapon/armor system as your crew.
- **Captains** have an aura (e.g. +1 Strength to their side) and a tactic
  deck: `Reinforcement Surge` (+2 extra reserves enter), `Arrow Volley`,
  `Champion's Challenge`, `Shield Wall`. One tactic is **telegraphed** each
  turn as an intent icon — that's what you play cards around.
- Difficulty knobs, in order of preference: better reserves (quality), bigger
  reserves (endurance), field cap (width), captain aura. Avoid stat-inflating
  grunts past readable numbers.

## Artifacts

Run-long (later: campaign-long) passives with one trigger each — e.g.
*Lindisfarne Chalice: +1 momentum at the start of every battle*; *Raven
Banner: first character death each battle costs no momentum*. Mechanically
just a list of hooks on the combat engine; the strategic-map conquest
connection ("conquer once → permanent boost, revisit in later runs → benefit")
plugs in later without engine changes. Build the hook system in v0, ship 3–4
artifacts as debug toggles.

## Tuning baseline (v0 starting numbers)

Hand 5 · momentum cap 10 · first wave 3, your field cap 5, 5 in reserve ·
enemy: 5 fielded, cap 6, reserve 5, reinforce 2/turn, captain last · your
grunts: 12 HP / 6 morale / 3 Str / speed 3; defender grunts steadier at 7
morale (they are home) · enemy captain: 30 HP / 5 Str (never routs) · your
captain: 20 HP / 4 Str · ally death −2 morale to fielded side,
rout −1. A fight should run ~6–10 turns. With reinforcement living in the
deck, the no-card bot is structurally crippled (it never crosses a second
man) — it is a floor metric now, expected to lose heavily, not narrowly; the
tuning target moves to the random card-playing bot sitting near an even
fight (~50–65% wins).

## Playtest watchlist (decided, but on probation)

Rulings made deliberately, to be re-examined with the M1/M2 prototype in hand:

- **Cards-only control** — no manual retargeting. Fallback if fights feel
  like spectating: a generic `Order` (1 momentum: retarget one character).
- **Keep-hand rule** — hand persists between turns, draw back up to 5.
  Current leaning: full draw-play-discard each turn is probably the more fun
  loop. That change is its own slice (it reprices every card and the scrap
  mechanic) — do not bundle it into other work.
- **Morale cascade tuning** — avalanche routs should be a dramatic
  occasional payoff, not the default way every fight ends.
- **Momentum storage** — currently unspent momentum carries over in full.
  Open: decay (lose half at end of turn?) to force spending the boarding
  surge while it's hot. Undecided by design; try carryover first.
- **Enemy reinforcement rate** — fixed 2/turn now; try 1/turn. A constant
  either way, never random.
- **The commit action** — the 1-momentum manual crossing may be redundant
  next to Reinforce/Swap cards; keep it until playtests say the deck alone
  never strands the first wave.

## What "fun" means here (evaluation checklist for the prototype)

- At least once per fight you choose between grinding the line and forcing a
  window to the captain.
- Momentum swings are legible: you can feel a turn where the boarding "tips".
- A character death makes you angry at yourself, not at dice.
- Loot-scrapping happens sometimes and feels like a real (bad) choice.
- A fight fits in ~5 minutes.

If three of five fail after tuning, the combat core gets redesigned before
any other system is built.
