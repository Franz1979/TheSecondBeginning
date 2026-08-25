class_name FogOfWarMemory
extends RefCounted

# Storage sparso "quali microcelle della macrocella corrente sono già state viste, e quando"
# (fog of war — vedi FogOfWarRenderer.gd per come viene consumato). Nessun tier di dettaglio
# qui (Step 3): un solo timestamp per posizione, non ancora terreno/risorse/esatto separati.
#
# Chiave = coordinate microcella LOCALI alla macrocella corrente (Vector2i) — nessun
# namespacing multi-macrocella: GameScene mostra sempre una sola macrocella alla volta, quindi
# non serve prefissare le chiavi con le coordinate macro. Valore = absolute_day
# (GameData.get_absolute_day()) al momento dell'ultimo avvistamento.
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
# Posseduta da GameScene (non da FogOfWarRenderer): un futuro step di persistenza dovrà passare
# questo oggetto a GameSaveService/GameLoadService esattamente come già fa con game_data/world —
# quei due servizi toccano sempre oggetti di livello GameScene, mai lo stato interno di un
# renderer. Oggi non persistita (sopravvive solo alla sessione corrente): viene ricreata da zero
# ogni volta che GameScene._ready() gira, stessa non-persistenza già in uso per
# MicroCellRenderer._shrub_birth_year_cache/_tree_birth_year_cache.
var last_seen_by_position: Dictionary = {} # Vector2i -> int (absolute_day)


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
	return _is_within_memory(pos, current_absolute_day, terrain_memory_days)


func is_resource_fresh(pos: Vector2i, current_absolute_day: int, resource_memory_days: int) -> bool:
	return _is_within_memory(pos, current_absolute_day, resource_memory_days)


func is_detail_fresh(pos: Vector2i, current_absolute_day: int, detail_memory_days: int) -> bool:
	return _is_within_memory(pos, current_absolute_day, detail_memory_days)


func _is_within_memory(pos: Vector2i, current_absolute_day: int, memory_duration_days: int) -> bool:
	if not last_seen_by_position.has(pos):
		return false
	return current_absolute_day - last_seen_by_position[pos] <= memory_duration_days
