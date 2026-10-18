class_name FeastGroundShape
extends RefCounted

# Spiazzo delle feste (feast_ground, 2026-10-17, docs/design/feast_ground.md — passo 2a): quadrato di terra battuta 2x2
# con al centro un cerchio di sassi, cenere e due legnetti spenti (il fuoco si accende durante la festa, passo 2b).
# Un solo disegno per mappa (MicroCellRenderer._draw_buildings), anteprima (BuildingGhost) e icona (FeastGroundIcon).
# Nessuna porta e nessuna rotazione: è un quadrato. Dal 2026-10-18 (richiesta utente) anche i materiali si vedono: 4
# tronchi distesi intorno al fuoco come sedute (la legna) e una cornice di ossa distese lungo il bordo (le ossa,
# BONE_PER_SIDE per lato: il costo è più alto, ma di più sul quadrato sarebbero una linea continua).
#
# draw(canvas, center, rect_px, invalid, alpha): `center` = centro del quadrato nello spazio del canvas, `rect_px` = lato
# in pixel (sulla mappa 2 microcelle = 20 px; tutte le misure sotto scalano col lato); `invalid` = anteprima su una
# posizione non edificabile (tinta rossastra, come le altre sagome di BuildingGhost).

const TYPE := "feast_ground"
# Misure in frazione del lato del quadrato.
const GROUND_INSET: float = 0.03
# Cerchio del fuoco più piccolo (2026-10-18, richiesta utente): prima raggio 0.2, sassi 0.05, cenere 0.13, legnetti 0.1.
const RING_RADIUS: float = 0.12
const STONE_RADIUS: float = 0.03
const STONE_COUNT: int = 11
const ASH_RADIUS: float = 0.075
const STICK_HALF_LENGTH: float = 0.055
const STICK_WIDTH: float = 0.016
const SPECK_COUNT: int = 14
const SPECK_RADIUS: float = 0.015

const ASH_COLOR := Color(0.36, 0.34, 0.32, 1.0)
const ASH_LIGHT_COLOR := Color(0.55, 0.53, 0.50, 1.0)
const CHARRED_STICK_COLOR := Color(0.18, 0.13, 0.09, 1.0)
const STONE_COLORS: Array[Color] = [
	Color(0.58, 0.57, 0.54, 1.0), Color(0.66, 0.64, 0.60, 1.0), Color(0.50, 0.49, 0.47, 1.0),
]
const STONE_OUTLINE := Color(0.32, 0.31, 0.30, 1.0)
# Tronchi-sedute: distanza dal centro, metà lunghezza, spessore e rotazione della croce (frazioni del lato / radianti).
const LOG_COUNT: int = 4
const LOG_DISTANCE: float = 0.28
const LOG_HALF_LENGTH: float = 0.1
const LOG_WIDTH: float = 0.055
const LOG_ROTATION: float = 0.35
const LOG_OUTLINE_WIDTH: float = 0.01
const LOG_END_LENGTH: float = 0.018
const LOG_COLOR := Color(0.50, 0.33, 0.18, 1.0)
const LOG_DARK_COLOR := Color(0.24, 0.15, 0.08, 1.0)
const LOG_END_COLOR := Color(0.82, 0.68, 0.47, 1.0)
# Cornice d'ossa: ossa per lato (angoli esclusi), distanza dal bordo, metà lunghezza, spessore, pomelli alle estremità.
# Tutte distese lungo il bordo (2026-10-18, richiesta utente — prima paletti verticali: sui lati sembravano paralleli
# al bordo, sopra e sotto perpendicolari).
const BONE_PER_SIDE: int = 5
const BONE_EDGE_INSET: float = 0.07
const BONE_HALF_LENGTH: float = 0.032
const BONE_WIDTH: float = 0.013
const BONE_KNOB_RADIUS: float = 0.012
const INVALID_TINT := Color(1.0, 0.45, 0.4, 1.0)


static func draw(
	canvas: CanvasItem, center: Vector2, rect_px: Vector2, invalid: bool, alpha: float = 1.0, with_ground: bool = true
) -> void:
	var side: float = minf(rect_px.x, rect_px.y)
	var tint := func(color: Color) -> Color:
		var result: Color = color * INVALID_TINT if invalid else color
		result.a = color.a * alpha
		return result

	# Terra battuta, con qualche puntino fisso (stessi colori di DirtGroundPattern). Sulla mappa no (`with_ground` false): lì
	# il fondo sono i tile di terra battuta del renderer, che si fondono con gli edifici vicini; resta per anteprima e icona.
	if with_ground:
		var inset := rect_px * GROUND_INSET
		canvas.draw_rect(Rect2(center - rect_px / 2.0 + inset, rect_px - inset * 2.0), tint.call(DirtGroundPattern.BASE_COLOR), true)
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		for i in range(SPECK_COUNT):
			var offset := Vector2(rng.randf_range(-0.42, 0.42), rng.randf_range(-0.42, 0.42)) * side
			var color: Color = DirtGroundPattern.SPECK_COLORS[i % DirtGroundPattern.SPECK_COLORS.size()]
			canvas.draw_circle(center + offset, SPECK_RADIUS * side, tint.call(color))

	# Tronchi-sedute intorno al fuoco, tangenti al cerchio (2026-10-18: sagome piene con contorno scuro invece di linee
	# spesse sfumate): corpo, venatura, sezioni chiare alle estremità.
	for i in range(LOG_COUNT):
		var angle: float = LOG_ROTATION + TAU * float(i) / float(LOG_COUNT)
		var log_center := center + Vector2(cos(angle), sin(angle)) * LOG_DISTANCE * side
		var dir := Vector2(-sin(angle), cos(angle))
		var along := dir * LOG_HALF_LENGTH * side
		var across := dir.orthogonal() * LOG_WIDTH * 0.5 * side
		var body := PackedVector2Array([
			log_center - along - across, log_center + along - across, log_center + along + across, log_center - along + across,
		])
		canvas.draw_colored_polygon(body, tint.call(LOG_COLOR))
		canvas.draw_line(log_center - along * 0.7, log_center + along * 0.7, tint.call(LOG_DARK_COLOR), LOG_OUTLINE_WIDTH * side)
		var end_step := dir * LOG_END_LENGTH * side
		for end_sign in [-1.0, 1.0]:
			var tip: Vector2 = log_center + along * end_sign
			var inner: Vector2 = tip - end_step * end_sign
			canvas.draw_colored_polygon(PackedVector2Array([inner - across, tip - across, tip + across, inner + across]), tint.call(LOG_END_COLOR))
		var outline := body.duplicate()
		outline.append(body[0])
		canvas.draw_polyline(outline, tint.call(LOG_DARK_COLOR), LOG_OUTLINE_WIDTH * side)

	# Cenere e legnetti spenti dentro il cerchio.
	canvas.draw_circle(center, ASH_RADIUS * side, tint.call(ASH_COLOR))
	canvas.draw_circle(center + Vector2(0.03, -0.02) * side, ASH_RADIUS * 0.5 * side, tint.call(ASH_LIGHT_COLOR))
	for angle in [0.5, -0.7]:
		var direction := Vector2(cos(angle), sin(angle)) * STICK_HALF_LENGTH * side
		canvas.draw_line(center - direction, center + direction, tint.call(CHARRED_STICK_COLOR), STICK_WIDTH * side, true)

	# Cerchio di sassi.
	for i in range(STONE_COUNT):
		var angle: float = TAU * float(i) / float(STONE_COUNT)
		var stone_center := center + Vector2(cos(angle), sin(angle)) * RING_RADIUS * side
		var polygon := PlaceholderBuildingShapes._blob_polygon(stone_center, STONE_RADIUS * side, 7100 + i, 7)
		canvas.draw_colored_polygon(polygon, tint.call(STONE_COLORS[i % STONE_COLORS.size()]))
		var outline := polygon.duplicate()
		outline.append(polygon[0])
		canvas.draw_polyline(outline, tint.call(STONE_OUTLINE), 0.012 * side, true)

	# Cornice d'ossa lungo il bordo: ogni osso disteso nel verso del suo lato, con i due pomelli alle estremità; stesse
	# posizioni sui quattro lati, angoli liberi. Senza contorno (2026-10-18, richiesta utente: metà delle chiamate di disegno).
	var half := 0.5 - BONE_EDGE_INSET
	var bone_color: Color = tint.call(BoneIcon.BONE_COLOR)
	for i in range(BONE_PER_SIDE):
		var t := lerpf(-half, half, (float(i) + 0.5) / float(BONE_PER_SIDE))
		for bone in [[Vector2(t, -half), Vector2.RIGHT], [Vector2(t, half), Vector2.RIGHT], [Vector2(-half, t), Vector2.DOWN], [Vector2(half, t), Vector2.DOWN]]:
			var mid: Vector2 = center + (bone[0] as Vector2) * side
			var half_bone: Vector2 = (bone[1] as Vector2) * BONE_HALF_LENGTH * side
			canvas.draw_line(mid - half_bone, mid + half_bone, bone_color, BONE_WIDTH * side)
			for end_point in [mid - half_bone, mid + half_bone]:
				canvas.draw_circle(end_point, BONE_KNOB_RADIUS * side, bone_color)
