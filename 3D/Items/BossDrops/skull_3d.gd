class_name Skull3D extends Ball3D
## A beaten boss's skull (see BossDrop). It isn't scored in a goal: a team
## knocks it home to its own altar (it counts for whichever team last played
## it), which turns it into a reward after a while (see
## Altar3D.start_reward). Otherwise it handles like the ball. Online the
## server spots the delivery.

## A loose skull counts as home this close (flat) to the altar of the team
## that last played it.
const DELIVER_RANGE := 2.5


func _physics_process(delta: float) -> void:
	super(delta)
	if Net.decides():
		_check_delivery()


func _check_delivery() -> void:
	var game: Game3D_Class = Global.Game3D
	if not game or not game.balls.has(self):
		return
	if last_team < 0:
		return
	var altar: Altar3D = game.altar_of_team(last_team)
	if not altar:
		return
	var to_altar: Vector3 = altar.global_position - global_position
	if Vector2(to_altar.x, to_altar.z).length() < DELIVER_RANGE:
		game.deliver_skull(last_team, self)
