class_name FacetedStoneMesh
extends RefCounted

# Forma di una pietra a facce piatte, usata dalla roccia (Rock3D) e dal sasso (Pebble3D) con misure diverse:
# base larga appoggiata a terra, un anello a metà altezza più stretto e ruotato, una cima piccola. Gli anelli sono
# "storti" in modo fisso per variante (stessa variante = stessa forma a ogni apertura). Centro della base in (0, 0, 0).

const COLOR_BASE := Color("8d8a82")


# radius: mezza larghezza; height: altezza; sides: lati degli anelli; jitter: irregolarità (0..1); variant: seme;
# color: tinta di base (grigio pietra se non indicata, es. rossiccio per le zolle d'argilla).
static func build(radius: float, height: float, sides: int, jitter: float, variant: int, color: Color = COLOR_BASE) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (variant + 1)
	var bottom := _ring(rng, sides, radius, -0.04 * height, 0.0, jitter)
	var middle := _ring(rng, sides, radius * 0.82, height * 0.5, PI / sides, jitter)
	var top := _ring(rng, sides, radius * 0.42, height * 0.88, 0.0, jitter)
	var peak := Vector3(radius * rng.randf_range(-0.12, 0.12), height, radius * rng.randf_range(-0.12, 0.12))

	var builder := FlatMeshBuilder.new()
	for i in range(sides):
		var j := (i + 1) % sides
		# Fianco basso: base -> anello di mezzo (ruotato di mezzo lato, quindi triangoli alternati).
		_face(builder, rng, color, bottom[i], bottom[j], middle[i])
		_face(builder, rng, color, bottom[j], middle[j], middle[i])
		# Fianco alto: anello di mezzo -> cima.
		_face(builder, rng, color, middle[i], middle[j], top[j])
		_face(builder, rng, color, middle[i], top[j], top[i])
		# Cappello.
		_face(builder, rng, color, top[i], top[j], peak)
	return builder.build()


static func _ring(rng: RandomNumberGenerator, sides: int, radius: float, y: float, phase: float, jitter: float) -> Array:
	var points := []
	for i in range(sides):
		var angle := phase + TAU * i / sides + rng.randf_range(-0.25, 0.25) * TAU / sides
		var r := radius * (1.0 + rng.randf_range(-jitter, jitter))
		points.append(Vector3(cos(angle) * r, y * (1.0 + rng.randf_range(-jitter, jitter) * 0.5), sin(angle) * r))
	return points


# Faccia rivolta verso l'esterno (rispetto all'asse verticale della pietra), con un tono leggermente diverso per faccia:
# più chiaro verso l'alto, così la forma si legge anche in ombra.
static func _face(builder: FlatMeshBuilder, rng: RandomNumberGenerator, color: Color, a: Vector3, b: Vector3, c: Vector3) -> void:
	var centroid := (a + b + c) / 3.0
	var outward := Vector3(centroid.x, maxf(centroid.y, 0.0) * 0.6, centroid.z)
	if (c - a).cross(b - a).dot(outward) < 0.0:
		var t := b
		b = c
		c = t
	var normal := (c - a).cross(b - a).normalized()
	var tone := 0.9 + 0.18 * clampf(normal.y, 0.0, 1.0) + rng.randf_range(-0.04, 0.04)
	builder.add_triangle(a, b, c, color * Color(tone, tone, tone, 1.0))
