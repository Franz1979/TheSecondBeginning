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
	state: MacroCellState,
	primary_resource_type: GameTypes.WorldObjectType,
	season: GameTypes.Season
) -> float:
	var base_quantity := _get_base_quantity(rules, state, primary_resource_type)
	return base_quantity * rules.yield_ratio * rules.seasonal_availability_multiplier[season]


static func get_available_calories(
	rules: CaloricSourceRules,
	state: MacroCellState,
	primary_resource_type: GameTypes.WorldObjectType,
	season: GameTypes.Season
) -> float:
	return get_available_units(rules, state, primary_resource_type, season) * rules.calories_per_unit


# UNICO punto di ramificazione tra FORAGE (oggi) e le future fonti a sottotipo (frutti): il
# resto della formula sopra è identico e condiviso, nessun altro if va aggiunto altrove.
# NB: subtype_composition è in unità di SPAZIO (microcelle), non resource_quantity — quando
# questo ramo servirà davvero per i frutti andrà convertito a densità (stesso pattern di
# MacroCellDetailPanel._update_shrub_subtype_label/_update_tree_subtype_label), il che richiederà
# anche cell.terrain_base/biome/coast_type che questa funzione oggi non riceve (FORAGE non ne
# ha bisogno). Segnalato qui per non dimenticarlo quando arriverà quel momento.
static func _get_base_quantity(
	rules: CaloricSourceRules,
	state: MacroCellState,
	primary_resource_type: GameTypes.WorldObjectType
) -> float:
	if rules.source_subtype.is_empty():
		return float(state.get_resource_quantity(primary_resource_type))
	var composition := state.get_subtype_composition(primary_resource_type)
	return float(composition.get(rules.source_subtype, 0))


# Wrapper di comodo per FORAGE (oggi l'unica fonte caricata): risolve regole e risorsa
# primaria collegata (GRASS) così i chiamanti (es. MacroCellDetailPanel) non devono conoscerla.
static func get_forage_available_units(state: MacroCellState, season: GameTypes.Season) -> float:
	var rules := get_caloric_source_rules("forage")
	if rules == null:
		return 0.0
	return get_available_units(rules, state, GameTypes.WorldObjectType.GRASS, season)


static func get_forage_available_calories(state: MacroCellState, season: GameTypes.Season) -> float:
	var rules := get_caloric_source_rules("forage")
	if rules == null:
		return 0.0
	return get_available_calories(rules, state, GameTypes.WorldObjectType.GRASS, season)
