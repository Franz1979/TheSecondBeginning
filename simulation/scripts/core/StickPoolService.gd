class_name StickPoolService
extends RefCounted

# Pool di bastoni per lotto/microcella con TREE (2026-09-08, richiesta utente) — capacità
# CONGELATA fino al prossimo checkpoint growth (fine SPRING, giorno 181 — vedi WorldTimeService.
# _run_growth_checkpoint), azzerata (non cumulata, mai sommata alla precedente) ad ogni nuovo
# checkpoint, calcolata PIGRAMENTE solo quando la macrocella viene effettivamente ridisegnata
# (chiamata da GameScene/MacroCellScene._refresh_resource_visuals) — stesso principio "lazy" già
# in uso per StonePositionService/VegetationPositionService, MAI un secondo sweep globale come
# growth/mortality (gli unici checkpoint che toccano OGNI macrocella del mondo indipendentemente
# da essere vista o meno, vedi ricognizione LOD).
#
# Un "lotto" è una singola microcella (confermato in ricognizione, 2026-09-08) — stesso spazio di
# MacroCellState.tree_claimed_lots/tree_individual_subtype/tree_virtual_birth_year, nessuna nuova
# unità di granularità introdotta qui.
#
# THIN WRAPPER su VegetationPoolService (2026-09-16, richiesta utente — Step 1 estrazione base
# comune per plant_fiber) — l'algoritmo vero (checkpoint/staleness/conteggio maturi/scrittura
# capacity) vive ora in VegetationPoolService.gd, parametrizzato su object_type, riusabile anche per
# SHRUB (plant_fiber, Step 2) e in futuro per bacche/frutti filtrati per subtype. QUESTA classe resta
# per compatibilità dei chiamanti esistenti (GameScene/MacroCellScene/TerrainScatteredResourceService,
# nessuno dei quali è stato toccato in questo passo) — stessa firma pubblica, stesso comportamento
# osservabile, verificato con [DBG_POOL] prima/dopo il refactor su un save esistente.

# STICKS_PER_MATURE_TREE RIMOSSA (2026-09-16, richiesta utente) — era una costante hardcoded, ora
# il valore vive su stick.tres (campo units_per_mature_plant, SecondaryResourceRules.gd) e viene
# letto da VegetationPoolService.resolve_units_per_mature_individual ad ogni refresh_macrocell,
# tarabile senza toccare codice.


# Aggiorna macro_state.stick_quantities per ogni lotto TREE la cui capacità è scaduta rispetto
# all'ultimo checkpoint growth passato — no-op (anche il solo confronto Dictionary) per i lotti già
# freschi. Chiamata una volta per macrocella viva ad ogni refresh vegetazione — il costo per una
# macrocella interamente fresca è un confronto per lotto, trascurabile anche ripetuto ad ogni
# refresh (movimento del player incluso).
static func refresh_macrocell(macro_state: MacroCellState, game_data: GameData) -> void:
	VegetationPoolService.refresh_macrocell(
		macro_state, game_data, GameTypes.WorldObjectType.TREE,
		VegetationPoolService.resolve_units_per_mature_individual("stick"),
		macro_state.stick_quantities, [], "stick"
	)


# Giorno assoluto (stessa unità di GameData.get_absolute_day/ExpiredObjectCalculator/
# active_growth_bonuses — anno*DAYS_PER_YEAR+giorno, monotono) dell'ultimo checkpoint growth GIÀ
# PASSATO (fine SPRING, giorno 181 — vedi SeasonCalculator.get_season_end_day). Se oggi siamo già
# oltre il giorno 181 di quest'anno, è quello di quest'anno; altrimenti (checkpoint di quest'anno
# non ancora avvenuto) è quello dell'anno scorso — stesso identico "epoch" per ogni lotto finché
# non scatta il prossimo checkpoint growth, indipendentemente da quante volte la macrocella viene
# ridisegnata nel frattempo.
# Pubblico (non più `_`-prefixed, 2026-09-09) — riusato anche da
# TerrainScatteredResourceService.get_available per lo stesso identico confronto di freschezza
# lotto, invece di duplicare qui la formula. Ora delega a VegetationPoolService (2026-09-16) —
# STESSA firma/STESSO risultato, TerrainScatteredResourceService non cambia.
static func most_recent_growth_checkpoint_absolute_day(game_data: GameData) -> int:
	return VegetationPoolService.most_recent_growth_checkpoint_absolute_day(game_data)
