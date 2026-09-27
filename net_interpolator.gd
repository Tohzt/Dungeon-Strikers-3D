class_name NetInterpolator extends RefCounted
## Plays back another machine's updates a little in the past, blending
## between them, so remote things move smoothly even though packets arrive
## unevenly. Snapshots are stamped with the sender's physics clock (see
## now()), so each interpolator must only be fed by one sender at a time;
## clear() it when that changes.

## How far behind the newest update playback runs. Enough to absorb a
## late packet or two.
const DELAY := 0.1
## Playback that has drifted further than this from where it should be
## jumps instead of catching up gradually.
const MAX_DRIFT := 0.25
## How quickly playback eases back toward DELAY behind the newest update.
const DRIFT_CORRECTION := 2.0
const MAX_SNAPSHOTS := 32
## Senders only send while something moves, but repeat a resting pose this
## often anyway: updates are unreliable, and a lost "it landed" packet
## would otherwise leave it hanging in the air on someone's screen.
const RESEND_IDLE_MSEC := 1000
## A jump further than this between updates is a teleport (e.g. respawn):
## snap to it instead of sliding across the map.
const TELEPORT_DISTANCE := 3.0

var delay: float
var _times: Array[float] = []
var _xforms: Array[Transform3D] = []
## Extra values carried with each snapshot (angles), blended with lerp_angle.
var _extras: Array[PackedFloat32Array] = []
var _render_time: float = -1.0


## `playback_delay` 0 means "always show the newest update" (the server
## uses that: it wants the least lag, not smoothness, and has no screen).
func _init(playback_delay: float = DELAY) -> void:
	delay = playback_delay


## Sender-side timestamp: this machine's physics clock in seconds.
static func now() -> float:
	return float(Engine.get_physics_frames()) / Engine.physics_ticks_per_second


func is_empty() -> bool:
	return _times.is_empty()


func clear() -> void:
	_times.clear()
	_xforms.clear()
	_extras.clear()
	_render_time = -1.0


func push(time: float, xform: Transform3D, extras: PackedFloat32Array = PackedFloat32Array()) -> void:
	if not _times.is_empty() and time > _times[-1] \
			and xform.origin.distance_to(_xforms[-1].origin) > TELEPORT_DISTANCE:
		clear()
	if not _times.is_empty():
		if time <= _times[-1]:
			return  # Duplicate or out of order
		# The sender went quiet (it only sends while things move). Start the
		# new movement from where it rested rather than from the last
		# snapshot's old timestamp, or playback would jump ahead.
		var tick: float = 1.0 / Engine.physics_ticks_per_second
		if time - _times[-1] > delay + tick * 2.0:
			_append(time - tick, _xforms[-1], _extras[-1])
	_append(time, xform, extras)
	if _render_time < 0.0:
		_render_time = time - delay


## Advance playback by `delta` and return [transform, extras] for this
## frame, or an empty array if there's nothing to show yet.
func sample(delta: float) -> Array:
	if _times.is_empty():
		return []
	var target: float = _times[-1] - delay
	_render_time += delta
	var drift: float = target - _render_time
	if abs(drift) > MAX_DRIFT:
		_render_time = target
	else:
		_render_time += drift * min(delta * DRIFT_CORRECTION, 1.0)

	# Drop snapshots playback has fully passed, keeping one behind it to blend from
	while _times.size() > 2 and _times[1] <= _render_time:
		_times.pop_front()
		_xforms.pop_front()
		_extras.pop_front()

	if _times.size() == 1 or _render_time <= _times[0]:
		return [_xforms[0], _extras[0]]
	if _render_time >= _times[-1]:
		return [_xforms[-1], _extras[-1]]  # Ran out: hold, don't guess ahead
	var t: float = inverse_lerp(_times[0], _times[1], _render_time)
	var extras := PackedFloat32Array()
	for i in _extras[0].size():
		extras.append(lerp_angle(_extras[0][i], _extras[1][i], t))
	return [_xforms[0].interpolate_with(_xforms[1], t), extras]


func _append(time: float, xform: Transform3D, extras: PackedFloat32Array) -> void:
	_times.append(time)
	_xforms.append(xform)
	_extras.append(extras)
	if _times.size() > MAX_SNAPSHOTS:
		_times.pop_front()
		_xforms.pop_front()
		_extras.pop_front()
