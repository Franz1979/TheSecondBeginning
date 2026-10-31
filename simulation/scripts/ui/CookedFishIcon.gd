class_name CookedFishIcon
extends Control

# Icona "pesce cotto" (2026-10-31, richiesta utente — ricette del pesce): la sagoma del pesce crudo (FishMeatIcon.draw_fish)
# dorata e bruna, con tre segni scuri di brace sul fianco. draw_into (statica) condivisa con DepositStorageIcons.

const BACK_COLOR := Color(0.62, 0.38, 0.16, 1.0)
const BELLY_COLOR := Color(0.88, 0.70, 0.42, 1.0)
const DARK_COLOR := Color(0.28, 0.15, 0.06, 1.0)
const GRILL_COLOR := Color(0.30, 0.16, 0.07, 0.9)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna il pesce cotto dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(x: float, y: float) -> Vector2: return origin + Vector2(x * area.x, y * area.y)
	var unit: float = minf(area.x, area.y)
	FishMeatIcon.draw_fish(canvas, origin, area, BACK_COLOR, BELLY_COLOR, DARK_COLOR, Color.TRANSPARENT)
	for x in [0.40, 0.52, 0.64]:
		canvas.draw_line(p.call(x - 0.03, 0.40), p.call(x + 0.03, 0.60), GRILL_COLOR, unit * 0.035, true)
