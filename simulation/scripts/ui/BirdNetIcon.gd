class_name BirdNetIcon
extends Control

# Icona disegnata "rete per uccelli" (2026-11-07, capanna del trappoliere): un accrocchio paleolitico, non un telaio —
# due rami storti e un po' inclinati piantati per terra, una rete di fibra annodata a mano, a maglie irregolari e
# insaccata, legata ai rami con giri di corda, con un paio di capi sfilacciati che pendono. Solo _draw(), coordinate
# relative, nessun randf(): le irregolarità sono scostamenti fissi. draw_into (statica) condivisa con DepositStorageIcons.

const BRANCH_COLOR := Color(0.45, 0.31, 0.17, 1.0)
const BRANCH_DARK_COLOR := Color(0.29, 0.19, 0.10, 1.0)
const NET_COLOR := Color(0.74, 0.64, 0.44, 1.0)
const NET_DARK_COLOR := Color(0.50, 0.41, 0.25, 1.0)

# Rami: punti dal piede alla cima, storti, il sinistro inclinato in fuori, il destro in dentro.
const LEFT_BRANCH := [Vector2(0.20, 0.92), Vector2(0.18, 0.70), Vector2(0.20, 0.48), Vector2(0.15, 0.26), Vector2(0.12, 0.10)]
const RIGHT_BRANCH := [Vector2(0.82, 0.93), Vector2(0.84, 0.72), Vector2(0.80, 0.50), Vector2(0.83, 0.30), Vector2(0.80, 0.12)]
# Rametto laterale spezzato su ciascun ramo (attacco, punta).
const TWIGS := [[Vector2(0.18, 0.60), Vector2(0.08, 0.52)], [Vector2(0.82, 0.40), Vector2(0.92, 0.33)]]
# Griglia dei nodi della rete (4 righe × 5 colonne), già storta: righe più fitte in alto, insaccata al centro in basso.
const KNOTS := [
	[Vector2(0.17, 0.22), Vector2(0.33, 0.20), Vector2(0.49, 0.23), Vector2(0.64, 0.21), Vector2(0.82, 0.25)],
	[Vector2(0.19, 0.38), Vector2(0.34, 0.39), Vector2(0.51, 0.42), Vector2(0.66, 0.38), Vector2(0.81, 0.41)],
	[Vector2(0.19, 0.55), Vector2(0.36, 0.59), Vector2(0.50, 0.62), Vector2(0.67, 0.58), Vector2(0.80, 0.56)],
	[Vector2(0.20, 0.70), Vector2(0.35, 0.77), Vector2(0.52, 0.80), Vector2(0.65, 0.75), Vector2(0.81, 0.71)],
]
# Capi sfilacciati che pendono dal bordo basso (partenza, punta).
const LOOSE_ENDS := [[Vector2(0.35, 0.77), Vector2(0.33, 0.88)], [Vector2(0.52, 0.80), Vector2(0.56, 0.90)]]
# Legature: giri di corda dove la rete tocca i rami.
const LASHINGS := [Vector2(0.16, 0.22), Vector2(0.19, 0.55), Vector2(0.82, 0.25), Vector2(0.80, 0.56)]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna la rete dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(v: Vector2) -> Vector2: return origin + Vector2(v.x * area.x, v.y * area.y)
	var unit: float = minf(area.x, area.y)
	var branch_width: float = unit * 0.07
	var net_width: float = maxf(unit * 0.022, 1.0)

	# Rami dietro alla rete.
	for branch in [LEFT_BRANCH, RIGHT_BRANCH]:
		var points := PackedVector2Array()
		for point in branch:
			points.append(p.call(point))
		canvas.draw_polyline(points, BRANCH_DARK_COLOR, branch_width * 1.35, true)
		canvas.draw_polyline(points, BRANCH_COLOR, branch_width, true)
	for twig in TWIGS:
		canvas.draw_line(p.call(twig[0]), p.call(twig[1]), BRANCH_DARK_COLOR, branch_width * 0.5, true)

	# Rete: fili orizzontali e verticali tra nodi storti, così le maglie vengono irregolari.
	var rows: int = KNOTS.size()
	var columns: int = (KNOTS[0] as Array).size()
	for r in range(rows):
		var row_points := PackedVector2Array()
		for c in range(columns):
			row_points.append(p.call(KNOTS[r][c]))
		canvas.draw_polyline(row_points, NET_COLOR if r > 0 else NET_DARK_COLOR, net_width * (1.6 if r == 0 else 1.0), true)
	for c in range(columns):
		var column_points := PackedVector2Array()
		for r in range(rows):
			column_points.append(p.call(KNOTS[r][c]))
		canvas.draw_polyline(column_points, NET_COLOR, net_width, true)
	# Nodi: puntini più scuri agli incroci interni.
	for r in range(1, rows):
		for c in range(1, columns - 1):
			canvas.draw_circle(p.call(KNOTS[r][c]), unit * 0.018, NET_DARK_COLOR)
	for loose in LOOSE_ENDS:
		canvas.draw_line(p.call(loose[0]), p.call(loose[1]), NET_COLOR, net_width, true)

	# Legature sui rami: due giri di corda di traverso.
	for lashing in LASHINGS:
		var center: Vector2 = p.call(lashing)
		for offset in [-0.022, 0.022]:
			var a: Vector2 = center + Vector2(-unit * 0.05, unit * (offset - 0.015))
			var b: Vector2 = center + Vector2(unit * 0.05, unit * (offset + 0.015))
			canvas.draw_line(a, b, NET_DARK_COLOR, net_width * 1.4, true)
