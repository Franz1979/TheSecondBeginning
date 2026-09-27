class_name CommandKnifeIcon
extends Node2D

# Icona del comando "butcher" (2026-09-26, richiesta utente — macellazione): un coltello inclinato, manico di
# legno e lama di pietra con il filo più chiaro. Stesso stile delle altre icone di comando disegnate
# (CommandHammerIcon, CrosshairIcon): registrata in IconRegistry.COMMAND_ICON_NODES, lampeggia sul bersaglio
# tramite GameScene._spawn_command_icon; origine = centro dell'icona, pixel locali della cella (10 px =
# 1 microcella).

const WOOD := Color(0.62, 0.42, 0.22, 1.0)
const STONE := Color(0.55, 0.56, 0.58, 1.0)
const EDGE := Color(0.82, 0.83, 0.85, 1.0)
const OUTLINE := Color(0.18, 0.14, 0.12, 1.0)
const OUTLINE_WIDTH_PX: float = 0.3


func _draw() -> void:
	# Asse del coltello: dal manico in basso a sinistra alla punta in alto a destra.
	var axis := Vector2(1.0, -1.0).normalized()
	var normal := axis.orthogonal()
	var handle_start: Vector2 = -axis * 3.2
	var guard: Vector2 = -axis * 0.9
	var tip: Vector2 = axis * 3.4
	# Manico.
	draw_line(handle_start, guard, OUTLINE, 0.9 + OUTLINE_WIDTH_PX * 2.0, true)
	draw_line(handle_start, guard, WOOD, 0.9, true)
	# Lama: dorso dritto da un lato, filo curvo dall'altro, fino alla punta.
	var blade := PackedVector2Array([
		guard + normal * 0.55,
		guard + axis * 2.4 + normal * 0.45,
		tip,
		guard + axis * 2.2 - normal * 0.75,
		guard - normal * 0.7,
	])
	draw_colored_polygon(blade, STONE)
	# Filo della lama, più chiaro.
	draw_line(guard - normal * 0.6, guard + axis * 2.2 - normal * 0.65, EDGE, 0.25, true)
	var outline := blade.duplicate()
	outline.append(blade[0])
	draw_polyline(outline, OUTLINE, OUTLINE_WIDTH_PX, true)
