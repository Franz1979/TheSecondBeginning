class_name Territory
extends RefCounted

# Insieme delle macrocelle occupate da un PopulationGroup. Step 4 del refactoring fauna introdusse
# l'entità con territori sempre a 1 cella; Step 5 aggiunge territori multi-cella ma di dimensione
# FISSA fin dalla creazione (vedi TerritoryBuilderService, invocato solo alla creazione di un
# nuovo gruppo) — nessuna espansione/restringimento nel tempo ancora (Step 8 futuro). rabbit
# resta sempre a 1 cella (min_territory_cells=1); deer nasce con min_territory_cells celle (oggi
# 3). Non serializzato come .tres, stesso trattamento di PopulationGroup/MacroCellState — solo
# salvato/caricato come dato di partita (vedi GameSaveService/GameLoadService).
var occupied_macrocells: Array[Vector2i] = []

func _init(_occupied_macrocells: Array[Vector2i]) -> void:
	occupied_macrocells = _occupied_macrocells


# Factory per il caso di oggi: un gruppo con una sola cella (bottone debug, caricamento save).
static func from_single_cell(coords: Vector2i) -> Territory:
	return Territory.new([coords])


func get_cell_count() -> int:
	return occupied_macrocells.size()


func contains(coords: Vector2i) -> bool:
	return occupied_macrocells.has(coords)


# Punto di transizione unico per i chiamanti che assumono un solo "home" per gruppo (rendering,
# debug, alcune UI): restituisce sempre la prima cella BFS-seed di occupied_macrocells (per
# rabbit, l'unica). Con territori multi-cella (Step 5+) NON è più l'intero territorio — chi ha
# bisogno di tutte le celle usa occupied_macrocells direttamente (vedi AnimalConsumptionService,
# AnimalBirthMitigationService, PopulationGroup.get_population_by_cell).
func get_primary_cell() -> Vector2i:
	return occupied_macrocells[0]


# Baricentro geometrico di occupied_macrocells, arrotondato alla cella intera più vicina — non
# garantito essere una cella effettivamente occupata (né valida/di terra), è solo un punto di
# riferimento: TerritoryBuilderService.expand_by_one_cell lo usa come radice BFS per trovare la
# cella libera più vicina, TerritoryDynamicsService lo usa per ordinare le celle da rilasciare in
# contrazione per distanza decrescente (Step 8 del refactoring fauna).
func get_centroid() -> Vector2i:
	var sum_x := 0
	var sum_y := 0
	for coords in occupied_macrocells:
		sum_x += coords.x
		sum_y += coords.y
	var count := occupied_macrocells.size()
	return Vector2i(int(round(float(sum_x) / count)), int(round(float(sum_y) / count)))
