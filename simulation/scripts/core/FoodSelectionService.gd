class_name FoodSelectionService
extends RefCounted

# Sceglie COSA prelevare da un edificio per riempire le provviste massimizzando le calorie
# (2026-09-19, richiesta utente). Solo calcolo: non tocca ne' il magazzino ne' l'individuo. Stateless
# (RefCounted, static), stesso pattern degli altri service.
#
# Criterio "commestibile": lo stesso di WarehouseSelectionService - CaloricCalculator.
# get_caloric_source_rules(nome).calories_per_unit > 0 (in piu' space_per_unit > 0, altrimenti il
# rapporto calorie/spazio non e' definito e l'unita' non occuperebbe spazio).

# Tolleranza sul floor(spazio_residuo / space_per_unit): lo spazio residuo e' un float e un "esattamente
# 3 unita'" puo' risultare 2.9999999.
const UNIT_FIT_EPSILON: float = 0.000001


# Ritorna {"quantities": {nome_risorsa: unita' intere da prelevare}, "space_used": float,
# "calories": float, "body_quantities": {...}, "body_calories": float}. Le risorse commestibili presenti in building.stored_resources (quantity > 0)
# sono ordinate per calorie/spazio DECRESCENTE (a parita', per nome, cosi' l'esito e' deterministico);
# lo spazio libero `free_space` viene riempito con unita' INTERE: dalla prima risorsa se ne prende
# min(disponibili, quante ne stanno intere nello spazio residuo), poi si passa alla successiva quando
# la prima si esaurisce o non entra piu' (anche una risorsa con unita' piu' grandi dello spazio
# residuo viene saltata, e le successive, piu' piccole, possono ancora entrare). Nessun edificio,
# nessun cibo o (free_space <= 0 e calorie_target <= 0) -> quantities vuote e totali 0.
#
# calorie_target (2026-09-19, richiesta utente - recupero della riserva corporea; default 0.0 = comportamento
# INVARIATO, nessun body_*): calorie da destinare alla RISERVA CORPOREA, che non occupa spazio nelle
# provviste. Due fasi sulle stesse disponibilita':
#   1. RISERVA (ha la precedenza, se il cibo non basta per entrambe): unita' intere fino a coprire
#      calorie_target, partendo dalle risorse con calorie/spazio PIU' BASSO (quelle peggiori da portare
#      con se': per mangiare lo spazio non conta, cosi' quelle compatte restano per le provviste);
#      l'ultima unita' puo' superare il target di meno di un'unita'. Esito in "body_quantities" e
#      "body_calories".
#   2. PROVVISTE: come sempre, sul cibo rimasto dopo la fase 1. Esito in "quantities"/"space_used"/
#      "calories", che descrivono SOLO cio' che va alle provviste (stesso significato di prima).
# Il chiamante preleva la somma dei due gruppi.
static func select_food(building: Building, free_space: float, calorie_target: float = 0.0) -> Dictionary:
	var result := {"quantities": {}, "space_used": 0.0, "calories": 0.0, "body_quantities": {}, "body_calories": 0.0}
	if building == null or (free_space <= 0.0 and calorie_target <= 0.0):
		_log_selection(building, free_space, [], result)
		return result

	# Candidati: {"name", "available", "space", "calories", "ratio"}.
	var candidates: Array = []
	for resource_name in building.stored_resources.keys():
		var entry: Dictionary = building.stored_resources[resource_name]
		var available: int = int(entry.get("quantity", 0))
		if available <= 0:
			continue
		var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
		if rules == null or rules.calories_per_unit <= 0.0 or rules.space_per_unit <= 0.0:
			continue
		candidates.append({
			"name": resource_name,
			"available": available,
			"space": rules.space_per_unit,
			"calories": rules.calories_per_unit,
			"ratio": rules.calories_per_unit / rules.space_per_unit,
		})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["ratio"]), float(b["ratio"])):
			return float(a["ratio"]) > float(b["ratio"])
		return String(a["name"]) < String(b["name"])
	)

	# Fase 1 - riserva corporea (vedi sopra). candidates e' in ordine di ratio DECRESCENTE: si scorre al
	# contrario per partire dalle risorse con calorie/spazio piu' basso. "available" viene scalato,
	# cosi' la fase 2 vede solo il cibo rimasto.
	if calorie_target > 0.0:
		var remaining_calories: float = calorie_target
		for i in range(candidates.size() - 1, -1, -1):
			if remaining_calories <= 0.0:
				break
			var body_candidate: Dictionary = candidates[i]
			var calories_per_unit: float = body_candidate["calories"]
			var units_needed: int = int(ceil(remaining_calories / calories_per_unit - UNIT_FIT_EPSILON))
			var body_units: int = mini(int(body_candidate["available"]), units_needed)
			if body_units <= 0:
				continue
			result["body_quantities"][body_candidate["name"]] = body_units
			result["body_calories"] += float(body_units) * calories_per_unit
			remaining_calories -= float(body_units) * calories_per_unit
			body_candidate["available"] = int(body_candidate["available"]) - body_units

	var remaining_space: float = free_space
	for candidate in candidates:
		var space_per_unit: float = candidate["space"]
		var units_that_fit: int = int(floor(remaining_space / space_per_unit + UNIT_FIT_EPSILON))
		var units: int = mini(int(candidate["available"]), units_that_fit)
		if units <= 0:
			continue
		result["quantities"][candidate["name"]] = units
		result["space_used"] += float(units) * space_per_unit
		result["calories"] += float(units) * float(candidate["calories"])
		remaining_space -= float(units) * space_per_unit

	_log_selection(building, free_space, candidates, result)
	return result


# Log diagnostico (DebugLogging.SHOW_FOOD_SELECTION_LOGS, spento di default): candidati in ordine di
# calorie/spazio e scelta fatta. Solo print.
static func _log_selection(building: Building, free_space: float, candidates: Array, result: Dictionary) -> void:
	if not DebugLogging.ENABLED or not DebugLogging.SHOW_FOOD_SELECTION_LOGS:
		return
	var candidate_texts: Array[String] = []
	for candidate in candidates:
		candidate_texts.append("%s(disp=%d spazio/u=%.2f cal/u=%.2f cal/spazio=%.2f)" % [
			candidate["name"], candidate["available"], candidate["space"], candidate["calories"], candidate["ratio"]
		])
	print("[FOOD SELECTION DEBUG] edificio=%s spazio_libero=%.2f candidati=[%s] -> riserva=%s calorie_riserva=%.2f | provviste=%s spazio_usato=%.2f calorie=%.2f" % [
		("%s #%d" % [building.building_type_name, building.id]) if building != null else "(nessuno)",
		free_space, ", ".join(candidate_texts), str(result["body_quantities"]), result["body_calories"],
		str(result["quantities"]), result["space_used"], result["calories"]
	])
