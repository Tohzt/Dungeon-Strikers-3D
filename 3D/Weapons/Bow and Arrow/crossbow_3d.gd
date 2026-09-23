class_name CrossbowClass3D extends WeaponClass3D
## Crossbow: hold-to-throw comes for free from the generic WeaponClass3D
## hand-follow behavior. Unlike a melee weapon, it doesn't dangle at/swing
## from the hand - while held (and not being thrown) it springs to a fixed
## aim-forward pose in front of the wielder instead, and a tap fires an arrow
## rather than playing the shoulder-swipe animation.

@export var arrow_scene: PackedScene
@export var arrow_speed: float = 40.0
@export var muzzle_forward_offset: float = 0.6
@export var muzzle_height_offset: float = 0.0

@export var hold_forward_offset: float = 0.85
@export var hold_height_offset: float = 0.1

# Sideways offset (in the wielder's local space) of whichever hand is
# holding this, cached on equip. Without this, both hands' held-forward
# poses would collapse to the same point straight out from body-center, so
# picking up two crossbows would pile them on top of each other instead of
# one at each hand's side.
var _hand_side_offset: float = 0.0


func equip(new_wielder: Node3D, hand: Area3D = null) -> void:
	super.equip(new_wielder, hand)
	if new_wielder and hand:
		_hand_side_offset = new_wielder.to_local(hand.global_position).x


func attack(aim_direction: Vector3) -> void:
	if not arrow_scene or not wielder:
		return

	var arrow : Node3D = arrow_scene.instantiate()
	wielder.get_parent().add_child(arrow)
	arrow.global_position = global_position \
		+ aim_direction.normalized() * muzzle_forward_offset \
		+ Vector3.UP * muzzle_height_offset
	arrow.exclude_body(wielder)
	arrow.exclude_body(self)
	arrow.fire(aim_direction, arrow_speed)


func _physics_process(delta: float) -> void:
	if is_held and not is_thrown and wielder:
		_physics_process_held_forward(delta)
	else:
		super._physics_process(delta)


func _physics_process_held_forward(_delta: float) -> void:
	var target_local: Vector3 = Vector3(_hand_side_offset, hold_height_offset, hold_forward_offset)
	var target_pos: Vector3 = wielder.to_global(target_local)

	var offset: Vector3 = target_pos - global_position
	var spring_force: Vector3 = offset * follow_strength
	var damping_force: Vector3 = -linear_velocity * follow_damping
	apply_central_force(spring_force + damping_force)

	rotation = Vector3(0.0, wielder.rotation.y, 0.0)
