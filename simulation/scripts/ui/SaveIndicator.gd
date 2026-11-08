class_name SaveIndicator
extends CanvasLayer

# Rotellina del salvataggio in sovraimpressione (2026-11-08, richiesta utente): compare in alto a sinistra durante ogni
# salvataggio e resta tra un cambio di scena e l'altro, perché è figlia dell'autoload GameSettings. Sta ferma mentre il
# thread principale costruisce i dati (SaveFileWriter fa il resto su un altro thread, e lì gira).
# Si accende da sola quando SaveFileWriter è al lavoro; begin() serve per farla vedere PRIMA della parte bloccante.

const LAYER_ON_TOP := 128
const SPINNER_POSITION := Vector2(16, 16)
const SPINNER_SIZE := 40.0
const SPINNER_WIDTH := 4.0
const SPINNER_ARC := TAU * 0.75
const TURNS_PER_SECOND := 1.2
const COLOR_BACKGROUND := Color(0.0, 0.0, 0.0, 0.55)
const COLOR_ARC := Color(1.0, 1.0, 1.0, 0.95)
# Tempo minimo a schermo: copre i frame prima della partenza del salvataggio ed evita un lampo se finisce subito.
const MIN_VISIBLE_MSEC := 500

static var _instance: SaveIndicator = null

var _spinner: Control
var _angle := 0.0
var _hide_not_before_msec := 0


# Da chiamare con await prima di salvare: mostra la rotellina e lascia che venga disegnata.
static func begin() -> void:
	if _instance == null:
		return
	_instance._show_now()
	await _instance.get_tree().process_frame
	await _instance.get_tree().process_frame


func _ready() -> void:
	_instance = self
	layer = LAYER_ON_TOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_spinner = Control.new()
	_spinner.position = SPINNER_POSITION
	_spinner.size = Vector2.ONE * SPINNER_SIZE
	_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spinner.draw.connect(_on_spinner_draw)
	add_child(_spinner)


func _process(delta: float) -> void:
	var is_busy := SaveFileWriter.is_busy()
	if not visible:
		if is_busy:
			_show_now()
		return
	if not is_busy and Time.get_ticks_msec() >= _hide_not_before_msec:
		visible = false
		return
	_angle = fposmod(_angle + TAU * TURNS_PER_SECOND * delta, TAU)
	_spinner.queue_redraw()


func _show_now() -> void:
	visible = true
	_hide_not_before_msec = Time.get_ticks_msec() + MIN_VISIBLE_MSEC


func _on_spinner_draw() -> void:
	var center := Vector2.ONE * SPINNER_SIZE * 0.5
	var radius := SPINNER_SIZE * 0.5
	_spinner.draw_circle(center, radius, COLOR_BACKGROUND)
	_spinner.draw_arc(center, radius * 0.62, _angle, _angle + SPINNER_ARC, 32, COLOR_ARC, SPINNER_WIDTH, true)
