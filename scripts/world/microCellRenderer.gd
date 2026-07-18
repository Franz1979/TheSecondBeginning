class_name MicroCellRenderer
extends Node2D

const CELL_SIZE: int = 10
const NEIGHBOR_STRIP_DEPTH: int = 40 # px, solo un'anteprima, non è territorio giocabile
const COLOR_STONE := Color(0.45, 0.45, 0.45, 0.6) # alpha bassa: i cerchi sovrapposti si fondono per densità
const VEGETATION_COLORS := {
	GameTypes.WorldObjectType.TREE: Color(0.10, 0.45, 0.15, 0.85),
}
const COLOR_TREE_TRUNK := Color(0.40, 0.26, 0.13, 0.95)
const COLOR_TREE_FRUIT_WILD := Color(0.75, 0.50, 0.15, 0.95) # marroncino: ghiande/castagne (wild_fruit)
const COLOR_TREE_FRUIT_DOMESTICABLE := Color(0.80, 0.15, 0.15, 0.95) # rosso: frutti da futura domesticazione (mele/pere)
const COLOR_SHRUB_GREEN := Color(0.38, 0.55, 0.18, 0.85) # lobi "fogliosi"
const COLOR_SHRUB_BROWN := Color(0.50, 0.38, 0.20, 0.85) # lobi "legnosi"
const COLOR_SHRUB_BERRY := Color(0.75, 0.08, 0.10, 0.95) # puntini rossi per gli shrub fruit_bearing
const COLOR_GRASS_BASE := Color(0.28, 0.58, 0.18, 0.85) # verde più scuro
const COLOR_GRASS_TIP := Color(0.55, 0.80, 0.30, 0.85)  # verde più chiaro
const BOUNDARY_DASH_COLOR := Color(0, 0, 0, 0.6)
const BOUNDARY_DASH_WIDTH: float = 2.0
const BOUNDARY_DASH_LENGTH: float = 6.0

const DIRECTIONS := [
	Vector2i(0, -1), # nord
	Vector2i(0, 1),  # sud
	Vector2i(1, 0),  # est
	Vector2i(-1, 0), # ovest
]

# Per ogni curva, il perno (angolo vero della griglia, in frazione 0..1 di grid_size) e
# l'intervallo di angoli (radianti) dell'arco che collega i due lati. Il raggio medio
# dell'arco è sempre grid_size/2, quindi l'arco tocca esattamente il bordo della cella nei
# punti dove prima finivano i due rettangoli dritti (stessa larghezza, nessuna discontinuità
# con i connettori nelle celle vicine) — solo la piega diventa un quarto di cerchio invece
# che uno spigolo a 90°.
const CORNER_ARC_DATA := {
	GameTypes.RiverShape.CORNER_TOP_RIGHT: {"pivot": Vector2(1, 0), "from": PI, "to": PI / 2.0},
	GameTypes.RiverShape.CORNER_RIGHT_BOTTOM: {"pivot": Vector2(1, 1), "from": -PI / 2.0, "to": -PI},
	GameTypes.RiverShape.CORNER_BOTTOM_LEFT: {"pivot": Vector2(0, 1), "from": 0.0, "to": -PI / 2.0},
	GameTypes.RiverShape.CORNER_LEFT_TOP: {"pivot": Vector2(0, 0), "from": PI / 2.0, "to": 0.0},
}
const CORNER_ARC_SEGMENTS: int = 24

var world: World
# Vector2i direzione -> MacroCellData/MacroCellState del vicino reale (o null se fuori mappa).
# Sono solo un'anteprima visiva: non fanno parte di `world` e non saranno mai interagibili.
var neighbor_cells: Dictionary = {}
var neighbor_states: Dictionary = {}

var is_river: bool = false
var river_shape: GameTypes.RiverShape = GameTypes.RiverShape.NONE
var river_thickness_ratio: float = 0.0 # river_space / MacroCellState.TOTAL_SPACE

var stone_positions: Array = [] # Array[Vector2i]
var vegetation_positions: Dictionary = {} # WorldObjectType -> Array[Vector2i]

# STONE_VARIANT_COUNT sagome-base pre-generate una sola volta (stessa formula di jitter
# per-vertice di sempre, seminata per variante invece che per posizione) e riusate per tutte le
# posizioni stone via MultiMesh — invece di un draw_polygon irregolare per ogni singola pietra,
# ne bastano STONE_VARIANT_COUNT in totale indipendentemente da quante pietre ci sono nella
# cella. Ogni pietra sceglie deterministicamente la sua variante da hash(pos) e riceve comunque
# posizione/rotazione/scala per-istanza uniche, quindi la ripetizione tra pietre non è mai
# "identica": solo la sagoma di base è condivisa fra gruppi di ~1/12 delle pietre.
var _stone_variant_meshes: Array = [] # ArrayMesh, indicizzato per variante — costruito una volta sola
var _stone_multimeshes: Array = [] # MultiMesh, indicizzato per variante — un draw_multimesh ciascuno
# Quota fruit_bearing/totale della composizione SHRUB della macrocella (0..1). Il renderer non
# conosce subtype_composition: riceve solo questo rapporto già calcolato dal chiamante (stessa
# separazione di responsabilità di vegetation_positions, che arriva già generato).
var shrub_fruit_ratio: float = 0.0
# Quota wild_fruit/totale e domesticable_fruit/totale della composizione TREE della macrocella
# (0..1 ciascuno, indipendenti) — stessa separazione di responsabilità di shrub_fruit_ratio
# sopra. Due rapporti separati (non uno combinato) perché ora ogni sottotipo ha un colore
# distinto sulla mappa (vedi COLOR_TREE_FRUIT_WILD/COLOR_TREE_FRUIT_DOMESTICABLE).
var tree_wild_fruit_ratio: float = 0.0
var tree_domesticable_fruit_ratio: float = 0.0

# DEBUG TEMPORANEO: conta le chiamate di disegno EFFETTIVE (draw_multimesh/draw_multiline_colors)
# per stone+grass+shrub+tree+bacche in un singolo _draw(), non più le istanze logiche — dopo la
# conversione a MultiMesh/draw_multiline_colors il numero atteso è un piccolo valore costante
# (stone: fino a 12, vegetazione: fino a 5), indipendente da quante posizioni ci sono nella
# cella. Da rimuovere una volta confermato che il freeze di rendering non si presenta più.
var _debug_draw_primitive_count: int = 0


func setup(_world: World) -> void:
	world = _world
	queue_redraw()


func set_neighbors(neighbors: Dictionary, states: Dictionary = {}) -> void:
	neighbor_cells = neighbors
	neighbor_states = states
	queue_redraw()


# Da chiamare solo se la macrocella reale ha water_type == RIVER: `shape` è il suo
# river_shape reale, `thickness_ratio` è river_space/TOTAL_SPACE (quanto della cella
# è dedicato al fiume, usato per dare uno spessore proporzionale alla fascia disegnata).
func set_river(shape: GameTypes.RiverShape, thickness_ratio: float) -> void:
	is_river = true
	river_shape = shape
	river_thickness_ratio = clamp(thickness_ratio, 0.0, 1.0)
	queue_redraw()


func set_stone_positions(positions: Array) -> void:
	stone_positions = positions
	_rebuild_stone_multimeshes()
	queue_redraw()


func set_vegetation_positions(positions: Dictionary) -> void:
	vegetation_positions = positions
	_rebuild_tree_multimeshes()
	_rebuild_shrub_multimeshes()
	_rebuild_grass_buffers()
	queue_redraw()


func set_shrub_fruit_ratio(ratio: float) -> void:
	shrub_fruit_ratio = clamp(ratio, 0.0, 1.0)
	# Solo le bacche dipendono dal rapporto: niente bisogno di ricalcolare anche tree/grass qui.
	_rebuild_shrub_multimeshes()
	queue_redraw()


func set_tree_fruit_ratios(wild_ratio: float, domesticable_ratio: float) -> void:
	tree_wild_fruit_ratio = clamp(wild_ratio, 0.0, 1.0)
	tree_domesticable_fruit_ratio = clamp(domesticable_ratio, 0.0, 1.0)
	# Solo i dot frutto dipendono dai rapporti, ma vivono nello stesso rebuild di trunk/canopy.
	_rebuild_tree_multimeshes()
	queue_redraw()


func _draw() -> void:
	if world == null:
		return

	_debug_draw_primitive_count = 0

	for cell in world.cells:
		var color: Color = TerrainColors.get_land_color(cell) if is_river else TerrainColors.get_cell_color(cell)
		var rect := Rect2(
			cell.x * CELL_SIZE,
			cell.y * CELL_SIZE,
			CELL_SIZE,
			CELL_SIZE
		)
		draw_rect(rect, color)
		draw_rect(rect, TerrainColors.GRID, false, 1.0)

	var grid_size: int = World.WIDTH * CELL_SIZE
	if is_river:
		_draw_river(grid_size)

	_draw_stone_positions()
	_draw_vegetation_positions()
	_draw_neighbor_previews(grid_size)
	_draw_boundary(grid_size)

	print("[DEBUG RENDER] primitive stone+grass+shrub+tree+bacche in questo _draw(): ", _debug_draw_primitive_count)


func _draw_stone_positions() -> void:
	for mm in _stone_multimeshes:
		if mm.instance_count <= 0:
			continue
		draw_multimesh(mm, null)
		_debug_draw_primitive_count += 1


# Ogni sagoma-variante è un poligono a raggio irregolare (non un cerchio perfetto) per un
# aspetto più "roccioso": ogni vertice ha una propria variazione di raggio, derivata da
# hash(variante, indice vertice) — stessa formula di jitter di sempre, solo seminata per
# variante invece che per posizione (vedi commento su _stone_variant_meshes sopra). Il colore è
# cotto direttamente nei vertici della mesh (bianco * COLOR_STONE), quindi ogni pietra risulta
# comunque più larga della cella e le forme sovrapposte si fondono per alpha come prima.
const STONE_BLOB_VERTEX_COUNT: int = 9
const STONE_BLOB_VERTEX_JITTER: float = 0.18 # ±18% del raggio base, per vertice
const STONE_VARIANT_COUNT: int = 12


func _ensure_stone_multimeshes() -> void:
	if not _stone_multimeshes.is_empty():
		return

	for variant in range(STONE_VARIANT_COUNT):
		_stone_variant_meshes.append(_build_stone_variant_mesh(variant))

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.mesh = _stone_variant_meshes[variant]
		mm.instance_count = 0
		_stone_multimeshes.append(mm)


func _build_stone_variant_mesh(variant: int) -> ArrayMesh:
	var radius_variation: float = float(hash(Vector2i(variant, 977)) % 1000) / 1000.0
	var radius: float = lerp(6.5, 7.5, radius_variation)

	var points := PackedVector2Array()
	for i in range(STONE_BLOB_VERTEX_COUNT):
		var angle: float = (float(i) / float(STONE_BLOB_VERTEX_COUNT)) * TAU
		var vertex_t: float = float(hash(Vector2i(variant, i) * 41 + Vector2i(i * 13 + 3, 7)) % 1000) / 1000.0
		var vertex_jitter: float = lerp(-STONE_BLOB_VERTEX_JITTER, STONE_BLOB_VERTEX_JITTER, vertex_t)
		var vertex_radius: float = radius * (1.0 + vertex_jitter)
		points.append(Vector2(cos(angle), sin(angle)) * vertex_radius)

	return _build_fan_mesh(points, COLOR_STONE)


# Ricalcola i buffer istanza (posizione/rotazione/scala per-pietra) ogni volta che le posizioni
# stone cambiano — stesso momento in cui prima si ridisegnava tutto, solo che ora il lavoro
# O(N) produce dati per MultiMesh invece di emettere subito un draw_polygon per pietra.
func _rebuild_stone_multimeshes() -> void:
	_ensure_stone_multimeshes()

	var buckets: Array = []
	for i in range(STONE_VARIANT_COUNT):
		buckets.append([]) # Array[Transform2D]

	var half: float = CELL_SIZE / 2.0
	for pos in stone_positions:
		var variant: int = posmod(hash(pos), STONE_VARIANT_COUNT)

		var offset_x: float = lerp(-0.8, 0.8, float(hash(pos * 5 + Vector2i(2, 9)) % 1000) / 1000.0)
		var offset_y: float = lerp(-0.8, 0.8, float(hash(pos * 5 + Vector2i(9, 2)) % 1000) / 1000.0)
		var base := Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)
		var center := base + Vector2(half, half) + Vector2(offset_x, offset_y)

		# Rotazione + lieve variazione di scala per-istanza: disguisano la ripetizione tra le
		# STONE_VARIANT_COUNT sagome condivise, oltre alla posizione già unica per pietra.
		var rotation: float = (float(hash(pos * 13 + Vector2i(31, 17)) % 1000) / 1000.0) * TAU
		var scale_variation: float = lerp(0.9, 1.1, float(hash(pos * 19 + Vector2i(3, 41)) % 1000) / 1000.0)

		var transform := Transform2D(rotation, Vector2.ZERO).scaled(Vector2(scale_variation, scale_variation))
		transform.origin = center

		buckets[variant].append(transform)

	for variant in range(STONE_VARIANT_COUNT):
		var transforms: Array = buckets[variant]
		var mm: MultiMesh = _stone_multimeshes[variant]
		mm.instance_count = transforms.size()
		for i in range(transforms.size()):
			mm.set_instance_transform_2d(i, transforms[i])


# Triangola a ventaglio (dal centro locale 0,0) un poligono convesso/quasi-convesso come quello
# degli stone blob, cuocendo color direttamente nei vertici — così una MultiMesh che riusa
# questa mesh non ha bisogno di colore per-istanza. Riusabile per qualunque forma a ventaglio
# futura (es. i cerchi unitari di tree/shrub/bacche saranno costruiti allo stesso modo).
static func _build_fan_mesh(points: PackedVector2Array, color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(color)

	var center := Vector3.ZERO
	var count := points.size()
	for i in range(count):
		var a := Vector3(points[i].x, points[i].y, 0.0)
		var b := Vector3(points[(i + 1) % count].x, points[(i + 1) % count].y, 0.0)
		st.add_vertex(center)
		st.add_vertex(a)
		st.add_vertex(b)

	return st.commit()


# Guard economico prima di ogni draw_polygon/draw_colored_polygon con un array di punti
# generato dinamicamente: serve almeno 3 vertici, e ognuno deve avere coordinate finite (non
# NaN/Inf). Oggi nessuna chiamata del renderer può produrre un array del genere (i conteggi di
# vertici sono costanti fisse, i valori sempre derivati da lerp con estremi finiti), ma il
# controllo resta economico da avere come rete di sicurezza se quei presupposti cambiano.
static func _is_valid_polygon_points(points: PackedVector2Array) -> bool:
	if points.size() < 3:
		return false
	for p in points:
		if not (is_finite(p.x) and is_finite(p.y)):
			return false
	return true


# Ordine di disegno preservato (dal più diffuso al più dominante, così TREE resta sopra):
# grass (draw_multiline_colors) -> shrub blobs -> bacche -> tree trunk -> tree canopy -> dot
# frutto wild -> dot frutto domesticable (sopra la chioma, altrimenti invisibili). Ogni
# gruppo è oggi al più UNA chiamata di disegno, indipendentemente da quante istanze contiene —
# i buffer (transform/colore per MultiMesh, punti/colori per grass) sono già pronti, ricalcolati
# nei setter (_rebuild_*) quando le posizioni cambiano, non qui.
func _draw_vegetation_positions() -> void:
	if not _grass_points.is_empty():
		draw_multiline_colors(_grass_points, _grass_colors, 1.1)
		_debug_draw_primitive_count += 1

	if _shrub_multimesh != null and _shrub_multimesh.instance_count > 0:
		draw_multimesh(_shrub_multimesh, null)
		_debug_draw_primitive_count += 1

	if _berry_multimesh != null and _berry_multimesh.instance_count > 0:
		draw_multimesh(_berry_multimesh, null)
		_debug_draw_primitive_count += 1

	if _tree_trunk_multimesh != null and _tree_trunk_multimesh.instance_count > 0:
		draw_multimesh(_tree_trunk_multimesh, null)
		_debug_draw_primitive_count += 1

	if _tree_canopy_multimesh != null and _tree_canopy_multimesh.instance_count > 0:
		draw_multimesh(_tree_canopy_multimesh, null)
		_debug_draw_primitive_count += 1

	if _tree_fruit_wild_multimesh != null and _tree_fruit_wild_multimesh.instance_count > 0:
		draw_multimesh(_tree_fruit_wild_multimesh, null)
		_debug_draw_primitive_count += 1

	if _tree_fruit_domesticable_multimesh != null and _tree_fruit_domesticable_multimesh.instance_count > 0:
		draw_multimesh(_tree_fruit_domesticable_multimesh, null)
		_debug_draw_primitive_count += 1


const VEGETATION_CIRCLE_SEGMENTS: int = 12

var _tree_trunk_mesh: ArrayMesh
var _tree_canopy_mesh: ArrayMesh
var _tree_fruit_wild_mesh: ArrayMesh
var _tree_fruit_domesticable_mesh: ArrayMesh
var _shrub_blob_mesh: ArrayMesh # bianca: il colore per-lobo arriva per-istanza (use_colors)
var _berry_mesh: ArrayMesh
var _vegetation_meshes_ready: bool = false

var _tree_trunk_multimesh: MultiMesh
var _tree_canopy_multimesh: MultiMesh
var _tree_fruit_wild_multimesh: MultiMesh
var _tree_fruit_domesticable_multimesh: MultiMesh
var _shrub_multimesh: MultiMesh
var _berry_multimesh: MultiMesh


func _ensure_vegetation_meshes() -> void:
	if _vegetation_meshes_ready:
		return
	_vegetation_meshes_ready = true

	_tree_trunk_mesh = _build_quad_mesh(COLOR_TREE_TRUNK)
	_tree_canopy_mesh = _build_circle_mesh(VEGETATION_CIRCLE_SEGMENTS, VEGETATION_COLORS[GameTypes.WorldObjectType.TREE])
	_tree_fruit_wild_mesh = _build_circle_mesh(VEGETATION_CIRCLE_SEGMENTS, COLOR_TREE_FRUIT_WILD)
	_tree_fruit_domesticable_mesh = _build_circle_mesh(VEGETATION_CIRCLE_SEGMENTS, COLOR_TREE_FRUIT_DOMESTICABLE)
	_shrub_blob_mesh = _build_circle_mesh(VEGETATION_CIRCLE_SEGMENTS, Color.WHITE)
	_berry_mesh = _build_circle_mesh(VEGETATION_CIRCLE_SEGMENTS, COLOR_SHRUB_BERRY)


func _ensure_vegetation_multimeshes() -> void:
	if _tree_trunk_multimesh != null:
		return

	_tree_trunk_multimesh = _make_multimesh(_tree_trunk_mesh, false)
	_tree_canopy_multimesh = _make_multimesh(_tree_canopy_mesh, false)
	_tree_fruit_wild_multimesh = _make_multimesh(_tree_fruit_wild_mesh, false)
	_tree_fruit_domesticable_multimesh = _make_multimesh(_tree_fruit_domesticable_mesh, false)
	_shrub_multimesh = _make_multimesh(_shrub_blob_mesh, true)
	_berry_multimesh = _make_multimesh(_berry_mesh, false)


static func _make_multimesh(mesh: ArrayMesh, use_colors: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = use_colors
	mm.mesh = mesh
	mm.instance_count = 0
	return mm


static func _apply_transforms(mm: MultiMesh, transforms: Array) -> void:
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform_2d(i, transforms[i])


# Quadrato unitario ancorato in alto a sinistra (0,0)-(1,1): scalato per (trunk_width,
# trunk_height) e traslato in (trunk_x, trunk_y) riproduce esattamente il vecchio
# Rect2(trunk_x, trunk_y, trunk_width, trunk_height).
static func _build_quad_mesh(color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(color)
	var a := Vector3(0, 0, 0)
	var b := Vector3(1, 0, 0)
	var c := Vector3(1, 1, 0)
	var d := Vector3(0, 1, 0)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)
	return st.commit()


# Cerchio unitario (raggio 1, centrato all'origine): scalato per il raggio reale per-istanza
# riproduce esattamente il vecchio draw_circle(center, radius, color).
static func _build_circle_mesh(segments: int, color: Color) -> ArrayMesh:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle: float = (float(i) / float(segments)) * TAU
		points.append(Vector2(cos(angle), sin(angle)))
	return _build_fan_mesh(points, color)


# Albero stilizzato: tronco (rettangolo) + chioma (cerchio) sopra, con leggera variazione
# di dimensione/offset orizzontale per albero, derivata deterministicamente dalla sua
# posizione — stessa formula di sempre, solo scritta in un transform per-istanza invece che
# emessa subito come draw_rect/draw_circle.
func _rebuild_tree_multimeshes() -> void:
	_ensure_vegetation_meshes()
	_ensure_vegetation_multimeshes()

	var positions: Array = vegetation_positions.get(GameTypes.WorldObjectType.TREE, [])
	var trunk_transforms: Array = []
	var canopy_transforms: Array = []
	var wild_fruit_transforms: Array = []
	var domesticable_fruit_transforms: Array = []

	for pos in positions:
		var base := Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)
		var half: float = CELL_SIZE / 2.0

		var size_variation: float = float(hash(pos) % 1000) / 1000.0
		var offset_variation: float = float(hash(pos * 7 + Vector2i(3, 11)) % 1000) / 1000.0
		var horizontal_offset: float = lerp(-1.0, 1.0, offset_variation)

		var trunk_width: float = 1.6
		var trunk_height: float = lerp(3.0, 4.0, size_variation)
		var trunk_x: float = base.x + half + horizontal_offset - trunk_width / 2.0
		var trunk_y: float = base.y + CELL_SIZE - trunk_height - 0.5

		var trunk_transform := Transform2D(0, Vector2.ZERO).scaled(Vector2(trunk_width, trunk_height))
		trunk_transform.origin = Vector2(trunk_x, trunk_y)
		trunk_transforms.append(trunk_transform)

		var canopy_radius: float = lerp(2.8, 3.8, size_variation)
		var canopy_center := Vector2(base.x + half + horizontal_offset, trunk_y - canopy_radius * 0.6)
		var canopy_transform := Transform2D(0, Vector2.ZERO).scaled(Vector2(canopy_radius, canopy_radius))
		canopy_transform.origin = canopy_center
		canopy_transforms.append(canopy_transform)

		if _is_tree_fruit_bearing(pos):
			var dots := _build_tree_fruit_transforms(pos, canopy_center, canopy_radius)
			if _is_tree_fruit_domesticable(pos):
				domesticable_fruit_transforms.append_array(dots)
			else:
				wild_fruit_transforms.append_array(dots)

	_apply_transforms(_tree_trunk_multimesh, trunk_transforms)
	_apply_transforms(_tree_canopy_multimesh, canopy_transforms)
	_apply_transforms(_tree_fruit_wild_multimesh, wild_fruit_transforms)
	_apply_transforms(_tree_fruit_domesticable_multimesh, domesticable_fruit_transforms)


# Identità fruttifera stabile per posizione, stesso pattern di _is_shrub_fruit_bearing sotto
# (hash(pos) puro confrontato con la soglia combinata wild+domesticable) ma con salt diverso
# per non correlare le due sequenze — un microcella potrebbe altrimenti risultare "fruttifera"
# per entrambe le risorse sempre insieme o mai, il che non ha basi ecologiche.
func _is_tree_fruit_bearing(pos: Vector2i) -> bool:
	var hash_value: float = float(hash(pos * 3 + Vector2i(211, 149)) % 100000) / 100000.0
	return hash_value < (tree_wild_fruit_ratio + tree_domesticable_fruit_ratio)


# Seconda classificazione, indipendente dalla prima (salt diverso): SOLO per le posizioni già
# fruttifere secondo _is_tree_fruit_bearing, decide wild vs domesticable confrontando un hash
# con la probabilità condizionata domesticable/(wild+domesticable). Stessa stabilità posizionale
# delle altre soglie hash del renderer: finché il rapporto tra i due resta invariato, una
# posizione classificata domesticable lo resta; solo i casi "al margine" cambiano lato se il
# rapporto si sposta.
func _is_tree_fruit_domesticable(pos: Vector2i) -> bool:
	var total_ratio: float = tree_wild_fruit_ratio + tree_domesticable_fruit_ratio
	if total_ratio <= 0.0:
		return false
	var hash_value: float = float(hash(pos * 5 + Vector2i(83, 227)) % 100000) / 100000.0
	return hash_value < (tree_domesticable_fruit_ratio / total_ratio)


const TREE_FRUIT_SALTS := [
	Vector2i(59, 5),
	Vector2i(23, 61),
	Vector2i(37, 89),
]

# 1-2 piccoli dot (colore assegnato dal chiamante in base a wild/domesticable) lungo il bordo
# della chioma — stesso principio geometrico delle bacche shrub, angolo/distanza per-dot
# derivati da hash(pos).
func _build_tree_fruit_transforms(pos: Vector2i, canopy_center: Vector2, canopy_radius: float) -> Array:
	var transforms: Array = []
	var dot_count: int = 2 + (hash(pos * 17 + Vector2i(4, 90)) % 2) # 2 o 3 dot
	for i in range(dot_count):
		var salt: Vector2i = TREE_FRUIT_SALTS[i % TREE_FRUIT_SALTS.size()]
		var angle: float = (float(hash(pos * salt.x + Vector2i(salt.y, i + 200)) % 1000) / 1000.0) * TAU
		var distance: float = lerp(0.5, 1.0, float(hash(pos * salt.y + Vector2i(i + 200, salt.x)) % 1000) / 1000.0) * canopy_radius
		var dot_center := canopy_center + Vector2(cos(angle), sin(angle)) * distance

		var dot_transform := Transform2D(0, Vector2.ZERO).scaled(Vector2(0.6, 0.6))
		dot_transform.origin = dot_center
		transforms.append(dot_transform)
	return transforms


# Shrub stilizzato: 3-4 piccoli cerchi sovrapposti e sfalsati attorno al centro della cella
# (colore per-istanza via MultiMesh.use_colors, gradiente verde/marrone come sempre) + le
# eventuali bacche (Regola di stabilità posizionale invariata: _is_shrub_fruit_bearing decide
# ancora da hash(pos) puro, non dalla composizione). Ricalcolato anche quando cambia solo
# shrub_fruit_ratio (set_shrub_fruit_ratio), non solo le posizioni.
const SHRUB_BLOB_SALTS := [
	Vector2i(5, 13),
	Vector2i(17, 3),
	Vector2i(11, 23),
	Vector2i(29, 7),
]
const SHRUB_BERRY_SALTS := [
	Vector2i(41, 19),
	Vector2i(7, 37),
	Vector2i(53, 3),
]

func _rebuild_shrub_multimeshes() -> void:
	_ensure_vegetation_meshes()
	_ensure_vegetation_multimeshes()

	var positions: Array = vegetation_positions.get(GameTypes.WorldObjectType.SHRUB, [])
	var blob_transforms: Array = []
	var blob_colors: Array = []
	var berry_transforms: Array = []

	for pos in positions:
		var base := Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)
		var half: float = CELL_SIZE / 2.0
		var center := base + Vector2(half, half)

		var blob_count: int = 3 + (hash(pos) % 2) # 3 o 4 lobi, variabile per shrub
		for i in range(blob_count):
			var salt: Vector2i = SHRUB_BLOB_SALTS[i]
			var angle: float = (float(hash(pos * salt.x + Vector2i(salt.y, i)) % 1000) / 1000.0) * TAU
			var distance: float = lerp(0.8, 1.8, float(hash(pos * salt.y + Vector2i(i, salt.x)) % 1000) / 1000.0)
			var radius: float = lerp(1.4, 2.2, float(hash(pos * (salt.x + salt.y) + Vector2i(i, i)) % 1000) / 1000.0)
			var hue_t: float = float(hash(pos * (salt.x + salt.y + 41) + Vector2i(i, i + 1)) % 1000) / 1000.0
			var blob_color: Color = COLOR_SHRUB_GREEN.lerp(COLOR_SHRUB_BROWN, hue_t)
			var blob_center := center + Vector2(cos(angle), sin(angle)) * distance

			var blob_transform := Transform2D(0, Vector2.ZERO).scaled(Vector2(radius, radius))
			blob_transform.origin = blob_center
			blob_transforms.append(blob_transform)
			blob_colors.append(blob_color)

		if _is_shrub_fruit_bearing(pos):
			var berry_count: int = 2 + (hash(pos * 61 + Vector2i(3, 8)) % 2) # 2 o 3 bacche
			for i in range(berry_count):
				var berry_salt: Vector2i = SHRUB_BERRY_SALTS[i % SHRUB_BERRY_SALTS.size()]
				var berry_angle: float = (float(hash(pos * berry_salt.x + Vector2i(berry_salt.y, i + 100)) % 1000) / 1000.0) * TAU
				var berry_distance: float = lerp(0.6, 1.6, float(hash(pos * berry_salt.y + Vector2i(i + 100, berry_salt.x)) % 1000) / 1000.0)
				var berry_center := center + Vector2(cos(berry_angle), sin(berry_angle)) * berry_distance

				var berry_transform := Transform2D(0, Vector2.ZERO).scaled(Vector2(0.55, 0.55))
				berry_transform.origin = berry_center
				berry_transforms.append(berry_transform)

	_apply_transforms(_shrub_multimesh, blob_transforms)
	for i in range(blob_colors.size()):
		_shrub_multimesh.set_instance_color(i, blob_colors[i])

	_apply_transforms(_berry_multimesh, berry_transforms)


# Identità fruttifera stabile per posizione: un valore 0..1 derivato SOLO da pos (nessuna
# dipendenza dalla composizione, dall'anno o da quante volte la scena è stata riaperta) confrontato
# con shrub_fruit_ratio corrente. Finché il rapporto fruit_bearing/totale resta uguale o cresce,
# ogni posizione che era fruttifera lo resta; solo se il rapporto scende, le posizioni "al margine"
# (hash-value appena sotto la vecchia soglia) smettono di esserlo — coerente con una reale
# diminuzione locale del sottotipo, non un redraw arbitrario.
func _is_shrub_fruit_bearing(pos: Vector2i) -> bool:
	var hash_value: float = float(hash(pos * 3 + Vector2i(97, 53)) % 100000) / 100000.0
	return hash_value < shrub_fruit_ratio


# Ciuffo d'erba stilizzato: 5-8 fili sottili (linee) sparsi su quasi tutta la larghezza della
# cella, ciascuno con angolo/altezza/colore leggermente diversi — stessa formula di sempre, ma
# accumulata in un'unica coppia di buffer punti/colori invece di un draw_line per filo: tutti i
# fili della cella vengono poi disegnati con una sola draw_multiline_colors in _draw().
var _grass_points: PackedVector2Array = PackedVector2Array()
var _grass_colors: PackedColorArray = PackedColorArray()

func _rebuild_grass_buffers() -> void:
	var points := PackedVector2Array()
	var colors := PackedColorArray()

	var positions: Array = vegetation_positions.get(GameTypes.WorldObjectType.GRASS, [])
	for pos in positions:
		var base := Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)
		var blade_count: int = 5 + (hash(pos) % 4) # 5-8 fili

		for i in range(blade_count):
			var salt: int = i * 19 + 7
			var blade_x: float = lerp(0.5, CELL_SIZE - 0.5, float(hash(pos * salt + Vector2i(i, salt)) % 1000) / 1000.0)
			var blade_y_inset: float = lerp(0.3, 1.2, float(hash(pos * (salt + 3) + Vector2i(salt, i)) % 1000) / 1000.0)
			var blade_base := Vector2(base.x + blade_x, base.y + CELL_SIZE - blade_y_inset)

			var angle_variation: float = lerp(-0.5, 0.5, float(hash(pos * (salt + 11) + Vector2i(i, salt)) % 1000) / 1000.0)
			var angle: float = -PI / 2.0 + angle_variation # verso l'alto, con oscillazione laterale
			var height: float = lerp(2.5, 4.5, float(hash(pos * (salt + 17) + Vector2i(salt, i)) % 1000) / 1000.0)
			var hue_t: float = float(hash(pos * (salt + 23) + Vector2i(i, salt + 5)) % 1000) / 1000.0
			var color: Color = COLOR_GRASS_BASE.lerp(COLOR_GRASS_TIP, hue_t)

			var tip: Vector2 = blade_base + Vector2(cos(angle), sin(angle)) * height
			points.append(blade_base)
			points.append(tip)
			# draw_multiline_colors vuole un colore per SEGMENTO (colors.size() == points.size()/2),
			# non uno per punto — un'unica append qui, non due.
			colors.append(color)

	_grass_points = points
	_grass_colors = colors


# Fascia di fiume al centro della cella, orientata secondo river_shape — stessa geometria
# di WorldRenderer._draw_river_cell ma scalata all'intera griglia 100x100 invece di una
# singola cella da 10px.
func _draw_river(grid_size: int) -> void:
	var thickness: float = max(grid_size * river_thickness_ratio, 1.0)
	var half: float = grid_size / 2.0
	var center: float = half

	if CORNER_ARC_DATA.has(river_shape):
		var data: Dictionary = CORNER_ARC_DATA[river_shape]
		var pivot: Vector2 = data["pivot"] * grid_size
		_draw_river_arc(pivot, data["from"], data["to"], half - thickness / 2.0, half + thickness / 2.0)
		return

	match river_shape:
		GameTypes.RiverShape.VERTICAL:
			draw_rect(Rect2(center - thickness / 2.0, 0, thickness, grid_size), TerrainColors.RIVER)

		GameTypes.RiverShape.HORIZONTAL:
			draw_rect(Rect2(0, center - thickness / 2.0, grid_size, thickness), TerrainColors.RIVER)

		GameTypes.RiverShape.FULL:
			draw_rect(Rect2(0, 0, grid_size, grid_size), TerrainColors.RIVER)

		_:
			draw_rect(Rect2(center - thickness / 2.0, 0, thickness, grid_size), TerrainColors.RIVER)


# Fascia ad anello (settore di corona circolare) tra due raggi, imperniata sull'angolo vero
# della cella: dà alla curva un bordo esterno arrotondato invece che a blocchi.
func _draw_river_arc(pivot: Vector2, angle_from: float, angle_to: float, inner_radius: float, outer_radius: float) -> void:
	var points := PackedVector2Array()
	for i in range(CORNER_ARC_SEGMENTS + 1):
		var t: float = float(i) / float(CORNER_ARC_SEGMENTS)
		var angle: float = lerp(angle_from, angle_to, t)
		points.append(pivot + Vector2(cos(angle), sin(angle)) * outer_radius)
	for i in range(CORNER_ARC_SEGMENTS + 1):
		var t: float = float(i) / float(CORNER_ARC_SEGMENTS)
		var angle: float = lerp(angle_to, angle_from, t)
		points.append(pivot + Vector2(cos(angle), sin(angle)) * inner_radius)

	if not _is_valid_polygon_points(points):
		push_warning("MicroCellRenderer: arco fiume scartato, punti non validi (size=%d)" % points.size())
		return

	draw_colored_polygon(points, TerrainColors.RIVER)


func _draw_neighbor_previews(grid_size: int) -> void:
	var center: float = grid_size / 2.0

	for direction in DIRECTIONS:
		var neighbor: MacroCellData = neighbor_cells.get(direction, null)
		if neighbor == null:
			continue

		var rect: Rect2
		match direction:
			Vector2i(0, -1):
				rect = Rect2(0, -NEIGHBOR_STRIP_DEPTH, grid_size, NEIGHBOR_STRIP_DEPTH)
			Vector2i(0, 1):
				rect = Rect2(0, grid_size, grid_size, NEIGHBOR_STRIP_DEPTH)
			Vector2i(1, 0):
				rect = Rect2(grid_size, 0, NEIGHBOR_STRIP_DEPTH, grid_size)
			Vector2i(-1, 0):
				rect = Rect2(-NEIGHBOR_STRIP_DEPTH, 0, NEIGHBOR_STRIP_DEPTH, grid_size)

		# Il vicino è controllato per conto suo, a prescindere da cosa sia la cella centrale
		# (fiume, lago, montagna...): se QUEL vicino è davvero un fiume, la sua striscia mostra
		# il suo terreno più una fascia sottile con lo spessore del SUO river_space, non il
		# pieno colore acqua. Lago/mare restano un riempimento pieno, sono già acqua per intero.
		if neighbor.water_type == GameTypes.WaterType.RIVER:
			draw_rect(rect, TerrainColors.get_land_color(neighbor))
			_draw_river_connector(direction, grid_size, center, _neighbor_river_thickness(direction, grid_size))
		else:
			draw_rect(rect, TerrainColors.get_cell_color(neighbor))


func _neighbor_river_thickness(direction: Vector2i, grid_size: int) -> float:
	var state: MacroCellState = neighbor_states.get(direction, null)
	var ratio: float = 0.0
	if state != null:
		ratio = float(state.get_river_space()) / float(MacroCellState.TOTAL_SPACE)
	return max(grid_size * ratio, 1.0)


# Piccolo prolungamento del fiume dentro la striscia di anteprima del vicino, per far
# vedere che il fiume continua (o finisce) in quella direzione.
func _draw_river_connector(direction: Vector2i, grid_size: int, center: float, thickness: float) -> void:
	var rect: Rect2
	match direction:
		Vector2i(0, -1):
			rect = Rect2(center - thickness / 2.0, -NEIGHBOR_STRIP_DEPTH, thickness, NEIGHBOR_STRIP_DEPTH)
		Vector2i(0, 1):
			rect = Rect2(center - thickness / 2.0, grid_size, thickness, NEIGHBOR_STRIP_DEPTH)
		Vector2i(1, 0):
			rect = Rect2(grid_size, center - thickness / 2.0, NEIGHBOR_STRIP_DEPTH, thickness)
		Vector2i(-1, 0):
			rect = Rect2(-NEIGHBOR_STRIP_DEPTH, center - thickness / 2.0, NEIGHBOR_STRIP_DEPTH, thickness)

	draw_rect(rect, TerrainColors.RIVER)


# Riga tratteggiata sul perimetro del quadrato 100x100 reale: segna dove finisce la
# cella "giocabile" e comincia la sola anteprima dei vicini.
func _draw_boundary(grid_size: int) -> void:
	draw_dashed_line(Vector2(0, 0), Vector2(grid_size, 0), BOUNDARY_DASH_COLOR, BOUNDARY_DASH_WIDTH, BOUNDARY_DASH_LENGTH)
	draw_dashed_line(Vector2(0, grid_size), Vector2(grid_size, grid_size), BOUNDARY_DASH_COLOR, BOUNDARY_DASH_WIDTH, BOUNDARY_DASH_LENGTH)
	draw_dashed_line(Vector2(0, 0), Vector2(0, grid_size), BOUNDARY_DASH_COLOR, BOUNDARY_DASH_WIDTH, BOUNDARY_DASH_LENGTH)
	draw_dashed_line(Vector2(grid_size, 0), Vector2(grid_size, grid_size), BOUNDARY_DASH_COLOR, BOUNDARY_DASH_WIDTH, BOUNDARY_DASH_LENGTH)
