class_name ShieldClass3D extends WeaponClass3D
## Shield: held in the off hand beside a one-handed weapon, it's general
## defense: whoever holds it takes less damage and shove from every hit
## (see PlayerClass3D.receive_hit), wearing it a little each time. It
## doesn't attack.
##
## Monsters (see SkeletonEnemy3D) still raise theirs to block: while raised
## the arm holds it up in front (its hold_clip), and it catches the ball
## (see Ball3D); online every machine is told when it goes up or down.

## Times the damage and knockback its holder takes.
@export var damage_taken: float = 0.7
@export var knockback_taken: float = 0.6

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
