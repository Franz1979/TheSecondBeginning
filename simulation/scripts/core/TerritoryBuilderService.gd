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


# Esclude dalla BFS le celle il cui terrain_base è interamente WATER (mare/lago) — non le
# celle con un fiume che attraversa un terreno altrimenti normale (water_type == RIVER senza
# terrain_base == WATER, vedi PresetMapGenerator: il fiume imposta solo water_type, mai
# terrain_base, sulla cella che attraversa). Stesso criterio già usato ovunque nel codebase per
# distinguere "questa macrocella è un corpo d'acqua" (DroughtEventEffectService,
# SeaFloodEventEffectService, WorldProcessors, ResourceCalculator, ...).
# Esclude anche le celle già occupate da un territorio ESISTENTE della STESSA specie
# (species_name, vedi _collect_species_occupied_cells sotto) — gli areali della stessa specie non
# si sovrappongono mai; specie diverse invece possono coesistere sulla stessa cella senza alcun
# vincolo qui (competizione per le risorse, non per "diritto territoriale" — vedi
# TerritoryDynamicsService).
# Se le celle libere adiacenti non bastano a raggiungere cell_count (mappa stretta, mare vicino,
# territorio rivale della stessa specie tutt'intorno), nessun errore: si restituisce un Territory
# con tutte le celle raggiunte, comunque valido. `start` è sempre inclusa a prescindere (è la
# cella scelta esplicitamente dal chiamante, vedi sopra) anche se già occupata da un rivale della
# stessa specie — nessuna validazione su di essa, invariato rispetto a prima di questa modifica.
func build_territory(world: World, start: Vector2i, cell_count: int, species_name: String) -> Territory:
	var occupied: Array[Vector2i] = [start]
	if cell_count <= 1:
		return Territory.new(occupied)

	var species_occupied := _collect_species_occupied_cells(world, species_name, null)

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
			if species_occupied.has(neighbor):
				continue

			occupied.append(neighbor)
			queue.append(neighbor)

	return Territory.new(occupied)


# Espansione annuale del territorio di un gruppo esistente (Step 8 del refactoring fauna): a
# differenza di build_territory sopra (dimensione target nota in anticipo, chiamato solo alla
# creazione del gruppo), qui si aggiunge SEMPRE e SOLO UNA cella per invocazione — l'espansione
# procede per tentativi anno dopo anno (vedi TerritoryDynamicsService), non calcola in anticipo
# quante celle servirebbero davvero. Thin wrapper su find_nearest_free_cell sotto (Step 9: la
# stessa ricerca serve anche a PopulationSplitService per trovare dove fondare il nuovo
# territorio, senza mutare quello del gruppo di origine — da qui l'estrazione). Muta
# territory.occupied_macrocells in place aggiungendo la cella trovata. Ritorna true se una cella è
# stata aggiunta, false se la ricerca non ne trova una raggiungibile (mappa satura, mare, o
# territorio rivale della stessa specie tutt'intorno) — non un errore, il chiamante lascia il
# territorio invariato.
func expand_by_one_cell(world: World, territory: Territory, species_name: String) -> bool:
	var found = find_nearest_free_cell(world, territory, species_name)
	if found == null:
		return false
	territory.occupied_macrocells.append(found)
	return true


# Espande il territorio di fino a n celle in un colpo solo (Step 8b, predatori — vedi
# TerritoryDynamicsService, che sostituisce per loro il passo ±1 annuale degli erbivori con un
# salto diretto alla cella-target calcolata dal criterio di densità). Riusa find_nearest_free_cell
# ad ogni iterazione, che ricalcola centroid/occupied_lookup sul territory aggiornato ad ogni
# chiamata — le celle appena aggiunte in questa stessa invocazione sono quindi già visibili
# all'iterazione successiva, nessuno stato duplicato da tenere sincronizzato a mano. Si ferma
# prima di n se la BFS si esaurisce (mappa satura, mare, o territorio rivale della stessa specie
# tutt'intorno) — non un errore, stessa degradazione graduale di build_territory/
# expand_by_one_cell. Ritorna il numero di celle EFFETTIVAMENTE aggiunte (può essere < n), così
# il chiamante sa se il territorio ha raggiunto il target o si è fermato prima.
func expand_by_n_cells(world: World, territory: Territory, species_name: String, n: int) -> int:
	var added := 0
	while added < n:
		var found = find_nearest_free_cell(world, territory, species_name)
		if found == null:
			break
		territory.occupied_macrocells.append(found)
		added += 1
	return added


# Contrae il territorio di fino a n celle in un colpo solo (Step 8b, predatori — simmetrico a
# expand_by_n_cells sopra). Ricalcola il baricentro ad OGNI rilascio (non una volta sola prima del
# ciclo): rimuovere una cella sposta il baricentro, quindi la cella "più lontana" può cambiare da
# un'iterazione all'altra — stesso principio di TerritoryDynamicsService._contract_by_one_cell,
# qui solo ripetuto n volte. Nessuna conoscenza di min_territory_cells qui: si ferma solo per
# sicurezza quando resta 1 sola cella (mai un territorio vuoto), il rispetto del minimo di specie
# resta responsabilità del chiamante (calcola n di conseguenza). Chiama
# world.release_species_territory(species_name) ad ogni cella rilasciata, stesso motivo di
# _contract_by_one_cell: i gruppi bloccati di questa specie sanno che vale la pena riprovare la
# ricerca di territorio. Ritorna il numero di celle EFFETTIVAMENTE rilasciate (può essere < n se
# il territorio arriva a 1 cella prima).
func contract_by_n_cells(world: World, territory: Territory, species_name: String, n: int) -> int:
	var cells := territory.occupied_macrocells
	var released := 0
	while released < n and cells.size() > 1:
		var centroid := territory.get_centroid()
		var farthest: Vector2i = cells[0]
		var farthest_distance := _manhattan_distance(farthest, centroid)
		for coords in cells:
			var distance := _manhattan_distance(coords, centroid)
			if distance > farthest_distance:
				farthest = coords
				farthest_distance = distance

		cells.erase(farthest)
		world.release_species_territory(species_name)
		released += 1

	return released


static func _manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


# BFS a partire dal baricentro di `territory` (Territory.get_centroid, arrotondato alla cella più
# vicina — un punto puramente esplorativo, non necessariamente una cella occupata o valida),
# stessa esclusione acqua di build_territory, ma ORDINE DELLE DIREZIONI RIMESCOLATO A OGNI
# CHIAMATA (vedi _shuffled_directions sotto) invece del DIRECTIONS fisso di build_territory —
# usare qui lo stesso ordine N/S/O/E costante produceva un bias sistematico verso nord (prima
# direzione della costante, quasi sempre libera a inizio partita): ogni scissione/espansione
# finiva per piazzare la nuova cella a nord della precedente, incatenandosi in una lunga colonna
# verticale invece di distribuirsi in tutte le direzioni (osservato empiricamente su rabbit,
# territorio sempre a 1 cella quindi ogni crescita passa da qui). Randomizzazione pura (RNG
# globale via Array.shuffle), non hash-based: questa chiamata non ha bisogno di riproducibilità
# deterministica tra run con lo stesso seed, a differenza di ResourcePositionService. Le celle già
# in territory.occupied_macrocells vengono attraversate come tappe di passaggio (per raggiungere
# il fronte del territorio) ma non contano mai come candidate. Le celle occupate da un territorio
# RIVALE della STESSA specie (species_name, vedi _collect_species_occupied_cells sotto) sono
# invece trattate come l'acqua: né candidate né tappe di passaggio — la BFS non attraversa mai il
# territorio di un gruppo rivale della stessa specie per raggiungere una cella libera oltre di esso
# (stesso motivo per cui non si può "passare sopra" il mare). Specie diverse restano invece del
# tutto ininfluenti qui, invariato. Pura: non muta `territory`. Ritorna la prima cella libera
# trovata, o null se la BFS si esaurisce senza trovarne una raggiungibile.
func find_nearest_free_cell(world: World, territory: Territory, species_name: String) -> Variant:
	var centroid := territory.get_centroid()
	var occupied_lookup: Dictionary = {}
	for coords in territory.occupied_macrocells:
		occupied_lookup[coords] = true

	var species_occupied := _collect_species_occupied_cells(world, species_name, territory)

	var visited: Dictionary = {centroid: true}
	var queue: Array[Vector2i] = [centroid]
	var head := 0

	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		for direction in _shuffled_directions():
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
			if species_occupied.has(neighbor):
				continue

			return neighbor

	return null


# Copia di DIRECTIONS mescolata con l'RNG globale (Array.shuffle, non hash-based: questa ricerca
# non richiede riproducibilità deterministica tra run con lo stesso seed, a differenza di
# ResourcePositionService). Richiamata ad ogni nodo processato dal while loop di
# find_nearest_free_cell sopra, non una volta sola per chiamata — un solo shuffle per l'intera
# BFS lascerebbe comunque un ordine di preferenza fisso per tutta la ricerca di UNA singola
# espansione/scissione (rilevante per i territori multi-cella, dove il fronte libero può essere a
# più di un livello di distanza dal baricentro); rimescolare a ogni nodo elimina qualunque
# direzione preferenziale residua, non solo tra una chiamata e l'altra.
func _shuffled_directions() -> Array[Vector2i]:
	var directions := DIRECTIONS.duplicate()
	directions.shuffle()
	return directions


# Raccoglie in un Dictionary[Vector2i, bool] tutte le occupied_macrocells dei gruppi ESISTENTI
# della stessa specie (species_name) in world.population_groups, escludendo `exclude_territory`
# per riferimento di oggetto — il territorio del gruppo stesso che sta espandendo (expand_by_one_
# cell) non può mai risultare "occupato da un rivale"; null per build_territory, dove il gruppo
# non esiste ancora e quindi non c'è nulla da autoescludere. Specie diverse da species_name non
# contribuiscono mai a questo insieme (nessun vincolo cross-specie, per design).
func _collect_species_occupied_cells(
	world: World, species_name: String, exclude_territory: Territory
) -> Dictionary:
	var occupied: Dictionary = {}
	for group in world.population_groups:
		if group.species_name != species_name:
			continue
		if group.territory == null or group.territory == exclude_territory:
			continue
		for coords in group.territory.occupied_macrocells:
			occupied[coords] = true
	return occupied
