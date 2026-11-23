class_name Shrubs3D
extends RefCounted

# Oggetto 3D: i cespugli di UNA macrocella, nelle stesse posizioni e con le stesse bolle del 2D (ShrubSnapshot3D).
# Con USE_BUSH_MODELS (acceso, ombra spenta) i cespugli vivi sono modelli Quaternius da file, larghi quanto le bolle del 2D:
# - solo legno ("macchia"): Bush verde, ognuno con una sua tinta fissa (BUSH_TONES);
# - da frutto: tutti uguali, secondo la stagione come il 2D (ShrubSnapshot3D.fruit_state): coi fiori in primavera, con
#   le bacche in estate e autunno finché non sono raccolte, spoglio se raccolto, giovane o d'inverno.
# Con USE_BUSH_MODELS spento, come prima: macchia = cupola di bolle del 2D (ShrubBlob3D), rovo = bolle più tralci ad
# arco (ShrubCanes3D), col colore del 2D scurito un poco verso il verde delle chiome.
# Cespuglio tagliato e cespuglio morto (2026-11-20): da file (dead_cut_plants.py), un ciuffo di fusti mozzati e un Bush
# rado di foglie secche, larghi quanto la sagoma del 2D (taglia salvata al taglio o alla morte). Con USE_BUSH_MODELS
# spento il tagliato torna ai tralci spogli da codice e il morto non si vede.

# Le misure del 2D sono pensate per la vista dall'alto: qui si allargano come le chiome (Trees3D.CROWN_SCALE).
const SPREAD_SCALE := 1.5
const BLOB_SCALE := 1.5
const BLOB_SQUASH := 0.62
# Quanto la bolla resta sotto terra (frazione dell'altezza): la cupola sembra uscire dal suolo.
const BLOB_SINK := 0.35
const CANE_SCALE := 1.15
const CUT_SCALE := 1.6
const COLOR_TOWARD := Color("4f6e2e")
const COLOR_TOWARD_AMOUNT := 0.35
# Cespugli da file, dal 2026-11-20: modelli Quaternius (SOURCES_PER_GIOCO/blender/scripts/bushes.py), Bush_Common con le
# foglie tinte di verde chiaro per le macchie, Bush_Common_Flowers per i cespugli da frutto. Larghi 1 e alti 0,72 nel
# file: la larghezza diventa quella delle bolle del 2D (2 x extent) per BUSH_SCALE. Hanno il LOD dell'import.
# 2026-11-20: con le ombre la prova in partita (test3d.json, SSAO spento, 75%) era scesa da 53 a 22-23 fps, per le foglie
# in alpha di centinaia di cespugli disegnate anche nell'ombra. Riaccesi SENZA ombra (BUSH_CAST_SHADOWS) per misurare
# quanto pesava l'ombra; false rimette le bolle.
# PROVA FPS (2026-11-21, reversibile): false = bolle e tralci low poly di prima, senza foglie a ritaglio; true = com'era.
const USE_BUSH_MODELS := true
const BUSH_CAST_SHADOWS := false
const BUSH_DIR := "res://render3d/assets/models/vegetation/bushes/"
# Versioni con metà delle foglie (scelte dall'utente il 2026-11-20 dal confronto originale / metà / un terzo, bushes.py
# LEVELS). Per tornare indietro: "bush_common", "bush_common_flowers" (originali) o il suffisso "_33" (un terzo).
const BUSH_MODELS := ["bush_common_50", "bush_common_flowers_50", "bush_fruit_berries_50", "bush_fruit_bare_50"]
const BUSH_WOOD := 0 # indici in BUSH_MODELS: cespuglio solo legno
const BUSH_FRUIT := 1 # da frutto coi fiori
const BUSH_FRUIT_BERRIES := 2 # da frutto con le bacche
const BUSH_FRUIT_BARE := 3 # da frutto spoglio
# Tinte delle macchie (richiesta utente 2026-11-20: non tutte dello stesso verde, niente colori di stagione): moltiplicano
# il verde chiaro della texture, una per individuo e sempre la stessa (dal suo seme). Verdi dal chiaro al medio per lo
# più, qualcuna giallina, una su otto circa sul rossiccio. I cespugli da frutto restano tutti uguali (bianco = nessuna tinta).
const BUSH_GREEN_LIGHT := Color(1.0, 1.0, 1.0)
const BUSH_GREEN_DARK := Color(0.66, 0.76, 0.66)
const BUSH_YELLOWISH := Color(1.0, 0.95, 0.62)
const BUSH_REDDISH_A := Color(1.0, 0.62, 0.52)
const BUSH_REDDISH_B := Color(0.95, 0.5, 0.42)
const BUSH_REDDISH_PERCENT := 12
const BUSH_YELLOWISH_PERCENT := 12
const BUSH_SCALE := 1.0
# Quanto il piede scende sotto terra (frazione dell'altezza): sul terreno in pendenza non resta sospeso.
const BUSH_SINK := 0.05
static var _bush_meshes: Array = []
const DEAD_CUT_DIR := "res://render3d/assets/models/vegetation/dead_cut/"
# Larghezza del modello = diametro della sagoma del 2D (stella dei rovi tagliati, cerchio della pianta secca) per
# questo fattore, lo stesso allargamento delle bolle dei cespugli vivi.
const DEAD_CUT_WIDTH_SCALE := 2.0 * SPREAD_SCALE


# base_global: angolo della cella in microcelle assolute (per l'altezza del terreno). null se non c'è niente.
static func build(snapshot: ShrubSnapshot3D, base_global: Vector2, material: Material) -> Node3D:
	if snapshot.size() == 0 and snapshot.cut_centers.is_empty() and snapshot.dead_centers.is_empty():
		return null
	var blob_meshes := ShrubBlob3D.meshes()
	var bush_meshes := _get_bush_meshes() if USE_BUSH_MODELS else []
	var bush_transforms := _empty_lists(bush_meshes.size())
	var bush_colors := _empty_lists(bush_meshes.size())
	var leafy_meshes := ShrubCanes3D.leafy_meshes()
	var bare_meshes := ShrubCanes3D.bare_meshes()
	var blob_transforms := _empty_lists(blob_meshes.size())
	var blob_colors := _empty_lists(blob_meshes.size())
	var leafy_transforms := _empty_lists(leafy_meshes.size())
	var bare_transforms := _empty_lists(bare_meshes.size())
	# Cespugli che possono avere le bacche: indice dell'individuo -> indice tra i candidati. Ognuno va sia tra quelli con
	# le bacche sia tra gli spogli; quello che non si vede ha scala zero (apply_berries li scambia).
	var berry_of: Dictionary = {}
	for j in range(snapshot.berry_index.size()):
		berry_of[snapshot.berry_index[j]] = j
	var berry_transforms: Array = []
	berry_transforms.resize(snapshot.berry_index.size())
	var berry_list_index := PackedInt32Array() # posizione nella lista "con le bacche" (uguale in quella "spoglio")
	berry_list_index.resize(snapshot.berry_index.size())
	berry_list_index.fill(-1) # -1: cespuglio senza sagoma, non disegnato
	var berry_shown := PackedByteArray()
	berry_shown.resize(snapshot.berry_index.size())

	for i in range(snapshot.size()):
		var center := snapshot.centers[i]
		var shrub_seed := snapshot.seeds[i]
		var yaw := float(posmod(shrub_seed, 3600)) / 3600.0 * TAU
		var extent := 0.0
		if USE_BUSH_MODELS:
			for b in range(snapshot.blob_starts[i], snapshot.blob_starts[i + 1]):
				var blob_offset := (snapshot.blob_centers[b] - center) * SPREAD_SCALE
				extent = maxf(extent, blob_offset.length() + snapshot.blob_radii[b] * BLOB_SCALE)
			if extent > 0.0:
				var bush_size := extent * 2.0 * BUSH_SCALE
				var bush_transform := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * bush_size),
					Vector3(center.x, _height(base_global, center) - bush_size * 0.72 * BUSH_SINK, center.y))
				if berry_of.has(i):
					var j: int = berry_of[i]
					var with_berries := snapshot.fruit_state[i] == ShrubSnapshot3D.FRUIT_BERRIES
					berry_transforms[j] = bush_transform
					berry_shown[j] = 1 if with_berries else 0
					berry_list_index[j] = bush_transforms[BUSH_FRUIT_BERRIES].size()
					bush_transforms[BUSH_FRUIT_BERRIES].append(bush_transform if with_berries else _hidden(bush_transform))
					bush_transforms[BUSH_FRUIT_BARE].append(_hidden(bush_transform) if with_berries else bush_transform)
					bush_colors[BUSH_FRUIT_BERRIES].append(Color.WHITE)
					bush_colors[BUSH_FRUIT_BARE].append(Color.WHITE)
					continue
				var bush_variant := BUSH_WOOD
				if snapshot.fruit_bearing[i] == 1:
					match snapshot.fruit_state[i]:
						ShrubSnapshot3D.FRUIT_FLOWERS: bush_variant = BUSH_FRUIT
						ShrubSnapshot3D.FRUIT_BERRIES: bush_variant = BUSH_FRUIT_BERRIES
						_: bush_variant = BUSH_FRUIT_BARE
				bush_transforms[bush_variant].append(bush_transform)
				bush_colors[bush_variant].append(_bush_tone(shrub_seed) if bush_variant == BUSH_WOOD else Color.WHITE)
			continue
		for b in range(snapshot.blob_starts[i], snapshot.blob_starts[i + 1]):
			var offset := (snapshot.blob_centers[b] - center) * SPREAD_SCALE
			var radius := snapshot.blob_radii[b] * BLOB_SCALE
			extent = maxf(extent, offset.length() + radius)
			var ground := center + offset
			var height := radius * BLOB_SQUASH
			var y := _height(base_global, ground) + height * (1.0 - BLOB_SINK)
			var variant := posmod(shrub_seed / 13 + b, blob_meshes.size())
			blob_transforms[variant].append(Transform3D(Basis(Vector3.UP, yaw + b).scaled(Vector3(radius, height, radius)),
				Vector3(ground.x, y, ground.y)))
			var color := snapshot.blob_colors[b].lerp(COLOR_TOWARD, COLOR_TOWARD_AMOUNT)
			color.a = 1.0
			blob_colors[variant].append(color)
		if snapshot.fruit_bearing[i] == 1 and extent > 0.0:
			var reach := extent * CANE_SCALE
			var variant := posmod(shrub_seed / 17, leafy_meshes.size())
			leafy_transforms[variant].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(reach, reach * 0.8, reach)),
				Vector3(center.x, _height(base_global, center), center.y)))

	var cut_model_transforms: Array = []
	var dead_model_transforms: Array = []
	if USE_BUSH_MODELS:
		_dead_cut_transforms(snapshot.cut_centers, snapshot.cut_radii, snapshot.cut_seeds, base_global, cut_model_transforms)
		_dead_cut_transforms(snapshot.dead_centers, snapshot.dead_radii, snapshot.dead_seeds, base_global, dead_model_transforms)
	for i in range(0 if USE_BUSH_MODELS else snapshot.cut_centers.size()):
		var center := snapshot.cut_centers[i]
		var cut_seed := snapshot.cut_seeds[i]
		var reach := snapshot.cut_radii[i] * CUT_SCALE
		var yaw := float(posmod(cut_seed, 3600)) / 3600.0 * TAU
		var variant := posmod(cut_seed / 13, bare_meshes.size())
		bare_transforms[variant].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(reach, reach, reach)),
			Vector3(center.x, _height(base_global, center), center.y)))

	var node := Node3D.new()
	node.name = "Shrubs"
	if USE_BUSH_MODELS:
		var bush_slots := _empty_lists(bush_meshes.size())
		node.add_child(MultiMeshGroup3D.build("Bushes", bush_meshes, bush_transforms, null, bush_colors, BUSH_CAST_SHADOWS,
			bush_slots))
		node.set_meta(&"berry_keys", snapshot.berry_keys)
		node.set_meta(&"berry_jitters", snapshot.berry_jitters)
		node.set_meta(&"berry_transforms", berry_transforms)
		node.set_meta(&"berry_list_index", berry_list_index)
		node.set_meta(&"berry_shown", berry_shown)
		node.set_meta(&"berry_slots", bush_slots[BUSH_FRUIT_BERRIES])
		node.set_meta(&"bare_slots", bush_slots[BUSH_FRUIT_BARE])
	node.add_child(MultiMeshGroup3D.build("Blobs", blob_meshes, blob_transforms, material, blob_colors))
	node.add_child(MultiMeshGroup3D.build("Canes", leafy_meshes, leafy_transforms, material))
	node.add_child(MultiMeshGroup3D.build("CutCanes", bare_meshes, bare_transforms, material))
	if USE_BUSH_MODELS:
		node.add_child(MultiMeshGroup3D.build("CutShrubs", [ModelMesh3D.load_mesh(DEAD_CUT_DIR + "shrub_cut.gltf")],
			[cut_model_transforms], null))
		node.add_child(MultiMeshGroup3D.build("DeadShrubs", [ModelMesh3D.load_mesh(DEAD_CUT_DIR + "shrub_dead.gltf")],
			[dead_model_transforms], null, [], BUSH_CAST_SHADOWS))
	return node


# Bacche raccolte o ricresciute (2026-11-21, misura FPS: prima si rifacevano tutti i cespugli della cella, 65-185 ms):
# come il 2D, che lì rifà solo i frutti, si scambiano solo i candidati che hanno cambiato stato, da "con le bacche" a
# "spoglio" o il contrario. `shown` = GameStateReader.shrub_berries_shown sui candidati del nodo (berry_keys).
static func apply_berries(node: Node3D, shown: PackedByteArray) -> void:
	if node == null or not node.has_meta(&"berry_shown"):
		return
	var current: PackedByteArray = node.get_meta(&"berry_shown")
	var list_index: PackedInt32Array = node.get_meta(&"berry_list_index")
	var transforms: Array = node.get_meta(&"berry_transforms")
	var berry_slots: Array = node.get_meta(&"berry_slots")
	var bare_slots: Array = node.get_meta(&"bare_slots")
	for j in range(mini(shown.size(), current.size())):
		if shown[j] == current[j] or list_index[j] < 0:
			continue
		current[j] = shown[j]
		var bush_transform: Transform3D = transforms[j]
		var with_berries := shown[j] == 1
		var k := list_index[j]
		if k < berry_slots.size():
			_set_slot(berry_slots[k], bush_transform if with_berries else _hidden(bush_transform))
		if k < bare_slots.size():
			_set_slot(bare_slots[k], _hidden(bush_transform) if with_berries else bush_transform)
	node.set_meta(&"berry_shown", current)


static func _set_slot(slot: Variant, value: Transform3D) -> void:
	if slot is Array:
		((slot as Array)[0] as MultiMesh).set_instance_transform(int((slot as Array)[1]), value)


# Copia nascosta: stessa posizione (resta nello stesso blocco), scala zero.
static func _hidden(value: Transform3D) -> Transform3D:
	return Transform3D(Basis().scaled(Vector3.ZERO), value.origin)


static func _dead_cut_transforms(centers: PackedVector2Array, radii: PackedFloat32Array, seeds: PackedInt32Array,
		base_global: Vector2, out: Array) -> void:
	for i in range(centers.size()):
		var center := centers[i]
		var width := radii[i] * DEAD_CUT_WIDTH_SCALE
		var yaw := float(posmod(seeds[i], 3600)) / 3600.0 * TAU
		out.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * width),
			Vector3(center.x, _height(base_global, center) - width * 0.02, center.y)))


# Le forme dei cespugli; ai materiali di una copia della forma si accende vertex_color_use_as_albedo, così il colore di
# ogni copia del MultiMesh (la tinta) moltiplica la texture. La forma caricata resta com'è.
static func _get_bush_meshes() -> Array:
	if _bush_meshes.is_empty():
		for mesh in ModelMesh3D.load_meshes(BUSH_DIR, BUSH_MODELS):
			_bush_meshes.append(_tintable(mesh))
	return _bush_meshes


static func _tintable(mesh: Mesh) -> Mesh:
	if mesh == null:
		return null
	var copy := mesh.duplicate() as Mesh
	for s in range(copy.get_surface_count()):
		var surface_material := copy.surface_get_material(s) as BaseMaterial3D
		if surface_material != null:
			surface_material = surface_material.duplicate() as BaseMaterial3D
			surface_material.vertex_color_use_as_albedo = true
			copy.surface_set_material(s, surface_material)
	return copy


# Tinta fissa di una macchia dal suo seme: rossiccia, giallina o un verde tra chiaro e medio.
static func _bush_tone(shrub_seed: int) -> Color:
	var pick := posmod(shrub_seed / 7, 100)
	var shade := float(posmod(shrub_seed / 3, 1000)) / 1000.0
	if pick < BUSH_REDDISH_PERCENT:
		return BUSH_REDDISH_A.lerp(BUSH_REDDISH_B, shade)
	if pick < BUSH_REDDISH_PERCENT + BUSH_YELLOWISH_PERCENT:
		return BUSH_YELLOWISH.lerp(BUSH_GREEN_LIGHT, shade * 0.5)
	return BUSH_GREEN_LIGHT.lerp(BUSH_GREEN_DARK, shade)


static func _height(base_global: Vector2, local: Vector2) -> float:
	return GroundHeight3D.land_height(base_global.x + local.x, base_global.y + local.y)


static func _empty_lists(count: int) -> Array:
	var lists: Array = []
	for i in range(count):
		lists.append([])
	return lists
