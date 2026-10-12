class_name AttackWaveSpec3D extends Resource
## One wave a WeaponMove3D sends out when it strikes (see AttackWave3D): a
## short-lived hitbox that travels away from the wielder, so a swing reaches
## further than the blade. Light swings send a short one, heavies a big one.

enum Shape {
	ARC,  ## A crescent slash, flying along its direction
	THRUST,  ## A narrow spike, for stabs
	ORB,  ## A ball of energy
	SHOCKWAVE,  ## A crescent rolling along the ground
	RING,  ## A ring spreading out all round where it started
}
@export var shape: Shape = Shape.ARC
## Across its direction of travel (the ring's starting radius), meters.
@export var width: float = 2.4
## Along its direction of travel (the ring's band), meters.
@export var length: float = 0.8
## Tall, meters. The hitbox is centered on the wielder's middle (a
## shockwave's sits on the ground).
@export var height: float = 1.6
## Meters per second (a ring: how fast it spreads).
@export var speed: float = 16.0
## How far it goes before it's gone (a ring: its final radius), meters.
@export var reach: float = 3.0
## Starts this far ahead of the wielder, meters.
@export var start_offset: float = 0.6
## Turned this far (degrees) off the aim, e.g. for a spread.
@export var angle_offset: float = 0.0
## Rolled about its direction (degrees): 0 a flat, horizontal slash, 90 a
## vertical chop, in between a diagonal.
@export var tilt: float = 0.0
## Seconds after the strike before it sets off.
@export var delay: float = 0.0
## Its size by the end of its flight, times its starting size.
@export var grow: float = 1.0
## Rides along with the wielder instead of flying off (a dash's hitbox); it
## lasts reach / speed seconds.
@export var follow: bool = false

@export_group("Hits")
## Times the weapon's base damage and knockback.
@export var damage_scale: float = 0.7
@export var knockback_scale: float = 1.0
## Upward shove, m/s.
@export var pop: float = 3.0
## Keeps going through whoever it hits. Otherwise the first player or
## monster it hits stops it.
@export var pierce: bool = false
## Carries on through walls instead of stopping at them.
@export var through_walls: bool = false
## Can hit the same body again after this many seconds (0 = once each).
@export var rehit_time: float = 0.0
## Times the knockback it hits the ball with.
@export var ball_scale: float = 1.0

@export_group("Burst")
## An ORB only: over 0, it hits nothing on its way. It bursts on touching
## anyone (or the ball), on reaching a wall, or once it's flown its reach
## (so reach / speed is its fuse), hitting everything within this many
## meters once.
@export var burst_radius: float = 0.0
## Grows in front of the wielder while their heavy charges, and is what
## flies off when it strikes (see PlayerClass3D._show_charging).
@export var held_while_charging: bool = false

@export_group("Look")
## Its own look's color, and what a `look` or `end_look` is tinted.
@export var color: Color = Color(0.85, 0.95, 1.0, 0.85)
## Shown as it instead of its own look: a HELD Vfx.EFFECTS id (an orb, a
## fireball), `width` across. Empty = its own look.
@export var look: StringName = &""
## Shown on the ground where it ends (a burst: burst_radius across, else
## `width`): a Vfx.EFFECTS id. Empty = none.
@export var end_look: StringName = &""
