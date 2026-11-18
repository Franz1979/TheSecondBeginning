class_name TerrainMesh3D
extends RefCounted

# Oggetto 3D: il terreno di UNA macrocella. Un quadrato per microcella, a facce piatte, con lievi ondulazioni
# (GroundHeight3D) e il colore del 2D tradotto in tinta 3D (Palette3D), variato a chiazze larghe (più giallo / più
# scuro) come nel bozzetto, mai casella per casella. Sotto l'acqua il terreno scende a fondale; dove c'è argilla scende
# a conca e sfuma verso il rossiccio angolo per angolo (ClayPatch3D.corner_weights), così la pozza ha il contorno tondo.

# Chiazze: verso il giallo-paglia dove il rumore è alto, verso lo scuro dove è basso.
const PATCH_FREQUENCY := 0.045
const PATCH_WARM := Color("b7b45a")
const PATCH_WARM_AMOUNT := 0.22
const PATCH_DARK_AMOUNT := 0.12
const HEIGHT_TINT := 0.05

static var _patch_noise: FastNoiseLite


# water_cells: Vector2i (microcella) -> tipo d'acqua (vedi Cell3D.WATER_*). clay_weights: quantità d'argilla per angolo
# (ClayPatch3D.corner_weights, vuoto = niente argilla). Ritorna il nodo già pronto, in coordinate locali della
# macrocella (0..100 su x e z).
static func build(source: Cell3DSource, water_cells: Dictionary, clay_weights: PackedFloat32Array, material: Material) -> MeshInstance3D:
	var size := World.WIDTH
	var base_x := source.coords.x * World.WIDTH
	var base_y := source.coords.y * World.HEIGHT

	# Altezze degli angoli (size+1)x(size+1): un angolo che tocca l'acqua scende al fondale, così la riva fa da scarpata.
	var heights := PackedFloat32Array()
	heights.resize((size + 1) * (size + 1))
	for j in range(size + 1):
		for i in range(size + 1):
			var h := GroundHeight3D.land_height(base_x + i, base_y + j)
			if _corner_touches(i, j, water_cells):
				h = GroundHeight3D.WATER_BED
			elif not clay_weights.is_empty():
				h -= ClayPatch3D.depth_for(clay_weights[j * (size + 1) + i])
			heights[j * (size + 1) + i] = h

	var use_land_color := source.water_type == GameTypes.WaterType.RIVER
	var builder := FlatMeshBuilder.new()
	for j in range(size):
		for i in range(size):
			var pos := Vector2i(i, j)
			var h00 := heights[j * (size + 1) + i]
			var h10 := heights[j * (size + 1) + i + 1]
			var h11 := heights[(j + 1) * (size + 1) + i + 1]
			var h01 := heights[(j + 1) * (size + 1) + i]
			var color: Color
			if water_cells.has(pos):
				color = Palette3D.SEABED
			else:
				var micro_cell: MacroCellData = source.world.get_cell_at(i, j)
				var color_2d: Color = TerrainColors.PLAIN
				if micro_cell != null:
					color_2d = TerrainColors.get_land_color(micro_cell) if use_land_color else TerrainColors.get_cell_color(micro_cell)
				color = _vary(Palette3D.terrain_color(color_2d), base_x + i + 0.5, base_y + j + 0.5, (h00 + h11) * 0.5)
			var a := Vector3(i, h00, j)
			var b := Vector3(i + 1, h10, j)
			var c := Vector3(i + 1, h11, j + 1)
			var d := Vector3(i, h01, j + 1)
			if not clay_weights.is_empty() and not water_cells.has(pos) and _touches_clay(clay_weights, i, j, size):
				# Bordo e fondo della pozza: colore per angolo, sfumato dal prato all'argilla.
				var ca := ClayPatch3D.blend_color(color, Vector2i(i, j), clay_weights[j * (size + 1) + i])
				var cb := ClayPatch3D.blend_color(color, Vector2i(i + 1, j), clay_weights[j * (size + 1) + i + 1])
				var cc := ClayPatch3D.blend_color(color, Vector2i(i + 1, j + 1), clay_weights[(j + 1) * (size + 1) + i + 1])
				var cd := ClayPatch3D.blend_color(color, Vector2i(i, j + 1), clay_weights[(j + 1) * (size + 1) + i])
				builder.add_triangle_colors(a, b, c, ca, cb, cc)
				builder.add_triangle_colors(a, c, d, ca, cc, cd)
			else:
				builder.add_quad(a, b, c, d, color)

	var instance := MeshInstance3D.new()
	instance.name = "Terrain"
	instance.mesh = builder.build()
	instance.material_override = material
	return instance


static func _touches_clay(weights: PackedFloat32Array, i: int, j: int, size: int) -> bool:
	return weights[j * (size + 1) + i] > 0.0 or weights[j * (size + 1) + i + 1] > 0.0 \
		or weights[(j + 1) * (size + 1) + i + 1] > 0.0 or weights[(j + 1) * (size + 1) + i] > 0.0


# true se uno dei quattro quadrati attorno all'angolo (i, j) è in `cells` (Vector2i -> qualunque valore).
static func _corner_touches(i: int, j: int, cells: Dictionary) -> bool:
	if cells.is_empty():
		return false
	return cells.has(Vector2i(i - 1, j - 1)) or cells.has(Vector2i(i, j - 1)) \
		or cells.has(Vector2i(i - 1, j)) or cells.has(Vector2i(i, j))


# Tinta a chiazze larghe e continue (dipende solo dalla posizione assoluta: combacia tra macrocelle) e più chiaro sui dossi.
static func _vary(color: Color, gx: float, gy: float, height: float) -> Color:
	if _patch_noise == null:
		_patch_noise = FastNoiseLite.new()
		_patch_noise.seed = 4242
		_patch_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_patch_noise.frequency = PATCH_FREQUENCY
		_patch_noise.fractal_octaves = 3
	var n := _patch_noise.get_noise_2d(gx, gy)
	var varied := color.lerp(PATCH_WARM, n * PATCH_WARM_AMOUNT) if n > 0.0 else color.darkened(-n * PATCH_DARK_AMOUNT)
	var bump := height / GroundHeight3D.AMPLITUDE * HEIGHT_TINT
	return varied.lightened(bump) if bump > 0.0 else varied.darkened(-bump)
