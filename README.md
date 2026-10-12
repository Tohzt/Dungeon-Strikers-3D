# Dungeon Strikers 3D

A team PvPvE arena brawler made in Godot 4.7. Teams fight a boss, scramble
for what it drops (a skull to knock home to their altar, or a ball to score
in a goal), pick perks at their altar between rounds, and race to a set
number of player kills. Up to four players play locally (with bots to fill
seats) or online.

## Running

Open `project.godot` in Godot 4.7 and run it; the main menu offers single
player, local multiplayer and online play.

### Online

Online play goes through a dedicated server (`net.gd`). To test against a
server on your own machine:

```sh
godot --headless --path . -- --server          # the server
godot --path . -- --address=127.0.0.1          # each game copy
```

One copy hosts with a code, the others join with it. Bump
`PROTOCOL_VERSION` in `net.gd` whenever RPCs or synced properties change.

`deploy_server.sh` uploads the project to the droplet and restarts its
server (it needs a `droplet` host in `~/.ssh/config`).

Known problems and unfinished work are tracked in `OPEN_ISSUES_CONTEXT.md`.

## Layout

- `global.gd`, `players.gd`, `net.gd`: autoloads (shared helpers, local
  seats and devices, online sessions). `net_motion.gd` and
  `net_interpolator.gd` sync moving objects.
- `3D/Game/`: the match (`game_3d.gd`), maps and cameras.
- `3D/player_3d/`: the player. `character_body_3d.gd` is the player itself;
  `player_arm_3d.gd` holds each arm's state, `player_combo_3d.gd` plays out
  dual-wield specials, and `player_visual_3d.gd` drives the model and
  animations.
- `3D/Items/`, `3D/Weapons/`: weapons, the ball and skull, stands, chests,
  altars and pickups.
- `3D/Entities/`: the slime boss and minions, input handlers (player and
  bot).
- `3D/Perks/`, `3D/HUD/`: rogue-lite perks and the in-match HUD.
- `Menus/`: main and pause menus.
- `Game/Dungeon/`: generators for the dungeon arena and its GridMap
  palettes. `build_dungeon_arena.gd` overwrites `DungeonArena.tscn` (see its
  header for how to run it); it needs the autoloads, so `godot --script`
  won't work.
