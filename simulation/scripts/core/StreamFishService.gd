class_name StreamFishService
extends RefCounted

# Pesce dei ruscelli (2026-10-31, richiesta utente — pesca passo 1): pesci per microcella di ruscello, niente totale per
# macrocella. Stateless: quanti pesci al massimo ha ogni microcella si ricava dalla posizione (hash, come il tracciato in
# StreamMicrocellService), e in MacroCellState.stream_fish_taken restano SOLO le microcelle pescate. Il ritorno si
# calcola quando serve dai giorni passati (GameData.get_absolute_day), nessun giro sulle celle.
#   - pozze, insenature e sorgente (tutto ciò che non è un tratto largo 1, StreamMicrocellService.is_narrow): sempre
#     pesce; tratti larghi 1: pesce in una microcella su due;
#   - da MIN_FISH a MAX_FISH pesci per microcella;
#   - un pesce pescato torna dopo RETURN_DAYS giorni (arriva da monte o da valle), uno alla volta fino al massimo.

const MIN_FISH := 12
const MAX_FISH := 15
# Quota di microcelle con pesce nei tratti larghi 1 (su 1000).
const NARROW_FISH_PER_MILLE := 500
const RETURN_DAYS := 20
const _SEED_PRESENCE := 300
const _SEED_AMOUNT := 301


# Pesci al massimo nella microcella `pos` del ruscello della macrocella (macro_x, macro_y); 0 se non è ruscello o se è
# un tratto senza pesce. `stream_positions` = LiveMacroCell.stream_positions (StreamMicrocellService.get_positions).
static func get_max_fish(stream_positions: Dictionary, macro_x: int, macro_y: int, pos: Vector2i) -> int:
	if not stream_positions.has(pos):
		return 0
	var gx := macro_x * World.WIDTH + pos.x
	var gy := macro_y * World.HEIGHT + pos.y
	if StreamMicrocellService.is_narrow(stream_positions, pos):
		if StreamMicrocellService._hash(gx, gy, _SEED_PRESENCE) % 1000 >= NARROW_FISH_PER_MILLE:
			return 0
	return MIN_FISH + StreamMicrocellService._hash(gx, gy, _SEED_AMOUNT) % (MAX_FISH - MIN_FISH + 1)


# Pesci presenti adesso nella microcella, compreso il ritorno dei giorni passati.
static func get_fish(state: MacroCellState, stream_positions: Dictionary, macro_x: int, macro_y: int, pos: Vector2i, day: int) -> int:
	var max_fish := get_max_fish(stream_positions, macro_x, macro_y, pos)
	if max_fish <= 0:
		return 0
	return int(_current(state, pos, max_fish, day)["count"])


# Pesci presenti in ogni microcella del ruscello che ne ha (Vector2i -> int), per il disegno.
static func get_fish_counts(state: MacroCellState, stream_positions: Dictionary, macro_x: int, macro_y: int, day: int) -> Dictionary:
	var counts: Dictionary = {}
	for pos in stream_positions:
		var fish := get_fish(state, stream_positions, macro_x, macro_y, pos, day)
		if fish > 0:
			counts[pos] = fish
	return counts


# Toglie un pesce dalla microcella (la pesca). false se non ce n'è.
static func take_fish(state: MacroCellState, stream_positions: Dictionary, macro_x: int, macro_y: int, pos: Vector2i, day: int) -> bool:
	var max_fish := get_max_fish(stream_positions, macro_x, macro_y, pos)
	if max_fish <= 0:
		return false
	var current := _current(state, pos, max_fish, day)
	if int(current["count"]) <= 0:
		return false
	# Da pieno il conto del ritorno parte da oggi; altrimenti continua quello già in corso.
	var since := day if int(current["count"]) >= max_fish else int(current["since"])
	state.stream_fish_taken[pos] = {"count": int(current["count"]) - 1, "since": since}
	return true


# {"count", "since"}: pesci adesso e giorno da cui conta il prossimo ritorno. Le voci tornate piene restano nel
# dizionario finché la microcella non viene pescata di nuovo: valgono come pieno e sono poche.
static func _current(state: MacroCellState, pos: Vector2i, max_fish: int, day: int) -> Dictionary:
	var entry: Variant = state.stream_fish_taken.get(pos)
	if entry == null:
		return {"count": max_fish, "since": day}
	var since := int(entry["since"])
	var returned := maxi(day - since, 0) / RETURN_DAYS
	var count := int(entry["count"]) + returned
	if count >= max_fish:
		return {"count": max_fish, "since": day}
	return {"count": count, "since": since + returned * RETURN_DAYS}
