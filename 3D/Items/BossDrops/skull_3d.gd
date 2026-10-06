class_name Skull3D extends Ball3D
## A beaten boss's skull (see BossDrop). It isn't scored in a goal: a team
## brings it home to its own altar, which turns it into a reward after a
## while (see Altar3D.start_reward). Carrying it in counts, and so does
## knocking it onto the altar after one of the team last played it.
## Otherwise it handles like the ball: both hands to carry, a hard hit knocks
## it loose, and it can be thrown. Online the server spots the delivery.

## A loose skull counts as home this close (flat) to the altar of the team
## that last played it.
const DELIVER_RANGE := 2.5


func _ready() -> void:
	tint_by_speed = false
	super()


func _physics_process(delta: float) -> void:
	super(delta)
	if Net.decides():
		_check_delivery()


func _check_delivery() -> void:
	var game: Game3D_Class = Global.Game3D
	if not game or not game.balls.has(self):
		return
	if holder:
		var team: int = holder.slot.team if holder.slot else -1
		var altar: Altar3D = game.altar_of_team(team)
		if altar and altar.reach.overlaps_body(holder):
			game.deliver_skull(team, self)
	elif last_team >= 0:
		var altar: Altar3D = game.altar_of_team(last_team)
		if not altar:
			return
		var to_altar: Vector3 = altar.global_position - global_position
		if Vector2(to_altar.x, to_altar.z).length() < DELIVER_RANGE:
			game.deliver_skull(last_team, self)
