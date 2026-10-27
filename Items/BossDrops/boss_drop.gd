class_name BossDrop extends RefCounted
## What a boss leaves behind when it's beaten (see Boss3D.drop). Each kind
## is a Ball3D (or subclass) that Game3D spawns into play.

enum Kind {
	NONE,   ## Drops nothing
	BALL,   ## The soccer ball: score it in a goal (see Goal3D)
	SKULL,  ## Knock it home to your altar for a reward (see Skull3D)
	BOMB,   ## Knock it into the enemy goal before it goes off (see Bomb3D)
}

## The scene each kind spawns. BALL uses Game3D.ball_scene instead, so a
## level can swap its ball.
const SCENES: Dictionary[Kind, String] = {
	Kind.BALL: "res://Entities/Ball/ball_3d.tscn",
	Kind.SKULL: "res://Items/BossDrops/skull_3d.tscn",
	Kind.BOMB: "res://Items/BossDrops/bomb_3d.tscn",
}
## Just the looks of each kind, shown floating inside the boss until it drops.
const MODELS: Dictionary[Kind, String] = {
	Kind.SKULL: "res://Items/BossDrops/skull_model.tscn",
	Kind.BOMB: "res://Items/BossDrops/bomb_model.tscn",
}


static func scene_of(kind: Kind) -> PackedScene:
	return load(SCENES[kind]) if SCENES.has(kind) else null


static func model_of(kind: Kind) -> PackedScene:
	return load(MODELS[kind]) if MODELS.has(kind) else null
