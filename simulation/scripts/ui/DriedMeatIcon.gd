class_name DriedMeatIcon
extends Control

# Icona provvisoria "carne essiccata" (2026-10-03, richiesta utente — essiccazione, passo 1): tre strisce di carne
# sottili e scure, leggermente storte, con una venatura di grasso secco. Stesso schema di CookedMeatIcon: draw_into
# (statica) condivisa con DepositStorageIcons (magazzini e mucchi a terra).

const STRIP_COLOR := Color(0.42, 0.16, 0.12, 1.0)
const STRIP_DARK_COLOR := Color(0.26, 0.09, 0.07, 1.0)
const FAT_COLOR := Color(0.80, 0.62, 0.42, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna la carne essiccata dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(x: float, y: float) -> Vector2: return origin + Vector2(x * area.x, y * area.y)
	var unit: float = minf(area.x, area.y)
	for strip in [[0.22, 0.20, 0.30, 0.82], [0.46, 0.16, 0.50, 0.84], [0.70, 0.20, 0.76, 0.80]]:
		var top: Vector2 = p.call(strip[0], strip[1])
		var bottom: Vector2 = p.call(strip[2], strip[3])
		canvas.draw_line(top, bottom, STRIP_DARK_COLOR, unit * 0.17, true)
		canvas.draw_line(top, bottom, STRIP_COLOR, unit * 0.12, true)
		canvas.draw_line(top.lerp(bottom, 0.25), top.lerp(bottom, 0.55), FAT_COLOR, unit * 0.03, true)
