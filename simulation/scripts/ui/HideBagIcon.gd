class_name HideBagIcon
extends Control

# Icona disegnata "sacca di pelle" (2026-09-27, richiesta utente): un sacchetto panciuto color cuoio, con il collo
# arricciato stretto da un laccio chiaro che termina con due capi pendenti. Stesso schema di HideIcon/BoneAwlIcon:
# solo _draw(), coordinate relative, nessun randf(). draw_into (statica) condivisa con DepositStorageIcons.

const BAG_COLOR := Color(0.66, 0.48, 0.30, 1.0)
const BAG_DARK_COLOR := Color(0.42, 0.29, 0.17, 1.0)
const LACE_COLOR := Color(0.90, 0.82, 0.62, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna la sacca dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(x: float, y: float) -> Vector2: return origin + Vector2(x * area.x, y * area.y)
	var line_width: float = minf(area.x, area.y) * 0.05
	# Corpo: pancia larga in basso, che si stringe verso il collo.
	var body := PackedVector2Array([
		p.call(0.40, 0.34), p.call(0.60, 0.34), p.call(0.72, 0.44), p.call(0.82, 0.60),
		p.call(0.82, 0.76), p.call(0.72, 0.88), p.call(0.50, 0.92), p.call(0.28, 0.88),
		p.call(0.18, 0.76), p.call(0.18, 0.60), p.call(0.28, 0.44),
	])
	canvas.draw_colored_polygon(body, BAG_COLOR)
	var closed_body := body.duplicate()
	closed_body.append(body[0])
	canvas.draw_polyline(closed_body, BAG_DARK_COLOR, line_width, true)
	# Collo arricciato sopra il laccio.
	var neck := PackedVector2Array([
		p.call(0.42, 0.30), p.call(0.34, 0.12), p.call(0.46, 0.18), p.call(0.54, 0.10),
		p.call(0.58, 0.18), p.call(0.68, 0.12), p.call(0.58, 0.30),
	])
	canvas.draw_colored_polygon(neck, BAG_COLOR)
	var closed_neck := neck.duplicate()
	closed_neck.append(neck[0])
	canvas.draw_polyline(closed_neck, BAG_DARK_COLOR, line_width, true)
	# Laccio: giro attorno al collo e due capi pendenti.
	canvas.draw_line(p.call(0.36, 0.32), p.call(0.64, 0.32), LACE_COLOR, line_width * 1.4, true)
	canvas.draw_line(p.call(0.52, 0.32), p.call(0.60, 0.50), LACE_COLOR, line_width, true)
	canvas.draw_line(p.call(0.52, 0.32), p.call(0.66, 0.44), LACE_COLOR, line_width, true)
