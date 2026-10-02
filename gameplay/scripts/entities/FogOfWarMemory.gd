class_name FogOfWarMemory
extends RefCounted

# Storage sparso "quali microcelle della macrocella corrente sono già state viste, e quando"
# (fog of war — vedi FogOfWarRenderer.gd per come viene consumato). Nessun tier di dettaglio
# qui (Step 3): un solo timestamp per posizione, non ancora terreno/risorse/esatto separati.
#
# Chiave = coordinate microcella LOCALI alla macrocella PROPRIETARIA di questa istanza (Vector2i)
# — nessun namespacing multi-macrocella qui dentro: ogni macrocella (vedi GameScene.
# fog_of_war_memories, Dictionary[Vector2i coord_macro, FogOfWarMemory]) ha la propria istanza
# indipendente, una per cella, mai condivisa. Valore = absolute_day (GameData.get_absolute_day())
# al momento dell'ultimo avvistamento.
#
# UN SOLO timestamp per cella serve oggi a TUTTI E TRE i tier di decadimento (vedi
# is_terrain_fresh/is_resource_fresh/is_detail_fresh sotto) — "vista" è un evento unico, non
# per-tier: chi guarda una cella la osserva sempre per intero (terreno, risorse e dettaglio
# insieme), quindi un solo mark_seen basta. Se in futuro servirà un "rinfresco parziale" (es. il
# player passa di sfuggita e coglie solo il terreno senza osservare bene le risorse/il dettaglio
# — uno sguardo fugace vs. una sosta prolungata), questo dizionario dovrà diventare UNO PER TIER
# (last_seen_terrain_by_position, last_seen_resource_by_position, ecc.) invece di condiviso — non
# farlo ora, è scope futuro: oggi ogni avvistamento rinfresca sempre tutti e tre i tier insieme.
#
# Posseduta da GameScene (non da FogOfWarRenderer, che riceve solo un riferimento via setup()),
# UNA per macrocella dentro GameScene.fog_of_war_memories — sopravvive lì per tutta la sessione
# anche quando la macrocella esce dal set vivo (streaming multi-cella, vedi LiveMacroCell), e
# viaggia tra scene tramite GameSettings.active_fog_of_war_memories (stesso canale di handoff già
# in uso per active_world/active_game_data). Persistita su salvataggio da GameSaveService/
# GameLoadService (sezione "fog_of_war" del JSON) — legge/scrive direttamente last_seen_by_
# position, nessun metodo di (de)serializzazione dedicato qui, stesso pattern già in uso per
# MacroCellState (i due servizi toccano sempre i campi pubblici direttamente).
var last_seen_by_position: Dictionary = {} # Vector2i -> int (absolute_day)

# Pavimento delle zone di lavoro (2026-10-01, richiesta utente): microcelle dentro una WorkArea di questa macrocella
# (Vector2i -> true), ricostruite da GameScene._refresh_work_area_fog_floor SOLO quando cambiano le zone o la macrocella
# si attiva. Per queste posizioni, se già viste almeno una volta, terreno e risorse restano sempre "freschi" (livello 2:
# risorse visibili, animali no — is_detail_fresh non lo guarda) e prune_stale non le cancella. Nessun nuovo stato:
# solo una ricerca in più nel Dictionary, e solo quando la memoria normale è già scaduta. Non salvato (si ricava dalle
# zone).
var floor_positions: Dictionary = {}


func mark_seen(pos: Vector2i, absolute_day: int) -> void:
	last_seen_by_position[pos] = absolute_day


func has_ever_been_seen(pos: Vector2i) -> bool:
	return last_seen_by_position.has(pos)


# Decadimento multi-livello (Step 3): tre getter distinti, uno per tier, invece dell'unico
# is_still_fresh dello Step 2 — anche se oggi condividono la stessa implementazione (stesso
# last_seen_by_position, stessa formula), restano tre metodi separati apposta: se in futuro il
# dizionario si sdoppierà per tier (vedi commento sopra su last_seen_by_position), solo il corpo
# di questi tre dovrà cambiare, non ogni punto in cui FogOfWarRenderer li chiama. Tutti pigri
# (calcolati ad ogni chiamata, nessun processo che ticchetta) e senza mutazione — nessuna
# rimozione dell'entry quando scade, stesso principio già motivato per is_still_fresh: mark_seen
# resta l'unico scrittore, il volume dati è irrilevante, "liberare memoria" non è un problema
# reale da risolvere qui.
#
# Le tre soglie arrivano da chi chiama (vedi FogOfWarRenderer.terrain_memory_days/
# resource_memory_days/detail_memory_days): questa classe resta agnostica sul PERCHÉ di quei
# numeri (in futuro modificabili da tech/edifici, Step 4) — sa solo confrontare il timestamp
# grezzo che possiede con la soglia che le viene data.
func is_terrain_fresh(pos: Vector2i, current_absolute_day: int, terrain_memory_days: int) -> bool:
	return _is_within_memory(pos, current_absolute_day, terrain_memory_days) or _is_floor(pos)


func is_resource_fresh(pos: Vector2i, current_absolute_day: int, resource_memory_days: int) -> bool:
	return _is_within_memory(pos, current_absolute_day, resource_memory_days) or _is_floor(pos)


func is_detail_fresh(pos: Vector2i, current_absolute_day: int, detail_memory_days: int) -> bool:
	return _is_within_memory(pos, current_absolute_day, detail_memory_days)


func _is_within_memory(pos: Vector2i, current_absolute_day: int, memory_duration_days: int) -> bool:
	if not last_seen_by_position.has(pos):
		return false
	return current_absolute_day - last_seen_by_position[pos] <= memory_duration_days


# Pavimento (vedi floor_positions): solo per celle già viste almeno una volta, così una zona disegnata nel nero non
# rivela nulla.
func _is_floor(pos: Vector2i) -> bool:
	return floor_positions.has(pos) and last_seen_by_position.has(pos)


# Sostituisce il pavimento con `positions` (Vector2i -> true) e restituisce le posizioni entrate o uscite, da passare
# a FogOfWarRenderer.mark_positions_dirty. Chiamata solo da GameScene._refresh_work_area_fog_floor.
func set_floor_positions(positions: Dictionary) -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	for pos in floor_positions:
		if not positions.has(pos):
			changed.append(pos)
	for pos in positions:
		if not floor_positions.has(pos):
			changed.append(pos)
	floor_positions = positions
	return changed


# Pulizia periodica (non ad ogni _draw() come i getter sopra, che restano puri e senza mutazione)
# — chiamata da GameScene._maybe_prune_fog_of_war_memories ogni FogOfWarRules.prune_interval_days
# giorni, mai ogni giorno. max_memory_days arriva sempre dal chiamante (vedi FogOfWarCalculator.
# get_max_known_memory_days): DEVE essere il massimo ATTUALMENTE conosciuto, mai un tetto teorico
# futuro più ampio — deciso esplicitamente con l'utente: una soglia di memoria più ampia sbloccata
# in futuro non deve "resuscitare" posizioni già dimenticate qui (stessa logica di una scheda di
# memoria più grande comprata oggi, che non ripristina foto già cancellate ieri). Raccoglie prima
# le chiavi da rimuovere in un array separato invece di cancellare durante l'iterazione stessa del
# Dictionary — GDScript non garantisce la sicurezza di una mutazione a metà `for pos in dict`.
#
# Restituisce le posizioni potate (Step 3.3, 2026-09-03) — GameScene._maybe_prune_fog_of_war_
# memories le inoltra a FogOfWarRenderer.mark_positions_dirty per la macrocella corrispondente,
# se attualmente viva: la texture persistente del renderer non ha modo di sapere altrimenti che
# queste posizioni sono cambiate, vedi FogOfWarRenderer.gd per il perché.
func prune_stale(current_absolute_day: int, max_memory_days: int) -> Array[Vector2i]:
	var stale_positions: Array[Vector2i] = []
	for pos in last_seen_by_position:
		# Pavimento delle zone (2026-10-01): il "visto almeno una volta" deve restare, mai potato.
		if current_absolute_day - last_seen_by_position[pos] > max_memory_days and not floor_positions.has(pos):
			stale_positions.append(pos)
	for pos in stale_positions:
		last_seen_by_position.erase(pos)
	return stale_positions
