class_name TerrainMesh3D
extends RefCounted

# Oggetto 3D: il terreno di UNA macrocella, a texture (TerrainMaterial3D / terrain.gdshader). Una griglia di 101x101
# angoli con vertici condivisi e normali morbide, con lievi ondulazioni (GroundHeight3D). Ogni angolo porta:
#   - la tinta del bioma (colore del 2D tradotto da Palette3D, variato a chiazze larghe), media delle caselle attorno;
#   - UV = posizione assoluta in microcelle (le texture combaciano tra macrocelle);
#   - UV2 = (quota di terra, quota d'argilla): terra per deserto/spiaggia/roccia/fondale, argilla da ClayPatch3D.
# Sotto l'acqua il terreno scende a fondale; dove c'è argilla scende a conca. Il bordo frastagliato della pozza lo
# disegna lo shader.

# Chiazze: verso il giallo-paglia dove il rumore è alto, verso lo scuro dove è basso.
const PATCH_FREQUENCY := 0.045
const PATCH_WARM := Color("b7b45a")
const PATCH_WARM_AMOUNT := 0.22
const PATCH_DARK_AMOUNT := 0.12
const HEIGHT_TINT := 0.05

static var _patch_noise: FastNoiseLite


# water_cells: Vector2i (microcella) -> tipo d'acqua (vedi Cell3D.WATER_*). clay_weights: quantità d'argilla per angolo
# (ClayPatch3D.corner_weights, vuoto = niente argilla). stream_mask: maschera del ruscello (StreamMask3D, null = niente
# ruscello), per incassarne il letto. Ritorna il nodo già pronto, in coordinate locali della macrocella (0..100 su x e z).
static func build(source: Cell3DSource, water_cells: Dictionary, clay_weights: PackedFloat32Array, stream_mask: Image,
		material: Material) -> MeshInstance3D:
	var size := World.WIDTH
	var stride := size + 1
	var base_x := source.coords.x * World.WIDTH
	var base_y := source.coords.y * World.HEIGHT

	# Altezze degli angoli: un angolo che tocca l'acqua scende al fondale, così la riva fa da scarpata.
	var heights := PackedFloat32Array()
	heights.resize(stride * stride)
	for j in range(stride):
		for i in range(stride):
			var h := GroundHeight3D.land_height(base_x + i, base_y + j)
			if _corner_touches(i, j, water_cells):
				h = GroundHeight3D.WATER_BED
			else:
				if not clay_weights.is_empty():
					h -= ClayPatch3D.depth_for(clay_weights[j * stride + i])
				if stream_mask != null:
					h -= StreamMask3D.bed_depth_at(stream_mask, i, j)
			heights[j * stride + i] = h

	# Tinta e quota di terra per casella, poi mediate sugli angoli.
	var use_land_color := source.water_type == GameTypes.WaterType.RIVER
	var cell_colors := PackedColorArray()
	var cell_dirt := PackedFloat32Array()
	cell_colors.resize(size * size)
	cell_dirt.resize(size * size)
	for j in range(size):
		for i in range(size):
			var pos := Vector2i(i, j)
			var mid_height := (heights[j * stride + i] + heights[(j + 1) * stride + i + 1]) * 0.5
			if water_cells.has(pos):
				cell_colors[j * size + i] = Palette3D.SEABED
				cell_dirt[j * size + i] = 1.0
				continue
			var micro_cell: MacroCellData = source.world.get_cell_at(i, j) if source.world != null else null
			var color_2d: Color = TerrainColors.PLAIN
			if micro_cell != null:
				color_2d = TerrainColors.get_land_color(micro_cell) if use_land_color else TerrainColors.get_cell_color(micro_cell)
			cell_colors[j * size + i] = _vary(Palette3D.terrain_color(color_2d), base_x + i + 0.5, base_y + j + 0.5, mid_height)
			cell_dirt[j * size + i] = Palette3D.dirt_amount(color_2d)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uvs2 := PackedVector2Array()
	vertices.resize(stride * stride)
	normals.resize(stride * stride)
	colors.resize(stride * stride)
	uvs.resize(stride * stride)
	uvs2.resize(stride * stride)
	for j in range(stride):
		for i in range(stride):
			var k := j * stride + i
			vertices[k] = Vector3(i, heights[k], j)
			# Normale morbida dalle altezze dei vicini.
			var hl := heights[j * stride + maxi(i - 1, 0)]
			var hr := heights[j * stride + mini(i + 1, size)]
			var hu := heights[maxi(j - 1, 0) * stride + i]
			var hd := heights[mini(j + 1, size) * stride + i]
			var dx := float(mini(i + 1, size) - maxi(i - 1, 0))
			var dz := float(mini(j + 1, size) - maxi(j - 1, 0))
			normals[k] = Vector3(-(hr - hl) / dx, 1.0, -(hd - hu) / dz).normalized()
			# Media delle caselle attorno all'angolo.
			var color_sum := Color(0, 0, 0, 0)
			var dirt_sum := 0.0
			var n := 0
			for cy in [j - 1, j]:
				for cx in [i - 1, i]:
					if cx < 0 or cy < 0 or cx >= size or cy >= size:
						continue
					color_sum += cell_colors[cy * size + cx]
					dirt_sum += cell_dirt[cy * size + cx]
					n += 1
			colors[k] = Color(color_sum.r / n, color_sum.g / n, color_sum.b / n, 1.0)
			uvs[k] = Vector2(base_x + i, base_y + j)
			uvs2[k] = Vector2(dirt_sum / n, clay_weights[k] if not clay_weights.is_empty() else 0.0)

	# Due triangoli per casella, in senso orario visti dall'alto (a, b, c) e (a, c, d).
	var indices := PackedInt32Array()
	indices.resize(size * size * 6)
	var t := 0
	for j in range(size):
		for i in range(size):
			var a := j * stride + i
			var b := a + 1
			var c := a + stride + 1
			var d := a + stride
			indices[t] = a
			indices[t + 1] = b
			indices[t + 2] = c
			indices[t + 3] = a
			indices[t + 4] = c
			indices[t + 5] = d
			t += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uvs2
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var instance := MeshInstance3D.new()
	instance.name = "Terrain"
	instance.mesh = mesh
	instance.material_override = material
	# Niente ombra proiettata dal terreno (2026-11-23, misura FPS con RenderDoc): il terreno è quasi piatto e la sua
	# ombra cadeva solo su sé stesso; nella mappa delle ombre costava ~0,2 ms (fino a ~4 ms quando lo shader scartava
	# i pixel della nebbia nera, poi tolto). Le ombre di alberi, rocce ed edifici sul terreno restano (le riceve).
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


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
