class_name PlaceholderBuildingShapes
extends RefCounted

# Disegni PROVVISORI degli edifici segnaposto (2026-09-26, richiesta utente — graticcio, affumicatoio, sepoltura,
# vallo di terra: esistono solo nell'albero delle idee e nella barra di costruzione, senza ricette né funzioni).
# Un solo disegno condiviso da mappa (MicroCellRenderer._draw_buildings), anteprima di piazzamento
# (BuildingGhost) e icona della barra (le *Icon.gd di questi tipi), invece di tre copie. Tutti senza porta
# (has_door = false): nessuna rotazione.
#
# draw(canvas, type, center, invalid, scale): `center` è il centro della microcella nello spazio del canvas,
# `scale` = pixel per unità di disegno (1.0 sulla mappa: una microcella = 10 px); `invalid` = anteprima su una
# posizione non edificabile (tinta rossastra semitrasparente, come le altre sagome di BuildingGhost).

# "clothing_hut" non è più qui (2026-10-20): sulla mappa e nell'anteprima usa ClothingHutShape (vista dall'alto); il suo ramo
# di draw() resta per la sola icona della barra (ClothingHutIcon, vista di fronte).
const TYPES: Array[String] = ["drying_rack", "smokehouse", "burial", "earthwork", "stacked_stones", "rubble", "teaching_stump", "waste_pit"]

# Ceppo dell'insegnamento (teaching_stump, 2026-10-16, richiesta utente): aula all'aperto vista dall'alto — il ceppo in
# alto come cattedra (corteccia, sezione chiara con gli anelli) e davanti due file curve di pietre piatte come banchi
# (3 + 3), rivolte al ceppo. Sagome delle pietre con _blob_polygon (seed fissi), stessi grigi del cumulo delle pietre.
const TEACHING_STUMP_CENTER := Vector2(0.0, -2.6)
const TEACHING_STUMP_RADIUS: float = 1.6
# Banchi: centro (x, y) e raggio (z); due file ad arco attorno al ceppo.
const TEACHING_STUMP_SEATS: Array[Vector3] = [
	Vector3(-2.7, 0.3, 0.95), Vector3(0.0, 0.9, 0.95), Vector3(2.7, 0.3, 0.95),
	Vector3(-3.3, 2.9, 0.95), Vector3(0.0, 3.6, 0.95), Vector3(3.3, 2.9, 0.95),
]

# Fossa dei rifiuti (waste_pit, 2026-10-18, richiesta utente): buca vista dall'alto — bordo di terra smossa, fondo
# scuro e qualche scarto sul fondo (un rametto, un pezzo di pelle, un sasso). Sagome con _blob_polygon (seed fissi).
const WASTE_PIT_RIM_RADIUS: float = 4.3
const WASTE_PIT_HOLE_RADIUS: float = 3.1
const WASTE_PIT_RIM := Color(0.50, 0.40, 0.29, 1.0)
const WASTE_PIT_HOLE := Color(0.20, 0.16, 0.12, 1.0)
const WASTE_PIT_SCRAP_HIDE := Color(0.46, 0.38, 0.30, 1.0)
const WASTE_PIT_SCRAP_STONE := Color(0.52, 0.50, 0.47, 1.0)

# Macerie (rubble, 2026-10-10; ridisegnate il 2026-10-18, richiesta utente — "meno cartone animato", nello stile degli
# altri edifici come StorageHutShape: colori di terra smorzati, contorni sottili marroni, nessuna forma gonfia). Vista
# dall'alto: una chiazza bassa di terra smossa con una metà in ombra, schegge di pietra piccole e qualche asse spezzata.
const RUBBLE_GROUND_RADIUS: float = 3.7
# Scala dell'intero disegno delle macerie (2026-10-18): più piccolo della Fossa, che occupa quasi tutta la microcella.
const RUBBLE_DRAW_SCALE: float = 0.7
const RUBBLE_GROUND := Color(0.47, 0.40, 0.31, 1.0)
const RUBBLE_GROUND_SHADE := Color(0.40, 0.34, 0.26, 1.0)
const RUBBLE_OUTLINE := Color(0.30, 0.22, 0.12, 1.0)
const RUBBLE_OUTLINE_WIDTH: float = 0.35
# Schegge di pietra: centro (x, y) e raggio (z); colori nello stesso ordine.
const RUBBLE_CHUNKS: Array[Vector3] = [
	Vector3(-1.6, -0.9, 0.75), Vector3(1.2, -1.6, 0.6), Vector3(0.4, 1.4, 0.8), Vector3(-1.0, 1.9, 0.5),
	Vector3(2.0, 0.6, 0.55), Vector3(-2.3, 0.6, 0.45), Vector3(0.1, -0.2, 0.5),
]
const RUBBLE_CHUNK_COLORS: Array[Color] = [
	Color(0.56, 0.53, 0.48, 1.0), Color(0.50, 0.47, 0.43, 1.0), Color(0.60, 0.57, 0.51, 1.0), Color(0.53, 0.50, 0.45, 1.0),
	Color(0.58, 0.55, 0.49, 1.0), Color(0.49, 0.46, 0.42, 1.0), Color(0.55, 0.52, 0.46, 1.0),
]
# Assi spezzate: estremi (x1, y1, x2, y2), colore chiaro/scuro alternato come le falde dei tetti.
const RUBBLE_BEAMS: Array[Vector4] = [Vector4(-2.8, -2.0, -0.6, -0.4), Vector4(0.9, 2.6, 2.9, 1.2), Vector4(-0.4, -2.7, 1.5, -2.1)]
const RUBBLE_BEAM_WIDTH: float = 0.45
const RUBBLE_BEAM_LIGHT := Color(0.66, 0.51, 0.32, 1.0)
const RUBBLE_BEAM_DARK := Color(0.54, 0.40, 0.24, 1.0)

# Capanna del vestiario (clothing_hut, 2026-10-11, richiesta utente — segnaposto): vista di fronte, una capanna a
# punta di pelli grigio-brune con l'ingresso scuro e, a destra, una pelle tesa ad asciugare su un telaio di due pali.
const CLOTHING_HUT_HIDE := Color(0.52, 0.48, 0.43, 1.0)
const CLOTHING_HUT_HIDE_DARK := Color(0.38, 0.35, 0.32, 1.0)
const CLOTHING_HUT_DOOR := Color(0.16, 0.13, 0.11, 1.0)
const LOG_BARK := Color(0.36, 0.24, 0.12, 1.0)
const LOG_END := Color(0.80, 0.64, 0.42, 1.0)
const LOG_RING := Color(0.60, 0.45, 0.27, 1.0)

# Pietre rituali (stacked_stones, ridisegnate 2026-10-02 — seconda versione, richiesta utente: un luogo rituale
# costruito apposta, non un mucchio): vista dall'alto, composizione SIMMETRICA attorno al centro, dal basso in alto —
# una pelle stesa come base, un piccolo cumulo di 3 pietre al centro, 4 ossa a raggiera sui quattro lati, 4 rametti
# a raggiera sulle diagonali (tra un osso e l'altro). Niente contorno né ombreggiatura. Colori di pelle, ossa e
# rametti presi dalle icone delle risorse (HideIcon/BoneIcon/StickIcon), così restano gli stessi del resto del gioco.
const STACKED_STONES_HIDE_RADIUS: float = 4.1
const STACKED_STONES_HIDE_VERTICES: int = 12
# Cumulo: centro (x, y) e raggio (z) di ogni pietra, dalla base alla cima, ognuna un po' più chiara della precedente.
const STACKED_STONES_PILE: Array[Vector3] = [
	Vector3(0.0, 0.15, 1.7), Vector3(0.25, -0.15, 1.1), Vector3(-0.1, -0.35, 0.6),
]
const STACKED_STONES_PILE_COLORS: Array[Color] = [
	Color(0.62, 0.60, 0.56, 1.0), Color(0.72, 0.70, 0.66, 1.0), Color(0.81, 0.79, 0.75, 1.0),
]
# Ossa (assi cardinali) e rametti (diagonali): da raggio interno a raggio esterno, spessore, e per le ossa il raggio
# delle due estremità arrotondate.
const STACKED_STONES_BONE_INNER: float = 2.2
const STACKED_STONES_BONE_OUTER: float = 3.5
const STACKED_STONES_BONE_WIDTH: float = 0.45
const STACKED_STONES_BONE_KNOB_RADIUS: float = 0.32
const STACKED_STONES_STICK_INNER: float = 2.0
const STACKED_STONES_STICK_OUTER: float = 3.9
const STACKED_STONES_STICK_WIDTH: float = 0.35
const STACKED_STONES_BLOB_VERTICES: int = 9

const WOOD := Color(0.55, 0.38, 0.20, 1.0)
const WOOD_DARK := Color(0.36, 0.24, 0.12, 1.0)
const MEAT_STRIP := Color(0.62, 0.20, 0.16, 1.0)
const SMOKEHOUSE_WALL := Color(0.40, 0.30, 0.22, 1.0)
const SMOKE := Color(0.78, 0.78, 0.76, 0.75)
const EARTH := Color(0.47, 0.36, 0.24, 1.0)
const EARTH_DARK := Color(0.33, 0.25, 0.16, 1.0)
const STONE := Color(0.62, 0.61, 0.58, 1.0)
const OUTLINE := Color(0.18, 0.14, 0.12, 1.0)
const INVALID_TINT := Color(0.9, 0.25, 0.25, 0.55)
# Lastra-altare del cumulo sepolcrale (2026-10-04, passo 3a): rettangolo in unità di disegno (centro della microcella =
# 0,0; microcella da -5 a 5), nella striscia libera sotto il tumulo (le pietre del cerchio arrivano a y 2.65).
const BURIAL_SLAB_RECT := Rect2(-3.0, 2.85, 6.0, 1.95)
const BURIAL_SLAB_EDGE: float = 0.45
# Lastra di pietra (2026-10-08, richiesta utente — la pietra è ora tra i materiali del cumulo; prima letto di terra
# battuta): grigi della famiglia di rocce e sassi (MicroCellRenderer.COLOR_STONE/COLOR_PEBBLE, PebbleIcon), il piano un filo
# più scuro e freddo delle pietre del cerchio (STONE) per staccarsene, il bordo inferiore come il contorno dei sassi e una
# venatura sottile che la fa leggere come una lastra spaccata, non un rettangolo grigio.
const SLAB_TOP := Color(0.55, 0.54, 0.52, 1.0)
const SLAB_EDGE := Color(0.36, 0.35, 0.33, 1.0)
const SLAB_CRACK := Color(0.42, 0.41, 0.39, 1.0)
const SLAB_CRACK_WIDTH: float = 0.18


# Direzione dell'edificio (2026-10-17, richiesta utente — tutti gli edifici ruotabili): i disegni sono fatti verso SUD;
# gli altri ruotano di 90° per passo (orario, N-E-S-W), tranne quelli visti di fronte, che a OVEST si specchiano soltanto
# (ruotati sembrerebbero coricati). Una sola draw_set_transform per edificio: nessun costo di disegno in più.
const FRONT_VIEW_TYPES: Array[String] = ["drying_rack", "smokehouse", "clothing_hut", "earthwork"]


static func _direction_angle(building_type: String, direction: GameTypes.Direction) -> float:
	if FRONT_VIEW_TYPES.has(building_type):
		return 0.0
	return float(int(direction) - int(GameTypes.Direction.SOUTH)) * PI / 2.0


static func _direction_mirror(building_type: String, direction: GameTypes.Direction) -> float:
	return -1.0 if FRONT_VIEW_TYPES.has(building_type) and direction == GameTypes.Direction.WEST else 1.0


# Centro della lastra in microcelle, relativo all'angolo della microcella del cumulo (0..1): dove si posa il corpo. Ruota
# con la direzione del cumulo (2026-10-17).
static func burial_slab_center_microcell(direction: GameTypes.Direction = GameTypes.Direction.SOUTH) -> Vector2:
	return Vector2(0.5, 0.5) + (BURIAL_SLAB_RECT.get_center() / 10.0).rotated(_direction_angle("burial", direction))


static func draw(
	canvas: CanvasItem, building_type: String, canvas_center: Vector2, invalid: bool = false, scale: float = 1.0,
	direction: GameTypes.Direction = GameTypes.Direction.SOUTH
) -> void:
	# Tutto si disegna attorno all'origine dentro la trasformazione della direzione, ripristinata alla fine.
	canvas.draw_set_transform(canvas_center, _direction_angle(building_type, direction), Vector2(_direction_mirror(building_type, direction), 1.0))
	var center := Vector2.ZERO
	var tint := func(color: Color) -> Color: return INVALID_TINT if invalid else color
	var p := func(x: float, y: float) -> Vector2: return center + Vector2(x, y) * scale
	var w := func(width: float) -> float: return width * scale
	match building_type:
		"drying_rack":
			# Due pali, una traversa e quattro strisce di carne appese.
			canvas.draw_line(p.call(-3.2, 3.0), p.call(-3.2, -2.6), tint.call(WOOD_DARK), w.call(0.6), true)
			canvas.draw_line(p.call(3.2, 3.0), p.call(3.2, -2.6), tint.call(WOOD_DARK), w.call(0.6), true)
			canvas.draw_line(p.call(-3.8, -2.4), p.call(3.8, -2.4), tint.call(WOOD), w.call(0.6), true)
			for x in [-2.2, -0.8, 0.6, 2.0]:
				canvas.draw_line(p.call(x, -2.2), p.call(x + 0.2, 0.6), tint.call(MEAT_STRIP), w.call(0.7), true)
		"smokehouse":
			# Capanno conico di rami chiuso, con fumo che esce dalla cima.
			var body := PackedVector2Array([p.call(-3.4, 3.0), p.call(0.0, -2.8), p.call(3.4, 3.0)])
			canvas.draw_colored_polygon(body, tint.call(SMOKEHOUSE_WALL))
			var outline := body.duplicate()
			outline.append(body[0])
			canvas.draw_polyline(outline, tint.call(OUTLINE), w.call(0.3), true)
			canvas.draw_line(p.call(-1.2, 3.0), p.call(0.0, -1.0), tint.call(WOOD_DARK), w.call(0.3), true)
			canvas.draw_line(p.call(1.2, 3.0), p.call(0.0, -1.0), tint.call(WOOD_DARK), w.call(0.3), true)
			if not invalid:
				canvas.draw_circle(p.call(0.4, -3.6), w.call(0.8), SMOKE)
				canvas.draw_circle(p.call(1.3, -4.4), w.call(0.6), SMOKE)
		"burial":
			# Tumulo ovale di terra con un cerchio di pietre e una pietra ritta.
			# Ovale come poligono (2026-10-17: prima una draw_set_transform propria, che annullerebbe quella della direzione).
			var mound := PackedVector2Array()
			for i in range(24):
				var mound_angle := TAU * float(i) / 24.0
				mound.append(p.call(cos(mound_angle) * 3.6, sin(mound_angle) * 3.6 * 0.6))
			canvas.draw_colored_polygon(mound, tint.call(EARTH))
			for i in range(8):
				var angle := TAU * float(i) / 8.0
				canvas.draw_circle(p.call(cos(angle) * 3.6, sin(angle) * 2.2), w.call(0.45), tint.call(STONE))
			canvas.draw_rect(Rect2(p.call(-0.5, -2.8), Vector2(1.0, 2.6) * scale), tint.call(STONE))
			# Lastra-altare (2026-10-04, cumulo sepolcrale passo 3a; di pietra dal 2026-10-08): piatta e bassa, nella striscia
			# libera sotto il tumulo — piano grigio, un bordo inferiore più scuro che ne suggerisce il poco spessore e una
			# venatura spezzata. Il corpo posato accanto al cumulo ci viene disteso sopra (burial_slab_center_microcell).
			canvas.draw_rect(Rect2(p.call(BURIAL_SLAB_RECT.position.x, BURIAL_SLAB_RECT.position.y), BURIAL_SLAB_RECT.size * scale), tint.call(SLAB_TOP))
			canvas.draw_rect(Rect2(
				p.call(BURIAL_SLAB_RECT.position.x, BURIAL_SLAB_RECT.end.y - BURIAL_SLAB_EDGE), Vector2(BURIAL_SLAB_RECT.size.x, BURIAL_SLAB_EDGE) * scale
			), tint.call(SLAB_EDGE))
			canvas.draw_polyline(PackedVector2Array([
				p.call(-1.6, BURIAL_SLAB_RECT.position.y), p.call(-1.1, 3.55), p.call(-1.4, 3.95), p.call(-0.9, BURIAL_SLAB_RECT.end.y - BURIAL_SLAB_EDGE),
			]), tint.call(SLAB_CRACK), w.call(SLAB_CRACK_WIDTH), true)
			canvas.draw_line(p.call(1.3, 3.25), p.call(2.2, 3.75), tint.call(SLAB_CRACK), w.call(SLAB_CRACK_WIDTH), true)
		"earthwork":
			# Argine di terra ad arco, con il ciglio più scuro.
			var ridge := PackedVector2Array()
			for i in range(9):
				var t := float(i) / 8.0
				ridge.append(p.call(-4.0 + 8.0 * t, 1.0 - sin(t * PI) * 2.6))
			canvas.draw_polyline(ridge, tint.call(EARTH), w.call(2.2), true)
			canvas.draw_polyline(ridge, tint.call(EARTH_DARK), w.call(0.5), true)
		"clothing_hut":
			# Telaio con la pelle tesa (dietro), poi la capanna a punta con l'ingresso e le cuciture.
			canvas.draw_line(p.call(2.4, 3.8), p.call(2.4, -1.6), tint.call(WOOD_DARK), w.call(0.45), true)
			canvas.draw_line(p.call(4.4, 3.8), p.call(4.4, -1.6), tint.call(WOOD_DARK), w.call(0.45), true)
			canvas.draw_colored_polygon(PackedVector2Array([
				p.call(2.5, -1.2), p.call(4.3, -1.2), p.call(4.1, 1.6), p.call(2.7, 1.6),
			]), tint.call(CLOTHING_HUT_HIDE_DARK))
			var hut := PackedVector2Array([p.call(-1.0, -4.0), p.call(2.0, 3.8), p.call(-4.2, 3.8)])
			canvas.draw_colored_polygon(hut, tint.call(CLOTHING_HUT_HIDE))
			canvas.draw_colored_polygon(PackedVector2Array([
				p.call(-1.1, 0.6), p.call(0.1, 3.8), p.call(-2.3, 3.8),
			]), tint.call(CLOTHING_HUT_DOOR))
			canvas.draw_line(p.call(-1.0, -4.0), p.call(-2.6, -0.2), tint.call(CLOTHING_HUT_HIDE_DARK), w.call(0.25), true)
			canvas.draw_line(p.call(-1.0, -4.0), p.call(0.6, -0.2), tint.call(CLOTHING_HUT_HIDE_DARK), w.call(0.25), true)
			canvas.draw_line(p.call(-1.0, -4.0), p.call(-1.2, -5.0), tint.call(WOOD_DARK), w.call(0.4), true)
			canvas.draw_line(p.call(-1.0, -4.0), p.call(-0.5, -4.9), tint.call(WOOD_DARK), w.call(0.4), true)
			var hut_outline := hut.duplicate()
			hut_outline.append(hut[0])
			canvas.draw_polyline(hut_outline, tint.call(OUTLINE), w.call(0.3), true)
		"rubble":
			# Detriti dal fondo in su, poi le travi spezzate sopra (con il contorno scuro sotto il legno).
			# Più piccole della Fossa dei rifiuti (2026-10-18, richiesta utente): tutto il disegno scalato di RUBBLE_DRAW_SCALE.
			var rp := func(x: float, y: float) -> Vector2: return p.call(x * RUBBLE_DRAW_SCALE, y * RUBBLE_DRAW_SCALE)
			var rw := func(width: float) -> float: return w.call(width * RUBBLE_DRAW_SCALE)
			# Terra smossa: la chiazza in ombra sotto, quella chiara sopra spostata verso destra e in alto (resta un bordo
			# d'ombra a sinistra e in basso), contorno sottile; poi assi e schegge, ognuna col suo contorno.
			var ground := _blob_polygon(center, rw.call(RUBBLE_GROUND_RADIUS), 300, 12, 0.88, 1.06)
			canvas.draw_colored_polygon(ground, tint.call(RUBBLE_GROUND_SHADE))
			canvas.draw_colored_polygon(
				_blob_polygon(rp.call(0.35, -0.35), rw.call(RUBBLE_GROUND_RADIUS * 0.82), 300, 12, 0.88, 1.06), tint.call(RUBBLE_GROUND)
			)
			var ground_outline := ground.duplicate()
			ground_outline.append(ground[0])
			canvas.draw_polyline(ground_outline, tint.call(RUBBLE_OUTLINE), rw.call(RUBBLE_OUTLINE_WIDTH), true)
			for i in range(RUBBLE_BEAMS.size()):
				var beam: Vector4 = RUBBLE_BEAMS[i]
				canvas.draw_line(rp.call(beam.x, beam.y), rp.call(beam.z, beam.w), tint.call(RUBBLE_OUTLINE), rw.call(RUBBLE_BEAM_WIDTH + 0.25), true)
				canvas.draw_line(rp.call(beam.x, beam.y), rp.call(beam.z, beam.w), tint.call(RUBBLE_BEAM_LIGHT if i % 2 == 0 else RUBBLE_BEAM_DARK), rw.call(RUBBLE_BEAM_WIDTH), true)
			for i in range(RUBBLE_CHUNKS.size()):
				var chunk: Vector3 = RUBBLE_CHUNKS[i]
				var stone := _blob_polygon(rp.call(chunk.x, chunk.y), rw.call(chunk.z), 310 + i, 6, 0.75, 1.15)
				canvas.draw_colored_polygon(stone, tint.call(RUBBLE_CHUNK_COLORS[i]))
				var stone_outline := stone.duplicate()
				stone_outline.append(stone[0])
				canvas.draw_polyline(stone_outline, tint.call(RUBBLE_OUTLINE), rw.call(0.2), true)
		"waste_pit":
			# Bordo di terra, fondo scuro, poi gli scarti sopra il fondo.
			canvas.draw_colored_polygon(_blob_polygon(center, w.call(WASTE_PIT_RIM_RADIUS), 500, 12, 0.9, 1.06), tint.call(WASTE_PIT_RIM))
			canvas.draw_colored_polygon(_blob_polygon(center, w.call(WASTE_PIT_HOLE_RADIUS), 501, 10, 0.85, 1.05), tint.call(WASTE_PIT_HOLE))
			canvas.draw_colored_polygon(_blob_polygon(p.call(0.9, 0.8), w.call(0.9), 502, 7, 0.7, 1.1), tint.call(WASTE_PIT_SCRAP_HIDE))
			canvas.draw_colored_polygon(_blob_polygon(p.call(-1.1, 1.2), w.call(0.55), 503), tint.call(WASTE_PIT_SCRAP_STONE))
			canvas.draw_line(p.call(-1.6, -0.9), p.call(1.0, -1.5), tint.call(WOOD), w.call(0.35), true)
		"teaching_stump":
			# Ceppo: corteccia scura, sezione chiara, due anelli. Poi i banchi, ognuno col suo bordo scuro sotto.
			var stump_center: Vector2 = p.call(TEACHING_STUMP_CENTER.x, TEACHING_STUMP_CENTER.y)
			canvas.draw_circle(stump_center, w.call(TEACHING_STUMP_RADIUS), tint.call(LOG_BARK))
			canvas.draw_circle(stump_center, w.call(TEACHING_STUMP_RADIUS * 0.8), tint.call(LOG_END))
			canvas.draw_arc(stump_center, w.call(TEACHING_STUMP_RADIUS * 0.5), 0.0, TAU, 16, tint.call(LOG_RING), w.call(0.18), true)
			canvas.draw_arc(stump_center, w.call(TEACHING_STUMP_RADIUS * 0.22), 0.0, TAU, 12, tint.call(LOG_RING), w.call(0.15), true)
			for i in range(TEACHING_STUMP_SEATS.size()):
				var seat: Vector3 = TEACHING_STUMP_SEATS[i]
				canvas.draw_colored_polygon(
					_blob_polygon(p.call(seat.x, seat.y + 0.2), w.call(seat.z), 400 + i, 8, 0.85, 1.1), tint.call(SLAB_EDGE)
				)
				canvas.draw_colored_polygon(
					_blob_polygon(p.call(seat.x, seat.y), w.call(seat.z), 400 + i, 8, 0.85, 1.1),
					tint.call(STACKED_STONES_PILE_COLORS[i % STACKED_STONES_PILE_COLORS.size()])
				)
		"stacked_stones":
			# Dal basso in alto: pelle, cumulo, ossa (assi cardinali), rametti (diagonali). Sagome irregolari
			# deterministiche (seed fisso), stabili tra un ridisegno e l'altro; disposizione regolare a raggiera.
			canvas.draw_colored_polygon(
				_blob_polygon(center, w.call(STACKED_STONES_HIDE_RADIUS), 200, STACKED_STONES_HIDE_VERTICES, 0.9, 1.08),
				tint.call(HideIcon.HIDE_COLOR)
			)
			for i in range(STACKED_STONES_PILE.size()):
				var stone: Vector3 = STACKED_STONES_PILE[i]
				canvas.draw_colored_polygon(
					_blob_polygon(p.call(stone.x, stone.y), w.call(stone.z), i), tint.call(STACKED_STONES_PILE_COLORS[i])
				)
			for i in range(4):
				var bone_dir := Vector2.RIGHT.rotated(TAU * float(i) / 4.0)
				var bone_inner: Vector2 = p.call(bone_dir.x * STACKED_STONES_BONE_INNER, bone_dir.y * STACKED_STONES_BONE_INNER)
				var bone_outer: Vector2 = p.call(bone_dir.x * STACKED_STONES_BONE_OUTER, bone_dir.y * STACKED_STONES_BONE_OUTER)
				canvas.draw_line(bone_inner, bone_outer, tint.call(BoneIcon.BONE_COLOR), w.call(STACKED_STONES_BONE_WIDTH), true)
				# Estremità doppie dell'osso: due cerchietti affiancati per lato, perpendicolari all'osso.
				var side: Vector2 = bone_dir.orthogonal() * w.call(STACKED_STONES_BONE_KNOB_RADIUS * 0.7)
				for end_point in [bone_inner, bone_outer]:
					canvas.draw_circle(end_point + side, w.call(STACKED_STONES_BONE_KNOB_RADIUS), tint.call(BoneIcon.BONE_COLOR))
					canvas.draw_circle(end_point - side, w.call(STACKED_STONES_BONE_KNOB_RADIUS), tint.call(BoneIcon.BONE_COLOR))
			for i in range(4):
				var stick_dir := Vector2.RIGHT.rotated(TAU * (float(i) + 0.5) / 4.0)
				canvas.draw_line(
					p.call(stick_dir.x * STACKED_STONES_STICK_INNER, stick_dir.y * STACKED_STONES_STICK_INNER),
					p.call(stick_dir.x * STACKED_STONES_STICK_OUTER, stick_dir.y * STACKED_STONES_STICK_OUTER),
					tint.call(StickIcon.STICK_COLOR_DARK), w.call(STACKED_STONES_STICK_WIDTH), true
				)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Sagoma irregolare vista dall'alto (pietre e pelle delle pietre rituali): `vertices` vertici con raggio jittered attorno a
# `center` (stesso principio di MicroCellRenderer._pebble_blob_polygon), RNG locale seedata con `seed_index` così la
# forma è stabile tra un ridisegno e l'altro.
static func _blob_polygon(
	center: Vector2, radius: float, seed_index: int, vertices: int = STACKED_STONES_BLOB_VERTICES,
	jitter_min: float = 0.8, jitter_max: float = 1.12
) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_index
	var rotation := rng.randf_range(0.0, TAU)
	var points := PackedVector2Array()
	for v in range(vertices):
		var angle: float = rotation + TAU * float(v) / float(vertices)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius * rng.randf_range(jitter_min, jitter_max))
	return points
