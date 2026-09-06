class_name PieChart
extends Control

# Componente grafico a torta generico e riusabile (Step 6a del piano statistiche, 2026-09-06) —
# stesso principio di LineChart.gd: Control con _draw() immediate-mode, nessuna scena propria,
# nessuna logica di dominio, nessuna assunzione sui nomi/tipi delle chiavi (str(key) generico —
# oggi fasce d'età come chiavi String, domani cause di morte, qualunque altra distribuzione
# categorica futura senza toccare questo file). Riceve un Dictionary chiave->valore numerico via
# set_data() e disegna una torta con una fetta per chiave, proporzionale al valore sul totale.
#
# Layout: torta a sinistra (quadrata, centrata verticalmente) + legenda a destra (un rigo per
# chiave: quadratino colore + "chiave: valore (percentuale%)") — preferito a etichette incollate
# sul bordo di ogni fetta, che con fette piccole si accavallerebbero o uscirebbero illeggibili.

const PALETTE := [
	Color(0.35, 0.65, 0.95, 1.0),
	Color(0.95, 0.55, 0.35, 1.0),
	Color(0.45, 0.85, 0.55, 1.0),
	Color(0.85, 0.45, 0.85, 1.0),
	Color(0.95, 0.85, 0.35, 1.0),
	Color(0.55, 0.55, 0.95, 1.0),
	Color(0.95, 0.45, 0.55, 1.0),
	Color(0.45, 0.85, 0.85, 1.0),
]

const PLACEHOLDER_COLOR := Color(0.6, 0.6, 0.6, 1.0)
const LABEL_COLOR := Color(0.85, 0.85, 0.85, 1.0)
const LABEL_FONT_SIZE: int = 11
const LEGEND_SWATCH_SIZE: float = 10.0
const LEGEND_ROW_HEIGHT: float = 16.0
const PADDING: float = 8.0

var _data: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(0, 140)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


# Sostituisce interamente i dati mostrati e ridisegna — unico metodo pubblico, stesso principio di
# LineChart.set_data(). `data` può essere vuoto o avere tutti i valori a zero: entrambi i casi
# sono gestiti in _draw() senza eccezioni/divisioni per zero (vedi il controllo su `total` sotto).
func set_data(data: Dictionary) -> void:
	_data = data
	queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var font := ThemeDB.fallback_font

	var keys := _data.keys()
	var total := 0.0
	for key in keys:
		total += maxf(float(_data[key]), 0.0)

	# Nessuna chiave, o tutte a zero (es. fasce d'età prima che esista un solo individuo) —
	# stesso placeholder di LineChart con zero punti, nessuna torta vuota disegnata.
	if keys.is_empty() or total <= 0.0:
		_draw_placeholder_text(font, "Dati insufficienti")
		return

	# Torta = quadrato a sinistra (mai più larga della metà del Control, mai più alta dell'altezza
	# disponibile) — il resto della larghezza è per la legenda.
	var pie_diameter := minf(size.y - PADDING * 2.0, size.x * 0.5)
	var pie_radius := pie_diameter * 0.5
	var pie_center := Vector2(PADDING + pie_radius, size.y * 0.5)
	var legend_x := PADDING + pie_diameter + PADDING * 2.0

	var start_angle := -PI / 2.0 # ore 12, prima fetta verso l'alto, poi in senso orario
	var color_index := 0
	var legend_y := PADDING
	for key in keys:
		var value := maxf(float(_data[key]), 0.0)
		var fraction := value / total
		var color: Color = PALETTE[color_index % PALETTE.size()]
		color_index += 1
		if value > 0.0:
			var slice_angle := fraction * TAU
			_draw_pie_slice(pie_center, pie_radius, start_angle, slice_angle, color)
			start_angle += slice_angle
		# Riga di legenda comunque disegnata anche per una chiave a valore 0 (es. una fascia d'età
		# senza individui) — stesso principio già seguito da StatisticsPanel per le cause di morte:
		# una categoria a zero compare comunque, invece di sparire silenziosamente dalla lista.
		legend_y = _draw_legend_row(font, legend_x, legend_y, color, key, value, fraction)


func _draw_pie_slice(center: Vector2, radius: float, start_angle: float, slice_angle: float, color: Color) -> void:
	# Densità dell'arco proporzionale all'ampiezza della fetta (8 segmenti/radiante) — una fetta
	# piccola non ha bisogno di tanti segmenti quanto una quasi intera.
	var segments := maxi(1, int(ceil(absf(slice_angle) * 8.0)))
	var points := PackedVector2Array()
	points.append(center)
	for i in range(segments + 1):
		var angle := start_angle + slice_angle * (float(i) / float(segments))
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)


func _draw_legend_row(font: Font, x: float, y: float, color: Color, key: Variant, value: float, fraction: float) -> float:
	draw_rect(Rect2(x, y, LEGEND_SWATCH_SIZE, LEGEND_SWATCH_SIZE), color)
	var label_text := "%s: %s (%.0f%%)" % [str(key), _format_value(value), fraction * 100.0]
	draw_string(
		font, Vector2(x + LEGEND_SWATCH_SIZE + 4.0, y + LEGEND_SWATCH_SIZE), label_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, LABEL_COLOR
	)
	return y + LEGEND_ROW_HEIGHT


# Interi senza decimali (il caso comune: conteggi) — stessa funzione/motivo di LineChart._format_value.
func _format_value(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return "%.1f" % value


func _draw_placeholder_text(font: Font, text: String) -> void:
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
	draw_string(font, (size - text_size) / 2.0, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, PLACEHOLDER_COLOR)
