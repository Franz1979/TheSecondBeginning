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
const COLOR_FISH_BODY := Color(0.45, 0.55, 0.65, 0.85) # grigio-azzurro argentato
const COLOR_FISH_TAIL := Color(0.35, 0.44, 0.53, 0.85) # leggermente più scuro del corpo
# Palette erba per stagione (base=radice/filo scuro, tip=punta): PRIMAVERA/ESTATE riusano
# COLOR_GRASS_BASE/TIP sopra (verde vivo, invariato), AUTUNNO vira a dorato/paglierino,
# INVERNO a un verde-grigio spento (vegetazione dormiente). Cambio netto a inizio stagione,
# non una transizione giorno per giorno — vedi _rebuild_grass_buffers.
const GRASS_PALETTE_BY_SEASON := {
	GameTypes.Season.WINTER: {"base": Color(0.42, 0.40, 0.26, 0.80), "tip": Color(0.58, 0.52, 0.34, 0.80)},
	GameTypes.Season.SPRING: {"base": Color(0.28, 0.58, 0.18, 0.85), "tip": Color(0.55, 0.80, 0.30, 0.85)},
	GameTypes.Season.SUMMER: {"base": Color(0.28, 0.58, 0.18, 0.85), "tip": Color(0.55, 0.80, 0.30, 0.85)},
	GameTypes.Season.AUTUMN: {"base": Color(0.55, 0.42, 0.12, 0.85), "tip": Color(0.82, 0.62, 0.18, 0.85)},
}
# Colore chioma per stagione, solo per gli alberi NON conifer (is_evergreen=false: wood_only,
# wild_fruit, domesticable_fruit — non distinti fra loro a livello di rendering, un solo colore
# "chioma caduca" condiviso). SPRING/SUMMER riusano VEGETATION_COLORS[TREE] (verde normale,
# invariato), AUTUMN vira a marrone-rossiccio, WINTER scende ad alpha molto bassa su un colore
# spento grigio-bruno anziché verde ("rami spogli visti da lontano", non del tutto invisibile).
# Gli alberi conifer non usano questa palette: chioma a forma di abete, sempre piena/verde in
# ogni stagione — vedi _rebuild_tree_multimeshes (il sottotipo "conifer" arriva già deciso in
# tree_individual_subtype, vedi IndividualVegetationService).
const TREE_CANOPY_PALETTE_BY_SEASON := {
	GameTypes.Season.WINTER: Color(0.35, 0.30, 0.22, 0.20),
	GameTypes.Season.SPRING: Color(0.10, 0.45, 0.15, 0.85),
	GameTypes.Season.SUMMER: Color(0.10, 0.45, 0.15, 0.85),
	GameTypes.Season.AUTUMN: Color(0.55, 0.28, 0.10, 0.85),
}
const COLOR_TREE_CONIFER_CANOPY := Color(0.10, 0.45, 0.15, 0.85) # identico al verde normale odierno
# Marker statici per uno slot bloccato da taglio (vedi cut_positions) — forme DISTINTE per tipo,
# non un placeholder unico: TREE riusa la mesh del tronco vero (_tree_trunk_mesh, stesso colore
# COLOR_TREE_TRUNK) ridotta a TREE_STUMP_HEIGHT_RATIO della sua altezza normale e senza chioma —
# un ceppo, non un albero mozzato a metà; SHRUB usa una sagoma a stella (rovi intrecciati, vedi
# _build_bramble_mesh) invece del blob tondo dei lobi vivi, per leggersi come "cespuglio raso e
# aggrovigliato" a colpo d'occhio. Entrambe scalate da PlayerHarvestService.cut_individual al
# momento del taglio (vedi vegetation_cut_exceptions.size_multiplier) — stessa proporzione
# età×densità di un individuo vivo equivalente, non una taglia fissa.
const COLOR_BRAMBLE := Color(0.35, 0.22, 0.12, 0.95) # marrone scuro, stesso tono di un ceppo fresco
const TREE_STUMP_HEIGHT_RATIO: float = 1.0 / 3.0
const BRAMBLE_BASE_RADIUS: float = 1.5
const BRAMBLE_POINT_COUNT: int = 7
const BRAMBLE_INNER_RADIUS_RATIO: float = 0.35
# Marker "pianta morta" (mortalità naturale, vedi vegetation_death_exceptions). SHRUB resta il
# placeholder generico a cerchio (vedi DEAD_RADIUS_BY_TYPE, ora usato solo per lui — richiesta
# esplicita dell'utente di lasciarlo così per ora). TREE invece ha una sagoma dedicata — vedi
# _build_dead_tree_mesh/_build_dead_tree_transform sotto: colore tronco (non grigio, per non
# leggersi come un placeholder generico), nessuna chioma (a differenza del ceppo da taglio,
# _build_tree_stump_transform, che è anche troncato in altezza — qui l'albero morto resta IN
# PIEDI, solo spoglio), e una sagoma SPEZZATA (una piega a metà altezza, non una linea dritta —
# altrimenti a distanza si confondeva con un filo d'erba) più allungata del tronco vivo, oltre
# alla consueta leggera inclinazione deterministica per-istanza (DEAD_TREE_MAX_TILT_DEGREES).
const COLOR_DEAD := Color(0.55, 0.52, 0.46, 0.80) # grigio-bruno spento, "pianta secca" (solo SHRUB)
const DEAD_RADIUS_BY_TYPE := {
	GameTypes.WorldObjectType.SHRUB: 1.4,
}
const DEAD_TREE_TRUNK_WIDTH_RATIO: float = 0.7 # frazione della larghezza del tronco vivo (1.6)
const DEAD_TREE_MAX_TILT_DEGREES: float = 12.0
# Punti (in spazio unitario locale, stessa convenzione 0..1 del quad del tronco vivo) della
# spezzata: base a terra -> piega -> cima, deliberatamente NON allineati in verticale (silhouette
# a "<": la piega sporge da un lato, la cima torna verso il centro) — vedi _build_dead_tree_mesh.
const DEAD_TREE_BEND_POINTS: Array = [Vector2(0.5, 1.0), Vector2(0.12, 0.42), Vector2(0.62, 0.0)]
const DEAD_TREE_LINE_HALF_THICKNESS: float = 0.11
# Finestra di fruttificazione per i marcatori bacche/frutti (tarda estate/autunno): fuori da
# queste stagioni i marcatori non vengono disegnati, ma il sottotipo congelato dell'individuo
# (vedi tree_individual_subtype/shrub_individual_subtype) resta invariato — è solo un gate a
# draw-time.
const FRUITING_SEASONS := [GameTypes.Season.SUMMER, GameTypes.Season.AUTUMN]
const BOUNDARY_DASH_COLOR := Color(0, 0, 0, 0.6)
const BOUNDARY_DASH_WIDTH: float = 2.0
const BOUNDARY_DASH_LENGTH: float = 6.0

# Edifici piazzati (vedi World.buildings/GameScene._place_building_at) — stessa convenzione di
# verticalità (pareti+tetto) già usata da BuildingGhost per l'anteprima, ma OPACA e senza la
# variante rossa "non edificabile" (un edificio già piazzato è sempre valido). Pochi edifici per
# macrocella attesi: disegnati immediate-mode come il fiume/i confini, nessun MultiMesh.
const BUILDING_WALL_COLOR := Color(0.55, 0.42, 0.28, 1.0)
const BUILDING_WALL_OUTLINE_COLOR := Color(0.3, 0.22, 0.12, 1.0)
const BUILDING_ROOF_COLOR := Color(0.45, 0.28, 0.12, 1.0)
const BUILDING_ROOF_OUTLINE_COLOR := Color(0.25, 0.15, 0.06, 1.0)
const BUILDING_WALL_WIDTH: float = 6.0
const BUILDING_WALL_HEIGHT: float = 4.0
const BUILDING_ROOF_WIDTH: float = 8.0
const BUILDING_ROOF_HEIGHT: float = 4.5

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
# Posizioni microcella (Vector2i) degli edifici già piazzati in QUESTA macrocella — vedi
# GameScene._refresh_building_visuals, che filtra World.buildings per macro_x/macro_y prima di
# passarli qui: questo renderer non conosce World, solo "dove disegnare".
var building_positions: Array = [] # Array[Vector2i]
var vegetation_positions: Dictionary = {} # WorldObjectType -> Array[Vector3i] per TREE/SHRUB (lotto x,y + indice individuo), Array[Vector2i] per GRASS (nessuna identità individuale)
var fish_positions: Array = [] # Array[Vector2i] — STEP 1: valorizzato solo per macrocelle SEA/LAKE
# Posizioni (Vector3i, per TREE/SHRUB) con un blocco di taglio/morte attualmente attivo — vedi
# IndividualVegetationService.get_cut_positions/get_dead_positions. Disegnate con un marker
# statico distinto (tronco mozzato / pianta secca, vedi _rebuild_cut_dead_multimeshes) al posto
# del blob vivo normale, che per quello slot semplicemente non esiste (vegetation_positions non
# lo contiene, vedi IndividualVegetationService._is_blocked).
var cut_positions: Dictionary = {} # WorldObjectType -> Array[Vector3i]
var dead_positions: Dictionary = {} # WorldObjectType -> Array[Vector3i]

# STONE_VARIANT_COUNT sagome-base pre-generate una sola volta (stessa formula di jitter
# per-vertice di sempre, seminata per variante invece che per posizione) e riusate per tutte le
# posizioni stone via MultiMesh — invece di un draw_polygon irregolare per ogni singola pietra,
# ne bastano STONE_VARIANT_COUNT in totale indipendentemente da quante pietre ci sono nella
# cella. Ogni pietra sceglie deterministicamente la sua variante da hash(pos) e riceve comunque
# posizione/rotazione/scala per-istanza uniche, quindi la ripetizione tra pietre non è mai
# "identica": solo la sagoma di base è condivisa fra gruppi di ~1/12 delle pietre.
var _stone_variant_meshes: Array = [] # ArrayMesh, indicizzato per variante — costruito una volta sola
var _stone_multimeshes: Array = [] # MultiMesh, indicizzato per variante — un draw_multimesh ciascuno
# Sottotipo congelato per individuo — Vector3i -> String ("wood_only"/"fruit_bearing" per SHRUB,
# "wood_only"/"wild_fruit"/"domesticable_fruit"/"conifer" per TREE), stesso oggetto di
# MacroCellState.tree_individual_subtype/shrub_individual_subtype (Dictionary per riferimento,
# vedi set_tree_subtypes/set_shrub_subtypes) — deciso una sola volta da IndividualVegetationService
# alla nascita dell'individuo, mai più ricalcolato qui: il renderer si limita a leggerlo. Sostituisce
# i vecchi shrub_fruit_ratio/tree_wild_fruit_ratio/tree_domesticable_fruit_ratio/tree_conifer_ratio
# (rimossi insieme ai test hash a schermo _is_tree_conifer ecc., spostati in
# IndividualVegetationService dove ora avviene la decisione).
var shrub_individual_subtype: Dictionary = {}
var tree_individual_subtype: Dictionary = {}
# Parametri fasce età per sottotipo SHRUB, chiave = subtype_name ("wood_only"/"fruit_bearing"),
# valore = {"youth_duration_years": int, "adult_duration_years": int, "size_multiplier_by_age":
# Array[float], "ratios": Array[float]} — tutti già risolti dal chiamante (SubtypeRules + age_composition):
# il renderer non legge mai ResourceCalculator/MacroCellState direttamente. Un sottotipo assente da
# questo dizionario (es. track_age_bands=false) non riceve mai variazione di dimensione (vedi
# _resolve_age_band_and_size).
var shrub_age_params: Dictionary = {}
# Anno di gioco corrente (game_data.year), servito insieme a shrub_age_params perché
# AgeBandVisualService ne ha bisogno per calcolare gli anni vissuti di ogni posizione.
var shrub_current_year: int = 0
# Stessa coppia di shrub_age_params/shrub_current_year sopra, ma per i 4 sottotipi TREE
# ("wood_only"/"wild_fruit"/"domesticable_fruit"/"conifer") — vedi set_tree_age_params.
var tree_age_params: Dictionary = {}
var tree_current_year: int = 0
# Stagione corrente (vedi GRASS_PALETTE_BY_SEASON/FRUITING_SEASONS sopra) — arriva già risolta
# dal chiamante (MacroCellScene, via SeasonCalculator.get_season_for_day), stessa separazione
# di responsabilità delle altre proprietà "calcolate altrove" del renderer.
var current_season: GameTypes.Season = GameTypes.Season.WINTER

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


# Da chiamare quando la macrocella caricata NON ha un fiume (GameScene._load_macro_cell, riuso
# della stessa istanza di renderer tra macrocelle diverse) — set_river sopra non ha mai modo di
# tornare a false una volta impostato a true, quindi senza questa chiamata un fiume disegnato in
# una macrocella resterebbe visibile anche dopo essere passati a una macrocella senza fiume.
func clear_river() -> void:
	is_river = false
	river_shape = GameTypes.RiverShape.NONE
	river_thickness_ratio = 0.0
	queue_redraw()


func set_stone_positions(positions: Array) -> void:
	stone_positions = positions
	_rebuild_stone_multimeshes()
	queue_redraw()


func set_building_positions(positions: Array) -> void:
	building_positions = positions
	queue_redraw()


func set_vegetation_positions(positions: Dictionary) -> void:
	vegetation_positions = positions
	_rebuild_tree_multimeshes()
	_rebuild_shrub_multimeshes()
	_rebuild_grass_buffers()
	queue_redraw()


# ============================================================================================
# Click-detection su un singolo individuo (TREE/SHRUB) — vedi VegetationSelectorController, che
# interroga queste due query per ogni candidato vicino al click. Entrambe riusano ESATTAMENTE le
# stesse funzioni del rebuild (_compute_tree_visual/_compute_shrub_visual), mai una copia della
# formula — vedi il commento lì sul perché `is_first_sight` resta al default `false` in una query
# isolata.
# ============================================================================================

# Posizione a schermo (spazio locale di questo renderer, stessi pixel di CELL_SIZE) del "centro
# visivo" di un individuo: canopy_center per un TREE vivo (il grosso della massa visiva sta nella
# chioma, non nel tronco) ma "ground" per un TREE bloccato (tagliato/morto) — non ha più chioma,
# solo il ceppo a livello del suolo, vedi _build_tree_stump_transform. Per SHRUB resta sempre
# "center" del cluster (vivo o rovi, stesso ancoraggio). GameTypes.WorldObjectType diversi da
# TREE/SHRUB (GRASS non ha identità individuale, vedi vegetation_positions) ritornano Vector2.ZERO.
func get_individual_screen_position(object_type: GameTypes.WorldObjectType, individual_key: Vector3i) -> Vector2:
	match object_type:
		GameTypes.WorldObjectType.TREE:
			var visual := _compute_tree_visual(individual_key, _lot_extent_counts(GameTypes.WorldObjectType.TREE))
			return visual["canopy_center"] if has_individual(object_type, individual_key) else visual["ground"]
		GameTypes.WorldObjectType.SHRUB:
			return _compute_shrub_visual(individual_key, _lot_extent_counts(GameTypes.WorldObjectType.SHRUB))["center"]
		_:
			return Vector2.ZERO


# Dati per il pannello informativo (sottotipo/fascia età/anni vissuti) di un individuo VIVO già
# selezionato — {} se object_type non è TREE/SHRUB o l'individuo non esiste più (il chiamante
# dovrebbe aver già verificato has_individual prima di arrivare qui). Per uno slot bloccato
# (tagliato/morto) vedi get_blocked_marker_info sotto, non questa.
func get_individual_info(object_type: GameTypes.WorldObjectType, individual_key: Vector3i) -> Dictionary:
	match object_type:
		GameTypes.WorldObjectType.TREE:
			var visual := _compute_tree_visual(individual_key, _lot_extent_counts(GameTypes.WorldObjectType.TREE))
			return {"subtype_name": visual["subtype_name"], "age_band": visual["age_band"], "years_lived": visual["years_lived"], "size_multiplier": visual["size_multiplier"]}
		GameTypes.WorldObjectType.SHRUB:
			var visual := _compute_shrub_visual(individual_key, _lot_extent_counts(GameTypes.WorldObjectType.SHRUB))
			return {"subtype_name": visual["subtype_name"], "age_band": visual["age_band"], "years_lived": visual["years_lived"], "size_multiplier": visual["size_multiplier"]}
		_:
			return {}


# Dati per il pannello informativo di uno slot BLOCCATO (tagliato o morto) selezionato — {} se non
# è bloccato (individuo vivo o slot inesistente). "years_ago" = anni trascorsi dal blocco, letto
# dall'anno corrente del tipo giusto (tree_current_year/shrub_current_year, già tenuti aggiornati
# da set_tree_age_params/set_shrub_age_params).
func get_blocked_marker_info(object_type: GameTypes.WorldObjectType, individual_key: Vector3i) -> Dictionary:
	var current_year: int = tree_current_year if object_type == GameTypes.WorldObjectType.TREE else shrub_current_year
	for entry in cut_positions.get(object_type, []):
		if entry["key"] == individual_key:
			return {"state": "cut", "years_ago": current_year - int(entry["event_year"]), "size_multiplier": float(entry["size_multiplier"])}
	for entry in dead_positions.get(object_type, []):
		if entry["key"] == individual_key:
			return {"state": "dead", "years_ago": current_year - int(entry["event_year"]), "size_multiplier": float(entry["size_multiplier"])}
	return {}


func has_blocked_marker(object_type: GameTypes.WorldObjectType, individual_key: Vector3i) -> bool:
	return not get_blocked_marker_info(object_type, individual_key).is_empty()


# Vero se `individual_key` è ancora tra le posizioni correnti di `object_type` — usato dal
# chiamante (GameScene) per invalidare una selezione dopo un rebuild (pianta morta/migrata, in
# futuro tagliata da PlayerHarvestService).
func has_individual(object_type: GameTypes.WorldObjectType, individual_key: Vector3i) -> bool:
	return vegetation_positions.get(object_type, []).has(individual_key)


# Limiti SUPERIORI dei range usati in _rebuild_shrub_multimeshes per posizione/raggio di un blob
# (distanza 0.8-1.8, raggio 1.4-2.2) — usati da _draw_selected_individual_highlight per un cerchio
# che racchiude per costruzione ogni blob possibile del cluster (bacche incluse, il cui ingombro
# massimo è sempre minore): nessun singolo raggio esatto esiste per SHRUB (posizione/raggio
# per-blob sono randomizzati e ricalcolati solo dentro il rebuild, mai memorizzati per posizione),
# quindi questa resta un'approssimazione per eccesso dichiarata, non un contorno che segue i
# singoli lobi (tracciarne l'unione esatta non vale la spesa per un indicatore di selezione).
const SHRUB_BLOB_MAX_DISTANCE_RATIO: float = 1.8
const SHRUB_BLOB_MAX_RADIUS_RATIO: float = 2.2


# Individuo attualmente selezionato per l'ispezione — analogo a Individual.is_selected per il
# player, ma vive qui (non su un oggetto persistente: un individuo vegetale non ha una Resource
# propria, solo l'identità posizionale Vector3i) e solo sul renderer della cella che lo possiede
# davvero (ogni LiveMacroCell ha la propria istanza — vedi GameScene._select_vegetation, che pulisce
# esplicitamente la selezione su tutte le ALTRE celle vive). object_type=-1 è il sentinel "nessuna
# selezione" (GameTypes.WorldObjectType non ha un valore NONE riusabile qui).
var _selected_individual_type: int = -1
var _selected_individual_key: Vector3i


func set_selected_individual(object_type: GameTypes.WorldObjectType, individual_key: Vector3i) -> void:
	_selected_individual_type = object_type
	_selected_individual_key = individual_key
	queue_redraw()


func clear_selected_individual() -> void:
	if _selected_individual_type == -1:
		return
	_selected_individual_type = -1
	queue_redraw()


# Contorno rosso sottile che segue la sagoma REALE dell'individuo (non un cerchio bianco a
# distanza fissa dal centro come per il player — scelta esplicita dell'utente): un TREE non-
# conifer e uno SHRUB hanno comunque una chioma/cluster rotondi, quindi un cerchio È la sagoma
# corretta lì; un TREE conifer invece ha una chioma a triangolo (vedi CONIFER_SHAPE_POINTS/
# _build_conifer_mesh) — disegnargli sopra un cerchio lo faceva sembrare sempre rotondo e
# (nell'intervallo stretto 2.8-3.8×size_multiplier) quasi sempre della stessa dimensione
# percepita, invece di aderire alla punta e alla base larga del suo vero contorno. Nessun disegno
# se l'individuo selezionato è sparito da questo rebuild (has_individual): evita un contorno
# "fantasma" nel frame tra un rebuild che rimuove l'individuo e la chiamata di GameScene a
# clear_selected_individual (vedi _invalidate_selected_vegetation_if_missing), che avviene
# comunque nello stesso frame ma dopo il primo queue_redraw.
const SELECTION_HIGHLIGHT_COLOR := Color(0.95, 0.1, 0.1, 0.95)
const SELECTION_HIGHLIGHT_WIDTH: float = 0.5
# Leggero margine verso l'esterno (10%) così il contorno risulta aderente-ma-fuori dalla sagoma
# disegnata sotto, invece di sovrapporsi esattamente al suo bordo (che con un tratto da 0.8px
# rischierebbe di confondersi visivamente con l'edge della mesh stessa).
const SELECTION_OUTLINE_PADDING_RATIO: float = 1.1

func _draw_selected_individual_highlight() -> void:
	if _selected_individual_type == -1:
		return

	if has_individual(_selected_individual_type, _selected_individual_key):
		_draw_alive_selection_outline()
		return

	# Slot bloccato (tagliato/morto): niente sagoma da inseguire (conifer/chioma non esistono più
	# per un ceppo), un semplice cerchio proporzionato alla stessa size_multiplier persistita usata
	# per disegnare il marker (vedi _build_tree_stump_transform/_build_shrub_stump_transform) è
	# sufficiente a confermare "è questo che hai selezionato".
	var blocked_info := get_blocked_marker_info(_selected_individual_type, _selected_individual_key)
	if blocked_info.is_empty():
		return
	var center := get_individual_screen_position(_selected_individual_type, _selected_individual_key)
	var base_radius: float = 1.6 if _selected_individual_type == GameTypes.WorldObjectType.TREE else BRAMBLE_BASE_RADIUS
	var radius: float = base_radius * float(blocked_info["size_multiplier"]) * SELECTION_OUTLINE_PADDING_RATIO
	draw_arc(center, radius, 0, TAU, 24, SELECTION_HIGHLIGHT_COLOR, SELECTION_HIGHLIGHT_WIDTH)


# Contorno che segue la sagoma di un individuo VIVO — stessa logica di sempre (chioma tonda per
# TREE non-conifer/SHRUB, triangolo per conifer), estratta a parte da _draw_selected_individual_
# highlight solo per separare questo caso da quello di uno slot bloccato (vedi sopra).
func _draw_alive_selection_outline() -> void:
	if _selected_individual_type == GameTypes.WorldObjectType.TREE:
		var visual := _compute_tree_visual(_selected_individual_key, _lot_extent_counts(GameTypes.WorldObjectType.TREE))
		if visual["is_conifer"]:
			_draw_conifer_selection_outline(visual["canopy_center"], visual["canopy_radius"])
		else:
			var radius: float = visual["canopy_radius"] * SELECTION_OUTLINE_PADDING_RATIO
			draw_arc(visual["canopy_center"], radius, 0, TAU, 24, SELECTION_HIGHLIGHT_COLOR, SELECTION_HIGHLIGHT_WIDTH)
	elif _selected_individual_type == GameTypes.WorldObjectType.SHRUB:
		var visual := _compute_shrub_visual(_selected_individual_key, _lot_extent_counts(GameTypes.WorldObjectType.SHRUB))
		var radius: float = (
			SHRUB_BLOB_MAX_DISTANCE_RATIO * float(visual["density_scale"])
			+ SHRUB_BLOB_MAX_RADIUS_RATIO * float(visual["size_multiplier"])
		) * SELECTION_OUTLINE_PADDING_RATIO
		draw_arc(visual["center"], radius, 0, TAU, 24, SELECTION_HIGHLIGHT_COLOR, SELECTION_HIGHLIGHT_WIDTH)


# Stessi CONIFER_SHAPE_POINTS della mesh reale (mai una copia separata dei tre vertici), scalati
# leggermente oltre canopy_radius (SELECTION_OUTLINE_PADDING_RATIO) e ripetendo il primo punto in
# coda: draw_polyline non chiude da sé il poligono.
func _draw_conifer_selection_outline(canopy_center: Vector2, canopy_radius: float) -> void:
	# `radius`, non `scale`: Node2D ha già una proprietà `scale` (Vector2) — un local scalare con
	# lo stesso nome la ombreggerebbe senza motivo.
	var radius: float = canopy_radius * SELECTION_OUTLINE_PADDING_RATIO
	var points := PackedVector2Array()
	for p in CONIFER_SHAPE_POINTS:
		points.append(canopy_center + p * radius)
	points.append(points[0])
	draw_polyline(points, SELECTION_HIGHLIGHT_COLOR, SELECTION_HIGHLIGHT_WIDTH)


func set_fish_positions(positions: Array) -> void:
	fish_positions = positions
	_rebuild_fish_multimeshes()
	queue_redraw()


func set_shrub_subtypes(subtype_store: Dictionary) -> void:
	shrub_individual_subtype = subtype_store
	_rebuild_shrub_multimeshes()
	queue_redraw()


func set_shrub_age_params(current_year: int, age_params: Dictionary, birth_year_store: Dictionary) -> void:
	shrub_current_year = current_year
	shrub_age_params = age_params
	shrub_birth_year_store = birth_year_store
	_rebuild_shrub_multimeshes()
	queue_redraw()


func set_tree_subtypes(subtype_store: Dictionary) -> void:
	tree_individual_subtype = subtype_store
	_rebuild_tree_multimeshes()
	queue_redraw()


func set_tree_age_params(current_year: int, age_params: Dictionary, birth_year_store: Dictionary) -> void:
	tree_current_year = current_year
	tree_age_params = age_params
	tree_birth_year_store = birth_year_store
	_rebuild_tree_multimeshes()
	queue_redraw()


# Vedi cut_positions/dead_positions in testa al file: rigenera solo i marker statici (tronco
# mozzato / pianta secca), mai i blob vivi (quelli dipendono da vegetation_positions, invariato).
func set_cut_positions(positions: Dictionary) -> void:
	cut_positions = positions
	_rebuild_cut_dead_multimeshes()
	queue_redraw()


func set_dead_positions(positions: Dictionary) -> void:
	dead_positions = positions
	_rebuild_cut_dead_multimeshes()
	queue_redraw()


# Il colore dell'erba e quello della chioma degli alberi NON conifer dipendono dalla stagione,
# quindi entrambi vanno ricalcolati qui; la visibilità dei frutti (FRUITING_SEASONS) è invece un
# gate a draw-time, non richiede nessun rebuild dei loro buffer. La chioma conifer (a forma di
# abete) resta sempre piena/verde in ogni stagione, ma il rebuild va comunque rifatto per intero
# perché lo stesso _rebuild_tree_multimeshes ricostruisce entrambi i gruppi insieme.
func set_season(season: GameTypes.Season) -> void:
	current_season = season
	_rebuild_grass_buffers()
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
	_draw_selected_individual_highlight()
	_draw_fish_positions()
	_draw_buildings()
	_draw_neighbor_previews(grid_size)
	_draw_boundary(grid_size)

	#print("[DEBUG RENDER] primitive stone+grass+shrub+tree+bacche in questo _draw(): ", _debug_draw_primitive_count)


# Stessa geometria di BuildingGhost._draw() (pareti+tetto, ancorati al "terreno" del centro
# cella), ma opaca: un edificio piazzato non è più un'anteprima. Ancoraggio al centro della
# microcella (base+half), nessun jitter/dispersione come per la vegetazione — un edificio occupa
# una posizione precisa, non un lotto condiviso da più individui.
func _draw_buildings() -> void:
	var half: float = CELL_SIZE / 2.0
	for pos in building_positions:
		var ground := Vector2(pos.x * CELL_SIZE + half, pos.y * CELL_SIZE + half)
		var wall_rect := Rect2(
			ground.x - BUILDING_WALL_WIDTH / 2.0,
			ground.y - BUILDING_WALL_HEIGHT,
			BUILDING_WALL_WIDTH,
			BUILDING_WALL_HEIGHT
		)
		draw_rect(wall_rect, BUILDING_WALL_COLOR)
		draw_rect(wall_rect, BUILDING_WALL_OUTLINE_COLOR, false, 1.0)

		var roof_base_y: float = ground.y - BUILDING_WALL_HEIGHT
		var roof_points := PackedVector2Array([
			Vector2(ground.x - BUILDING_ROOF_WIDTH / 2.0, roof_base_y),
			Vector2(ground.x + BUILDING_ROOF_WIDTH / 2.0, roof_base_y),
			Vector2(ground.x, roof_base_y - BUILDING_ROOF_HEIGHT),
		])
		draw_colored_polygon(roof_points, BUILDING_ROOF_COLOR)
		draw_polyline(PackedVector2Array([roof_points[0], roof_points[2], roof_points[1]]), BUILDING_ROOF_OUTLINE_COLOR, 1.2)


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
# grass (draw_multiline_colors) -> shrub blobs -> bacche -> tree trunk -> tree canopy (tonda,
# non-conifer) -> tree canopy conifer (abete) -> dot frutto wild -> dot frutto domesticable
# (sopra la chioma, altrimenti invisibili; mai per le posizioni conifer, escluse a monte). Ogni
# gruppo è oggi al più UNA chiamata di disegno, indipendentemente da quante istanze contiene —
# i buffer (transform/colore per MultiMesh, punti/colori per grass) sono già pronti, ricalcolati
# nei setter (_rebuild_*) quando le posizioni cambiano, non qui.
func _draw_vegetation_positions() -> void:
	if _tree_stump_multimesh != null and _tree_stump_multimesh.instance_count > 0:
		draw_multimesh(_tree_stump_multimesh, null)
		_debug_draw_primitive_count += 1

	if _shrub_stump_multimesh != null and _shrub_stump_multimesh.instance_count > 0:
		draw_multimesh(_shrub_stump_multimesh, null)
		_debug_draw_primitive_count += 1

	if _dead_multimesh != null and _dead_multimesh.instance_count > 0:
		draw_multimesh(_dead_multimesh, null)
		_debug_draw_primitive_count += 1

	if _dead_tree_multimesh != null and _dead_tree_multimesh.instance_count > 0:
		draw_multimesh(_dead_tree_multimesh, null)
		_debug_draw_primitive_count += 1

	if not _grass_points.is_empty():
		# Spessore ridotto da 1.1 a 0.5: alla lunghezza attuale dei fili (vedi height in
		# _rebuild_grass_buffers, accorciata di recente) 1.1px li faceva leggere come tronconi
		# tozzi invece che fili sottili.
		draw_multiline_colors(_grass_points, _grass_colors, 0.5)
		_debug_draw_primitive_count += 1

	if _shrub_multimesh != null and _shrub_multimesh.instance_count > 0:
		draw_multimesh(_shrub_multimesh, null)
		_debug_draw_primitive_count += 1

	var fruit_in_season: bool = current_season in FRUITING_SEASONS

	if fruit_in_season and _berry_multimesh != null and _berry_multimesh.instance_count > 0:
		draw_multimesh(_berry_multimesh, null)
		_debug_draw_primitive_count += 1

	if _tree_trunk_multimesh != null and _tree_trunk_multimesh.instance_count > 0:
		draw_multimesh(_tree_trunk_multimesh, null)
		_debug_draw_primitive_count += 1

	if _tree_canopy_multimesh != null and _tree_canopy_multimesh.instance_count > 0:
		draw_multimesh(_tree_canopy_multimesh, null)
		_debug_draw_primitive_count += 1

	if _tree_conifer_canopy_multimesh != null and _tree_conifer_canopy_multimesh.instance_count > 0:
		draw_multimesh(_tree_conifer_canopy_multimesh, null)
		_debug_draw_primitive_count += 1

	if fruit_in_season and _tree_fruit_wild_multimesh != null and _tree_fruit_wild_multimesh.instance_count > 0:
		draw_multimesh(_tree_fruit_wild_multimesh, null)
		_debug_draw_primitive_count += 1

	if fruit_in_season and _tree_fruit_domesticable_multimesh != null and _tree_fruit_domesticable_multimesh.instance_count > 0:
		draw_multimesh(_tree_fruit_domesticable_multimesh, null)
		_debug_draw_primitive_count += 1


const VEGETATION_CIRCLE_SEGMENTS: int = 12

var _tree_trunk_mesh: ArrayMesh
var _tree_canopy_mesh: ArrayMesh # bianca: il colore stagionale arriva per-istanza (use_colors)
var _tree_conifer_canopy_mesh: ArrayMesh # forma ad abete, colore fisso (mai stagionale)
var _tree_fruit_wild_mesh: ArrayMesh
var _tree_fruit_domesticable_mesh: ArrayMesh
var _shrub_blob_mesh: ArrayMesh # bianca: il colore per-lobo arriva per-istanza (use_colors)
var _berry_mesh: ArrayMesh
var _bramble_mesh: ArrayMesh # sagoma a stella per il taglio SHRUB, vedi _build_bramble_mesh
var _dead_mesh: ArrayMesh # cerchio generico, ora usato solo per SHRUB morto
var _dead_tree_mesh: ArrayMesh # riusa la forma quad del tronco, colore COLOR_DEAD invece di COLOR_TREE_TRUNK
var _vegetation_meshes_ready: bool = false

var _tree_trunk_multimesh: MultiMesh
var _tree_canopy_multimesh: MultiMesh
var _tree_conifer_canopy_multimesh: MultiMesh
var _tree_fruit_wild_multimesh: MultiMesh
var _tree_fruit_domesticable_multimesh: MultiMesh
var _shrub_multimesh: MultiMesh
var _berry_multimesh: MultiMesh
var _tree_stump_multimesh: MultiMesh # riusa _tree_trunk_mesh, istanza separata dal tronco vivo
var _shrub_stump_multimesh: MultiMesh # riusa _bramble_mesh
var _dead_multimesh: MultiMesh # SHRUB morto (cerchio generico)
var _dead_tree_multimesh: MultiMesh # TREE morto (tronco spoglio inclinato)


func _ensure_vegetation_meshes() -> void:
	if _vegetation_meshes_ready:
		return
	_vegetation_meshes_ready = true

	_tree_trunk_mesh = _build_quad_mesh(COLOR_TREE_TRUNK)
	_tree_canopy_mesh = _build_circle_mesh(VEGETATION_CIRCLE_SEGMENTS, Color.WHITE)
	_tree_conifer_canopy_mesh = _build_conifer_mesh(COLOR_TREE_CONIFER_CANOPY)
	_tree_fruit_wild_mesh = _build_circle_mesh(VEGETATION_CIRCLE_SEGMENTS, COLOR_TREE_FRUIT_WILD)
	_tree_fruit_domesticable_mesh = _build_circle_mesh(VEGETATION_CIRCLE_SEGMENTS, COLOR_TREE_FRUIT_DOMESTICABLE)
	_shrub_blob_mesh = _build_circle_mesh(VEGETATION_CIRCLE_SEGMENTS, Color.WHITE)
	_berry_mesh = _build_circle_mesh(VEGETATION_CIRCLE_SEGMENTS, COLOR_SHRUB_BERRY)
	_bramble_mesh = _build_bramble_mesh(COLOR_BRAMBLE)
	_dead_mesh = _build_circle_mesh(VEGETATION_CIRCLE_SEGMENTS, COLOR_DEAD)
	_dead_tree_mesh = _build_dead_tree_mesh(COLOR_TREE_TRUNK)


func _ensure_vegetation_multimeshes() -> void:
	if _tree_trunk_multimesh != null:
		return

	_tree_trunk_multimesh = _make_multimesh(_tree_trunk_mesh, false)
	_tree_canopy_multimesh = _make_multimesh(_tree_canopy_mesh, true)
	_tree_stump_multimesh = _make_multimesh(_tree_trunk_mesh, false)
	_shrub_stump_multimesh = _make_multimesh(_bramble_mesh, false)
	_dead_multimesh = _make_multimesh(_dead_mesh, false)
	_dead_tree_multimesh = _make_multimesh(_dead_tree_mesh, false)
	_tree_conifer_canopy_multimesh = _make_multimesh(_tree_conifer_canopy_mesh, false)
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


# Transform completo di un ceppo TREE — riusa ESATTAMENTE la formula del tronco vivo
# (_compute_tree_visual, campo "ground": dipende solo da lotto/indice/quanti individui condividono
# il lotto, MAI da sottotipo/età, quindi resta valida anche per un individuo di cui sottotipo/età
# sono già stati dimenticati) per l'ancoraggio, ma altezza/larghezza scalate dal size_multiplier
# PERSISTITO al momento del taglio (vedi PlayerHarvestService.cut_individual) invece che da uno
# risolto ora (che sarebbe sempre il default neutro 1.0, avendo perso l'età) — TREE_STUMP_HEIGHT_
# RATIO tronca l'altezza a un ceppo invece di un tronco intero senza chioma. size_variation
# ricalcolato dalla sola chiave (hash puro di lotto+indice, indipendente da tutto il resto):
# nessun bisogno di persisterlo separatamente, è già deterministico.
func _build_tree_stump_transform(key: Vector3i, size_multiplier: float, lot_counts: Dictionary) -> Transform2D:
	var ground: Vector2 = _compute_tree_visual(key, lot_counts)["ground"]
	var jitter_pos := Vector2i(key.x, key.y) + Vector2i(key.z * 619, key.z * 823)
	var size_variation: float = float(hash(jitter_pos) % 1000) / 1000.0
	var trunk_width: float = 1.6 * size_multiplier
	var stub_height: float = lerp(3.0, 4.0, size_variation) * size_multiplier * TREE_STUMP_HEIGHT_RATIO
	var t := Transform2D(0, Vector2.ZERO).scaled(Vector2(trunk_width, stub_height))
	t.origin = Vector2(ground.x - trunk_width / 2.0, ground.y - stub_height)
	return t


# Transform completo di un cespuglio SHRUB tagliato (rovi) — stesso principio del tronco sopra,
# ma centrato su "center" (_compute_shrub_visual) e scalato in modo uniforme (nessuna forma
# direzionale come il tronco, la stella dei rovi è isotropa).
func _build_shrub_stump_transform(key: Vector3i, size_multiplier: float, lot_counts: Dictionary) -> Transform2D:
	var center: Vector2 = _compute_shrub_visual(key, lot_counts)["center"]
	var radius: float = BRAMBLE_BASE_RADIUS * size_multiplier
	var t := Transform2D(0, Vector2.ZERO).scaled(Vector2(radius, radius))
	t.origin = center
	return t


# Transform di un marker "pianta morta" generico (cerchio, vedi commento su COLOR_DEAD) — usato
# oggi solo per SHRUB (TREE ha una sagoma dedicata, vedi _build_dead_tree_transform sotto). Stessa
# logica di ancoraggio ("center", vedi _compute_shrub_visual) e stesso scaling per size_multiplier
# persistito degli altri marker statici.
func _build_dead_marker_transform(object_type: GameTypes.WorldObjectType, key: Vector3i, size_multiplier: float, lot_counts: Dictionary) -> Transform2D:
	var center: Vector2 = _compute_shrub_visual(key, lot_counts)["center"]
	var radius: float = DEAD_RADIUS_BY_TYPE.get(object_type, 1.5) * size_multiplier
	var t := Transform2D(0, Vector2.ZERO).scaled(Vector2(radius, radius))
	t.origin = center
	return t


# Transform di un albero morto in piedi (mortalità naturale, TREE) — richiesta estetica esplicita
# dell'utente: non un cerchio generico né una linea dritta (si confondeva con un filo d'erba), ma
# una sagoma SPEZZATA (vedi _build_dead_tree_mesh/DEAD_TREE_BEND_POINTS) color tronco, più
# allungata del tronco vivo e un po' storta. A differenza del ceppo da taglio
# (_build_tree_stump_transform, troncato in altezza a TREE_STUMP_HEIGHT_RATIO — lì l'albero è
# stato abbattuto), qui l'albero è morto ma ancora in piedi, spoglio (nessuna chioma).
# L'inclinazione ruota attorno alla base (il punto "ground", coordinate locali (0.5, 1.0) nella
# mesh — vedi DEAD_TREE_BEND_POINTS) componendo gli assi x/y ruotati direttamente invece di usare
# .rotated() sul Transform2D già traslato (che ruoterebbe attorno all'origine sbagliata).
# size_variation e tilt derivano da due hash indipendenti sulla stessa chiave (salt diversi) così
# le due variazioni non correlano tra loro.
func _build_dead_tree_transform(key: Vector3i, size_multiplier: float, lot_counts: Dictionary) -> Transform2D:
	var ground: Vector2 = _compute_tree_visual(key, lot_counts)["ground"]
	var jitter_pos := Vector2i(key.x, key.y) + Vector2i(key.z * 619, key.z * 823)
	var size_variation: float = float(hash(jitter_pos) % 1000) / 1000.0
	var tilt_hash: float = float(hash(jitter_pos * 7 + Vector2i(311, 947)) % 1000) / 1000.0

	var trunk_width: float = DEAD_TREE_TRUNK_WIDTH_RATIO * size_multiplier
	# Più allungato del tronco vivo (che usa lerp(3.0, 4.0)) — la spezzata letta da lontano deve
	# leggersi come un albero morto in piedi, non un filo d'erba alto quanto un tronco normale.
	var trunk_height: float = lerp(4.5, 6.5, size_variation) * size_multiplier
	var tilt_angle: float = deg_to_rad(lerp(-DEAD_TREE_MAX_TILT_DEGREES, DEAD_TREE_MAX_TILT_DEGREES, tilt_hash))

	var x_axis := Vector2(cos(tilt_angle), sin(tilt_angle)) * trunk_width
	var y_axis := Vector2(-sin(tilt_angle), cos(tilt_angle)) * trunk_height
	var t := Transform2D(x_axis, y_axis, Vector2.ZERO)
	# Il quad unitario ha il piede (bottom-center, coordinate locali (0.5, 1.0)) su questo pivot:
	# sottraendolo dall'origine si ottiene che la base del tronco ruoti attorno a `ground`, non il
	# suo angolo in alto a sinistra.
	t.origin = ground - (x_axis * 0.5 + y_axis)
	return t


# Ricalcola i marker statici di cut_positions/dead_positions — chiamata dai rispettivi setter,
# indipendente dal rebuild dei blob vivi (vegetation_positions non li contiene, vedi
# IndividualVegetationService._is_blocked), ma ne condivide la stessa geometria di ancoraggio
# (vedi le tre funzioni sopra). Ogni entry porta già "size_multiplier" (vedi
# IndividualVegetationService.get_cut_positions/get_dead_positions) — nessun bisogno di risolverlo
# qui, viene passato così com'è.
func _rebuild_cut_dead_multimeshes() -> void:
	_ensure_vegetation_meshes()
	_ensure_vegetation_multimeshes()

	var tree_stump_transforms: Array = []
	var shrub_stump_transforms: Array = []
	for object_type in cut_positions:
		var lot_counts := _lot_extent_counts(object_type)
		for entry in cut_positions[object_type]:
			var key: Vector3i = entry["key"]
			var size_multiplier: float = entry["size_multiplier"]
			if object_type == GameTypes.WorldObjectType.TREE:
				tree_stump_transforms.append(_build_tree_stump_transform(key, size_multiplier, lot_counts))
			else:
				shrub_stump_transforms.append(_build_shrub_stump_transform(key, size_multiplier, lot_counts))
	_apply_transforms(_tree_stump_multimesh, tree_stump_transforms)
	_apply_transforms(_shrub_stump_multimesh, shrub_stump_transforms)

	var dead_transforms: Array = []
	var dead_tree_transforms: Array = []
	for object_type in dead_positions:
		var lot_counts := _lot_extent_counts(object_type)
		for entry in dead_positions[object_type]:
			if object_type == GameTypes.WorldObjectType.TREE:
				dead_tree_transforms.append(_build_dead_tree_transform(entry["key"], entry["size_multiplier"], lot_counts))
			else:
				dead_transforms.append(_build_dead_marker_transform(object_type, entry["key"], entry["size_multiplier"], lot_counts))
	_apply_transforms(_dead_multimesh, dead_transforms)
	_apply_transforms(_dead_tree_multimesh, dead_tree_transforms)


# Quanti individui (vivi O bloccati da un'eccezione di taglio/morte) condividono ciascun lotto —
# a differenza di _count_individuals_per_lot su un solo Array, questa combina vegetation_positions
# (vivi, Array[Vector3i]) con le sole CHIAVI di cut_positions/dead_positions (bloccati, Array
# [Dictionary] — vedi IndividualVegetationService.get_cut_positions/get_dead_positions) PRIMA di
# contare, così local_count non scende mai solo perché un individuo è stato tagliato/è morto:
# esattamente la stessa "estensione nota" calcolata da
# IndividualVegetationService._count_known_extent_by_lot lato generazione — le due devono restare
# in accordo, altrimenti un lotto affollato apparirebbe diverso da quanto la generazione ha
# davvero deciso. SENZA questo, tagliare un individuo cambierebbe local_count per i suoi vicini di
# lotto ancora vivi, e sia il disk-offset di TREE sia l'offset_range di SHRUB dipendono da
# local_count — i vicini si sposterebbero pur non avendo perso la propria identità.
func _lot_extent_counts(object_type: GameTypes.WorldObjectType) -> Dictionary:
	var combined: Array = vegetation_positions.get(object_type, []).duplicate()
	for entry in cut_positions.get(object_type, []):
		combined.append(entry["key"])
	for entry in dead_positions.get(object_type, []):
		combined.append(entry["key"])
	return _count_individuals_per_lot(combined)


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


# Sagoma SPEZZATA per l'albero morto in piedi (vedi DEAD_TREE_BEND_POINTS/_build_dead_tree_
# transform) — non un quad pieno come il tronco vivo: una linea spessa che segue DEAD_TREE_BEND_
# POINTS (base -> piega -> cima), costruita segmento per segmento da _add_thick_line_segment.
# Stessa convenzione di spazio unitario (0..1) del quad del tronco vivo, cosicché la stessa
# formula di transform (basi x/y scalate per trunk_width/trunk_height, origine ancorata al punto
# base) resti valida senza modifiche.
static func _build_dead_tree_mesh(color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(color)
	for i in range(DEAD_TREE_BEND_POINTS.size() - 1):
		_add_thick_line_segment(st, DEAD_TREE_BEND_POINTS[i], DEAD_TREE_BEND_POINTS[i + 1], DEAD_TREE_LINE_HALF_THICKNESS)
	return st.commit()


# Aggiunge un segmento spesso (due triangoli, spessore costante perpendicolare al segmento) tra
# due punti — usato da _build_dead_tree_mesh per costruire la spezzata senza dover ricorrere a
# un'unica forma piena rettangolare come il tronco vivo.
static func _add_thick_line_segment(st: SurfaceTool, from: Vector2, to: Vector2, half_thickness: float) -> void:
	var direction: Vector2 = (to - from).normalized()
	var perp: Vector2 = Vector2(-direction.y, direction.x) * half_thickness
	var a := Vector3(from.x + perp.x, from.y + perp.y, 0)
	var b := Vector3(to.x + perp.x, to.y + perp.y, 0)
	var c := Vector3(to.x - perp.x, to.y - perp.y, 0)
	var d := Vector3(from.x - perp.x, from.y - perp.y, 0)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


# Cerchio unitario (raggio 1, centrato all'origine): scalato per il raggio reale per-istanza
# riproduce esattamente il vecchio draw_circle(center, radius, color).
static func _build_circle_mesh(segments: int, color: Color) -> ArrayMesh:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle: float = (float(i) / float(segments)) * TAU
		points.append(Vector2(cos(angle), sin(angle)))
	return _build_fan_mesh(points, color)


# Punti (spazio unitario, origine (0,0) = canopy_center prima dello scale per canopy_radius)
# della sagoma conifer — condivisi tra _build_conifer_mesh (il blob disegnato) e
# _draw_conifer_selection_outline (il contorno di selezione), così le due forme non possono mai
# disallinearsi. Array normale (non PackedVector2Array: il parser non accetta un
# PackedVector2Array come espressione costante) — convertito dove serve un PackedVector2Array
# vero (vedi _build_conifer_mesh).
const CONIFER_SHAPE_POINTS := [
	Vector2(0.0, -1.3),
	Vector2(-1.0, 0.9),
	Vector2(1.0, 0.9),
]

# Sagoma stilizzata ad abete/conifera (triangolo isoscele, apice in alto): più alta e stretta
# del cerchio unitario (apice a -1.3 invece di -1.0) per leggersi come "sempreverde a punta"
# anche alla scala minuscola di una singola microcella, distinguendosi a colpo d'occhio dal
# blob tondo usato per gli altri sottotipi. Origine (0,0) del ventaglio comunque interna al
# triangolo (centroide ~ (0, 0.17)), quindi la triangolazione di _build_fan_mesh resta piena.
static func _build_conifer_mesh(color: Color) -> ArrayMesh:
	return _build_fan_mesh(PackedVector2Array(CONIFER_SHAPE_POINTS), color)


# Sagoma a stella (raggio esterno/interno alternati, BRAMBLE_POINT_COUNT punte) invece del blob
# tondo dei lobi vivi — legge come un cespuglio raso, intricato di rametti spinosi, a colpo
# d'occhio distinguibile dal cerchio pieno usato ovunque altrove in questo file. Stessa
# triangolazione a ventaglio di _build_circle_mesh/_build_conifer_mesh, solo con raggio non
# costante lungo il perimetro.
static func _build_bramble_mesh(color: Color) -> ArrayMesh:
	var points := PackedVector2Array()
	var point_total: int = BRAMBLE_POINT_COUNT * 2
	for i in range(point_total):
		var angle: float = (float(i) / float(point_total)) * TAU
		var radius: float = 1.0 if i % 2 == 0 else BRAMBLE_INNER_RADIUS_RATIO
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return _build_fan_mesh(points, color)


# Anno di nascita virtuale per individuo TREE — Dictionary[Vector3i, int] di PROPRIETÀ del
# chiamante (MacroCellState.tree_virtual_birth_year, vedi set_tree_age_params), non del renderer:
# passato per riferimento (i Dictionary in GDScript lo sono sempre). Il congelamento vero e
# proprio avviene in IndividualVegetationService (alla nascita dell'individuo, mai più qui) —
# questo renderer lo legge soltanto, ma essendo lo STESSO oggetto di MacroCellState il
# congelamento sopravvive comunque a save/load e alla ricreazione dell'istanza renderer nello
# streaming multi-cella. Tenuto separato da shrub_birth_year_store: una stessa cella griglia può
# ospitare SHRUB in un anno e TREE in un altro (successione ecologica), le due mappe non vanno
# mai confuse.
var tree_birth_year_store: Dictionary = {}

# Calcolo COMPLETO di un individuo TREE — geometria a schermo, a partire da un sottotipo/età già
# NOTI (mai più decisi qui, vedi IndividualVegetationService: il sottotipo è congelato una sola
# volta alla nascita dell'individuo in tree_individual_subtype, l'età in tree_birth_year_store) —
# riusato sia da _rebuild_tree_multimeshes (che ne ricava i Transform2D per il MultiMesh) sia
# dalle query pubbliche get_individual_screen_position/get_individual_info (click-detection, vedi
# VegetationSelectorController): mai una seconda copia della formula.
func _compute_tree_visual(individual_key: Vector3i, lot_counts: Dictionary) -> Dictionary:
	var pos := Vector2i(individual_key.x, individual_key.y)
	var index: int = individual_key.z
	# Salt indipendente da qualunque altro hash del renderer: il jitter visivo di un individuo
	# entro il footprint 10x10px del lotto non deve dipendere dagli stessi bit hash del suo
	# sottotipo, altrimenti un dato offset visivo finirebbe sistematicamente correlato ad esso.
	var jitter_pos := pos + Vector2i(index * 619, index * 823)

	# Letto da tree_individual_subtype (congelato da IndividualVegetationService alla nascita
	# dell'individuo) invece di ritestato ogni volta contro un rapporto corrente — un individuo non
	# "cambia specie" se le proporzioni della cella si spostano nel frattempo. "wood_only" è solo un
	# fallback difensivo (non dovrebbe mai servire: un individuo in vegetation_positions ha sempre
	# già un sottotipo congelato).
	var subtype_name: String = tree_individual_subtype.get(individual_key, "wood_only")
	var is_conifer: bool = subtype_name == "conifer"
	var is_domesticable: bool = subtype_name == "domesticable_fruit"
	var is_fruit_bearing: bool = is_domesticable or subtype_name == "wild_fruit"

	var resolved := _resolve_age_band_and_size(individual_key, subtype_name, tree_age_params, tree_birth_year_store, tree_current_year)
	var age_band: GameTypes.AgeBand = resolved["age_band"]
	var age_size_multiplier: float = resolved["size_multiplier"]

	# Due scale indipendenti e moltiplicative, mai in conflitto: age_size_multiplier (sopra) segna
	# la fascia d'età, density_scale segna quanto questo lotto è affollato — vedi
	# _resolve_density_scale_and_offset_range per la formula. A local_count=1 (il caso comune, un
	# solo individuo per lotto) density_scale=1.0: comportamento visivo IDENTICO a prima
	# dell'introduzione degli individui multipli per lotto.
	var local_count: int = int(lot_counts.get(pos, 1))
	var density_scale: float = float(_resolve_density_scale_and_offset_range(local_count)["density_scale"])
	var size_multiplier: float = age_size_multiplier * density_scale

	var base := Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)
	var half: float = CELL_SIZE / 2.0
	var size_variation: float = float(hash(jitter_pos) % 1000) / 1000.0
	# Wobble organico piccolo, stessa ampiezza di BASE_OFFSET_RANGE (il range pre-esistente quando
	# ogni lotto ospitava un solo individuo) — dà varietà, ma la SEPARAZIONE vera tra più individui
	# è garantita dal termine deterministico sotto (_fibonacci_disk_offset), non da questo wobble
	# indipendente per individuo (vedi il commento lì sul perché per TREE non basta allargare un
	# range casuale).
	var offset_variation: float = float(hash(jitter_pos * 7 + Vector2i(3, 11)) % 1000) / 1000.0
	var vertical_variation: float = float(hash(jitter_pos * 13 + Vector2i(29, 5)) % 1000) / 1000.0
	var wobble := Vector2(
		lerp(-BASE_OFFSET_RANGE, BASE_OFFSET_RANGE, offset_variation),
		lerp(-BASE_OFFSET_RANGE, BASE_OFFSET_RANGE, vertical_variation)
	)
	var disk_offset := _fibonacci_disk_offset(index, local_count, MAX_OFFSET_RANGE)
	# `ground` = punto in cui QUESTO individuo "poggia", disperso su tutto il footprint 10x10px via
	# disk_offset/wobble esattamente come center per SHRUB (base + half + offset).
	var ground := Vector2(
		base.x + half + disk_offset.x + wobble.x,
		base.y + half + disk_offset.y + wobble.y
	)

	var trunk_width: float = 1.6 * size_multiplier
	var trunk_height: float = lerp(3.0, 4.0, size_variation) * size_multiplier
	var trunk_y: float = ground.y - trunk_height
	var canopy_radius: float = lerp(2.8, 3.8, size_variation) * size_multiplier
	var canopy_center := Vector2(ground.x, trunk_y - canopy_radius * 0.6)

	return {
		"is_conifer": is_conifer, "is_fruit_bearing": is_fruit_bearing, "is_domesticable": is_domesticable,
		"subtype_name": subtype_name, "age_band": age_band, "size_multiplier": size_multiplier,
		"years_lived": tree_current_year - int(tree_birth_year_store.get(individual_key, tree_current_year)),
		"jitter_pos": jitter_pos, "ground": ground,
		"trunk_width": trunk_width, "trunk_height": trunk_height, "trunk_y": trunk_y,
		"canopy_center": canopy_center, "canopy_radius": canopy_radius,
	}


# Albero stilizzato: tronco (rettangolo) + chioma (cerchio) sopra — vedi _compute_tree_visual per
# tutta la geometria/identità di un individuo, qui resta solo la costruzione dei Transform2D per
# il MultiMesh e lo smistamento nei buffer giusti (conifer vs chioma tonda, dot frutto
# wild/domesticable).
func _rebuild_tree_multimeshes() -> void:
	_ensure_vegetation_meshes()
	_ensure_vegetation_multimeshes()

	var positions: Array = vegetation_positions.get(GameTypes.WorldObjectType.TREE, []) # Array[Vector3i]: lotto x,y + indice individuo
	var trunk_transforms: Array = []
	var canopy_transforms: Array = []
	var canopy_colors: Array = []
	var conifer_canopy_transforms: Array = []
	var wild_fruit_transforms: Array = []
	var domesticable_fruit_transforms: Array = []

	var deciduous_canopy_color: Color = TREE_CANOPY_PALETTE_BY_SEASON.get(current_season, VEGETATION_COLORS[GameTypes.WorldObjectType.TREE])

	# Estensione nota (vivi+bloccati), non il solo conteggio dei vivi — vedi _lot_extent_counts:
	# altrimenti tagliare un individuo cambierebbe il local_count (quindi il disk-offset) dei suoi
	# vicini di lotto ancora vivi, spostandoli pur non avendo perso la propria identità.
	var lot_counts: Dictionary = _lot_extent_counts(GameTypes.WorldObjectType.TREE)

	for individual_key in positions:
		var visual: Dictionary = _compute_tree_visual(individual_key, lot_counts)
		var ground: Vector2 = visual["ground"]
		var trunk_width: float = visual["trunk_width"]
		var trunk_y: float = visual["trunk_y"]
		var canopy_center: Vector2 = visual["canopy_center"]
		var canopy_radius: float = visual["canopy_radius"]

		var trunk_transform := Transform2D(0, Vector2.ZERO).scaled(Vector2(trunk_width, visual["trunk_height"]))
		trunk_transform.origin = Vector2(ground.x - trunk_width / 2.0, trunk_y)
		trunk_transforms.append(trunk_transform)

		var canopy_transform := Transform2D(0, Vector2.ZERO).scaled(Vector2(canopy_radius, canopy_radius))
		canopy_transform.origin = canopy_center

		# Ramo esclusivo: un individuo è O conifer (chioma ad abete, sempre verde piena, MAI
		# frutti) O uno degli altri tre sottotipi (chioma tonda, colore per stagione, idonea al
		# test frutta) — a differenza del test frutta stesso, qui l'esclusione è intenzionale ed
		# esplicita, non solo un'approssimazione indipendente (vedi discussione: conifer non deve
		# mai comparire con ghiande/mele).
		if visual["is_conifer"]:
			conifer_canopy_transforms.append(canopy_transform)
		else:
			canopy_transforms.append(canopy_transform)
			canopy_colors.append(deciduous_canopy_color)

			# YOUNG non produce mai frutti (production_coefficient_young = 0.0, stesso
			# coefficiente usato dal calcolo calorico), stesso gate già applicato alle bacche
			# shrub — irrilevante per wood_only/conifer, che non entrano mai in questo ramo.
			if visual["is_fruit_bearing"] and visual["age_band"] != GameTypes.AgeBand.YOUNG:
				var dots := _build_tree_fruit_transforms(visual["jitter_pos"], canopy_center, canopy_radius)
				if visual["is_domesticable"]:
					domesticable_fruit_transforms.append_array(dots)
				else:
					wild_fruit_transforms.append_array(dots)

	_apply_transforms(_tree_trunk_multimesh, trunk_transforms)
	_apply_transforms(_tree_canopy_multimesh, canopy_transforms)
	for i in range(canopy_colors.size()):
		_tree_canopy_multimesh.set_instance_color(i, canopy_colors[i])
	_apply_transforms(_tree_conifer_canopy_multimesh, conifer_canopy_transforms)
	_apply_transforms(_tree_fruit_wild_multimesh, wild_fruit_transforms)
	_apply_transforms(_tree_fruit_domesticable_multimesh, domesticable_fruit_transforms)


const TREE_FRUIT_SALTS := [
	Vector2i(59, 5),
	Vector2i(23, 61),
	Vector2i(37, 89),
]

# Raggio dot proporzionale a canopy_radius (che arriva già scalato per età*densità — vedi
# _rebuild_tree_multimeshes) invece di una dimensione fissa: 0.18 è tarato sul canopy_radius
# medio pre-esistente (~3.3, tra 2.8 e 3.8) così un albero non rimpicciolito per affollamento dà
# lo stesso dot di prima (~0.6) — un albero rimpicciolito (lotto affollato o giovane) ha ora dot
# proporzionalmente più piccoli invece di restare fissi e sproporzionati rispetto alla chioma.
const FRUIT_DOT_RADIUS_RATIO: float = 0.18

# 1-2 piccoli dot (colore assegnato dal chiamante in base a wild/domesticable) lungo il bordo
# della chioma — stesso principio geometrico delle bacche shrub, angolo/distanza per-dot
# derivati da hash(pos).
func _build_tree_fruit_transforms(pos: Vector2i, canopy_center: Vector2, canopy_radius: float) -> Array:
	var transforms: Array = []
	var dot_count: int = 2 + (hash(pos * 17 + Vector2i(4, 90)) % 2) # 2 o 3 dot
	var dot_radius: float = canopy_radius * FRUIT_DOT_RADIUS_RATIO
	for i in range(dot_count):
		var salt: Vector2i = TREE_FRUIT_SALTS[i % TREE_FRUIT_SALTS.size()]
		var angle: float = (float(hash(pos * salt.x + Vector2i(salt.y, i + 200)) % 1000) / 1000.0) * TAU
		var distance: float = lerp(0.5, 1.0, float(hash(pos * salt.y + Vector2i(i + 200, salt.x)) % 1000) / 1000.0) * canopy_radius
		var dot_center := canopy_center + Vector2(cos(angle), sin(angle)) * distance

		var dot_transform := Transform2D(0, Vector2.ZERO).scaled(Vector2(dot_radius, dot_radius))
		dot_transform.origin = dot_center
		transforms.append(dot_transform)
	return transforms


# Shrub stilizzato: 3-4 piccoli cerchi sovrapposti e sfalsati attorno al centro della cella
# (colore per-istanza via MultiMesh.use_colors, gradiente verde/marrone come sempre) + le
# eventuali bacche (il sottotipo fruit_bearing/wood_only arriva già congelato in
# shrub_individual_subtype, vedi IndividualVegetationService). Ricalcolato anche quando cambia
# solo il sottotipo (set_shrub_subtypes), non solo le posizioni.
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
# Anno di nascita virtuale per individuo SHRUB — stesso principio di tree_birth_year_store sopra
# (Dictionary di proprietà del chiamante, MacroCellState.shrub_virtual_birth_year, passato per
# riferimento da set_shrub_age_params): il congelamento vero avviene in IndividualVegetationService,
# questo renderer lo legge soltanto (vedi _resolve_age_band_and_size). Tenuta separata da
# tree_birth_year_store: stessa posizione griglia può ospitare risorse diverse in anni diversi,
# le due mappe non vanno mai confuse.
var shrub_birth_year_store: Dictionary = {}

# Calcolo COMPLETO di un individuo SHRUB — geometria a schermo, a partire da un sottotipo/età già
# NOTI (mai più decisi qui, vedi IndividualVegetationService) — riusato sia da
# _rebuild_shrub_multimeshes (che vi costruisce sopra i singoli blob/bacche) sia dalle query
# pubbliche get_individual_screen_position/get_individual_info.
func _compute_shrub_visual(individual_key: Vector3i, lot_counts: Dictionary) -> Dictionary:
	var pos := Vector2i(individual_key.x, individual_key.y)
	var index: int = individual_key.z
	# Stesso principio di decorrelazione di _compute_tree_visual.
	var jitter_pos := pos + Vector2i(index * 619, index * 823)

	# Letto da shrub_individual_subtype (congelato alla nascita dell'individuo, vedi
	# IndividualVegetationService) invece di ritestato ogni volta contro un rapporto corrente.
	var subtype_name: String = shrub_individual_subtype.get(individual_key, "wood_only")
	var is_fruit_bearing: bool = subtype_name == "fruit_bearing"

	var resolved := _resolve_age_band_and_size(individual_key, subtype_name, shrub_age_params, shrub_birth_year_store, shrub_current_year)
	var age_band: GameTypes.AgeBand = resolved["age_band"]
	var age_size_multiplier: float = resolved["size_multiplier"]

	# Stesse due scale indipendenti di _compute_tree_visual — vedi il commento lì.
	var spacing := _resolve_density_scale_and_offset_range(int(lot_counts.get(pos, 1)))
	var offset_range: float = spacing["offset_range"]
	var density_scale: float = spacing["density_scale"]
	var size_multiplier: float = age_size_multiplier * density_scale

	var base := Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)
	var half: float = CELL_SIZE / 2.0
	# `center` per-individuo (non fisso al centro esatto del lotto): senza di esso più shrub nello
	# stesso lotto ancorerebbero l'intero cluster di blob allo stesso identico punto,
	# sovrapponendosi per costruzione indipendentemente da quanto i singoli blob si disperdono
	# attorno al centro.
	var center_offset_x: float = lerp(-offset_range, offset_range, float(hash(jitter_pos * 17 + Vector2i(53, 9)) % 1000) / 1000.0)
	var center_offset_y: float = lerp(-offset_range, offset_range, float(hash(jitter_pos * 19 + Vector2i(9, 53)) % 1000) / 1000.0)
	var center := base + Vector2(half, half) + Vector2(center_offset_x, center_offset_y)

	return {
		"is_fruit_bearing": is_fruit_bearing, "subtype_name": subtype_name, "age_band": age_band,
		"years_lived": shrub_current_year - int(shrub_birth_year_store.get(individual_key, shrub_current_year)),
		"jitter_pos": jitter_pos, "center": center, "density_scale": density_scale, "size_multiplier": size_multiplier,
	}


func _rebuild_shrub_multimeshes() -> void:
	_ensure_vegetation_meshes()
	_ensure_vegetation_multimeshes()

	var positions: Array = vegetation_positions.get(GameTypes.WorldObjectType.SHRUB, []) # Array[Vector3i]: lotto x,y + indice individuo
	var blob_transforms: Array = []
	var blob_colors: Array = []
	var berry_transforms: Array = []

	# Estensione nota (vivi+bloccati), vedi commento in _rebuild_tree_multimeshes.
	var lot_counts: Dictionary = _lot_extent_counts(GameTypes.WorldObjectType.SHRUB)

	for individual_key in positions:
		var visual: Dictionary = _compute_shrub_visual(individual_key, lot_counts)
		var jitter_pos: Vector2i = visual["jitter_pos"]
		var center: Vector2 = visual["center"]
		var density_scale: float = visual["density_scale"]
		var size_multiplier: float = visual["size_multiplier"]

		var blob_count: int = 3 + (hash(jitter_pos) % 2) # 3 o 4 lobi, variabile per shrub
		for i in range(blob_count):
			var salt: Vector2i = SHRUB_BLOB_SALTS[i]
			var angle: float = (float(hash(jitter_pos * salt.x + Vector2i(salt.y, i)) % 1000) / 1000.0) * TAU
			# distance scala per density_scale (non per size_multiplier pieno, età esclusa): la
			# COMPATTEZZA del cluster segue quanto il lotto è affollato, non la fascia d'età di
			# questo singolo individuo — altrimenti un giovane in un lotto affollato avrebbe un
			# cluster ancora più compresso di un adulto nello stesso lotto, un segnale ridondante
			# con age_size_multiplier che già scala il raggio dei blob sotto.
			var distance: float = lerp(0.8, 1.8, float(hash(jitter_pos * salt.y + Vector2i(i, salt.x)) % 1000) / 1000.0) * density_scale
			var radius: float = lerp(1.4, 2.2, float(hash(jitter_pos * (salt.x + salt.y) + Vector2i(i, i)) % 1000) / 1000.0) * size_multiplier
			var hue_t: float = float(hash(jitter_pos * (salt.x + salt.y + 41) + Vector2i(i, i + 1)) % 1000) / 1000.0
			var blob_color: Color = COLOR_SHRUB_GREEN.lerp(COLOR_SHRUB_BROWN, hue_t)
			var blob_center := center + Vector2(cos(angle), sin(angle)) * distance

			var blob_transform := Transform2D(0, Vector2.ZERO).scaled(Vector2(radius, radius))
			blob_transform.origin = blob_center
			blob_transforms.append(blob_transform)
			blob_colors.append(blob_color)

		# YOUNG non produce mai bacche (production_coefficient_young = 0.0, stesso coefficiente
		# usato dal calcolo calorico): il test di fruttiferità resta indipendente dalla fascia
		# età, ma qui viene comunque soppresso per gli individui YOUNG.
		if visual["is_fruit_bearing"] and visual["age_band"] != GameTypes.AgeBand.YOUNG:
			var berry_count: int = 2 + (hash(jitter_pos * 61 + Vector2i(3, 8)) % 2) # 2 o 3 bacche
			for i in range(berry_count):
				var berry_salt: Vector2i = SHRUB_BERRY_SALTS[i % SHRUB_BERRY_SALTS.size()]
				var berry_angle: float = (float(hash(jitter_pos * berry_salt.x + Vector2i(berry_salt.y, i + 100)) % 1000) / 1000.0) * TAU
				# distance scala per density_scale, stesso principio della distanza dei blob sopra
				# (compattezza del cluster legata all'affollamento del lotto, non alla fascia età).
				var berry_distance: float = lerp(0.6, 1.6, float(hash(jitter_pos * berry_salt.y + Vector2i(i + 100, berry_salt.x)) % 1000) / 1000.0) * density_scale
				var berry_center := center + Vector2(cos(berry_angle), sin(berry_angle)) * berry_distance

				# Raggio scalato per size_multiplier (età*densità), stesso principio del raggio dei
				# blob sopra: prima fisso a 0.55, ora proporzionato invece di restare sproporzionato
				# rispetto a un cluster ormai rimpicciolito.
				var berry_radius: float = 0.55 * size_multiplier
				var berry_transform := Transform2D(0, Vector2.ZERO).scaled(Vector2(berry_radius, berry_radius))
				berry_transform.origin = berry_center
				berry_transforms.append(berry_transform)

	_apply_transforms(_shrub_multimesh, blob_transforms)
	for i in range(blob_colors.size()):
		_shrub_multimesh.set_instance_color(i, blob_colors[i])

	_apply_transforms(_berry_multimesh, berry_transforms)


# Quanti individui condividono lo stesso lotto (microcella) — serve a _resolve_density_scale_and_
# offset_range sotto per decidere quanto rimpicciolire/disperdere ciascun individuo. Pre-pass
# leggero (O(n)): una passata sola su `positions` prima del loop principale, non ricalcolato
# individuo per individuo.
func _count_individuals_per_lot(positions: Array) -> Dictionary:
	var counts: Dictionary = {}
	for individual_key in positions:
		var lot_pos := Vector2i(individual_key.x, individual_key.y)
		counts[lot_pos] = int(counts.get(lot_pos, 0)) + 1
	return counts


# A local_count=1 (il caso comune) offset_range=BASE_OFFSET_RANGE e density_scale=1.0: nessuna
# regressione visiva rispetto a prima dell'introduzione degli individui multipli per lotto — sono
# esattamente i valori hard-coded che il rendering usava quando ogni lotto ospitava un solo
# individuo. Oltre 1: offset_range cresce linearmente con local_count fino a SPREAD_REFERENCE_
# COUNT (il caso "lotto affollato" osservato in editor), poi resta al massimo; density_scale
# scala per 1/sqrt(local_count) — un raggio ∝ 1/√N mantiene l'area complessiva disegnata da N
# individui piccoli paragonabile a quella di 1 individuo grande — con un floor MIN_DENSITY_SCALE
# così anche un lotto molto affollato resta visibile/cliccabile. Le due scale sono indipendenti
# tra loro E indipendenti da age_size_multiplier (fascia d'età, calcolato altrove): il chiamante
# le compone moltiplicandole, mai l'una al posto dell'altra.
const SPREAD_REFERENCE_COUNT: int = 5
const BASE_OFFSET_RANGE: float = 1.0
const MAX_OFFSET_RANGE: float = 3.0
const MIN_DENSITY_SCALE: float = 0.4

func _resolve_density_scale_and_offset_range(local_count: int) -> Dictionary:
	var jitter_scale: float = clamp(float(local_count - 1) / float(SPREAD_REFERENCE_COUNT - 1), 0.0, 1.0)
	var offset_range: float = lerp(BASE_OFFSET_RANGE, MAX_OFFSET_RANGE, jitter_scale)
	var density_scale: float = clamp(1.0 / sqrt(float(local_count)), MIN_DENSITY_SCALE, 1.0)
	return {"offset_range": offset_range, "density_scale": density_scale}


# Disposizione deterministica "a girasole" (Fibonacci disk, angolo aureo ~137.5°) usata SOLO da
# TREE (vedi _rebuild_tree_multimeshes) — SHRUB continua a usare offset_range sopra con due hash
# indipendenti per X/Y, e lì funziona bene: la chioma di uno shrub è già un cluster di blob
# sovrapposti per design, tollerante alla vicinanza. TREE invece ha una forma riconoscibile
# (tronco sottile + chioma), dove due hash indipendenti possono per puro caso concentrare più
# individui vicini (un problema di impacchettamento statistico, non risolvibile solo allargando
# il range) — anche una lieve vicinanza casuale si legge chiaramente come "due tronchi
# appiccicati". Questa disposizione garantisce GEOMETRICAMENTE che gli indici 0..local_count-1
# riempiano il disco disponibile in modo uniforme, mai per fortuna del hash: ogni individuo
# riceve un raggio crescente (∝ √((index+0.5)/local_count), distribuzione a densità areale
# costante — gli stessi semi di girasole usano questa costruzione in natura per riempirsi senza
# sovrapporsi) e un angolo che avanza dell'angolo aureo ad ogni indice (evita allineamenti
# periodici che un angolo "rotondo" produrrebbe). A local_count<=1 nessun offset — individuo
# unico, resta centrato come prima di questo cambiamento (il piccolo wobble organico si aggiunge
# comunque sopra, vedi il chiamante).
const GOLDEN_ANGLE: float = 2.399963229728653 # ~137.5077 gradi in radianti

func _fibonacci_disk_offset(index: int, local_count: int, max_radius: float) -> Vector2:
	if local_count <= 1:
		return Vector2.ZERO
	var radius: float = max_radius * sqrt((float(index) + 0.5) / float(local_count))
	var angle: float = float(index) * GOLDEN_ANGLE
	return Vector2(cos(angle), sin(angle)) * radius


# Fascia età + moltiplicatore dimensione per un INDIVIDUO (granularità per-individuo), condiviso
# da qualunque risorsa con age bands (oggi SHRUB e TREE) — PURA LETTURA: l'anno di nascita è già
# stato congelato una volta per sempre da IndividualVegetationService al momento della nascita
# dell'individuo (vedi shrub_birth_year_store/tree_birth_year_store, persistiti su MacroCellState,
# chiave Vector3i = lotto x,y + indice individuo locale), questa funzione non scrive mai più nulla
# lì — a differenza di prima di questa sessione, quando il congelamento avveniva qui al primo
# render reale. Nessuna entry per l'individuo (non ancora congelato per qualche motivo, o
# sottotipo con track_age_bands=false) => resta neutro, età ADULT/dimensione 1.0 di default.
func _resolve_age_band_and_size(
	individual_key: Vector3i,
	subtype_name: String,
	params_by_subtype: Dictionary,
	birth_year_store: Dictionary,
	current_year: int
) -> Dictionary:
	var params: Dictionary = params_by_subtype.get(subtype_name, {})
	if params.is_empty() or not birth_year_store.has(individual_key):
		return {"age_band": GameTypes.AgeBand.ADULT, "size_multiplier": 1.0}

	var years_lived: int = current_year - int(birth_year_store[individual_key])
	var age_band: GameTypes.AgeBand = AgeBandVisualService.band_for_age(
		years_lived, params["youth_duration_years"], params["adult_duration_years"]
	)
	return {"age_band": age_band, "size_multiplier": params["size_multiplier_by_age"][age_band]}


# Ciuffo d'erba stilizzato: 5-8 fili sottili (linee) sparsi su quasi tutta la larghezza della
# cella, ciascuno con angolo/altezza/colore leggermente diversi — stessa formula di sempre, ma
# accumulata in un'unica coppia di buffer punti/colori invece di un draw_line per filo: tutti i
# fili della cella vengono poi disegnati con una sola draw_multiline_colors in _draw().
var _grass_points: PackedVector2Array = PackedVector2Array()
var _grass_colors: PackedColorArray = PackedColorArray()

func _rebuild_grass_buffers() -> void:
	var points := PackedVector2Array()
	var colors := PackedColorArray()

	var palette: Dictionary = GRASS_PALETTE_BY_SEASON.get(current_season, {"base": COLOR_GRASS_BASE, "tip": COLOR_GRASS_TIP})
	var grass_base: Color = palette["base"]
	var grass_tip: Color = palette["tip"]

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
			var height: float = lerp(1.3, 2.4, float(hash(pos * (salt + 17) + Vector2i(salt, i)) % 1000) / 1000.0)
			var hue_t: float = float(hash(pos * (salt + 23) + Vector2i(i, salt + 5)) % 1000) / 1000.0
			var color: Color = grass_base.lerp(grass_tip, hue_t)

			var tip: Vector2 = blade_base + Vector2(cos(angle), sin(angle)) * height
			points.append(blade_base)
			points.append(tip)
			# draw_multiline_colors vuole un colore per SEGMENTO (colors.size() == points.size()/2),
			# non uno per punto — un'unica append qui, non due.
			colors.append(color)

	_grass_points = points
	_grass_colors = colors


# Pesce stilizzato: corpo a ellisse (cerchio unitario scalato in modo anisotropo *nello spazio
# locale* — scaled_local, non scaled: con scaled() la scala verrebbe applicata nello spazio
# globale DOPO la rotazione, e un cerchio è invariante per rotazione, quindi l'ellisse
# risulterebbe sempre allineata agli assi invece che orientata secondo heading — poi ruotato
# come corpo rigido) + una piccola coda triangolare agganciata dietro, stessa rotazione del
# corpo. Un solo heading casuale per pesce (da hash(pos)) dà varietà di orientamento senza
# bisogno di più primitive — stesso principio "poche forme condivise, trasformo per istanza"
# già usato per stone/tree/shrub.
const FISH_BODY_LENGTH_RANGE := Vector2(2.0, 3.0) # semiasse lungo (direzione di marcia)
const FISH_BODY_WIDTH_RANGE := Vector2(0.8, 1.2)  # semiasse corto (fianchi)
const FISH_TAIL_LENGTH_RATIO: float = 0.6 # relativo a body_length
const FISH_TAIL_WIDTH_RATIO: float = 1.3  # la coda è più larga della sezione del corpo

var _fish_body_mesh: ArrayMesh
var _fish_tail_mesh: ArrayMesh
var _fish_meshes_ready: bool = false

var _fish_body_multimesh: MultiMesh
var _fish_tail_multimesh: MultiMesh


func _ensure_fish_meshes() -> void:
	if _fish_meshes_ready:
		return
	_fish_meshes_ready = true

	_fish_body_mesh = _build_circle_mesh(VEGETATION_CIRCLE_SEGMENTS, COLOR_FISH_BODY)
	# Triangolo unitario: punta a sinistra (-1, 0), base sul lato destro (0, -1)/(0, 1) — il
	# lato destro è il punto di aggancio dietro al corpo (vedi tail_local_offset sotto).
	var tail_points := PackedVector2Array([Vector2(-1, 0), Vector2(0, -1), Vector2(0, 1)])
	_fish_tail_mesh = _build_fan_mesh(tail_points, COLOR_FISH_TAIL)


func _ensure_fish_multimeshes() -> void:
	if _fish_body_multimesh != null:
		return

	_fish_body_multimesh = _make_multimesh(_fish_body_mesh, false)
	_fish_tail_multimesh = _make_multimesh(_fish_tail_mesh, false)


func _rebuild_fish_multimeshes() -> void:
	_ensure_fish_meshes()
	_ensure_fish_multimeshes()

	var body_transforms: Array = []
	var tail_transforms: Array = []

	for pos in fish_positions:
		var base := Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)
		var half: float = CELL_SIZE / 2.0

		var offset_x: float = lerp(-1.0, 1.0, float(hash(pos * 5 + Vector2i(4, 12)) % 1000) / 1000.0)
		var offset_y: float = lerp(-1.0, 1.0, float(hash(pos * 5 + Vector2i(12, 4)) % 1000) / 1000.0)
		var center := base + Vector2(half, half) + Vector2(offset_x, offset_y)

		var heading: float = (float(hash(pos * 7 + Vector2i(31, 53)) % 1000) / 1000.0) * TAU
		var size_t: float = float(hash(pos) % 1000) / 1000.0
		var body_length: float = lerp(FISH_BODY_LENGTH_RANGE.x, FISH_BODY_LENGTH_RANGE.y, size_t)
		var body_width: float = lerp(FISH_BODY_WIDTH_RANGE.x, FISH_BODY_WIDTH_RANGE.y, size_t)

		var body_transform := Transform2D(heading, Vector2.ZERO).scaled_local(Vector2(body_length, body_width))
		body_transform.origin = center
		body_transforms.append(body_transform)

		var tail_length: float = body_length * FISH_TAIL_LENGTH_RATIO
		var tail_width: float = body_width * FISH_TAIL_WIDTH_RATIO
		# Punto dietro il corpo (bordo posteriore dell'ellisse, local (-body_length, 0) prima
		# della rotazione), ruotato dello stesso heading: qui la coda viene agganciata.
		var tail_local_offset: Vector2 = Vector2(-body_length, 0).rotated(heading)
		var tail_transform := Transform2D(heading, Vector2.ZERO).scaled_local(Vector2(tail_length, tail_width))
		tail_transform.origin = center + tail_local_offset
		tail_transforms.append(tail_transform)

	_apply_transforms(_fish_body_multimesh, body_transforms)
	_apply_transforms(_fish_tail_multimesh, tail_transforms)


func _draw_fish_positions() -> void:
	if _fish_body_multimesh != null and _fish_body_multimesh.instance_count > 0:
		draw_multimesh(_fish_body_multimesh, null)
		_debug_draw_primitive_count += 1
	if _fish_tail_multimesh != null and _fish_tail_multimesh.instance_count > 0:
		draw_multimesh(_fish_tail_multimesh, null)
		_debug_draw_primitive_count += 1


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


# Riempimento piatto del vicino diagonale in ciascuno dei 4 angoli — stesso pattern di
# _draw_neighbor_previews ma un quadrato NEIGHBOR_STRIP_DEPTH x NEIGHBOR_STRIP_DEPTH invece di
# una fascia intera, e sempre get_land_color (mai get_cell_color): un vicino-fiume qui mostra
# solo il suo terreno di base, senza fascia fluviale — l'angolo è troppo piccolo perché quella
# fascia sia percepibile/rilevante a questo livello di zoom (a differenza delle fasce cardinali
# sopra, dove il fiume attraversa l'intero lato ed è quindi sempre visibile). get_land_color
# resta comunque corretta anche per SEA/LAKE (terrain_base == WATER ci finisce comunque dentro),
# quindi un angolo davvero tutto-acqua si vede comunque blu.
# Riga tratteggiata sul perimetro del quadrato 100x100 reale: segna dove finisce la
# cella "giocabile" e comincia la sola anteprima dei vicini.
func _draw_boundary(grid_size: int) -> void:
	draw_dashed_line(Vector2(0, 0), Vector2(grid_size, 0), BOUNDARY_DASH_COLOR, BOUNDARY_DASH_WIDTH, BOUNDARY_DASH_LENGTH)
	draw_dashed_line(Vector2(0, grid_size), Vector2(grid_size, grid_size), BOUNDARY_DASH_COLOR, BOUNDARY_DASH_WIDTH, BOUNDARY_DASH_LENGTH)
	draw_dashed_line(Vector2(0, 0), Vector2(0, grid_size), BOUNDARY_DASH_COLOR, BOUNDARY_DASH_WIDTH, BOUNDARY_DASH_LENGTH)
	draw_dashed_line(Vector2(grid_size, 0), Vector2(grid_size, grid_size), BOUNDARY_DASH_COLOR, BOUNDARY_DASH_WIDTH, BOUNDARY_DASH_LENGTH)
