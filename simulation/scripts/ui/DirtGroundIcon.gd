class_name DirtGroundIcon
extends Control

# Icona del terreno in terra battuta per il bottone in BuildBar (2026-09-19, richiesta utente —
# "schiarisci l'icona e falla dello stesso colore di sfondo del renderer"; poi "togli il bordo"):
# un quadrato dello STESSO colore base del rendering (DirtGroundPattern.BASE_COLOR) con le stesse
# macchie (prima variante), a tutto slot: nessun margine né contorno, così non ha una cornice come
# DepositSiteIcon (che ha bordo e sacchi) e le due icone non si confondono. Control minimale, solo
# _draw(), stesso schema di PebbleCircleIcon/DepositSiteIcon.

const PATTERN_VARIANT: int = 0


func _ready() -> void:
	# IGNORE: puro disegno, i click devono raggiungere il Button sotto (vedi PebbleCircleIcon).
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var side: float = minf(size.x, size.y)
	var origin: Vector2 = size / 2.0 - Vector2(side, side) / 2.0
	draw_rect(Rect2(origin, Vector2(side, side)), DirtGroundPattern.BASE_COLOR)
	for speckle in DirtGroundPattern.speckles(PATTERN_VARIANT):
		draw_circle(origin + Vector2(speckle["x"], speckle["y"]) * side, float(speckle["r"]) * side, speckle["color"])
