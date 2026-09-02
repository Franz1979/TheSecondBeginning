extends Camera2D

const MOVE_SPEED: float = 500.0
const ZOOM_STEP: float = 0.25
const EDGE_PAN_MARGIN: float = 24.0
const EDGE_PAN_MAX_SPEED: float = 500.0
# Il pan si attiva solo dopo una permanenza CONTINUA nel margine per almeno questo tempo (vedi
# _edge_pan_hover_time in _process) — non appena il mouse esce dal margine (o smette di essere
# "candidato" per qualunque motivo, es. entra sulla UI) il timer si azzera. Risolve uno scatto
# indesiderato della camera quando si attraversa il bordo destro della mappa per raggiungere la
# Sidebar (l'unico bordo adiacente a della UI reale, non al vuoto dello schermo): senza questa
# soglia, il solo transito nel margine — anche solo di striscio, in pochi frame — bastava a far
# scattare il pan prima ancora che gui_get_hovered_control() rilevasse il controllo di
# destinazione. Un pan intenzionale (mouse fermo/lento vicino al bordo) supera comunque la soglia
# senza percezione di ritardo; un passaggio veloce verso la UI non la raggiunge mai.
const EDGE_PAN_ACTIVATION_DELAY: float = 0.3

# @export (non const) così ogni scena può stringere/allargare il proprio range di zoom dalla
# .tscn senza toccare questo script condiviso — es. GameScene usa un min_zoom più basso per
# poter ispezionare da vicino l'individuo/le microcelle.
@export var min_zoom: float = 0.4
@export var max_zoom: float = 3.0

var _edge_pan_hover_time: float = 0.0

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
	if edge_pan == Vector2.ZERO:
		_edge_pan_hover_time = 0.0
	else:
		_edge_pan_hover_time += delta
		if _edge_pan_hover_time >= EDGE_PAN_ACTIVATION_DELAY:
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
	# Drag-to-pan col tasto CENTRALE (richiesta utente, 2026-09-02 — mancava, unica modalità di
	# movimento manuale della camera non ancora coperta da WASD/edge-pan; il tasto destro resta
	# escluso apposta, già impegnato per gli ordini di movimento in GameScene). event.relative è
	# già in pixel-schermo per questo frame di InputEventMouseMotion — diviso per zoom (non
	# moltiplicato: zoom > 1 = più vicino = un pixel-schermo copre MENO mondo) così il trascinamento
	# segue il cursore 1:1 in world-space qualunque sia il livello di zoom corrente, esattamente
	# come ci si aspetta da un pan.
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		position -= event.relative / zoom

	if event is InputEventMouseButton:
		# Rotella avanti (WHEEL_UP) avvicina, rotella indietro (WHEEL_DOWN) allontana — invertito
		# rispetto al comportamento originale, confermato con l'utente per tutte le viste (script
		# condiviso).
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom += Vector2(ZOOM_STEP, ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom -= Vector2(ZOOM_STEP, ZOOM_STEP)

		zoom.x = clamp(zoom.x, min_zoom, max_zoom)
		zoom.y = clamp(zoom.y, min_zoom, max_zoom)

	# Zoom immediato al massimo/minimo consentito da questa istanza (min_zoom/max_zoom sopra,
	# quindi per-scena come lo zoom a rotella) — "+" avvicina al massimo, "-" allontana al
	# minimo, stesso verso della rotella invertita. Condiviso da tutte le viste (script comune),
	# innocuo dove non c'è nulla su cui inquadrare da vicino.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
			zoom = Vector2(max_zoom, max_zoom)
		elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
			zoom = Vector2(min_zoom, min_zoom)
