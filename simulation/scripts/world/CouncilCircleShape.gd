class_name CouncilCircleShape
extends RefCounted

# Cerchio del consiglio (council_circle, 2026-10-26, richiesta utente): 2x2, un cerchio ma costruito, non un mucchio di sassi
# come il cerchio di sassi. Su terra battuta (niente lastricato): anello di pietre sbozzate, in piedi e a passo regolare;
# dentro, sul terreno calpestato, un giro di lastre piatte dove siedono gli anziani, rivolte al centro; al centro la pietra
# piatta di chi parla. Forme leggermente irregolari (seme fisso per pietra, stabili tra un ridisegno e l'altro): lavoro a
# mano, non squadrato. Niente focolare.
# Un solo disegno per mappa (MicroCellRenderer._draw_buildings), anteprima (BuildingGhost) e icona (CouncilCircleIcon),
# stesso schema di FeastGroundShape. Nessuna porta e nessuna rotazione.
#
# draw(canvas, center, rect_px, invalid, alpha, with_ground): `center` = centro del quadrato nello spazio del canvas,
# `rect_px` = lato in pixel (sulla mappa 2 microcelle = 20 px; le misure sotto sono frazioni del lato); `invalid` =
# anteprima su una posizione non edificabile (tinta rossastra); `with_ground` false sulla mappa, dove il fondo sono i tile
# di terra battuta del renderer (il cerchio calpestato si disegna comunque, è parte dell'edificio).

const TYPE := "council_circle"
const GROUND_INSET: float = 0.03
# Terreno calpestato dentro l'anello, un po' più scuro della terra battuta.
const TRAMPLED_RADIUS: float = 0.34
const TRAMPLED_COLOR := Color(0.0, 0.0, 0.0, 0.10)
# Anello: pietre in piedi, rettangoli sbozzati orientati lungo la circonferenza.
const RING_RADIUS: float = 0.41
const RING_STONE_COUNT: int = 12
const RING_STONE_LENGTH: float = 0.10
const RING_STONE_DEPTH: float = 0.07
# Sedili: lastre piatte più lunghe che larghe, lungo un cerchio interno.
const SEAT_RADIUS: float = 0.22
const SEAT_COUNT: int = 6
const SEAT_LENGTH: float = 0.14
const SEAT_DEPTH: float = 0.06
# Pietra di chi parla, al centro.
const SPEAKER_STONE_RADIUS: float = 0.065
# Irregolarità: scarto massimo dei vertici (frazione della misura) e dell'angolo di ogni pietra (radianti).
const VERTEX_JITTER: float = 0.14
const ANGLE_JITTER: float = 0.04
const OUTLINE_WIDTH: float = 0.008
# Ombra in basso a destra: le pietre dell'anello sono in piedi, i sedili bassi.
const RING_SHADOW_OFFSET := Vector2(0.018, 0.024)
const SEAT_SHADOW_OFFSET := Vector2(0.010, 0.013)
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.28)
const RING_STONE_COLORS: Array[Color] = [
	Color(0.60, 0.59, 0.56, 1.0), Color(0.66, 0.64, 0.60, 1.0), Color(0.55, 0.54, 0.52, 1.0),
]
const SEAT_COLOR := Color(0.70, 0.67, 0.61, 1.0)
const SPEAKER_STONE_COLOR := Color(0.62, 0.60, 0.56, 1.0)
const STONE_OUTLINE := Color(0.36, 0.34, 0.31, 1.0)
const INVALID_TINT := Color(1.0, 0.45, 0.4, 1.0)


static func draw(
	canvas: CanvasItem, center: Vector2, rect_px: Vector2, invalid: bool, alpha: float = 1.0, with_ground: bool = true
) -> void:
	var side: float = minf(rect_px.x, rect_px.y)
	var tint := func(color: Color) -> Color:
		var result: Color = color * INVALID_TINT if invalid else color
		result.a = color.a * alpha
		return result
	var line_width: float = maxf(OUTLINE_WIDTH * side, 0.35)

	if with_ground:
		var inset := rect_px * GROUND_INSET
		canvas.draw_rect(Rect2(center - rect_px / 2.0 + inset, rect_px - inset * 2.0), tint.call(DirtGroundPattern.BASE_COLOR), true)
	canvas.draw_circle(center, TRAMPLED_RADIUS * side, tint.call(TRAMPLED_COLOR))

	for i in range(RING_STONE_COUNT):
		var angle: float = TAU * float(i) / float(RING_STONE_COUNT)
		_stone(canvas, center, angle, RING_RADIUS * side, RING_STONE_LENGTH * side, RING_STONE_DEPTH * side, 7200 + i,
			RING_STONE_COLORS[i % RING_STONE_COLORS.size()], RING_SHADOW_OFFSET * side, tint, line_width)
	# Sedili sfalsati di mezzo passo rispetto ai punti cardinali, come attorno a un fuoco.
	for i in range(SEAT_COUNT):
		var angle: float = TAU * (float(i) + 0.5) / float(SEAT_COUNT)
		_stone(canvas, center, angle, SEAT_RADIUS * side, SEAT_LENGTH * side, SEAT_DEPTH * side, 7300 + i,
			SEAT_COLOR, SEAT_SHADOW_OFFSET * side, tint, line_width)

	# Pietra di chi parla: piatta, quasi tonda.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7400
	var speaker := PackedVector2Array()
	for v in range(9):
		speaker.append(center + Vector2.from_angle(TAU * float(v) / 9.0) * SPEAKER_STONE_RADIUS * side * rng.randf_range(0.88, 1.08))
	_polygon(canvas, speaker, SPEAKER_STONE_COLOR, SEAT_SHADOW_OFFSET * side, tint, line_width)


# Pietra sbozzata: un rettangolo `length` × `depth` a distanza `radius` dal centro, lato lungo lungo la circonferenza, con
# gli angoli smussati e i vertici un po' spostati (seme fisso).
static func _stone(
	canvas: CanvasItem, center: Vector2, angle: float, radius: float, length: float, depth: float, stone_seed: int,
	color: Color, shadow_offset: Vector2, tint: Callable, line_width: float
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = stone_seed
	angle += rng.randf_range(-ANGLE_JITTER, ANGLE_JITTER)
	var radial := Vector2.from_angle(angle)
	var tangent := radial.orthogonal()
	var stone_center: Vector2 = center + radial * radius
	var half_length: float = length / 2.0
	var half_depth: float = depth / 2.0
	var bevel: float = 0.3
	# Ottagono: rettangolo con gli angoli tagliati, in coordinate (lungo la circonferenza, verso l'esterno).
	var corners: Array[Vector2] = [
		Vector2(-half_length * (1.0 - bevel), -half_depth), Vector2(half_length * (1.0 - bevel), -half_depth),
		Vector2(half_length, -half_depth * (1.0 - bevel)), Vector2(half_length, half_depth * (1.0 - bevel)),
		Vector2(half_length * (1.0 - bevel), half_depth), Vector2(-half_length * (1.0 - bevel), half_depth),
		Vector2(-half_length, half_depth * (1.0 - bevel)), Vector2(-half_length, -half_depth * (1.0 - bevel)),
	]
	var points := PackedVector2Array()
	for corner in corners:
		var jittered := Vector2(
			corner.x + rng.randf_range(-VERTEX_JITTER, VERTEX_JITTER) * half_length * 0.5,
			corner.y + rng.randf_range(-VERTEX_JITTER, VERTEX_JITTER) * half_depth,
		)
		points.append(stone_center + tangent * jittered.x + radial * jittered.y)
	_polygon(canvas, points, color, shadow_offset, tint, line_width)


static func _polygon(
	canvas: CanvasItem, points: PackedVector2Array, color: Color, shadow_offset: Vector2, tint: Callable, line_width: float
) -> void:
	var shadow := PackedVector2Array()
	for point in points:
		shadow.append(point + shadow_offset)
	canvas.draw_colored_polygon(shadow, tint.call(SHADOW_COLOR))
	canvas.draw_colored_polygon(points, tint.call(color))
	var outline := points.duplicate()
	outline.append(points[0])
	canvas.draw_polyline(outline, tint.call(STONE_OUTLINE), line_width, true)
