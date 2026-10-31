class_name SmokedFishIcon
extends Control

# Icona "pesce affumicato" (2026-10-31, richiesta utente — ricette del pesce): la sagoma del pesce crudo
# (FishMeatIcon.draw_fish) bruno scuro con il ventre ambrato e un filo di fumo grigio che sale, come SmokedMeatIcon.
# draw_into (statica) condivisa con DepositStorageIcons.

const BACK_COLOR := Color(0.32, 0.18, 0.08, 1.0)
const BELLY_COLOR := Color(0.72, 0.48, 0.20, 1.0)
const DARK_COLOR := Color(0.16, 0.08, 0.04, 1.0)
const SMOKE_COLOR := Color(0.70, 0.70, 0.68, 0.85)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna il pesce affumicato dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(x: float, y: float) -> Vector2: return origin + Vector2(x * area.x, y * area.y)
	var unit: float = minf(area.x, area.y)
	FishMeatIcon.draw_fish(canvas, origin, area, BACK_COLOR, BELLY_COLOR, DARK_COLOR, Color.TRANSPARENT)
	canvas.draw_polyline(PackedVector2Array([
		p.call(0.62, 0.30), p.call(0.58, 0.22), p.call(0.64, 0.14), p.call(0.60, 0.06),
	]), SMOKE_COLOR, unit * 0.035, true)
