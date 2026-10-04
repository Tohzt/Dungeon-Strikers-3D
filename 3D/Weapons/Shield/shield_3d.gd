class_name ShieldClass3D extends WeaponClass3D
## Shield: tap-to-bump and hold-to-throw come for free from the generic
## Weapon3D/WeaponClass3D behavior. Blocking is shield-specific: while raised
## the arm holds it up in front (its hold_clip). A raised shield also catches
## the ball (see Ball3D), so whoever blocks can keep goal; online every
## machine is told when it goes up or down.

var is_blocking: bool = false


func start_block() -> void:
	_set_blocking(true)


func stop_block() -> void:
	_set_blocking(false)


func is_holding_pose() -> bool:
	return is_blocking and super()


func _set_blocking(value: bool) -> void:
	if value == is_blocking:
		return
	is_blocking = value
	if Net.match_synced and is_multiplayer_authority():
		_net_blocking.rpc(value)


@rpc("any_peer", "reliable")
func _net_blocking(value: bool) -> void:
	if _is_from_owner():
		is_blocking = value
