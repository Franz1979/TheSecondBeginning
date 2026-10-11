class_name ApparelIcon
extends Control

# Icona disegnata del vestiario (2026-10-11, richiesta utente — vestiti, scarpe, monili; icona provvisoria). UNA sola
# icona per tutti i capi di categoria APPAREL: la sagoma segue SecondaryResourceRules.apparel_kind (tunica per il
# corpo, due calzari per i piedi, filo di perline per il collo, anello per il polso, berretto per la testa) e il colore è apparel_color, così
# un capo nuovo ha già un'icona senza toccare codice. Un capo con un'icona propria (immagine in IconRegistry.
# ICON_TEXTURE_DIR o voce in IconRegistry.RESOURCE_ICON_NODES) la usa al posto di questa.
#
# draw_into (statica) è la geometria vera, condivisa con DepositStorageIcons (magazzini e mucchi a terra).

const OUTLINE_DARKEN: float = 0.45
const BEAD_COUNT: int = 7
# Larghezza / altezza della sagoma della tunica, uguale al riquadro dello slot del corpo (ApparelFigure, 36x68).
const TUNIC_ASPECT: float = 36.0 / 68.0

var resource_name: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_resource_into(self, resource_name, Vector2.ZERO, size)


# Disegna il capo `resource_name` dentro il rettangolo (origin, area). false se non è un capo di vestiario.
static func draw_resource_into(canvas: CanvasItem, resource_name: String, origin: Vector2, area: Vector2) -> bool:
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if rules == null or rules.category != SecondaryResourceTypes.Category.APPAREL:
		return false
	draw_into(canvas, origin, area, rules.apparel_kind, rules.apparel_color)
	return true


static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2, kind: int, color: Color) -> void:
	var outline_color := color.darkened(OUTLINE_DARKEN)
	var line_width: float = minf(area.x, area.y) * 0.05
	match kind:
		SecondaryResourceTypes.ApparelKind.BODY:
			_draw_tunic(canvas, origin, area, color, outline_color, line_width)
		SecondaryResourceTypes.ApparelKind.FEET:
			_draw_footwraps(canvas, origin, area, color, outline_color, line_width)
		SecondaryResourceTypes.ApparelKind.NECK:
			_draw_necklace(canvas, origin, area, color, outline_color, line_width)
		SecondaryResourceTypes.ApparelKind.HEAD:
			_draw_headwear(canvas, origin, area, color, outline_color, line_width)
		_:
			_draw_bracelet(canvas, origin, area, color, outline_color, line_width)


# --- Helper condivisi con le icone dedicate dei capi (FurDressIcon, FurCapIcon, WorkedHide*Icon) ---

# Rettangolo (origin, size) con proporzioni `aspect` (larghezza/altezza), il più grande che sta in (origin, area),
# centrato: le vesti alte restano della loro forma anche nei riquadri quadrati di zaino e magazzini.
static func fit_aspect(origin: Vector2, area: Vector2, aspect: float) -> Rect2:
	var fitted := Vector2(minf(area.x, area.y * aspect), minf(area.y, area.x / aspect))
	return Rect2(origin + (area - fitted) * 0.5, fitted)


# Contorno da una sequenza di curve quadratiche in coordinate di disegno: `start`, poi coppie [controllo, fine]
# (come i comandi Q di un path SVG), campionate a `steps` punti ciascuna e mappate nel rettangolo `rect`
# (design_size = dimensione dello spazio di disegno).
static func quad_outline(start: Vector2, segments: Array, design_size: Vector2, rect: Rect2, steps: int = 6) -> PackedVector2Array:
	var points := PackedVector2Array()
	var current := start
	points.append(map_point(current, design_size, rect))
	for segment in segments:
		var control: Vector2 = segment[0]
		var end: Vector2 = segment[1]
		for i in range(1, steps + 1):
			var t := float(i) / float(steps)
			var p := current.lerp(control, t).lerp(control.lerp(end, t), t)
			points.append(map_point(p, design_size, rect))
		current = end
	return points


static func map_point(design_point: Vector2, design_size: Vector2, rect: Rect2) -> Vector2:
	return rect.position + design_point / design_size * rect.size


# Segmenti (coppie [inizio, fine] in coordinate di disegno) disegnati come tratti di pelo.
static func draw_strokes(canvas: CanvasItem, strokes: Array, design_size: Vector2, rect: Rect2, color: Color, width: float) -> void:
	for stroke in strokes:
		canvas.draw_line(map_point(stroke[0], design_size, rect), map_point(stroke[1], design_size, rect), color, width, true)


static func _point(origin: Vector2, area: Vector2, x: float, y: float) -> Vector2:
	return origin + Vector2(x * area.x, y * area.y)


# Tunica lunga (fin sopra le ginocchia, richiesta utente: "non una t-shirt"), maniche corte, scollo a V, orlo svasato,
# vista di fronte; stretta in vita da una cintura. Pensata per il riquadro alto dello slot del corpo (ApparelFigure).
static func _draw_tunic(canvas: CanvasItem, origin: Vector2, area: Vector2, color: Color, outline_color: Color, line_width: float) -> void:
	# Proporzioni fisse (TUNIC_ASPECT): in un riquadro quadrato (zaino, magazzini) la tunica resta della sua forma,
	# centrata, invece di schiacciarsi; nel riquadro alto dello slot del corpo lo riempie.
	var fitted := Vector2(minf(area.x, area.y * TUNIC_ASPECT), minf(area.y, area.x / TUNIC_ASPECT))
	origin += (area - fitted) * 0.5
	area = fitted
	var relative := [
		Vector2(0.333, 0.059), Vector2(0.500, 0.132), Vector2(0.667, 0.059), Vector2(0.833, 0.103),
		Vector2(0.917, 0.221), Vector2(0.806, 0.250), Vector2(0.778, 0.191), Vector2(0.806, 0.485),
		Vector2(0.917, 0.897), Vector2(0.083, 0.897), Vector2(0.194, 0.485), Vector2(0.222, 0.191),
		Vector2(0.194, 0.250), Vector2(0.083, 0.221), Vector2(0.167, 0.103),
	]
	var outline := PackedVector2Array()
	for point in relative:
		outline.append(_point(origin, area, point.x, point.y))
	canvas.draw_colored_polygon(outline, color)
	var closed := outline.duplicate()
	closed.append(outline[0])
	canvas.draw_polyline(closed, outline_color, line_width, true)
	# Cintura in vita.
	canvas.draw_line(_point(origin, area, 0.194, 0.45), _point(origin, area, 0.806, 0.45), outline_color, line_width * 2.0, true)


# Due calzari di pelle affiancati, con il laccio.
static func _draw_footwraps(canvas: CanvasItem, origin: Vector2, area: Vector2, color: Color, outline_color: Color, line_width: float) -> void:
	for center_x in [0.32, 0.68]:
		var center := _point(origin, area, center_x, 0.55)
		var radius := Vector2(area.x * 0.16, area.y * 0.34)
		var shape := PackedVector2Array()
		for i in range(20):
			var angle := TAU * float(i) / 20.0
			shape.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
		canvas.draw_colored_polygon(shape, color)
		var closed := shape.duplicate()
		closed.append(shape[0])
		canvas.draw_polyline(closed, outline_color, line_width, true)
		canvas.draw_line(center + Vector2(-radius.x, -radius.y * 0.2), center + Vector2(radius.x, -radius.y * 0.2), outline_color, line_width, true)


# Filo di perline ad arco.
static func _draw_necklace(canvas: CanvasItem, origin: Vector2, area: Vector2, color: Color, outline_color: Color, line_width: float) -> void:
	var center := _point(origin, area, 0.5, 0.28)
	var radius := Vector2(area.x * 0.34, area.y * 0.48)
	var string_points := PackedVector2Array()
	for i in range(17):
		var angle := PI * float(i) / 16.0
		string_points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	canvas.draw_polyline(string_points, outline_color, line_width, true)
	var bead_radius: float = minf(area.x, area.y) * 0.08
	for i in range(BEAD_COUNT):
		var angle := PI * (0.12 + 0.76 * float(i) / float(BEAD_COUNT - 1))
		var bead := center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)
		canvas.draw_circle(bead, bead_radius, color)
		canvas.draw_arc(bead, bead_radius, 0.0, TAU, 12, outline_color, line_width * 0.6, true)


# Anello spesso con tre perline.
static func _draw_bracelet(canvas: CanvasItem, origin: Vector2, area: Vector2, color: Color, outline_color: Color, line_width: float) -> void:
	var center := _point(origin, area, 0.5, 0.5)
	var radius: float = minf(area.x, area.y) * 0.30
	canvas.draw_arc(center, radius, 0.0, TAU, 32, color, line_width * 3.0, true)
	canvas.draw_arc(center, radius + line_width * 1.5, 0.0, TAU, 32, outline_color, line_width * 0.6, true)
	canvas.draw_arc(center, radius - line_width * 1.5, 0.0, TAU, 32, outline_color, line_width * 0.6, true)
	var bead_radius: float = minf(area.x, area.y) * 0.08
	for i in range(3):
		var angle := PI * (0.25 + 0.25 * float(i))
		var bead := center + Vector2(cos(angle), sin(angle)) * radius
		canvas.draw_circle(bead, bead_radius, color.lightened(0.25))
		canvas.draw_arc(bead, bead_radius, 0.0, TAU, 12, outline_color, line_width * 0.6, true)


# Berretto di pelle a cupola con la tesa, vista di fronte.
static func _draw_headwear(canvas: CanvasItem, origin: Vector2, area: Vector2, color: Color, outline_color: Color, line_width: float) -> void:
	var center := _point(origin, area, 0.5, 0.66)
	var radius := Vector2(area.x * 0.32, area.y * 0.42)
	var dome := PackedVector2Array()
	for i in range(17):
		var angle := PI + PI * float(i) / 16.0
		dome.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	canvas.draw_colored_polygon(dome, color)
	var closed := dome.duplicate()
	closed.append(dome[0])
	canvas.draw_polyline(closed, outline_color, line_width, true)
	var brim := Rect2(_point(origin, area, 0.10, 0.64), Vector2(area.x * 0.80, area.y * 0.12))
	canvas.draw_rect(brim, color.darkened(0.15))
	canvas.draw_rect(brim, outline_color, false, line_width)
