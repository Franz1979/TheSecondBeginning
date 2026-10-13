class_name WorkedHideCapIcon
extends Control

# Icona disegnata del "cappello di pelli lavorate" (worked_hide_cap, 2026-10-11, richiesta utente — secondo livello,
# segnaposto): berretto a cupola con qualche cucitura, bordo folto arrotondato con zigzag e pompon in cima. Toni grigi
# come le altre icone del vestiario. Stesso schema di WorkedHideDressIcon, nessun randf().
#
# draw_into (statica) è la geometria vera, condivisa con DepositStorageIcons (magazzini e mucchi a terra).

const DESIGN_SIZE := Vector2(120.0, 120.0)
const HIDE_COLOR := WorkedHideDressIcon.HIDE_COLOR
const OUTLINE_COLOR := WorkedHideDressIcon.OUTLINE_COLOR
const TRIM_COLOR := WorkedHideDressIcon.TRIM_COLOR
const STITCH_COLOR := WorkedHideDressIcon.STITCH_COLOR

const DOME_START := Vector2(22, 78)
const DOME_SEGMENTS := [[Vector2(22, 22), Vector2(60, 20)], [Vector2(98, 22), Vector2(98, 78)]]
const STITCHES := [
	[Vector2(40, 45), Vector2(46, 45)], [Vector2(64, 38), Vector2(70, 38)], [Vector2(54, 58), Vector2(60, 58)],
	[Vector2(76, 60), Vector2(82, 60)],
]
const BRIM_RECT := Rect2(14, 74, 92, 20)
const POMPON_CENTER := Vector2(60, 18)
const POMPON_RADIUS: float = 6.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var rect := ApparelIcon.fit_aspect(origin, area, 1.0)
	if ApparelIcon.is_small(rect):
		rect = ApparelIcon.shrink(rect, ApparelIcon.SMALL_HEADWEAR_SCALE)
	var unit: float = rect.size.x / DESIGN_SIZE.x
	var line_width: float = maxf(2.0 * unit, 1.0)
	var dome := ApparelIcon.quad_outline(DOME_START, DOME_SEGMENTS, DESIGN_SIZE, rect, 10)
	# Piccola (magazzini, mucchi): cupola e tesa piene con contorno netto (ApparelIcon.is_small).
	if ApparelIcon.is_small(rect):
		ApparelIcon.draw_silhouette(canvas, dome, HIDE_COLOR, OUTLINE_COLOR)
		var small_brim := Rect2(ApparelIcon.map_point(BRIM_RECT.position, DESIGN_SIZE, rect), BRIM_RECT.size * unit)
		canvas.draw_rect(small_brim, TRIM_COLOR)
		canvas.draw_rect(small_brim, OUTLINE_COLOR, false, 1.0)
		return
	canvas.draw_colored_polygon(dome, HIDE_COLOR)
	ApparelIcon.draw_strokes(canvas, STITCHES, DESIGN_SIZE, rect, STITCH_COLOR, line_width)
	var closed := dome.duplicate()
	closed.append(dome[0])
	canvas.draw_polyline(closed, OUTLINE_COLOR, line_width, true)
	var brim := Rect2(ApparelIcon.map_point(BRIM_RECT.position, DESIGN_SIZE, rect), BRIM_RECT.size * unit)
	var brim_style := StyleBoxFlat.new()
	brim_style.bg_color = TRIM_COLOR
	brim_style.set_corner_radius_all(int(roundf(10.0 * unit)))
	brim_style.set_border_width_all(int(maxf(roundf(2.0 * unit), 1.0)))
	brim_style.border_color = OUTLINE_COLOR
	brim_style.anti_aliasing = true
	canvas.draw_style_box(brim_style, brim)
	var zigzag := WorkedHideDressIcon._zigzag(Vector2(18, 80), 17, 5.0, -5.0, DESIGN_SIZE, rect)
	canvas.draw_polyline(zigzag, OUTLINE_COLOR.lerp(TRIM_COLOR, 0.5), line_width * 0.8, true)
	var pompon := ApparelIcon.map_point(POMPON_CENTER, DESIGN_SIZE, rect)
	canvas.draw_circle(pompon, POMPON_RADIUS * unit, TRIM_COLOR)
	canvas.draw_arc(pompon, POMPON_RADIUS * unit, 0.0, TAU, 16, OUTLINE_COLOR, line_width * 0.75, true)
