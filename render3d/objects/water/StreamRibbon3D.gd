class_name StreamRibbon3D
extends RefCounted

# Oggetto 3D: il ruscello di UNA macrocella, come nastro morbido che segue lo stesso tracciato del 2D
# (StreamMicrocellService.get_layout): linee centrali, slarghi e laghetto della sorgente. Sotto l'acqua un alone di
# fango. Larghezze e rumore uguali al 2D (MicroCellRenderer.set_streams), convertite da pixel a microcelle.

const HALF_WIDTH_MIN := 0.18
const HALF_WIDTH_MAX := 0.34
const MUD_MARGIN_MIN := 0.15
const MUD_MARGIN_MAX := 0.4
const WIDENING_RADIUS := 0.55
const FAN_SEGMENTS := 8
const POND_SEGMENTS := 14
# Altezza sopra il terreno, per non mescolarsi con lui.
const MUD_LIFT := 0.04
const WATER_LIFT := 0.08
const MUD_COLOR := Color("6b5a3c")


# Ritorna un nodo con fango e acqua, oppure null se la cella non ha ruscello.
static func build(source: Cell3DSource, mud_material: Material, water_material: Material) -> Node3D:
	var paths: Array = source.stream_layout.get("paths", [])
	var widenings: Array = source.stream_layout.get("widenings", [])
	var pond_center: Variant = source.stream_layout.get("pond_center", null)
	if paths.is_empty() and widenings.is_empty() and pond_center == null:
		return null
	var base := Vector2(source.coords.x * World.WIDTH, source.coords.y * World.HEIGHT)
	var mud := FlatMeshBuilder.new()
	var water := FlatMeshBuilder.new()
	# Opaca: i pezzi del nastro si sovrappongono, con la trasparenza le giunture verrebbero più scure.
	var water_color := Palette3D.WATER_RIVER

	for path in paths:
		var points: PackedVector2Array = path
		var left := PackedFloat32Array()
		var right := PackedFloat32Array()
		var extra := PackedFloat32Array()
		for p in points:
			var key := Vector2i(int(p.x * 8.0), int(p.y * 8.0))
			left.append(lerpf(HALF_WIDTH_MIN, HALF_WIDTH_MAX, Noise2DMatch.value(key, 1)))
			right.append(lerpf(HALF_WIDTH_MIN, HALF_WIDTH_MAX, Noise2DMatch.value(key, 2)))
			extra.append(lerpf(MUD_MARGIN_MIN, MUD_MARGIN_MAX, Noise2DMatch.value(key, 3)))
		for i in range(points.size()):
			var radius := (left[i] + right[i]) * 0.5
			_fan(mud, base, points[i], radius + extra[i], FAN_SEGMENTS, MUD_LIFT, MUD_COLOR)
			_fan(water, base, points[i], radius, FAN_SEGMENTS, WATER_LIFT, water_color)
			if i == points.size() - 1:
				continue
			var normal := (points[i + 1] - points[i]).normalized().orthogonal()
			if normal == Vector2.ZERO:
				continue
			_strip(mud, base, points[i], points[i + 1], normal,
				left[i] + extra[i], right[i] + extra[i], left[i + 1] + extra[i + 1], right[i + 1] + extra[i + 1], MUD_LIFT, MUD_COLOR)
			_strip(water, base, points[i], points[i + 1], normal,
				left[i], right[i], left[i + 1], right[i + 1], WATER_LIFT, water_color)
	for widening in widenings:
		_fan(mud, base, widening, WIDENING_RADIUS + MUD_MARGIN_MIN, FAN_SEGMENTS, MUD_LIFT, MUD_COLOR)
		_fan(water, base, widening, WIDENING_RADIUS, FAN_SEGMENTS, WATER_LIFT, water_color)
	if pond_center != null:
		var pond_radius := StreamMicrocellService.POND_RADIUS
		_fan(mud, base, pond_center, pond_radius + MUD_MARGIN_MAX, POND_SEGMENTS, MUD_LIFT, MUD_COLOR)
		_fan(water, base, pond_center, pond_radius, POND_SEGMENTS, WATER_LIFT, water_color)

	var node := Node3D.new()
	node.name = "Stream"
	var mud_instance := MeshInstance3D.new()
	mud_instance.mesh = mud.build()
	mud_instance.material_override = mud_material
	mud_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mud_instance)
	var water_instance := MeshInstance3D.new()
	water_instance.mesh = water.build()
	water_instance.material_override = water_material
	water_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(water_instance)
	return node


static func _point(base: Vector2, p: Vector2, lift: float) -> Vector3:
	return Vector3(p.x, GroundHeight3D.land_height(base.x + p.x, base.y + p.y) + lift, p.y)


static func _fan(builder: FlatMeshBuilder, base: Vector2, center: Vector2, radius: float, segments: int, lift: float, color: Color) -> void:
	var c := _point(base, center, lift)
	for s in range(segments):
		var a0 := TAU * s / segments
		var a1 := TAU * (s + 1) / segments
		builder.add_ground_triangle(c,
			_point(base, center + Vector2(cos(a0), sin(a0)) * radius, lift),
			_point(base, center + Vector2(cos(a1), sin(a1)) * radius, lift), color)


static func _strip(builder: FlatMeshBuilder, base: Vector2, from: Vector2, to: Vector2, normal: Vector2,
		left_from: float, right_from: float, left_to: float, right_to: float, lift: float, color: Color) -> void:
	var a := _point(base, from + normal * left_from, lift)
	var b := _point(base, from - normal * right_from, lift)
	var c := _point(base, to - normal * right_to, lift)
	var d := _point(base, to + normal * left_to, lift)
	builder.add_ground_triangle(a, b, c, color)
	builder.add_ground_triangle(a, c, d, color)

