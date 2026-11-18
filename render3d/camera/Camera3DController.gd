class_name Camera3DController
extends Camera3D

# Camera della vista 3D: alta e inclinata, guarda lo stesso punto della camera 2D (che resta la fonte del "dove sono"
# per il gioco: celle accese, ritorno al 2D). Comandi:
# - WASD / frecce: spostamento (secondo la direzione in cui si guarda)
# - rotella: zoom
# - tasto centrale trascinato: spostamento
# - tasto destro trascinato: rotazione (orizzontale) e piccola correzione dell'inclinazione (verticale)
# L'inclinazione segue lo zoom, come nei gestionali di villaggi: da lontano più dall'alto (PITCH_FAR_DEG), da vicino
# più di fianco (PITCH_NEAR_DEG). Mai quasi verticale: lì il 3D sembra piatto.
# I clic del mouse sulla mappa vengono fermati qui: in 3D la mappa è solo da guardare.

const PAN_SPEED_PER_DISTANCE := 1.1
const ZOOM_FACTOR := 0.88
const MIN_DISTANCE := 10.0
const MAX_DISTANCE := 450.0
const PITCH_NEAR_DEG := 35.0
const PITCH_FAR_DEG := 60.0
# Correzione a mano col tasto destro, attorno all'angolo automatico.
const PITCH_OFFSET_MAX_DEG := 8.0
const ROTATE_SPEED := 0.006
const FOV_DEG := 32.0

var _reader: GameStateReader
var _yaw: float = 0.0
var _pitch_offset_deg: float = 0.0
var _distance: float = 80.0


func setup(reader: GameStateReader) -> void:
	_reader = reader
	fov = FOV_DEG
	near = 0.5
	far = 2000.0
	# Distanza iniziale simile all'inquadratura del 2D: stessa larghezza di mondo visibile.
	var viewport_height := get_viewport().get_visible_rect().size.y
	var visible_microcells := viewport_height / maxf(reader.camera_zoom(), 0.01) / float(MicroCellRenderer.CELL_SIZE)
	_distance = clampf(visible_microcells / (2.0 * tan(deg_to_rad(FOV_DEG) * 0.5)), MIN_DISTANCE, MAX_DISTANCE)
	_update_transform()


func _process(delta: float) -> void:
	if _reader == null:
		return
	if not _reader.camera_input_locked():
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
			_reader.move_camera(_screen_to_ground(direction.normalized()) * _distance * PAN_SPEED_PER_DISTANCE * delta)
	_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	if _reader == null or _reader.camera_input_locked():
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(MIN_DISTANCE, _distance * ZOOM_FACTOR)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(MAX_DISTANCE, _distance / ZOOM_FACTOR)
		# Nessun clic arriva alla mappa 2D nascosta.
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			var world_per_pixel := _distance * 2.0 * tan(deg_to_rad(FOV_DEG) * 0.5) / get_viewport().get_visible_rect().size.y
			_reader.move_camera(_screen_to_ground(-motion.relative) * world_per_pixel)
			get_viewport().set_input_as_handled()
		elif motion.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_yaw -= motion.relative.x * ROTATE_SPEED
			_pitch_offset_deg = clampf(_pitch_offset_deg + motion.relative.y * ROTATE_SPEED * 40.0, -PITCH_OFFSET_MAX_DEG, PITCH_OFFSET_MAX_DEG)
			get_viewport().set_input_as_handled()


# Direzione sullo schermo (x a destra, y in basso) -> direzione sul terreno in microcelle (x, y della mappa 2D).
func _screen_to_ground(screen: Vector2) -> Vector2:
	var right := Vector2(cos(_yaw), -sin(_yaw))
	var down := Vector2(sin(_yaw), cos(_yaw))
	return right * screen.x + down * screen.y


func _update_transform() -> void:
	var target_2d := _reader.camera_position()
	var target := Vector3(target_2d.x, 0.0, target_2d.y)
	var pitch := deg_to_rad(_current_pitch_deg())
	var offset := Vector3(sin(_yaw) * cos(pitch), sin(pitch), cos(_yaw) * cos(pitch)) * _distance
	look_at_from_position(target + offset, target, Vector3.UP)


# Angolo automatico dallo zoom (in scala logaritmica: ogni scatto di rotella pesa uguale), più la correzione a mano,
# sempre dentro PITCH_NEAR_DEG..PITCH_FAR_DEG.
func _current_pitch_deg() -> float:
	var t := clampf(log(_distance / MIN_DISTANCE) / log(MAX_DISTANCE / MIN_DISTANCE), 0.0, 1.0)
	return clampf(lerpf(PITCH_NEAR_DEG, PITCH_FAR_DEG, t) + _pitch_offset_deg, PITCH_NEAR_DEG, PITCH_FAR_DEG)
