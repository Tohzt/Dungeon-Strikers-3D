class_name BossTrigger3D extends Area3D
## Wakes every sleeping boss (Boss3D.wait_for_players) the first time a
## player walks in. Cover a boss arena with it so the fight starts when the
## first team arrives, whoever that is.

## Shown on the scoreboard as the bosses wake. %s = the boss's name.
@export var message: String = "%s awakens!"

var _triggered: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _triggered or not body is PlayerClass3D:
		return
	_triggered = true
	for node: Node in get_tree().get_nodes_in_group("Boss"):
		var boss: Boss3D = node as Boss3D
		if boss and boss.wait_for_players:
			boss.wake()
			if Global.Game3D:
				Global.Game3D.scoreboard.announce(message % boss.display_name, Color(0.6, 1.0, 0.5))
