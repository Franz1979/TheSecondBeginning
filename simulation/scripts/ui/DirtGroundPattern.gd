class_name DirtGroundPattern
extends RefCounted

# Aspetto del terreno in terra battuta (2026-09-19, richiesta utente — "un terreno di colore così
# uniforme è poco credibile, sporcalo con qualche puntino/macchia casuale di altro colore"): UN SOLO
# punto di verità per colore base e macchie, condiviso da MicroCellRenderer (mesh cotte dei tile
# piazzati) e DirtGroundIcon (icona in BuildBar) — l'icona usa lo stesso colore di sfondo del
# rendering, come richiesto.
#
# speckles(variant) restituisce le macchie di UNA variante del tile in spazio unitario [0,1]²
# (x, y, raggio come frazione del lato, colore), deterministiche per numero di variante (seed fisso
# per variante): il renderer cuoce VARIANT_COUNT varianti diverse e ne assegna una a ogni tile per
# hash della posizione, così tile vicini non ripetono lo stesso disegno. Ogni macchia sta interamente
# dentro il tile (centro tenuto a distanza >= raggio dai bordi), quindi tile adiacenti restano
# senza cuciture.

const BASE_COLOR := Color(0.86, 0.77, 0.58, 1.0)
const VARIANT_COUNT: int = 8

# Chiazze larghe a basso contrasto (variazione di tono del terreno) e puntini piccoli più
# contrastati (sassolini, zolle scure, grani chiari).
const BLOB_COUNT: int = 3
const BLOB_RADIUS_MIN: float = 0.10
const BLOB_RADIUS_MAX: float = 0.20
const BLOB_COLORS: Array[Color] = [
	Color(0.80, 0.71, 0.52, 1.0),
	Color(0.90, 0.83, 0.66, 1.0),
]
const SPECK_COUNT: int = 10
const SPECK_RADIUS_MIN: float = 0.02
const SPECK_RADIUS_MAX: float = 0.06
const SPECK_COLORS: Array[Color] = [
	Color(0.62, 0.50, 0.34, 1.0),
	Color(0.68, 0.64, 0.58, 1.0),
	Color(0.72, 0.54, 0.38, 1.0),
	Color(0.94, 0.89, 0.74, 1.0),
]


# Chiazze prima, puntini dopo: l'ordine è quello di disegno (i puntini stanno sopra le chiazze).
# `inner_margin` (2026-09-19, richiesta utente — "tieni le macchie lontane dai bordi irregolari"):
# distanza minima, come frazione del lato, tra il BORDO di ogni macchia e il bordo del tile — 0.0
# (default, l'icona) = fino al bordo; il renderer passa un margine >= della massima rientranza del
# contorno irregolare, così nessuna macchia spunta fuori sagoma. Le sequenze casuali sono le stesse
# per ogni margine (stesso seed): cambia solo l'intervallo in cui cade il centro.
static func speckles(variant: int, inner_margin: float = 0.0) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (variant + 1)
	var result: Array[Dictionary] = []
	for i in range(BLOB_COUNT):
		result.append(_make_speckle(rng, rng.randf_range(BLOB_RADIUS_MIN, BLOB_RADIUS_MAX), BLOB_COLORS, inner_margin))
	for i in range(SPECK_COUNT):
		result.append(_make_speckle(rng, rng.randf_range(SPECK_RADIUS_MIN, SPECK_RADIUS_MAX), SPECK_COLORS, inner_margin))
	return result


static func _make_speckle(rng: RandomNumberGenerator, radius: float, colors: Array[Color], inner_margin: float) -> Dictionary:
	var low: float = inner_margin + radius
	var high: float = 1.0 - inner_margin - radius
	return {
		"x": rng.randf_range(low, high),
		"y": rng.randf_range(low, high),
		"r": radius,
		"color": colors[rng.randi() % colors.size()],
	}
