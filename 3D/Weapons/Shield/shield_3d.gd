class_name ShieldClass3D extends WeaponClass3D
## Shield: tap-to-bump and hold-to-throw come for free from the generic
## Weapon3D/WeaponClass3D hand-follow behavior. Blocking is shield-specific:
## while raised it ignores the hand entirely and springs toward a fixed pose
## out in front of the wielder instead.

@export var block_forward_offset: float = 0.7
@export var block_height_offset: float = 0.2
# Blocking needs to hold its position against the wielder's own walking
# motion, not just swing naturally like a carried weapon, so it gets its own
# (stiffer) spring constants instead of reusing follow_strength/follow_damping.
@export var block_follow_strength: float = 2500.0
@export var block_follow_damping: float = 104.0

var is_blocking: bool = false


func start_block() -> void:
	is_blocking = true


func stop_block() -> void:
	is_blocking = false
	# Resync the hand-follow velocity-prediction baseline, otherwise the next
	# frame sees prev_hand_pos still sitting wherever it was when blocking
	# started (possibly seconds and several walked meters ago), computes a
	# huge bogus hand velocity, and flings the shield out ahead of the hand
	# for a frame before it corrects. Same fix as equip()'s reset, same reason.
	if held_hand:
		prev_hand_pos = held_hand.global_position


func _physics_process(delta: float) -> void:
	if is_blocking and is_held and not is_thrown:
		_physics_process_block(delta)
	else:
		super._physics_process(delta)


func _physics_process_block(_delta: float) -> void:
	if not wielder: return

	var forward_dir: Vector3 = Vector3(sin(wielder.rotation.y), 0.0, cos(wielder.rotation.y))
	var target_pos: Vector3 = wielder.global_position + forward_dir * block_forward_offset + Vector3.UP * block_height_offset

	var offset: Vector3 = target_pos - global_position
	var spring_force: Vector3 = offset * block_follow_strength
	var damping_force: Vector3 = -linear_velocity * block_follow_damping
	apply_central_force(spring_force + damping_force)

	# Face the same direction as the wielder. If the shield mesh looks
	# rotated wrong in-editor, fix it on the mesh child's local transform
	# rather than here (matches how sword_common_gltf is corrected).
	rotation = Vector3(0.0, wielder.rotation.y, 0.0)
