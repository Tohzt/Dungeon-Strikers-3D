@tool
class_name Goal3D extends StaticBody3D
## A goal mouth. When the ball goes into its net, `scoring_team` gets a point.
## Online only the server (which simulates the ball) counts goals.

const PLAYERS_SCRIPT := preload("res://players.gd")

## The team (PlayerSlot.team) awarded a point when the ball goes in here,
## i.e. the team attacking this goal.
@export var scoring_team: int = 0
## The team defending this goal, i.e. whose side it's on. Colors the net.
@export var owner_team: int = 1:
	set(value):
		owner_team = value
		if is_node_ready():
			_apply_team_color()

@onready var net: Area3D = $Net
@onready var net_mesh: MeshInstance3D = $Net/MeshInstance3D


func _ready() -> void:
	_apply_team_color()
	if Engine.is_editor_hint():
		return
	add_to_group("Goal")
	net.body_entered.connect(_on_net_body_entered)


func _on_net_body_entered(body: Node3D) -> void:
	if body is Ball3D and (not Net.in_session() or Net.is_server):
		Global.Game3D.score_goal(scoring_team, body)


## Tints the net with the owning team's color, keeping its transparency.
func _apply_team_color() -> void:
	var material: StandardMaterial3D = net_mesh.get_surface_override_material(0)
	if not material:
		return
	# Our own copy, so the two goals don't share (and fight over) one material.
	if not material.resource_local_to_scene:
		material = material.duplicate()
		material.resource_local_to_scene = true
		net_mesh.set_surface_override_material(0, material)
	# Read from the script, not the Players autoload, so it also works in the editor.
	var team_colors: Array[Color] = PLAYERS_SCRIPT.TEAM_COLORS
	var color: Color = team_colors[owner_team % team_colors.size()]
	color.a = material.albedo_color.a
	material.albedo_color = color
