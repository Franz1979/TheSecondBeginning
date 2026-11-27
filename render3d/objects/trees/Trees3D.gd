class_name Trees3D
extends RefCounted

# Oggetto 3D: gli alberi vivi di UNA macrocella, nelle stesse posizioni e con la stessa taglia relativa del 2D
# (TreeSnapshot3D). Latifoglie wood_only: le 5 CommonTree Quaternius (CC0), preparate da
# SOURCES_PER_GIOCO/blender/scripts/common_trees.py, scelte a caso dal seme (2026-11-20). Latifoglie da frutto selvatiche
# (wild_fruit): la quercia (SOURCES_PER_GIOCO/blender/scripts/oak.py, 2026-11-21), con le ghiande in vista con la regola
# del 2D (fruit_shown). Da frutto addomesticabili (domesticable_fruit): l'albero da frutto a ciuffetti
# (SOURCES_PER_GIOCO/blender/scripts/fruit_tree.py, 2026-11-21), con le ciliegie con la stessa regola. Conifere: i 5 pini
# Quaternius (CC0) con le loro texture, preparati da render3d/blender/scripts/pines.py (origine al piede, misure in metri).
# Il verde di ogni chioma varia un poco per albero. Stagioni e frutti: più avanti.
# Le misure del 2D sono pensate per la vista dall'alto; qui si allungano (fattori *_SCALE) per un albero adulto alto
# circa 2 microcelle con la chioma larga circa 1.
# Stagioni delle latifoglie (2026-11-21), come il 2D (TREE_CANOPY_PALETTE_BY_SEASON): verdi in primavera ed estate;
# d'autunno i modelli *_autumn (foglie Leaves_Autumn, oro chiaro, di SOURCES_PER_GIOCO/blender/scripts/seasonal_trees.py)
# tinti albero per albero dal seme (AUTUMN_TINTS, per la quercia OAK_AUTUMN_TINTS più terrose); d'inverno spoglie
# (*_bare: le CommonTree tengono i rametti della corteccia, la quercia i suoi rami).

# PROVA FPS (2026-11-21, reversibile): true = alberi low poly pieni di prima (tronco TreeTrunk3D, chioma a nuvole
# BroadleafCrown3D, coni ConiferCrown3D, colore sui vertici, niente foglie a ritaglio), senza stagioni né frutti; ceppi e
# alberi morti restano da file. false = modelli Quaternius (com'era).
const USE_LOW_POLY := false
const CONIFER_CROWN_SCALE := 1.5
const CONIFER_GREEN_A := Color("2c5232")
const CONIFER_GREEN_B := Color("3e6a3a")

# PROVA FPS (2026-11-22, reversibile): true = i modelli con parti a ritaglio (foglie, corteccia dei pini e delle CommonTree)
# non fanno ombra loro; la fa al loro posto una sagoma piena e invisibile, con le misure prese dal modello: tronco a
# cilindro + chioma a palla (a cono per i pini) grande come il riquadro delle foglie; solo il tronco per le spoglie
# d'inverno. I modelli senza ritaglio (quercia spoglia) tengono la loro ombra. false = ombre dai modelli (com'era).
const SHADOW_PROXY := true
const PROXY_CROWN_FILL := 0.85 # la chioma vera non riempie il suo riquadro: palla e cono un po' più stretti
const PROXY_TRUNK_RADIUS := 0.035 # raggio del tronco, in parte dell'altezza del modello
static var _shadow_proxies: Dictionary = {} # Mesh del modello -> sagoma (null: il modello tiene la sua ombra)
# Ombre degli alberi spegnibili dal livello di qualità (2026-11-27, UserOptions.quality_3d_tree_shadows: spente in Bassa).
# I gruppi che fanno ombra (sagome, modelli con la loro ombra, morti e ceppi) stanno in SHADOW_GROUP: set_shadows li
# cambia tutti al volo, senza ricostruirli; quelli nuovi nascono già col valore del livello attuale.
const SHADOW_GROUP := &"tree_shadows_3d"

const TRUNK_HEIGHT_SCALE := 2.4
const TRUNK_RADIUS_SCALE := 0.45
const CROWN_SCALE := 1.5
const SINK := 0.05

const BROADLEAF_GREEN_A := Color("4d7433")
const BROADLEAF_GREEN_B := Color("6f8f3c")

# Pini: stessa altezza totale delle conifere di prima (tronco corto + chioma conica alta 2,6 volte il suo raggio),
# divisa per l'altezza media dei modelli in metri; ogni variante tiene la sua proporzione (pine_4 è il più alto).
const PINE_DIR := "res://render3d/assets/models/vegetation/pines/"
const PINE_MODELS := ["pine_1", "pine_2", "pine_3", "pine_4", "pine_5"]
const PINE_REFERENCE_HEIGHT := 8.2 # m, media dei 5 modelli
const CONIFER_TRUNK_SHARE := 0.45 * 0.8
const CONIFER_CROWN_HEIGHT := 1.5 * 1.05 * 2.6
# Leggera variazione di tono per albero (moltiplica la texture, se il materiale usa il colore dei vertici).
const PINE_TONE_A := Color(0.88, 0.92, 0.88)
const PINE_TONE_B := Color(1.0, 1.0, 1.0)

# Latifoglie wood_only: come i pini, altezza totale della chioma procedurale (tronco + centro chioma a 0,45 r + mezza
# altezza 0,85 r) divisa per l'altezza media dei modelli; ogni variante tiene la sua proporzione.
const COMMON_TREE_DIR := "res://render3d/assets/models/vegetation/common_trees/"
const COMMON_TREE_MODELS := ["commontree_1", "commontree_2", "commontree_3", "commontree_4", "commontree_5"]
const COMMON_TREE_REFERENCE_HEIGHT := 8.15 # m, media dei 5 modelli
const BROADLEAF_CROWN_TOP := 0.45 + 0.85

# Alberi tagliati e morti (2026-11-20), da file (SOURCES_PER_GIOCO/blender/scripts/dead_cut_plants.py), con la taglia
# salvata dal 2D al taglio o alla morte (un ceppo di albero giovane è più piccolo):
# - ceppo: largo 1 con le radici nel file; largo STUMP_WIDTH_SCALE volte il tronco tagliato del 2D;
# - albero morto in piedi: i 5 DeadTree Quaternius (solo corteccia), scelti dal seme; alto quanto il tronco morto del 2D
#   per DEAD_TREE_HEIGHT_SCALE, diviso l'altezza media dei modelli (ogni variante tiene la sua proporzione).
const DEAD_CUT_DIR := "res://render3d/assets/models/vegetation/dead_cut/"
const STUMP_MODEL := "tree_stump"
const STUMP_WIDTH_SCALE := 1.6
const DEAD_TREE_MODELS := ["deadtree_1", "deadtree_2", "deadtree_3", "deadtree_4", "deadtree_5"]
const DEAD_TREE_REFERENCE_HEIGHT := 12.7 # m, media dei 5 modelli
const DEAD_TREE_HEIGHT_SCALE := TRUNK_HEIGHT_SCALE * 1.3

# Quercia (wild_fruit): altezza come le CommonTree (tronco + chioma procedurale), divisa per OAK_REFERENCE_HEIGHT. Il
# modello è largo quanto alto (9 m), il doppio di una CommonTree: il riferimento più alto del vero la tiene un po' più bassa
# così non è più larga di circa 1,3 volte le latifoglie vicine.
const OAK_DIR := "res://render3d/assets/models/vegetation/fruit_trees/"
const OAK_MODELS := ["oak", "oak_acorns", "oak_autumn", "oak_acorns_autumn", "oak_bare"]
const OAK_AUTUMN := 2
const OAK_BARE := 4
const AUTUMN_TINTS := [Color(1.0, 0.95, 0.55), Color(1.0, 0.62, 0.30), Color(0.75, 0.36, 0.20)]
# Il giallo-bruno tende al giallo-oliva (2026-11-21): su quella tinta le ghiande scure dei rami si vedono bene.
const OAK_AUTUMN_TINTS := [Color(0.88, 0.82, 0.42), Color(0.85, 0.48, 0.26), Color(0.66, 0.40, 0.24)]
const OAK_REFERENCE_HEIGHT := 9.2 * 1.25
# Albero da frutto addomesticabile: stessi indici di variante della quercia (OAK_AUTUMN, OAK_BARE). Alto 9,2 m e largo 5
# come una CommonTree: nessun correttivo sull'altezza.
const FRUIT_TREE_MODELS := ["fruit_tree", "fruit_tree_fruits", "fruit_tree_autumn", "fruit_tree_fruits_autumn", "fruit_tree_bare"]
const FRUIT_TREE_AUTUMN_TINTS := [Color(1.0, 0.55, 0.25), Color(0.95, 0.30, 0.20), Color(1.0, 0.85, 0.45)]
const FRUIT_TREE_REFERENCE_HEIGHT := 9.2

static var _pine_meshes: Array = []
static var _oak_meshes: Array = []
static var _fruit_tree_meshes: Array = []
static var _common_tree_autumn_meshes: Array = []
static var _common_tree_bare_meshes: Array = []
static var _common_tree_meshes: Array = []
static var _dead_tree_meshes: Array = []


# base_global: angolo della cella in microcelle assolute (per l'altezza del terreno). null se non ci sono alberi.
static func build(snapshot: TreeSnapshot3D, base_global: Vector2, material: Material) -> Node3D:
	if snapshot.size() == 0 and snapshot.stump_grounds.is_empty() and snapshot.dead_grounds.is_empty():
		return null
	if USE_LOW_POLY:
		return _build_low_poly(snapshot, base_global, material)
	var pine_meshes := _get_pine_meshes()
	var common_meshes := _get_common_tree_meshes()
	match snapshot.season:
		GameTypes.Season.AUTUMN:
			common_meshes = _get_common_tree_autumn_meshes()
		GameTypes.Season.WINTER:
			common_meshes = _get_common_tree_bare_meshes()
	var oak_meshes := _get_oak_meshes()
	var oak_transforms: Array = [[], [], [], [], []]
	var oak_colors: Array = [[], [], [], [], []]
	var fruit_meshes := _get_fruit_tree_meshes()
	var fruit_transforms: Array = [[], [], [], [], []]
	var fruit_colors: Array = [[], [], [], [], []]
	var common_transforms: Array = []
	var common_colors: Array = []
	for i in range(common_meshes.size()):
		common_transforms.append([])
		common_colors.append([])
	var pine_transforms: Array = []
	var pine_colors: Array = []
	for i in range(pine_meshes.size()):
		pine_transforms.append([])
		pine_colors.append([])

	for i in range(snapshot.size()):
		var ground := snapshot.grounds[i]
		var tree_seed := snapshot.seeds[i]
		var y := GroundHeight3D.land_height(base_global.x + ground.x, base_global.y + ground.y) - SINK
		var foot := Vector3(ground.x, y, ground.y)
		var yaw := float(posmod(tree_seed, 3600)) / 3600.0 * TAU
		var tone := float(posmod(tree_seed / 7, 1000)) / 1000.0
		var trunk_height := snapshot.trunk_heights[i] * TRUNK_HEIGHT_SCALE
		if snapshot.conifer[i] == 1:
			var height := trunk_height * CONIFER_TRUNK_SHARE + snapshot.canopy_radii[i] * CONIFER_CROWN_HEIGHT
			var size := height / PINE_REFERENCE_HEIGHT
			var variant := posmod(tree_seed / 13, pine_meshes.size())
			pine_transforms[variant].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), foot))
			pine_colors[variant].append(PINE_TONE_A.lerp(PINE_TONE_B, tone))
			continue
		var crown_radius := snapshot.canopy_radii[i] * CROWN_SCALE
		if snapshot.fruit_bearing[i] == 0:
			var common_size := (trunk_height + crown_radius * BROADLEAF_CROWN_TOP) / COMMON_TREE_REFERENCE_HEIGHT
			var common_variant := posmod(tree_seed / 13, common_meshes.size())
			common_transforms[common_variant].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * common_size), foot))
			var common_color: Color = PINE_TONE_A.lerp(PINE_TONE_B, tone)
			if snapshot.season == GameTypes.Season.AUTUMN:
				common_color = AUTUMN_TINTS[posmod(tree_seed / 17, AUTUMN_TINTS.size())]
			common_colors[common_variant].append(common_color)
			continue
		# Da frutto: quercia (wild_fruit) o albero da frutto (domesticable_fruit), stesse varianti per stagione e frutti.
		var is_oak := snapshot.domesticable[i] == 0
		var fruit_size := (trunk_height + crown_radius * BROADLEAF_CROWN_TOP) / (OAK_REFERENCE_HEIGHT if is_oak else FRUIT_TREE_REFERENCE_HEIGHT)
		var fruit_variant := 1 if snapshot.fruit_shown[i] == 1 else 0
		var fruit_color: Color = PINE_TONE_A.lerp(PINE_TONE_B, tone)
		if snapshot.season == GameTypes.Season.WINTER:
			fruit_variant = OAK_BARE
		elif snapshot.season == GameTypes.Season.AUTUMN:
			fruit_variant += OAK_AUTUMN
			var tints: Array = OAK_AUTUMN_TINTS if is_oak else FRUIT_TREE_AUTUMN_TINTS
			fruit_color = tints[posmod(tree_seed / 17, tints.size())]
		var fruit_transform := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * fruit_size), foot)
		if is_oak:
			oak_transforms[fruit_variant].append(fruit_transform)
			oak_colors[fruit_variant].append(fruit_color)
		else:
			fruit_transforms[fruit_variant].append(fruit_transform)
			fruit_colors[fruit_variant].append(fruit_color)

	var node := Node3D.new()
	node.name = "Trees"
	# Nessun materiale sostitutivo: i pini usano i loro (corteccia e aghi con texture).
	_add_tree_group(node, "Pines", pine_meshes, pine_transforms, pine_colors)
	_add_tree_group(node, "CommonTrees", common_meshes, common_transforms, common_colors)
	_add_tree_group(node, "Oaks", oak_meshes, oak_transforms, oak_colors)
	_add_tree_group(node, "FruitTrees", fruit_meshes, fruit_transforms, fruit_colors)
	_add_stumps_and_dead(node, snapshot, base_global)
	return node


# Un gruppo di alberi da modello; con SHADOW_PROXY i modelli che hanno una sagoma si disegnano senza ombra e la sagoma,
# nelle stesse posizioni, fa solo l'ombra.
static func _add_tree_group(node: Node3D, group_name: String, meshes: Array, transforms: Array, colors: Array) -> void:
	if not SHADOW_PROXY:
		node.add_child(_shadow_caster(MultiMeshGroup3D.build(group_name, meshes, transforms, null, colors)))
		return
	var proxies: Array = []
	var proxied_transforms: Array = []
	var own_shadow_transforms: Array = []
	for i in range(meshes.size()):
		var proxy := _shadow_proxy(meshes[i])
		proxies.append(proxy)
		proxied_transforms.append(transforms[i] if proxy != null else [])
		own_shadow_transforms.append([] if proxy != null else transforms[i])
	node.add_child(MultiMeshGroup3D.build(group_name, meshes, proxied_transforms, null, colors, false))
	node.add_child(_shadow_caster(MultiMeshGroup3D.build(group_name + "Shadows", proxies, proxied_transforms, null, [], true, [], true)))
	node.add_child(_shadow_caster(MultiMeshGroup3D.build(group_name + "OwnShadow", meshes, own_shadow_transforms, null, colors)))


# Accende o spegne le ombre di tutti gli alberi già costruiti (livello di qualità cambiato, View3D).
static func set_shadows(tree: SceneTree, enabled: bool) -> void:
	for group_node in tree.get_nodes_in_group(SHADOW_GROUP):
		_apply_shadows(group_node, enabled)


# Mette un gruppo appena costruito tra quelli che fanno ombra, già col valore del livello attuale.
static func _shadow_caster(group_node: Node3D) -> Node3D:
	group_node.add_to_group(SHADOW_GROUP)
	_apply_shadows(group_node, UserOptions.quality_3d_tree_shadows())
	return group_node


# Le sagome (solo ombra) si nascondono; gli altri blocchi si disegnano senza fare ombra.
static func _apply_shadows(group_node: Node, enabled: bool) -> void:
	for child in group_node.get_children():
		var instance := child as GeometryInstance3D
		if instance == null:
			continue
		if instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			instance.visible = enabled
		else:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# Sagoma d'ombra di un modello (SHADOW_PROXY), fatta una volta per forma; null se il modello non ha parti a ritaglio.
static func _shadow_proxy(mesh: Mesh) -> Mesh:
	if mesh == null:
		return null
	if _shadow_proxies.has(mesh):
		return _shadow_proxies[mesh]
	var leaves := AABB()
	var has_leaves := false
	var is_pine := false
	var cutout := false
	for s in range(mesh.get_surface_count()):
		var surface_material := mesh.surface_get_material(s) as BaseMaterial3D
		if surface_material == null:
			continue
		if surface_material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			cutout = true
		if surface_material.resource_name.begins_with("Leaves"):
			is_pine = is_pine or surface_material.resource_name == "Leaves_Pine"
			var box := _surface_aabb(mesh, s)
			leaves = leaves.merge(box) if has_leaves else box
			has_leaves = true
	var proxy: ArrayMesh = null
	if cutout:
		proxy = ArrayMesh.new()
		var height := mesh.get_aabb().end.y
		var trunk_top := leaves.position.y if has_leaves else height * 0.7
		var trunk_radius := height * PROXY_TRUNK_RADIUS
		var trunk := CylinderMesh.new()
		trunk.radial_segments = 6
		trunk.rings = 0
		trunk.top_radius = 1.0
		trunk.bottom_radius = 1.0
		trunk.height = 1.0
		_add_proxy_shape(proxy, trunk.get_mesh_arrays(), Vector3(trunk_radius, trunk_top, trunk_radius), Vector3(0.0, trunk_top * 0.5, 0.0))
		if has_leaves:
			var half := leaves.size * 0.5 * PROXY_CROWN_FILL
			if is_pine:
				var cone := CylinderMesh.new()
				cone.radial_segments = 8
				cone.rings = 0
				cone.top_radius = 0.0
				cone.bottom_radius = 1.0
				cone.height = 1.0
				var radius := (half.x + half.z) * 0.5
				_add_proxy_shape(proxy, cone.get_mesh_arrays(), Vector3(radius, leaves.size.y, radius), leaves.get_center())
			else:
				var ball := SphereMesh.new()
				ball.radial_segments = 8
				ball.rings = 4
				ball.radius = 1.0
				ball.height = 2.0
				_add_proxy_shape(proxy, ball.get_mesh_arrays(), half, leaves.get_center())
	_shadow_proxies[mesh] = proxy
	return proxy


static func _surface_aabb(mesh: Mesh, surface: int) -> AABB:
	var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
	if vertices.is_empty():
		return AABB()
	var box := AABB(vertices[0], Vector3.ZERO)
	for vertex in vertices:
		box = box.expand(vertex)
	return box


# Aggiunge alla sagoma una forma di base (centrata nell'origine, larga 2 o alta 1) allungata di `scale` e spostata in `offset`.
static func _add_proxy_shape(proxy: ArrayMesh, arrays: Array, scale: Vector3, offset: Vector3) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for v in range(vertices.size()):
		vertices[v] = vertices[v] * scale + offset
	arrays[Mesh.ARRAY_VERTEX] = vertices
	proxy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


# Alberi low poly di prima (USE_LOW_POLY), ripresi dal commit 2a5b5ca: tronco comune, chioma a nuvole per le latifoglie
# (anche quercia e albero da frutto), a coni per le conifere, verde per albero dal seme. Ceppi e morti come i Quaternius.
static func _build_low_poly(snapshot: TreeSnapshot3D, base_global: Vector2, material: Material) -> Node3D:
	var broadleaf_meshes := BroadleafCrown3D.meshes()
	var conifer_meshes := ConiferCrown3D.meshes()
	var trunk_transforms: Array = []
	var broadleaf_transforms: Array = []
	var broadleaf_colors: Array = []
	var conifer_transforms: Array = []
	var conifer_colors: Array = []
	for i in range(broadleaf_meshes.size()):
		broadleaf_transforms.append([])
		broadleaf_colors.append([])
	for i in range(conifer_meshes.size()):
		conifer_transforms.append([])
		conifer_colors.append([])
	for i in range(snapshot.size()):
		var ground := snapshot.grounds[i]
		var tree_seed := snapshot.seeds[i]
		var y := GroundHeight3D.land_height(base_global.x + ground.x, base_global.y + ground.y) - SINK
		var foot := Vector3(ground.x, y, ground.y)
		var yaw := float(posmod(tree_seed, 3600)) / 3600.0 * TAU
		var tone := float(posmod(tree_seed / 7, 1000)) / 1000.0
		var trunk_height := snapshot.trunk_heights[i] * TRUNK_HEIGHT_SCALE
		var trunk_radius := snapshot.trunk_widths[i] * TRUNK_RADIUS_SCALE * 0.5
		var crown_radius := snapshot.canopy_radii[i] * CROWN_SCALE
		var is_conifer := snapshot.conifer[i] == 1
		if is_conifer:
			# Il tronco si vede appena sotto i rami bassi.
			trunk_height *= 0.45
		trunk_transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(trunk_radius, trunk_height, trunk_radius)), foot))
		if is_conifer:
			var crown_scale := snapshot.canopy_radii[i] * CONIFER_CROWN_SCALE
			var variant := posmod(tree_seed / 13, conifer_meshes.size())
			conifer_transforms[variant].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(crown_scale, crown_scale * 1.05, crown_scale)),
				foot + Vector3(0.0, trunk_height * 0.8, 0.0)))
			conifer_colors[variant].append(CONIFER_GREEN_A.lerp(CONIFER_GREEN_B, tone))
		else:
			var variant := posmod(tree_seed / 13, broadleaf_meshes.size())
			broadleaf_transforms[variant].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(crown_radius, crown_radius * 0.85, crown_radius)),
				foot + Vector3(0.0, trunk_height + crown_radius * 0.45, 0.0)))
			broadleaf_colors[variant].append(BROADLEAF_GREEN_A.lerp(BROADLEAF_GREEN_B, tone))
	var node := Node3D.new()
	node.name = "Trees"
	node.add_child(MultiMeshGroup3D.build("Trunks", [TreeTrunk3D.mesh()], [trunk_transforms], material))
	node.add_child(MultiMeshGroup3D.build("BroadleafCrowns", broadleaf_meshes, broadleaf_transforms, material, broadleaf_colors))
	node.add_child(MultiMeshGroup3D.build("ConiferCrowns", conifer_meshes, conifer_transforms, material, conifer_colors))
	_add_stumps_and_dead(node, snapshot, base_global)
	return node


static func _add_stumps_and_dead(node: Node3D, snapshot: TreeSnapshot3D, base_global: Vector2) -> void:
	var stump_transforms: Array = []
	for i in range(snapshot.stump_grounds.size()):
		var ground := snapshot.stump_grounds[i]
		var width := snapshot.stump_widths[i] * STUMP_WIDTH_SCALE
		var yaw := float(posmod(snapshot.stump_seeds[i], 3600)) / 3600.0 * TAU
		var y := GroundHeight3D.land_height(base_global.x + ground.x, base_global.y + ground.y) - SINK * width
		stump_transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * width), Vector3(ground.x, y, ground.y)))
	var dead_meshes := _get_dead_tree_meshes()
	var dead_transforms: Array = []
	for m in range(dead_meshes.size()):
		dead_transforms.append([])
	for i in range(snapshot.dead_grounds.size()):
		var ground := snapshot.dead_grounds[i]
		var seed_value := snapshot.dead_seeds[i]
		var size := snapshot.dead_heights[i] * DEAD_TREE_HEIGHT_SCALE / DEAD_TREE_REFERENCE_HEIGHT
		var yaw := float(posmod(seed_value, 3600)) / 3600.0 * TAU
		var y := GroundHeight3D.land_height(base_global.x + ground.x, base_global.y + ground.y) - SINK
		dead_transforms[posmod(seed_value / 13, dead_meshes.size())].append(
			Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), Vector3(ground.x, y, ground.y)))
	node.add_child(_shadow_caster(MultiMeshGroup3D.build("Stumps", [ModelMesh3D.load_mesh(DEAD_CUT_DIR + STUMP_MODEL + ".gltf")],
		[stump_transforms], null)))
	node.add_child(_shadow_caster(MultiMeshGroup3D.build("DeadTrees", dead_meshes, dead_transforms, null)))


static func _get_dead_tree_meshes() -> Array:
	if _dead_tree_meshes.is_empty():
		_dead_tree_meshes = ModelMesh3D.load_meshes(DEAD_CUT_DIR, DEAD_TREE_MODELS)
	return _dead_tree_meshes


static func _get_pine_meshes() -> Array:
	if _pine_meshes.is_empty():
		_pine_meshes = ModelMesh3D.load_meshes(PINE_DIR, PINE_MODELS)
	return _pine_meshes


static func _get_oak_meshes() -> Array:
	if _oak_meshes.is_empty():
		_oak_meshes = ModelMesh3D.load_meshes(OAK_DIR, OAK_MODELS)
		_oak_meshes[OAK_AUTUMN] = _tintable_leaves(_oak_meshes[OAK_AUTUMN])
		_oak_meshes[OAK_AUTUMN + 1] = _tintable_leaves(_oak_meshes[OAK_AUTUMN + 1])
	return _oak_meshes


static func _get_fruit_tree_meshes() -> Array:
	if _fruit_tree_meshes.is_empty():
		_fruit_tree_meshes = ModelMesh3D.load_meshes(OAK_DIR, FRUIT_TREE_MODELS)
		_fruit_tree_meshes[OAK_AUTUMN] = _tintable_leaves(_fruit_tree_meshes[OAK_AUTUMN])
		_fruit_tree_meshes[OAK_AUTUMN + 1] = _tintable_leaves(_fruit_tree_meshes[OAK_AUTUMN + 1])
	return _fruit_tree_meshes


static func _get_common_tree_autumn_meshes() -> Array:
	if _common_tree_autumn_meshes.is_empty():
		for model_name in COMMON_TREE_MODELS:
			_common_tree_autumn_meshes.append(_tintable_leaves(ModelMesh3D.load_mesh(COMMON_TREE_DIR + model_name + "_autumn.gltf")))
	return _common_tree_autumn_meshes


static func _get_common_tree_bare_meshes() -> Array:
	if _common_tree_bare_meshes.is_empty():
		for model_name in COMMON_TREE_MODELS:
			_common_tree_bare_meshes.append(ModelMesh3D.load_mesh(COMMON_TREE_DIR + model_name + "_bare.gltf"))
	return _common_tree_bare_meshes


# Copia della forma in cui le foglie (materiali "Leaves...") prendono il colore dell'istanza (vertex_color_use_as_albedo):
# la tinta d'autunno di ogni albero. La corteccia resta com'è.
static func _tintable_leaves(mesh: Mesh) -> Mesh:
	if mesh == null:
		return null
	var copy := mesh.duplicate() as Mesh
	for s in range(copy.get_surface_count()):
		var surface_material := copy.surface_get_material(s) as BaseMaterial3D
		if surface_material != null and surface_material.resource_name.begins_with("Leaves"):
			surface_material = surface_material.duplicate() as BaseMaterial3D
			surface_material.vertex_color_use_as_albedo = true
			copy.surface_set_material(s, surface_material)
	return copy


static func _get_common_tree_meshes() -> Array:
	if _common_tree_meshes.is_empty():
		_common_tree_meshes = ModelMesh3D.load_meshes(COMMON_TREE_DIR, COMMON_TREE_MODELS)
	return _common_tree_meshes
