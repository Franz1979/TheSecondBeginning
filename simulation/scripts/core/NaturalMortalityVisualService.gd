class_name NaturalMortalityVisualService
extends RefCounted

# Traduce la mortalità AGGREGATA già applicata da ResourceMortalityService (vedi
# MacroCellState.last_mortality_loss) in marker "morto" su specifici individui noti — senza mai
# ripetere il decremento aggregato, già avvenuto. Chiamata solo da GameScene (unica scena con
# fog of war/click-detection per-individuo), solo per le celle vive: una cella non viva quando la
# mortalità scatta non riceve marker per quell'anno, l'aggregato resta comunque corretto (stessa
# inconsistenza accettata già discussa per il territorio non osservato).
#
# Criterio di scelta (deciso con l'utente): tra gli individui noti E ancora "freschi" per il fog
# of war (mai tra quelli scaduti — non c'è nulla da aggiornare visivamente lì), quanti riceverne un
# marker è proporzionale a quanta parte del noto è ancora fresca ("se il 30% è fresco, muore
# visivamente il 30% della perdita"); QUALI tra i freschi, a sorteggio puro (nessun criterio di
# età/posizione).
#
# UPDATE: "visto dal fog of war" non è più has_ever_been_seen (permanente, mai decade) ma
# is_resource_fresh (decade oltre FogOfWarRules.resource_memory_days) — deciso con l'utente
# insieme al lavoro di pruning di FogOfWarMemory.last_seen_by_position. NON is_terrain_fresh
# (tentativo iniziale, corretto dall'utente): terrain_memory_days copre solo "che tipo di
# terreno/bioma è questa cella", il tier più grezzo e più lento a scadere di tutti e tre — "quali
# piante c'erano" è invece territorio di resource_memory_days (vedi la mappatura dichiarata in
# FogOfWarRenderer.gd: detail=entità in movimento, resource=vegetazione/risorse a grana media,
# terrain=solo il tipo di cella). Sarebbe incoerente ricordare la morte di un individuo preciso
# più a lungo di quanto si ricordi che lì c'era vegetazione affatto — "morto" è un sottoinsieme
# più fine di "risorse presenti", non può sopravvivere alla scadenza di quest'ultimo. has_ever_
# been_seen resta comunque disponibile su FogOfWarMemory — meccanica non rimossa, solo non più
# invocata da qui.

# Unici due tipi con identità per-individuo (GRASS non ne ha, vedi IndividualVegetationService) —
# gli unici per cui "quale individuo muore" ha senso come domanda.
const MORTAL_INDIVIDUAL_TYPES: Array[GameTypes.WorldObjectType] = [
	GameTypes.WorldObjectType.TREE, GameTypes.WorldObjectType.SHRUB,
]


# Sceglie quali individui noti-e-freschi di object_type devono morire visivamente quest'anno.
# Consuma (cancella) macro_state.last_mortality_loss[object_type] nella stessa chiamata — non va
# mai processato due volte. Ritorna un Array[Vector3i] vuoto se non c'è nulla da fare (nessuna
# perdita registrata, nessun individuo noto, o nessuno di quelli noti è ancora fresco).
# current_absolute_day/terrain_memory_days arrivano dal chiamante (vedi GameScene._apply_natural_
# mortality_visuals) invece di essere ricalcolati qui: stesso principio già in uso per le tre
# soglie passate a FogOfWarMemory.is_*_fresh da FogOfWarRenderer, questa classe non deve sapere da
# dove viene la soglia, solo come applicarla.
static func select_dying_individuals(
	macro_state: MacroCellState,
	fog_of_war_memory: FogOfWarMemory,
	object_type: GameTypes.WorldObjectType,
	current_absolute_day: int,
	resource_memory_days: int
) -> Array:
	var loss: int = int(macro_state.last_mortality_loss.get(object_type, 0))
	macro_state.last_mortality_loss.erase(object_type)
	if loss <= 0 or fog_of_war_memory == null:
		return []

	var birth_year_store: Dictionary = macro_state.tree_virtual_birth_year if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_virtual_birth_year
	var known_individuals: Array = birth_year_store.keys()
	if known_individuals.is_empty():
		return []

	var seen_individuals: Array = []
	for key in known_individuals:
		if fog_of_war_memory.is_resource_fresh(Vector2i(key.x, key.y), current_absolute_day, resource_memory_days):
			seen_individuals.append(key)
	if seen_individuals.is_empty():
		return []

	# Frazione sugli INDIVIDUI noti di questo tipo (non sull'intera macrocella): risponde
	# direttamente a "di quanti individui potrei plausibilmente segnare la morte, quanti ne ho
	# davvero visti", non a "quanta della mappa ho esplorato" (che potrebbe non correlare con dove
	# si trova davvero questa vegetazione).
	var visible_fraction: float = float(seen_individuals.size()) / float(known_individuals.size())
	var marks_needed: int = min(int(round(float(loss) * visible_fraction)), seen_individuals.size())
	if marks_needed <= 0:
		return []

	seen_individuals.shuffle()
	return seen_individuals.slice(0, marks_needed)


# Marca un individuo come morto — stessa identica scrittura di PlayerHarvestService.cut_individual
# (blocco universale + dimenticare età/sottotipo, size_multiplier catturato dal chiamante PRIMA di
# quella cancellazione) ma SENZA ripetere il decremento aggregato: quello lo ha già fatto
# ResourceMortalityService per l'intero anno, prima ancora che select_dying_individuals scegliesse
# quali individui specifici rappresentano quella perdita.
static func kill_individual(
	macro_state: MacroCellState,
	object_type: GameTypes.WorldObjectType,
	individual_key: Vector3i,
	size_multiplier: float,
	current_year: int
) -> void:
	macro_state.vegetation_death_exceptions[individual_key] = {
		"origin_type": object_type,
		"death_year": current_year,
		"size_multiplier": size_multiplier,
	}
	var birth_year_store: Dictionary = macro_state.tree_virtual_birth_year if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_virtual_birth_year
	var subtype_store: Dictionary = macro_state.tree_individual_subtype if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_individual_subtype
	birth_year_store.erase(individual_key)
	subtype_store.erase(individual_key)
