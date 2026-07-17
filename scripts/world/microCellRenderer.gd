class_name MicroCellRenderer
extends Node2D

const CELL_SIZE: int = 10
const NEIGHBOR_STRIP_DEPTH: int = 40 # px, solo un'anteprima, non è territorio giocabile
const COLOR_STONE := Color(0.45, 0.45, 0.45, 0.6) # alpha bassa: i cerchi sovrapposti si fondono per densità
const VEGETATION_COLORS := {
	GameTypes.WorldObjectType.TREE: Color(0.10, 0.45, 0.15, 0.85),
}
const COLOR_TREE_TRUNK := Color(0.40, 0.26, 0.13, 0.95)
const COLOR_SHRUB_GREEN := Color(0.38, 0.55, 0.18, 0.85) # lobi "fogliosi"
const COLOR_SHRUB_BROWN := Color(0.50, 0.38, 0.20, 0.85) # lobi "legnosi"
const COLOR_GRASS_BASE := Color(0.28, 0.58, 0.18, 0.85) # verde più scuro
const COLOR_GRASS_TIP := Color(0.55, 0.80, 0.30, 0.85)  # verde più chiaro
# Ordine di disegno: dal più diffuso (GRASS) al più dominante (TREE), così quest'ultimo
# resta visivamente "sopra" — non dovrebbero mai sovrapporsi (le posizioni sono generate
# a esclusione reciproca), ma se mai succedesse il tipo dominante resta comunque visibile.
const VEGETATION_DRAW_ORDER := [
	GameTypes.WorldObjectType.GRASS,
	GameTypes.WorldObjectType.SHRUB,
	GameTypes.WorldObjectType.TREE,
]
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
	queue_redraw()


func set_vegetation_positions(positions: Dictionary) -> void:
	vegetation_positions = positions
	queue_redraw()


func _draw() -> void:
	if world == null:
		return

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


func _draw_stone_positions() -> void:
	for pos in stone_positions:
		_draw_stone_blob(pos)


# Ogni posizione stone è un poligono più largo della cella (raggio base > metà cella): quando
# due celle stone sono adiacenti le forme si sovrappongono e si fondono in un'unica massa
# continua grazie all'alpha compositing (più forme sovrapposte = colore più denso al centro,
# celle isolate/di bordo restano più leggere, senza bisogno di sfumature/gradient veri).
# Il contorno è un poligono a raggio irregolare (non un cerchio perfetto) per un aspetto più
# "roccioso": ogni vertice ha una propria variazione di raggio, derivata da hash(pos, indice
# vertice) — riproducibile ma diversa punta per punta. Stessa variazione di raggio/offset
# complessivo per posizione già calibrata (hash(pos) come per tree/shrub/grass).
const STONE_BLOB_VERTEX_COUNT: int = 9
const STONE_BLOB_VERTEX_JITTER: float = 0.18 # ±18% del raggio base, per vertice

func _draw_stone_blob(pos: Vector2i) -> void:
	var base := Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)
	var half: float = CELL_SIZE / 2.0
	var center := base + Vector2(half, half)

	var radius_variation: float = float(hash(pos) % 1000) / 1000.0
	var radius: float = lerp(6.5, 7.5, radius_variation)

	var offset_x: float = lerp(-0.8, 0.8, float(hash(pos * 5 + Vector2i(2, 9)) % 1000) / 1000.0)
	var offset_y: float = lerp(-0.8, 0.8, float(hash(pos * 5 + Vector2i(9, 2)) % 1000) / 1000.0)
	var blob_center := center + Vector2(offset_x, offset_y)

	var points := PackedVector2Array()
	for i in range(STONE_BLOB_VERTEX_COUNT):
		var angle: float = (float(i) / float(STONE_BLOB_VERTEX_COUNT)) * TAU
		var vertex_t: float = float(hash(pos * 41 + Vector2i(i, i * 13 + 3)) % 1000) / 1000.0
		var vertex_jitter: float = lerp(-STONE_BLOB_VERTEX_JITTER, STONE_BLOB_VERTEX_JITTER, vertex_t)
		var vertex_radius: float = radius * (1.0 + vertex_jitter)
		points.append(blob_center + Vector2(cos(angle), sin(angle)) * vertex_radius)

	draw_polygon(points, PackedColorArray([COLOR_STONE]))


func _draw_vegetation_positions() -> void:
	for resource_type in VEGETATION_DRAW_ORDER:
		if not vegetation_positions.has(resource_type):
			continue

		if resource_type == GameTypes.WorldObjectType.TREE:
			_draw_tree_positions(vegetation_positions[resource_type])
			continue

		if resource_type == GameTypes.WorldObjectType.SHRUB:
			_draw_shrub_positions(vegetation_positions[resource_type])
			continue

		if resource_type == GameTypes.WorldObjectType.GRASS:
			_draw_grass_positions(vegetation_positions[resource_type])
			continue


func _draw_tree_positions(positions: Array) -> void:
	for pos in positions:
		_draw_tree(pos)


# Albero stilizzato: tronco (rettangolo) + chioma (cerchio) sopra, con leggera variazione
# di dimensione/offset orizzontale per albero, derivata deterministicamente dalla sua
# posizione (le posizioni sono già frutto di una generazione deterministica per macrocella,
# quindi un hash della posizione basta a variare senza bisogno di altri seed).
func _draw_tree(pos: Vector2i) -> void:
	var base := Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)
	var half: float = CELL_SIZE / 2.0

	var size_variation: float = float(hash(pos) % 1000) / 1000.0
	var offset_variation: float = float(hash(pos * 7 + Vector2i(3, 11)) % 1000) / 1000.0
	var horizontal_offset: float = lerp(-1.0, 1.0, offset_variation)

	var trunk_width: float = 1.6
	var trunk_height: float = lerp(3.0, 4.0, size_variation)
	var trunk_x: float = base.x + half + horizontal_offset - trunk_width / 2.0
	var trunk_y: float = base.y + CELL_SIZE - trunk_height - 0.5
	draw_rect(Rect2(trunk_x, trunk_y, trunk_width, trunk_height), COLOR_TREE_TRUNK)

	var canopy_radius: float = lerp(2.8, 3.8, size_variation)
	var canopy_center := Vector2(base.x + half + horizontal_offset, trunk_y - canopy_radius * 0.6)
	draw_circle(canopy_center, canopy_radius, VEGETATION_COLORS[GameTypes.WorldObjectType.TREE])


func _draw_shrub_positions(positions: Array) -> void:
	for pos in positions:
		_draw_shrub(pos)


# Shrub stilizzato: 3-4 piccoli cerchi sovrapposti e sfalsati attorno al centro della cella,
# per dare un'idea di volume irregolare/cespuglioso — deliberatamente più basso e "disordinato"
# della sagoma verticale di TREE (nessun tronco, nessuna base fissa in basso). Stessa tecnica
# di TREE per la variazione deterministica: hash della posizione con moltiplicatori/offset
# diversi per ogni valore da variare, nessun seed aggiuntivo da passare al renderer.
const SHRUB_BLOB_SALTS := [
	Vector2i(5, 13),
	Vector2i(17, 3),
	Vector2i(11, 23),
	Vector2i(29, 7),
]

func _draw_shrub(pos: Vector2i) -> void:
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
		draw_circle(blob_center, radius, blob_color)


func _draw_grass_positions(positions: Array) -> void:
	for pos in positions:
		_draw_grass(pos)


# Ciuffo d'erba stilizzato: 5-8 fili sottili (linee) sparsi su quasi tutta la larghezza
# della cella (non da un unico punto), ciascuno con angolo/altezza/colore (due tonalità di
# verde) leggermente diversi — deliberatamente il più basso e "leggero" dei tre, per leggersi
# come il livello diffuso sotto shrub e tree, ma con più copertura visiva di prima. Stessa
# tecnica di variazione deterministica via hash(pos).
func _draw_grass(pos: Vector2i) -> void:
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
		draw_line(blade_base, tip, color, 1.1)


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
