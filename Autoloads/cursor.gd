extends Node
## The mouse cursor. Everywhere it's POINTER, plain white; in a match the
## mouse player's tints it by what they're doing with their weapon (see
## PlayerClass3D._update_cursor), so they can tell a heavy's ready without
## looking away from where they're aiming.
##
## It's the hardware cursor (no lag behind the mouse), so each tint is its
## own texture: they're made once each and kept, and the cursor's only set
## when the tint changes.

const POINTER: Texture2D = preload("res://Assets/Cursors/pointer_scifi_b.png")
## Where in POINTER the click lands: its tip.
const HOTSPOT := Vector2(6, 6)

enum State { IDLE, LIGHT, CHARGING, CHARGED, HEAVY, THROW }

const COLORS: Dictionary[State, Color] = {
	State.IDLE: Color.WHITE,
	State.LIGHT: Color(1.0, 0.85, 0.3),
	## A charge runs from IDLE's color to this, then turns CHARGED's.
	State.CHARGING: Color(1.0, 0.55, 0.15),
	State.CHARGED: Color(1.0, 0.2, 0.2),
	State.HEAVY: Color(1.0, 0.2, 0.2),
	State.THROW: Color(0.4, 0.85, 1.0),
}
## How many tints a charge steps through on its way up.
const CHARGE_STEPS := 6

var _base: Image
var _textures: Dictionary[Color, ImageTexture] = {}
var _shown: Color = Color(0, 0, 0, 0)


func _ready() -> void:
	_base = POINTER.get_image()
	if _base.is_compressed():
		_base.decompress()
	_base.convert(Image.FORMAT_RGBA8)
	reset()


## Back to the plain pointer.
func reset() -> void:
	show_state(State.IDLE)


## Tint the cursor for `state`; `charge` (0-1) is how far a CHARGING heavy is.
func show_state(state: State, charge: float = 0.0) -> void:
	var color: Color = COLORS[state]
	if state == State.CHARGING:
		var step: float = floorf(clampf(charge, 0.0, 1.0) * CHARGE_STEPS) / CHARGE_STEPS
		color = COLORS[State.IDLE].lerp(color, step)
	if color == _shown:
		return
	_shown = color
	Input.set_custom_mouse_cursor(_tinted(color), Input.CURSOR_ARROW, HOTSPOT)


## POINTER with its white parts in `color` (the black outline stays black).
func _tinted(color: Color) -> ImageTexture:
	if _textures.has(color):
		return _textures[color]
	var image: Image = _base.duplicate()
	for y: int in image.get_height():
		for x: int in image.get_width():
			image.set_pixel(x, y, image.get_pixel(x, y) * Color(color, 1.0))
	var texture := ImageTexture.create_from_image(image)
	_textures[color] = texture
	return texture
