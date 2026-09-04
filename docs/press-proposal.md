# The press — scoring the shieldwall column by column (proposal)

Status: **RULED 2026-09-05 and IMPLEMENTED** (suite `tests/test_press.gd`;
the shipped rule is tabulated in `docs/combat-design.md`, "The press").
The owner's rulings on the forks below:

1. **Payout — the win bonus (e):** +1 momentum for having the press, +1
   more per column of margin (`PRESS_WIN_MOMENTUM`, `PRESS_MARGIN_MOMENTUM`);
   the losing line takes −1 morale on every fielded man at margin ≥ 2
   (`PRESS_MORALE`, `PRESS_MORALE_MARGIN`). The enemy has no momentum, so
   its press pays only your morale.
2. **Which damage counts — a TAG, not a row rule.** Arrows do not resolve
   columns, but the rule is not "second line does not count": a covered
   spear's reach from the second row scores like any steel. The bow carries
   `Weapon.resolves_columns = false`, so an archer's damage never wins a
   column — ranged or bow-butt melee alike. Future units can carry the tag.
3. **Only blood counts.** Damage the guard absorbed is a 0; the shieldman's
   planted shield is a full answer. The scoring equals what the forecast
   already shows.
4. Uncontested columns are wins for the side present (ruled 2026-09-02) —
   and **presence comes first**: a column held by one side only is that
   side's whatever the ledger says, so blood into a column you do not hold
   wins nothing, and a column empty on both sides scores for nobody.

Everything below is the proposal as argued; where it and the rulings
differ, the rulings and `combat-design.md` win.

## The idea (owner's words, lightly ordered)

Make the combat more shieldwall-ish, more about the formation. Every column
is a duel: **if your man does more damage than the man facing him, you win
that column.** The side that wins more columns gets a bonus — at least
momentum for the player, scaled by how much the line won by — and the losing
side might take morale damage. Or something else, if something better turns
up.

## Why it fits

The lines redesign already made placement targeting and defense; what it
did not make is a reason to hold a *line* rather than four separate lanes.
Today a column is only a lane for damage. Scoring it turns each column into
a contest with a winner, and the count of winners into a verdict on the
whole formation: a shieldwall that holds three columns of four **is
winning** even before anyone dies. That is the shieldwall fantasy — the
press, the line that gives — and it is deterministic, readable off the
board, and already forecastable by the engine's `forecast()`.

It also gives the player a second tempo engine besides kills, which is the
one the momentum design lacks: today the only way to earn momentum in the
fight is a corpse, so the best formation is the one that kills fastest.
Winning the press rewards *holding* — block, shieldmen, Careful Assault —
as tempo, not just survival.

## Proposed rules (first cut)

Resolved **once per round, after step 6** (both sides' beats have landed),
before reinforcement.

1. **Column duel.** For each of the 4 columns, total the physical damage
   each side **dealt into that column this round** (after block and
   softening; a miss is 0; a graze counts in the column it landed in). The
   side with the higher total **wins the column**. Equal totals — including
   0–0 — is no result.
2. **Uncontested columns are wins** (RULED 2026-09-02). A column with men
   on only one side is won by that side: the man facing an empty column
   has already forfeited his swing to a miss or a closing step, so
   holding the column is what he contributes. Columns are scored **where
   men stand after the beats**, closing steps included — a man who
   stepped this round counts in the column he arrived in, where he dealt
   0, so he can hand that column to the enemy if their man there landed
   a blow. A column empty on both sides scores nothing.
3. **The press.** The side with more column wins has the press this round;
   `margin` = its wins minus the other side's wins. Equal wins: no press.
4. **The bonus.**
   - Player has the press: **+`margin` momentum** (still subject to the
     cap of 10).
   - Whoever has the press: **every fielded man of the other side takes −1
     morale** if `margin` ≥ 2 (the line is giving); at `margin` 1 nothing
     but the momentum. Berserkers stay immune, captains never rout,
     nothing new there.
5. **Nothing moves.** The press is a verdict, not a shove. Movement stays
   on the cards and on the closing rule.

Constants — `PRESS_MORALE = 1`, `PRESS_MORALE_MARGIN = 2`, momentum
1:1 with margin — are placeholders for the retune, like everything else.

### What it interacts with

- **Momentum economy.** Kills pay 2; a press pays up to 4 (a clean sweep)
  every round, forever. That is a lot. If the sims show momentum pinned at
  the cap, the first levers are: pay momentum only at `margin` ≥ 2, or cap
  the press at 2. The design principle to keep is that momentum stays
  tempo: the press is tempo (your line is driving theirs), so it belongs
  here rather than in morale alone.
- **Block and patterns.** A blocking beat deals 0, so a shieldman *cannot*
  win his column on his block turn — he can only deny it (their blow into
  his guard is 0 too, so 0–0, no result). That is right: the wall holds,
  the axe-men win. Whether damage *absorbed by guard* should count as
  "dealt" is fork 3 below.
- **Archers.** Their arrows land in the mark's column and count there
  (rule 1 says "into that column"), so an archer can swing a column her
  side has no front-liner in. That makes the second line matter to the
  press; fork 2 asks whether that is wanted.
- **The first wave.** Three boarders against a watch of five leaves one
  column with defenders only, so the watch wins it every round until a
  reinforcement fills it: the press starts against the boarder, and
  hurrying men over the rail (Reinforce, the commit action) is how it is
  turned. On-fantasy, and it prices the boarding maneuver's opening
  momentum against a standing morale leak — the sims should read how many
  rounds the fourth column stays open.
- **Kill vs break.** Unchanged in spirit, sharper in practice: routing a
  column's front man loses them that column next round *and* pushes the
  press, so fear tactics now feed the momentum engine indirectly.
- **Enemy side.** The enemy has no momentum, so the press pays it only
  morale damage on the player's men. Asymmetric by design (the enemy's
  tempo is the captain's word). If that feels toothless, the enemy press
  could instead bring the captain's command a turn earlier.
- **Forecast.** The per-token forecast already predicts damage per column;
  the press forecast is a sum over it — showable as a per-column
  "winning / losing / even" glyph and a projected margin, so the player
  reads the verdict before committing cards. UI shows nothing the engine
  did not compute.

## Forks to rule on (recommendation first)

1. **What the press pays.** (a) momentum = margin to the player, morale
   −1 to the losing side at margin ≥ 2 — *recommended: it is the owner's
   idea and both halves are existing currencies*; (b) morale only, no
   momentum (safer for the economy, but then holding a line never earns
   tempo, which is the thing the idea fixes); (c) a +1 damage aura for
   the pressing side next round, like the captain's word (loud, but
   stacks with the word into an avalanche).
   **Owner's addendum (2026-09-02): consider making *winning at all* the
   thing that matters**, in one of two shapes — (d) *just win*: a flat
   reward for having the press, margin ignored (say +2 momentum, and the
   morale wave on every press), so a 2–1 line and a 4–0 sweep pay the
   same and the whole contest is about tipping the count; or (e) *win
   bonus*: a flat extra on top of the margin (say +1 momentum for the
   press itself, then +1 per column of margin), so the first column of
   advantage is worth more than any later one. Either makes getting the
   press more important than running it up, which pulls play toward
   contesting the marginal column rather than piling onto a column already
   won. (e) keeps the margin readable and is the smaller change; (d) is
   the cleaner rule if the sims show margin-chasing dominates.
2. **Which damage counts.** (a) all physical damage into the column,
   arrows included — *recommended: it makes the second line part of the
   wall*; (b) melee only, so the press is strictly the front line's.
3. **Does blocked damage count?** (a) only damage that reached HP —
   *recommended: block is supposed to stop things, and it keeps the
   scoring identical to what the forecast already shows*; (b) damage
   before guard, so a man who forced their shield up still "won" — more
   swings score, fewer 0–0 columns, but the shieldman's block turn stops
   being a full answer.
4. ~~**Uncontested columns.**~~ RULED: they count as a win for the side
   present (rule 2). The owner's reasoning: the man facing an empty
   column has already lost his attack to the miss, so he should at least
   contribute something. Spreading wide is therefore a press strategy,
   and the consequence for the boarding is noted above.

## Something else, if the press disappoints

- **The shove as verdict.** Instead of a bonus, the winning column's loser
  is treated as if shoved (Break the Line's effect, free) when he lost by
  ≥ N. Visceral, but it moves men without a card, against the spirit of
  the rider design, where only a card or the closing rule moves a man.
- **Line integrity.** Adjacent men who both won their columns grant each
  other +1 guard next round: the wall rewards itself locally, no side-wide
  verdict at all. Smaller, purely defensive, no economy risk.
- **The press as a track.** A single side-wide counter (−4..+4) that the
  round's margin moves; at ±4 the losing side's whole front takes a morale
  wave and the track resets. Slower and swingier; reads like a tug of war.

## If it ships: the implementation shape

- New system → new suite `tests/test_press.gd`. Column scoring, the
  uncontested rule, the tie rules, the margin, momentum with cap, the
  morale wave at margin ≥ 2 and not at 1, berserker immunity, that arrows
  count in the mark's column, that nothing moves, and determinism under
  `test_same_seed_same_battle`.
- Engine: a `press_result` computed in the fight phase from the same
  damage events the forecast uses (no second damage model); a
  `forecast_press()` for the UI next to `forecast()`.
- Sims before/after on both anchors, reading momentum-at-cap turns and
  the cost of victory, per the retune rules in `docs/combat-design.md`.
- Lands **before** the numeric retune, by the standing rule that prices
  wait until the mechanism is settled.
