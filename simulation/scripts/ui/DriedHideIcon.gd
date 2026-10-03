class_name DriedHideIcon
extends Control

# Icona provvisoria "pelle essiccata" (2026-10-03, richiesta utente — essiccazione, passo 1): la stessa sagoma della
# pelle (HideIcon) ma più chiara e rigida, tesa su un telaio di due rametti incrociati. Stesso schema di HideIcon:
# draw_into (statica) condivisa con DepositStorageIcons (magazzini e mucchi a terra).

const DRIED_HIDE_COLOR := Color(0.82, 0.70, 0.50, 1.0)
const DRIED_HIDE_DARK_COLOR := Color(0.55, 0.42, 0.26, 1.0)
const FRAME_COLOR := Color(0.40, 0.27, 0.14, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna la pelle essiccata dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(x: float, y: float) -> Vector2: return origin + Vector2(x * area.x, y * area.y)
	var unit: float = minf(area.x, area.y)
	# Telaio sotto la pelle.
	canvas.draw_line(p.call(0.10, 0.10), p.call(0.90, 0.90), FRAME_COLOR, unit * 0.06, true)
	canvas.draw_line(p.call(0.90, 0.10), p.call(0.10, 0.90), FRAME_COLOR, unit * 0.06, true)
	var outline := PackedVector2Array([
		p.call(0.50, 0.16), p.call(0.60, 0.26), p.call(0.80, 0.22), p.call(0.70, 0.40),
		p.call(0.76, 0.60), p.call(0.82, 0.80), p.call(0.62, 0.72), p.call(0.50, 0.86),
		p.call(0.38, 0.72), p.call(0.18, 0.80), p.call(0.24, 0.60), p.call(0.30, 0.40),
		p.call(0.20, 0.22), p.call(0.40, 0.26),
	])
	canvas.draw_colored_polygon(outline, DRIED_HIDE_COLOR)
	var closed := outline.duplicate()
	closed.append(outline[0])
	canvas.draw_polyline(closed, DRIED_HIDE_DARK_COLOR, unit * 0.05, true)
