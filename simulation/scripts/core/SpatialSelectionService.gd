class_name SpatialSelectionService
extends RefCounted

# Service di ricerca spaziale GENERICO (2026-09-10, richiesta utente — estratto da
# WarehouseSelectionService: quell'algoritmo "candidato più vicino che soddisfa una condizione" non
# aveva nulla di specifico per Building/magazzino a parte il criterio di ammissibilità, scritto
# inline nel loop) — stateless, stesso pattern service già in uso nel progetto (TaskFactory/
# BuildingStorageService/TerrainScatteredResourceService): nessuna istanza, funzioni statiche pure.
# Pensato per essere riusato oltre i Building (es. future "aree di lavoro"), quindi NON referenzia
# Building/World da nessuna parte: opera su un Array generico di candidati e un Callable di
# ammissibilità iniettato dal chiamante. WarehouseSelectionService.find_best (vedi lì) resta oggi
# l'unico chiamante reale — ora un thin wrapper che costruisce il predicate giusto e passa
# world.buildings come `candidates`, stesso comportamento di prima di questo refactor.
#
# CONVENZIONE DI POSIZIONE (2026-09-10) — nessun metodo get_position()/property `position` uniforme
# esiste oggi su Building (solo macro_x/macro_y/micro_x/micro_y separati, verificato in ricognizione
# prima di questo refactor): questo service non introduce una nuova interfaccia/classe base per non
# costruire un'astrazione prima che serva davvero (nessun secondo tipo di candidato esiste ancora) —
# assume invece che ogni candidato esponga quei quattro campi (macro_x/macro_y/micro_x/micro_y: int)
# più `id: int`, esattamente come Building oggi, per duck-typing puro (Array non tipizzato, GDScript
# risolve i campi a runtime, nessun cast/interfaccia richiesti). Non è davvero una convenzione
# "presa in prestito da Building": è la convenzione di posizionamento dell'INTERO progetto per
# qualunque oggetto piazzato nella griglia macro/micro (stessa struttura di HumanIndividual.
# home_macro_coords+position, MacroCellState, ecc. — vedi CLAUDE.md) — un futuro candidato "area di
# lavoro" la userebbe comunque, per coerenza col resto del mondo simulato. Se un giorno servisse un
# candidato con una rappresentazione di posizione DIVERSA, quello sarà il momento di introdurre un
# resolver iniettabile (Callable candidato->Vector2) — non costruito ora, nessun caso reale lo
# richiede.


# Trova il candidato più vicino a `origin_position` (già nello spazio locale di `origin_macro_coords`
# — stessa convenzione già in uso da WarehouseSelectionService.find_best) che soddisfa `predicate` ed
# è assente da `excluded_ids`. `predicate: Callable` riceve il candidato (Variant) e ritorna bool —
# nessun'altra assunzione sul suo contenuto, il chiamante decide cosa "ammissibile" significhi (per
# WarehouseSelectionService: capacità residua sufficiente; per un futuro criterio "edificio con
# accepts_thoughts": un semplice controllo su rules.accepts_thoughts, senza toccare questo service).
# Ritorna il candidato stesso o null se nessuno soddisfa entrambi i filtri — nessun cast al tipo
# concreto qui (questo service non conosce Building), il chiamante lo fa (vedi WarehouseSelectionService.
# find_best). Stesso ordine di controllo (esclusi PRIMA del predicate, mai il contrario — coerenza
# con l'algoritmo originale) e stesso criterio di tie-break (primo trovato a parità di distanza
# vince, confronto `<` stretto mai `<=`) di WarehouseSelectionService.find_best PRIMA di questo
# refactor — comportamento immutato, solo spostato qui.
static func find_nearest(
	candidates: Array,
	origin_position: Vector2,
	origin_macro_coords: Vector2i,
	predicate: Callable,
	excluded_ids: Array = []
) -> Variant:
	if candidates == null:
		return null

	var best: Variant = null
	var best_distance_squared := INF
	for candidate in candidates:
		if excluded_ids.has(candidate.id):
			continue
		if not predicate.call(candidate):
			continue
		var candidate_position := _position_relative_to(candidate, origin_macro_coords)
		var distance_squared := origin_position.distance_squared_to(candidate_position)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best = candidate

	return best


# Formula di conversione cross-macrocella + posizione locale, CENTRALIZZATA qui (2026-09-10 — prima
# duplicata identica in WarehouseSelectionService._building_position_relative_to,
# GameScene._debug_test_daydream_task, GameScene._try_assign_unload_command_on_right_click,
# UnloadAction.on_complete — SOLO questo service la usa da questo passo: gli altri tre punti restano
# INVARIATI, fuori scope di questo refactor, un giro successivo li farà convergere qui). `candidate`
# Variant (duck-typed macro_x/macro_y/micro_x/micro_y, vedi nota in testa al file) — stessa identica
# formula/stessa identica unità (World.WIDTH) di prima, nessun comportamento nuovo introdotto.
static func _position_relative_to(candidate: Variant, origin_macro_coords: Vector2i) -> Vector2:
	var macro_offset: Vector2 = Vector2(Vector2i(candidate.macro_x, candidate.macro_y) - origin_macro_coords) * World.WIDTH
	return Vector2(candidate.micro_x, candidate.micro_y) + macro_offset
