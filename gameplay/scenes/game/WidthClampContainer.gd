class_name WidthClampContainer
extends Container

# Contenitore che NON propaga la larghezza minima dei figli (2026-10-03, richiesta utente — regola "l'info panel non si
# allarga mai", vedi GameInfoPanel.gd). Dentro le schede di GameInfoTabs sta tra lo ScrollContainer (scorrimento
# orizzontale disattivato) e il contenuto:
#   - larghezza minima 0: il contenuto, per quanto chieda, non allarga lo scroll, la scheda né la sidebar;
#   - altezza minima = la più alta tra quelle dei figli visibili: lo scorrimento verticale resta quello di prima;
#   - ogni figlio occupa esattamente il rettangolo del contenitore, quindi la larghezza della scheda: le etichette a capo
#     vanno a capo su quella larghezza. Un figlio che non può stringersi abbastanza (larghezza minima più grande) resta
#     più largo e viene tagliato a destra (clip_contents).


func _init() -> void:
	clip_contents = true


func _get_minimum_size() -> Vector2:
	var height := 0.0
	for child in get_children():
		var control := child as Control
		if control == null or not control.visible or control.top_level:
			continue
		height = maxf(height, control.get_combined_minimum_size().y)
	return Vector2(0.0, height)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		for child in get_children():
			var control := child as Control
			if control == null or not control.visible or control.top_level:
				continue
			fit_child_in_rect(control, Rect2(Vector2.ZERO, size))
