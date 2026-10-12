class_name WeaponMove3D extends Resource
## A weapon's light attack (a tap of its button) or heavy attack (held to
## charge, let go once fully charged). See PlayerClass3D._start_move.
##
## It swings like a normal attack (or plays `combo`'s beats), and each
## strike sends out `waves` (see AttackWave3D) so it reaches further than
## the blade. A move can also do something more than swing: throw the
## weapon out as a boomerang, send it circling the wielder, dash forward,
## or fire a big shot.

enum Action {
	NONE,  ## Just the swing and its waves
	BOOMERANG,  ## The weapon flies out along the aim and comes back
	ORBIT,  ## The weapon (both, dual wielding) circles the wielder and comes back
	DASH,  ## The wielder dashes along the aim
	SHOT,  ## A ranged weapon fires one big shot (see CrossbowClass3D.fire_heavy)
}

## Seconds of holding the heavy button to fully charge
## a heavy. Unused for a light.
@export var charge_time: float = 0.6
## Beats to play (MAIN-hand ones, see WeaponCombo3D). Empty = one strike.
@export var combo: WeaponCombo3D
## The clip a single strike plays, and that a charge winds back with.
## Empty = the weapon's own swing clip.
@export var clip: StringName = &""
## Whether the weapon swings (or fires) as usual on each strike: its blade
## can hit, a ranged weapon fires its bolt. Off = only the waves and the action hit.
@export var swings: bool = true
## Times the weapon's swing_duration.
@export var duration_scale: float = 1.0
## Times the step forward a swing takes. 0 = stand still.
@export var lunge_scale: float = 1.0
## Sent out on each strike.
@export var waves: Array[AttackWaveSpec3D] = []
## Played as it strikes (an Sfx.SOUNDS id), on top of the swing. Empty = none.
@export var sound: StringName = &""
## Shakes the camera of everyone near where it strikes (see CameraShake). 0 = none.
@export var shake: float = 0.0
## Shown as it strikes (a Vfx.EFFECTS id), along the aim. Empty = none.
@export var vfx: StringName = &""

@export_group("Action")
@export var action: Action = Action.NONE
## BOOMERANG / ORBIT: times the weapon's base damage and knockback, per hit.
@export var action_damage_scale: float = 1.0
@export var action_knockback_scale: float = 1.0
## BOOMERANG: how far out it flies (m) and how fast (m/s).
@export var throw_reach: float = 10.0
@export var throw_speed: float = 20.0
## ORBIT: how far out it circles (m), for how long (s), and how many times round.
@export var orbit_radius: float = 3.0
@export var orbit_time: float = 1.0
@export var orbit_turns: float = 2.0
## DASH: how fast (m/s) and for how long (s).
@export var dash_speed: float = 22.0
@export var dash_time: float = 0.25
## SHOT: the shot's size, damage and speed, times a normal shot's; and
## whether it flies through whoever it hits.
@export var shot_scale: float = 2.5
@export var shot_damage_scale: float = 2.5
@export var shot_speed_scale: float = 1.3
@export var shot_pierce: bool = true


## The wave held while this charges (see AttackWaveSpec3D.held_while_charging), if any.
func held_wave() -> AttackWaveSpec3D:
	for wave: AttackWaveSpec3D in waves:
		if wave.held_while_charging:
			return wave
	return null


## The clip a charge winds back with, for a weapon whose own is `fallback`.
func charge_clip(fallback: StringName) -> StringName:
	if clip != &"":
		return clip
	if combo and not combo.steps.is_empty() and combo.steps[0].main_clip != &"":
		return combo.steps[0].main_clip
	return fallback
