class_name CrossbowClass3D extends WeaponClass3D
## A shooting weapon: hold-to-throw comes for free from the generic
## WeaponClass3D behavior. A tap fires `arrow_scene` instead of swinging, and
## while held the arms keep it aimed (its hold_clip). The bow uses it for
## arrows; the staff and wand fire magic bolts, with no hold_clip, so they're
## just carried in the hand.

@export var arrow_scene: PackedScene
@export var arrow_speed: float = 40.0
@export var muzzle_forward_offset: float = 0.6
@export var muzzle_height_offset: float = 0.0
## What a shot sounds like (an Sfx.SOUNDS id).
@export var fire_sound: StringName = &"bow_release"

## The shot that breaks it carries its full break burst, bursting where it
## lands; the weapon itself then shatters in this much of one.
const SPENT_BREAK_BURST_SCALE := 0.4


func attack(aim_direction: Vector3) -> void:
	if not arrow_scene or not wielder:
		return

	var muzzle: Vector3 = global_position \
		+ aim_direction.normalized() * muzzle_forward_offset \
		+ Vector3.UP * muzzle_height_offset
	_fire_arrow(muzzle, aim_direction, true)
	if Net.match_synced:
		_net_fire.rpc(muzzle, aim_direction)
	wear()  # Each shot is a use


## `real` arrows hit things; online, everyone else's copy of a shot is just
## for show, since the shooter's machine decides what it hit.
func _fire_arrow(muzzle: Vector3, aim_direction: Vector3, real: bool) -> void:
	var arrow: Arrow3D = arrow_scene.instantiate()
	arrow.deals_damage = real
	# The shot that breaks it is the big one (see Weapon3D.is_last_use)
	if is_last_use():
		arrow.damage *= FINAL_DAMAGE_MULTIPLIER
		arrow.knockback *= FINAL_KNOCKBACK_MULTIPLIER
		arrow.scale = Vector3.ONE * 1.6
		if Properties:
			arrow.set_burst(Properties.break_burst_radius, Properties.break_burst_damage,
				Properties.break_burst_knockback, shatter_color())
			break_burst_scale = SPENT_BREAK_BURST_SCALE
	wielder.get_parent().add_child(arrow)
	arrow.global_position = muzzle
	arrow.exclude_body(wielder)
	arrow.shooter = wielder
	arrow.exclude_body(self)
	arrow.fire(aim_direction, arrow_speed)
	Sfx.play(fire_sound, muzzle)


@rpc("any_peer", "reliable")
func _net_fire(muzzle: Vector3, aim_direction: Vector3) -> void:
	if _is_from_owner() and arrow_scene and wielder:
		_fire_arrow(muzzle, aim_direction, false)
