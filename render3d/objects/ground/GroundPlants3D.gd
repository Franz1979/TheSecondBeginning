class_name GroundPlants3D
extends RefCounted

# Oggetto 3D: le piantine a terra delle risorse "chiazza d'erba" di UNA macrocella (2026-11-21), una per figurina del 2D
# (GroundPatchSnapshot3D), nello stesso punto: erbe medicinali (violetta), verdure selvatiche (foglie lunghe), granaglie
# (spiga colorata per granaglia, a ciuffetto), lino (steli azzurri), uova (nido). Una risorsa senza modello in MODELS
# non si disegna (si aggiunge una riga quando avrà il suo).
# Forme: Quaternius (SOURCES_PER_GIOCO/blender/scripts/ground_plants.py), larghe 1 con l'origine al piede, foglie a
# texture con ritaglio. Taglia, rotazione e tinta fisse per lotto e risorsa (hash); la tinta moltiplica la texture
# (vertex_color_use_as_albedo su una copia dei materiali, come i cespugli). Senza ombre: sono tante e basse.

const MODEL_DIR := "res://render3d/assets/models/vegetation/ground_plants/"
# risorsa -> forme (una scelta per lotto, fissa). Erbe medicinali sempre col mazzo intero da 6 (utente, 2026-11-21);
# lino selvatico: nostri steli a ciuffo fitto, 5 o 7 (non è un cereale: disegno suo, non la spiga).
const MODELS := {
	"medicinal_herbs": ["medicinal_herbs_plant"],
	"wild_vegetables": ["wild_vegetables_plant"],
	"grains": ["grains_plant"],
	"wild_flax": ["wild_flax_plant_5", "wild_flax_plant_7"],
	# Uova: nido nostro (egg_nest.py) con 2 o 3 uova, piccolo e senza dettagli.
	"eggs": ["egg_nest_2", "egg_nest_3"],
}
# Granaglie (2026-11-21, utente): un solo disegno (Flower_4_Single), la spiga col colore della granaglia del lotto
# (voce "grain" dello snapshot). Il fiore del modello è grigio (materiale FLOWER_MATERIAL): la tinta lo colora.
const GRAIN_TINTS := {
	"wild_wheat": Color(0.95, 0.70, 0.20),
	"wild_oats": Color(0.97, 0.95, 0.78),
	"wild_rye": Color(0.55, 0.66, 0.80),
	"wild_seeds": Color(0.66, 0.38, 0.20),
}
const GRAIN_TINT_DEFAULT := Color(0.88, 0.74, 0.40)
const FLOWER_MATERIAL := "FlowersGray"
# Larghezza in microcelle (2026-11-21, utente: un dettaglio in un angolo della microcella, non la protagonista; il punto
# è già spostato dal centro come la figurina del 2D). Verdure un poco più grandi delle erbe medicinali.
const WIDTH_RANGE := Vector2(0.315, 0.405)
# Larghezza per risorsa, al posto di WIDTH_RANGE.
const WIDTH_BY_RESOURCE := {
	"medicinal_herbs": Vector2(0.22, 0.308),
	"grains": Vector2(0.1152, 0.1584),
	"wild_flax": Vector2(0.15, 0.19),
	"eggs": Vector2(0.24, 0.30),
}
# Tinte per copia: leggere differenze tra una piantina e l'altra.
const TONES := [Color(1.0, 1.0, 1.0), Color(0.85, 0.95, 0.85), Color(1.05, 1.0, 0.85), Color(0.9, 1.0, 0.95)]
const SINK := 0.01
# Distanza dal punto del lotto delle spighe di un lotto con più granaglie (microcelle): un ciuffetto, non sparse.
const CLUSTER_RADIUS := 0.07

static var _meshes: Dictionary = {} # "modello/granaglia" -> Mesh (null se manca)


static func build(snapshot: GroundPatchSnapshot3D, base_global: Vector2) -> Node3D:
	var meshes: Array = []
	var transforms: Array = []
	var colors: Array = []
	var index_of: Dictionary = {}
	for item in snapshot.items:
		var resource: String = item["resource"]
		if not MODELS.has(resource):
			continue
		var lot: Vector2i = item["lot"]
		var pos: Vector2 = item["pos"]
		var h := hash("%d_%d_%s_%s_3d" % [lot.x, lot.y, resource, item.get("grain", "")])
		# Più granaglie nello stesso lotto: spighe in cerchio attorno al punto, angolo di partenza fisso per lotto.
		var cluster: Array = item.get("cluster", [0, 1])
		if int(cluster[1]) > 1:
			var start := float(posmod(hash(lot), 628)) / 100.0
			pos += Vector2.from_angle(start + TAU * float(cluster[0]) / float(cluster[1])) * CLUSTER_RADIUS
		var names: Array = MODELS[resource]
		var model_name: String = names[posmod(h / 13, names.size())]
		var grain: String = item.get("grain", "")
		if resource == "grains" and grain == "":
			grain = "?" # granaglia non detta: tinta di ripiego (GRAIN_TINT_DEFAULT), mai il fiore grigio
		var mesh_key := model_name + "/" + grain
		var mesh := _mesh_for(model_name, grain)
		if mesh == null:
			continue
		if not index_of.has(mesh_key):
			index_of[mesh_key] = meshes.size()
			meshes.append(mesh)
			transforms.append([])
			colors.append([])
		var k: int = index_of[mesh_key]
		var size_range: Vector2 = WIDTH_BY_RESOURCE.get(resource, WIDTH_RANGE)
		var width := lerpf(size_range.x, size_range.y, float(posmod(h, 1000)) / 1000.0)
		var yaw := float(posmod(h / 1000, 628)) / 100.0
		var y := GroundHeight3D.land_height(base_global.x + pos.x, base_global.y + pos.y) - SINK
		(transforms[k] as Array).append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * width), Vector3(pos.x, y, pos.y)))
		(colors[k] as Array).append(TONES[posmod(h / 7, TONES.size())])
	if meshes.is_empty():
		return null
	return MultiMeshGroup3D.build("GroundPlants", meshes, transforms, null, colors, false)


static func _mesh_for(model_name: String, grain: String) -> Mesh:
	var key := model_name + "/" + grain
	if not _meshes.has(key):
		var tint: Color = GRAIN_TINTS.get(grain, GRAIN_TINT_DEFAULT) if grain != "" else Color.WHITE
		_meshes[key] = _tintable(ModelMesh3D.load_mesh(MODEL_DIR + model_name + ".gltf"), tint)
	return _meshes[key]


# flower_tint: colore del materiale FLOWER_MATERIAL (il fiore grigio delle granaglie); bianco = invariato.
static func _tintable(mesh: Mesh, flower_tint: Color = Color.WHITE) -> Mesh:
	if mesh == null:
		return null
	var copy := mesh.duplicate() as Mesh
	for s in range(copy.get_surface_count()):
		var surface_material := copy.surface_get_material(s) as BaseMaterial3D
		if surface_material != null:
			surface_material = surface_material.duplicate() as BaseMaterial3D
			surface_material.vertex_color_use_as_albedo = true
			if surface_material.resource_name == FLOWER_MATERIAL:
				surface_material.albedo_color = flower_tint
			copy.surface_set_material(s, surface_material)
	return copy
