class_name EarthworkShape
extends RefCounted

# Vallo difensivo (earthwork) a pezzi uniti (2026-10-04, richiesta utente), condiviso da mappa
# (MicroCellRenderer._draw_buildings), anteprima di piazzamento (BuildingGhost) e icona della barra (EarthworkIcon).
# Dal 2026-10-04 (edifici lineari riusabili) il disegno vero è quello comune di LinearShape: qui restano solo i parametri
# del vallo — argine di terra bruna largo quanto il cumulo (raggio 2.6) con il ciglio più scuro, nessun fosso — e la
# stessa firma di prima per i chiamanti. Vedi LinearShape per la forma di ogni pezzo (centro, bracci, angoli smussati,
# estremità) e per i raccordi tra angoli.

const MOUND_RADIUS: float = 2.6
const CREST_WIDTH: float = 0.8
const CREST_DOT_RADIUS: float = 0.9
const EARTH := Color(0.47, 0.36, 0.24, 1.0)
const EARTH_DARK := Color(0.33, 0.25, 0.16, 1.0)
const INVALID_TINT := Color(0.9, 0.25, 0.25, 0.55)
# Striscia di fondo chiaro sotto l'argine (2026-10-04): un po' più larga del cumulo.
const GROUND_HALF_WIDTH: float = 3.6
# Lati di un tratto dritto orizzontale (E | W): l'aspetto dell'icona.
const STRAIGHT_MASK: int = LinearShape.STRAIGHT_MASK

static var STYLE := LinearShapeStyle.new(
	MOUND_RADIUS, EARTH, EARTH_DARK, CREST_WIDTH, CREST_DOT_RADIUS, INVALID_TINT, GROUND_HALF_WIDTH
)


static func is_corner_mask(neighbor_mask: int) -> bool:
	return LinearShape.is_corner_mask(neighbor_mask)


# `invalid` = anteprima su una posizione non edificabile; `alpha` per l'anteprima semitrasparente; `clip_mask` = lati il
# cui vicino è a sua volta un angolo (vedi LinearShape).
static func draw(
	canvas: CanvasItem, center: Vector2, neighbor_mask: int, invalid: bool = false, alpha: float = 1.0,
	scale: float = 1.0, clip_mask: int = 0
) -> void:
	LinearShape.draw(canvas, center, neighbor_mask, STYLE, invalid, alpha, scale, clip_mask)


# Fondo chiaro sotto l'argine (vedi LinearShape.draw_ground): `fill_mask` = lati con un vicino che ha il proprio fondo.
static func draw_ground(canvas: CanvasItem, center: Vector2, neighbor_mask: int, clip_mask: int, fill_mask: int, color: Color) -> void:
	LinearShape.draw_ground(canvas, center, neighbor_mask, clip_mask, fill_mask, STYLE, color)
