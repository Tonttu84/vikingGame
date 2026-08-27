# The Lines Redesign — positional boarding combat (working spec)

Status: **phases A (geometry engine) and B (role kits) shipped;** C–D still
to come. The rules in `docs/combat-design.md` describe the shipped state. Systems this spec
does not mention (momentum carryover, morale waves and routs, maneuvers,
Retained cards, the automatic death-save, artifacts, hand model) carry over
unchanged.

Phase A landed with three deliberate deviations from the phasing below:
Break the Line (the shove, provisional cost 1) and Challenge (the captains'
cross-column duel, provisional cost 2) were repurposed in A rather than D —
their old effects referenced deleted rules, and shipping dead cards was
worse than pricing early (D still owns the numbers). And the UI grew a
per-token **incoming-damage forecast** (engine `forecast()`: physical +
morale, from the same targeting/damage code the phases resolve with) so
positional threat is readable at a glance.

## Why

On a flat field the kill order barely matters and targeting is invisible.
This redesign makes the fight a readable, re-arrangeable board where:

- you **snipe specific enemies for momentum** — preferably the ones dealing
  the most damage — while **avoiding HP damage on the men you plan to break
  by morale** (kills pay momentum; routs are free but pay nothing);
- **placement is targeting**: who hits whom is decided by where people
  stand, and cards move people;
- **placement is also defense**: attacks into an empty column hit air —
  misses are spatial and deterministic, never dice;
- the enemy re-arranges on a telegraphed schedule, so no ordering stays
  solved.

## Geometry

Each side: **4 columns × 2 lines**, plus the untouchable reserve.

```
their reserve  (below decks — can NEVER act, can never be hit)
their 2nd line  [ B1 ][ B2 ][ B3 ][ B4 ]
their front     [ F1 ][ F2 ][ F3 ][ F4 ]
                  |      |     |     |     column duels
your front      [ F1 ][ F2 ][ F3 ][ F4 ]
your 2nd line   [ B1 ][ B2 ][ B3 ][ B4 ]
your reserve   (your ship — can NEVER act; ship archers feed covering fire)
```

- **Adjacency** = same line, neighboring column (auras, cleaves).
- Any slot may be empty. Fielded caps are the slots themselves (up to 8);
  the rail bottleneck stays as the flow limit (Reinforce/commit per turn),
  not a standing cap.
- The old bow-fires-from-reserve rule is **deleted**. Reserve does nothing.

## Targeting: strict columns

- A fighter attacks **the nearest occupied enemy slot in his own column**
  (their front first, then their second line). Whole enemy column empty →
  **the attack misses** — he swings at air.
- Dodging is real: vacate a column and their berserker there hits nothing
  (at the price of your own attack lane in that column). Their telegraphed
  shifts re-aim at you; yours re-aim at them.
- **Front-liners** attack their column. **Spearmen** also attack their
  column from the second line (reach). Other second-liners cannot melee.
- **Archers** (second line only) auto-snipe: they shoot the **lowest-HP
  fielded enemy anywhere** (tiebreak: spawn order) for LOW damage (base 2).
  The weak base attack is deliberate — archers finish and harass, they do
  not carry. This is the one attack placement cannot dodge.
- Engagement tracking (`engaged_with`) and the spread/keep-target rules are
  **deleted** — columns replace them. The spear first-engagement bonus dies
  with them; spear's identity is now reach.

## The captain: no special rules

Their captain is simply **the last enemy to reinforce**. Until then he is in
reserve: unhittable, inactive, like all reserves. Once fielded he stands in
the formation like anyone — reach him through his column, snipe him with
archers, kill him and the crew yields. The exposure rules (field ≤ 2,
forced exposure) are **deleted**; `Break the Line` and `Challenge` are
repurposed (see cards). Your captain likewise: a fighter wherever you place
him, game over if he dies, safe while on your ship.

## Momentum (testing values)

- **+2 per kill** (up from 1) — sniping the right man is the tempo engine.
- **+1** at the start of your turn.
- Routs still grant **0** — breaking men is free but pays nothing.
- Carryover and cap 10 unchanged; revisit the cap if double bounties flood it.

## Role kits (data-driven hooks, same kits both sides)

Deliberately small sheet stays (HP/Morale/Str/Speed/weapon/armor); a kit is
one or two hooks, in ArtifactData style. If everyone has the same stats the
kill order is meaningless — kits are what make "kill him FIRST" a puzzle.

Implementation mapping (agreed, Phase B): kits ride the EXISTING idioms —
boolean flags and weapon kinds, no new enum. `is_shieldman` flag (half
damage rounded up applied last, after side-wide softening, to melee AND
snipes but not card/tactic true damage — volleys are the shieldman
counter-play; aura +1 armor to line-neighbors, melee only, never himself);
cleave rides `is_berserker` (2-damage graze to the target's line-neighbors,
captured before the main blow lands, softened and shield-halved but never
armored, kills pay the normal bounty); the anti-aura breaker rides the axe
weapon itself; the leader aura (+1 melee damage to line-neighbors) rides
`is_captain`. Covering Volley fires one 2-true-damage arrow PER archer in
your reserve, re-aiming at the weakest defender between arrows — zero ship
archers, silent rail. RosterText grows a `shieldman` token. Forecast must
include cleave grazes and the scaled volley.

| Kit | Hooks (v0 numbers) |
| --- | --- |
| Shieldman | Takes half damage (rounded up, after armor). Aura: +1 armor to line-neighbors. Low damage. Place him in the hard hitter's column. |
| Berserker | Cleave: his attack also hits the target's line-neighbors for 2. Morale-immune (existing). Their berserker is your #1 kill bounty. |
| Spearman | Reach: attacks his column from the second line. |
| Archer | Second line only. Auto-snipes lowest-HP fielded enemy for 2. |
| Breaker (axe) | Ignores 2 armor (existing) and his target gets no aura armor — the shieldman counter. |
| Karl | No kit. Cheap, low morale: rout fodder. Do not waste swings. |
| Captain | Leader aura: line-neighbors +1 damage. Big stats. No other rules. |

## Enemy dynamics: shifts + wind-ups (all telegraphed, never dice)

Two layers keep the solved order dissolving:

1. **Captain's calls** — formation moves telegraphed one turn ahead like
   tactics today: *Fresh men forward* (front and second lines swap),
   *Shift larboard/starboard* (the line slides one column, all matchups
   change), *Step up* (back-liners fill empty front slots). Chosen
   deterministically from the enemy's tactic list by the seeded RNG.
2. **Wind-ups** — per-role rhythms shown on the token: their berserker
   winds up a heavy cleave every 3rd turn (dodge his column or eat it),
   their archer marks a target one turn before a double shot. Fixed
   timers, visible counters.

Their reinforcement keeps its fixed rate and now also **chooses slots**
deterministically (fill front gaps first, left to right), captain last.

## Cards: movement rides on effects

The design principle (decided): **movement is semi-free — it rides on cards
you would play anyway.** A pure movement card has to compete with direct
effects for the same card slot and loses; a free-move action makes position
too cheap to mean anything. So MOST cards carry a movement rider next to
their effect: play the card for its punch and the move comes with it. The
only movement-first cards are the retained crossing pair (Reinforce/Swap),
whose job was always logistics. Sketch (priced in Phase D):

| Card | Sketch (effect + movement rider) |
| --- | --- |
| Reinforce (retained) | Field a reserve man **into a slot you choose**. |
| Swap (retained) | Any two of your men trade slots (fielded↔fielded or fielded↔reserve). |
| Spear Volley | 2 damage to the enemy front line, then slide one of your men one column. |
| Shield Wall | Your side takes −2 this round; first, swap any two of your fielded men into place. |
| Rally | Heal an ally 4; he may step one line forward or back. |
| Battle Fury | An ally attacks twice this turn; he may first advance into an empty front slot. |
| War Cry | +1 momentum per kill this turn; slide one of your men toward the killing. |
| Feint | Draw 2; slide one of your men one column (the feint IS the step). |
| Fall Back | Retire a front-liner to his second line; +2 morale to him (breather). |
| Break the Line | REPURPOSED: shove an enemy front-liner one column sideways — you re-aim THEIR formation (into the berserker's wind-up, out of the shieldman's aura). |
| Challenge | REPURPOSED: only while both captains are fielded — they attack each other this round regardless of columns. |
| Terrifying Bellow / Concentrated | Effects unchanged; riders to be decided per card in Phase D. |
| Aim! (maybe) | Override the archers' auto-snipe target this turn. Only if playtests want it. |

Concentrated Attack becomes: everyone **who can reach the target** strikes
it (his column's attackers + archers) — reach still respects geometry.

## What gets deleted

Engagement tracking and spread targeting · captain exposure rules
(`captain_forced_exposed`, field ≤ 2, EXPOSE_CAPTAIN effect) · bow from
reserve · flat-field `player_field`/`enemy_field` arrays (become slot
grids) · the duel-bypasses-the-line rule.

## Phases (each shippable, TDD, own commit)

- **A. Geometry engine — SHIPPED** — slot grids, strict-column targeting
  with spatial misses, reach/snipe, movement verbs (slide/advance/retire/
  swap/place; slide is player-reachable through the shove, the rest through
  Swap/Reinforce until D's riders), kill = +2, reserve-never-acts,
  captain-as-plain-last-reinforcement, RosterText slot syntax (`f1`..`b4`),
  UI renders 2×4 grids (functional, not pretty) with forecast badges.
  New suites: `test_formation`, `test_column_targeting`, `test_forecast`.
- **B. Role kits — SHIPPED** — the hooks table above exactly as mapped
  (shieldman auras never stack — a second adjacent shield adds nothing;
  the cleave arc is captured before the blow lands), distinct default
  rosters both sides
  (raider breakers vs a two-shieldman defender wall, karls at morale 4),
  covering-volley scaling with ship archers, forecast covering grazes
  and the re-aimed volley. Suite: `test_kits`. Post-B sims are in
  combat-design.md's tuning baseline: the wall grinds the random bot
  (5.6% win, 46.6% stalemate) — kill order is real and the bot is blind
  to it; D owns the retune.
- **C. Enemy dynamics** — captain's calls + wind-ups, telegraph plumbing,
  reinforcement slot choice. Suite: `test_patterns`.
- **D. Card rework & polish** — the table above, prices from sims, UI drag
  targets for slots, retune to ~6–10 turn fights.

Bot note: RandomBot learns legal placement moves only (random but valid);
tuning targets stay honest but expect noisier numbers until D.

## Open questions (watchlist)

- Column count 4: right for an 8-man crew? (3 would crowd, 5 would straggle.)
- Archer damage 2 and kill bounty +2: first numbers to sim.
- Does the PLAYER get free step-up when a front slot empties, or is that
  cards-only too? (Start cards-only; the enemy's step-up is a captain call.)
- Does losing spear-first-strike make spears too plain? (Reach may be enough.)
- Aim! card: only add if auto-snipe frustrates in playtests.
- Movement riders: optional or mandatory? Optional ("may slide") is safe;
  mandatory riders make strong effects double-edged — the best card in hand
  might force an awkward step, which is texture AND friction. Start
  optional; try mandatory on one or two cards as spice.
