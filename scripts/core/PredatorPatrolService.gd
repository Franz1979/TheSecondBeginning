class_name PredatorPatrolService
extends RefCounted

# Pattugliamento giornaliero dei branchi di predatori (Step 2 del piano predatori): calcola un
# percorso di "finestre di caccia" quadrate (PredatorRules.hunting_window_size) che copre l'intero
# territorio del branco seguendone la forma reale — nessun salto attraverso spazio non-territorio,
# valido anche per forme a "L"/"U"/ramificate — e lo scorre avanti e indietro giorno per giorno.
#
# Due fasi a costo molto diverso, tenute deliberatamente nello stesso service perché condividono
# lo stesso stato di gruppo (patrol_route/patrol_index/patrol_direction su PopulationGroup) e la
# stessa unità di dominio, stesso principio con cui altri service di questo codebase (es.
# TerritoryDynamicsService) tengono insieme più fasi correlate di uno stesso meccanismo:
#   Fase A (recompute_route) — O(celle territorio): ricostruisce l'intero percorso da zero.
#   Invocata SOLO quando la forma di group.territory cambia davvero — MAI al checkpoint annuale
#   incondizionatamente, MAI ogni giorno. Tre chiamanti (Step 7): GameScene/GameLoadService per
#   creazione/caricamento di un gruppo (reset_progress rispettivamente true/false, nessuna
#   posizione precedente da preservare), TerritoryDynamicsService per espansione/contrazione di un
#   gruppo esistente e PopulationSplitService per il territorio nuovo del gruppo scisso — questi
#   ultimi due tramite recompute_route_preserving_position (Fase A ter sotto) e recompute_route
#   rispettivamente.
#   Fase B (advance_patrol) — O(1): avanza l'indice sul percorso già calcolato. Invocata ogni
#   giorno, indipendentemente da Fase A.


# Fase A. Ricalcola da zero patrol_route sul gruppo, riflettendo la forma ATTUALE di
# group.territory — mai un aggiornamento incrementale del percorso precedente, sempre una
# ricostruzione completa (economica, vedi _build_route: O(celle territorio), evento raro a
# cadenza annuale/stagionale o alla creazione del gruppo). reset_progress=true (default):
# patrol_index/patrol_direction vengono riazzerati a 0/+1 insieme al percorso — un indice
# relativo al percorso VECCHIO non avrebbe più senso su un percorso nuovo quando la forma del
# territorio è DAVVERO cambiata (espansione/contrazione, nuovo gruppo scisso, creazione dallo
# strumento di debug), i due non condividono alcuna corrispondenza posizionale garantita in quel
# caso. reset_progress=false: usato SOLO da GameLoadService dopo un caricamento — lì il territorio
# non è cambiato affatto rispetto al momento del salvataggio (stesse celle, stesso ordine, stesso
# _build_route deterministico => patrol_route ricostruito qui è byte-per-byte identico a quello
# perso al caricamento, mai persistito per design), quindi patrol_index/patrol_direction
# CARICATI DAL SAVE (storia reale, persistita separatamente — vedi PopulationGroup.gd) restano
# validi sul percorso appena ricostruito e non vanno azzerati: il chiamante li scrive già PRIMA di
# questa chiamata (territorio e i 4 campi persistiti prima, patrol_route ricalcolato dopo, vedi
# GameLoadService), questo flag esiste solo a garantire che questa funzione non li tocchi affatto.
func recompute_route(group: PopulationGroup, rules: PredatorRules, reset_progress: bool = true) -> void:
	group.patrol_route = _build_route(group.territory, rules.hunting_window_size)
	if reset_progress:
		group.patrol_index = 0
		group.patrol_direction = 1


# Fase A ter. Come recompute_route sopra, ma preserva la CONTINUITÀ del pattugliamento invece di
# resettare sempre a 0 — usata quando il territorio cambia forma per espansione/contrazione (Step
# 8b, TerritoryDynamicsService), mai per un territorio del tutto nuovo (lì recompute_route con
# reset_progress=true resta corretto, nessuna posizione precedente da preservare). Cattura la
# cella su cui il branco si trovava (vecchio patrol_route[vecchio patrol_index]) PRIMA di
# sovrascrivere patrol_route, poi cerca nel NUOVO percorso la cella più vicina (distanza
# Chebyshev, stessa metrica di _chebyshev_distance sotto) e riparte da lì invece che dall'indice
# 0 — un salto verso la cella più vicina invece di un teletrasporto logico a un punto arbitrario
# del nuovo percorso. patrol_direction resta sempre +1 dopo un ricalcolo: si autocorregge al primo
# rimbalzo (advance_patrol), non vale la pena dedurlo dal verso precedente. Nessun percorso
# precedente (route vuoto, es. gruppo appena creato) o nuovo percorso vuoto: degrada a un reset
# normale (index 0), stesso comportamento di recompute_route.
func recompute_route_preserving_position(group: PopulationGroup, rules: PredatorRules) -> void:
	var previous_anchor: Vector2i = Vector2i.ZERO
	var has_previous_anchor := false
	if group.patrol_route.size() > 0:
		var safe_index: int = clamp(group.patrol_index, 0, group.patrol_route.size() - 1)
		previous_anchor = group.patrol_route[safe_index]
		has_previous_anchor = true

	group.patrol_route = _build_route(group.territory, rules.hunting_window_size)
	group.patrol_direction = 1

	if not has_previous_anchor or group.patrol_route.is_empty():
		group.patrol_index = 0
		return

	var closest_index := 0
	var closest_distance := _chebyshev_distance(previous_anchor, group.patrol_route[0])
	for i in range(1, group.patrol_route.size()):
		var distance := _chebyshev_distance(previous_anchor, group.patrol_route[i])
		if distance < closest_distance:
			closest_distance = distance
			closest_index = i
	group.patrol_index = closest_index


# Fase B. Rimbalzo agli estremi dell'array (mai un reset a 0 una volta raggiunta la fine) —
# comportamento "avanti e indietro" richiesto, non un loop che ricomincia identico. No-op su
# percorso vuoto o a una sola entry: quest'ultimo caso non dovrebbe mai verificarsi con
# hunting_window_size >= 2 (vedi _single_cell_fallback sotto, produce sempre window_size² >= 4
# varianti distinte anche nel caso degenere di territorio a 1 cella), ma resta un guard difensivo
# economico per non dividere per zero / indicizzare fuori range su un array vuoto.
func advance_patrol(group: PopulationGroup) -> void:
	var route := group.patrol_route
	if route.size() <= 1:
		return

	group.patrol_index += group.patrol_direction
	if group.patrol_index >= route.size() - 1:
		group.patrol_index = route.size() - 1
		group.patrol_direction = -1
	elif group.patrol_index <= 0:
		group.patrol_index = 0
		group.patrol_direction = 1


# Costruisce il percorso completo per un territorio. Caso degenere a 1 sola cella (es. territorio
# appena creato per un gruppo scisso, vedi Territory.from_single_cell) -> fallback dedicato (vedi
# _single_cell_fallback), altrimenti: componenti connesse -> DFS con backtracking esplicito per
# componente -> selezione con backfill obbligatorio sull'ultima occorrenza (vedi
# _select_with_backfill). window_size funge anche da stride di selezione — il valore più permissivo
# per cui la copertura resta comunque garantita senza buchi (finestre successive si toccano o si
# sovrappongono in entrambi gli assi), nessun campo dedicato separato necessario.
func _build_route(territory: Territory, window_size: int) -> Array[Vector2i]:
	var cells := territory.occupied_macrocells
	if cells.is_empty():
		return []
	if cells.size() == 1:
		return _single_cell_fallback(cells[0], window_size)

	var occupied_lookup: Dictionary = {}
	for coords in cells:
		occupied_lookup[coords] = true

	# Ogni entry: {"start": Vector2i, "size": int} — basta un rappresentante per componente (la DFS
	# sotto, vincolata a occupied_lookup, non può mai attraversare il confine tra due componenti
	# per costruzione: se due celle fossero raggiungibili l'una dall'altra sarebbero la STESSA
	# componente) più la sua dimensione, solo per ordinare. Nessun bisogno di materializzare
	# l'elenco intero delle celle di ciascuna componente.
	var components := _find_connected_components(cells, occupied_lookup)
	# Per dimensione decrescente; eventuali pareggi in ordine non specificato — ininfluente ai fini
	# di copertura/vincoli, la scelta è solo per avere un ordine "ragionevole" (le componenti più
	# grandi pattugliate per prime) tra i salti inevitabili da una componente all'altra.
	components.sort_custom(func(a, b): return a["size"] > b["size"])

	var raw_walk: Array[Vector2i] = []
	for component in components:
		var start: Vector2i = component["start"]
		raw_walk.append_array(_dfs_walk(start, occupied_lookup))

	return _select_with_backfill(raw_walk, window_size)


# Flood-fill a 4 vicini SOLO sul lookup del territorio (mai su World/get_cell_at: l'adiacenza che
# conta qui è "fa parte del territorio", non la geografia della mappa) — individua le componenti
# connesse. Necessario perché il territorio non è garantito connesso: TerritoryBuilderService.
# find_nearest_free_cell cerca la cella libera più vicina al CENTROIDE geometrico del territorio
# (Territory.get_centroid, una media di coordinate, esplicitamente non garantita essere una cella
# occupata), e su una forma con una concavità profonda riempita di terra (es. una "U" larga che
# aggira un lago) il centroide può cadere dentro la sacca vuota — la cella libera restituita da lì,
# pur valida, non è detto sia adiacente ad alcuna cella territorio reale, producendo una componente
# isolata. Non un caso puramente teorico sui territori grandi dei predatori (150-300 celle, vedi
# analisi di design) — per questo il resto dell'algoritmo non assume mai connettività.
func _find_connected_components(cells: Array[Vector2i], occupied_lookup: Dictionary) -> Array[Dictionary]:
	var visited: Dictionary = {}
	var components: Array[Dictionary] = []

	for start in cells:
		if visited.has(start):
			continue

		var size := 1
		visited[start] = true
		var queue: Array[Vector2i] = [start]
		var head := 0
		while head < queue.size():
			var current: Vector2i = queue[head]
			head += 1
			for direction in TerritoryBuilderService.DIRECTIONS:
				var neighbor: Vector2i = current + direction
				if visited.has(neighbor) or not occupied_lookup.has(neighbor):
					continue
				visited[neighbor] = true
				size += 1
				queue.append(neighbor)

		components.append({"start": start, "size": size})

	return components


# DFS iterativa con backtracking ESPLICITO (Euler tour dell'albero di copertura) — stack esplicito
# invece di ricorsione, cosicché il passo di ritorno sia un'istruzione visibile (walk.append dopo
# il pop) e non un dettaglio implicito dello stack di chiamata. Ogni passo, discesa o backtrack,
# viene accodato a walk: questo è ciò che garantisce che OGNI cella della componente compaia come
# posizione esplicita almeno una volta nella sequenza grezza (le foglie/vicoli ciechi esattamente
# una volta, i nodi interni due o più volte) — proprietà su cui si basa _select_with_backfill sotto
# per poter scegliere ogni cella come anchor prima o poi, angoli/celle isolate incluse.
func _dfs_walk(start: Vector2i, occupied_lookup: Dictionary) -> Array[Vector2i]:
	var walk: Array[Vector2i] = [start]
	var visited: Dictionary = {start: true}
	var stack: Array[Vector2i] = [start]

	while not stack.is_empty():
		var current: Vector2i = stack[stack.size() - 1]
		var descended := false
		for direction in TerritoryBuilderService.DIRECTIONS:
			var neighbor: Vector2i = current + direction
			if visited.has(neighbor) or not occupied_lookup.has(neighbor):
				continue
			visited[neighbor] = true
			stack.append(neighbor)
			walk.append(neighbor)
			descended = true
			break

		if not descended:
			stack.pop_back()
			if not stack.is_empty():
				walk.append(stack[stack.size() - 1])

	return walk


# Selezione con backfill obbligatorio — sostituisce un semplice campionamento "una cella ogni
# stride posizioni", scartato in fase di analisi perché opera sull'indice grezzo senza sapere se
# quella è l'unica occorrenza di una cella: una cella-foglia con una sola occorrenza il cui indice
# non cade sullo stride sparirebbe per sempre, mai diventando anchor. Qui invece ogni cella diversa
# di raw_walk viene selezionata come anchor ESATTAMENTE una volta (mai più, vedi `selected`): o
# opportunisticamente, quando la distanza Chebyshev dall'ultimo anchor selezionato è già >= stride
# (il caso comune, dà lo spaziamento voluto), o OBBLIGATORIAMENTE al suo ultimo passaggio nella
# sequenza grezza se non è mai stata selezionata prima — garanzia che regge sempre, comprese le
# celle-foglia con una sola occorrenza (la loro unica occorrenza È la loro ultima per definizione).
# Costo accettato: vicino ai vicoli ciechi il passo tra un anchor forzato e il precedente può
# superare lo stride nominale — il branco "scatta" verso la punta del ramo invece di avvicinarcisi
# gradualmente. Non viola alcun vincolo (il movimento resta comunque sempre dentro il grafo di
# adiacenza reale del territorio), solo un'accelerazione locale accettata vicino alle estremità.
func _select_with_backfill(raw_walk: Array[Vector2i], stride: int) -> Array[Vector2i]:
	var last_occurrence: Dictionary = {}
	for i in range(raw_walk.size()):
		last_occurrence[raw_walk[i]] = i

	var route: Array[Vector2i] = []
	var selected: Dictionary = {}
	var has_last_selected := false
	var last_selected := Vector2i.ZERO

	for i in range(raw_walk.size()):
		var cell: Vector2i = raw_walk[i]
		if selected.has(cell):
			continue

		var far_enough: bool = (
			not has_last_selected
			or _chebyshev_distance(last_selected, cell) >= stride
		)
		var last_chance: bool = i == int(last_occurrence[cell])

		if far_enough or last_chance:
			route.append(cell)
			selected[cell] = true
			last_selected = cell
			has_last_selected = true

	return route


# Fallback per il caso degenere di territorio a 1 sola cella (es. un gruppo appena scisso, vedi
# Territory.from_single_cell): un percorso di lunghezza 1 renderebbe impossibile rispettare "mai la
# stessa finestra di ieri" per costruzione geometrica, non per un difetto della selezione sopra
# (con una sola cella disponibile, _select_with_backfill produrrebbe comunque una sola entry).
# L'anchor (vertice top-left) non deve necessariamente COINCIDERE con l'unica cella territorio,
# deve solo produrre una finestra che la contenga ancora — questo lascia window_size² varianti
# valide del vertice top-left attorno a quell'unica cella (per window_size=5, 25 varianti, tutte
# distinte per costruzione: coppie (dx,dy) diverse producono sempre anchor diversi), sufficienti a
# garantire variazione giorno su giorno anche in questo caso limite. La variante dx=0,dy=0 fa
# coincidere l'anchor con la cella stessa, quindi anche qui la cella diventa comunque anchor almeno
# una volta, non solo "contenuta" da finestre altrui.
func _single_cell_fallback(cell: Vector2i, window_size: int) -> Array[Vector2i]:
	var variants: Array[Vector2i] = []
	for dy in range(window_size):
		for dx in range(window_size):
			variants.append(Vector2i(cell.x - dx, cell.y - dy))
	return variants


func _chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return max(abs(a.x - b.x), abs(a.y - b.y))
