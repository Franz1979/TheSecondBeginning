class_name FishMeatIcon
extends Control

# Icona disegnata "pesce crudo" (2026-10-31, richiesta utente — pesca): trota di profilo, dorso scuro e ventre chiaro
# argentato, coda a forcella, pinna dorsale, occhio, e qualche puntino sul fianco. Stessi toni dei pesci sulla mappa
# (MicroCellRenderer.COLOR_FISH_BODY). Solo _draw(), coordinate relative, nessun randf(). draw_into (statica)
# condivisa con DepositStorageIcons.

const BACK_COLOR := Color(0.36, 0.45, 0.52, 1.0)
const BELLY_COLOR := Color(0.78, 0.82, 0.84, 1.0)
const DARK_COLOR := Color(0.20, 0.26, 0.31, 1.0)
const SPOT_COLOR := Color(0.24, 0.30, 0.34, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna il pesce dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	draw_fish(canvas, origin, area, BACK_COLOR, BELLY_COLOR, DARK_COLOR, SPOT_COLOR)


# Sagoma del pesce con i colori dati (2026-10-31): condivisa con le icone del pesce cotto, essiccato e affumicato
# (CookedFishIcon, DriedFishIcon, SmokedFishIcon), che ci aggiungono i loro dettagli. `spot_color` trasparente = niente
# puntini.
static func draw_fish(
	canvas: CanvasItem, origin: Vector2, area: Vector2, back_color: Color, belly_color: Color, dark_color: Color, spot_color: Color
) -> void:
	var p := func(x: float, y: float) -> Vector2: return origin + Vector2(x * area.x, y * area.y)
	var unit: float = minf(area.x, area.y)

	# Coda a forcella, a sinistra.
	canvas.draw_colored_polygon(PackedVector2Array([
		p.call(0.26, 0.50), p.call(0.08, 0.32), p.call(0.14, 0.50), p.call(0.08, 0.68),
	]), back_color)
	# Pinna dorsale.
	canvas.draw_colored_polygon(PackedVector2Array([
		p.call(0.44, 0.38), p.call(0.52, 0.26), p.call(0.60, 0.37),
	]), back_color)
	# Corpo: metà alta scura (dorso), metà bassa chiara (ventre), muso a destra.
	var back := PackedVector2Array([
		p.call(0.24, 0.50), p.call(0.34, 0.40), p.call(0.52, 0.35), p.call(0.72, 0.37),
		p.call(0.86, 0.44), p.call(0.92, 0.50),
	])
	var belly := PackedVector2Array([
		p.call(0.92, 0.50), p.call(0.86, 0.57), p.call(0.70, 0.63), p.call(0.50, 0.64),
		p.call(0.34, 0.60), p.call(0.24, 0.50),
	])
	canvas.draw_colored_polygon(back, back_color)
	canvas.draw_colored_polygon(belly, belly_color)
	var outline := back.duplicate()
	outline.append_array(belly)
	canvas.draw_polyline(outline, dark_color, unit * 0.03, true)
	# Puntini sul fianco.
	if spot_color.a > 0.0:
		for spot in [Vector2(0.42, 0.44), Vector2(0.52, 0.42), Vector2(0.62, 0.45), Vector2(0.48, 0.50)]:
			canvas.draw_circle(p.call(spot.x, spot.y), unit * 0.018, spot_color)
	# Opercolo e occhio.
	canvas.draw_arc(p.call(0.76, 0.50), unit * 0.08, -PI * 0.35, PI * 0.35, 8, dark_color, unit * 0.02, true)
	canvas.draw_circle(p.call(0.84, 0.46), unit * 0.03, dark_color)
