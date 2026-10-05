class_name BossDrop extends RefCounted
## What a boss leaves behind when it's beaten (see Boss3D.drop). Each kind
## is a carryable Ball3D (or subclass) that Game3D spawns into play.

enum Kind {
	NONE,   ## Drops nothing
	BALL,   ## The soccer ball: score it in a goal (see Goal3D)
	SKULL,  ## Carry it home to your altar for a reward (see Skull3D)
}

## The scene each kind spawns. BALL uses Game3D.ball_scene instead, so a
## level can swap its ball.
const SCENES: Dictionary[Kind, String] = {
	Kind.BALL: "res://3D/ball_3d.tscn",
	Kind.SKULL: "res://3D/Items/BossDrops/skull_3d.tscn",
}
## Just the looks of each kind, shown floating inside the boss until it drops.
const MODELS: Dictionary[Kind, String] = {
	Kind.SKULL: "res://3D/Items/BossDrops/skull_model.tscn",
}


static func scene_of(kind: Kind) -> PackedScene:
	return load(SCENES[kind]) if SCENES.has(kind) else null


static func model_of(kind: Kind) -> PackedScene:
	return load(MODELS[kind]) if MODELS.has(kind) else null
