class_name BuildingCommandIcon
extends Control

# Icone disegnate della riga comandi del pannello edificio (2026-10-03, richiesta utente — prima erano emoji): stesso
# stile delle icone disegnate degli edifici (HideTentIcon, EarthworkIcon): forme piene con un contorno scuro, scalate
# al proprio rettangolo. Chiare, pensate per lo sfondo scuro dei pulsanti. Un solo script per tutte le icone, scelte
# con `kind`; il pulsante che la contiene la ridisegna cambiando `kind` (Demolisci <-> Annulla cantiere).
# Annullamenti (2026-10-03, richiesta utente): l'icona della cosa annullata con sopra una croce rossa (_draw_cancel_cross)
# — paletti del cantiere, Migliora, dinamite.

const KIND_UPGRADE := "upgrade"
const KIND_EMPTY_ALL := "empty_all"
const KIND_DEMOLISH := "demolish"
const KIND_CANCEL_SITE := "cancel_site"
const KIND_CANCEL_UPGRADE := "cancel_upgrade"
const KIND_CANCEL_DEMOLITION := "cancel_demolition"

# Il disegno è pensato in un quadrato di DRAWING_SPAN unità, scalato al lato minore del rettangolo.
const DRAWING_SPAN: float = 20.0
const OUTLINE_WIDTH: float = 0.9

const OUTLINE := Color(0.14, 0.11, 0.09, 1.0)
const HOUSE_WALL := Color(0.90, 0.84, 0.70, 1.0)
const HOUSE_ROOF := Color(0.78, 0.55, 0.32, 1.0)
const HOUSE_DOOR := Color(0.40, 0.28, 0.16, 1.0)
const ARROW := Color(0.62, 0.90, 0.50, 1.0)
const CRATE_WOOD := Color(0.86, 0.66, 0.40, 1.0)
const CRATE_INSIDE := Color(0.42, 0.29, 0.16, 1.0)
const CRATE_PLANK_LINE := Color(0.55, 0.38, 0.20, 1.0)
const DYNAMITE_RED := Color(0.90, 0.22, 0.18, 1.0)
const DYNAMITE_BAND := Color(0.95, 0.88, 0.70, 1.0)
const FUSE := Color(0.85, 0.80, 0.68, 1.0)
const SPARK_OUTER := Color(1.0, 0.55, 0.12, 1.0)
const SPARK_INNER := Color(1.0, 0.92, 0.45, 1.0)
const CROSS_RED := Color(0.95, 0.32, 0.28, 1.0)
const STAKE_WOOD := Color(0.88, 0.72, 0.48, 1.0)
const STAKE_ROPE := Color(0.92, 0.88, 0.76, 1.0)

var kind: String = KIND_UPGRADE:
	set(value):
		kind = value
		queue_redraw()

var _scale: float = 1.0
var _origin: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	_scale = minf(size.x, size.y) / DRAWING_SPAN
	_origin = size * 0.5 - Vector2(DRAWING_SPAN, DRAWING_SPAN) * 0.5 * _scale
	match kind:
		KIND_UPGRADE:
			_draw_upgrade()
		KIND_EMPTY_ALL:
			_draw_empty_all()
		KIND_DEMOLISH:
			_draw_demolish()
		KIND_CANCEL_SITE:
			_draw_site_stakes()
			_draw_cancel_cross()
		KIND_CANCEL_UPGRADE:
			_draw_upgrade()
			_draw_cancel_cross()
		KIND_CANCEL_DEMOLITION:
			_draw_demolish()
			_draw_cancel_cross()


# Migliora: casa a sinistra, freccia in su a destra.
func _draw_upgrade() -> void:
	_shape([Vector2(1.5, 10.0), Vector2(11.5, 10.0), Vector2(11.5, 18.0), Vector2(1.5, 18.0)], HOUSE_WALL)
	_shape([Vector2(0.3, 10.6), Vector2(6.5, 4.2), Vector2(12.7, 10.6)], HOUSE_ROOF)
	_shape([Vector2(5.4, 13.4), Vector2(7.6, 13.4), Vector2(7.6, 18.0), Vector2(5.4, 18.0)], HOUSE_DOOR)
	_up_arrow(16.3, 2.8, 18.0, 2.9, 1.1)


# Svuota tutto: cassa aperta (coperchio ribaltato a sinistra) con una freccia che esce verso l'alto.
func _draw_empty_all() -> void:
	_shape([Vector2(3.0, 10.0), Vector2(17.0, 10.0), Vector2(16.0, 18.5), Vector2(4.0, 18.5)], CRATE_WOOD)
	draw_line(_p(Vector2(3.6, 14.2)), _p(Vector2(16.5, 14.2)), CRATE_PLANK_LINE, OUTLINE_WIDTH * _scale, true)
	# Bocca della cassa vista dall'alto, scura.
	_shape([Vector2(3.0, 10.0), Vector2(17.0, 10.0), Vector2(15.8, 8.6), Vector2(4.2, 8.6)], CRATE_INSIDE)
	# Coperchio aperto, incernierato sul bordo sinistro.
	_shape([Vector2(3.0, 10.0), Vector2(4.2, 8.6), Vector2(1.6, 3.6), Vector2(0.4, 5.0)], CRATE_WOOD)
	_up_arrow(10.0, 0.6, 12.5, 2.6, 1.0)


# Demolisci: candelotto di dinamite rosso con la miccia accesa.
func _draw_demolish() -> void:
	_shape([Vector2(6.5, 7.5), Vector2(13.5, 7.5), Vector2(13.5, 19.0), Vector2(6.5, 19.0)], DYNAMITE_RED)
	_shape([Vector2(6.5, 11.6), Vector2(13.5, 11.6), Vector2(13.5, 13.4), Vector2(6.5, 13.4)], DYNAMITE_BAND)
	var fuse: PackedVector2Array = PackedVector2Array([
		_p(Vector2(10.0, 7.5)), _p(Vector2(10.3, 5.6)), _p(Vector2(11.6, 4.2)), _p(Vector2(13.6, 3.6)),
	])
	draw_polyline(fuse, OUTLINE, (OUTLINE_WIDTH + 1.2) * _scale, true)
	draw_polyline(fuse, FUSE, 1.2 * _scale, true)
	var spark := _p(Vector2(14.6, 3.2))
	for angle in [0.0, 0.8, 1.6, 2.4, 3.2, 4.0, 4.8, 5.6]:
		var direction := Vector2.from_angle(angle)
		draw_line(spark + direction * 1.4 * _scale, spark + direction * 2.6 * _scale, SPARK_OUTER, 0.7 * _scale, true)
	draw_circle(spark, 1.5 * _scale, SPARK_OUTER)
	draw_circle(spark, 0.8 * _scale, SPARK_INNER)


# Paletti del cantiere: quattro rametti piantati agli angoli di un riquadro visto di sbieco, uniti da una corda.
func _draw_site_stakes() -> void:
	var bases: Array = [Vector2(4.0, 17.5), Vector2(16.0, 17.5), Vector2(6.0, 11.0), Vector2(14.0, 11.0)]
	var heights: Array = [8.0, 8.0, 6.0, 6.0]
	var rope := PackedVector2Array()
	for index in [2, 3, 1, 0, 2]:
		var base: Vector2 = bases[index]
		rope.append(_p(base - Vector2(0.0, float(heights[index]) * 0.75)))
	draw_polyline(rope, OUTLINE, (OUTLINE_WIDTH + 0.8) * _scale, true)
	draw_polyline(rope, STAKE_ROPE, 0.8 * _scale, true)
	for index in bases.size():
		var base: Vector2 = bases[index]
		var height: float = heights[index]
		_shape([
			base + Vector2(-0.9, 0.0), base + Vector2(-0.45, -height), base + Vector2(0.45, -height), base + Vector2(0.9, 0.0),
		], STAKE_WOOD)


# Croce rossa (un "più" ruotato di 45°) con lo stesso contorno, sopra l'icona della cosa annullata.
func _draw_cancel_cross() -> void:
	var arm_half_width: float = 1.4
	var arm_length: float = 8.0
	var a := arm_half_width
	var l := arm_length
	var plus: Array = [
		Vector2(a, -l), Vector2(a, -a), Vector2(l, -a), Vector2(l, a), Vector2(a, a), Vector2(a, l),
		Vector2(-a, l), Vector2(-a, a), Vector2(-l, a), Vector2(-l, -a), Vector2(-a, -a), Vector2(-a, -l),
	]
	var points: Array = []
	for point: Vector2 in plus:
		points.append(point.rotated(PI / 4.0) + Vector2(DRAWING_SPAN, DRAWING_SPAN) * 0.5)
	_shape(points, CROSS_RED)


# Freccia in su, in unità del disegno: punta in (center_x, tip_y), asta fino a bottom_y; punta alta 6.
func _up_arrow(center_x: float, tip_y: float, bottom_y: float, head_half_width: float, shaft_half_width: float) -> void:
	var head_base_y: float = tip_y + 6.0
	_shape([
		Vector2(center_x, tip_y),
		Vector2(center_x + head_half_width, head_base_y),
		Vector2(center_x + shaft_half_width, head_base_y),
		Vector2(center_x + shaft_half_width, bottom_y),
		Vector2(center_x - shaft_half_width, bottom_y),
		Vector2(center_x - shaft_half_width, head_base_y),
		Vector2(center_x - head_half_width, head_base_y),
	], ARROW)


# Poligono pieno con il contorno scuro, in unità del disegno.
func _shape(points: Array, fill: Color) -> void:
	var polygon := PackedVector2Array()
	for point in points:
		polygon.append(_p(point))
	draw_colored_polygon(polygon, fill)
	var outline := polygon.duplicate()
	outline.append(polygon[0])
	draw_polyline(outline, OUTLINE, OUTLINE_WIDTH * _scale, true)


func _p(point: Vector2) -> Vector2:
	return _origin + point * _scale
