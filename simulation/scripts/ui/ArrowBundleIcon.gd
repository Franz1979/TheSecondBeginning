class_name ArrowBundleIcon
extends Control

# Icona disegnata "mazzo di frecce" (2026-10-04, richiesta utente; ridisegnata lo stesso giorno perché a 32 px sembrava
# un bastone storto): tre frecce DRITTE in verticale, affiancate e ben separate — asta chiara color legno, punta di
# pietra grigia a triangolo in alto più larga dell'asta, due penne corte per lato in basso — e una legatura di corda
# orizzontale a metà altezza che attraversa le tre aste. Poche forme grandi con un contorno scuro sottile, così si
# legge sul fondo colorato del riquadro a 32 px e resta una sagoma riconoscibile anche nell'icona piccola del magazzino
# sulla mappa. Usa tutto il riquadro meno MARGIN. Solo _draw(), coordinate relative, nessun randf(). draw_into
# (statica) condivisa con DepositStorageIcons.

const SHAFT_COLOR := Color(0.82, 0.66, 0.42, 1.0)
const STONE_COLOR := Color(0.66, 0.65, 0.62, 1.0)
const FLETCHING_COLOR := Color(0.92, 0.92, 0.88, 1.0)
const BINDING_COLOR := Color(0.58, 0.42, 0.22, 1.0)
const OUTLINE_COLOR := Color(0.16, 0.12, 0.08, 1.0)

const MARGIN: float = 0.08
# Centri delle tre frecce (frazioni della larghezza) e misure, tutte in frazioni del lato.
const ARROW_X: Array[float] = [0.24, 0.50, 0.76]
const SHAFT_WIDTH: float = 0.08
const TIP_HALF_WIDTH: float = 0.09
const TIP_TOP: float = MARGIN
const TIP_BASE: float = 0.30
const SHAFT_BOTTOM: float = 1.0 - MARGIN
const FLETCH_TOP: float = 0.72
const FLETCH_SPREAD: float = 0.075
const BINDING_Y: float = 0.54
const BINDING_HALF_HEIGHT: float = 0.045
const OUTLINE: float = 0.025


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(x: float, y: float) -> Vector2: return origin + Vector2(x * area.x, y * area.y)
	var unit: float = minf(area.x, area.y)
	# Tutto in proporzione al lato, come le altre icone: nell'icona piccola del magazzino sulla mappa (lato ~2 px) le tre
	# aste restano separate e la sagoma resta quella del riquadro grande.
	var outline: float = unit * OUTLINE
	var shaft_width: float = unit * SHAFT_WIDTH
	for x in ARROW_X:
		# Asta: prima il bordo scuro, poi il legno chiaro sopra.
		var shaft_top: Vector2 = p.call(x, TIP_BASE - 0.02)
		var shaft_bottom: Vector2 = p.call(x, SHAFT_BOTTOM)
		canvas.draw_line(shaft_top, shaft_bottom, OUTLINE_COLOR, shaft_width + outline * 2.0)
		canvas.draw_line(shaft_top, shaft_bottom, SHAFT_COLOR, shaft_width)
		# Penne: due tratti corti per lato, dall'asta verso il basso e in fuori.
		for side in [-1.0, 1.0]:
			for step in [0.0, 0.08]:
				var from: Vector2 = p.call(x, FLETCH_TOP + step)
				var to: Vector2 = p.call(x + side * FLETCH_SPREAD, FLETCH_TOP + step + 0.07)
				canvas.draw_line(from, to, OUTLINE_COLOR, shaft_width * 0.7 + outline * 2.0)
				canvas.draw_line(from, to, FLETCHING_COLOR, shaft_width * 0.7)
		# Punta di pietra a triangolo, più larga dell'asta, con il contorno scuro.
		var tip := PackedVector2Array([
			p.call(x - TIP_HALF_WIDTH, TIP_BASE), p.call(x, TIP_TOP), p.call(x + TIP_HALF_WIDTH, TIP_BASE),
		])
		canvas.draw_colored_polygon(tip, STONE_COLOR)
		var closed_tip := tip.duplicate()
		closed_tip.append(tip[0])
		canvas.draw_polyline(closed_tip, OUTLINE_COLOR, outline)
	# Legatura di corda orizzontale a metà altezza, sopra le tre aste.
	var binding := Rect2(
		p.call(ARROW_X[0] - 0.09, BINDING_Y - BINDING_HALF_HEIGHT),
		Vector2((ARROW_X[2] - ARROW_X[0] + 0.18) * area.x, BINDING_HALF_HEIGHT * 2.0 * area.y)
	)
	canvas.draw_rect(binding.grow(outline), OUTLINE_COLOR)
	canvas.draw_rect(binding, BINDING_COLOR)
