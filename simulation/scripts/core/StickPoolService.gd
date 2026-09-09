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
# Estrazione deliberatamente NUOVA (non dal renderer): MicroCellRenderer._resolve_age_band_and_size
# esiste già e fa un calcolo simile, ma legge da CACHE di rendering (age_params costruiti da
# set_tree_age_params, copie sincronizzate delle SubtypeRules — un dettaglio di ottimizzazione del
# renderer), non direttamente da MacroCellState. Questo service va invece dritto a
# ResourceCalculator.get_subtype_rule(TREE, ...) — stessa fonte di verità della cache del renderer,
# ma senza passare dal renderer stesso (che non deve conoscere logica di simulazione/pool
# risorse). Il solo pezzo davvero riusato è AgeBandVisualService.band_for_age, già statico/puro.

const STICKS_PER_MATURE_TREE: int = 3


# Aggiorna macro_state.stick_quantities per ogni lotto TREE la cui capacità è scaduta rispetto
# all'ultimo checkpoint growth passato — no-op (anche il solo confronto Dictionary) per i lotti già
# freschi. Chiamata una volta per macrocella viva ad ogni refresh vegetazione — il costo per una
# macrocella interamente fresca è un confronto per lotto, trascurabile anche ripetuto ad ogni
# refresh (movimento del player incluso).
static func refresh_macrocell(macro_state: MacroCellState, game_data: GameData) -> void:
	var checkpoint_absolute_day := most_recent_growth_checkpoint_absolute_day(game_data)

	var stale_lots: Array = []
	for lot in macro_state.tree_claimed_lots.keys():
		var existing: Dictionary = macro_state.stick_quantities.get(lot, {})
		if existing.is_empty() or int(existing.get("checkpoint_day", -1)) != checkpoint_absolute_day:
			stale_lots.append(lot)
	if stale_lots.is_empty():
		return

	# Raggruppamento in UNA sola passata su tree_virtual_birth_year (stesso principio già in uso in
	# MicroCellRenderer._lot_extent_counts/_count_individuals_per_lot) invece di riscansionare
	# l'intera macrocella per ogni lotto stale — O(individui totali) una volta, non O(lotti stale ×
	# individui totali).
	var individuals_by_lot := _group_individuals_by_lot(macro_state, stale_lots)
	for lot in stale_lots:
		var capacity := _compute_capacity_for_lot(macro_state, individuals_by_lot.get(lot, []), game_data.year)
		macro_state.stick_quantities[lot] = {
			"checkpoint_day": checkpoint_absolute_day,
			"capacity": capacity,
			"harvested": 0,
		}


# Giorno assoluto (stessa unità di GameData.get_absolute_day/ExpiredObjectCalculator/
# active_growth_bonuses — anno*DAYS_PER_YEAR+giorno, monotono) dell'ultimo checkpoint growth GIÀ
# PASSATO (fine SPRING, giorno 181 — vedi SeasonCalculator.get_season_end_day). Se oggi siamo già
# oltre il giorno 181 di quest'anno, è quello di quest'anno; altrimenti (checkpoint di quest'anno
# non ancora avvenuto) è quello dell'anno scorso — stesso identico "epoch" per ogni lotto finché
# non scatta il prossimo checkpoint growth, indipendentemente da quante volte la macrocella viene
# ridisegnata nel frattempo.
# Pubblico (non più `_`-prefixed, 2026-09-09) — riusato anche da
# TerrainScatteredResourceService.get_available per lo stesso identico confronto di freschezza
# lotto, invece di duplicare qui la formula.
static func most_recent_growth_checkpoint_absolute_day(game_data: GameData) -> int:
	var growth_day := SeasonCalculator.get_season_end_day(GameTypes.Season.SPRING)
	if game_data.current_day >= growth_day:
		return game_data.year * GameData.DAYS_PER_YEAR + growth_day
	return (game_data.year - 1) * GameData.DAYS_PER_YEAR + growth_day


static func _group_individuals_by_lot(macro_state: MacroCellState, lots: Array) -> Dictionary:
	var lot_set: Dictionary = {}
	for lot in lots:
		lot_set[lot] = true

	var grouped: Dictionary = {}
	for key in macro_state.tree_virtual_birth_year.keys():
		var lot := Vector2i(key.x, key.y)
		if not lot_set.has(lot):
			continue
		var list: Array = grouped.get(lot, [])
		list.append(key)
		grouped[lot] = list
	return grouped


# Conta gli alberi ADULT/OLD (non YOUNG) tra `individual_keys` (già filtrati a UN solo lotto da
# _group_individuals_by_lot) — stessa combinazione subtype_rule+band_for_age già usata dal renderer
# per la resa visiva, qui applicata direttamente a MacroCellState. capacity = 3 bastoni per albero
# maturo, valore fisso per ora (nessuna variazione per sottotipo/bioma — solo il dato richiesto in
# questo passo).
static func _compute_capacity_for_lot(macro_state: MacroCellState, individual_keys: Array, current_year: int) -> int:
	var mature_count := 0
	for key in individual_keys:
		var subtype_name: String = macro_state.tree_individual_subtype.get(key, "")
		var subtype_rule := ResourceCalculator.get_subtype_rule(GameTypes.WorldObjectType.TREE, subtype_name)
		if subtype_rule == null:
			continue
		var years_lived: int = current_year - int(macro_state.tree_virtual_birth_year[key])
		var age_band: GameTypes.AgeBand = AgeBandVisualService.band_for_age(
			years_lived, subtype_rule.youth_duration_years, subtype_rule.adult_duration_years
		)
		if age_band != GameTypes.AgeBand.YOUNG:
			mature_count += 1
	return STICKS_PER_MATURE_TREE * mature_count
