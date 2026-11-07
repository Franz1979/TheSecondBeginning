class_name ExtractionSourceService
extends RefCounted

# Fonti dell'estrazione (2026-11-04, richiesta utente — Vasellame, passo 3: generalizzare la Quarry). QuarryAction non sa
# cosa sta scavando: chiede qui quanto resta nel bersaglio, cosa si ottiene e dove sta il lavoro già fatto. Una fonte nuova
# aggiunge la sua costante e un caso in ogni funzione. Stateless, funzioni statiche.

const SOURCE_ROCK := "rock"
const SOURCE_CLAY := "clay"


# Risorsa che si ottiene dalla fonte.
static func get_resource_name(source: String) -> String:
	match source:
		SOURCE_ROCK:
			var rules := ResourceCalculator.get_density_rules(GameTypes.WorldObjectType.ROCK)
			return rules.extraction_yield_resource_name if rules != null else ""
		SOURCE_CLAY:
			return ClayDepositService.RESOURCE_NAME
	push_error("ExtractionSourceService.get_resource_name: fonte sconosciuta '%s'." % source)
	return ""


# Fonte da cui si ottiene `resource_name`; "" se non si estrae.
static func source_for_resource(resource_name: String) -> String:
	for source: String in [SOURCE_ROCK, SOURCE_CLAY]:
		if get_resource_name(source) == resource_name:
			return source
	return ""


# Unità di un'estrazione piena; 0 se la fonte non si estrae.
static func units_per_extraction(source: String) -> int:
	match source:
		SOURCE_ROCK:
			var rules := ResourceCalculator.get_density_rules(GameTypes.WorldObjectType.ROCK)
			return maxi(rules.extraction_units_per_extraction, 0) if rules != null and rules.extraction_yield_resource_name != "" else 0
		SOURCE_CLAY:
			return ClayDepositService.UNITS_PER_EXTRACTION
	return 0


# Voci per ResourceChoiceRows: una per ogni fonte conosciuta.
static func list_source_choices() -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	for source in list_known_sources():
		var resource_name := get_resource_name(source)
		choices.append({"id": source, "text": IconRegistry.get_resource_display_name(resource_name), "resource_name": resource_name})
	return choices


# Fonti già conosciute: la risorsa non è bloccata da un'idea non ancora scoperta.
static func list_known_sources() -> Array[String]:
	var sources: Array[String] = []
	for source: String in [SOURCE_ROCK, SOURCE_CLAY]:
		if not TerrainScatteredResourceService.is_resource_locked(get_resource_name(source)):
			sources.append(source)
	return sources


# Quanto resta nel bersaglio (0 = esaurito, o nessun bersaglio in quella posizione).
static func get_remaining(source: String, macro_state: MacroCellState, position: Vector2i) -> int:
	match source:
		SOURCE_ROCK:
			return RockStoneService.get_remaining_stone(macro_state, position)
		SOURCE_CLAY:
			return ClayDepositService.get_remaining(macro_state, position)
	push_error("ExtractionSourceService.get_remaining: fonte sconosciuta '%s'." % source)
	return 0


# Estrae dal bersaglio: {"resource_name", "quantity"}, {} se non si ottiene nulla.
static func extract(source: String, macro_state: MacroCellState, position: Vector2i) -> Dictionary:
	match source:
		SOURCE_ROCK:
			return RockStoneService.extract(macro_state, position)
		SOURCE_CLAY:
			return ClayDepositService.extract(macro_state, position)
	push_error("ExtractionSourceService.extract: fonte sconosciuta '%s'." % source)
	return {}


# Chiave del lavoro già fatto in MacroCellState.cut_work_progress.
static func progress_key(source: String, position: Vector2i) -> String:
	match source:
		SOURCE_ROCK:
			return CutAction.progress_key(GameTypes.WorldObjectType.ROCK, Vector3i(position.x, position.y, 0))
		SOURCE_CLAY:
			return "clay|%d|%d" % [position.x, position.y]
	push_error("ExtractionSourceService.progress_key: fonte sconosciuta '%s'." % source)
	return ""
