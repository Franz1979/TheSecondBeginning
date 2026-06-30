extends Camera2D

const MOVE_SPEED: float = 500.0
const ZOOM_STEP: float = 0.1
const MIN_ZOOM: float = 0.4
const MAX_ZOOM: float = 3.0

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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom -= Vector2(ZOOM_STEP, ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom += Vector2(ZOOM_STEP, ZOOM_STEP)

		zoom.x = clamp(zoom.x, MIN_ZOOM, MAX_ZOOM)
		zoom.y = clamp(zoom.y, MIN_ZOOM, MAX_ZOOM)
