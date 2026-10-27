class_name ScreenResViewport extends TextureRect
## A SubViewport shown at the screen's real resolution. A stretched
## SubViewportContainer renders at the control's size in UI units, which the
## window's canvas_items stretch then scales up (blurry, pixelated 3D in
## fullscreen). This sizes `viewport` in screen pixels instead and draws its
## texture back into the control's rect, so 3D stays as sharp as the text.

## Put the 3D scene under this. Its size is managed here.
var viewport := SubViewport.new()


func _init() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(viewport)
	resized.connect(_fit)
	# Also refit when a parent's scale changes (e.g. FitCenterContainer)
	set_notify_transform(true)


func _ready() -> void:
	texture = viewport.get_texture()
	get_viewport().size_changed.connect(_fit)
	_fit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_fit()


func _fit() -> void:
	if not is_inside_tree():
		return
	# The window's stretch, times any canvas/control scaling above this
	var to_screen: Transform2D = get_viewport().get_final_transform() * get_global_transform_with_canvas()
	var pixels: Vector2 = size * to_screen.get_scale().abs()
	viewport.size = Vector2i(pixels.round()).max(Vector2i.ONE)
