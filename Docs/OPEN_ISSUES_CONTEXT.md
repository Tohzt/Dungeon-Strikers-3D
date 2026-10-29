# Open Issues — Context

Known problems and unfinished work, gathered on 2026-10-05 from a code
review plus the leftovers of `TODO.txt` and `CHARACTER_MODELS_CONTEXT.md`
(both deleted once everything still open was moved here). Most important
first. Delete an entry once it's done, and this file once it's empty.

Code is referenced by file and function rather than line, since lines move.

---

## 1. Hit damage is only sanity-capped (only matters for public play)

Damage is decided on the attacker's machine and applied by the victim's
owner (or the server, for bosses, minions, skeletons and towers), which
keeps combat responsive. Received hits now go through
`Combat.vetted_damage` (0 to `MAX_REMOTE_HIT_DAMAGE` × the attacker's
damage perk stat), attacker credit through `Game3D.vetted_attacker` (the
sender must own the named player, or be the server), and
`Weapon3D._decide_equip` checks reach. The damage cap is deliberately
loose, so a modified client can still hit much harder than its weapon
allows. Before public matchmaking, consider a tighter cap from the
attacker's held weapons and perks, and a reach check on hits (thrown
weapons, arrows and bombs make that harder).

## 2. Animation gaps (from the character-models work)

- **Left-hand throws look weak.** `General/Throw` only moves the right arm,
  so the left hand throws with half of the dual-wield chop
  (`PlayerVisual3D.OFFHAND_THROW_CLIP`). Mirroring the throw clip offline
  (Blender) would fix it; Godot can't mirror animations at runtime.

## 3. Carrying the ball (carry meter)

Carrying was shelved on 2026-10-07 (last in `a0959a5`) and came back on
2026-10-12 with a carry meter in place of the old boost bar:
- `Ball3D`: `holder`, `request_grab`/`request_throw` and their server RPCs
  (grab cooldown, reach slack). A held ball has no collision, so it can't
  be carried into a net: it has to be thrown in. A skull can be walked
  onto the altar.
- `PlayerClass3D.carry` (blue HUD bar, 0-100): Interact grabs a ball in
  reach (needs `CARRY_MIN_TO_GRAB`). Carrying drains it (3s from full);
  Throw charges and throws along the aim; Shoot (E / LT) charges and
  shoots it straight at `Game3D.shot_target` (the goal attacked, or your
  altar with a skull). Carrying, you can lock on to
  teammates: Shoot then passes (`Ball3D.Shot.PASS`, the first teammate it
  reaches catches it) or, locked on to an enemy, attacks (`Shot.ATTACK`,
  8-20 damage by charge to the first enemy hit); it's tossed forward when the meter empties,
  and knocked loose by a hit, a roll, a stagger or a knockdown.
- Bots grab the ball, run it at the goal (around to the front of it),
  shoot inside `SHOT_RANGE` with a clear line, pass up the field or throw
  it on before the meter runs out, tackle enemy carriers and escort
  teammates. In 4-bot simulations on Pitch they scored about 3 goals per
  5 minutes, where before they scored none.
- Still to do: a carry pose, carrying-specific perks (the old "Sure Hands"
  / "Pickpocket"), and a playtest of the meter numbers.

## 4. Unfinished features (from the old TODO list)

- **Training room and attack dummy.** The title screen has a Training
  button (disabled for now, `MainMenu`'s `%TrainingButton`). It should open a
  solo room with a dummy to hit, where players can try out characters,
  weapons and perks. `GameTools3D` in `Game/tools.gd` has the old test-room
  builder, though no map uses it now.

## 5. Playtesting still needed

- Consumable cards (`PlayerClass3D.consumables`, two slots, since
  2026-10-29; replaced the one-slot item slot of 2026-10-27): shop
  bombs/flasks and item boxes' bombs, flasks and giant weapons go in a free
  slot (full slots grey out shop throwables, and item boxes stop rolling
  them). Tapping Use Item (G / D-pad Down) uses the first; holding it opens
  the card hand (`CardHand`): perks fanned at the bottom, the two slots to
  the right; mouse hovers to pick and clicks to use, a pad flicks the right
  stick and presses RB / Interact. Attacks and Interact are muted while it's
  open. Cards are kept through death; bots use giant weapons at once and
  throwables once they have a target. Check the hold time
  (`PlayerInputHandler3D.HAND_HOLD_TIME`), the pad controls, and how the
  hands sit with 2-4 local players.
- Swing feel and time-to-kill since the animated-attack rework (players
  have 250 HP, a sword hit is 40, `kills_to_win` is 5).
- The per-weapon ball interactions (`WeaponBehavior3D` `ball_*` exports)
  have only been tried offline; check them online.
- Advanced controls' hold-to-throw for weapons wasn't covered by the
  scripted test after the player refactor; try it in game.

## Testing tips

There are no automated tests, but the game runs headless well:

- `godot --headless --path . res://Game/Maps/Pitch.tscn --quit-after 300`
  loads a map and runs 300 frames; any `SCRIPT ERROR` lines mean trouble.
- After adding a new `class_name`, run `godot --headless --path . --import`
  once so Godot registers it, or scripts that use it fail to parse.
- A small temporary scene that seats bots (`Players.add_bot()`) and then
  changes to a map, run with `--fixed-fps 60`, gives a repeatable bot
  match: compare counts like kills and swing frames before and after a
  change. With `seed()` set, the same code gives identical results.
- For online, run a server (`-- --server`) and two clients
  (`-- --address=127.0.0.1`) headless; a temporary client scene can call
  `Net.host()` / `Net.join()` / `Net.start_match()` and script the players.
- Never save scenes from `godot --script`: autoloads aren't loaded there,
  and saved scenes lose their scripts.
