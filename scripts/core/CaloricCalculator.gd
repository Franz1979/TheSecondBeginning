class_name CaloricCalculator
extends RefCounted

const CALORIC_SOURCES_DIR := "res://data/caloric_sources/"


static func get_caloric_source_rules(resource_name: String) -> CaloricSourceRules:
	var path := CALORIC_SOURCES_DIR + resource_name + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as CaloricSourceRules


# Formula generica condivisa da qualsiasi fonte calorica, presente o futura: quantità_base ×
# yield_ratio × seasonal_availability_multiplier[stagione]. Nessuno stock persistente: pura
# funzione della risorsa primaria/sottotipo collegata al momento della chiamata.
static func get_available_units(
	rules: CaloricSourceRules,
	cell: MacroCellData,
	state: MacroCellState,
	primary_resource_type: GameTypes.WorldObjectType,
	season: GameTypes.Season
) -> float:
	var base_quantity := _get_base_quantity(rules, cell, state, primary_resource_type)
	return base_quantity * rules.yield_ratio * rules.seasonal_availability_multiplier[season]


static func get_available_calories(
	rules: CaloricSourceRules,
	cell: MacroCellData,
	state: MacroCellState,
	primary_resource_type: GameTypes.WorldObjectType,
	season: GameTypes.Season
) -> float:
	return get_available_units(rules, cell, state, primary_resource_type, season) * rules.calories_per_unit


# UNICO punto di ramificazione tra FORAGE (source_subtype vuoto, stateless) e le fonti a
# sottotipo (es. frutti): per queste ultime subtype_composition è in unità di SPAZIO
# (microcelle), non resource_quantity — va convertito in quantità con la stessa densità usata
# per l'aggregato del resource_type, tramite ResourceCalculator.get_subtype_quantity (identica
# formula già usata da MacroCellDetailPanel per mostrare i sottotipi come quantità). Se il
# sottotipo ha track_age_bands=true, la quantità non è più un blocco unico ugualmente produttivo:
# va pesata per fascia d'età (vedi _get_age_weighted_quantity sotto); altrimenti (default, es.
# FORAGE e ogni sottotipo non ancora esteso alle age bands) resta la formula piatta di sempre.
static func _get_base_quantity(
	rules: CaloricSourceRules,
	cell: MacroCellData,
	state: MacroCellState,
	primary_resource_type: GameTypes.WorldObjectType
) -> float:
	if rules.source_subtype.is_empty():
		return float(state.get_resource_quantity(primary_resource_type))

	var subtype_rule := ResourceCalculator.get_subtype_rule(primary_resource_type, rules.source_subtype)
	if subtype_rule != null and subtype_rule.track_age_bands:
		return _get_age_weighted_quantity(subtype_rule, cell, state, primary_resource_type, rules.source_subtype)

	var composition := state.get_subtype_composition(primary_resource_type)
	var subtype_space: int = int(composition.get(rules.source_subtype, 0))
	return float(ResourceCalculator.get_subtype_quantity(primary_resource_type, subtype_space, cell))


# Somma pesata per fascia d'età: YOUNG*production_coefficient_young + ADULT*..._adult +
# OLD*..._old, ciascuna convertita da spazio a quantità separatamente (non su un totale
# pre-pesato) con la stessa densità/formula di get_subtype_quantity, cosicché il fallback sopra
# e questo ramo restino coerenti quando i coefficienti sono tutti 1.0.
static func _get_age_weighted_quantity(
	subtype_rule: SubtypeRules,
	cell: MacroCellData,
	state: MacroCellState,
	primary_resource_type: GameTypes.WorldObjectType,
	source_subtype: String
) -> float:
	var age_counts := state.get_age_composition(primary_resource_type, source_subtype)

	var young_quantity := ResourceCalculator.get_subtype_quantity(
		primary_resource_type, int(age_counts.get(GameTypes.AgeBand.YOUNG, 0)), cell
	)
	var adult_quantity := ResourceCalculator.get_subtype_quantity(
		primary_resource_type, int(age_counts.get(GameTypes.AgeBand.ADULT, 0)), cell
	)
	var old_quantity := ResourceCalculator.get_subtype_quantity(
		primary_resource_type, int(age_counts.get(GameTypes.AgeBand.OLD, 0)), cell
	)

	return young_quantity * subtype_rule.production_coefficient_young \
		+ adult_quantity * subtype_rule.production_coefficient_adult \
		+ old_quantity * subtype_rule.production_coefficient_old


# Wrapper di comodo per FORAGE (oggi l'unica fonte caricata): risolve regole e risorsa
# primaria collegata (GRASS) così i chiamanti (es. MacroCellDetailPanel) non devono conoscerla.
# cell è comunque richiesto per uniformità di firma con get_available_units/calories, anche se
# FORAGE (source_subtype vuoto) non lo legge mai in _get_base_quantity.
static func get_forage_available_units(cell: MacroCellData, state: MacroCellState, season: GameTypes.Season) -> float:
	var rules := get_caloric_source_rules("forage")
	if rules == null:
		return 0.0
	return get_available_units(rules, cell, state, GameTypes.WorldObjectType.GRASS, season)


static func get_forage_available_calories(cell: MacroCellData, state: MacroCellState, season: GameTypes.Season) -> float:
	var rules := get_caloric_source_rules("forage")
	if rules == null:
		return 0.0
	return get_available_calories(rules, cell, state, GameTypes.WorldObjectType.GRASS, season)


# Applica la transizione stagionale dello stock persistente (MacroCellState.secondary_resource_stock)
# per fonti con consuming_depletes_primary = false (es. bacche mature) — no-op per FORAGE, che
# resta stateless. Ad ogni cambio di stagione:
#  - se new_season è la cycle_start_season della fonte: reset pieno, il residuo precedente è
#    scartato ("i frutti non si accumulano da un ciclo all'altro");
#  - altrimenti, se il tetto teorico (base_quantity * yield_ratio * multiplier) sale rispetto
#    alla stagione precedente: lo stock guadagna esattamente la differenza tra i due tetti
#    (nuova maturazione, non un secondo reset pieno);
#  - se il tetto scende: lo stock decade in proporzione al rapporto tra i moltiplicatori (non tra
#    i tetti, per restare corretto anche quando base_quantity è 0).
static func update_secondary_resource_stock(
	rules: CaloricSourceRules,
	cell: MacroCellData,
	state: MacroCellState,
	primary_resource_type: GameTypes.WorldObjectType,
	previous_season: GameTypes.Season,
	new_season: GameTypes.Season
) -> void:
	if rules.consuming_depletes_primary:
		return

	var before := state.get_secondary_resource_stock(rules.caloric_source_name)
	var base_quantity := _get_base_quantity(rules, cell, state, primary_resource_type)
	var new_ceiling := base_quantity * rules.yield_ratio * rules.seasonal_availability_multiplier[new_season]
	var new_stock: float

	if new_season == rules.cycle_start_season:
		new_stock = new_ceiling
	else:
		var old_ceiling := base_quantity * rules.yield_ratio * rules.seasonal_availability_multiplier[previous_season]
		if new_ceiling >= old_ceiling:
			new_stock = before + (new_ceiling - old_ceiling)
		else:
			var old_multiplier: float = rules.seasonal_availability_multiplier[previous_season]
			var new_multiplier: float = rules.seasonal_availability_multiplier[new_season]
			new_stock = before * (new_multiplier / old_multiplier) if old_multiplier > 0.0 else 0.0

	state.set_secondary_resource_stock(rules.caloric_source_name, new_stock)

	if DebugLogging.ENABLED and state.x == 50 and state.y == 50:
		print("[SECONDARY STOCK %s] %s -> %s: %.2f -> %.2f" % [
			rules.caloric_source_name,
			GameTypes.Season.keys()[previous_season], GameTypes.Season.keys()[new_season],
			before, state.get_secondary_resource_stock(rules.caloric_source_name)
		])


# Per fonti a STOCK persistente (consuming_depletes_primary = false): legge lo stock già
# aggiornato dai checkpoint stagionali (MacroCellState.secondary_resource_stock), non lo
# ricalcola — a differenza di get_available_units/calories (stateless, per fonti come FORAGE).
# Generica per resource_name: aggiungere acorn/fruit non richiede nuove funzioni qui.
static func get_secondary_resource_stock_units(state: MacroCellState, resource_name: String) -> float:
	return state.get_secondary_resource_stock(resource_name)


static func get_secondary_resource_stock_calories(state: MacroCellState, resource_name: String) -> float:
	var rules := get_caloric_source_rules(resource_name)
	if rules == null:
		return 0.0
	return state.get_secondary_resource_stock(resource_name) * rules.calories_per_unit


# TEMPORANEO: nessun consumatore reale (fauna) esiste ancora per le fonti a stock persistente.
# Metodo di debug per simulare manualmente un consumo e verificare a mano la formula sopra —
# richiamabile da codice/pannello di debug, va rimosso quando esisterà un vero consumo automatico.
static func debug_consume_secondary_resource(state: MacroCellState, resource_name: String, amount: float) -> void:
	var before := state.get_secondary_resource_stock(resource_name)
	state.set_secondary_resource_stock(resource_name, before - amount)
	if DebugLogging.ENABLED:
		print("[SECONDARY STOCK DEBUG CONSUME] %s: %.1f -> %.1f (consumo %.1f)" % [
			resource_name, before, state.get_secondary_resource_stock(resource_name), amount
		])
