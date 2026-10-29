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

Online play goes through a dedicated server (`Autoloads/net.gd`). To test against a
server on your own machine:

```sh
godot --headless --path . -- --server          # the server
godot --path . -- --address=127.0.0.1          # each game copy
```

One copy hosts with a code, the others join with it. Bump
`PROTOCOL_VERSION` in `Autoloads/net.gd` whenever RPCs or synced properties change.

`Tools/deploy_server.sh` uploads the project to the droplet and restarts its
server (it needs a `droplet` host in `~/.ssh/config`).

Known problems and unfinished work are tracked in `Docs/OPEN_ISSUES_CONTEXT.md`.

## Layout

- `Autoloads/`: the autoloads: `global.gd` (shared helpers), `players.gd`
  (local seats and devices), `net.gd` (online sessions), `sfx.gd`, `vfx.gd`
  and `cursor.gd`.
- `Network/`: `net_motion.gd` and `net_interpolator.gd` sync moving objects.
- `Game/`: the match (`game_3d.gd`), map registry (`match_map.gd`), stats
  and editor test tools.
  - `Maps/`: the playable map scenes and their GridMap palettes (`GridMaps/`).
  - `Modes/`: mode logic (Pitch).
  - `Camera/`, `Level/` (doors, goals, spawns, torches…), `Hazards/`, `Towers/`.
- `Entities/`: everything that moves on its own.
  - `Player/`: the player. `character_body_3d.gd` is the player itself;
    `player_arm_3d.gd` holds each arm's state and `player_visual_3d.gd`
    drives the model and animations. Also the roster, names and seat data.
  - `Ball/`, `SlimeBoss/` (and its minions), `Skeleton/`, and `Input/`
    (player and bot input handlers).
- `Items/`: weapons (`Weapons/`: base scripts, `Moves/`, then one folder per
  weapon kind), altars/shops, chests, weapon stands, boss drops, coins,
  potions, throwables and other pickups.
- `Combat/`: hits, attack waves and elements. `Perks/`: rogue-lite perks.
- `UI/`: the in-match `HUD/`, `Menus/` (main, pause, character select) and
  shared `Controls/`.
- `Assets/`: third-party art, audio, VFX, fonts and the UI theme.
- `Tools/`: `deploy_server.sh` and the GridMap palette generator in
  `Dungeon/`.
- `Docs/`: design notes and open issues.
