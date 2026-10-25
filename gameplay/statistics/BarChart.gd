class_name BarChart
extends Control

# Grafico a barre verticali generico (2026-10-25, richiesta utente — scheda Parametri delle statistiche): stesso
# principio di LineChart/PieChart, Control con _draw() immediate-mode e nessuna logica di dominio. Ogni barra è
# {"label": String, "value": float in 0-100, "color": Color, "tooltip": String}; l'asse va sempre da 0 a 100 (%).
# Il tooltip della barra sotto il mouse viene da _get_tooltip, con la stessa geometria di _draw (stesso schema di
# SeasonProgressBar).

const AXIS_COLOR := Color(0.5, 0.5, 0.5, 0.6)
const GRID_COLOR := Color(0.5, 0.5, 0.5, 0.22)
const LABEL_COLOR := Color(0.8, 0.8, 0.8, 1.0)
const GRID_LABEL_COLOR := Color(0.65, 0.65, 0.65, 0.85)
const LABEL_FONT_SIZE: int = 11
const GRID_LABEL_FONT_SIZE: int = 9
const PADDING_LEFT: float = 32.0
const PADDING_RIGHT: float = 8.0
const PADDING_TOP: float = 16.0
const PADDING_BOTTOM: float = 20.0
# Larghezza della barra rispetto al suo spazio.
const BAR_WIDTH_RATIO: float = 0.6
const GRID_STEPS: Array[float] = [25.0, 50.0, 75.0, 100.0]

var _bars: Array[Dictionary] = []


func _ready() -> void:
	custom_minimum_size = Vector2(0, 150)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_bars(bars: Array[Dictionary]) -> void:
	_bars = bars
	queue_redraw()


func _plot_rect() -> Rect2:
	return Rect2(PADDING_LEFT, PADDING_TOP, maxf(size.x - PADDING_LEFT - PADDING_RIGHT, 0.0), maxf(size.y - PADDING_TOP - PADDING_BOTTOM, 0.0))


# Rettangolo della barra `index` (altezza proporzionale al valore) e spazio che le spetta (per il tooltip).
func _bar_slot(plot: Rect2, index: int) -> Rect2:
	var slot_width := plot.size.x / maxf(_bars.size(), 1)
	return Rect2(plot.position.x + slot_width * index, plot.position.y, slot_width, plot.size.y)


func _draw() -> void:
	var plot := _plot_rect()
	if plot.size.x <= 0.0 or plot.size.y <= 0.0:
		return
	var font := get_theme_default_font()
	var bottom := plot.end.y
	for step in GRID_STEPS:
		var y := bottom - plot.size.y * step / 100.0
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), GRID_COLOR)
		draw_string(font, Vector2(2.0, y + GRID_LABEL_FONT_SIZE * 0.4), "%d%%" % int(step), HORIZONTAL_ALIGNMENT_LEFT, -1, GRID_LABEL_FONT_SIZE, GRID_LABEL_COLOR)
	draw_line(Vector2(plot.position.x, bottom), Vector2(plot.end.x, bottom), AXIS_COLOR)
	for i in range(_bars.size()):
		var bar: Dictionary = _bars[i]
		var slot := _bar_slot(plot, i)
		var value := clampf(float(bar.get("value", 0.0)), 0.0, 100.0)
		var bar_width := slot.size.x * BAR_WIDTH_RATIO
		var bar_height := plot.size.y * value / 100.0
		var bar_x := slot.position.x + (slot.size.x - bar_width) / 2.0
		draw_rect(Rect2(bar_x, bottom - bar_height, bar_width, bar_height), bar.get("color", Color.WHITE))
		var value_text := "%d%%" % roundi(value)
		draw_string(font, Vector2(slot.position.x, bottom - bar_height - 3.0), value_text, HORIZONTAL_ALIGNMENT_CENTER, slot.size.x, GRID_LABEL_FONT_SIZE, LABEL_COLOR)
		draw_string(font, Vector2(slot.position.x, bottom + LABEL_FONT_SIZE + 3.0), String(bar.get("label", "")), HORIZONTAL_ALIGNMENT_CENTER, slot.size.x, LABEL_FONT_SIZE, LABEL_COLOR)


func _get_tooltip(at_position: Vector2) -> String:
	var plot := _plot_rect()
	for i in range(_bars.size()):
		if _bar_slot(plot, i).grow_individual(0.0, PADDING_TOP, 0.0, PADDING_BOTTOM).has_point(at_position):
			return TooltipText.wrap(String(_bars[i].get("tooltip", "")))
	return ""
