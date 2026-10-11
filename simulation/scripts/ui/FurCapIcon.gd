class_name FurCapIcon
extends Control

# Icona disegnata del "copricapo di pelliccia" (fur_cap, 2026-10-11, richiesta utente — toni grigi): una cuffia di
# pelo arruffato, cupola irregolare con ciuffi chiari tutt'intorno e qualche ciuffo scuro sul pelo. Stesso schema di
# FurDressIcon: coordinate nello spazio di disegno DESIGN_SIZE (dall'anteprima approvata), nessun randf().
#
# draw_into (statica) è la geometria vera, condivisa con DepositStorageIcons (magazzini e mucchi a terra).

const DESIGN_SIZE := Vector2(120.0, 120.0)
const FUR_COLOR := FurDressIcon.FUR_COLOR
const OUTLINE_COLOR := FurDressIcon.OUTLINE_COLOR
const LIGHT_TUFT_COLOR := FurDressIcon.LIGHT_TUFT_COLOR
const DARK_TUFT_COLOR := FurDressIcon.DARK_TUFT_COLOR

const OUTLINE_START := Vector2(20, 84)
const OUTLINE_SEGMENTS := [
	[Vector2(16, 60), Vector2(26, 42)], [Vector2(38, 22), Vector2(60, 20)], [Vector2(82, 22), Vector2(94, 42)],
	[Vector2(104, 60), Vector2(100, 84)], [Vector2(90, 92), Vector2(80, 88)], [Vector2(70, 94), Vector2(60, 90)],
	[Vector2(50, 94), Vector2(40, 88)], [Vector2(30, 92), Vector2(20, 84)],
]
const LIGHT_TUFTS := [
	[Vector2(22, 86), Vector2(19, 94)], [Vector2(32, 90), Vector2(31, 98)], [Vector2(44, 90), Vector2(44, 99)],
	[Vector2(56, 92), Vector2(56, 100)], [Vector2(66, 92), Vector2(67, 100)], [Vector2(78, 90), Vector2(80, 98)],
	[Vector2(90, 90), Vector2(93, 97)], [Vector2(100, 84), Vector2(104, 91)], [Vector2(24, 46), Vector2(18, 43)],
	[Vector2(34, 30), Vector2(30, 24)], [Vector2(48, 22), Vector2(46, 15)], [Vector2(60, 19), Vector2(60, 12)],
	[Vector2(72, 22), Vector2(74, 15)], [Vector2(86, 30), Vector2(90, 24)], [Vector2(96, 46), Vector2(102, 43)],
]
const DARK_TUFTS := [
	[Vector2(40, 44), Vector2(42, 51)], [Vector2(56, 36), Vector2(57, 43)], [Vector2(72, 42), Vector2(70, 49)],
	[Vector2(46, 62), Vector2(48, 68)], [Vector2(64, 60), Vector2(63, 67)], [Vector2(82, 62), Vector2(80, 68)],
	[Vector2(34, 70), Vector2(36, 76)],
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var rect := ApparelIcon.fit_aspect(origin, area, 1.0)
	var unit: float = rect.size.x / DESIGN_SIZE.x
	var outline := ApparelIcon.quad_outline(OUTLINE_START, OUTLINE_SEGMENTS, DESIGN_SIZE, rect)
	canvas.draw_colored_polygon(outline, FUR_COLOR)
	ApparelIcon.draw_strokes(canvas, DARK_TUFTS, DESIGN_SIZE, rect, DARK_TUFT_COLOR, maxf(2.0 * unit, 1.0))
	var closed := outline.duplicate()
	closed.append(outline[0])
	canvas.draw_polyline(closed, OUTLINE_COLOR, maxf(2.0 * unit, 1.0), true)
	ApparelIcon.draw_strokes(canvas, LIGHT_TUFTS, DESIGN_SIZE, rect, LIGHT_TUFT_COLOR, maxf(2.0 * unit, 1.0))
