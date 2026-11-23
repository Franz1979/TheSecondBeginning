class_name BuildingModels3D
extends RefCounted

# Oggetto 3D: gli edifici di UNA cella che hanno modelli Blender (.glb in render3d/assets/models/buildings/, ricette in
# SOURCES_PER_GIOCO/blender/scripts/). Un modello per fase: indice = fase di BuildingConstructionStage (0 = cantiere non
# allestito, 1..N fasi del lavoro), l'ultimo = edificio finito. Se manca il modello di una fase, quell'edificio non si
# disegna (più avanti: cantiere generico). Modelli in metri: x 0,1 (1 microcella = 10 m). Porta verso -Z del modello.

const MODEL_SCALE := 0.1
const MODEL_DIR := "res://render3d/assets/models/buildings/"
const MODELS := {
	# Fase 0 (piazzato, non allestito): nessun modello, solo il cartello — non ha ancora portato niente nessuno.
	"stick_tent": ["", "stick_tent_1_struttura", "stick_tent_2_copertura", "stick_tent_3_finita"],
	# Tenda di pelli (2026-11-23): stesse soglie della tenda di rami ([0.0, 0.4] in hide_tent.tres), un po' più grande.
	"hide_tent": ["", "hide_tent_1_struttura", "hide_tent_2_copertura", "hide_tent_3_finita"],
	"stacked_stones": ["", "stacked_stones_1_base", "stacked_stones_2_meta", "stacked_stones_3_finita"],
	# waste_pit.tres non ha soglie: tutto lo scavo è fase 1.
	"waste_pit": ["", "waste_pit_1_scavo", "waste_pit_2_finita"],
	# Macerie di un edificio crollato (2026-11-23, SOURCES_PER_GIOCO/blender/scripts/rubble.py): compaiono già intere, una
	# fase sola. Lo stesso modello va sopra i cantieri coi detriti dei ceppi (site_debris, _add_site_debris).
	"rubble": ["", "rubble"],
	# drying_rack.tres non ha soglie: tutto il lavoro è fase 1. Il finito è vuoto: i carichi li appende _add_rack_loads.
	"drying_rack": ["", "drying_rack_1_cantiere", "drying_rack_2_finito"],
	# deposit_site.tres non ha soglie: tutto il lavoro è fase 1. Il finito è solo il contorno di bastoni a terra: i mucchi
	# nei 9 posti al centro li mette Piles3D (SOURCES_PER_GIOCO/blender/scripts/deposit_site.py).
	"deposit_site": ["", "deposit_site_1_cantiere", "deposit_site_2_finito"],
	# pebble_circle.tres non ha soglie: tutto il lavoro è fase 1 (mucchio di sassolini e primi sassi posati).
	"pebble_circle": ["", "pebble_circle_1_cantiere", "pebble_circle_2_finito"],
	# campfire.tres non ha soglie. Il finito è vuoto qui: pietre e legna (per stato) le mette HearthFire3D, coi suoi effetti.
	"campfire": ["", "campfire_1_cantiere", ""],
	# smokehouse.tres non ha soglie: tutto il lavoro è fase 1. Il finito è vuoto: carichi appesi (_add_rack_loads), catasta
	# (_add_fuel_piles) e fuoco (Hearth3D, senza le sue pietre) secondo lo stato vero.
	"smokehouse": ["", "smokehouse_1_cantiere", "smokehouse_2_finito"],
	# stone_ford.tres non ha soglie: tutto il lavoro è fase 1. Nessun .glb: la forma la compone _ford_mesh coi sassi del
	# gioco (FORD_STONES); i nomi qui servono solo a contare le fasi.
	"stone_ford": ["", "stone_ford_1_cantiere", "stone_ford_2_finito"],
	# earthwork.tres non ha soglie: tutto il lavoro è fase 1. La forma la compone _earthwork_mesh dai pezzi secondo i vicini;
	# i nomi qui servono solo a contare le fasi.
	"earthwork": ["", "earthwork_1_cantiere", "earthwork_2_finito"],
	# Capanna dell'attrezzaio (2026-11-23): soglie [0.0, 0.4] in toolmaker_hut.tres come le tende. Il finito ha la
	# rastrelliera vuota: gli attrezzi pronti li mette _add_fuel_piles (TOOLMAKER_TOOL_BY_RESOURCE).
	"toolmaker_hut": ["", "toolmaker_hut_1_struttura", "toolmaker_hut_2_copertura", "toolmaker_hut_3_finita"],
	# Deposito coperto (2026-11-23): soglie [0.0, 0.4] in covered_depot.tres. Solo la tettoia: i mucchi nei 9 posti li
	# mette Piles3D, come per il sito di deposito.
	"covered_depot": ["", "covered_depot_1_pali", "covered_depot_2_telaio", "covered_depot_3_finito"],
	# Cumulo sepolcrale (2026-11-23): soglie [0.0, 0.4] in burial.tres. Uguale qualunque sia il numero dei sepolti.
	"burial": ["", "burial_1_scavo", "burial_2_tumulo", "burial_3_finito"],
	# Spiazzo delle feste (2026-11-23, 2x2): soglie [0.0, 0.4] in feast_ground.tres. Il finito non ha il fuoco: lo mette
	# Hearth3D (focolare con le sue pietre), acceso durante il banchetto.
	"feast_ground": ["", "feast_ground_1_mucchi", "feast_ground_2_cerchio", "feast_ground_3_finito"],
}

# Vallo di terra (2026-11-23, SOURCES_PER_GIOCO/blender/scripts/earthwork.py): edificio lineare, un pezzo per microcella
# composto come nel 2D (LinearShape) dalla maschera dei vicini ("linear_neighbors" del 2D): angolo girato per la sua
# coppia di lati, altrimenti cumulo più un braccio per lato. Pezzi modellati col nord a -Z (braccio verso nord, angolo
# tra nord ed est): il modello non si gira con la porta. Cantiere: la stessa forma schiacciata in altezza.
const EARTHWORK_TYPE := "earthwork"
const EARTHWORK_CENTER := "earthwork_centro"
const EARTHWORK_ARM := "earthwork_braccio"
const EARTHWORK_CORNER := "earthwork_angolo"
# Maschera dell'angolo -> quarti di giro in senso orario dal pezzo "angolo" (nord+est). Bit: N 1, E 2, S 4, O 8.
const EARTHWORK_CORNER_TURNS := {0b0011: 0, 0b0110: 1, 0b1100: 2, 0b1001: 3}
const EARTHWORK_CANTIERE_HEIGHT := 0.45   # CANTIERE_HEIGHT della ricetta
static var _earthwork_meshes: Dictionary = {}

# Guado di pietre (2026-11-22, richiesta utente: pietre come quelle del gioco, più distanziate del 2D): i sassi Quaternius
# della vista 3D (Pebble3D, render3d/assets/models/rocks/, larghi circa FORD_PEBBLE_WIDTH m) ingranditi, più spessi
# (FORD_VERTICAL) e affondati (FORD_SINK) perché sporgano di circa 30 cm anche dove la riva scende verso l'acqua. Stessi
# numeri della scena di revisione SOURCES_PER_GIOCO/blender/scripts/stone_ford.py (STONES, HEAP), qui con z = -y del
# Blender. Fila lungo z: l'edificio si gira di traverso al ruscello (StreamMicrocellService.ford_angle, come il 2D, letto
# da GameStateReader come direzione della "porta"). Per pietra: x, z, sasso, larghezza (m), rotazione (gradi).
const FORD_TYPE := "stone_ford"
const FORD_ROCKS_DIR := "res://render3d/assets/models/rocks/"
const FORD_STONES := [
	[0.35, 3.9, "pebble_round_2", 1.7, 20.0],
	[-0.35, 1.3, "pebble_round_4", 1.8, 75.0],
	[0.3, -1.3, "pebble_round_5", 1.8, 140.0],
	[-0.3, -3.9, "pebble_round_3", 1.7, 250.0],
]
# Cantiere: le due pietre delle rive (la prima e l'ultima) e sulla riva un mucchietto: x, z, quota, sasso, larghezza, gradi.
const FORD_HEAP := [
	[2.5, 4.2, 0.0, "pebble_square_1", 0.8, 10.0],
	[3.1, 4.4, 0.0, "pebble_square_3", 0.7, 80.0],
	[2.7, 4.7, 0.0, "pebble_round_1", 0.75, 200.0],
	[2.8, 4.4, 0.18, "pebble_square_2", 0.65, 130.0],
]
const FORD_PEBBLE_WIDTH := 1.1
const FORD_VERTICAL := 2.0
const FORD_SINK := 0.4
const FORD_HEAP_SINK := 0.05
static var _ford_meshes: Dictionary = {}

# Essiccatoio (SOURCES_PER_GIOCO/blender/scripts/drying_rack.py): un carico appeso per posto occupato, nell'ordine dei posti, alle
# x di SLOT_X della ricetta. Carne e pesce alla traversa alta, pelle alla bassa (punti in metri, assi di Godot: la y del
# Blender diventa -z). Ingrediente fresco e prodotto secco hanno lo stesso carico.
const RACK_TYPE := "drying_rack"
const RACK_ITEM_BY_RESOURCE := {
	"meat": "carne", "dried_meat": "carne",
	"fish_meat": "pesce", "dried_fish": "pesce",
	"hide": "pelle", "dried_hide": "pelle",
}
const RACK_SLOT_X := [-2.0, -1.2, -0.4, 0.4, 1.2, 2.0]  # graticcio stretto (2026-11-21)
# Ogni carico in tre misure secondo quanto è pieno il posto (2026-11-23): drying_rack_<carico>_1..3.glb (1, 2 o 3 pezzi);
# la misura la sceglie GameStateReader._sized_load. Un modello per posto, come prima.
const RACK_LOAD_LEVELS := 3
const RACK_TOP_HANG := Vector2(1.78, 0.0)     # (quota, z) traversa alta
const RACK_LOW_HANG := Vector2(1.05, -0.4225) # (quota, z) traversa bassa

# Affumicatoio (SOURCES_PER_GIOCO/blender/scripts/smokehouse.py, 2026-11-22): gli stessi carichi dell'essiccatoio, uno per
# posto occupato da carne, pesce o pelle (da affumicare o già affumicati), agli 8 punti SLOTS della ricetta: prima i 4
# della traversa davanti, poi i 4 di quella sotto la tettoia. Punti (x, quota, z) in metri, assi di Godot.
const SMOKEHOUSE_TYPE := "smokehouse"
const SMOKEHOUSE_ITEM_BY_RESOURCE := {
	"meat": "carne", "smoked_meat": "carne",
	"fish_meat": "pesce", "smoked_fish": "pesce",
	"hide": "pelle", "smoked_hide": "pelle",
}
const SMOKEHOUSE_SLOTS := [
	Vector3(-3.1, 1.85, -3.0), Vector3(-2.3, 1.85, -3.0), Vector3(1.3, 1.85, -3.0), Vector3(2.2, 1.85, -3.0),
	Vector3(-2.8, 1.698, 1.9), Vector3(-1.4, 1.698, 1.9), Vector3(0.0, 1.698, 1.9), Vector3(1.4, 1.698, 1.9),
]
# Catasta sul fianco: ceppi se c'è legna da ardere, fascine se ci sono bastoni (i due combustibili del gioco).
const SMOKEHOUSE_FUEL_PILES := {"firewood": "smokehouse_ceppi", "stick": "smokehouse_rametti"}
# Attrezzeria (SOURCES_PER_GIOCO/blender/scripts/toolmaker_hut.py, 2026-11-23): un modello per tipo di attrezzo pronto nei
# Prodotti finiti, già al suo posto attorno alla rastrelliera (o il travois sul fianco della capanna).
const TOOLMAKER_TYPE := "toolmaker_hut"
const TOOLMAKER_TOOL_BY_RESOURCE := {
	"stone_spear": "toolmaker_hut_lancia", "bow": "toolmaker_hut_arco", "arrow_bundle": "toolmaker_hut_frecce",
	"stone_axe": "toolmaker_hut_ascia", "bone_pick": "toolmaker_hut_piccone", "dried_hide_bag": "toolmaker_hut_borsa",
	"smoked_hide_bag": "toolmaker_hut_borsa_affumicata", "waterskin": "toolmaker_hut_otre", "travois": "toolmaker_hut_travois",
}
# Centro del focolare nel modello (HEARTH_CENTER della ricetta: x -0,4, y 1,6 del Blender), in metri, assi di Godot.
const SMOKEHOUSE_HEARTH := Vector3(-0.4, 0.0, -1.6)
# Spiazzo delle feste: il falò del banchetto è un focolare al centro del quadrato.
const FEAST_GROUND_TYPE := "feast_ground"
const RUBBLE_TYPE := "rubble"

# Fossa dei rifiuti (SOURCES_PER_GIOCO/blender/scripts/waste_pit.py): lo strato di rifiuti sale dal fondo alla cima della parete
# e si allarga con lei secondo quanto è piena (BuildingModelsSnapshot3D.fills); piena del tutto = il cumulo stracolmo.
# Misure in metri come nella ricetta (FLOOR_Z, WALL_TOP_Z, FLOOR_RADIUS, WALL_TOP_RADIUS).
const PIT_FILL := "waste_pit_riempimento"
const PIT_FULL := "waste_pit_stracolma"
const PIT_FILL_RISE := 0.45 - 0.03
const PIT_FILL_WIDEN := 3.1 / 2.6 - 1.0

# Cartello dei cantieri non allestiti, per tutti i tipi (SOURCES_PER_GIOCO/blender/scripts/wip_sign.py).
const WIP_SIGN := "wip_sign"

# Niente LOD per gli edifici (2026-11-20, richiesta utente): con la soglia LOD della vista 3D (UserOptions.quality_3d_lod_threshold,
# 16 px) la semplificazione automatica dell'import cancellava da lontano i pezzi piccoli e staccati (sassi e bastoncini
# delle pietre rituali). Gli edifici sono pochi: si tiene sempre il modello pieno, con una lod_bias altissima su ogni
# MeshInstance3D (anche cartello, riempimento della fossa e carichi dell'essiccatoio).
const NO_LOD_BIAS := 1000.0


static func has_models(type_name: String) -> bool:
	return MODELS.has(type_name)


# base_global: angolo della cella in microcelle assolute (per l'altezza del terreno). stream_mask: maschera del ruscello
# della cella (StreamMask3D, per la quota del guado; null = niente ruscello). null se non c'è niente da disegnare.
static func build(snapshot: BuildingModelsSnapshot3D, base_global: Vector2, stream_mask: Image = null) -> Node3D:
	if snapshot.size() == 0:
		return null
	var root := Node3D.new()
	for i in range(snapshot.size()):
		var center := snapshot.centers[i]
		var y := GroundHeight3D.land_height(base_global.x + center.x, base_global.y + center.y)
		var position := Vector3(center.x, y, center.y)
		# Cartello "cantiere" su ogni edificio piazzato e non ancora allestito (come nel 2D), sempre girato verso sud
		# (la camera guarda da lì); giallo su tutte e due le facce.
		if snapshot.stages[i] == BuildingConstructionStage.NOT_SET_UP:
			var sign_mesh := _load_mesh(WIP_SIGN)
			if sign_mesh != null:
				var sign_instance := MeshInstance3D.new()
				sign_instance.mesh = sign_mesh
				sign_instance.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * MODEL_SCALE), position)
				root.add_child(sign_instance)
		if i < snapshot.site_debris.size() and snapshot.site_debris[i]:
			_add_site_debris(root, position, snapshot.ids[i])
		var linear_mask := snapshot.linear_masks[i] if i < snapshot.linear_masks.size() else 0
		var mesh := _mesh_for(snapshot.type_names[i], snapshot.stages[i], linear_mask)
		if mesh == null:
			continue
		if snapshot.type_names[i] == FORD_TYPE:
			position.y = _ford_ground(base_global, center, stream_mask)
		var door := snapshot.doors[i]
		# Vallo: i pezzi sono già girati per lato, il modello resta col nord a -Z.
		if snapshot.type_names[i] == EARTHWORK_TYPE:
			door = Vector2(0.0, -1.0)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		var basis := Basis.looking_at(Vector3(door.x, 0.0, door.y), Vector3.UP).scaled(Vector3.ONE * MODEL_SCALE)
		instance.transform = Transform3D(basis, position)
		instance.set_meta("building_id", snapshot.ids[i])
		root.add_child(instance)
		if i < snapshot.fills.size() and snapshot.fills[i] > 0.0:
			_add_pit_fill(instance, snapshot.fills[i])
		if i < snapshot.rack_loads.size() and not snapshot.rack_loads[i].is_empty():
			_add_rack_loads(instance, snapshot.rack_loads[i], snapshot.type_names[i])
		if i < snapshot.fuel_piles.size() and not snapshot.fuel_piles[i].is_empty():
			_add_fuel_piles(instance, snapshot.fuel_piles[i])
	if root.get_child_count() == 0:
		root.free()
		return null
	_disable_lod(root)
	return root


static func _disable_lod(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).lod_bias = NO_LOD_BIAS
	for child in node.get_children():
		_disable_lod(child)


# Riempimento della fossa, figlio del suo modello (stessa scala e rotazione, misure in metri del modello).
static func _add_pit_fill(pit: MeshInstance3D, fill: float) -> void:
	var full := fill >= 1.0
	var mesh := _load_mesh(PIT_FULL if full else PIT_FILL)
	if mesh == null:
		return
	var layer := MeshInstance3D.new()
	layer.mesh = mesh
	if not full:
		var widen := 1.0 + PIT_FILL_WIDEN * fill
		layer.transform = Transform3D(Basis.IDENTITY.scaled(Vector3(widen, 1.0, widen)), Vector3(0.0, PIT_FILL_RISE * fill, 0.0))
	pit.add_child(layer)


# Carichi appesi all'essiccatoio o all'affumicatoio, figli del suo modello (stessa scala e rotazione, misure in metri del
# modello). Gli stessi modelli per tutti e due.
static func _add_rack_loads(rack: MeshInstance3D, loads: PackedStringArray, type_name: String) -> void:
	var smokehouse := type_name == SMOKEHOUSE_TYPE
	var slot_count := SMOKEHOUSE_SLOTS.size() if smokehouse else RACK_SLOT_X.size()
	for slot in range(mini(loads.size(), slot_count)):
		var item := loads[slot]
		if item.is_empty():
			continue
		var mesh := _load_mesh("drying_rack_" + item)
		if mesh == null:
			continue
		var load_instance := MeshInstance3D.new()
		load_instance.mesh = mesh
		if smokehouse:
			load_instance.position = SMOKEHOUSE_SLOTS[slot]
		else:
			var hang: Vector2 = RACK_LOW_HANG if item.begins_with("pelle") else RACK_TOP_HANG
			load_instance.position = Vector3(RACK_SLOT_X[slot], hang.x, hang.y)
		rack.add_child(load_instance)


# Macerie sopra un cantiere coi detriti dei ceppi, al centro dell'edificio come nel 2D (non girate: il mucchio è tondo).
static func _add_site_debris(root: Node3D, position: Vector3, building_id: int) -> void:
	var mesh := _load_mesh(RUBBLE_TYPE)
	if mesh == null:
		return
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * MODEL_SCALE), position)
	instance.set_meta("building_id", building_id)
	root.add_child(instance)


# Catasta dell'affumicatoio (ceppi, fascine) o attrezzi pronti dell'attrezzeria, figli del modello: già al loro posto.
static func _add_fuel_piles(building: MeshInstance3D, piles: PackedStringArray) -> void:
	for pile_name in piles:
		var mesh := _load_mesh(pile_name)
		if mesh == null:
			continue
		var pile := MeshInstance3D.new()
		pile.mesh = mesh
		building.add_child(pile)


# Dove sta il focolare dell'affumicatoio rispetto al centro dell'edificio, in microcelle (x = est, y = sud), con la porta
# verso `door` (stessa rotazione del modello in build()).
static func smokehouse_hearth_offset(door: Vector2) -> Vector2:
	var basis := Basis.looking_at(Vector3(door.x, 0.0, door.y), Vector3.UP)
	var offset := basis * SMOKEHOUSE_HEARTH * MODEL_SCALE
	return Vector2(offset.x, offset.z)


# Modello dell'edificio finito (anteprima del piazzamento, PlacementGhost3D); null se il tipo non ha modelli.
# linear_mask: vicini del pezzo per gli edifici lineari (il vallo), come nel 2D.
static func finished_mesh(type_name: String, linear_mask: int = 0) -> Mesh:
	return _mesh_for(type_name, BuildingConstructionStage.COMPLETE, linear_mask)


static func _mesh_for(type_name: String, stage: int, linear_mask: int = 0) -> Mesh:
	var names: Array = MODELS.get(type_name, [])
	if names.is_empty():
		return null
	var index := names.size() - 1 if stage == BuildingConstructionStage.COMPLETE else stage
	if index < 0 or index >= names.size():
		return null
	if String(names[index]).is_empty():
		return null
	if type_name == FORD_TYPE:
		return _ford_mesh(index == names.size() - 1)
	if type_name == EARTHWORK_TYPE:
		return _earthwork_mesh(linear_mask, index == names.size() - 1)
	return _load_mesh(names[index])


# Forma di un pezzo di vallo per la sua maschera dei vicini (bit 1 << lato, N E S O = 0..3, LinearShape): angolo = il
# pezzo "angolo" girato per la sua coppia di lati; altrimenti il cumulo più un braccio per lato. Cantiere: la stessa
# forma schiacciata (EARTHWORK_CANTIERE_HEIGHT). Una forma per maschera e fase, fatta una volta.
static func _earthwork_mesh(mask: int, finished: bool) -> Mesh:
	var key := mask * 2 + (1 if finished else 0)
	if _earthwork_meshes.has(key):
		return _earthwork_meshes[key]
	var squash := Vector3(1.0, 1.0 if finished else EARTHWORK_CANTIERE_HEIGHT, 1.0)
	var pieces: Array = []
	if EARTHWORK_CORNER_TURNS.has(mask):
		pieces.append([_load_mesh(EARTHWORK_CORNER), int(EARTHWORK_CORNER_TURNS[mask])])
	else:
		pieces.append([_load_mesh(EARTHWORK_CENTER), 0])
		for side in range(4):
			if mask & (1 << side):
				pieces.append([_load_mesh(EARTHWORK_ARM), side])
	var placed: Array = []
	for piece: Array in pieces:
		# Un quarto di giro in senso orario (visto dall'alto) per lato, come nella ricetta.
		var basis := Basis(Vector3.UP, -float(piece[1]) * PI / 2.0).scaled(squash)
		placed.append([piece[0], Transform3D(basis, Vector3.ZERO)])
	var result := _merge_meshes(placed)
	_earthwork_meshes[key] = result
	return result


# Fonde più forme, ognuna con la sua trasformazione ([Mesh, Transform3D]), in una forma sola con una superficie per
# materiale (le texture restano). Forme mancanti (null) saltate.
static func _merge_meshes(placed: Array) -> ArrayMesh:
	var tools := {} # Material -> SurfaceTool
	for entry: Array in placed:
		var mesh: Mesh = entry[0]
		if mesh == null:
			continue
		for surface in range(mesh.get_surface_count()):
			var material := mesh.surface_get_material(surface)
			if not tools.has(material):
				var new_tool := SurfaceTool.new()
				new_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[material] = new_tool
			(tools[material] as SurfaceTool).append_from(mesh, surface, entry[1])
	var result := ArrayMesh.new()
	for material in tools:
		var tool: SurfaceTool = tools[material]
		tool.set_material(material)
		tool.commit(result)
	return result


# Forma del guado (finito o cantiere): i sassi di FORD_STONES (e FORD_HEAP nel cantiere) messi al loro posto e fusi in
# una forma sola, una superficie per materiale (la texture dei sassi resta). Fatta una volta per fase.
static func _ford_mesh(finished: bool) -> Mesh:
	if _ford_meshes.has(finished):
		return _ford_meshes[finished]
	var pieces: Array = []
	for k in range(FORD_STONES.size()):
		if finished or k == 0 or k == FORD_STONES.size() - 1:
			var stone: Array = FORD_STONES[k]
			pieces.append([stone[0], stone[1], 0.0, stone[2], stone[3], stone[4], FORD_SINK])
	if not finished:
		for heap_stone: Array in FORD_HEAP:
			pieces.append(heap_stone + [FORD_HEAP_SINK])
	var placed: Array = []
	for piece: Array in pieces:
		var s := float(piece[4]) / FORD_PEBBLE_WIDTH
		var basis := Basis(Vector3.UP, deg_to_rad(float(piece[5]))).scaled(Vector3(s, s * FORD_VERTICAL, s))
		var xform := Transform3D(basis, Vector3(float(piece[0]), float(piece[2]) - float(piece[6]), float(piece[1])))
		placed.append([ModelMesh3D.load_mesh(FORD_ROCKS_DIR + String(piece[3]) + ".gltf"), xform])
	var result := _merge_meshes(placed)
	_ford_meshes[finished] = result
	return result


# Quota del guado: la media dei quattro angoli della sua microcella come li fa il terreno 3D (TerrainMesh3D: ondulazione
# meno il letto del ruscello), così le pietre stanno sulla riva scavata e non a livello del prato.
static func _ford_ground(base_global: Vector2, center: Vector2, stream_mask: Image) -> float:
	var i := int(floor(center.x))
	var j := int(floor(center.y))
	var total := 0.0
	for corner in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i, j + 1), Vector2i(i + 1, j + 1)]:
		var h := GroundHeight3D.land_height(base_global.x + corner.x, base_global.y + corner.y)
		if stream_mask != null:
			h -= StreamMask3D.bed_depth_at(stream_mask, corner.x, corner.y)
		total += h
	return total / 4.0


static func _load_mesh(model_name: String) -> Mesh:
	return ModelMesh3D.load_mesh(MODEL_DIR + model_name + ".glb")
