class_name Piles3D
extends RefCounted

# Oggetto 3D: i mucchietti delle scorte di UNA cella (StoragePilesSnapshot3D). Oggi ogni risorsa è un "adesivo": la sua
# icona del 2D appoggiata a terra (PileStickers3D, 2026-11-21, richiesta utente: le 3 forme neutre di pile.py erano
# troppo generiche). Quando una risorsa avrà il suo modello vero, avrà qui il suo mucchio e le altre restano adesivo.
# Un MultiMesh per risorsa presente nella cella.

# Lato dell'icona del magazzino nel 2D, in microcelle (i mucchi a terra lo scalano con StoragePilesSnapshot3D.scales).
const ICON_SIDE := MicroCellRenderer.DEPOSIT_SITE_STORAGE_SQUARE_SIDE / float(MicroCellRenderer.CELL_SIZE)
# Appena sopra il terreno; ogni adesivo della cella un filo più su del precedente, così due adesivi sovrapposti (mucchi
# a terra) non sfarfallano.
const LIFT := 0.01
const LIFT_STEP := 0.002

# Risorse che hanno già il loro modello al posto dell'adesivo (2026-11-21, richiesta utente: si aggiungono man mano, una
# riga per risorsa; i mucchi a terra scalano tutto come gli adesivi). Due tipi:
# - "length": un oggetto solo, disteso in diagonale nella casella (punta nell'origine, lungo +X, lungo 1, colori sui
#   vertici: SOURCES_PER_GIOCO/blender/scripts/weapons_ground.py), lungo "length" microcelle (casella 0,22 di lato,
#   diagonale 0,31): le lance stanno nella diagonale, il coltello un po' più grande del vero (0,1) per leggerlo.
# - "scale": un mucchio unico del magazzino (SOURCES_PER_GIOCO/blender/scripts/storage_piles.py, in metri: scala 0,1),
#   centrato nella casella e girato a caso dal seme; largo circa 1,2-1,5 m in una casella di 2,2.
const MODEL_DIR := "res://render3d/assets/models/props/"
const MODELS := {
	"wooden_spear": {"models": ["weapon_ground_wooden_spear.gltf"], "length": 0.30},
	"stone_spear": {"models": ["weapon_ground_stone_spear.gltf"], "length": 0.30},
	"stone_knife": {"models": ["weapon_ground_stone_knife.gltf"], "length": 0.14},
	"acorn": {"models": ["storage_acorn.glb"], "scale": 0.1},
	"fruit": {"models": ["storage_fruit.glb"], "scale": 0.1},
	"berry": {"models": ["storage_berry.glb"], "scale": 0.1},
	# Materie prime (SOURCES_PER_GIOCO/blender/scripts/raw_material_piles.py, 2026-11-23): 60-520 triangoli l'una.
	"wood": {"models": ["storage_wood.glb"], "scale": 0.1},
	"stick": {"models": ["storage_stick.glb"], "scale": 0.1},
	"pebble": {"models": ["storage_pebble.glb"], "scale": 0.1},
	"stone": {"models": ["storage_stone.glb"], "scale": 0.1},
	"clay": {"models": ["storage_clay.glb"], "scale": 0.1},
	"bone": {"models": ["storage_bone.glb"], "scale": 0.1},
	"hide": {"models": ["storage_hide.glb"], "scale": 0.1},
	"meat": {"models": ["storage_meat.glb"], "scale": 0.1},
	"fish_meat": {"models": ["storage_fish_meat.glb"], "scale": 0.1},
	"sinew": {"models": ["storage_sinew.glb"], "scale": 0.1},
	"flax_fiber": {"models": ["storage_flax_fiber.glb"], "scale": 0.1},
	"plant_fiber": {"models": ["storage_plant_fiber.glb"], "scale": 0.1},
	"straw": {"models": ["storage_straw.glb"], "scale": 0.1},
	"hay": {"models": ["storage_hay.glb"], "scale": 0.1},
	"medicinal_herbs": {"models": ["storage_medicinal_herbs.glb"], "scale": 0.1},
	# Semilavorati (SOURCES_PER_GIOCO/blender/scripts/semi_finished_piles.py, 2026-11-23): 170-430 triangoli l'uno.
	"firewood": {"models": ["storage_firewood.glb"], "scale": 0.1},
	"fiber_rope": {"models": ["storage_fiber_rope.glb"], "scale": 0.1},
	"flax_rope": {"models": ["storage_flax_rope.glb"], "scale": 0.1},
	"flax_thread": {"models": ["storage_flax_thread.glb"], "scale": 0.1},
	"dried_hide": {"models": ["storage_dried_hide.glb"], "scale": 0.1},
	"smoked_hide": {"models": ["storage_smoked_hide.glb"], "scale": 0.1},
	# Cibo (SOURCES_PER_GIOCO/blender/scripts/food_piles.py, 2026-11-23): 100-470 triangoli l'uno.
	"cooked_meat": {"models": ["storage_cooked_meat.glb"], "scale": 0.1},
	"dried_meat": {"models": ["storage_dried_meat.glb"], "scale": 0.1},
	"smoked_meat": {"models": ["storage_smoked_meat.glb"], "scale": 0.1},
	"cooked_fish": {"models": ["storage_cooked_fish.glb"], "scale": 0.1},
	"dried_fish": {"models": ["storage_dried_fish.glb"], "scale": 0.1},
	"smoked_fish": {"models": ["storage_smoked_fish.glb"], "scale": 0.1},
	"barley_pita": {"models": ["storage_barley_pita.glb"], "scale": 0.1},
	"oat_cake": {"models": ["storage_oat_cake.glb"], "scale": 0.1},
	"rye_bread": {"models": ["storage_rye_bread.glb"], "scale": 0.1},
	"wheat_bread": {"models": ["storage_wheat_bread.glb"], "scale": 0.1},
	"mushroom": {"models": ["storage_mushroom.glb"], "scale": 0.1},
	"eggs": {"models": ["storage_eggs.glb"], "scale": 0.1},
	"wild_vegetables": {"models": ["storage_wild_vegetables.glb"], "scale": 0.1},
	# Medicinali e vestiario (SOURCES_PER_GIOCO/blender/scripts/apparel_medicinal_piles.py, 2026-11-23): 100-450 triangoli.
	"herbal_infusion": {"models": ["storage_herbal_infusion.glb"], "scale": 0.1},
	"herbal_ointment": {"models": ["storage_herbal_ointment.glb"], "scale": 0.1},
	"splint": {"models": ["storage_splint.glb"], "scale": 0.1},
	"fur_dress": {"models": ["storage_fur_dress.glb"], "scale": 0.1},
	"fur_cap": {"models": ["storage_fur_cap.glb"], "scale": 0.1},
	"worked_hide_dress": {"models": ["storage_worked_hide_dress.glb"], "scale": 0.1},
	"worked_hide_cap": {"models": ["storage_worked_hide_cap.glb"], "scale": 0.1},
	"hide_footwear": {"models": ["storage_hide_footwear.glb"], "scale": 0.1},
}
# Distesi in diagonale nella casella, tutti nello stesso verso: il magazzino resta ordinato.
const MODEL_YAW := PI * 0.25
# Attrezzi distesi: tre copie per casella, un mucchietto (2026-11-23, richiesta utente: uno solo si vedeva poco). Per
# copia: spostamento di fianco e lungo l'attrezzo (frazioni della sua lunghezza), rotazione in più, alzata (frazioni della
# lunghezza: la terza sta sopra le prime due, appena di traverso). Triangoli ×3 (lancia ~170, coltello ~85).
const LENGTH_COPIES := [
	[-0.07, 0.03, -0.06, 0.0],
	[0.07, -0.04, 0.05, 0.0],
	[0.0, 0.0, 0.2, 0.016],
]

# Carcasse (SOURCES_PER_GIOCO/blender/scripts/carcass.py): lunghe 1, pelo chiaro tinto dal colore della specie.
const CARCASS_DIR := "res://render3d/assets/models/animals/carcass/"
const CARCASS_MODELS := ["carcass_quadruped", "carcass_bird"]

static var _carcass_meshes: Array = []
static var _model_meshes: Dictionary = {}


# base_global: angolo della cella in microcelle assolute (altezza del terreno). null se non ci sono mucchietti.
static func build(snapshot: StoragePilesSnapshot3D, base_global: Vector2, material: Material) -> Node3D:
	if snapshot.is_empty():
		return null
	var root := Node3D.new()
	root.name = "Piles"
	if snapshot.size() > 0:
		root.add_child(_build_piles(snapshot, base_global, material))
	if not snapshot.carcass_positions.is_empty():
		root.add_child(_build_carcasses(snapshot, base_global))
	return root


# Adesivi (materiale proprio di ogni risorsa) e modelli (colore dei vertici: `material`) in due gruppi di MultiMesh.
static func _build_piles(snapshot: StoragePilesSnapshot3D, base_global: Vector2, material: Material) -> Node3D:
	var stickers := _Group.new()
	var models := _Group.new()
	var ratio := PileStickers3D.slot_to_icon_ratio()
	for i in range(snapshot.size()):
		var name := snapshot.resource_names[i]
		var position := snapshot.positions[i]
		var y := GroundHeight3D.land_height(base_global.x + position.x, base_global.y + position.y) + LIFT + LIFT_STEP * float(i % 8)
		var center := Vector3(position.x, y, position.y)
		if MODELS.has(name):
			var entry: Dictionary = MODELS[name]
			var variants := _model_meshes_for(name)
			if entry.has("length") and variants[0] != null:
				var length: float = float(entry["length"]) * snapshot.scales[i]
				for copy in LENGTH_COPIES:
					var basis := Basis(Vector3.UP, MODEL_YAW + float(copy[2])).scaled(Vector3.ONE * length)
					var along := basis.x.normalized()
					var side := Vector3(-along.z, 0.0, along.x)
					var offset := (side * float(copy[0]) + along * float(copy[1]) + Vector3.UP * float(copy[3])) * length
					# Punta nell'origine: si sposta indietro di mezza lunghezza perché l'oggetto stia centrato nella casella.
					models.add(name, variants[0], Transform3D(basis, center + offset - basis.x * 0.5))
				continue
			if entry.has("scale") and variants[0] != null:
				var yaw := float(posmod(snapshot.seeds[i], 3600)) / 3600.0 * TAU
				var pile_basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * float(entry["scale"]) * snapshot.scales[i])
				models.add(name, variants[0], Transform3D(pile_basis, Vector3(position.x, center.y - LIFT, position.y)))
				continue
		var mesh := PileStickers3D.mesh_for(name)
		if mesh == null:
			continue
		# Dritto come nel 2D del magazzino (alto dell'icona verso -Z, il nord): si legge con la camera di partenza.
		var sticker_basis := Basis.IDENTITY.scaled(Vector3.ONE * ICON_SIDE * snapshot.scales[i] * ratio)
		stickers.add(name, mesh, Transform3D(sticker_basis, center))
	var root := Node3D.new()
	root.name = "Stockpiles"
	if not stickers.meshes.is_empty():
		root.add_child(MultiMeshGroup3D.build("Stickers", stickers.meshes, stickers.transforms, null, [], false))
	if not models.meshes.is_empty():
		root.add_child(MultiMeshGroup3D.build("Models", models.meshes, models.transforms, material, [], false))
	return root


# Modelli della risorsa (MODELS), uno per variante, caricati una volta; null al posto di un file che manca.
static func _model_meshes_for(resource_name: String) -> Array:
	if not _model_meshes.has(resource_name):
		var meshes: Array = []
		for model_name in (MODELS[resource_name] as Dictionary)["models"]:
			meshes.append(ModelMesh3D.load_mesh(MODEL_DIR + String(model_name)))
		_model_meshes[resource_name] = meshes
	return _model_meshes[resource_name]


# Forme di un gruppo di MultiMesh e le copie di ciascuna, per nome di risorsa.
class _Group:
	var meshes: Array = []
	var transforms: Array = []
	var _index_by_name: Dictionary = {}

	func add(resource_name: String, mesh: Mesh, transform: Transform3D) -> void:
		if not _index_by_name.has(resource_name):
			_index_by_name[resource_name] = meshes.size()
			meshes.append(mesh)
			transforms.append([])
		(transforms[_index_by_name[resource_name]] as Array).append(transform)


# Carcasse: modello lungo 1 (testa verso +X) scalato alla lunghezza del 2D e girato come il 2D attorno alla verticale.
static func _build_carcasses(snapshot: StoragePilesSnapshot3D, base_global: Vector2) -> Node3D:
	var transforms: Array = [[], []]
	var colors: Array = [[], []]
	for i in range(snapshot.carcass_positions.size()):
		var position := snapshot.carcass_positions[i]
		var kind := int(snapshot.carcass_bird[i])
		var y := GroundHeight3D.land_height(base_global.x + position.x, base_global.y + position.y)
		var basis := Basis(Vector3.UP, -snapshot.carcass_rotations[i]).scaled(Vector3.ONE * snapshot.carcass_lengths[i])
		transforms[kind].append(Transform3D(basis, Vector3(position.x, y, position.y)))
		colors[kind].append(snapshot.carcass_colors[i])
	return MultiMeshGroup3D.build("Carcasses", _get_carcass_meshes(), transforms, null, colors)


# Forme delle carcasse con i materiali del pelo che prendono il colore dell'istanza (vertex_color_use_as_albedo); sangue,
# zoccoli e becco restano del loro colore.
static func _get_carcass_meshes() -> Array:
	if _carcass_meshes.is_empty():
		for model_name in CARCASS_MODELS:
			var mesh := ModelMesh3D.load_mesh(CARCASS_DIR + model_name + ".gltf")
			if mesh != null:
				mesh = mesh.duplicate() as Mesh
				for s in range(mesh.get_surface_count()):
					var surface_material := mesh.surface_get_material(s) as BaseMaterial3D
					if surface_material != null and (surface_material.resource_name.contains("Fur") or surface_material.resource_name.contains("Belly")):
						surface_material = surface_material.duplicate() as BaseMaterial3D
						surface_material.vertex_color_use_as_albedo = true
						mesh.surface_set_material(s, surface_material)
			_carcass_meshes.append(mesh)
	return _carcass_meshes
