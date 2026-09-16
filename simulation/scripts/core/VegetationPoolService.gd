class_name VegetationPoolService
extends RefCounted

# Base comune per i pool "risorsa a terra per lotto/microcella derivata da individui maturi di un
# tipo di vegetazione" (2026-09-16, richiesta utente — Step 1 del piano plant_fiber) — ESTRATTA da
# StickPoolService.gd (TREE -> stick), che ora è un thin wrapper su questa classe, comportamento
# IDENTICO a prima (nessun cambio per gli stick, verificato dal player con [DBG_POOL] prima/dopo
# questo refactor). Parametrizzata su `object_type` (TREE/SHRUB) così lo stesso identico algoritmo
# serve anche a plant_fiber (SHRUB, nessun filtro subtype, Step 2) e in futuro a bacche/frutti
# (SHRUB/TREE filtrati per subtype specifico via `allowed_subtypes`, non ancora usato da nessun
# chiamante oggi — vuoto = "qualunque subtype valido conta", stesso comportamento di stick).
#
# Non tocca in alcun modo TerrainScatteredResourceService/il click destro/il rendering/
# BuildingSiteClearingService: questa classe resta il solo "motore di calcolo capacità", chi la
# chiama (oggi solo StickPoolService) resta responsabile di tutto il resto, esattamente come prima.

# [DBG_POOL] (2026-09-16, richiesta utente) — SOLA STAMPA, nessuna logica toccata. Gated dalla
# categoria RESOURCE_POOL di DebugLogging.gd (2026-09-16, richiesta utente — riordino log di
# debug: prima un const locale DBG_POOL_ENABLED a questo file, default true; ora
# DebugLogging.SHOW_RESOURCE_POOL_LOGS, default false, stesso schema di ogni altra categoria).
# Attivazione: nessun tasto nuovo, stampa da sé ogni volta che refresh_macrocell gira per davvero
# (vedi StickPoolService.gd per i dettagli di quando questo succede in-game).


# Risolve "unità per individuo maturo" (2026-09-16, richiesta utente) dal campo units_per_mature_
# plant sul .tres della risorsa (SecondaryResourceRules.gd), invece della vecchia costante hardcoded
# in StickPoolService/PlantFiberPoolService — tarabile senza toccare codice. `resource_name` è il
# nome file (es. "stick", "plant_fiber"), stessa convenzione di CaloricCalculator.
# get_caloric_source_rules. Campo mancante/.tres non risolvibile/valore <= 0 -> push_warning
# esplicito (MAI un default silenzioso) e ritorna comunque il valore letto così com'è (0 se non
# risolvibile): un valore 0 rende visibile il problema (capacity per lotto sempre 0) invece di
# mascherarlo con un numero che sembra normale.
static func resolve_units_per_mature_individual(resource_name: String) -> int:
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if rules == null:
		push_warning("VegetationPoolService: nessuna SecondaryResourceRules risolvibile per '%s' — units_per_mature_plant non disponibile, uso 0." % resource_name)
		return 0
	if rules.units_per_mature_plant <= 0:
		push_warning("VegetationPoolService: '%s.tres' ha units_per_mature_plant assente o 0 — capacity per lotto risulterà sempre 0 finché non lo valorizzi nel .tres." % resource_name)
	return rules.units_per_mature_plant


# Giorno assoluto dell'ultimo checkpoint growth GIÀ PASSATO (fine SPRING) — ESTRATTA identica da
# StickPoolService (vedi quel file per il commento esteso originale, invariato nel contenuto).
# StickPoolService.most_recent_growth_checkpoint_absolute_day ora delega qui, stessa firma/stesso
# risultato per i chiamanti esterni esistenti (TerrainScatteredResourceService), che non cambiano.
static func most_recent_growth_checkpoint_absolute_day(game_data: GameData) -> int:
	var growth_day := SeasonCalculator.get_season_end_day(GameTypes.Season.SPRING)
	if game_data.current_day >= growth_day:
		return game_data.year * GameData.DAYS_PER_YEAR + growth_day
	return (game_data.year - 1) * GameData.DAYS_PER_YEAR + growth_day


# Aggiorna `quantities` (il Dictionary di destinazione, es. macro_state.stick_quantities — passato
# per riferimento: GDScript tratta i Dictionary come tipo a riferimento, quindi le scritture qui
# dentro sono visibili al chiamante senza bisogno di un valore di ritorno) per ogni lotto di
# `object_type` la cui capacità è scaduta rispetto all'ultimo checkpoint growth — STESSA identica
# logica/STESSO no-op-se-fresco di StickPoolService.refresh_macrocell originale, ora generica.
#
# `debug_label` (2026-09-16) — SOLO per [DBG_POOL] (es. "stick"/"plant_fiber"): "" disattiva la
# stampa per questa chiamata anche con la categoria RESOURCE_POOL accesa, così un futuro chiamante
# che non vuole ancora diagnostica non deve toccare il flag globale.
static func refresh_macrocell(
	macro_state: MacroCellState,
	game_data: GameData,
	object_type: GameTypes.WorldObjectType,
	units_per_mature_individual: int,
	quantities: Dictionary,
	allowed_subtypes: Array = [],
	debug_label: String = ""
) -> void:
	var checkpoint_absolute_day := most_recent_growth_checkpoint_absolute_day(game_data)
	var claimed_lots := _claimed_lots_store(macro_state, object_type)

	var stale_lots: Array = []
	for lot in claimed_lots.keys():
		var existing: Dictionary = quantities.get(lot, {})
		if existing.is_empty() or int(existing.get("checkpoint_day", -1)) != checkpoint_absolute_day:
			stale_lots.append(lot)
	if stale_lots.is_empty():
		if DebugLogging.ENABLED and DebugLogging.SHOW_RESOURCE_POOL_LOGS and debug_label != "":
			_debug_print_pool(macro_state, quantities, debug_label)
		return

	# Raggruppamento in UNA sola passata (stesso principio già in uso nell'originale) invece di
	# riscansionare l'intera macrocella per ogni lotto stale.
	var individuals_by_lot := _group_individuals_by_lot(macro_state, object_type, stale_lots)
	for lot in stale_lots:
		var capacity := _compute_capacity_for_lot(
			macro_state, object_type, individuals_by_lot.get(lot, []), game_data.year,
			units_per_mature_individual, allowed_subtypes
		)
		quantities[lot] = {
			"checkpoint_day": checkpoint_absolute_day,
			"capacity": capacity,
			"harvested": 0,
		}
	if DebugLogging.ENABLED and DebugLogging.SHOW_RESOURCE_POOL_LOGS and debug_label != "":
		_debug_print_pool(macro_state, quantities, debug_label)


# [DBG_POOL] (vedi DebugLogging.SHOW_RESOURCE_POOL_LOGS sopra) — RIVISTO 2026-09-16, richiesta
# utente: il dump completo
# di ogni lotto (versione originale, Step 1) superava il limite della console su macrocelle con
# molti lotti e veniva troncato. Ora: UNA riga di riepilogo (lotti totali, somma capacity, somma
# harvested, quanti lotti hanno capacity>0, quanti hanno harvested>0) + l'elenco dei SOLI lotti con
# harvested>0 (i lotti "intonsi", la stragrande maggioranza in pratica, non producono più una riga
# ciascuno — il riepilogo li copre già nel conteggio). Sola lettura/stampa, nessuna logica toccata.
static func _debug_print_pool(macro_state: MacroCellState, quantities: Dictionary, debug_label: String) -> void:
	var total_capacity := 0
	var total_harvested := 0
	var lots_with_capacity := 0
	var lots_with_harvested := 0
	var harvested_lots: Array = []
	for lot in quantities.keys():
		var entry: Dictionary = quantities[lot]
		var capacity := int(entry.get("capacity", 0))
		var harvested := int(entry.get("harvested", 0))
		total_capacity += capacity
		total_harvested += harvested
		if capacity > 0:
			lots_with_capacity += 1
		if harvested > 0:
			lots_with_harvested += 1
			harvested_lots.append(lot)
	print("[DBG_POOL] macro=(%d,%d) %s_quantities: lotti=%d capacity_totale=%d harvested_totale=%d lotti_con_capacity=%d lotti_con_harvested=%d" % [
		macro_state.x, macro_state.y, debug_label, quantities.size(), total_capacity, total_harvested,
		lots_with_capacity, lots_with_harvested
	])
	for lot in harvested_lots:
		var entry: Dictionary = quantities[lot]
		print("[DBG_POOL]   lotto=%s capacity=%s harvested=%s checkpoint_day=%s" % [
			lot, entry.get("capacity"), entry.get("harvested"), entry.get("checkpoint_day")
		])


# Dispatch TREE/SHRUB sui tre registri per-individuo di MacroCellState — STESSO identico pattern
# (duplicato deliberatamente, non riusato) di IndividualVegetationService._claimed_lots_store/
# _subtype_store/_birth_year_store: quei tre sono `_`-prefixed (privati per convenzione di questo
# progetto) e di proprietà di quella classe, non un'utility condivisa — stesso principio "nessuna
# costante/funzione condivisa tra classi diverse" già seguito ovunque nel codebase (es. Action.gd).
static func _claimed_lots_store(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType) -> Dictionary:
	return macro_state.tree_claimed_lots if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_claimed_lots


static func _subtype_store(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType) -> Dictionary:
	return macro_state.tree_individual_subtype if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_individual_subtype


static func _birth_year_store(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType) -> Dictionary:
	return macro_state.tree_virtual_birth_year if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_virtual_birth_year


static func _group_individuals_by_lot(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType, lots: Array) -> Dictionary:
	var lot_set: Dictionary = {}
	for lot in lots:
		lot_set[lot] = true

	var birth_year_store := _birth_year_store(macro_state, object_type)
	var grouped: Dictionary = {}
	for key in birth_year_store.keys():
		var lot := Vector2i(key.x, key.y)
		if not lot_set.has(lot):
			continue
		var list: Array = grouped.get(lot, [])
		list.append(key)
		grouped[lot] = list
	return grouped


# Conta gli individui ADULT/OLD (non YOUNG) tra `individual_keys` (già filtrati a UN solo lotto) —
# STESSA combinazione subtype_rule+band_for_age dell'originale StickPoolService, ora generica su
# object_type. `allowed_subtypes` vuoto = qualunque subtype VALIDO conta (subtype_rule risolvibile),
# STESSO comportamento esatto di prima per stick — non vuoto = filtro aggiuntivo per un subtype
# specifico (bacche/frutti futuri, non usato da alcun chiamante in questo passo).
static func _compute_capacity_for_lot(
	macro_state: MacroCellState,
	object_type: GameTypes.WorldObjectType,
	individual_keys: Array,
	current_year: int,
	units_per_mature_individual: int,
	allowed_subtypes: Array
) -> int:
	var subtype_store := _subtype_store(macro_state, object_type)
	var birth_year_store := _birth_year_store(macro_state, object_type)
	var mature_count := 0
	for key in individual_keys:
		var subtype_name: String = subtype_store.get(key, "")
		if not allowed_subtypes.is_empty() and not allowed_subtypes.has(subtype_name):
			continue
		var subtype_rule := ResourceCalculator.get_subtype_rule(object_type, subtype_name)
		if subtype_rule == null:
			continue
		var years_lived: int = current_year - int(birth_year_store[key])
		var age_band: GameTypes.AgeBand = AgeBandVisualService.band_for_age(
			years_lived, subtype_rule.youth_duration_years, subtype_rule.adult_duration_years
		)
		if age_band != GameTypes.AgeBand.YOUNG:
			mature_count += 1
	return units_per_mature_individual * mature_count
