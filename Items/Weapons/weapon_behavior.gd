class_name WeaponBehavior3D extends Node
## How hard a weapon hits players and the ball (see Weapon3D.Behavior).

@export_category("Core")
@export var base_damage: float = 40.0  # Per hit (players have 250 HP); thrown hits do a bit more
@export var knockback_force: float = 10.0  # Shove speed given to whoever gets hit
## What its hits are made of, for how they look (see Vfx.hit).
@export var damage_type: DamageType.Kind = DamageType.Kind.SLASH

@export_category("Ball")
## What this weapon does to the ball when it hits it (swung or thrown), so
## each weapon has its own way of playing it. The sword is the baseline.
## How hard it sends the ball, on top of the usual shove from knockback_force.
@export var ball_power: float = 1.0
## Upward share of the hit: 0 sends it along the ground, above 1 lobs it high.
@export var ball_lift: float = 0.3
## Sets the ball's velocity instead of adding to it, so it goes exactly where
## it's aimed whatever it was doing (a pass).
@export var ball_exact: bool = false
## Sideways swerve (m/s^2) after a swing hits it, hooking back against the
## way the blade was moving. 0 = flies straight.
@export var ball_curve: float = 0.0
## Seconds the ball burns after this hits it (see Ball3D.ignite).
@export var ball_ignite_time: float = 0.0

## Utility: get world damage value (base + any dynamic mods you add later)
func get_damage() -> float:
	return base_damage


## This weapon hit `ball`, travelling along `dir` with the usual shove
## `strength` (knockback_force, scaled by swing speed). `blade_travel` is how
## the blade was moving (zero for a throw), for curving shots.
func hit_ball(ball: Ball3D, dir: Vector3, blade_travel: Vector3, strength: float, attacker: Node3D) -> void:
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	var speed: float = strength * Combat.OBJECT_IMPULSE_RATIO * ball_power / ball.mass
	if attacker is PlayerClass3D:
		speed *= attacker.perk_stat(&"ball_power")
	var velocity: Vector3 = dir * speed + Vector3.UP * speed * ball_lift
	var curve := Vector3.ZERO
	var side: Vector3 = blade_travel - dir * blade_travel.dot(dir)
	side.y = 0.0
	if ball_curve > 0.0 and side.length() > 0.5:
		curve = -side.normalized() * ball_curve
	ball.receive_weapon_hit(velocity, ball_exact, curve, ball_ignite_time, attacker)
