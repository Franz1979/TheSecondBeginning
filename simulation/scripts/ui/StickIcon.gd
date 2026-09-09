class_name StickIcon
extends Control

# Icona stilizzata "rami/bastoncini raccolti in natura" per il riquadro risorsa trasportata
# (2026-09-09, richiesta utente — dopo due giri di feedback su emoji: 🥢 leggeva come bacchette da
# tavola/utensile lavorato, 🪵 riservato a un futuro "wood" [materiale da costruzione DISTINTO,
# ancora senza .tres proprio, vedi hut.tres.required_materials] non a "stick" raccolto a terra.
# Nessun emoji Unicode rende bene "rametti sparsi", quindi disegnata a mano — stesso principio già
# seguito per StoneCircleIcon, vedi lì). Control minimale, solo _draw(): riempie il proprio Rect2
# (vedi IconRegistry.get_resource_icon_node, il consumatore, che lo ancora PRESET_FULL_RECT dentro
# lo slot che lo ospita), scala automaticamente con qualunque dimensione senza valori hardcoded.
#
# Tre rametti a linea SPEZZATA (non dritti: un piccolo kink a metà lunghezza dà lettura "ramo",
# non "bacchetta"/riga geometrica), angoli/lunghezze/spessori/colori leggermente diversi tra loro
# per un aspetto "raccolto, non fabbricato" — offset FISSI (mai randf(): un'icona statica non ha
# bisogno di variare tra un redraw e l'altro, stesso principio "nessun unseeded randf()" già
# seguito altrove nel progetto per elementi deterministici).

const STICK_COLOR_MAIN := Color(0.42, 0.30, 0.16, 1.0)
const STICK_COLOR_LIGHT := Color(0.55, 0.40, 0.22, 1.0)
const STICK_COLOR_DARK := Color(0.32, 0.22, 0.11, 1.0)


func _ready() -> void:
	# IGNORE (stesso principio di StoneCircleIcon): puro disegno, mai un bersaglio di input — il
	# tooltip sul riquadro trasportato vive sul CONTENITORE (carried_resource_box), non su questa
	# icona, vedi HumanIndividualInfoPanel._update_carried_resource_box.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	_draw_twig(Vector2(w * 0.18, h * 0.78), Vector2(w * 0.52, h * 0.42), Vector2(w * 0.82, h * 0.20), STICK_COLOR_MAIN, h * 0.09)
	_draw_twig(Vector2(w * 0.15, h * 0.30), Vector2(w * 0.48, h * 0.58), Vector2(w * 0.85, h * 0.75), STICK_COLOR_LIGHT, h * 0.07)
	_draw_twig(Vector2(w * 0.35, h * 0.85), Vector2(w * 0.55, h * 0.50), Vector2(w * 0.68, h * 0.15), STICK_COLOR_DARK, h * 0.06)


# Linea spezzata a due segmenti (start->mid->end) — il kink a `mid` è ciò che distingue un ramo da
# una riga dritta, senza bisogno di una vera texture/mesh per un'icona così piccola.
func _draw_twig(from: Vector2, mid: Vector2, to: Vector2, color: Color, width: float) -> void:
	draw_line(from, mid, color, width, true)
	draw_line(mid, to, color, width, true)
