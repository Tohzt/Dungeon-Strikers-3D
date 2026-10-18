class_name Nameplates3D extends CanvasLayer
## Every player's and bot's name over their head, filled in their team
## color as far as their health goes (NameTag), so you can tell who is who
## and how hurt they are at a glance. Follows Game3D.players, so players
## who leave lose theirs.

## How far above a player's origin the name sits: over the head and the
## leaders' crown.
const HEAD_HEIGHT := 1.9
const FONT_SIZE := 24
const BORDER := 8
## Under the HUDs (layer 1), over the arena.
const LAYER := 0

var _tags: Dictionary[PlayerClass3D, NameTag] = {}


func _ready() -> void:
	layer = LAYER


func _process(_delta: float) -> void:
	var game: Game3D_Class = Global.Game3D
	var camera: Camera3D = get_viewport().get_camera_3d()
	# Untyped: a player that's gone may already be freed
	for player: Variant in _tags.keys():
		if not is_instance_valid(player) or not game or not game.players.has(player):
			_tags[player].queue_free()
			_tags.erase(player)
	if not game or not camera:
		return
	for player: PlayerClass3D in game.players:
		if not is_instance_valid(player) or not player.is_inside_tree():
			continue
		var tag: NameTag = _tags.get(player)
		if not tag:
			tag = _make_tag()
			_tags[player] = tag
		var head: Vector3 = player.global_position + Vector3.UP * HEAD_HEIGHT
		tag.visible = player.visible and not camera.is_position_behind(head)
		if not tag.visible:
			continue
		if player.slot:
			tag.text = player.slot.label()
			tag.color = player.slot.color
		else:
			tag.text = String(player.name)
		tag.fraction = player.Entity.hp / player.Entity.hp_max if player.Entity.hp_max > 0.0 else 0.0
		var at: Vector2 = camera.unproject_position(head)
		tag.position = (at - Vector2(tag.size.x * 0.5, tag.size.y)).round()


func _make_tag() -> NameTag:
	var tag := NameTag.new()
	tag.font_size = FONT_SIZE
	tag.border = BORDER
	add_child(tag)
	return tag
