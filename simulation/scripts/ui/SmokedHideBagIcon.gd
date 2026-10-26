class_name SmokedHideBagIcon
extends Control

# Icona disegnata "sacca di pelle affumicata" (2026-10-25, richiesta utente — modello più durevole di dried_hide_bag):
# stessa sagoma di DriedHideBagIcon (sacchetto panciuto, collo arricciato, laccio con due capi, cucitura a punti), nel
# bruno scuro della pelle affumicata (lo stesso di SmokedHideIcon) con la cucitura chiara e un ricciolo di fumo sopra il
# collo che la distingue dalle altre due. Solo _draw(), coordinate relative, nessun randf(). draw_into (statica)
# condivisa con DepositStorageIcons.

const BAG_COLOR := Color(0.45, 0.30, 0.17, 1.0)
const BAG_DARK_COLOR := Color(0.24, 0.15, 0.08, 1.0)
const LACE_COLOR := Color(0.82, 0.70, 0.50, 1.0)
const STITCH_COLOR := Color(0.82, 0.70, 0.50, 1.0)
const SMOKE_COLOR := Color(0.70, 0.70, 0.68, 0.85)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna la sacca dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(x: float, y: float) -> Vector2: return origin + Vector2(x * area.x, y * area.y)
	var line_width: float = minf(area.x, area.y) * 0.05
	# Corpo: stessa pancia di DriedHideBagIcon.
	var body := PackedVector2Array([
		p.call(0.40, 0.34), p.call(0.60, 0.34), p.call(0.72, 0.44), p.call(0.82, 0.60),
		p.call(0.82, 0.76), p.call(0.72, 0.88), p.call(0.50, 0.92), p.call(0.28, 0.88),
		p.call(0.18, 0.76), p.call(0.18, 0.60), p.call(0.28, 0.44),
	])
	canvas.draw_colored_polygon(body, BAG_COLOR)
	var closed_body := body.duplicate()
	closed_body.append(body[0])
	canvas.draw_polyline(closed_body, BAG_DARK_COLOR, line_width, true)
	# Cucitura a punti chiara in mezzo alla pancia.
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
	# Laccio chiaro: giro attorno al collo e due capi pendenti.
	canvas.draw_line(p.call(0.36, 0.32), p.call(0.64, 0.32), LACE_COLOR, line_width * 1.4, true)
	canvas.draw_line(p.call(0.52, 0.32), p.call(0.60, 0.50), LACE_COLOR, line_width, true)
	canvas.draw_line(p.call(0.52, 0.32), p.call(0.66, 0.44), LACE_COLOR, line_width, true)
	# Ricciolo di fumo in alto a sinistra del collo.
	canvas.draw_arc(p.call(0.24, 0.20), minf(area.x, area.y) * 0.07, PI * 0.5, PI * 2.0, 10, SMOKE_COLOR, line_width, true)
	canvas.draw_arc(p.call(0.18, 0.08), minf(area.x, area.y) * 0.05, PI * 1.5, PI * 3.0, 8, SMOKE_COLOR, line_width, true)
