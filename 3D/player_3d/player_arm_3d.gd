class_name PlayerArm3D extends RefCounted
## One of a player's arms: what its hand holds, the buttons working it, and
## where it is in a swing, shot or throw. PlayerClass3D has a left and a
## right one and runs the same code on both, so nothing here is written
## twice. The arm's share of PlayerClass3D.arm_anim is read off its timers
## (see action() and clip_index()).
##
## A swing's or throw's phase runs 0-1 winding up, 1-2 striking, 2-3
## recovering (see PlayerVisual3D.CLIP_KEYS).

## Fists and ball bonks take this long; a weapon swing takes its own
## swing_duration (see WeaponProperties3D). The first half is the strike,
## the second the recovery.
const SWIPE_DURATION := 0.25
## The phase a swing starts from: 1 (cocked) after a draw-back, else partway
## through the wind-up so the clip still shows some.
const QUICK_SWING_PHASE := 0.5
## A ranged shot plays its clip's strike and recovery over this long. It
## doesn't count as swinging (shots aren't committed, and aren't rate-limited
## by it), so it has its own timer.
const SHOT_ANIM_DURATION := 0.35
## After letting go of a throw, the arm follows through for this long.
const THROW_RELEASE_DURATION := 0.3
## Springing back off something solid takes this long.
const REBOUND_DURATION := 0.18
## A spinning combo beat takes this share of its time to get the arms out
## (and as long again to bring them back in at the end).
const SPIN_ARMS_OUT := 0.15
const WINDUP_LERP_SPEED := 6.0
## Below this, a winding-down arm counts as back at rest.
const WINDUP_SHOWN := 0.02


## A button working this arm (its attack, or simple controls' throw).
class Press:
	## Held this frame, and last frame.
	var held: bool = false
	var was_held: bool = false
	## When the current press began (seconds, see PlayerArm3D.now()).
	var press_time: float = 0.0
	## A release only acts if its press was seen by the attack logic. Presses
	## made while blocking are swallowed, so e.g. Alt+click (which is both
	## heavy and plain attack) doesn't throw the shield when the button comes
	## back up.
	var armed: bool = false

	func just_pressed() -> bool:
		return held and not was_held

	func just_released() -> bool:
		return was_held and not held

	## How long the current (or just-released) press has lasted.
	func held_for() -> float:
		return PlayerArm3D.now() - press_time


var is_left: bool
## What this hand holds (a two-handed weapon is the right arm's; see
## PlayerClass3D._holds_two_handed).
var weapon: Weapon3D = null
var attack := Press.new()
var throw := Press.new()

# The current swing: time left out of swing_duration, and the phase its
# clip started from (see QUICK_SWING_PHASE).
var swing_time: float = 0.0
var swing_duration: float = SWIPE_DURATION
var swing_from: float = QUICK_SWING_PHASE
## A combo beat's clip for this swing (empty = the weapon's own), and
## whether it's held out for a spin rather than swung through.
var swing_clip: StringName = &""
var swing_spin: bool = false
var shot_time: float = 0.0
var release_time: float = 0.0

# A heavy weapon's swing draws back before it strikes (its swing_windup), so
# it can be seen coming. Once drawn it's committed: it can't be rolled out of.
var draw_weapon: Weapon3D = null
var draw_time: float = 0.0
var draw_total: float = 0.0

# A swing that connected: the arm holds still for a moment (hit-stop), then,
# if it hit something solid, springs back from where it stopped (rebound)
# instead of carrying on through.
var hitstop: float = 0.0
## Time left springing back; 0 = following through.
var rebound: float = 0.0
## The phase where it stopped.
var rebound_from: float = 0.0

## An empty hand mid-punch hits whatever the fist passes through, once each.
var punching: bool = false
var punch_hits: Array[Node] = []

## Wound back for a throw, 0-1 (see update_windup).
var windup: float = 0.0


func _init(left: bool) -> void:
	is_left = left


## Clock for button presses, in seconds.
static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ===== SWINGING =====

## Mid-swing, or drawing one back.
func is_swinging() -> bool:
	return swing_time > 0.0 or is_drawing()


func is_drawing() -> bool:
	return draw_time > 0.0


## Drawing a heavy swing back, or in the strike half of any swing: no
## rolling out of it. The follow-through can be rolled out of.
func is_committed() -> bool:
	return is_drawing() or swing_time > swing_duration * 0.5


## Start a swing `duration` seconds long, its clip from phase `from`.
func begin_swing(duration: float, from: float = QUICK_SWING_PHASE) -> void:
	swing_time = duration
	swing_duration = duration
	swing_from = from
	swing_clip = &""
	swing_spin = false


## Draw `drawn` back for `time` seconds before it strikes.
func begin_draw(drawn: Weapon3D, time: float) -> void:
	draw_weapon = drawn
	draw_time = time
	draw_total = time


## Counts the draw-back down. Returns the weapon once it's fully drawn (time
## to strike), else null.
func tick_draw(delta: float) -> Weapon3D:
	if not is_drawing():
		return null
	draw_time = max(draw_time - delta, 0.0)
	if is_drawing():
		return null
	var drawn: Weapon3D = draw_weapon
	draw_weapon = null
	return drawn


## 0 at the start of the draw, 1 fully drawn back; quick at first, then
## held, so the pose reads.
func draw_progress() -> float:
	var p: float = 1.0 - draw_time / draw_total
	return 1.0 - (1.0 - p) * (1.0 - p)


## Counts the swing, shot and throw follow-through down. A swing holds still
## during a hit-stop, and while springing back off something solid it runs
## on the rebound instead.
func tick(delta: float) -> void:
	if hitstop > 0.0:
		hitstop -= delta  # Held where it connected
	elif rebound > 0.0:
		rebound = max(rebound - delta, 0.0)
		swing_time = rebound  # Still mid-swing until it's back at rest
	else:
		swing_time = max(swing_time - delta, 0.0)
	shot_time = max(shot_time - delta, 0.0)
	release_time = max(release_time - delta, 0.0)


## The swing met something: stop where it is for a moment and, off
## something solid, spring back from there afterwards instead of finishing.
func start_contact(solid: bool) -> void:
	if hitstop > 0.0 or rebound > 0.0:
		return  # Already stopped
	# A spin carries on round through whatever it hits
	if swing_spin:
		solid = false
	hitstop = Combat.HITSTOP if solid else Combat.HITSTOP_LIGHT
	if not solid:
		return
	rebound = REBOUND_DURATION
	rebound_from = swing_phase()
	# A fist springing back off someone shouldn't punch anyone on the way
	punching = false


## Stop any punch or swing from hitting anything more.
func cancel() -> void:
	punching = false
	draw_time = 0.0
	draw_weapon = null
	if weapon:
		weapon.cancel_swing()


## Where the swing is: from where it started (swing_from) through the strike
## over its first half, then recovering over the second.
func swing_phase() -> float:
	var t: float = clamp(1.0 - swing_time / swing_duration, 0.0, 1.0)
	if swing_spin:
		# Arms out at the end of the strike for the spin, then recover
		if t < SPIN_ARMS_OUT:
			return lerp(swing_from, 2.0, t / SPIN_ARMS_OUT)
		return 2.0 + maxf(t - (1.0 - SPIN_ARMS_OUT), 0.0) / SPIN_ARMS_OUT
	if t < 0.5:
		return lerp(swing_from, 2.0, t * 2.0)
	return 2.0 + (t - 0.5) * 2.0


# ===== THROWING =====

## The arm follows through after letting go of a throw.
func play_throw_release() -> void:
	release_time = THROW_RELEASE_DURATION


## Winds the arm back while `pressed` and it has something to throw, ramping
## up over `ramp` seconds from `press_time` (matching the throw-charge
## window), and relaxes back to rest otherwise.
func update_windup(delta: float, pressed: bool, press_time: float, has_throwable: bool, ramp: float) -> void:
	var target: float = 0.0
	if pressed and has_throwable:
		target = clamp((now() - press_time) / ramp, 0.0, 1.0)
	windup = move_toward(windup, target, delta * WINDUP_LERP_SPEED)


# ===== ANIMATION =====

## (PlayerClass3D.ArmAction, phase) for this arm, busiest first.
func action() -> Vector2:
	if rebound > 0.0:
		# Back the way it came, from where it hit to cocked
		var r: float = rebound / REBOUND_DURATION
		return Vector2(PlayerClass3D.ArmAction.SWING, lerp(1.0, rebound_from, r * r))
	if swing_time > 0.0:
		return Vector2(PlayerClass3D.ArmAction.SWING, swing_phase())
	if is_drawing():
		return Vector2(PlayerClass3D.ArmAction.SWING, draw_progress())
	if shot_time > 0.0:
		return Vector2(PlayerClass3D.ArmAction.SWING, 3.0 - 2.0 * shot_time / SHOT_ANIM_DURATION)
	if release_time > 0.0:
		return Vector2(PlayerClass3D.ArmAction.THROW, 3.0 - 2.0 * release_time / THROW_RELEASE_DURATION)
	if windup > WINDUP_SHOWN:
		return Vector2(PlayerClass3D.ArmAction.THROW, windup)
	if weapon and weapon.is_holding_pose():
		return Vector2(PlayerClass3D.ArmAction.HOLD, 0.0)
	return Vector2(PlayerClass3D.ArmAction.REST, 0.0)


## The clip for arm_anim: a combo beat's, while it swings (-1 = the
## weapon's usual one).
func clip_index() -> float:
	if swing_time <= 0.0 and rebound <= 0.0:
		return -1.0
	return PlayerVisual3D.clip_index(swing_clip)
