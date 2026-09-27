class_name WorkAreaDragPreview
extends Node2D

# Anteprima del rettangolo durante il disegno di una zona di lavoro (2026-09-27, richiesta utente — modalità "disegna
# area" di GameScene): stesso disegno delle zone (WorkAreaOverlay.draw_work_area_rect). Le misure (es. "7×4") sono
# un'etichetta in spazio schermo (MapScreenLabels) sull'angolo in alto a sinistra, nitida a qualunque zoom e aggiornata
# a ogni frame. Figlio del container della macrocella in cui è iniziato il trascinamento.

const PREVIEW_COLOR := Color(1.0, 1.0, 1.0, 1.0)

var _rect: Rect2i = Rect2i()
var _screen_labels: MapScreenLabels = null


func _ready() -> void:
	_screen_labels = MapScreenLabels.new(self)
	add_child(_screen_labels)


func set_rect(rect: Rect2i) -> void:
	_rect = rect
	queue_redraw()


func _process(_delta: float) -> void:
	var items: Array = []
	if _rect.size.x > 0 and _rect.size.y > 0:
		items.append({"text": "%d×%d" % [_rect.size.x, _rect.size.y], "rect": WorkAreaOverlay.rect_to_pixels(_rect)})
	_screen_labels.update_labels(items)


func _draw() -> void:
	if _rect.size.x <= 0 or _rect.size.y <= 0:
		return
	WorkAreaOverlay.draw_work_area_rect(self, _rect, PREVIEW_COLOR)
