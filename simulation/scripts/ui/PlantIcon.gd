class_name PlantIcon
extends Control

# Icona di un tipo di pianta (2026-10-05, elenco delle piante sotto "Taglia" — OptionChoiceDialog): le stesse forme e
# gli stessi colori del disegno sulla mappa (costanti di MicroCellRenderer), ridotte a icona. Una per sottotipo:
#   - albero (wood_only): tronco marrone e chioma tonda verde;
#   - albero da ghiande (wild_fruit) / albero da frutto (domesticable_fruit): come l'albero, con i puntini della mappa
#     (ambra per le ghiande, rossi per i frutti);
#   - conifera: tronco e chioma a triangolo (CONIFER_SHAPE_POINTS);
#   - arbusto (wood_only): macchie verdi e marroni;
#   - arbusto da bacche (fruit_bearing): come l'arbusto, con i puntini delle bacche.
# Chioma sempre col verde di primavera (niente colore stagionale), nessuna variazione per età. Control minimale, solo
# _draw(): riempie il proprio Rect2 (il riquadro icona di chi la ospita) e si ridisegna solo quando cambia dimensione o
# visibilità, mai a ogni frame. Posizioni FISSE (mai randf()), stesso principio delle altre icone disegnate.

var object_type: GameTypes.WorldObjectType = GameTypes.WorldObjectType.TREE
var subtype_name: String = ""

const CANOPY_COLOR_KEY := GameTypes.Season.SPRING
const CIRCLE_SEGMENTS: int = 20
# Proporzioni dell'albero in unità della mappa (MicroCellRenderer._compute_tree_visual, valori medi): tronco largo 1.6
# e alto ~3.5, chioma di raggio ~3.3 col centro 0.6 raggi sopra la cima del tronco. Altezza totale ~9.5 unità.
const TREE_TRUNK_WIDTH: float = 1.6
const TREE_TRUNK_HEIGHT: float = 3.5
const TREE_CANOPY_RADIUS: float = 3.3
const TREE_TOTAL_HEIGHT: float = 9.5
# Puntini dei frutti sulla chioma: angoli e distanza fissi (sulla mappa variano per posizione).
const TREE_FRUIT_DOTS := [
	{"angle": -2.4, "distance": 0.62},
	{"angle": -0.5, "distance": 0.70},
	{"angle": 1.3, "distance": 0.55},
]
# Macchie dell'arbusto in unità della mappa (distanza 0.8-1.8, raggio 1.4-2.2 su MicroCellRenderer), colori alternati
# verde/marrone come il gradiente dei lobi. Ingombro ~±4 unità.
const SHRUB_BLOBS := [
	{"x": -1.3, "y": 0.4, "r": 1.7, "green": false},
	{"x": 1.2, "y": 0.5, "r": 1.6, "green": false},
	{"x": -0.6, "y": -0.8, "r": 2.0, "green": true},
	{"x": 0.9, "y": -0.6, "r": 1.8, "green": true},
]
const SHRUB_EXTENT: float = 8.4
const SHRUB_BERRIES := [Vector2(-1.2, -0.9), Vector2(1.4, -0.3), Vector2(0.1, 0.9)]
const SHRUB_BERRY_RADIUS: float = 0.55


static func create(p_object_type: GameTypes.WorldObjectType, p_subtype_name: String) -> PlantIcon:
	var icon := PlantIcon.new()
	icon.object_type = p_object_type
	icon.subtype_name = p_subtype_name
	return icon


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if object_type == GameTypes.WorldObjectType.SHRUB:
		_draw_shrub()
	else:
		_draw_tree()


func _draw_tree() -> void:
	var unit: float = minf(size.x, size.y) / TREE_TOTAL_HEIGHT
	var ground := Vector2(size.x * 0.5, size.y * 0.5 + TREE_TOTAL_HEIGHT * unit * 0.5)
	var trunk_width: float = TREE_TRUNK_WIDTH * unit
	var trunk_height: float = TREE_TRUNK_HEIGHT * unit
	draw_rect(Rect2(ground.x - trunk_width * 0.5, ground.y - trunk_height, trunk_width, trunk_height), MicroCellRenderer.COLOR_TREE_TRUNK)
	var canopy_radius: float = TREE_CANOPY_RADIUS * unit
	var canopy_center := Vector2(ground.x, ground.y - trunk_height - canopy_radius * 0.6)
	if subtype_name == "conifer":
		var points := PackedVector2Array()
		for point in MicroCellRenderer.CONIFER_SHAPE_POINTS:
			points.append(canopy_center + (point as Vector2) * canopy_radius)
		draw_colored_polygon(points, _opaque(MicroCellRenderer.COLOR_TREE_CONIFER_CANOPY))
		return
	draw_circle(canopy_center, canopy_radius, _opaque(MicroCellRenderer.TREE_CANOPY_PALETTE_BY_SEASON[CANOPY_COLOR_KEY]))
	var fruit_color := Color.TRANSPARENT
	if subtype_name == "wild_fruit":
		fruit_color = MicroCellRenderer.COLOR_TREE_FRUIT_WILD
	elif subtype_name == "domesticable_fruit":
		fruit_color = MicroCellRenderer.COLOR_TREE_FRUIT_DOMESTICABLE
	if fruit_color.a <= 0.0:
		return
	var dot_radius: float = canopy_radius * MicroCellRenderer.FRUIT_DOT_RADIUS_RATIO
	for dot in TREE_FRUIT_DOTS:
		var angle: float = float(dot["angle"])
		draw_circle(canopy_center + Vector2(cos(angle), sin(angle)) * canopy_radius * float(dot["distance"]), dot_radius, _opaque(fruit_color))


func _draw_shrub() -> void:
	var unit: float = minf(size.x, size.y) / SHRUB_EXTENT
	var center := size * 0.5
	for blob in SHRUB_BLOBS:
		var color: Color = MicroCellRenderer.COLOR_SHRUB_GREEN if bool(blob["green"]) else MicroCellRenderer.COLOR_SHRUB_BROWN
		draw_circle(center + Vector2(float(blob["x"]), float(blob["y"])) * unit, float(blob["r"]) * unit, _opaque(color))
	if subtype_name != "fruit_bearing":
		return
	for berry in SHRUB_BERRIES:
		draw_circle(center + (berry as Vector2) * unit, SHRUB_BERRY_RADIUS * unit, _opaque(MicroCellRenderer.COLOR_SHRUB_BERRY))


# Colori della mappa a piena opacità: sulla mappa la trasparenza fonde la pianta col terreno, nell'icona la farebbe
# sbiadire sul fondo del popup.
static func _opaque(color: Color) -> Color:
	return Color(color.r, color.g, color.b, 1.0)
