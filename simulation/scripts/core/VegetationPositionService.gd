class_name VegetationPositionService
extends RefCounted

# Frequency/threshold per tipo: GRASS diffusa e quasi "riempitiva" (macchie ampie, soglia
# permissiva), SHRUB intermedia (stessi valori di partenza di stone), TREE concentrata in
# boschetti densi e ben distinti (macchie piccole, soglia selettiva).
const NOISE_PARAMS := {
	GameTypes.WorldObjectType.TREE: {"frequency": 0.07, "threshold": 0.45},
	GameTypes.WorldObjectType.SHRUB: {"frequency": 0.05, "threshold": 0.4},
	GameTypes.WorldObjectType.GRASS: {"frequency": 0.03, "threshold": 0.3},
}

# Ordine di rivendicazione delle celle: dal tipo dominante (TREE) al più diffuso (GRASS),
# così ciascuno prenota le celle migliori del proprio campo di noise prima che il successivo
# scelga tra quelle rimaste libere — nessuna vera contesa, solo una sequenza di priorità. Con
# MIX_TREE_AND_SHRUB=true questo ordine resta il riferimento per GRASS (che esclude comunque
# l'unione di TREE+SHRUB), ma TREE e SHRUB non si escludono più a vicenda — vedi sotto.
const CLAIM_ORDER := [
	GameTypes.WorldObjectType.TREE,
	GameTypes.WorldObjectType.SHRUB,
	GameTypes.WorldObjectType.GRASS,
]

# Interruttore di reversibilità: false ripristina ESATTAMENTE il comportamento precedente (un solo
# `occupied` condiviso lungo CLAIM_ORDER, TREE esclude SHRUB esclude GRASS in sequenza — mai due
# tipi nello stesso lotto). true (default) scollega solo TREE e SHRUB tra loro: ciascuno sceglie
# contro i soli ostacoli fisici passati dal chiamante (stone/river), ignaro dell'altro — possono
# quindi condividere lo stesso lotto (un albero con qualche shrub sotto la chioma, invece di
# macchie sempre pure). GRASS non è toccato da questo interruttore: esclude comunque l'unione di
# quello che TREE e SHRUB hanno scelto, come sempre. TREE e SHRUB usano campi di rumore
# indipendenti (seed diversi, vedi _generate_for_type) quindi le loro macchie si sovrappongono
# solo dove i due campi capitano a coincidere — chiazze pure e chiazze miste convivono senza
# bisogno di una percentuale di mescolanza da tarare a mano. Un solo valore da cambiare per
# tornare al comportamento originale se il risultato visivo non convince.
const MIX_TREE_AND_SHRUB: bool = true


# A differenza di stone, queste posizioni NON vanno mai persistite: quantità e disposizione
# di grass/shrub/tree cambiano ogni anno (growth/encroachment/mortality/migration), quindi
# vanno ricalcolate a ogni apertura della scena a partire dalle quantità correnti. `occupied`
# è opzionale: passare le posizioni stone già generate per non disegnare vegetazione sopra
# le rocce. `current_year` è usato solo da TREE/SHRUB (vedi IndividualVegetationService) per
# il rientro in eleggibilità delle posizioni tagliate; GRASS non ha identità individuale
# (nessuna eccezione di taglio possibile) e continua a chiamare ResourcePositionService
# direttamente. Shape del risultato NON uniforme tra i tipi: result[TREE]/result[SHRUB] sono
# Array[Vector3i] (x, y del lotto + indice individuo locale, granularità per-individuo — vedi
# IndividualVegetationService), result[GRASS] resta Array[Vector2i] (un lotto = un'unica entità
# renderizzata, nessuna suddivisione in individui).
# building_positions (Vector2i -> true, vedi GameScene._building_positions_for_cell) blocca in modo
# PERMANENTE i lotti TREE/SHRUB già rivendicati che ricadono su un edificio, propagato fino a
# IndividualVegetationService._is_blocked — `occupied` da solo non basterebbe: un lotto già in
# tree_claimed_lots/shrub_claimed_lots viene rigenerato a prescindere da `occupied` (vedi commento
# lì). Il chiamante deve comunque unire building_positions ANCHE a `occupied` per GRASS (che non ha
# memoria persistita, si affida solo a `occupied`) e per impedire che un lotto TREE/SHRUB mai
# ancora rivendicato scelga in futuro proprio una cella con un edificio.
func generate_positions(macro_state: MacroCellState, occupied: Dictionary = {}, current_year: int = 0, current_day: int = 0, building_positions: Dictionary = {}) -> Dictionary:
	if MIX_TREE_AND_SHRUB:
		return _generate_positions_mixed(macro_state, occupied, current_year, current_day, building_positions)
	return _generate_positions_sequential(macro_state, occupied, current_year, current_day, building_positions)


# Comportamento originale: un solo occupied condiviso lungo CLAIM_ORDER.
func _generate_positions_sequential(macro_state: MacroCellState, occupied: Dictionary, current_year: int, current_day: int, building_positions: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for resource_type in CLAIM_ORDER:
		result[resource_type] = _generate_for_type(macro_state, resource_type, occupied, current_year, current_day, building_positions)
	return result


# TREE e SHRUB scelgono ciascuno contro un proprio scratch, seminato SOLO dagli ostacoli fisici
# del chiamante — non si vedono a vicenda, possono condividere lo stesso lotto. GRASS resta
# invariato rispetto a entrambi: esclude la loro unione, come nel comportamento sequenziale.
func _generate_positions_mixed(macro_state: MacroCellState, occupied: Dictionary, current_year: int, current_day: int, building_positions: Dictionary) -> Dictionary:
	var result: Dictionary = {}

	var tree_occupied: Dictionary = occupied.duplicate()
	result[GameTypes.WorldObjectType.TREE] = _generate_for_type(macro_state, GameTypes.WorldObjectType.TREE, tree_occupied, current_year, current_day, building_positions)

	var shrub_occupied: Dictionary = occupied.duplicate()
	result[GameTypes.WorldObjectType.SHRUB] = _generate_for_type(macro_state, GameTypes.WorldObjectType.SHRUB, shrub_occupied, current_year, current_day, building_positions)

	var grass_occupied: Dictionary = occupied.duplicate()
	for pos in tree_occupied.keys():
		grass_occupied[pos] = true
	for pos in shrub_occupied.keys():
		grass_occupied[pos] = true
	result[GameTypes.WorldObjectType.GRASS] = _generate_for_type(macro_state, GameTypes.WorldObjectType.GRASS, grass_occupied, current_year, current_day, building_positions)

	# Stesso contratto pubblico del ramo sequenziale: `occupied` del chiamante riceve comunque
	# l'unione di tutto ciò che la vegetazione ha preso, non solo gli ostacoli fisici di partenza.
	for pos in tree_occupied.keys():
		occupied[pos] = true
	for pos in shrub_occupied.keys():
		occupied[pos] = true
	for pos in grass_occupied.keys():
		occupied[pos] = true

	return result


func _generate_for_type(macro_state: MacroCellState, resource_type: GameTypes.WorldObjectType, occupied: Dictionary, current_year: int, current_day: int, building_positions: Dictionary) -> Array:
	var params: Dictionary = NOISE_PARAMS[resource_type]

	if resource_type == GameTypes.WorldObjectType.TREE or resource_type == GameTypes.WorldObjectType.SHRUB:
		return IndividualVegetationService.generate_positions(
			macro_state, resource_type, occupied, params["frequency"], params["threshold"], current_year, current_day, building_positions
		)

	# GRASS non ha identità individuale (genera a livello di intero lotto, non di singolo
	# indice) — un blocco da taglio anche su un solo indice di un lotto (vedi
	# MacroCellState.vegetation_cut_exceptions, blocco unificato) deve escludere l'INTERA
	# microcella per lei, non solo quell'indice: GRASS non ha modo di "crescere attorno" a un
	# indice bloccato dentro lo stesso lotto.
	if resource_type == GameTypes.WorldObjectType.GRASS:
		_exclude_blocked_lots(macro_state, current_year, occupied)

	var count: int = macro_state.get_dedicated_space(resource_type)
	var noise_seed: int = hash(str(macro_state.micro_seed) + "_" + str(resource_type))
	return ResourcePositionService.generate_positions(
		noise_seed, count, occupied, params["frequency"], params["threshold"]
	)


# Aggiunge a `occupied` (in place) ogni lotto Vector2i(x,y) con ALMENO un'eccezione di taglio O
# morte ancora attiva a un indice qualunque (entrambe bloccano allo stesso modo, vedi
# IndividualVegetationService._is_blocked — GRASS le tratta allo stesso identico modo, non ha
# motivo di distinguere la causa), ma con test di attività diversi per le due cause (vedi
# IndividualVegetationService, commento in testa al file): il taglio scade per anni trascorsi
# (IndividualVegetationService.REENTRY_YEARS_BY_TYPE, stessa tabella usata a livello di singolo
# indice), la morte naturale è attiva per pura presenza (azzerata altrove in blocco).
func _exclude_blocked_lots(macro_state: MacroCellState, current_year: int, occupied: Dictionary) -> void:
	for key in macro_state.vegetation_cut_exceptions.keys():
		var entry: Dictionary = macro_state.vegetation_cut_exceptions[key]
		var reentry_years: int = IndividualVegetationService.REENTRY_YEARS_BY_TYPE.get(entry["origin_type"], 0)
		if current_year - int(entry["cut_year"]) < reentry_years:
			occupied[Vector2i(key.x, key.y)] = true
	for key in macro_state.vegetation_death_exceptions.keys():
		occupied[Vector2i(key.x, key.y)] = true
