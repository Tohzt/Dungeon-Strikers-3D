class_name NameTag extends Control
## A player's name that doubles as their health bar. Two layers in a bold,
## rounded font: the whole name in a dark shade of the team color with a
## thick white border, then the name again in the team color, inside the
## border, cut off where their health runs out. At half health "PLAYER"
## shows "PLA" in the team color and "YER" in the darker shade.
##
## Used over every player's head (Nameplates3D) and on each local player's
## HUD (HUD3D). Sizes itself to the name; centered in any extra room.

const FONT_PATH := "res://Assets/UI/Fonts/Fredoka.ttf"
## Fredoka is a variable font: Bold.
const FONT_WEIGHT := 700
const BORDER_COLOR := Color.WHITE
## How much darker than the team color the part of the name health no
## longer fills is.
const EMPTY_DARKEN := 0.6

static var _font: Font

var text: String = "":
	set(value):
		if value == text:
			return
		text = value
		_refit()
var color: Color = Color.WHITE:
	set(value):
		if value == color:
			return
		color = value
		queue_redraw()
		_fill.queue_redraw()
## How much of the name is filled in, 0 to 1 (health / max health).
var fraction: float = 1.0:
	set(value):
		if is_equal_approx(value, fraction):
			return
		fraction = clampf(value, 0.0, 1.0)
		_place_clip()
var font_size: int = 22:
	set(value):
		if value == font_size:
			return
		font_size = value
		_refit()
## Thickness of the white border, in pixels.
var border: int = 8:
	set(value):
		if value == border:
			return
		border = value
		_refit()

## Cuts the team-colored copy off at `fraction`. Internal, so duplicating a
## NameTag (e.g. a HUD) doesn't make a second one.
var _clip: Control
var _fill: Control


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip, false, Node.INTERNAL_MODE_FRONT)
	_fill = Control.new()
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.draw.connect(_draw_fill)
	_clip.add_child(_fill)
	resized.connect(_place_clip)


static func font() -> Font:
	if not _font:
		var variation := FontVariation.new()
		variation.base_font = load(FONT_PATH)
		variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): FONT_WEIGHT}
		_font = variation
	return _font


func _get_minimum_size() -> Vector2:
	return _text_size() + Vector2.ONE * _pad() * 2.0


func _draw() -> void:
	var at: Vector2 = _baseline()
	draw_string_outline(font(), at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, border, BORDER_COLOR)
	draw_string(font(), at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color.darkened(EMPTY_DARKEN))


func _draw_fill() -> void:
	_fill.draw_string(font(), _baseline(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## The outline reaches half its thickness past the letters.
func _pad() -> float:
	return ceilf(border * 0.5) + 1.0


func _text_size() -> Vector2:
	return Vector2(font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x,
		font().get_height(font_size))


## Where the name starts (left end of its baseline), centered in our size.
func _baseline() -> Vector2:
	var natural: Vector2 = _get_minimum_size()
	return ((size - natural) * 0.5).floor() + Vector2(_pad(), _pad() + font().get_ascent(font_size))


func _refit() -> void:
	update_minimum_size()
	# Sized ourselves when nothing lays us out (e.g. over a player's head)
	if not get_parent() is Container:
		size = _get_minimum_size()
	queue_redraw()
	_fill.queue_redraw()
	_place_clip()


func _place_clip() -> void:
	var start: float = _baseline().x
	var width: float = _text_size().x
	_clip.size = Vector2(start + width * fraction if fraction > 0.0 else 0.0, size.y)
	_fill.size = size
