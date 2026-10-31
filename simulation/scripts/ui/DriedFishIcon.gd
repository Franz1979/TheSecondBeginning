class_name DriedFishIcon
extends Control

# Icona "pesce essiccato" (2026-10-31, richiesta utente — ricette del pesce): la sagoma del pesce crudo
# (FishMeatIcon.draw_fish) chiara e grigio-paglia, appesa per la coda a un laccio, come sull'essiccatoio. draw_into
# (statica) condivisa con DepositStorageIcons.

const BACK_COLOR := Color(0.66, 0.60, 0.48, 1.0)
const BELLY_COLOR := Color(0.86, 0.82, 0.70, 1.0)
const DARK_COLOR := Color(0.36, 0.31, 0.24, 1.0)
const CORD_COLOR := Color(0.55, 0.42, 0.25, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna il pesce essiccato dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(x: float, y: float) -> Vector2: return origin + Vector2(x * area.x, y * area.y)
	var unit: float = minf(area.x, area.y)
	FishMeatIcon.draw_fish(canvas, origin, area, BACK_COLOR, BELLY_COLOR, DARK_COLOR, Color.TRANSPARENT)
	# Laccio legato alla coda, che sale verso l'alto.
	canvas.draw_line(p.call(0.14, 0.50), p.call(0.14, 0.14), CORD_COLOR, unit * 0.03, true)
	canvas.draw_circle(p.call(0.14, 0.50), unit * 0.035, CORD_COLOR)
	# Pieghe della carne secca sul fianco.
	for x in [0.42, 0.56]:
		canvas.draw_line(p.call(x, 0.42), p.call(x + 0.04, 0.56), DARK_COLOR, unit * 0.02, true)
