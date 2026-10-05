class_name DriedHideBagIcon
extends Control

# Icona disegnata "sacca di pelle essiccata" (2026-10-04, richiesta utente — modello migliore di hide_bag): stessa sagoma
# di HideBagIcon (sacchetto panciuto, collo arricciato, laccio con due capi), nel colore chiaro della pelle essiccata
# (lo stesso di DriedHideIcon) e con una cucitura a punti sulla pancia che la distingue dalla sacca semplice. Solo
# _draw(), coordinate relative, nessun randf(). draw_into (statica) condivisa con DepositStorageIcons.

const BAG_COLOR := Color(0.82, 0.70, 0.50, 1.0)
const BAG_DARK_COLOR := Color(0.55, 0.42, 0.26, 1.0)
const LACE_COLOR := Color(0.42, 0.29, 0.17, 1.0)
const STITCH_COLOR := Color(0.42, 0.29, 0.17, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna la sacca dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(x: float, y: float) -> Vector2: return origin + Vector2(x * area.x, y * area.y)
	var line_width: float = minf(area.x, area.y) * 0.05
	# Corpo: stessa pancia di HideBagIcon.
	var body := PackedVector2Array([
		p.call(0.40, 0.34), p.call(0.60, 0.34), p.call(0.72, 0.44), p.call(0.82, 0.60),
		p.call(0.82, 0.76), p.call(0.72, 0.88), p.call(0.50, 0.92), p.call(0.28, 0.88),
		p.call(0.18, 0.76), p.call(0.18, 0.60), p.call(0.28, 0.44),
	])
	canvas.draw_colored_polygon(body, BAG_COLOR)
	var closed_body := body.duplicate()
	closed_body.append(body[0])
	canvas.draw_polyline(closed_body, BAG_DARK_COLOR, line_width, true)
	# Cucitura a punti in mezzo alla pancia: il segno del modello migliore.
	for i in range(5):
		var y: float = 0.50 + 0.08 * float(i)
		canvas.draw_line(p.call(0.46, y), p.call(0.54, y + 0.04), STITCH_COLOR, line_width * 0.9, true)
	# Collo arricciato sopra il laccio.
	var neck := PackedVector2Array([
		p.call(0.42, 0.30), p.call(0.34, 0.12), p.call(0.46, 0.18), p.call(0.54, 0.10),
		p.call(0.58, 0.18), p.call(0.68, 0.12), p.call(0.58, 0.30),
	])
	canvas.draw_colored_polygon(neck, BAG_COLOR)
	var closed_neck := neck.duplicate()
	closed_neck.append(neck[0])
	canvas.draw_polyline(closed_neck, BAG_DARK_COLOR, line_width, true)
	# Laccio scuro (la sacca semplice ce l'ha chiaro): giro attorno al collo e due capi pendenti.
	canvas.draw_line(p.call(0.36, 0.32), p.call(0.64, 0.32), LACE_COLOR, line_width * 1.4, true)
	canvas.draw_line(p.call(0.52, 0.32), p.call(0.60, 0.50), LACE_COLOR, line_width, true)
	canvas.draw_line(p.call(0.52, 0.32), p.call(0.66, 0.44), LACE_COLOR, line_width, true)
