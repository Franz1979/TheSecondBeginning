class_name TerritoryBuilderService
extends RefCounted

# Costruzione del Territory iniziale di un nuovo PopulationGroup (Step 5 del refactoring fauna:
# territori multi-cella, dimensione FISSA fin dalla creazione — nessuna espansione/restringimento
# nel tempo, quello è Step 8 futuro). BFS semplice, deterministica (ordine di direzione fisso, non
# un pattern organico come ResourcePositionService): parte da `start`, che è sempre inclusa a
# prescindere (è la cella scelta esplicitamente dal chiamante), poi esplora N/S/O/E livello per
# livello finché non raggiunge `cell_count` celle o esaurisce le celle raggiungibili.
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)
]


# Esclude dalla BFS solo le celle il cui terrain_base è interamente WATER (mare/lago) — non le
# celle con un fiume che attraversa un terreno altrimenti normale (water_type == RIVER senza
# terrain_base == WATER, vedi PresetMapGenerator: il fiume imposta solo water_type, mai
# terrain_base, sulla cella che attraversa). Stesso criterio già usato ovunque nel codebase per
# distinguere "questa macrocella è un corpo d'acqua" (DroughtEventEffectService,
# SeaFloodEventEffectService, WorldProcessors, ResourceCalculator, ...).
# Se le celle libere adiacenti non bastano a raggiungere cell_count (mappa stretta, mare vicino),
# nessun errore: si restituisce un Territory con tutte le celle raggiunte, comunque valido.
func build_territory(world: World, start: Vector2i, cell_count: int) -> Territory:
	var occupied: Array[Vector2i] = [start]
	if cell_count <= 1:
		return Territory.new(occupied)

	var visited: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	var head := 0

	while head < queue.size() and occupied.size() < cell_count:
		var current: Vector2i = queue[head]
		head += 1
		for direction in DIRECTIONS:
			if occupied.size() >= cell_count:
				break
			var neighbor: Vector2i = current + direction
			if visited.has(neighbor):
				continue
			visited[neighbor] = true

			var cell := world.get_cell_at(neighbor.x, neighbor.y)
			if cell == null or cell.terrain_base == GameTypes.TerrainBase.WATER:
				continue

			occupied.append(neighbor)
			queue.append(neighbor)

	return Territory.new(occupied)


# Espansione annuale del territorio di un gruppo esistente (Step 8 del refactoring fauna): a
# differenza di build_territory sopra (dimensione target nota in anticipo, chiamato solo alla
# creazione del gruppo), qui si aggiunge SEMPRE e SOLO UNA cella per invocazione — l'espansione
# procede per tentativi anno dopo anno (vedi TerritoryDynamicsService), non calcola in anticipo
# quante celle servirebbero davvero. BFS a partire dal baricentro del territorio attuale
# (Territory.get_centroid, arrotondato alla cella più vicina — un punto puramente esplorativo, non
# necessariamente una cella occupata o valida), stesso ordine di direzioni ed esclusione acqua di
# build_territory; le celle già in territory.occupied_macrocells vengono attraversate come tappe
# di passaggio (per raggiungere il fronte del territorio) ma non contano mai come candidate. Muta
# territory.occupied_macrocells in place aggiungendo la prima cella libera trovata. Ritorna true se
# una cella è stata aggiunta, false se la BFS si esaurisce senza trovarne una raggiungibile (mappa
# satura o mare tutt'intorno) — non un errore, il chiamante lascia il territorio invariato.
func expand_by_one_cell(world: World, territory: Territory) -> bool:
	var centroid := territory.get_centroid()
	var occupied_lookup: Dictionary = {}
	for coords in territory.occupied_macrocells:
		occupied_lookup[coords] = true

	var visited: Dictionary = {centroid: true}
	var queue: Array[Vector2i] = [centroid]
	var head := 0

	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		for direction in DIRECTIONS:
			var neighbor: Vector2i = current + direction
			if visited.has(neighbor):
				continue
			visited[neighbor] = true

			if occupied_lookup.has(neighbor):
				# Già del gruppo: non è un candidato, ma la BFS continua ad esplorare da lì per
				# raggiungere l'eventuale fronte libero oltre il territorio attuale.
				queue.append(neighbor)
				continue

			var cell := world.get_cell_at(neighbor.x, neighbor.y)
			if cell == null or cell.terrain_base == GameTypes.TerrainBase.WATER:
				continue

			territory.occupied_macrocells.append(neighbor)
			return true

	return false
