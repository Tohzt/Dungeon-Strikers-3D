class_name BossTrigger3D extends Area3D
## Wakes sleeping bosses (Boss3D.wait_for_players) the first time a player
## walks in. Cover a boss arena with it so the fight starts when the first
## team arrives, whoever that is.

## Shown on the scoreboard as the bosses wake. %s = the boss's name.
@export var message: String = "%s awakens!"
## The bosses it wakes. Empty = every sleeping boss in the level (fine when
## there's only one boss room).
@export var bosses: Array[Boss3D] = []

var _triggered: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _triggered or not body is PlayerClass3D:
		return
	_triggered = true
	var sleepers: Array[Boss3D] = bosses.duplicate()
	if sleepers.is_empty():
		for node: Node in get_tree().get_nodes_in_group("Boss"):
			if node is Boss3D:
				sleepers.append(node)
	for boss: Boss3D in sleepers:
		if is_instance_valid(boss) and boss.wait_for_players:
			boss.wake()
			if Global.Game3D:
				Global.Game3D.scoreboard.announce(message % boss.display_name, Color(0.6, 1.0, 0.5))
