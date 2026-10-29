class_name MatchMap extends RefCounted
## The levels a match can be played on, and what each one supports. The
## host picks one in the lobby (Players.map), along with the boss drop
## (Players.boss_drop), which some levels can't host: a bomb needs goals.
## On the pitch it's what kicks off instead (a ball, or a bomb).

enum Map {
	PITCH,    ## Soccer with hazards and a penned boss; first to N goals (PitchGame3D)
}

## In the order the lobby's Map button cycles through them. Only the pitch
## for now; the lobby hides its Map button while there's just one.
const MAPS: Array[Map] = [Map.PITCH]
const SCENES: Dictionary[Map, String] = {
	Map.PITCH: "res://Game/Maps/Pitch.tscn",
}
const NAMES: Dictionary[Map, String] = {
	Map.PITCH: "Pitch",
}
## Most teams each level is laid out for (matches Game3D.max_team_count).
const MAX_TEAMS: Dictionary[Map, int] = {
	Map.PITCH: 2,
}
## Levels with goals to score a ball in.
const HAS_GOALS: Array[Map] = [Map.PITCH]
## Levels whose bosses drop nothing (they swallow the ball), so any drop
## setting fits.
const NO_DROPS: Array[Map] = [Map.PITCH]

## Drops the host can pick, in the order the lobby's Ball button cycles.
## Each will get its own boss later; for now the one boss drops any of them.
## The first is the default. Only the bomb is offered for now: the ball and
## skull still work, so add BossDrop.Kind.BALL / SKULL back here to offer
## them (the Ball button shows once there's more than one).
const DROPS: Array[BossDrop.Kind] = [BossDrop.Kind.BOMB]
## Whether a ball needs a map with goals (see fits). Off: every map plays
## with the ball.
const BALL_NEEDS_GOALS := false
const DROP_NAMES: Dictionary[BossDrop.Kind, String] = {
	BossDrop.Kind.NONE: "None",
	BossDrop.Kind.SKULL: "Skull",
	BossDrop.Kind.BALL: "Soccer Ball",
	BossDrop.Kind.BOMB: "Bomb",
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
		and (not BALL_NEEDS_GOALS or drop != BossDrop.Kind.BALL or HAS_GOALS.has(map) or NO_DROPS.has(map)) \
		and (drop != BossDrop.Kind.BOMB or HAS_GOALS.has(map))


## The first map (in MAPS order) that fits, or the first map if none does.
static func first_fitting(team_count: int, drop: BossDrop.Kind) -> Map:
	for map: Map in MAPS:
		if fits(map, team_count, drop):
			return map
	return MAPS[0] as Map
