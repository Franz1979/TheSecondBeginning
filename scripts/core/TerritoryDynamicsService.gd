class_name TerritoryDynamicsService
extends RefCounted

# Rampa a due tratti del moltiplicatore di densità (vedi _get_density_multiplier sotto). Soglia
# di inizio 0.7 (dopo un giro di test a 0.5, poi tornata a 0.7): frenare troppo presto rischia di
# stabilizzare la popolazione di specie a crescita lenta e territorio ancora espandibile (es.
# deer) in un equilibrio permanente SOTTO la soglia che farebbe scattare l'espansione
# (_update_group_territory.needs_expansion_density, ~ratio > 1.0) — il freno pensato per chi non
# ha via di scampo (rabbit, sempre al massimo territorio) finirebbe per impedire alla via di
# scampo stessa (l'espansione di deer) di attivarsi mai. Stesso discorso varrà in futuro per lo
# split del gruppo (Step 9): la mitigazione non deve MAI essere così aggressiva da impedire alla
# popolazione di accumulare la pressione reale che serve a far scattare il meccanismo successivo.
const DENSITY_RATIO_RAMP_START := 0.7   # sotto: nessuna penalità, moltiplicatore = 1.0
const DENSITY_RATIO_FULL_CAPACITY := 1.0  # qui il moltiplicatore vale il "mid" della specie (vedi sotto)
const DENSITY_RATIO_RAMP_END := 1.5     # da qui in poi: moltiplicatore = 0.0, per tutti

# Il "mid" (valore del moltiplicatore esattamente a ratio=1.0, piena capacità etologica) non è
# un'unica costante: la stessa rampa 0.7->1.0 quadratica, applicata a un floor unico, andava bene
# per specie a riproduzione veloce (rabbit: anche un moltiplicatore basso produce comunque molti
# nascituri) ma soffocava una specie lenta (deer, base_birth_rate=0.4) fino a stabilizzarla in un
# equilibrio PERMANENTE — le nascite (già ridotte al 5%) bastavano solo a pareggiare la mortalità
# per vecchiaia, mai a produrre il surplus necessario a superare la soglia di espansione
# territoriale (osservato nei test: popolazione ferma esatta a 70 per tre cicli di fila). La
# discriminante è il VALORE di AnimalRules.base_birth_rate della specie, non il nome/l'identità
# della specie in sé (nessuna eccezione hardcoded, stesso principio già seguito ovunque in questo
# file) — sopra o uguale a DENSITY_FAST_GROWTH_BIRTH_RATE_THRESHOLD (1.0) è "veloce" (rabbit,
# base_birth_rate=1.5) e usa DENSITY_MULTIPLIER_MID_FAST (0.05, severo, già validato nei test:
# ha fermato un'esplosione da 14000+ individui); sotto è "lenta" (deer, base_birth_rate=0.4) e usa
# DENSITY_MULTIPLIER_MID_SLOW (0.25 per ora — se i test mostrano che il surplus di nascite resta
# comunque troppo debole per accumulare pressione in tempi ragionevoli, va alzato verso 0.5, mai
# oltre: un floor troppo alto vanificherebbe la mitigazione stessa).
#
# La FORMA della curva è invece IDENTICA per entrambe le categorie, nessuna doppia formula da
# mantenere: quadratica (t², frenata debole per la maggior parte del tratto, concentrata negli
# ultimi passi) da 0.7 a 1.0, poi lineare da 1.0 a 1.5 — ciascuna parte scende dal PROPRIO mid
# (0.05 o 0.25) fino a 0.0 esattamente a ratio=1.5, mai un floor piatto fisso uguale per tutte:
# un plateau comune a un valore fisso (es. sempre 0.05 tra 1.0 e 1.5 indipendentemente dal mid di
# partenza) creerebbe una discontinuità a ratio=1.0 per la specie lenta (salto da 0.25 a 0.05) —
# scartato apposta per restare continua in entrambi i punti di rottura, come tutte le altre curve
# di questo sistema.
const DENSITY_FAST_GROWTH_BIRTH_RATE_THRESHOLD := 1.0
const DENSITY_MULTIPLIER_MID_FAST := 0.05   # base_birth_rate >= soglia (oggi: rabbit)
const DENSITY_MULTIPLIER_MID_SLOW := 0.25   # base_birth_rate < soglia (oggi: deer)

# Espansione/contrazione del territorio di ogni PopulationGroup (Step 8 del refactoring fauna) —
# gira nello STESSO checkpoint di inizio birth_season di ciascuna specie in cui gira già
# AnimalBirthMitigationService, perché i due condividono la stessa identica definizione di
# "scarsità" (AnimalBirthMitigationService.compute_caloric_ratio — stock disponibile snapshot /
# fabbisogno stagionale age-weighted).
#
# Sequenza per ogni gruppo con rules.birth_season == season:
#   1. ratio_iniziale = compute_caloric_ratio() sul territorio ATTUALE
#   2. valuta espansione/contrazione (vedi _update_group_territory)
#   3. ratio_finale = compute_caloric_ratio() sul territorio ORA aggiornato (identico a
#      ratio_iniziale se il territorio non è cambiato — nessun ramo speciale necessario)
#   4. apply_mitigation_multiplier(group, ratio_finale) — mai il ratio_iniziale: la natalità di
#      fine stagione deve vedere l'effetto dell'eventuale aggiustamento territoriale di
#      quest'anno, non lo stato di prima.
#
# Nessuna eccezione hardcoded per specie: rabbit (min_territory_cells == max_territory_cells == 1)
# si autoesclude per pura costruzione matematica — density_cells_needed resta sempre uguale alle
# celle attuali (già 1) e la contrazione è strutturalmente impossibile quando current_cell_count
# non supera già min_territory_cells — senza bisogno di alcun controllo esplicito sul nome specie
# qui sotto. Ogni gruppo è valutato indipendentemente dagli altri — nessuna competizione/
# sovrapposizione tra territori di gruppi diversi ancora (TerritoryManager futuro).
func update_territories_and_mitigation(world: World, season: GameTypes.Season) -> void:
	var mitigation_service := AnimalBirthMitigationService.new()

	for group in world.population_groups:
		if group.population <= 0:
			continue
		var rules := AnimalCalculator.get_animal_rules(group.species_name)
		if rules == null or rules.birth_season != season:
			continue

		# Il ratio calorico è age-weighted (AnimalBirthMitigationService._get_seasonal_requirement):
		# per una specie senza track_age_bands, age_composition resta sempre vuota, quindi il
		# fabbisogno stagionale risulterebbe sempre 0 e il ratio un falso "0.0 = carestia
		# permanente". Nessuna specie oggi è in questo caso (rabbit e deer hanno entrambe
		# track_age_bands=true): il criterio calorico resta comunque disattivato (ratio neutro 1.0,
		# nessuna pressione) finché capitasse, il criterio di densità resta invece pienamente
		# specie-agnostico e valido in ogni caso.
		var initial_ratio_data: Dictionary = {"stock": 0.0, "requirement": 0.0, "ratio": 1.0}
		if rules.track_age_bands:
			initial_ratio_data = mitigation_service.compute_caloric_ratio(world, group, rules, season)
		var initial_ratio: float = initial_ratio_data["ratio"]

		var territory_result: Dictionary = {}
		if group.territory != null:
			territory_result = _update_group_territory(world, group, rules, initial_ratio)

		if not rules.track_age_bands:
			continue

		var final_ratio_data := mitigation_service.compute_caloric_ratio(world, group, rules, season)
		var final_ratio: float = final_ratio_data["ratio"]

		# Densità sul territorio DEFINITIVO di quest'anno (dopo _update_group_territory sopra),
		# mai su quello pre-aggiustamento — stesso principio già usato per final_ratio.
		var cell_count_final: int = group.territory.get_cell_count() if group.territory != null else 0
		var density_data := _get_density_multiplier(
			group.population, cell_count_final, rules.max_density_per_cell, rules.base_birth_rate
		)

		# log_enabled=false qui: per le specie con min_territory_cells > 1 il log dedicato sotto
		# mostra già ratio_finale/stock/fabbisogno — aggiungere anche il moltiplicatore lì evita
		# di stampare due righe con la stessa informazione (vedi apply_mitigation_multiplier).
		var multiplier_data := mitigation_service.apply_mitigation_multiplier(
			group, final_ratio, density_data["multiplier"], density_data["ratio"], rules.min_territory_cells <= 1
		)

		if DebugLogging.ENABLED and rules.min_territory_cells > 1 and not territory_result.is_empty():
			print(
				(
					"[TERRITORY DYNAMICS] #%d %s pop=%d celle=%d->%d "
					+ "ratio_iniziale=%.3f (stock=%.1f fabbisogno=%.1f) "
					+ "celle_da_densita=%d occupazione_media=%.2f soglia_contrazione=%.1f "
					+ "azione=%s (%s) "
					+ "ratio_finale=%.3f ratio_clampato=%.3f (stock=%.1f fabbisogno=%.1f) "
					+ "moltiplicatore_calorico=%.3f occupazione_ratio=%.3f moltiplicatore_densita=%.3f "
					+ "moltiplicatore_finale=%.3f"
				) % [
					group.id, group.species_name, group.population,
					territory_result["cells_before"], territory_result["cells_after"],
					initial_ratio, initial_ratio_data["stock"], initial_ratio_data["requirement"],
					territory_result["density_cells_needed"],
					territory_result["average_occupancy"], territory_result["contraction_threshold"],
					territory_result["action"], territory_result["reason"],
					final_ratio, multiplier_data["clamped_ratio"],
					final_ratio_data["stock"], final_ratio_data["requirement"],
					multiplier_data["caloric_multiplier"], density_data["ratio"], density_data["multiplier"],
					multiplier_data["final_multiplier"]
				]
			)


# Un solo controllo per gruppo: prima l'espansione, altrimenti la contrazione — mutuamente
# esclusive per costruzione (nessuna condizione può chiedere contemporaneamente più celle E meno
# celle), quindi if/elif, mai entrambe nello stesso checkpoint per lo stesso gruppo. Ritorna i
# dettagli della decisione (per il logging del chiamante), mai null/vuoto se raggiunta.
func _update_group_territory(
	world: World, group: PopulationGroup, rules: AnimalRules, caloric_ratio: float
) -> Dictionary:
	var current_cell_count := group.territory.get_cell_count()

	# Criterio 1 di espansione: densità etologica, indipendente dalle risorse (vedi
	# AnimalRules.max_density_per_cell) — nessun clamp qui, è solo il segnale "serve più spazio",
	# non un target di celle da raggiungere in un colpo solo (si espande di una cella alla volta
	# comunque, vedi sotto).
	var density_cells_needed: int = int(ceil(float(group.population) / float(rules.max_density_per_cell)))
	var needs_expansion_density: bool = density_cells_needed > current_cell_count

	# Criterio 2 di espansione: vincolo calorico, sulla stessa soglia RATIO_HIGH_THRESHOLD già
	# usata da AnimalBirthMitigationService per "sopra: nessuna penalità alla natalità" — non un
	# valore dedicato, per non avere due definizioni scoordinate di "questo territorio è in
	# difficoltà" nello stesso sistema.
	var needs_expansion_caloric: bool = caloric_ratio < AnimalBirthMitigationService.RATIO_HIGH_THRESHOLD

	# Contrazione: occupazione media (population/celle attuali) confrontata direttamente con METÀ
	# del limite etologico — non un denominatore gonfiato (l'ex fattore ×1.5, concettualmente
	# sbagliato: spostava l'intero limite di riferimento a 27, tollerando densità permanentemente
	# sopra il limite etologico dichiarato di 18 senza mai contrarre). Con la soglia a metà, la
	# "zona morta" di isteresi è [max_density_per_cell/2, max_density_per_cell] — sotto quella
	# banda si contrae, sopra si espande (criterio 1), dentro non si muove nulla: mai una
	# contrazione quando la densità è già pari o sopra il limite etologico normale.
	var average_occupancy: float = float(group.population) / float(current_cell_count)
	var contraction_threshold: float = float(rules.max_density_per_cell) / 2.0
	var needs_contraction: bool = (
		average_occupancy < contraction_threshold and current_cell_count > rules.min_territory_cells
	)

	var action := "nessun cambiamento"
	var reason := "nessun criterio soddisfatto"

	if needs_expansion_density or needs_expansion_caloric:
		if current_cell_count >= rules.max_territory_cells:
			reason = "espansione richiesta ma territorio già a max_territory_cells (%d)" % rules.max_territory_cells
		else:
			var added := TerritoryBuilderService.new().expand_by_one_cell(world, group.territory)
			if added:
				action = "espande di 1 cella"
				reason = _expansion_reason(needs_expansion_density, needs_expansion_caloric)
			else:
				reason = "espansione richiesta ma nessuna cella libera raggiungibile"
	elif needs_contraction:
		_contract_by_one_cell(group)
		action = "contrae di 1 cella"
		reason = "occupazione media sotto soglia isteresi (%.2f < %.1f)" % [average_occupancy, contraction_threshold]

	return {
		"cells_before": current_cell_count,
		"cells_after": group.territory.get_cell_count(),
		"density_cells_needed": density_cells_needed,
		"average_occupancy": average_occupancy,
		"contraction_threshold": contraction_threshold,
		"action": action,
		"reason": reason,
	}


# Mitigazione della natalità legata alla densità ETOLOGICA del territorio (AnimalRules.
# max_density_per_cell) — indipendente dalla disponibilità calorica sopra, MOLTIPLICA il
# moltiplicatore calorico già esistente invece di sostituirlo (vedi
# AnimalBirthMitigationService.apply_mitigation_multiplier, unico punto dove i due si combinano).
# occupazione_ratio = population / (celle_attuali del territorio DEFINITIVO di quest'anno ×
# max_density_per_cell) — SEMPRE la capacità dell'INTERO territorio, mai il valore per singola
# cella isolato: stessa formula identica per un territorio a 1 cella (rabbit) o multi-cella (deer).
#
# base_birth_rate sceglie il "mid" (vedi DENSITY_MULTIPLIER_MID_FAST/SLOW sopra per il perché),
# poi la stessa forma di curva si applica a entrambe le categorie, continua in ogni punto di
# rottura: sotto DENSITY_RATIO_RAMP_START (0.7) nessuna penalità (1.0); da lì a
# DENSITY_RATIO_FULL_CAPACITY (1.0) scende al mid della specie seguendo un easing QUADRATICO (t²,
# non lineare) — la frenata resta debole per la maggior parte del tratto (es. per una specie
# "veloce", a ratio=0.9 il moltiplicatore è ancora ~0.58, non ~0.37 come sarebbe con una rampa
# lineare) e si concentra quasi tutta negli ultimi passi verso 1.0; da lì a DENSITY_RATIO_RAMP_END
# (1.5) scende LINEARMENTE dal proprio mid fino a 0.0 esatto (mai un plateau piatto uguale per
# tutte le specie in questo tratto — vedi commento sopra sul perché). Oltre RAMP_END resta a 0.0
# per tutti — a differenza del solo vincolo calorico che con risorse abbondanti lascia la natalità
# a pieno regime anche a densità già assurde (osservato in test: 14000+ individui in una cella con
# max_density_per_cell=200, prima che fame/espansione avessero modo di intervenire).
func _get_density_multiplier(
	population: int, cell_count: int, max_density_per_cell: int, base_birth_rate: float
) -> Dictionary:
	var capacity: int = cell_count * max_density_per_cell
	if capacity <= 0:
		return {"ratio": 0.0, "multiplier": 1.0}

	var ratio: float = float(population) / float(capacity)
	var mid: float = (
		DENSITY_MULTIPLIER_MID_FAST if base_birth_rate >= DENSITY_FAST_GROWTH_BIRTH_RATE_THRESHOLD
		else DENSITY_MULTIPLIER_MID_SLOW
	)
	var multiplier: float

	if ratio < DENSITY_RATIO_RAMP_START:
		multiplier = 1.0
	elif ratio < DENSITY_RATIO_FULL_CAPACITY:
		var t: float = (ratio - DENSITY_RATIO_RAMP_START) / (DENSITY_RATIO_FULL_CAPACITY - DENSITY_RATIO_RAMP_START)
		multiplier = lerp(1.0, mid, t * t)
	elif ratio < DENSITY_RATIO_RAMP_END:
		var t: float = (ratio - DENSITY_RATIO_FULL_CAPACITY) / (DENSITY_RATIO_RAMP_END - DENSITY_RATIO_FULL_CAPACITY)
		multiplier = lerp(mid, 0.0, t)
	else:
		multiplier = 0.0

	return {"ratio": ratio, "multiplier": multiplier}


func _expansion_reason(needs_density: bool, needs_caloric: bool) -> String:
	if needs_density and needs_caloric:
		return "densita etologica e vincolo calorico"
	if needs_density:
		return "densita etologica"
	return "vincolo calorico (ratio < %.1f)" % AnimalBirthMitigationService.RATIO_HIGH_THRESHOLD


# Rilascia UNA sola cella per checkpoint — la più lontana dal baricentro — stesso approccio
# incrementale già usato dall'espansione (expand_by_one_cell): un passo alla volta, mai un salto
# diretto a un numero di celle "ottimale" calcolato in anticipo. Mai sotto min_territory_cells:
# già garantito dal chiamante, che valuta needs_contraction solo se current_cell_count >
# min_territory_cells. Eventuali pesi orfani in territory_distribution_weights per la cella
# rilasciata non richiedono pulizia: PopulationGroup.get_population_by_cell() itera solo
# territory.occupied_macrocells corrente (le chiavi in più vengono semplicemente ignorate), e
# PopulationTerritoryShuffleService sovrascrive comunque l'intero dizionario al prossimo cambio
# di stagione.
func _contract_by_one_cell(group: PopulationGroup) -> void:
	var cells := group.territory.occupied_macrocells
	if cells.size() <= 1:
		return

	var centroid := group.territory.get_centroid()
	var farthest: Vector2i = cells[0]
	var farthest_distance := _manhattan_distance(farthest, centroid)
	for coords in cells:
		var distance := _manhattan_distance(coords, centroid)
		if distance > farthest_distance:
			farthest = coords
			farthest_distance = distance

	cells.erase(farthest)


static func _manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)
