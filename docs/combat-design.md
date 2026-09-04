# Combat Design — Boarding Actions

This is the core of the game and the first (possibly only) thing we build.
Everything else in `game-design.md` is the long-term frame around it.

> **Redesign in progress:** positional combat is specified in
> [lines-redesign.md](lines-redesign.md) and lands in phases. **Phases A
> (the geometry engine), B (role kits) and C (enemy dynamics) have
> shipped** and this document describes them; the card rework and retune
> (D) is still to come.

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
are the fielded cap. The rail bottleneck is the crossing **rate** (the
turn's opening, plus Reinforce/Trade Places per turn), not a standing limit.

- **Placement is targeting.** A fighter attacks the nearest occupied enemy
  slot in his own column — their front first, then their second line. A
  whole empty enemy column means his swing **misses**: he hits air. Misses
  are spatial and deterministic, never dice.
- **A man who misses closes.** Rather than flail at the same empty column
  every turn, he forfeits the swing and **steps one column toward the
  nearest column with someone in it** (port on a tie; he stays put if
  his own line walls him in, and then he does swing at air). Second-liners
  who cannot reach never step — closing would buy them nothing.
- **Placement is also defense.** Vacate a column and their berserker there
  hits nothing — at the price of your own attack lane in that column. But
  the dodge buys a **turn**, not the fight: he walks the deck down and
  arrives — and **the man he walks toward is PINNED** where he stands
  (docs/block-and-patterns.md): no movement at all, by any hand, on a
  counter that grows with every repeat dodge and works loose 1 per own
  turn. Two survivors in different columns can no longer stand and
  stare at each other until the turn limit, and a runner cannot run
  forever.
- **The front line is relative** (owner's playtest ruling, 2026-09-04):
  a second-liner with nobody in the front slot of his own column counts
  as standing in the front line — he fights his column, he takes its
  blows (the column rule always sent them to him), and he closes like
  any front-liner when his column is empty of enemies. Auras and the
  forced movements (shove, drive) read REAL positions, never relative
  ones — being effectively front carries no boosts.
- **Front-liners** — actual or relative — fight their column. **Spears**
  also fight it from the second line even when covered (reach).
  **Archers** work their two beats only while COVERED — a man in the
  front slot of their column (docs/block-and-patterns.md): AIM locks the
  lowest-HP fielded enemy *anywhere* (spawn-order tiebreak; the focus
  target while one stands) with a full turn of warning, then SHOOT
  looses both flat-2 arrows at the mark and leaves him suppressed — the
  attack placement cannot dodge, though a raised guard blocks it and a
  rescued mark wastes it. An uncovered archer counts as front like
  anyone else: hand to hand, no aiming. A covered second-liner without
  reach simply holds his place. The **reserve never acts and can never
  be hit.**
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
- Your reinforcements flow through **the turn's opening** and **the deck**:
  the opening crosses one man free every turn (below), and on top of it
  `Reinforce` fields a man from your ship **into a slot you choose** while
  `Trade Places` trades any two of your men (fielded↔fielded or
  fielded↔reserve — also how the captain trades places with his prowman).
  A bad hand can never strand the first wave: the opening is always there.

## The press (shipped, 2026-09-05)

Every column is a duel and the line is a verdict (docs/press-proposal.md,
owner's rulings). Judged **once per round, after both sides' beats and
before reinforcements**, where men stand at that moment:

- **Presence first.** A column held by one side alone is that side's — the
  man facing nobody already lost his swing; holding the column is what he
  contributes. A column empty on both sides scores for nobody.
- **Both present: blood decides.** The side that dealt more blood INTO the
  column this round wins it — only what reached flesh (a blow that died on
  the guard is 0; the shieldman's planted shield is a full answer), from
  melee, heavy blows and cleave grazes alike, in the column the victim
  stood in when the blow landed. Equal, including 0–0, is no result.
- **The no-resolution tag.** Blood from a man whose weapon carries
  `resolves_columns = false` — the bow — never scores, ranged or melee.
  The rule is on the weapon, never the row: a covered spear's reach from
  the second line counts like any steel.
- **The press.** The side with more column wins has it; `margin` is the
  difference. Equal wins: no press.
- **The win bonus.** Player has the press: **+1 momentum for having it, +1
  per column of margin** (2–1 pays 2, 4–0 pays 4; capped at 10). Whoever
  has the press at **margin ≥ 2**: every fielded man of the losing line
  takes **−1 morale** (the morale-immune shrug; routs check). The enemy has
  no momentum, so its press pays only your morale.
- **Nothing moves.** A verdict, never a shove.
- The table shows the projected press beside their telegraphed tactic
  (`forecast_press()`, the same pass as the damage forecast: your blows on
  current geometry, theirs from their called positions) and last round's
  verdict; the ledgers (`player_column_blood`/`enemy_column_blood`) reset
  at your turn.

Constants are placeholders for the retune, like everything else.

## Role kits (shipped, phase B)

The sheet stays small; a kit is one or two positional hooks riding the
existing idioms — boolean flags and weapon kinds, no class enum. Kits are
what make "kill him FIRST" a puzzle; the same kits stand on both sides.

| Kit | Hooks (docs/block-and-patterns.md rework) |
| --- | --- |
| Shieldman (`is_shieldman`) | **The block kit**, pattern `guard, attack`: on the guard beat he swings nothing, raises his armor in block AGAIN on top of the turn-start guard, and his line-neighbors gain 2 each (same line, adjacent column, never himself). High guard value on the sheet (4–5 in the anchors). True damage still goes around block — volleys stay his counter-play. The old half-damage rule and +1-armor aura are gone. |
| Berserker (`is_berserker`) | Morale-immune (as before). Pattern `attack, attack, heavy`: the HEAVY beat doubles the blow and the graze. **Cleave:** his attack also grazes the target's line-neighbors for a flat 2 — softened and blocked like any physical hit; graze kills pay the normal bounty. The arc is set before the blow lands. Their berserker is your #1 kill bounty. |
| Spearman (spear) | Reach: fights his column from the second line. |
| Archer (bow) | Pattern `aim, shoot` — see character control above. Second line only in practice; at the rail he is just a fighter, though his beats keep marching. |
| Breaker (axe) | **Chews 2 block per point of damage, and axes swing first** in the fight order — the block-chewing lands while there is block to chew, opening a guarded man for the swords behind. (Piercing was wrong with multiple attackers: block the axe ignored would still stop everyone else.) |
| Karl | No kit. Cheap, low morale (4): rout fodder — do not waste swings. |
| Captain (`is_captain`) | **Leader aura: line-neighbors strike +1 in melee** (never himself, never snipes). Big stats. The ENEMY captain also carries his command — see enemy dynamics. |

The default rosters give the sides distinct silhouettes: your raiders are
breakers (axes, a spearman, one shieldman, an archer feeding the rail),
their watch is a wall (two shieldmen up front, a bowman behind, karls and
the berserker in the hold).

## Enemy dynamics (shipped, phase C)

Two telegraphed layers keep any solved kill-order dissolving — all fixed
timers and formation verbs, never dice:

- **Captain's calls** are formation moves in the enemy tactic pool,
  telegraphed a turn ahead like every tactic: *Fresh Men Forward* (their
  lines trade places), *Shift Port/Starboard* (the whole line slides a
  column — every duel re-pairs; each man moves only if his destination is
  free, processed from the leading edge, so pinning their wall against the
  rail denies the call), *Step Up* (back-liners fill their columns' empty
  front slots). The forecast previews enemy attacks from the positions the
  call will put them in; your own attacks resolve before the call, on
  current geometry.
- **Patterns** (docs/block-and-patterns.md, superseding the enemy-only
  wind-ups): every unit on BOTH sides follows its role's beat cycle, one
  beat per own fight phase, telegraphed on the token — the berserker's
  heavy blow, the archer's aim-then-shoot, the shieldman's guard. Beats
  advance landed or wasted alike; a man arriving on deck starts his
  rhythm over. Your own crew's rhythms are yours to plan around too.
- **The captain's command** replaces the telegraphed tactic every 4th
  enemy turn, from the sterncastle or the line alike: every fielded
  defender gains a permanent, stacking +1 attack damage. Unbounded
  escalation is the guarantee no fight locks up — and the reason slow
  play bleeds. Commands are scenario data; later captains carry
  different words.

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

## The prow pair (officers, first slice — shipped)

The **prowman** (stafnbúi — the prow warrior who led the charge) is the
captain's alternate, not his subordinate. Rulings (2026-08-28):

- **One of the pair must hold the field.** The prowman leads the first
  wave; the captain waits at his own rail. They are never fielded together.
- **They trade places only with each other.** `Swap` played on the fielded
  one — or the turn's free opening trade — brings the other across into his
  exact slot. Neither can swap with ordinary crew, cross by `Reinforce`, or
  take the opening's free crossing — and once the captain is the last of the
  pair, he cannot leave.
- **If the prowman leaves the field for good** — slain or broken — **the
  captain leaps the rail himself, immediately, for 1 momentum**
  (`PAIR_ENTRY_COST`). If the crew cannot pay, panic takes them: instant
  DEFEAT. Bank a point while the prowman fights.
- **Nobody drags the prowman back.** The Drag Him Back! reaction save never
  fires for him; his fall is the pair's hinge, and an automatic save would
  chain into a forced crossing the player never chose.
- Captain dies — game over, as ever. The rules activate only when the
  roster declares a prowman (RosterText token `prowman`, player side);
  bare test rosters keep the old free-crossing behavior.

HP not healing fully between a raid's battles (so both men's health is
managed across the whole raid) still lands with the raid loop; the formal
officer system with event rolls comes later.

## Turn structure

```
BOARDING (once)
  0. Choose and resolve a boarding maneuver (free card from its own deck).
PLAYER TURN
  1. Gain +1 momentum. Discard the hand (Retained cards stay), draw to 5.
  2. THE OPENING — one forced choice, nothing else is playable until it is
     made: (a) a FREE reinforcement, one man off your ship into a slot you
     pick; (b) a FREE swap ("snap"), two of your men trade places,
     fielded<->fielded or fielded<->reserve; or (c) +1 momentum AND +1 card,
     on top of step 1's own +1.
  3. Play any number of cards (pay momentum). Reinforce is the turn's
     SECOND crossing, Trade Places its second snap — both still priced.
  4. Fight: every fielded man performs his beat — axes first, then by
     speed (see character control); guard resets to armor at turn start.
ENEMY TURN
  5. Enemy tactic resolves (was telegraphed as an intent last turn) —
     a damage tactic, a captain's call re-arranging their line, or the
     captain's command itself every 4th turn; their guard resets first.
  6. Enemy characters perform their beats (heavy blows, aimed arrows,
     planted shields).
  7. Reinforce from below decks (the captain last); statuses tick
     (suppression and pins work loose); reveal next tactic.
```

## Momentum (the resource)

Momentum is battle tempo — a snowball resource that rewards aggression. The
boarding maneuver supplies a large opening surge (see above): you start the
fight rich and act from strength, exactly as a boarder should.

- **+1** at the start of your turn.
- **+1 more, and a card**, when the turn's opening takes the income instead
  of a free crossing or a free snap. That is the whole price of those two
  moves: a momentum and a card of tempo, paid by not taking them.
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
(dead weight) loot. **The shipped set is 15 tactics** (card rework, phase D —
docs/card-design-proposal.md is the design; every ruling in it is implemented
except the jump, see below).

**Every card carries both an effect and a movement, and the movement's
direction is fixed by the card.** That is the structural rule the set is
built on, and it partitions cleanly into three families:

| Family | The movement is | Cards |
| --- | --- | --- |
| **Rail** | a crossing, field ↔ reserve | Reinforce, Trade Places, Drag Him Back! |
| **Theirs** | forced on an enemy — the effect itself | Break the Line, Drive Him Back, Taunt |
| **Riders** | a fixed step by one of your own men | everything else |

### The five fixed movements (riders)

| Keyword | Meaning | Register |
| --- | --- | --- |
| **Close** | one column toward the nearest occupied enemy column (port on a tie) — the closing rule's own direction | perk |
| **Press** | second line → the empty front slot of his column | perk / setup |
| **Port** | one column toward column 0, along his own line | coin-flip cost |
| **Starboard** | one column toward column 3, along his own line | coin-flip cost |
| **Give Ground** | front → the empty second-line slot of his column | penalty |

Perk riders ride the cheap cards, the coin-flip pair the mid cards, Give
Ground the strong ones. Port and starboard are carried in **equal numbers
in every deck** (a test enforces it): on a symmetric board an imbalance is not
flavour, it is a silent drift of the whole crew toward one rail.

### The set

| Card | Cost | Effect | Movement |
| --- | --- | --- | --- |
| Reinforce | 1 | Retained. Field a man from your ship into a slot you choose | the crossing |
| Trade Places | 2 | Retained. Any two of your men trade slots (fielded↔fielded or fielded↔reserve) | the trade |
| Drag Him Back! | 1 | Retained, reaction. Fires automatically when a killing blow lands on a crew member: cancels it, pulls him to the ship at 1 HP (the permadeath safety valve — holding it and its momentum IS the play) | the pull |
| Break the Line | 1 | Shove an enemy front-liner one column sideways — you re-aim THEIR formation | theirs, your chosen direction |
| Drive Him Back | 2 | An enemy front-liner is driven into the second line of his column, swapping with the man behind him | theirs |
| Taunt | 2 | Name a defender and one of your men: the defender is dragged into the front slot of your man's column, swapping with whoever stood there | theirs |
| Feint | 0 | Draw 2 | Close |
| War Cry | 1 | +1 momentum per enemy slain this turn | Port |
| Terrifying Bellow | 1 | 2 morale damage to every fielded enemy | Starboard |
| Spear Volley | 2 | 2 true damage to every enemy front-liner | Port |
| Concentrated Attack | 2 | Everyone who can REACH the target (his column's attackers + your archers) strikes it this fight phase | Starboard |
| Battle Fury | 1 | An ally strikes one extra time this fight phase | Press |
| Push Them Back | 2 | No enemy reinforcements next turn | Press |
| Shield Wall | 1 | Your side takes −2 from every hit until your next turn; stops arrow volleys | Give Ground |
| Rally | 1 | Heal a **fielded** ally 4 | Give Ground |

Prices are still the pre-retune ones; card prices and roster HP are the last
mile to 6–10 turn fights and are deliberately untuned until the cards are
real, which is what this set is.

### Rulings the set depends on

- **The direction is never the player's.** A free direction is always good
  and so is never a cost. The player picks WHICH man takes the step; a card
  that names an ally binds the rider to him, so it asks nothing at all.
- **You may aim what you do to them; you may not aim what an order does to
  your own crew.** That is why Break the Line keeps a chosen direction: the
  shove *is* its effect, not a price attached to one.
- **Riders never displace** — the destination must be empty. A swap is a
  strong effect worth a card of its own (Trade Places), not a rider.
- **A card whose rider has no legal move is refused before payment**, card
  kept, nothing paid, exactly as a Reinforce with nowhere to land is. The
  movement is part of the price, so it cannot be engineered away by packing
  your grid. Battle Fury cannot be played on a front-liner; Rally cannot be
  played on a second-liner or on a man whose slot behind is taken; Shield
  Wall needs a front-liner who can retire. That is intended. The three
  rider-less rail cards are the escape valve, and ending the turn is always
  legal.
- **Rally is fielded-only.** Healing a man safe on the ship is not the
  decision the card asks for, and its rider would have nothing to ride on.
- **Give Ground is a disarm, never an escape** (and so is Drive Him Back
  from the other side): a man who retires inside his own column is still the
  man that column's attacker hits — `Formation.column_melee_target` takes the
  front man *if there is one, else the back man*. He has only given up his
  own swing. Only emptying a whole column dodges anything.
- **Challenge is folded into Taunt.** Taunt on the enemy captain *is* a
  challenge, expressed as movement rather than as a targeting override. The
  card, `challenge_active`, and the captain branches in `_pick_target` and
  `_can_melee` are deleted: there is no targeting override left in the
  engine, and a duel is arranged by moving men.
- **Taunt cannot be edge-blocked** — its destination is your own man's
  column — and it hauls a second-liner FORWARD, which is what drags their
  archer out of sniping position (`_is_sniper` requires the back line). It
  only ever increases contact, so it can never manufacture dead air.
- **Drive Him Back is weapon-aware without weapon code**: a spearman shrugs
  it off (reach works from the second line), a bowman is *upgraded* by it,
  everyone else is silenced while he stays back. Playing it on the wrong man
  helps them.
- **No enemy Taunt or Drive Him Back.** Enemy movement is telegraphed a turn
  ahead by design; an untelegraphed drag on their turn would break the rule
  that the player can always read the coming turn off the board. If it is
  ever added it arrives as a fifth captain's call, with a one-turn intent.
- **Jump (two columns) is not in the set, and is not cut on principle.** A
  fixed-direction jump is illegal from half the board at all times, and a
  jump *out* of contact buys two turns of dead air for one card — it is the
  one movement that can re-open the stall the closing rule closed. If it ever
  ships it must be a **player-aimed jump attached to a card that also carries
  a real effect** (every card is movement + effect; a pure-movement card
  loses its slot to a real one), and it lands **after** the numeric retune,
  not before.

Design rules: damage cards should rarely beat just letting characters fight —
cards **bend** the fight (tempo, protection, targeting, windows), they don't
replace it. Death prevention must exist but be scarce.

## Character control: autobattler with card override (adopted — on probation)

Decision: **autobattler bodies, card-controlled battle** — adopted for v0,
explicitly to be validated in M2 playtests (see the watchlist at the end).

- **Targeting is deterministic and spatial.** Who hits whom is decided by
  where people stand: a fighter attacks the nearest occupied enemy slot in
  his own column and archers snipe the weakest man anywhere. There is no
  override: to force a duel you MOVE a man into it (Taunt). Who gets hit is
  never lucky or unlucky;
  targeting RNG would undermine the no-dice rule below. Predictable AI is
  a feature — you plan around it like a puzzle, and the sim can verify it.
- **The bill is on the board.** The UI forecasts, per fighter, the physical
  and morale damage he stands to take next fight phases (column duels,
  reach, snipes, the telegraphed tactic — enemy attacks previewed from the
  positions a telegraphed call will put them in — wound-up heavy blows,
  aimed double shots, the morale wave of predicted deaths) — you read
  threat off the tokens instead of adding it up.
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
  from the second line. Axe: chews 2 block per point and swings first.
  Sword: +2 damage, no gimmick. Bow: second line only in practice — aims,
  then both flat-2 arrows suppress the mark. Looted weapons are
  equippable *or* sellable.
- **Armor** (1 slot): the man's GUARD — the block he starts each of his
  side's turns with (docs/block-and-patterns.md). Not a reduction.
- **One personality trait** (later, for the dynasty layer): coward, fury,
  loyal — hooks for events and AI quirks. Not in v0.

Damage = attacker Strength + weapon + rage + leader aura, minimum 1;
doubled on a heavy beat; cut by a third (rounded up against him) while
suppressed; then side-wide softening (shield wall, careful advance),
minimum 1; then the defender's BLOCK chews it — point for point, double
rate against an axe — and only the remainder wounds; zero blood is a
legal outcome. Card and tactic true damage goes around block. No misses,
no crit RNG in v0 — deterministic combat makes permadeath feel fair and
the engine testable; randomness lives in cards drawn and enemy tactics.

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
order now matters and the bot cannot see it. Post-dynamics (phase C,
n=500): 40.0% win / 48.4% defeat / 11.6% stalemate, avg 27 turns — the
captain's own calls break his wall's grind (a shieldman shifted off his
column stops anchoring it), wind-ups add spike damage both ways. Phase D
(card rework) carries the retune to the 6–10 turn, near-even target.
The no-card bot stays a floor metric (collapses to a ~6-turn repulse: it
never crosses a second man).

Post-pair (the prow pair, n=300, random bot): skirmish 58.7% win / 33.3%
defeat / 8.0% stalemate, avg 22 turns — the forced crossing fields the
captain (fearless, aura, STR 4) in fights where the bot once left him
ashore, and his entry converts many stalls into pushes. Veteran 64.0% win.
The no-card floor changes character: 64.7% defeat / 24% stalemate — with
no Swap card the captain, once forced across, fights until he falls, so
repulsed boardings become captain-deaths. Both shifts are the mechanic
speaking, not tuning targets; phase D owns the retune.

Post-closing (phase D chunk 3, n=300, random bot): skirmish 46.3% win /
53.7% defeat / **0% stalemate**, avg 14.1 turns (from 44.0% / 6.0% / 21.8);
veteran 58.7% win / 0% stalemate, avg 16.7 turns (from 61.0% / 5.0% /
20.7). The cost of victory improved with it — skirmish 1.24 → 1.12 dead in
a win, veteran 0.98 → 0.81 — because fights that used to be decided by
attrition over twenty turns now end while men are still standing. No
roster number and no card price moved: this is the closing rule alone,
and stalemates are gone because the board can no longer deadlock. The
no-card floor changes character again: 29.0% win / 71.0% defeat, avg 15.9
turns, since a passive crew's men now walk into contact instead of being
stranded in empty columns — still a clear loss, and the ~17-point gap to
the random bot is what card play is worth. The remaining distance to
6–10 turns is deliberately left to card prices and roster numbers once
the cards are real rather than placeholders.

### Two balance anchors & the cost of victory

Balance is read off two registered scenarios (`Scenarios.scenario_ids()`,
`scripts/sim.sh --scenario=`), bracketing a campaign the raid loop will
eventually string together:

- **skirmish** — day one: the 8-man starter crew, the 27-card starter deck,
  the karl-and-shieldman deck watch.
- **veteran** — deep in the raid: the same crew a summer later (10 men,
  blooded stats, armored in plunder, a second shieldman and archer), a
  39-card deck (deeper on the rail and the punch cards, five pieces of
  loot clogging it), boarding a jarl's levy warship (14 men, a thicker
  wall, a berserker and a second bowman in the hold, a 36 HP captain).

**Ruling: crew losses are permanent at the campaign level.** The raid loop
(planned) carries the roster between fights; the dead never come back.
There is no extra in-battle mechanic for this — morale waves already price
each death inside a fight — but it changes what "balanced" means: a win
that costs half the crew is a loss on layaway. The sim therefore grades
victories by body count (avg dead in a win, wins-by-dead histogram), and
tuning targets the cost of victory, not the win rate alone. Current
numbers (n=300, random bot): skirmish 41% win, 1.04 avg dead in a win,
40% of wins bloodless; veteran 63% win, 0.88 avg dead in a win, 53%
bloodless — the veteran crew overpowers even the bigger ship, which is
acceptable slack until phase D retunes prices. Both scenarios' no-card
baselines collapse to a repulsed boarding, as designed.

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
- ~~**The commit action**~~ — RESOLVED 2026-09-05: the 1-momentum manual
  crossing is deleted and **the turn's opening** replaces it (turn
  structure, step 2). The deck no longer has to carry the first wave alone
  and the crossing costs tempo, not coin. What the opening opens instead:
  income turns now pay 2 momentum and a card, so re-read the momentum-cap
  question above against that.

## What "fun" means here (evaluation checklist for the prototype)

- At least once per fight you choose between grinding the line and forcing a
  window to the captain.
- Momentum swings are legible: you can feel a turn where the boarding "tips".
- A character death makes you angry at yourself, not at dice.
- A retained card held for the right moment feels like discipline, not hoarding.
- A fight fits in ~5 minutes.

If three of five fail after tuning, the combat core gets redesigned before
any other system is built.
