class_name CommandLessonIcon
extends Node2D

# Icona del comando "lesson" (2026-10-17, richiesta utente — la lezione mostrava la falce di luna dei riti religiosi; "un
# libro o una tavoletta"): tavoletta di pietra con segni incisi, stesso stile delle altre icone di comando disegnate a
# codice. Registrata in IconRegistry.COMMAND_ICON_NODES; origine = centro dell'icona, pixel locali della cella (10 px =
# 1 microcella).

const STONE := Color(0.72, 0.70, 0.64, 1.0)
const STONE_EDGE := Color(0.50, 0.48, 0.44, 1.0)
const MARK := Color(0.30, 0.27, 0.24, 1.0)
const OUTLINE := Color(0.18, 0.14, 0.12, 1.0)
const HALF_SIZE := Vector2(2.1, 2.7)
const OUTLINE_WIDTH_PX: float = 0.3
const MARK_WIDTH_PX: float = 0.28


func _draw() -> void:
	var body := _rounded_rect(HALF_SIZE, 0.7)
	draw_colored_polygon(body, STONE)
	# Bordo inferiore più scuro: spessore della lastra.
	draw_line(Vector2(-HALF_SIZE.x + 0.4, HALF_SIZE.y - 0.15), Vector2(HALF_SIZE.x - 0.4, HALF_SIZE.y - 0.15), STONE_EDGE, 0.4, true)
	var outline := body.duplicate()
	outline.append(body[0])
	draw_polyline(outline, OUTLINE, OUTLINE_WIDTH_PX, true)
	# Segni incisi: tre righe di tacche di lunghezza diversa.
	for row in range(3):
		var y := -1.4 + float(row) * 1.25
		draw_line(Vector2(-1.3, y), Vector2(1.3 - float(row) * 0.5, y), MARK, MARK_WIDTH_PX, true)
		draw_line(Vector2(-1.0 + float(row) * 0.4, y - 0.35), Vector2(-1.0 + float(row) * 0.4, y + 0.35), MARK, MARK_WIDTH_PX, true)


static func _rounded_rect(half_size: Vector2, corner: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var centers := [
		Vector2(half_size.x - corner, -half_size.y + corner), Vector2(half_size.x - corner, half_size.y - corner),
		Vector2(-half_size.x + corner, half_size.y - corner), Vector2(-half_size.x + corner, -half_size.y + corner),
	]
	for i in range(4):
		var start_angle := -PI / 2.0 + float(i) * PI / 2.0
		for step in range(5):
			var angle := start_angle + float(step) / 4.0 * PI / 2.0
			points.append(centers[i] + Vector2(cos(angle), sin(angle)) * corner)
	return points
