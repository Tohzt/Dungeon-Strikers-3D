class_name CameraShake
## Screen shake for the GameCamera3D. Anything can add() trauma; the camera
## calls apply() each
## frame, which shakes it by trauma squared (so small knocks stay subtle and
## big ones kick) and lets the trauma drain away.
##
## The shake moves the camera's h_offset/v_offset rather than its
## transform, so it never feeds back into the camera's own easing.
##
## Each machine shakes for what it sees: call add() wherever the event
## already plays out on every machine (a stomp, a sound), or only where it
## matters to the local player (they got hit, their swing connected).

## Scales every shake; 0 turns it off.
static var strength: float = 1.0
## Where the camera in use is looking (set by apply()). Shakes added with
## a position fade out with distance from here.
static var focus: Vector3 = Vector3.ZERO

## Trauma drained per second.
const DECAY := 1.6
## Most the view moves at full trauma, as a share of half the screen height.
const MAX_OFFSET := 0.12
## Noise scroll speed: higher shakes faster.
const FREQUENCY := 28.0
## Positioned shakes are full strength within NEAR of the focus, gone by FAR.
const NEAR := 6.0
const FAR := 30.0

# Common amounts, so similar knocks feel the same everywhere.
const TINY := 0.18  # Our swing hits something light
const LIGHT := 0.3  # Our swing hits something solid, a blocked hit
const MEDIUM := 0.45  # We got hit, a weapon shatters
const HEAVY := 0.65  # Boss stomp, thunderclap, we went down

static var _trauma: float = 0.0
static var _noise: FastNoiseLite = null


## Shake by `amount` (0-1, adds up to 1). With `at`, weaker the further it
## is from what the camera's looking at.
static func add(amount: float, at: Variant = null) -> void:
	if at is Vector3:
		var distance: float = Vector2(at.x - focus.x, at.z - focus.z).length()
		amount *= 1.0 - smoothstep(NEAR, FAR, distance)
	_trauma = clamp(_trauma + amount, 0.0, 1.0)


## Shake `camera` for this frame and drain the trauma. `depth` is roughly
## how far away what it's looking at is, so the shake moves the picture by
## the same share of the screen at any distance or zoom.
static func apply(camera: Camera3D, delta: float, depth: float, look_point: Vector3) -> void:
	if not camera.is_current():
		return
	focus = look_point
	_trauma = max(_trauma - DECAY * delta, 0.0)
	var shake: float = _trauma * _trauma * strength
	if shake <= 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		return
	if not _noise:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_noise.frequency = 1.0
	var t: float = Time.get_ticks_msec() * 0.001 * FREQUENCY
	var reach: float = MAX_OFFSET * depth * tan(deg_to_rad(camera.fov) * 0.5) * shake
	camera.h_offset = _noise.get_noise_2d(t, 0.0) * reach
	camera.v_offset = _noise.get_noise_2d(t, 100.0) * reach

