# Combat Design — Boarding Actions

This is the core of the game and the first (possibly only) thing we build.
Everything else in `game-design.md` is the long-term frame around it.

> **Redesign in progress:** positional combat is specified in
> [lines-redesign.md](lines-redesign.md) and lands in phases. **Phases A
> (the geometry engine) and B (role kits) have shipped** and this document
> describes them; enemy shifts and wind-ups (C) and the card rework (D)
> are still to come.

## Fantasy & win condition

Two ships lashed together, your crew boards theirs. **Kill their captain** and
the rest surrender — the fight is a decapitation strike, not a wipe-out.
Characters are central and **permanently lost if they die**. If **your**
captain dies, the run is over. There is always a **retreat** option (cut the
ropes, fall back to your ship): you keep your survivors, lose the prize and
some momentum-related reward. Permadeath needs a coward's exit to be fair.

## The battlefield: the lines

Each side fields **4 columns × 2 lines** of slots, plus an untouchable
reserve (their hold, your ship). Any slot may be empty; the slots themselves
are the fielded cap. The rail bottleneck is the crossing **rate**
(Reinforce/Swap/commit per turn), not a standing limit.

- **Placement is targeting.** A fighter attacks the nearest occupied enemy
  slot in his own column — their front first, then their second line. A
  whole empty enemy column means his swing **misses**: he hits air. Misses
  are spatial and deterministic, never dice.
- **Placement is also defense.** Vacate a column and their berserker there
  hits nothing — at the price of your own attack lane in that column.
- **Front-liners** fight their column. **Spears** also fight it from the
  second line (reach). **Archers** in the second line auto-snipe the
  lowest-HP fielded enemy *anywhere* for a flat 2 (spawn-order tiebreak,
  armor ignored) — the one attack placement cannot dodge; the weak number
  is deliberate, archers finish and harass, they do not carry. Any other
  second-liner simply holds his place. The **reserve never acts and can
  never be hit.**
- **Your first wave** (e.g. 3 men, placed before the fight) boards a
  larger, surprised watch (e.g. 5); the rest of both crews feed in over
  the fight. Their reinforcements enter at a fixed rate (2/turn, never a
  die roll) and fill **front gaps left to right**, then the second line.
- **The enemy captain is the final reinforcement — and has no special
  rules.** He commands from the stern, unreachable like all reserves,
  while he has men to send; when the hold is empty and his line has room
  he steps in himself, and then he stands in the formation like anyone:
  reach him through his column, snipe him, shove his line apart. All the
  old exposure rules are gone.
- Your reinforcements flow **through the deck**: `Reinforce` fields a man
  from your ship **into a slot you choose**, `Swap` trades any two of your
  men (fielded↔fielded or fielded↔reserve — also how the captain trades
  places with his prowman). The 1-momentum commit action remains as a slow
  fallback so a bad hand never strands the first wave alone.

## Role kits (shipped, phase B)

The sheet stays small; a kit is one or two positional hooks riding the
existing idioms — boolean flags and weapon kinds, no class enum. Kits are
what make "kill him FIRST" a puzzle; the same kits stand on both sides.

| Kit | Hooks (v0 numbers) |
| --- | --- |
| Shieldman (`is_shieldman`) | Takes **half physical damage, rounded up**, applied last — after armor and side-wide softening — to melee, snipes and cleave grazes, never to card/tactic true damage (volleys are his counter-play). **Aura: +1 armor to line-neighbors** (same line, adjacent column), never himself. Low Strength: he anchors, he does not carry. |
| Berserker (`is_berserker`) | Morale-immune (as before). **Cleave:** his attack also grazes the target's line-neighbors for a flat 2 — never armored, but softened and shield-halved; graze kills pay the normal bounty. The arc is set before the blow lands. Their berserker is your #1 kill bounty. |
| Spearman (spear) | Reach: fights his column from the second line. |
| Archer (bow) | Second line only in practice: auto-snipes the weakest fielded enemy anywhere for a flat 2. Halved by a shieldman's shield like any physical hit. |
| Breaker (axe) | Ignores 2 worn armor **and denies the target all aura armor** — the shieldman counter. |
| Karl | No kit. Cheap, low morale (4): rout fodder — do not waste swings. |
| Captain (`is_captain`) | **Leader aura: line-neighbors strike +1 in melee** (never himself, never snipes). Big stats, no other rules. |

The default rosters give the sides distinct silhouettes: your raiders are
breakers (axes, a spearman, one shieldman, an archer feeding the rail),
their watch is a wall (two shieldmen up front, a bowman behind, karls and
the berserker in the hold).

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
| Grapple & Rush | +6 momentum. The vanilla crash. |
| Dawn Raid | +4 momentum; 3 defenders are caught below decks — they rejoin the BACK of their reserve queue, shaken (−2 morale). Their line is briefly thinner than your wave. |
| Covering Volley | +2 momentum; your archers hold your rail: every player fight phase opens with one 2-true-damage arrow **per archer still in your reserve**, re-aiming at the lowest-HP fielded defender between arrows, all battle. Field your archer and the rail loses her arrow; no ship archers, silent rail. |
| Careful Assault | +2 momentum; a shieldwall-like discipline: your side takes −1 damage from every hit, all battle. Drawback: 2 extra defenders have time to form up and the watch stands composed (+1 morale, blunting rout cascades). |

The choice is deliberate and deterministic (no draw): pick the maneuver that
fits this enemy. Forced-maneuver sims (300 battles each, random bot, post
hand-model redesign) sit at 56.0 / 61.7 / 74.3 / 71.7% — no pick is trivial.
The bot overrates the passive maneuvers (volley and armor generate value
with no decisions) and underrates raw momentum, so the human spread is
tighter than these numbers suggest (a human bursts Dawn Raid's
briefly-exposed captain on turn 1).

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
  1. Gain +1 momentum. Discard the hand (Retained cards stay), draw to 5.
  2. Play any number of cards (pay momentum).
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
- **+2** per enemy your side kills (including on the enemy's turn) — with
  targeting positional, choosing WHO dies is the player's craft, and
  sniping the right man is the tempo engine.
- **Carries over** between turns, **cap 10**. No reset — killing sprees bank
  into big turns.
- Losing a character costs **no momentum** — that pain flows through the
  morale system instead (next section). Momentum stays pure tempo: kills and
  turns feed it, nothing drains it.

The hand cycles: at the start of every turn the old hand is discarded and a
fresh 5 drawn — except **Retained** cards (Reinforce, Swap, Drag Him Back!),
which wait in hand for their moment and occupy draw room while they do.
Drag Him Back! **fires automatically** when a killing blow lands on a
non-captain crew member and its cost is affordable — no prompt; holding it
(and the momentum for it) IS the decision. Scrapping (discard-for-momentum)
was removed with the keep-hand rule it existed to relieve: loot now costs
you draws, nothing else, until the raid layer prices it in silver.

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
  your crew, but starve your card economy. Ideally you snipe the men worth
  a bounty and break the cheap ones without wasting swings on them.
- A rout empties a slot like a death does — breaking their line opens
  columns (and eventually their captain's hold) as surely as killing
  through it.
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
| Concentrated Attack | 2 | Everyone who can REACH the target (his column's attackers + your archers) strikes it this turn |
| Shield Wall | 1 | Your side takes −2 damage per hit until your next turn |
| Rally | 1 | Heal a character 4 |
| Drag Him Back! | 1 | Retained. Fires automatically when a killing blow lands on a crew member: cancels it, pulls them to the ship at 1 HP (the permadeath safety valve — holding it and its momentum IS the play) |
| Break the Line | 1 | Shove an enemy front-liner one column sideways — you re-aim THEIR formation (out of his duel, into a worse one) |
| Challenge | 2 | Only while both captains are fielded: they attack each other this round regardless of columns; everyone else fights on |
| Push Them Back | 2 | No enemy reinforcements next turn |
| Battle Fury | 1 | A character attacks twice this turn |
| Feint | 0 | Draw 2 cards |
| Terrifying Bellow | 1 | 2 morale damage to every fielded enemy |
| Reinforce | 1 | Retained. Field a man from your ship into a slot you choose |
| Swap | 1 | Retained. Any two of your men trade slots (fielded↔fielded or fielded↔reserve) |
| War Cry | 1 | +1 momentum per enemy killed this turn (stacks the snowball) |

Movement riders on the wider card pool (Spear Volley sliding a man, Rally
with a step, Feint as the step) are Phase D of the lines redesign.

Design rules: damage cards should rarely beat just letting characters fight —
cards **bend** the fight (tempo, protection, targeting, windows), they don't
replace it. Death prevention must exist but be scarce.

## Character control: autobattler with card override (adopted — on probation)

Decision: **autobattler bodies, card-controlled battle** — adopted for v0,
explicitly to be validated in M2 playtests (see the watchlist at the end).

- **Targeting is deterministic and spatial.** Who hits whom is decided by
  where people stand: a fighter attacks the nearest occupied enemy slot in
  his own column, archers snipe the weakest man anywhere, a challenged
  captain seeks the other captain. Who gets hit is never lucky or unlucky;
  targeting RNG would undermine the no-dice rule below. Predictable AI is
  a feature — you plan around it like a puzzle, and the sim can verify it.
- **The bill is on the board.** The UI forecasts, per fighter, the physical
  and morale damage he stands to take next fight phases (column duels,
  reach, snipes, the telegraphed tactic, the morale wave of predicted
  deaths) — you read threat off the tokens instead of adding it up.
- **All player agency flows through cards.** Want focus fire? That's
  `Concentrated Attack`. Want someone safe? `Drag Him Back!`. Want their
  line re-aimed? `Break the Line`. Cards move men; position does the rest.
  This makes the hand genuinely matter every turn, keeps turns fast, and
  scales to bigger fights without micromanagement.
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
- **Weapon** (1 slot): damage + one trait. Spear: reach — fights his column
  from the second line. Axe: ignores 2 armor. Sword: +2 damage, no gimmick.
  Bow: second line only in practice — snipes the weakest fielded enemy
  anywhere for a flat 2. Looted weapons are equippable *or* sellable.
- **Armor** (1 slot): flat damage reduction 1–3; heaviest armor −1 speed.
- **One personality trait** (later, for the dynasty layer): coward, fury,
  loyal — hooks for events and AI quirks. Not in v0.

Damage = attacker Strength + weapon + leader aura − defender armor (worn +
shieldman aura; the axe pierces 2 and denies the aura), minimum 1; then
side-wide softening (shield wall, careful advance), minimum 1; then a
shieldman defender halves what is left, rounded up. No misses, no crit RNG
in v0 — deterministic combat makes permadeath feel fair and the engine
testable; randomness lives in cards drawn and enemy tactics.

## Enemy design

An enemy boarding roster is data: `{captain, field_cap, reserves[], tactics[]}`.

- **Grunts** differentiate by the same weapon/armor/kit system as your crew.
- **Captains** have the leader aura (line-neighbors strike +1, shipped in
  phase B) and a tactic deck: `Reinforcement Surge` (+2 extra reserves
  enter), `Arrow Volley`, `Champion's Challenge`, `Shield Wall`. One tactic
  is **telegraphed** each turn as an intent icon — that's what you play
  cards around.
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

Hand 5 · momentum cap 10 · the grid is 4×2 slots per side · first wave 3,
5 in reserve · enemy: 5 fielded, reserve 6, reinforce 2/turn into front
gaps, captain last · your grunts: 12 HP / 6 morale / 3 Str / speed 3;
defender grunts steadier at 7 morale (they are home) · enemy captain:
30 HP / 5 Str (never routs) · your captain: 20 HP / 4 Str · archer snipe
flat 2 · kill +2 momentum · ally death −2 morale to fielded side, rout −1.
A fight should run ~6–10 turns eventually. Post-cutover (phase A alone,
n=200): random bot 24.5% win / 47.5% defeat / 27.5% stalemate, avg 30
turns. Post-kits (phase B, distinct rosters, n=500): 5.6% win / 47.8%
defeat / 46.6% stalemate, avg 40 turns — the defender wall (two halving
shieldmen) makes a placement-blind bot grind, and their berserker's
cleave plus the jarl's aura punish its clumping. Rough by design: kill
order now matters and the bot cannot see it. Phases C–D (enemy dynamics,
card rework) carry the retune back to the 6–10 turn, near-even target.
The no-card bot stays a floor metric (collapses to a ~6-turn repulse: it
never crosses a second man).

## Playtest watchlist (decided, but on probation)

Rulings made deliberately, to be re-examined with the M1/M2 prototype in hand:

- **Cards-only control** — no manual retargeting. Fallback if fights feel
  like spectating: a generic `Order` (1 momentum: retarget one character).
- **Hand model (RESOLVED)** — full draw-play-discard each turn, with the
  Retained keyword (Reinforce, Swap, Drag Him Back!) and the automatic
  death-save. Scrapping removed with it.
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
- A retained card held for the right moment feels like discipline, not hoarding.
- A fight fits in ~5 minutes.

If three of five fail after tuning, the combat core gets redesigned before
any other system is built.
