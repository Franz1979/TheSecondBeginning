class_name StreamMask3D
extends RefCounted

# Oggetto 3D: il ruscello di UNA macrocella, come "maschera" letta dallo shader del terreno (terrain.gdshader), così
# acqua e riva bagnata sono disegnate DENTRO il terreno e non appoggiate sopra. Stesso tracciato del 2D
# (StreamMicrocellService.get_layout: linee centrali, slarghi, laghetto della sorgente) e stesse larghezze/rumore
# (MicroCellRenderer.set_streams), convertite da pixel a microcelle.
# Immagine RGBA8 di PIXELS_PER_MICROCELL pixel per microcella: R = acqua (0.5 = bordo dell'acqua, 1 = centro),
# G = riva bagnata (0.5 = bordo della riva), B/A = direzione della corrente (x, y portati da -1..1 a 0..1), quella del
# tratto più vicino, nel verso del tracciato. Anche le quote del terreno ne tengono conto (letto un po' più basso).

const HALF_WIDTH_MIN := 0.18
const HALF_WIDTH_MAX := 0.34
const MUD_MARGIN_MIN := 0.15
const MUD_MARGIN_MAX := 0.4
const WIDENING_RADIUS := 0.55
const PIXELS_PER_MICROCELL := 4
# Quanto scende il terreno sotto il letto del ruscello (agli angoli della griglia).
const BED_DEPTH := 0.12


# Ritorna la maschera (Image RG8) o null se la cella non ha ruscello.
static func build(source: Cell3DSource) -> Image:
	var paths: Array = source.stream_layout.get("paths", [])
	var widenings: Array = source.stream_layout.get("widenings", [])
	var pond_center: Variant = source.stream_layout.get("pond_center", null)
	if paths.is_empty() and widenings.is_empty() and pond_center == null:
		return null
	var size := World.WIDTH * PIXELS_PER_MICROCELL
	var water := PackedFloat32Array()
	var bank := PackedFloat32Array()
	var flow := PackedVector2Array()
	water.resize(size * size)
	bank.resize(size * size)
	flow.resize(size * size)

	for path in paths:
		var points: PackedVector2Array = path
		var radii := PackedFloat32Array()
		var margins := PackedFloat32Array()
		for p in points:
			var key := Vector2i(int(p.x * 8.0), int(p.y * 8.0))
			radii.append((lerpf(HALF_WIDTH_MIN, HALF_WIDTH_MAX, Noise2DMatch.value(key, 1))
				+ lerpf(HALF_WIDTH_MIN, HALF_WIDTH_MAX, Noise2DMatch.value(key, 2))) * 0.5)
			margins.append(lerpf(MUD_MARGIN_MIN, MUD_MARGIN_MAX, Noise2DMatch.value(key, 3)))
		for i in range(points.size()):
			var j := mini(i + 1, points.size() - 1)
			_stamp_segment(water, bank, flow, size, points[i], points[j], radii[i], radii[j], margins[i], margins[j])
	for widening in widenings:
		_stamp_segment(water, bank, flow, size, widening, widening, WIDENING_RADIUS, WIDENING_RADIUS, MUD_MARGIN_MIN, MUD_MARGIN_MIN)
	if pond_center != null:
		var pond_radius := StreamMicrocellService.POND_RADIUS
		_stamp_segment(water, bank, flow, size, pond_center, pond_center, pond_radius, pond_radius, MUD_MARGIN_MAX, MUD_MARGIN_MAX)

	var bytes := PackedByteArray()
	bytes.resize(size * size * 4)
	for k in range(size * size):
		bytes[k * 4] = int(clampf(water[k], 0.0, 1.0) * 255.0)
		bytes[k * 4 + 1] = int(clampf(bank[k], 0.0, 1.0) * 255.0)
		bytes[k * 4 + 2] = int(clampf(flow[k].x * 0.5 + 0.5, 0.0, 1.0) * 255.0)
		bytes[k * 4 + 3] = int(clampf(flow[k].y * 0.5 + 0.5, 0.0, 1.0) * 255.0)
	return Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, bytes)


# Quanto scende il terreno all'angolo (i, j) della griglia: letto del ruscello appena incassato.
static func bed_depth_at(mask: Image, i: int, j: int) -> float:
	var size := mask.get_width()
	var x := clampi(i * PIXELS_PER_MICROCELL, 0, size - 1)
	var y := clampi(j * PIXELS_PER_MICROCELL, 0, size - 1)
	return BED_DEPTH * smoothstep(0.2, 0.7, mask.get_pixel(x, y).g)


# Segna acqua e riva attorno al tratto a-b (raggio e margine interpolati lungo il tratto). Valori: 1 al centro,
# 0.5 sul bordo, 0 fuori; si tiene il massimo tra i tratti. La corrente è la direzione del tratto che dà più acqua
# (uno slargo o il laghetto, senza direzione, non la cambia).
static func _stamp_segment(water: PackedFloat32Array, bank: PackedFloat32Array, flow: PackedVector2Array, size: int,
		a: Vector2, b: Vector2, radius_a: float, radius_b: float, margin_a: float, margin_b: float) -> void:
	var reach := maxf(radius_a + margin_a, radius_b + margin_b) * 2.0
	var ppm := float(PIXELS_PER_MICROCELL)
	var min_x := clampi(int(floor((minf(a.x, b.x) - reach) * ppm)), 0, size - 1)
	var max_x := clampi(int(ceil((maxf(a.x, b.x) + reach) * ppm)), 0, size - 1)
	var min_y := clampi(int(floor((minf(a.y, b.y) - reach) * ppm)), 0, size - 1)
	var max_y := clampi(int(ceil((maxf(a.y, b.y) + reach) * ppm)), 0, size - 1)
	var ab := b - a
	var length_sq := ab.length_squared()
	var direction := ab.normalized() if length_sq > 0.000001 else Vector2.ZERO
	for py in range(min_y, max_y + 1):
		for px in range(min_x, max_x + 1):
			var p := Vector2((px + 0.5) / ppm, (py + 0.5) / ppm)
			var t := 0.0 if length_sq < 0.000001 else clampf((p - a).dot(ab) / length_sq, 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			var radius := lerpf(radius_a, radius_b, t)
			var outer := radius + lerpf(margin_a, margin_b, t)
			var k := py * size + px
			# 1 al centro, 0.5 sul bordo, 0 a due volte il raggio.
			var value := clampf(1.0 - d / (radius * 2.0), 0.0, 1.0)
			if value > water[k]:
				water[k] = value
				if direction != Vector2.ZERO:
					flow[k] = direction
			bank[k] = maxf(bank[k], clampf(1.0 - d / (outer * 2.0), 0.0, 1.0))
