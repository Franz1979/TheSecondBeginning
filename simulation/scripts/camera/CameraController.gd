extends Camera2D

const MOVE_SPEED: float = 500.0
const ZOOM_STEP: float = 0.1
const MIN_ZOOM: float = 0.4
const MAX_ZOOM: float = 3.0
const EDGE_PAN_MARGIN: float = 24.0
const EDGE_PAN_MAX_SPEED: float = 500.0

func _ready() -> void:
	position = Vector2(800, 400)

func _process(delta: float) -> void:
	var direction := Vector2.ZERO

	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1

	if direction != Vector2.ZERO:
		position += direction.normalized() * MOVE_SPEED * delta

	var edge_pan := _get_edge_pan_vector()
	if edge_pan != Vector2.ZERO:
		position += edge_pan * EDGE_PAN_MAX_SPEED * delta


func _get_map_rect() -> Rect2:
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)

	var sidebar := get_parent().get_node_or_null("CanvasLayer/Sidebar")
	if sidebar is Control and sidebar.visible:
		rect.size.x = sidebar.get_global_rect().position.x

	return rect


func _get_edge_pan_vector() -> Vector2:
	if get_viewport().gui_get_hovered_control() != null:
		return Vector2.ZERO

	var mouse_pos := get_viewport().get_mouse_position()
	var rect := _get_map_rect()
	if not rect.has_point(mouse_pos):
		return Vector2.ZERO

	var pan := Vector2.ZERO

	var dist_left := mouse_pos.x - rect.position.x
	var dist_right := rect.position.x + rect.size.x - mouse_pos.x
	if dist_left < EDGE_PAN_MARGIN:
		pan.x = -(1.0 - dist_left / EDGE_PAN_MARGIN)
	elif dist_right < EDGE_PAN_MARGIN:
		pan.x = 1.0 - dist_right / EDGE_PAN_MARGIN

	var dist_top := mouse_pos.y - rect.position.y
	var dist_bottom := rect.position.y + rect.size.y - mouse_pos.y
	if dist_top < EDGE_PAN_MARGIN:
		pan.y = -(1.0 - dist_top / EDGE_PAN_MARGIN)
	elif dist_bottom < EDGE_PAN_MARGIN:
		pan.y = 1.0 - dist_bottom / EDGE_PAN_MARGIN

	return pan


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom -= Vector2(ZOOM_STEP, ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom += Vector2(ZOOM_STEP, ZOOM_STEP)

		zoom.x = clamp(zoom.x, MIN_ZOOM, MAX_ZOOM)
		zoom.y = clamp(zoom.y, MIN_ZOOM, MAX_ZOOM)
