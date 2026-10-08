class_name MatchMap extends RefCounted
## The levels a match can be played on, and what each one supports. The
## host picks one in the lobby (Players.map), along with the boss drop
## (Players.boss_drop), which some levels can't host: a ball needs goals.

enum Map {
	ARENA,    ## The open soccer field: goals and altars for up to 4 teams
	DUNGEON,  ## Two mirrored bases around a central arena; altars, no goals
	RACE,     ## Up to 4 teams race through a dungeon to an altar (RaceGame3D)
}

## In the order the lobby's Map button cycles through them.
const MAPS: Array[Map] = [Map.DUNGEON, Map.ARENA, Map.RACE]
const SCENES: Dictionary[Map, String] = {
	Map.ARENA: "res://3D/Game/Game3D.tscn",
	Map.DUNGEON: "res://3D/Game/DungeonArena.tscn",
	Map.RACE: "res://3D/Game/RaceDungeon.tscn",
}
const NAMES: Dictionary[Map, String] = {
	Map.ARENA: "Arena",
	Map.DUNGEON: "Dungeon",
	Map.RACE: "Race",
}
## Most teams each level is laid out for (matches Game3D.max_team_count).
const MAX_TEAMS: Dictionary[Map, int] = {
	Map.ARENA: 4,
	Map.DUNGEON: 2,
	Map.RACE: 4,
}
## Levels with goals to score a ball in.
const HAS_GOALS: Array[Map] = [Map.ARENA]
## Levels whose bosses drop nothing (they unlock doors), so any drop setting fits.
const NO_DROPS: Array[Map] = [Map.RACE]

## Drops the host can pick, in the order the lobby's Boss button cycles.
## Each will get its own boss later; for now the one boss drops any of them.
const DROPS: Array[BossDrop.Kind] = [BossDrop.Kind.SKULL, BossDrop.Kind.BALL]
const DROP_NAMES: Dictionary[BossDrop.Kind, String] = {
	BossDrop.Kind.NONE: "None",
	BossDrop.Kind.SKULL: "Skull",
	BossDrop.Kind.BALL: "Soccer Ball",
}


static func scene_of(map: Map) -> String:
	return SCENES[map]


static func name_of(map: Map) -> String:
	return NAMES[map]


static func drop_name(kind: BossDrop.Kind) -> String:
	return DROP_NAMES.get(kind, "?")


static func max_teams(map: Map) -> int:
	return MAX_TEAMS[map]


## Whether `map` can host a match of `team_count` teams where bosses drop `drop`.
static func fits(map: Map, team_count: int, drop: BossDrop.Kind) -> bool:
	return team_count <= MAX_TEAMS[map] \
		and (drop != BossDrop.Kind.BALL or HAS_GOALS.has(map) or NO_DROPS.has(map))


## The first map (in MAPS order) that fits, or ARENA if none does.
static func first_fitting(team_count: int, drop: BossDrop.Kind) -> Map:
	for map: Map in MAPS:
		if fits(map, team_count, drop):
			return map
	return Map.ARENA
