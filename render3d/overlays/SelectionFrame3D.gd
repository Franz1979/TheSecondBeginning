class_name SelectionFrame3D
extends RefCounted

# Oggetto 3D: le selezioni di UNA cella (SelectionSnapshot3D) nello stile del 3D (2026-11-19, richiesta utente: il cerchio
# rosso del 2D è roba da debug). Bianco caldo per tutto:
#   - anello morbido a terra attorno all'oggetto selezionato, di spessore fisso (più leggero per quello sotto il mouse),
#     poggiato sul terreno;
#   - riquadro sottile sulla microcella (ispezione, lotto di bastoni), poggiato sul terreno.
# Il contorno sui modelli (Outline3D) è spento: basta l'anello.

const COLOR := Color(1.0, 0.93, 0.75)
# Alone: più largo del raggio del 2D, così il bordo chiaro cade appena fuori dall'oggetto.
const HALO_SCALE := 1.35
# Anello: posizione del centro della striscia sul raggio dell'alone, spessore fisso in microcelle, pezzi del giro.
const RING_POSITION := 0.78
# Più sottile e meno bianco il 2026-11-19 (richiesta utente: era 0,12 / 0,08, pieno); dentro torna l'alone leggero.
const RING_CORE := 0.08
const RING_FADE := 0.06
const RING_ALPHA := 0.6
# Alone leggero dentro l'anello: più chiaro al centro, sparisce prima del bordo.
const FILL_ALPHA := 0.16
const RING_SEGMENTS := 48
# Riquadro: larghezza della striscia (microcelle), sollevamento, pezzi per lato.
const SQUARE_WIDTH := 0.05
const SQUARE_ALPHA := 0.9
const LIFT := 0.04
const SQUARE_STEPS := 4

static var _ring_material: StandardMaterial3D
static var _square_material: StandardMaterial3D


# base_global: angolo della cella in microcelle assolute. null se non c'è niente.
static func build(snapshot: SelectionSnapshot3D, base_global: Vector2) -> Node3D:
	if snapshot.is_empty():
		return null
	var node := Node3D.new()
	for i in range(snapshot.halo_centers.size()):
		node.add_child(_make_halo(snapshot.halo_centers[i], snapshot.halo_radii[i], snapshot.halo_strengths[i], base_global))
	if not snapshot.squares.is_empty():
		node.add_child(_make_squares(snapshot.squares, base_global))
	return node


# Anello a terra di spessore FISSO (2026-11-19, richiesta utente: con la texture scalata il bordo era largo in proporzione
# all'oggetto; ora è uguale per un sasso e per un edificio, -20% rispetto a prima). Striscia piena RING_CORE con due
# sfumature RING_FADE ai lati (niente linea netta), a pezzi così segue il terreno. Raggio come il bordo chiaro di prima.
static func _make_halo(center: Vector2, radius: float, strength: float, base_global: Vector2) -> MeshInstance3D:
	var ring_radius := radius * HALO_SCALE * RING_POSITION
	var inner := maxf(0.0, ring_radius - RING_CORE / 2.0 - RING_FADE)
	var core_in := maxf(0.0, ring_radius - RING_CORE / 2.0)
	var core_out := ring_radius + RING_CORE / 2.0
	var outer := core_out + RING_FADE
	var radii := [0.0, inner * 0.5, inner, core_in, core_out, outer]
	var fill := FILL_ALPHA * strength
	var ring := RING_ALPHA * strength
	var alphas := [fill, fill * 0.55, fill * 0.15, ring, ring, 0.0]
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	for k in range(RING_SEGMENTS):
		var a0 := TAU * k / RING_SEGMENTS
		var a1 := TAU * (k + 1) / RING_SEGMENTS
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		for band in range(radii.size() - 1):
			var p00: Vector2 = center + d0 * float(radii[band])
			var p01: Vector2 = center + d1 * float(radii[band])
			var p10: Vector2 = center + d0 * float(radii[band + 1])
			var p11: Vector2 = center + d1 * float(radii[band + 1])
			var c_in := Color(COLOR.r, COLOR.g, COLOR.b, float(alphas[band]))
			var c_out := Color(COLOR.r, COLOR.g, COLOR.b, float(alphas[band + 1]))
			vertices.append_array(PackedVector3Array([
				_on_ground(p00, base_global), _on_ground(p10, base_global), _on_ground(p11, base_global),
				_on_ground(p00, base_global), _on_ground(p11, base_global), _on_ground(p01, base_global),
			]))
			colors.append_array(PackedColorArray([c_in, c_out, c_out, c_in, c_out, c_in]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _get_ring_material()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func _get_ring_material() -> StandardMaterial3D:
	if _ring_material == null:
		_ring_material = StandardMaterial3D.new()
		_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_material.vertex_color_use_as_albedo = true
		_ring_material.vertex_color_is_srgb = true
		_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _ring_material


static func _make_squares(lots: Array[Vector2i], base_global: Vector2) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	for lot in lots:
		var corners := [Vector2(lot.x, lot.y), Vector2(lot.x + 1, lot.y), Vector2(lot.x + 1, lot.y + 1), Vector2(lot.x, lot.y + 1)]
		var center := Vector2(lot.x + 0.5, lot.y + 0.5)
		for side in range(4):
			var a: Vector2 = corners[side]
			var b: Vector2 = corners[(side + 1) % 4]
			# A pezzi, così la striscia segue il terreno; lato esterno sul bordo, interno verso il centro.
			for step in range(SQUARE_STEPS):
				var p0 := a.lerp(b, float(step) / SQUARE_STEPS)
				var p1 := a.lerp(b, float(step + 1) / SQUARE_STEPS)
				var q0 := p0 + (center - p0).normalized() * SQUARE_WIDTH
				var q1 := p1 + (center - p1).normalized() * SQUARE_WIDTH
				var v := [_on_ground(p0, base_global), _on_ground(p1, base_global), _on_ground(q1, base_global), _on_ground(q0, base_global)]
				vertices.append_array(PackedVector3Array([v[0], v[2], v[1], v[0], v[3], v[2]]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _get_square_material()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func _on_ground(local: Vector2, base_global: Vector2) -> Vector3:
	var y := GroundHeight3D.land_height(base_global.x + local.x, base_global.y + local.y) + LIFT
	return Vector3(local.x, y, local.y)


static func _get_square_material() -> StandardMaterial3D:
	if _square_material == null:
		_square_material = StandardMaterial3D.new()
		_square_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_square_material.albedo_color = Color(COLOR.r, COLOR.g, COLOR.b, SQUARE_ALPHA)
		_square_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_square_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _square_material
