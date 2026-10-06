class_name NetMotion extends RefCounted
## One node's movement over the network, both ends of it. The machine that
## simulates the node asks should_send() each tick and, when told to, sends
## its pose (with NetInterpolator.now()) through the node's own RPC; every
## other machine push()es the poses it receives and play()s them back
## smoothly each frame (see NetInterpolator).

var _interpolator := NetInterpolator.new(0.0 if Net.is_server else NetInterpolator.DELAY)
## The machine whose poses are being played back (see push()).
var _sender: int = 0

var _last_sent_transform: Transform3D
var _last_sent_msec: int = 0
var _last_sent_frame: int = -1
var _send_next: bool = false


## Sender: whether to send `xform` now. At most once per physics tick, and
## only while it moves, but a resting pose is repeated every
## NetInterpolator.RESEND_IDLE_MSEC (updates are unreliable, and a lost
## "it landed" would otherwise leave it hanging in the air for someone).
func should_send(xform: Transform3D) -> bool:
	var frame: int = Engine.get_physics_frames()
	var now_msec: int = Time.get_ticks_msec()
	if frame == _last_sent_frame:
		return false
	if not _send_next and xform.is_equal_approx(_last_sent_transform) \
			and now_msec - _last_sent_msec < NetInterpolator.RESEND_IDLE_MSEC:
		return false
	_send_next = false
	_last_sent_frame = frame
	_last_sent_transform = xform
	_last_sent_msec = now_msec
	return true


## Sender: send the next pose even if it hasn't moved (e.g. it was just let
## go, or this machine just took it over).
func send_next() -> void:
	_send_next = true


## Receiver: a pose `sender` stamped with its clock's `time`. Poses from
## different machines' clocks can't be blended, so a new sender starts
## playback afresh.
func push(time: float, xform: Transform3D, extras := PackedFloat32Array(), sender: int = 0) -> void:
	if sender != _sender:
		_interpolator.clear()
		_sender = sender
	_interpolator.push(time, xform, extras)


## Receiver, every rendered frame: move `node` to where its sender had it a
## moment ago. Returns the extras sent with that pose (empty if there's
## nothing to show yet).
func play(node: Node3D, delta: float) -> PackedFloat32Array:
	var sample: Array = _interpolator.sample(delta)
	if sample.is_empty():
		return PackedFloat32Array()
	node.global_transform = sample[0]
	return sample[1]


## Forget the poses so far (e.g. picked up: the ones from before are stale
## by the time it's let go).
func clear() -> void:
	_interpolator.clear()
