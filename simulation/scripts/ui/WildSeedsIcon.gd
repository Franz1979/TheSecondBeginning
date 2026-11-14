class_name WildSeedsIcon
extends Control

# Icona disegnata dei semi selvatici (2026-11-14, richiesta utente — prima solo l'emoji 🌾, che la linguetta
# Granaglie di "Gestione scorte" non sa mostrare): una spiga d'erba selvatica piegata con i chicchi alternati sui due
# lati e qualche seme sciolto a terra. Offset FISSI (icona statica, stesso principio di AcornIcon e delle altre).

# Colori in variabili (2026-11-15): la stessa spiga serve anche al grano selvatico (WildWheatIcon) con colori suoi.
var color_stalk := Color(0.55, 0.50, 0.24, 1.0)
var color_grain := Color(0.86, 0.70, 0.36, 1.0)
var color_grain_dark := Color(0.68, 0.52, 0.24, 1.0)
var color_awn := Color(0.80, 0.70, 0.45, 0.9)
const COLOR_OUTLINE := Color(0.30, 0.22, 0.10, 1.0)

const ELLIPSE_SEGMENTS: int = 12

# Stelo: dalla base in basso a sinistra fino alla punta in alto a destra, leggermente curvo.
const STALK_POINTS := [Vector2(0.30, 0.92), Vector2(0.38, 0.66), Vector2(0.48, 0.42), Vector2(0.62, 0.14)]

# Chicchi della spiga: (t lungo lo stelo tra 0.35 e 1.0, lato -1/+1). Disegnati dal basso verso l'alto.
const SPIKE_GRAINS := [
	{"t": 0.40, "side": -1.0}, {"t": 0.47, "side": 1.0},
	{"t": 0.55, "side": -1.0}, {"t": 0.62, "side": 1.0},
	{"t": 0.70, "side": -1.0}, {"t": 0.77, "side": 1.0},
	{"t": 0.85, "side": -1.0}, {"t": 0.92, "side": 1.0},
]

# Semi sciolti a terra: (cx, cy, rotazione).
const LOOSE_SEEDS := [
	{"cx": 0.58, "cy": 0.86, "rot": 0.6},
	{"cx": 0.72, "cy": 0.82, "rot": -0.4},
	{"cx": 0.82, "cy": 0.90, "rot": 1.1},
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var unit: float = minf(w, h)
	var stalk := PackedVector2Array()
	for point in STALK_POINTS:
		stalk.append(Vector2(w * point.x, h * point.y))
	draw_polyline(stalk, color_stalk, unit * 0.045, true)
	for grain in SPIKE_GRAINS:
		var t: float = grain["t"]
		var base := _point_on_stalk(stalk, t)
		var direction := (_point_on_stalk(stalk, minf(t + 0.05, 1.0)) - _point_on_stalk(stalk, maxf(t - 0.05, 0.0))).normalized()
		var normal := Vector2(-direction.y, direction.x) * float(grain["side"])
		# Chicco inclinato verso l'alto e verso l'esterno, con la sua resta (filo sottile) in punta.
		var axis := (direction + normal * 0.9).normalized()
		var center := base + axis * unit * 0.07
		_draw_grain(center, Vector2(unit * 0.075, unit * 0.04), axis.angle(), color_grain if grain["side"] > 0.0 else color_grain_dark, unit)
		draw_line(center + axis * unit * 0.07, center + axis * unit * 0.17, color_awn, unit * 0.015, true)
	# Chicco in punta.
	var tip := stalk[stalk.size() - 1]
	var tip_dir := (tip - stalk[stalk.size() - 2]).normalized()
	_draw_grain(tip + tip_dir * unit * 0.03, Vector2(unit * 0.075, unit * 0.04), tip_dir.angle(), color_grain, unit)
	for loose in LOOSE_SEEDS:
		_draw_grain(Vector2(w * loose["cx"], h * loose["cy"]), Vector2(unit * 0.065, unit * 0.035), loose["rot"], color_grain, unit)


func _point_on_stalk(stalk: PackedVector2Array, t: float) -> Vector2:
	var scaled: float = clampf(t, 0.0, 1.0) * float(stalk.size() - 1)
	var index: int = mini(int(scaled), stalk.size() - 2)
	return stalk[index].lerp(stalk[index + 1], scaled - float(index))


func _draw_grain(center: Vector2, radius: Vector2, rotation: float, color: Color, unit: float) -> void:
	var points := PackedVector2Array()
	for i in range(ELLIPSE_SEGMENTS):
		var angle: float = TAU * float(i) / float(ELLIPSE_SEGMENTS)
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y).rotated(rotation))
	draw_colored_polygon(points, color)
	points.append(points[0])
	draw_polyline(points, COLOR_OUTLINE, unit * 0.012, true)
