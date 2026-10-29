class_name DamageNumber3D extends Label3D
## How much a hit took, popping up over whoever took it and following them
## (knocked back or not), drifting up and fading out. Stays where they were
## last if they're gone. Shown with Vfx.damage_number(_everywhere).

const LIFETIME := 0.9
const RISE := 1.4
## Drifts this far to a random side, so a flurry of hits doesn't stack up.
const SPREAD := 0.5
## A hit this big or bigger shows bigger and hotter.
const BIG_HIT := 25.0
const COLOR := Color(1.0, 1.0, 1.0)
const BIG_COLOR := Color(1.0, 0.75, 0.2)
const FONT_SIZE := 56
const BIG_FONT_SIZE := 80

var _age: float = 0.0
var _target: Node3D
var _offset: Vector3
var _anchor: Vector3
var _drift: Vector3


static func make(target: Node3D, target_offset: Vector3, amount: float) -> DamageNumber3D:
	var label := DamageNumber3D.new()
	var big: bool = amount >= BIG_HIT
	label.text = str(roundi(amount))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.pixel_size = 0.01
	label.font_size = BIG_FONT_SIZE if big else FONT_SIZE
	label.outline_size = 14
	label.outline_modulate = Color(0.1, 0.05, 0.05)
	label.modulate = BIG_COLOR if big else COLOR
	label.render_priority = 10
	label.outline_render_priority = 9
	label._target = target
	label._offset = target_offset
	label._anchor = target.global_position + target_offset
	label._drift = Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU) * SPREAD
	return label


func _ready() -> void:
	global_position = _anchor


func _process(delta: float) -> void:
	_age += delta
	var t: float = _age / LIFETIME
	if t >= 1.0:
		queue_free()
		return
	if is_instance_valid(_target) and _target.is_inside_tree():
		_anchor = _target.global_position + _offset
	global_position = _anchor + _drift * t + Vector3.UP * RISE * ease(t, 0.4)
	# Pops in a touch big, then settles
	scale = Vector3.ONE * lerpf(1.4, 1.0, minf(t * 6.0, 1.0))
	modulate.a = 1.0 - ease(t, 3.0)
	outline_modulate.a = modulate.a
