class_name SlimeElement
## What a slime boss is made of (see Boss3D.element), and its minions with
## it: its name, its color, what its hits do to players (see afflict), how
## its bursts look (see show_burst), what it leaves behind and the spell it
## casts (see Boss3D._cast). Which one comes out is down to chance (see
## pick), the same on every machine.

enum Kind {
	RANDOM = -1,  ## Rolled when it's made (see pick)
	POISON,     ## Lobs globs that leave poison puddles; spits extra minions
	FIRE,       ## Spews fireballs that blow up and leave fire behind
	LIGHTNING,  ## Calls lightning down on everyone; quick, and its strikes and lunge knock players down
	FROST,      ## Freezes the ground around it in a big nova; its hits chill
	VOID,       ## Sinks into a portal and drops out of another onto someone
}

## The ones pick() deals from.
const ROLLABLE: Array[Kind] = [Kind.POISON, Kind.FIRE, Kind.LIGHTNING, Kind.FROST, Kind.VOID]

const NAMES: Dictionary[Kind, String] = {
	Kind.POISON: "Gelatinous Colossus",
	Kind.FIRE: "Molten Monarch",
	Kind.LIGHTNING: "Voltaic Ooze",
	Kind.FROST: "Glacial Glob",
	Kind.VOID: "Void Jelly",
}
## Its body (see-through).
const BODY_COLORS: Dictionary[Kind, Color] = {
	Kind.POISON: Color(0.36, 0.51, 0.23, 0.7),
	Kind.FIRE: Color(0.95, 0.32, 0.08, 0.75),
	Kind.LIGHTNING: Color(0.95, 0.85, 0.2, 0.7),
	Kind.FROST: Color(0.55, 0.85, 1.0, 0.65),
	Kind.VOID: Color(0.42, 0.15, 0.75, 0.7),
}
## Its magic: telegraphs, globs, puddles, effects and announcements.
const COLORS: Dictionary[Kind, Color] = {
	Kind.POISON: Color(0.55, 0.95, 0.2),
	Kind.FIRE: Color(1.0, 0.5, 0.1),
	Kind.LIGHTNING: Color(1.0, 0.95, 0.5),
	Kind.FROST: Color(0.6, 0.9, 1.0),
	Kind.VOID: Color(0.75, 0.35, 1.0),
}
## What it wears all fight: [Vfx.EFFECTS id (HELD), size, offset from its feet].
const AURAS: Dictionary[Kind, Array] = {
	Kind.POISON: [&"poisoned", 4.0, Vector3(0.0, 2.0, 0.0)],
	Kind.FIRE: [&"burning", 3.0, Vector3.ZERO],
	Kind.LIGHTNING: [&"lightning_ball", 2.0, Vector3(0.0, 5.0, 0.0)],
	Kind.FROST: [&"frozen", 4.5, Vector3(0.0, 2.0, 0.0)],
	Kind.VOID: [&"dark_ball", 2.0, Vector3(0.0, 5.0, 0.0)],
}
## How its stomps, bursts and globs go off: [Vfx.EFFECTS id, size per meter
## of reach, tinted in its color?].
const BURSTS: Dictionary[Kind, Array] = {
	Kind.POISON: [&"smoke", 1.0, true],
	Kind.FIRE: [&"explosion", 1.0, false],
	Kind.LIGHTNING: [&"lightning", 2.0, false],
	Kind.FROST: [&"shatter", 1.0, true],
	Kind.VOID: [&"dark_blast", 2.0, false],
}
## The puddle its globs and stomps leave (see SlimePool3D): [Vfx.EFFECTS id
## (HELD) shown in it, size per meter of radius]. None for the rest.
const POOLS: Dictionary[Kind, Array] = {
	Kind.POISON: [&"poisoned", 0.7],
	Kind.FIRE: [&"burning", 0.5],
}
## The bomb a bomb it drops (or swallows) turns into; any for the rest.
const BOMB_TYPES: Dictionary[Kind, Bomb3D.Type] = {
	Kind.POISON: Bomb3D.Type.POISON,
	Kind.FIRE: Bomb3D.Type.FIRE,
	Kind.FROST: Bomb3D.Type.ICE,
}
## How long its sting lasts at full strength.
const POISON_TIME := 4.0
const CHILL_TIME := 2.5
## Lightning's hits knock players down this much (see Combat.strike).
const SHOCK_KNOCK_DOWN := 1.0


## The element for the boss named `boss_name`, the same on every machine
## (from the match's seed, see Players.match_seed). Bosses that come one
## after another ("Boss_1", "Boss_2"...) are dealt from a shuffled deck, so
## every element shows up before any comes back; any other boss is a coin
## toss of its own.
static func pick(boss_name: String) -> Kind:
	var number: String = boss_name.trim_prefix("Boss_")
	if number != boss_name and number.is_valid_int() and number.to_int() > 0:
		var rng := RandomNumberGenerator.new()
		var deck: Array[Kind] = ROLLABLE.duplicate()
		var turn: int = number.to_int() - 1
		# A fresh shuffle each time round the deck
		rng.seed = hash("%d/%d" % [Players.match_seed, floori(float(turn) / deck.size())])
		for i in range(deck.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var swap: Kind = deck[i]
			deck[i] = deck[j]
			deck[j] = swap
		return deck[turn % deck.size()]
	return ROLLABLE[absi(hash("%d/%s" % [Players.match_seed, boss_name])) % ROLLABLE.size()]


## What being hit by `kind` (a boss, its minion, a glob or a puddle) does to
## `player` besides the hit: poison, burn or chill, for `strength` times as
## long as usual. At 2 or more frost freezes them solid.
static func afflict(player: PlayerClass3D, kind: Kind, strength: float = 1.0) -> void:
	if player.is_dead():
		return
	match kind:
		Kind.POISON:
			player.status.apply(PlayerStatus3D.Kind.POISONED, POISON_TIME * strength)
		Kind.FIRE:
			player.status.apply(PlayerStatus3D.Kind.BURNING, PlayerStatus3D.BURN_TIME * strength)
		Kind.FROST:
			if strength >= 2.0:
				player.status.apply(PlayerStatus3D.Kind.FROZEN, PlayerStatus3D.FREEZE_TIME)
			else:
				player.status.apply(PlayerStatus3D.Kind.CHILLED, CHILL_TIME * strength)


## How much `kind`'s hits knock players down (see Combat.strike).
static func knock_down(kind: Kind) -> float:
	return SHOCK_KNOCK_DOWN if kind == Kind.LIGHTNING else 0.0


## On this machine: `kind` going off at `at` (on the ground), reaching
## `reach` meters.
static func show_burst(kind: Kind, at: Vector3, reach: float) -> void:
	var look: Array = BURSTS[kind]
	var tint: Color = COLORS[kind] if look[2] else Color.TRANSPARENT
	Vfx.play(look[0], at, Vector3.FORWARD, false, reach * look[1], tint)
