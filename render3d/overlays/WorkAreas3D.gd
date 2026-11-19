class_name WorkAreas3D
extends RefCounted

# Sovrapposizione 3D: le aree di lavoro di UNA cella (WorkAreasSnapshot3D), come WorkAreaOverlay/WorkAreaDragPreview nel
# 2D: riempimento leggero e bordo nel colore della zona, poggiati sul terreno e appena sollevati (seguono le colline), più
# il nome (o le misure del trascinamento) all'angolo in alto a sinistra, sempre leggibile (Label3D a misura fissa sullo
# schermo, girata verso la camera). Senza luce né ombre: è interfaccia, non mondo.

# Bordo: i pixel del 2D (su CELL_SIZE) ridotti, nel 3D la striscia piena pesa di più.
const BORDER_SCALE := 0.6
const LIFT := 0.03
# Riempimento a quadratini di FILL_STEP microcelle (più grossi per le zone molto grandi), così segue il terreno.
const MAX_FILL_QUADS_PER_SIDE := 40
const LABEL_FONT_SIZE := 26
const LABEL_OUTLINE := 8
const LABEL_PIXEL_SIZE := 0.0016
# Scritta DENTRO la zona (2026-11-19, richiesta utente: sopra l'angolo usciva e copriva la zona vicina): appesa all'angolo
# in alto a sinistra e allungata verso il basso dello schermo, appena sollevata da terra.
const LABEL_HEIGHT := 0.05
const LABEL_CORNER_INSET := 0.5
const ICON_KEYS_META := &"icon_keys"

static var _material: StandardMaterial3D


# base_global: angolo della cella in microcelle assolute. null se non c'è niente da mostrare.
static func build(snapshot: WorkAreasSnapshot3D, base_global: Vector2) -> Node3D:
	if snapshot.size() == 0:
		return null
	var node := Node3D.new()
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	for i in range(snapshot.size()):
		var rect := snapshot.rects[i]
		var color := snapshot.colors[i]
		_add_fill(vertices, colors, rect, Color(color.r, color.g, color.b, snapshot.fill_alphas[i]), base_global)
		var width := snapshot.border_widths[i] / float(MicroCellRenderer.CELL_SIZE) * BORDER_SCALE
		_add_border(vertices, colors, rect, Color(color.r, color.g, color.b, 1.0), width, base_global)
		if snapshot.labels[i] != "":
			var label := _make_label(snapshot.labels[i], rect, base_global)
			# Icone dei lavori: le mette sullo schermo, sotto la scritta, WorkAreaIcons3D (sono disegni del 2D, non immagini).
			label.set_meta(ICON_KEYS_META, snapshot.icons[i])
			node.add_child(label)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _get_material()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(instance)
	return node


static func _add_fill(vertices: PackedVector3Array, colors: PackedColorArray, rect: Rect2i, color: Color, base_global: Vector2) -> void:
	var step := maxi(1, ceili(float(maxi(rect.size.x, rect.size.y)) / MAX_FILL_QUADS_PER_SIDE))
	var y := 0
	while y < rect.size.y:
		var x := 0
		var h := mini(step, rect.size.y - y)
		while x < rect.size.x:
			var w := mini(step, rect.size.x - x)
			var p := Vector2(rect.position.x + x, rect.position.y + y)
			_add_quad(vertices, colors, p, p + Vector2(w, 0), p + Vector2(w, h), p + Vector2(0, h), color, base_global)
			x += step
		y += step


# Quattro lati, a pezzi di una microcella (seguono il terreno); la striscia sta dentro il rettangolo, come il bordo 2D.
static func _add_border(vertices: PackedVector3Array, colors: PackedColorArray, rect: Rect2i, color: Color, width: float, base_global: Vector2) -> void:
	var r := Rect2(rect)
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	var segments := [
		[Vector2(x0, y0), Vector2(x1, y0), Vector2(0, width)],
		[Vector2(x0, y1), Vector2(x1, y1), Vector2(0, -width)],
		[Vector2(x0, y0), Vector2(x0, y1), Vector2(width, 0)],
		[Vector2(x1, y0), Vector2(x1, y1), Vector2(-width, 0)],
	]
	for segment in segments:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		var inward: Vector2 = segment[2]
		var pieces := maxi(1, ceili(a.distance_to(b)))
		for k in range(pieces):
			var p0 := a.lerp(b, float(k) / pieces)
			var p1 := a.lerp(b, float(k + 1) / pieces)
			_add_quad(vertices, colors, p0, p1, p1 + inward, p0 + inward, color, base_global)


static func _add_quad(vertices: PackedVector3Array, colors: PackedColorArray, a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color, base_global: Vector2) -> void:
	var v := [_on_ground(a, base_global), _on_ground(b, base_global), _on_ground(c, base_global), _on_ground(d, base_global)]
	vertices.append_array(PackedVector3Array([v[0], v[2], v[1], v[0], v[3], v[2]]))
	for i in range(6):
		colors.append(color)


static func _on_ground(local: Vector2, base_global: Vector2) -> Vector3:
	return Vector3(local.x, GroundHeight3D.land_height(base_global.x + local.x, base_global.y + local.y) + LIFT, local.y)


static func _make_label(text: String, rect: Rect2i, base_global: Vector2) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = LABEL_FONT_SIZE
	label.outline_size = LABEL_OUTLINE
	label.modulate = Color.WHITE
	label.outline_modulate = Color(0.08, 0.06, 0.04, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = LABEL_PIXEL_SIZE
	label.no_depth_test = true
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var corner := Vector2(rect.position) + Vector2(LABEL_CORNER_INSET, LABEL_CORNER_INSET)
	label.position = _on_ground(corner, base_global) + Vector3(0.0, LABEL_HEIGHT, 0.0)
	return label


static func _get_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.vertex_color_use_as_albedo = true
		# Colori delle zone come nel 2D (sRGB).
		_material.vertex_color_is_srgb = true
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _material
