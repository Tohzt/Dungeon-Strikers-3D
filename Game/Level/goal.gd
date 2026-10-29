class_name Goal3D extends StaticBody3D
## A goal mouth: a portal in its team's color, between the posts. When the
## ball goes into it, `scoring_team` gets a point; a bomb goes off in there
## instead, damaging `owner_team`'s base (whoever knocked it in, see
## Game3D.bomb_in_goal). Its team's players come out of it when they spawn
## (see Game3D._spawn_position).
## Online only the server (which simulates the ball) counts goals.

## scoring_team value: the point goes to whoever last played the ball
## (Ball3D.last_team), unless that's this goal's own team.
const LAST_TOUCH := -1
## The opening between the posts and under the bar (m), which the portal fills.
const MOUTH_SIZE := Vector2(6.5, 3.5)
## The portal, times the mouth, so its rim tucks in behind the posts and bar.
const PORTAL_OVERSIZE := 1.12
## VFXPortalController.portal_mode: its middle drawn in its own (dark)
## color, rather than warping or hiding what's behind.
const PORTAL_OPAQUE := 0
## How much darker than the team's color the far end of the tunnel is.
const PORTAL_DEPTH_DARKEN := 0.8
## The portal's outline: a square fill, so it's a rectangle filling the
## mouth (the pack's own is round).
const PORTAL_SHAPE: Texture2D = preload("res://Game/Level/goal_portal_shape.tres")

## The team (PlayerSlot.team) awarded a point when the ball goes in here,
## i.e. the team attacking this goal. LAST_TOUCH when several teams attack
## it (four-team matches; Game3D sets that up).
@export var scoring_team: int = 0
## The team defending this goal, i.e. whose side it's on. Colors the portal.
@export var owner_team: int = 1

@onready var net: Area3D = $Net


func _ready() -> void:
	add_to_group("Goal")
	net.body_entered.connect(_on_net_body_entered)
	_open_portal()


## Which way its mouth faces: out onto the field.
func facing() -> Vector3:
	return -global_basis.x


## Along its mouth, from post to post.
func across() -> Vector3:
	return global_basis.z


## Held open for the whole match: a rectangular tunnel of wispy rings (see
## Vfx.SETTINGS) in its team's color, dark at the far end. The pack's portal is a 2m square
## facing its +Z, which Vfx.attach turns to face our -X (the field).
func _open_portal() -> void:
	var color: Color = Players.team_color(owner_team)
	var portal: Node3D = Vfx.attach(&"portal", self, Vector3.ZERO, 0.0, 1.0, color)
	if not portal:
		return
	portal.scale = Vector3(MOUTH_SIZE.x, MOUTH_SIZE.y, 2.0) / 2.0 * PORTAL_OVERSIZE
	portal.set(&"portal_mode", PORTAL_OPAQUE)
	portal.set(&"secondary_color", color.darkened(PORTAL_DEPTH_DARKEN))
	portal.set(&"shape_texture", PORTAL_SHAPE)


func _on_net_body_entered(body: Node3D) -> void:
	if not body is Ball3D or not Net.decides():
		return
	if body is Bomb3D:
		Global.Game3D.bomb_in_goal(self, body)
		return
	var team: int = scoring_team
	if team == LAST_TOUCH:
		team = body.last_team
	if team < 0 or team == owner_team:
		Global.Game3D.return_ball(body)  # Own goal, or nobody played it
	else:
		Global.Game3D.score_goal(team, body)
