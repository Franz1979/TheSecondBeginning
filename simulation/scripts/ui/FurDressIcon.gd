class_name FurDressIcon
extends Control

# Icona disegnata del "vestito di pelliccia" (fur_dress, 2026-10-11, richiesta utente — "roba di pelliccia con il
# pelo", toni grigi per non confondersi con le altre icone): una pelle col pelo drappeggiata, dal contorno irregolare a
# curve, con ciuffi chiari lungo i bordi, qualche ciuffo scuro sul pelo e un laccio chiaro in vita. Proporzioni fisse
# (DESIGN_SIZE, le stesse del riquadro dello slot del corpo): centrata nei riquadri quadrati. Coordinate nello spazio
# di disegno DESIGN_SIZE (dall'anteprima approvata), nessun randf().
#
# draw_into (statica) è la geometria vera, condivisa con DepositStorageIcons (magazzini e mucchi a terra).

const DESIGN_SIZE := Vector2(108.0, 204.0)
const FUR_COLOR := Color(0.46, 0.42, 0.38, 1.0)
const OUTLINE_COLOR := Color(0.22, 0.20, 0.18, 1.0)
const LIGHT_TUFT_COLOR := Color(0.68, 0.64, 0.58, 1.0)
const DARK_TUFT_COLOR := Color(0.33, 0.30, 0.27, 1.0)
const CORD_COLOR := Color(0.76, 0.72, 0.62, 1.0)

const OUTLINE_START := Vector2(30, 14)
const OUTLINE_SEGMENTS := [
	[Vector2(40, 22), Vector2(54, 24)], [Vector2(68, 22), Vector2(78, 14)], [Vector2(92, 18), Vector2(98, 34)],
	[Vector2(96, 46), Vector2(90, 50)], [Vector2(92, 80), Vector2(88, 100)], [Vector2(96, 140), Vector2(98, 176)],
	[Vector2(86, 184), Vector2(74, 180)], [Vector2(64, 186), Vector2(54, 182)], [Vector2(42, 188), Vector2(32, 180)],
	[Vector2(20, 186), Vector2(10, 176)], [Vector2(14, 140), Vector2(20, 100)], [Vector2(16, 80), Vector2(18, 50)],
	[Vector2(12, 46), Vector2(10, 34)], [Vector2(16, 18), Vector2(30, 14)],
]
# Ciuffi chiari che sporgono dai bordi (orlo, spalle, fianchi).
const LIGHT_TUFTS := [
	[Vector2(12, 172), Vector2(8, 180)], [Vector2(20, 178), Vector2(18, 187)], [Vector2(30, 180), Vector2(30, 189)],
	[Vector2(40, 183), Vector2(41, 191)], [Vector2(52, 182), Vector2(52, 191)], [Vector2(62, 183), Vector2(64, 191)],
	[Vector2(72, 180), Vector2(75, 189)], [Vector2(84, 181), Vector2(88, 188)], [Vector2(95, 174), Vector2(100, 181)],
	[Vector2(10, 36), Vector2(4, 33)], [Vector2(14, 26), Vector2(9, 20)], [Vector2(24, 16), Vector2(21, 9)],
	[Vector2(84, 16), Vector2(87, 9)], [Vector2(94, 26), Vector2(99, 20)], [Vector2(98, 36), Vector2(104, 33)],
	[Vector2(18, 60), Vector2(12, 60)], [Vector2(17, 80), Vector2(11, 82)], [Vector2(19, 100), Vector2(13, 103)],
	[Vector2(16, 130), Vector2(10, 132)], [Vector2(13, 152), Vector2(7, 154)], [Vector2(90, 60), Vector2(96, 60)],
	[Vector2(91, 80), Vector2(97, 82)], [Vector2(89, 100), Vector2(95, 103)], [Vector2(93, 130), Vector2(99, 132)],
	[Vector2(96, 152), Vector2(102, 154)],
]
# Ciuffi scuri sul pelo.
const DARK_TUFTS := [
	[Vector2(34, 50), Vector2(37, 56)], [Vector2(48, 44), Vector2(50, 51)], [Vector2(64, 50), Vector2(62, 56)],
	[Vector2(76, 46), Vector2(73, 52)], [Vector2(40, 70), Vector2(42, 76)], [Vector2(60, 66), Vector2(58, 73)],
	[Vector2(70, 80), Vector2(73, 86)], [Vector2(30, 120), Vector2(33, 127)], [Vector2(46, 128), Vector2(48, 135)],
	[Vector2(64, 122), Vector2(62, 129)], [Vector2(78, 134), Vector2(75, 140)], [Vector2(38, 150), Vector2(40, 157)],
	[Vector2(58, 154), Vector2(57, 161)], [Vector2(74, 156), Vector2(72, 162)],
]
# Laccio in vita (curva) e i suoi due capi pendenti.
const CORD_START := Vector2(20, 100)
const CORD_SEGMENTS := [[Vector2(54, 108), Vector2(88, 100)]]
const CORD_ENDS := [[Vector2(58, 104), Vector2(54, 118)], [Vector2(62, 104), Vector2(66, 118)]]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var rect := ApparelIcon.fit_aspect(origin, area, DESIGN_SIZE.x / DESIGN_SIZE.y)
	var unit: float = rect.size.x / DESIGN_SIZE.x
	var outline := ApparelIcon.quad_outline(OUTLINE_START, OUTLINE_SEGMENTS, DESIGN_SIZE, rect)
	canvas.draw_colored_polygon(outline, FUR_COLOR)
	ApparelIcon.draw_strokes(canvas, DARK_TUFTS, DESIGN_SIZE, rect, DARK_TUFT_COLOR, maxf(2.0 * unit, 1.0))
	var closed := outline.duplicate()
	closed.append(outline[0])
	canvas.draw_polyline(closed, OUTLINE_COLOR, maxf(2.0 * unit, 1.0), true)
	ApparelIcon.draw_strokes(canvas, LIGHT_TUFTS, DESIGN_SIZE, rect, LIGHT_TUFT_COLOR, maxf(2.0 * unit, 1.0))
	canvas.draw_polyline(ApparelIcon.quad_outline(CORD_START, CORD_SEGMENTS, DESIGN_SIZE, rect), CORD_COLOR, maxf(3.0 * unit, 1.0), true)
	ApparelIcon.draw_strokes(canvas, CORD_ENDS, DESIGN_SIZE, rect, CORD_COLOR, maxf(2.5 * unit, 1.0))
