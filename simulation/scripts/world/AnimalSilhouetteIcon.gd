class_name AnimalSilhouetteIcon
extends Control

# Icona vettoriale per il filtro specie del tab Fauna (WorldInfoPanel._rebuild_species_filter_
# row) — disegna con _draw() la STESSA sagoma (corpo a ventaglio + 2 orecchie + coda) usata dal
# renderer sul campo (AnimalGroupRenderer.build_rabbit_mesh/build_deer_mesh), riusando la
# geometria condivisa (AnimalGroupRenderer.get_rabbit_silhouette_geometry/
# get_deer_silhouette_geometry) invece di duplicarla — nessuna texture/Viewport coinvolti: solo
# _draw() vettoriale, nitido a qualunque dimensione dell'icona.
#
# Specie senza una sagoma dedicata (nessuna oggi oltre rabbit/deer/boar/tarpan/aurochs/
# wild_donkey/mouflon/bezoar/wolf) ricadono su un marker generico (cerchio pieno + iniziale del
# nome) invece di restare vuote — un pulsante-filtro per una specie futura compare comunque senza
# bisogno di scrivere prima una sagoma dedicata per lei.
const GENERIC_MARKER_TEXT_COLOR := Color.WHITE
# Frazione del riquadro (size) effettivamente occupata dal contenuto disegnato — un margine
# uniforme così la sagoma/coda/orecchie non toccano mai il bordo del pulsante.
const CONTENT_FILL_RATIO := 0.85

var _color: Color = Color.WHITE
var _geometry: Dictionary = {}
var _has_dedicated_shape: bool = false
var _generic_marker_letter: String = ""


# species_name: "rabbit"/"deer"/"boar"/"tarpan"/"aurochs"/"wild_donkey"/"mouflon"/"bezoar"/"wolf"
# ottengono la sagoma dedicata (stessi parametri di forma del renderer sul campo, vedi
# AnimalGroupRenderer); qualunque altro valore ricade sul marker generico sopra. color è sempre
# scelto dal chiamante (MacroCellInfoPanel) — mai hardcoded qui, stesso principio di
# AnimalGroupRenderer.configure().
func configure(species_name: String, color: Color) -> void:
	_color = color
	_has_dedicated_shape = true
	match species_name:
		"rabbit":
			_geometry = AnimalGroupRenderer.get_rabbit_silhouette_geometry(
				AnimalGroupRenderer.RABBIT_BODY_LENGTH, AnimalGroupRenderer.RABBIT_BODY_WIDTH,
				AnimalGroupRenderer.RABBIT_EAR_LENGTH, AnimalGroupRenderer.RABBIT_EAR_WIDTH
			)
		"deer":
			_geometry = AnimalGroupRenderer.get_deer_silhouette_geometry(
				AnimalGroupRenderer.DEER_BODY_LENGTH, AnimalGroupRenderer.DEER_BODY_WIDTH,
				AnimalGroupRenderer.DEER_EAR_LENGTH, AnimalGroupRenderer.DEER_EAR_WIDTH
			)
		"boar":
			_geometry = AnimalGroupRenderer.get_boar_silhouette_geometry(
				AnimalGroupRenderer.BOAR_BODY_LENGTH, AnimalGroupRenderer.BOAR_BODY_WIDTH,
				AnimalGroupRenderer.BOAR_EAR_LENGTH, AnimalGroupRenderer.BOAR_EAR_WIDTH
			)
		"tarpan":
			_geometry = AnimalGroupRenderer.get_tarpan_silhouette_geometry(
				AnimalGroupRenderer.TARPAN_BODY_LENGTH, AnimalGroupRenderer.TARPAN_BODY_WIDTH,
				AnimalGroupRenderer.TARPAN_EAR_LENGTH, AnimalGroupRenderer.TARPAN_EAR_WIDTH
			)
		"aurochs":
			_geometry = AnimalGroupRenderer.get_aurochs_silhouette_geometry(
				AnimalGroupRenderer.AUROCHS_BODY_LENGTH, AnimalGroupRenderer.AUROCHS_BODY_WIDTH,
				AnimalGroupRenderer.AUROCHS_EAR_LENGTH, AnimalGroupRenderer.AUROCHS_EAR_WIDTH
			)
		"wild_donkey":
			_geometry = AnimalGroupRenderer.get_wild_donkey_silhouette_geometry(
				AnimalGroupRenderer.WILD_DONKEY_BODY_LENGTH, AnimalGroupRenderer.WILD_DONKEY_BODY_WIDTH,
				AnimalGroupRenderer.WILD_DONKEY_EAR_LENGTH, AnimalGroupRenderer.WILD_DONKEY_EAR_WIDTH
			)
		"mouflon":
			_geometry = AnimalGroupRenderer.get_mouflon_silhouette_geometry(
				AnimalGroupRenderer.MOUFLON_BODY_LENGTH, AnimalGroupRenderer.MOUFLON_BODY_WIDTH,
				AnimalGroupRenderer.MOUFLON_EAR_LENGTH, AnimalGroupRenderer.MOUFLON_EAR_WIDTH
			)
		"bezoar":
			_geometry = AnimalGroupRenderer.get_bezoar_silhouette_geometry(
				AnimalGroupRenderer.BEZOAR_BODY_LENGTH, AnimalGroupRenderer.BEZOAR_BODY_WIDTH,
				AnimalGroupRenderer.BEZOAR_EAR_LENGTH, AnimalGroupRenderer.BEZOAR_EAR_WIDTH
			)
		"wolf":
			_geometry = AnimalGroupRenderer.get_wolf_silhouette_geometry(
				AnimalGroupRenderer.WOLF_BODY_LENGTH, AnimalGroupRenderer.WOLF_BODY_WIDTH,
				AnimalGroupRenderer.WOLF_EAR_LENGTH, AnimalGroupRenderer.WOLF_EAR_WIDTH
			)
		_:
			_has_dedicated_shape = false
			_generic_marker_letter = species_name.substr(0, 1).to_upper() if species_name.length() > 0 else "?"
	queue_redraw()


func _draw() -> void:
	if _has_dedicated_shape:
		_draw_silhouette()
	else:
		_draw_generic_marker()


# Scala/centra la geometria (in unità "mondo" — body_length ~3-5.5, la stessa scala usata dal
# renderer sul campo) dentro `size` del Control. Nessun bisogno di orientamento "in marcia" (asse
# +X = muso lì): l'icona è statica, il corpo resta semplicemente orientato lungo l'asse
# orizzontale dell'icona.
func _draw_silhouette() -> void:
	var body_points: PackedVector2Array = _geometry["body_points"]
	var ears: Array = _geometry["ears"]
	var tail_center: Vector2 = _geometry["tail_center"]
	var tail_radius_x: float = _geometry["tail_radius_x"]
	var tail_radius_y: float = _geometry["tail_radius_y"]

	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for p in body_points:
		min_point = Vector2(min(min_point.x, p.x), min(min_point.y, p.y))
		max_point = Vector2(max(max_point.x, p.x), max(max_point.y, p.y))
	# Coda ed estremità orecchie possono sporgere oltre il corpo: incluse nel bounding box così
	# non vengono tagliate ai bordi dell'icona.
	var tail_min := tail_center - Vector2(tail_radius_x, tail_radius_y)
	var tail_max := tail_center + Vector2(tail_radius_x, tail_radius_y)
	min_point = Vector2(min(min_point.x, tail_min.x), min(min_point.y, tail_min.y))
	max_point = Vector2(max(max_point.x, tail_max.x), max(max_point.y, tail_max.y))
	for ear in ears:
		for point in ear:
			min_point = Vector2(min(min_point.x, point.x), min(min_point.y, point.y))
			max_point = Vector2(max(max_point.x, point.x), max(max_point.y, point.y))

	var content_size: Vector2 = max_point - min_point
	if content_size.x <= 0.0 or content_size.y <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return

	var scale_factor: float = min(size.x / content_size.x, size.y / content_size.y) * CONTENT_FILL_RATIO
	var content_center: Vector2 = (min_point + max_point) / 2.0
	var screen_center: Vector2 = size / 2.0

	var to_screen := func(p: Vector2) -> Vector2:
		return screen_center + (p - content_center) * scale_factor

	var screen_body := PackedVector2Array()
	for p in body_points:
		screen_body.append(to_screen.call(p))
	draw_colored_polygon(screen_body, _color)

	for ear in ears:
		var triangle := PackedVector2Array([
			to_screen.call(ear[0]), to_screen.call(ear[1]), to_screen.call(ear[2])
		])
		draw_colored_polygon(triangle, _color)

	# Ellisse (non un cerchio, vedi tail_radius_x/tail_radius_y sopra): draw_circle non supporta
	# raggi non uniformi, quindi la disegnamo come poligono campionato — stessa logica di
	# AnimalGroupRenderer._build_mesh_from_geometry, qui in coordinate schermo.
	var screen_tail := PackedVector2Array()
	for i in range(AnimalGroupRenderer.TAIL_SEGMENTS):
		var angle: float = (float(i) / float(AnimalGroupRenderer.TAIL_SEGMENTS)) * TAU
		var p := tail_center + Vector2(cos(angle) * tail_radius_x, sin(angle) * tail_radius_y)
		screen_tail.append(to_screen.call(p))
	draw_colored_polygon(screen_tail, _color)


func _draw_generic_marker() -> void:
	var radius: float = min(size.x, size.y) / 2.0 * CONTENT_FILL_RATIO
	var center: Vector2 = size / 2.0
	draw_circle(center, radius, _color)

	var font := ThemeDB.fallback_font
	var font_size: int = int(radius * 1.1)
	var text_size: Vector2 = font.get_string_size(
		_generic_marker_letter, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size
	)
	draw_string(
		font, center - text_size / 2.0 + Vector2(0.0, text_size.y * 0.35), _generic_marker_letter,
		HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, GENERIC_MARKER_TEXT_COLOR
	)
