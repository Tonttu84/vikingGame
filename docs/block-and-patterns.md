# Block, patterns, the captain's word, and the pin

The mechanics overhaul the owner deferred until the cards were real designs.
The cards are real now, so this lands BEFORE the numeric retune: block changes
what a hit is worth, patterns change when hits come, the captain's command
changes how long a fight can last, and the pin changes what dodging costs.
Tuning any price before these would be tuning a different game.

Owner rulings this document implements (recorded 2026-08-29/30):

1. **Armour becomes turn-scoped block.** No stat permanently reduces damage
   any more. `armor N` survives on the sheet with a new meaning: the man
   starts every one of his side's turns with N block — his guard, the shield
   he raises by habit. Block absorbs physical damage point for point and
   whatever is left when his side's turn comes round again is gone.
2. **Axes do not pierce block — they chew it.** Piercing is wrong with
   multiple attackers: block ignored by the axe would still stop everyone
   else, so the axeman would be wasted on any target his mates also hit.
   Instead every point of axe damage destroys TWO points of block, and
   **axes strike first** in the fight order, so the block-chewing lands
   while there is still block to chew and the swords behind hit flesh.
3. **The shieldman loses his half-damage rule.** Permanent halving is
   exactly the math this change removes. He becomes the block kit: the
   block-then-attack pattern with a high guard value, and his aura becomes
   shared block — when he plants the shield, his line-neighbors gain some
   too. True-damage volleys still go around block, so his counter-play
   keeps its teeth.
4. **Every unit follows a pattern, on BOTH sides.** Supersedes phase C's
   enemy-only wind-up ruling. Your own crew keeps its beats too; the
   telegraph layer becomes the rhythm layer, and placement/cards now play
   against time as well as space.
5. **The archer aims, then hits and weakens.** Two beats: aim locks the
   mark (a full turn of warning, no arrow), the shot looses both arrows and
   leaves the mark SUPPRESSED — he deals two-thirds of his damage, the lost
   third rounded up against him, until it wears off.
6. **The enemy captain's command replaces the tactic rotation every Nth
   turn**, whether he is fielded or waiting ashore — so the escalation
   cannot be locked out by a full board. The first command: every defender
   on the board gains a permanent, stacking +1 attack damage. Unbounded
   escalation is the termination guarantee the closing rule started.
   Later captains carry different commands, so the command is scenario
   data, not engine code. (Whether the ordinary rotation itself should
   stay seeded-random or become a fixed cycle is still open.)
7. **Closing pins the dodger.** When a man steps because his column is
   empty (the shipped closing rule), the man he is closing toward is
   PINNED: no movement at all — not his own cards, not his captain's
   calls, not a rescue off the deck — friend and foe alike, until the
   stacks decay. The number grows with each repeat (1st pin 1 turn, 2nd
   +2, 3rd +3 …), so dodging buys turns at a rising price and can never
   be a permanent escape.

## The shipped rules

### Block

- `Character.block` is turn-scoped guard. At the start of a side's turn,
  every FIELDED man on that side has his block set to his `armor` value
  (not added — leftover block does not bank). Reserve men carry none;
  a man fielded mid-turn raises his guard at his side's next turn start.
- Physical damage — melee blows, heavy blows, cleave grazes, arrows (the
  snipe, the aimed double shot, the rail volley's arrows are a card effect
  and stay true) — is absorbed by block first, point for point; only the
  remainder wounds. Zero is a legal result: a fully blocked hit draws no
  blood (the old minimum-1 lives BEFORE block, on the raw damage).
- True damage (card volleys, thrown cargo, the enemy arrow_volley tactic)
  bypasses block entirely, exactly as it bypassed armor. Blocking is the
  answer to steel, never to the sky.
- Morale damage ignores block.
- The axe: each point of its damage destroys 2 block. What the block
  swallows is paid at that rate; the rest wounds normally. (Axe 4 into
  block 6: the block dies for 3 of the axe's points, the last point cuts.)
- Fight order: axemen swing first (among themselves by speed, then spawn
  order), then everyone else (same tiebreaks). Both sides.
- Deleted: armor subtraction in `damage_against`, the axe's old
  ignore-2-armor trait, the shieldman's +1-armor aura and half-damage
  rule, and the aura-denial. `armor` the stat remains, as guard.

### Patterns

- `Character.pattern` is a cycle of beats; `Character.beat` indexes it.
  Roles map to patterns at spawn:

  | role | pattern |
  |---|---|
  | berserker | attack, attack, **heavy** |
  | bow | **aim**, **shoot** |
  | shieldman | **guard**, attack |
  | everyone else | attack |

- A fielded man performs his current beat in his side's fight phase, then
  the beat advances — landed, blocked, wasted or walked (the closing step)
  alike. The rhythm marches; only the unfielded stand outside time. A man
  arriving on deck starts his pattern over (beat 0).
- **heavy**: the old wind-up blow — damage ×2, cleave graze ×2 — now on a
  fixed third beat instead of a ticking counter. Wasted whole on an empty
  column, as before.
- **aim** (in the second line, with the bow): locks the mark — the weakest
  fielded opponent — and looses nothing. The mark is public. **shoot**:
  both arrows at the mark, then SUPPRESSED. A mark that died, routed or
  left the field wastes the shot whole, as before. An archer standing in
  the front line is just a fighter: any beat is a melee swing there, but
  the beats still advance.
- **guard**: no swing — he plants the shield and gains his `armor` in
  block AGAIN (on top of the turn-start guard), and his line-neighbors
  gain `SHIELD_AURA_BLOCK` each. Only the shieldman's guard beat shares;
  the aura is his kit, not the beat's.
- SUPPRESSED (`Character.suppressed`, in his side's turn-ends): every
  packet of damage he deals loses a third, rounded up against him
  (dealt = raw − ceil(raw/3), minimum 1). Applied at `SUPPRESS_TURNS` per
  shot; decays 1 at the end of his side's turn; re-application refreshes,
  never stacks.
- The forecast previews each man's CURRENT beat — it is what he will do
  next, since beats advance on action. Defender block is spent against the
  predicted physical damage in prediction order, so the bill shown is
  blood, not steel-on-shield.
- Deleted: `Character.windup`, `WINDUP_PERIOD`, `_advance_windups`,
  enemy-only wind-up roles. `state.archer_marks` stays and now serves both
  sides' bows.

### The captain's command

- Scenario data: `"captain_command": {"name": ..., "period": N, "effect":
  "blood_rage", "amount": 1}`. No entry, no command (bare test scenarios).
- Every Nth enemy turn (turn % N == 0), the telegraphed tactic for that
  turn IS the command — it replaces whatever the rotation would have
  picked, and it is telegraphed a turn ahead like any tactic. The captain
  speaks from wherever he stands: fielded, ashore, it makes no difference;
  only his death silences him (and his death already ends the battle).
- `blood_rage`: every fielded defender gains a permanent +1 to attack
  damage (`Character.rage`). It stacks with every repetition and never
  fades. Men still below decks miss the speech — they carry only the
  rages bellowed while they stood on the board.
- Both anchor scenarios carry the command at `period` 4.

### The pin

- When a man takes the closing step (his column was empty, he walks
  toward the fighting), the man he is walking toward — the melee target
  of the column he is closing on — is pinned: `pin_count += 1`,
  `pinned += pin_count`. First pin 1 turn, second +2 more, third +3.
- While `pinned > 0` the man CANNOT MOVE, by any hand: formation movement
  verbs refuse him (slides, advances, retirements, swaps, the group
  calls — a pinned man stands while his line shifts around him, and his
  column does not trade on fresh-men-forward), card movement is refused
  at the gate (riders, Trade Places, Taunt, Drive Him Back, Break the
  Line, Get Back!), he takes no closing steps of his own, and nobody
  drags him home — the reaction save cannot reach a pinned man, and he
  dies where he stands. Death and rout still remove him; the grave is
  not a move.
- Decay: 1 stack at the end of his side's turn. `pin_count` never decays
  within the battle: the price of the next dodge keeps growing.
- Legality queries (`can_play`, `swap_partners`, `taunt_targets`,
  `shove_directions`, rider movers) all exclude pinned men, so the UI
  never lights an illegal pick and `can_play`-driven bots stay honest.

## What this does NOT touch (deliberately)

- Card effects `SHIELD_WALL` (−2 soften + volley cover) and
  `PLAYER_ARMOR_BONUS` (the maneuver's battle-long soften) survive as-is:
  they are already turn-scoped or battle-scoped side-wide effects, not
  permanent per-man reduction. Converting them to block grants is card
  design, and belongs to the retune conversation.
- Prices, HP, guard values, `period`, `SHIELD_AURA_BLOCK`,
  `SUPPRESS_TURNS` are first guesses. The retune (next slice) owns them;
  the sims in each chunk's commit message are the paper trail.
- The ordinary tactic rotation stays seeded-random for now (open ruling).
