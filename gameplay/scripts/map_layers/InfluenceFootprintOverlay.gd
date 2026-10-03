class_name InfluenceFootprintOverlay
extends Node2D

# Impronta temporanea dell'influenza di UN edificio (2026-10-02, richiesta utente — bottone "Mostra influenza" del
# pannello edificio): un cerchio per ogni tipo con raggio > 0 (InfluenceService.get_effective_radius), centrato sul
# centro della microcella dell'edificio, con riempimento trasparente e bordo nel colore del tipo. Dissolvenza lineare
# in DURATION secondi, poi il nodo si toglie da solo — stesso principio di WorldRenderer.highlight_group_territories.
#
# Figlio del container della macrocella dell'edificio (coordinate locali, come gli altri overlay): il cerchio è
# disegnato intero anche oltre i bordi della macrocella, il disegno di un Node2D non viene ritagliato.
#
# Colori e disegno del cerchio (COLORS, building_center_px, draw_influence_circle) sono condivisi con i layer di
# influenza (InfluenceLayerOverlay, 2026-10-02).

const DURATION: float = 3.0
const FILL_ALPHA: float = 0.15
const BORDER_WIDTH: float = 2.0
const CIRCLE_POINTS: int = 96
const COLORS := {
	InfluenceService.InfluenceType.POLITICAL: Color(0.95, 0.75, 0.15),
	InfluenceService.InfluenceType.CULTURAL: Color(0.65, 0.35, 0.90),
	InfluenceService.InfluenceType.RELIGIOUS: Color(0.95, 0.35, 0.20),
}

# Centro (px, locali al container) e raggi in px per tipo, risolti una volta in show_building: l'impronta è una
# fotografia del momento del clic.
var _center: Vector2 = Vector2.ZERO
var _radii_px: Dictionary = {}
var _remaining: float = 0.0
# Anteprima al passaggio del mouse (2026-10-02): nessuna dissolvenza né scadenza, la toglie chi l'ha creata.
var persistent: bool = false


# Centro della microcella di `building` in pixel, nelle coordinate locali del container della macrocella
# `origin_macro_coords` (macrocelle diverse: offset di World.WIDTH microcelle per macrocella).
static func building_center_px(building: Building, origin_macro_coords: Vector2i) -> Vector2:
	var macro_offset := Vector2(Vector2i(building.macro_x, building.macro_y) - origin_macro_coords) * World.WIDTH
	return (Vector2(building.micro_x, building.micro_y) + Vector2(0.5, 0.5) + macro_offset) * float(MicroCellRenderer.CELL_SIZE)


# Raggio effettivo in pixel dell'influenza `influence_type` di `building` (0 = nessuna).
static func radius_px(building: Building, influence_type: InfluenceService.InfluenceType) -> float:
	return float(InfluenceService.get_effective_radius(building, influence_type)) * float(MicroCellRenderer.CELL_SIZE)


# Cerchio di influenza: riempimento trasparente e bordo nel colore del tipo, entrambi scalati da `fade` (1.0 = pieno).
static func draw_influence_circle(
	canvas: CanvasItem, center: Vector2, radius: float, influence_type: InfluenceService.InfluenceType, fade: float = 1.0
) -> void:
	var color: Color = COLORS.get(influence_type, Color.WHITE)
	canvas.draw_circle(center, radius, Color(color.r, color.g, color.b, FILL_ALPHA * fade))
	canvas.draw_arc(center, radius, 0.0, TAU, CIRCLE_POINTS, Color(color.r, color.g, color.b, fade), BORDER_WIDTH, true)


# `only_type` (2026-10-02, icone di influenza del pannello): solo il cerchio di quel tipo; -1 = tutti i tipi.
func show_building(building: Building, only_type: int = -1) -> void:
	_center = building_center_px(building, Vector2i(building.macro_x, building.macro_y))
	_radii_px.clear()
	for influence_type in InfluenceService.InfluenceType.values():
		if only_type >= 0 and influence_type != only_type:
			continue
		var radius := radius_px(building, influence_type)
		if radius > 0.0:
			_radii_px[influence_type] = radius
	_remaining = DURATION
	queue_redraw()


func _process(delta: float) -> void:
	if persistent:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var fade := 1.0 if persistent else clampf(_remaining / DURATION, 0.0, 1.0)
	for influence_type in _radii_px.keys():
		draw_influence_circle(self, _center, _radii_px[influence_type], influence_type, fade)
