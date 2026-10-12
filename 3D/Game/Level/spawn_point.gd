@tool
class_name SpawnPoint3D extends Marker3D
## Where a team's players start and respawn. Teammates line up side by side
## along this marker's local X axis, so rotate it to turn the line. Teams
## without one fall back to Game3D's spots between their goal and altar.

## The team (PlayerSlot.team) that spawns here.
@export var team: int = 0


func _ready() -> void:
	add_to_group("SpawnPoint")
