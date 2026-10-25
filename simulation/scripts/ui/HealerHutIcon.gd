class_name HealerHutIcon
extends Control

# Icona della capanna del guaritore nella barra di costruzione (healer_hut, 2026-10-25, richiesta utente): vista di
# fronte, come le icone delle altre capanne. Tettoia di frasche verde-brune con una larga apertura che lascia vedere il
# giaciglio di paglia e il focolare con la pentola degli infusi (come la vista dall'alto, 2026-10-25); a destra un palo con tre mazzetti di erbe appesi a testa in giù (uno fiorito di giallo, uno di viola)
# e, davanti, la ciotola di pietra. Stessi colori del disegno di mappa (HealerHutShape). Registrata in
# IconRegistry.BUILDING_ICON_NODES.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	# Disegno pensato in un quadrato di 10 unità centrato: scalato al lato minore del rettangolo.
	var unit := minf(size.x, size.y) / 10.0
	var origin := size * 0.5
	var p := func(x: float, y: float) -> Vector2:
		return origin + Vector2(x, y) * unit

	# Palo e mazzetti di erbe (dietro la capanna, a destra).
	draw_line(p.call(3.3, -3.6), p.call(3.3, 3.6), HealerHutShape.POLE, 0.45 * unit, true)
	draw_line(p.call(2.0, -3.4), p.call(4.6, -3.4), HealerHutShape.POLE, 0.4 * unit, true)
	for bundle in [Vector3(2.4, -3.4, 1), Vector3(3.3, -3.4, 0), Vector3(4.2, -3.4, 2)]:
		var top: Vector2 = p.call(bundle.x, bundle.y)
		var tip: Vector2 = p.call(bundle.x, bundle.y + 2.0)
		draw_colored_polygon(PackedVector2Array([
			top + Vector2(-0.12, 0.0) * unit, tip + Vector2(-0.45, 0.0) * unit, tip + Vector2(0.0, 0.25) * unit,
			tip + Vector2(0.45, 0.0) * unit, top + Vector2(0.12, 0.0) * unit,
		]), HealerHutShape.HERB)
		draw_line(top, tip, HealerHutShape.HERB_DARK, 0.15 * unit, true)
		draw_circle(top, 0.2 * unit, HealerHutShape.BARK)
		if int(bundle.z) != 0:
			draw_circle(tip + Vector2(0.0, 0.1) * unit, 0.28 * unit,
				HealerHutShape.FLOWER_YELLOW if int(bundle.z) == 1 else HealerHutShape.FLOWER_VIOLET)

	# Capanna a cupola: metà chiara e metà in ombra, fasci di frasche, contorno.
	var dome := PackedVector2Array()
	var shade := PackedVector2Array()
	var center: Vector2 = p.call(-0.8, 3.2)
	var radius_x := 4.0 * unit
	var radius_y := 5.2 * unit
	for i in range(17):
		var angle := PI + PI * float(i) / 16.0
		var point := center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y)
		dome.append(point)
		if i <= 8:
			shade.append(point)
	shade.append(center)
	draw_colored_polygon(dome, HealerHutShape.THATCH)
	draw_colored_polygon(shade, HealerHutShape.THATCH_SHADE)
	for i in range(1, 8):
		var angle := PI + PI * float(i) / 8.0
		draw_line(center + Vector2(cos(angle) * radius_x * 0.74, sin(angle) * radius_y * 0.74),
			center + Vector2(cos(angle) * radius_x * 0.97, sin(angle) * radius_y * 0.97), HealerHutShape.BUNDLE, 0.3 * unit, true)

	# Apertura larga della tettoia: interno in ombra, contorno della capanna e dell'apertura.
	var opening := PackedVector2Array()
	for i in range(13):
		var angle := PI + PI * float(i) / 12.0
		opening.append(center + Vector2(cos(angle) * radius_x * 0.68, sin(angle) * radius_y * 0.7))
	draw_colored_polygon(opening, HealerHutShape.DOOR)
	draw_polyline(dome, HealerHutShape.OUTLINE, 0.4 * unit, true)
	draw_polyline(opening, HealerHutShape.OUTLINE, 0.3 * unit, true)
	draw_line(dome[0], dome[dome.size() - 1], HealerHutShape.OUTLINE, 0.4 * unit, true)

	# Dentro: giaciglio di paglia con la pelle (a sinistra) e focolare con la pentola degli infusi (a destra).
	draw_rect(Rect2(p.call(-3.2, 2.4), Vector2(1.9, 0.8) * unit), HealerHutShape.STRAW)
	draw_rect(Rect2(p.call(-2.2, 2.3), Vector2(1.0, 0.9) * unit), HealerHutShape.BED_HIDE)
	draw_circle(p.call(0.4, 2.9), 0.75 * unit, HealerHutShape.EMBER)
	for stone_x in [-0.4, 0.4, 1.2]:
		draw_circle(p.call(stone_x, 3.0), 0.3 * unit, HealerHutShape.HEARTH_STONE)
	var pot := PackedVector2Array()
	for i in range(9):
		var angle := PI * float(i) / 8.0
		pot.append(p.call(0.4, 1.9) + Vector2(cos(angle) * 0.7, sin(angle) * 0.7) * unit)
	draw_colored_polygon(pot, HealerHutShape.POT)
	draw_line(p.call(-0.3, 1.9), p.call(1.1, 1.9), HealerHutShape.HERB_DARK, 0.25 * unit, true)

	# Ciotola di pietra davanti, con le erbe.
	var bowl := PackedVector2Array()
	for i in range(9):
		var angle := PI * float(i) / 8.0
		bowl.append(p.call(2.6, 3.2) + Vector2(cos(angle) * 1.3, sin(angle) * 0.9) * unit)
	draw_colored_polygon(bowl, HealerHutShape.BOWL)
	draw_line(p.call(1.3, 3.2), p.call(3.9, 3.2), HealerHutShape.BOWL_RIM, 0.3 * unit, true)
	draw_circle(p.call(2.6, 3.0), 0.5 * unit, HealerHutShape.BOWL_HERBS)
