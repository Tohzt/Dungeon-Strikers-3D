# Open Issues — Context

Known problems and unfinished work, gathered on 2026-10-05 from a code
review plus the leftovers of `TODO.txt` and `CHARACTER_MODELS_CONTEXT.md`
(both deleted once everything still open was moved here). Most important
first. Delete an entry once it's done, and this file once it's empty.

Code is referenced by file and function rather than line, since lines move.

---

## 1. Online matches and the server can get stuck

The dedicated server runs one session at a time (`net.gd`), so anything
that stalls a match also blocks every other player from hosting.

- **One idle player stalls the round.** The intermission only ends once
  every player has picked a perk at their altar (`PerkDirector._apply_pick`
  → `_finish_intermission`), and there's no time limit. Someone who walks
  away holds up the next boss for everyone.
  *Fix idea:* an intermission timer that auto-picks a random card for
  anyone still holding cards (bots already do this via `auto_pick`, which
  is offline-only today).
- **The server stays locked after a match.** `Net.in_match` only resets in
  `Net._close_session`, which runs when the *last* player leaves. A player
  sitting on the win screen blocks every new host. *Fix idea:* after
  `_win`, return everyone to the lobby (or end the session) after a delay.
- **Idle connections hold slots forever.** A client that connects but never
  sends `_request_host`/`_request_join` keeps one of the
  `MAX_CONNECTIONS` (8) slots. *Fix idea:* on the server, disconnect peers
  that haven't joined a session within a few seconds of connecting.

## 2. Ball speed values look left over from the 2D version

`3D/ball_3d.gd`, top of the file: `max_ball_speed = 600`,
`min_velocity_for_knockback = 150`, and color thresholds at 30% / 60% of
the max (180 / 360). Real speeds are about 10–40 m/s (a full throw is an
impulse of 15 on a 0.5 kg ball ≈ 30 m/s). As a result:
- the ball never shoves players it hits (`_on_body_entered`), even though
  `PlayerClass3D.shove` exists for exactly that;
- the speed coloring barely moves off green;
- the speed cap never applies.

*Fix idea:* rescale to metres per second (e.g. max ≈ 40, knockback from
≈ 15) and playtest. This changes gameplay, so tune it by feel.

## 3. Test rooms are switched on in the real map

`3D/Game/DungeonArena.tscn` saves `testing_mode = true` on its Tools node
(`GameTools3D`), so the test rooms with a stand for every weapon are built
in real matches, including on the deployed server. Turn it off unless
that's intended.

## 4. Clients decide their own hits (only matters for public play)

Damage is decided on the attacker's machine and applied by the victim's
owner, which keeps combat responsive. The receiving side doesn't check
what it's sent, so a modified client could cheat:
- `PlayerClass3D._net_receive_hit` accepts any damage, from any peer, and
  doesn't check that the sender is the attacker it names (kill credit can
  be spoofed);
- `Boss3D._request_hit` accepts any damage (one-shot the boss for its perk
  hand);
- `Game3D._request_use_shield` doesn't check the team has a shield left;
- `Weapon3D._request_equip` has no distance check.

Related race: shields are spent by the victim's machine before the server
agrees, so two teammates on different machines can both be saved by one
shield.

Fine for friends joining with a code. Before public matchmaking, add cheap
server-side checks: clamp damage to what the attacker's weapon and perks
allow, require the sender to be the named attacker, and check reach.

## 5. Weapon renaming trap (latent)

`Weapon3D._set_props` renames every weapon to `Properties.weapon_name` in
`_ready`. Weapons are found by node name in RPCs, so two weapons with the
same name under `Weapons` get an auto-generated name that can differ
between the server and clients. Stands work around it by renaming after
`add_child` (`WeaponStand3D._hand_weapon`), and no map places weapons
directly today, so nothing is broken yet. If weapons are ever placed in a
map, give them unique names after `_ready`, or drop the rename.

## 6. Animation gaps (from the character-models work)

- **Left-hand throws look weak.** `General/Throw` only moves the right arm,
  so the left hand throws with half of the dual-wield chop
  (`PlayerVisual3D.OFFHAND_THROW_CLIP`). Mirroring the throw clip offline
  (Blender) would fix it; Godot can't mirror animations at runtime.

## 7. Shelved: carrying the ball

Picking up, carrying and throwing the ball (and skull) was removed on
2026-10-07, to come back as part of a future game mode. The last commit
with it is `a0959a5` ("fixings"). It covered:
- `Ball3D`: `holder`, grab/release and their server RPCs (with a grab
  cooldown and reach slack), and burning whoever held a lit ball.
- `PlayerClass3D`: `held_ball`, interact to grab, tap/hold or Throw to
  throw, a bonk swing while carrying, slower walking and no sprinting with
  it, fumbling it on a hard hit, and `receive_burn`; plus the `Hold` node
  in `player_3d.tscn` where it was carried.
- Bots that carried drops home and shot at goals; the skull delivered by
  walking it onto the altar.
- Perks "Sure Hands" (`ball_grip`) and "Pickpocket" (`ball_strip`).
- Still to do when it returns: a carry pose (the arms just rested), and a
  throw animation on the hand that threw it (always the right arm).

Now the ball and skull are only knocked around: by swings, punches, thrown
weapons and the boss. A skull counts as home once it's knocked onto the
altar of the team that last played it. Bots knock it along the level's
navigation (`BotInputHandler3D._go_hit_ball`).

## 8. Unfinished features (from the old TODO list)

- **Damage numbers.** `Global.display_damage_3d()` and
  `3D/HUD/display_damage_3d.tscn` exist, but nothing calls them. Hook into
  `Combat.strike` or the `receive_hit` functions (online, show it on the
  machine that applies the hit and on the attacker's).
- **Attack dummy.** A training target for trying weapons (the test rooms
  from `GameTools3D` would be a natural home).
- **Launch a sword from the bow.** Fire a held melee weapon as the bow's
  projectile.
- **Thrown or dropped weapons keep the wielder's color** for a few seconds,
  so it's clear whose throw is in the air (thrown weapons already ignore
  the thrower: see `Weapon3D.thrower`).

## 9. Playtesting still needed

- Swing feel and time-to-kill since the animated-attack rework (players
  have 250 HP, a sword hit is 40, `kills_to_win` is 5).
- The per-weapon ball interactions (`WeaponBehavior3D` `ball_*` exports)
  have only been tried offline; check them online.
- Advanced controls' hold-to-throw for weapons wasn't covered by the
  scripted test after the player refactor; try it in game.

## Testing tips

There are no automated tests, but the game runs headless well:

- `godot --headless --path . res://3D/Game/DungeonArena.tscn --quit-after 300`
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
