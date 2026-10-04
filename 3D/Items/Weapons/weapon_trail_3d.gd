class_name WeaponTrail3D extends MeshInstance3D
## A fading ribbon behind a held weapon's blade while it's swung fast, so a
## swing reads as a sweep. Purely for looks: it follows the blade's pose,
## which every machine animates the same, so it needs no syncing.

## Seconds a stretch of ribbon lasts before it has faded out.
const LIFETIME := 0.16
## Blade speed (m/s, relative to the wielder, so walking doesn't count)
## above which it leaves a ribbon.
const MIN_SPEED := 7.0
## How see-through the newest edge is (0-1).
const ALPHA := 0.55
## Only over the strike and the start of the follow-through (arm_anim
## phases, see PlayerClass3D.arm_anim), not the wind-up.
const PHASE_FROM := 1.0
const PHASE_TO := 2.4
## Where along the blade the ribbon runs, from grip (0) to tip (1).
const FROM := 0.35

class Sample:
	var base: Vector3
	var tip: Vector3
	var msec: int
	var strip: int  # Samples in the same strip are joined up

var weapon: Weapon3D = null
var _samples: Array[Sample] = []
var _strip: int = 0
var _emitting: bool = false
var _last_tip_local: Vector3
var _last_usec: int = -1
var _sampled_frame: int = -1
var _mesh := ImmediateMesh.new()
var _base_local: Vector3
var _tip_local: Vector3


## Runs along `weapon`'s blade (local +Y), as long as its collision box.
func setup(owner_weapon: Weapon3D, color: Color) -> void:
	weapon = owner_weapon
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = color
	material_override = material
	var box := weapon.Collision.shape as BoxShape3D if weapon.Collision else null
	var center: Vector3 = weapon.Collision.position if weapon.Collision else Vector3.ZERO
	var half: float = box.size.y * 0.5 if box else 0.5
	_tip_local = center + Vector3(0, half, 0)
	_base_local = (center - Vector3(0, half, 0)).lerp(_tip_local, FROM)


## The weapon was just posed in the hand: add where its blade is now.
func sample() -> void:
	_sampled_frame = Engine.get_process_frames()
	var now_usec: int = Time.get_ticks_usec()
	var wielder: Node3D = weapon.wielder
	var fast: bool = false
	if weapon.is_held and wielder:
		var tip_local: Vector3 = wielder.global_transform.affine_inverse() * (weapon.global_transform * _tip_local)
		if _last_usec >= 0 and now_usec > _last_usec and _striking(wielder):
			var speed: float = tip_local.distance_to(_last_tip_local) / ((now_usec - _last_usec) / 1000000.0)
			fast = speed > MIN_SPEED
		_last_tip_local = tip_local
		_last_usec = now_usec
	else:
		_last_usec = -1
	if fast:
		if not _emitting:
			_strip += 1
		var s := Sample.new()
		s.base = weapon.global_transform * _base_local
		s.tip = weapon.global_transform * _tip_local
		s.msec = Time.get_ticks_msec()
		s.strip = _strip
		_samples.append(s)
	_emitting = fast
	_rebuild()


## The arm holding this is in the strike of a swing.
func _striking(wielder: Node3D) -> bool:
	if not wielder is PlayerClass3D:
		return true
	var player := wielder as PlayerClass3D
	var o: int = 0 if player.held_weapon_left == weapon else 2
	return roundi(player.arm_anim[o]) == PlayerClass3D.ArmAction.SWING \
		and player.arm_anim[o + 1] >= PHASE_FROM and player.arm_anim[o + 1] <= PHASE_TO


func _process(_delta: float) -> void:
	# Not posed since last frame (dropped, thrown): fade out what's left.
	# This can run before this frame's posing, so last frame's still counts.
	if Engine.get_process_frames() - _sampled_frame > 1 and not _samples.is_empty():
		_emitting = false
		_rebuild()


func _rebuild() -> void:
	var now: int = Time.get_ticks_msec()
	while not _samples.is_empty() and now - _samples[0].msec > LIFETIME * 1000.0:
		_samples.pop_front()
	_mesh.clear_surfaces()
	var i: int = 0
	while i < _samples.size():
		var j: int = i
		while j + 1 < _samples.size() and _samples[j + 1].strip == _samples[i].strip:
			j += 1
		if j > i:
			_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
			for k in range(i, j + 1):
				var s: Sample = _samples[k]
				var alpha: float = ALPHA * clampf(1.0 - (now - s.msec) / (LIFETIME * 1000.0), 0.0, 1.0)
				_mesh.surface_set_color(Color(1, 1, 1, alpha * 0.4))
				_mesh.surface_add_vertex(s.base)
				_mesh.surface_set_color(Color(1, 1, 1, alpha))
				_mesh.surface_add_vertex(s.tip)
			_mesh.surface_end()
		i = j + 1
