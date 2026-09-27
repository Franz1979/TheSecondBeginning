class_name PlaceholderBuildingShapes
extends RefCounted

# Disegni PROVVISORI degli edifici segnaposto (2026-09-26, richiesta utente — graticcio, affumicatoio, sepoltura,
# vallo di terra: esistono solo nell'albero delle idee e nella barra di costruzione, senza ricette né funzioni).
# Un solo disegno condiviso da mappa (MicroCellRenderer._draw_buildings), anteprima di piazzamento
# (BuildingGhost) e icona della barra (le *Icon.gd di questi tipi), invece di tre copie. Tutti senza porta
# (has_door = false): nessuna rotazione.
#
# draw(canvas, type, center, invalid, scale): `center` è il centro della microcella nello spazio del canvas,
# `scale` = pixel per unità di disegno (1.0 sulla mappa: una microcella = 10 px); `invalid` = anteprima su una
# posizione non edificabile (tinta rossastra semitrasparente, come le altre sagome di BuildingGhost).

const TYPES: Array[String] = ["drying_rack", "smokehouse", "burial", "earthwork"]

const WOOD := Color(0.55, 0.38, 0.20, 1.0)
const WOOD_DARK := Color(0.36, 0.24, 0.12, 1.0)
const MEAT_STRIP := Color(0.62, 0.20, 0.16, 1.0)
const SMOKEHOUSE_WALL := Color(0.40, 0.30, 0.22, 1.0)
const SMOKE := Color(0.78, 0.78, 0.76, 0.75)
const EARTH := Color(0.47, 0.36, 0.24, 1.0)
const EARTH_DARK := Color(0.33, 0.25, 0.16, 1.0)
const STONE := Color(0.62, 0.61, 0.58, 1.0)
const OUTLINE := Color(0.18, 0.14, 0.12, 1.0)
const INVALID_TINT := Color(0.9, 0.25, 0.25, 0.55)


static func draw(canvas: CanvasItem, building_type: String, center: Vector2, invalid: bool = false, scale: float = 1.0) -> void:
	var tint := func(color: Color) -> Color: return INVALID_TINT if invalid else color
	var p := func(x: float, y: float) -> Vector2: return center + Vector2(x, y) * scale
	var w := func(width: float) -> float: return width * scale
	match building_type:
		"drying_rack":
			# Due pali, una traversa e quattro strisce di carne appese.
			canvas.draw_line(p.call(-3.2, 3.0), p.call(-3.2, -2.6), tint.call(WOOD_DARK), w.call(0.6), true)
			canvas.draw_line(p.call(3.2, 3.0), p.call(3.2, -2.6), tint.call(WOOD_DARK), w.call(0.6), true)
			canvas.draw_line(p.call(-3.8, -2.4), p.call(3.8, -2.4), tint.call(WOOD), w.call(0.6), true)
			for x in [-2.2, -0.8, 0.6, 2.0]:
				canvas.draw_line(p.call(x, -2.2), p.call(x + 0.2, 0.6), tint.call(MEAT_STRIP), w.call(0.7), true)
		"smokehouse":
			# Capanno conico di rami chiuso, con fumo che esce dalla cima.
			var body := PackedVector2Array([p.call(-3.4, 3.0), p.call(0.0, -2.8), p.call(3.4, 3.0)])
			canvas.draw_colored_polygon(body, tint.call(SMOKEHOUSE_WALL))
			var outline := body.duplicate()
			outline.append(body[0])
			canvas.draw_polyline(outline, tint.call(OUTLINE), w.call(0.3), true)
			canvas.draw_line(p.call(-1.2, 3.0), p.call(0.0, -1.0), tint.call(WOOD_DARK), w.call(0.3), true)
			canvas.draw_line(p.call(1.2, 3.0), p.call(0.0, -1.0), tint.call(WOOD_DARK), w.call(0.3), true)
			if not invalid:
				canvas.draw_circle(p.call(0.4, -3.6), w.call(0.8), SMOKE)
				canvas.draw_circle(p.call(1.3, -4.4), w.call(0.6), SMOKE)
		"burial":
			# Tumulo ovale di terra con un cerchio di pietre e una pietra ritta.
			canvas.draw_set_transform(center, 0.0, Vector2(1.0, 0.6))
			canvas.draw_circle(Vector2.ZERO, w.call(3.6), tint.call(EARTH))
			canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			for i in range(8):
				var angle := TAU * float(i) / 8.0
				canvas.draw_circle(p.call(cos(angle) * 3.6, sin(angle) * 2.2), w.call(0.45), tint.call(STONE))
			canvas.draw_rect(Rect2(p.call(-0.5, -2.8), Vector2(1.0, 2.6) * scale), tint.call(STONE))
		"earthwork":
			# Argine di terra ad arco, con il ciglio più scuro.
			var ridge := PackedVector2Array()
			for i in range(9):
				var t := float(i) / 8.0
				ridge.append(p.call(-4.0 + 8.0 * t, 1.0 - sin(t * PI) * 2.6))
			canvas.draw_polyline(ridge, tint.call(EARTH), w.call(2.2), true)
			canvas.draw_polyline(ridge, tint.call(EARTH_DARK), w.call(0.5), true)
