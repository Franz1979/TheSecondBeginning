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


# Criterio di ordinamento "piu' denso prima" (2026-09-20, estratto da select_food per condividerlo con
# PickUpAction, zaino multi-risorsa): calorie/spazio DECRESCENTE, a parita' per nome (esito deterministico).
# true se la risorsa A va scelta prima della B.
static func is_denser_food_first(ratio_a: float, name_a: String, ratio_b: float, name_b: String) -> bool:
	if not is_equal_approx(ratio_a, ratio_b):
		return ratio_a > ratio_b
	return name_a < name_b


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
#
# pouch_calorie_room (2026-10-03, richiesta utente — tetto in giorni di autonomia, vedi RestockPouchAction): calorie che
# le provviste possono ancora ricevere. Nella fase 2 si caricano unita' intere finche' le calorie aggiunte restano sotto
# questo valore; l'ultima unita' puo' superarlo (chi consuma poco prende comunque almeno un pezzo). Vale insieme allo
# spazio: quello che arriva prima. INF (default) = nessun tetto, comportamento di prima. Non tocca la fase 1 (riserva).
#
# BUFFER DI USCITA (2026-09-27, bug "affamati che girano a vuoto al focolare"): le disponibilita' sono
# stored_resources PIU' Building.production_output, la stessa somma che WarehouseSelectionService.
# find_source_for_retrieval considera per scegliere la sorgente e che BuildingStorageService.withdraw
# preleva davvero. Prima si guardava solo lo storage: un focolare con carne cotta solo nel buffer era
# una sorgente valida ma la scelta risultava vuota, la task finiva senza prelievo e il bisogno rinasceva.
static func select_food(building: Building, free_space: float, calorie_target: float = 0.0, pouch_calorie_room: float = INF) -> Dictionary:
	if building == null:
		return select_food_from_entries({}, free_space, calorie_target, "(nessuno)", pouch_calorie_room)
	return select_food_from_entries(
		_get_withdrawable_entries(building), free_space, calorie_target, "%s #%d" % [building.building_type_name, building.id],
		pouch_calorie_room
	)


# Voci resource_name -> {"quantity"} prelevabili da `building`: stored_resources sommato al buffer di uscita
# (stessa quantita' di BuildingStorageService.get_available_quantity). Copia: non tocca l'edificio.
static func _get_withdrawable_entries(building: Building) -> Dictionary:
	if building.production_output.is_empty():
		return building.stored_resources
	var entries: Dictionary = {}
	for resource_name in building.stored_resources.keys():
		entries[resource_name] = {"quantity": int((building.stored_resources[resource_name] as Dictionary).get("quantity", 0))}
	for output_name in building.production_output.keys():
		var buffered: int = int(building.production_output[output_name])
		if buffered <= 0:
			continue
		var existing: Dictionary = entries.get(output_name, {"quantity": 0})
		entries[output_name] = {"quantity": int(existing.get("quantity", 0)) + buffered}
	return entries


# Stessa scelta di select_food su VOCI GENERICHE (2026-09-26, richiesta utente — rifornirsi dal proprio zaino):
# resource_name -> {"quantity", ...}, il formato comune di Building.stored_resources e di HumanIndividual.
# carried_resources. `source_label` serve solo al log. Criterio invariato: calorie/spazio decrescente.
static func select_food_from_entries(
	entries: Dictionary, free_space: float, calorie_target: float = 0.0, source_label: String = "", pouch_calorie_room: float = INF
) -> Dictionary:
	var result := {"quantities": {}, "space_used": 0.0, "calories": 0.0, "body_quantities": {}, "body_calories": 0.0}
	if free_space <= 0.0 and calorie_target <= 0.0:
		_log_selection(source_label, free_space, [], result)
		return result

	# Candidati: {"name", "available", "space", "calories", "ratio"}.
	var candidates: Array = []
	for resource_name in entries.keys():
		var entry: Dictionary = entries[resource_name]
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
		return FoodSelectionService.is_denser_food_first(float(a["ratio"]), String(a["name"]), float(b["ratio"]), String(b["name"]))
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
	var remaining_room: float = pouch_calorie_room
	for candidate in candidates:
		if remaining_room <= 0.0:
			break
		var space_per_unit: float = candidate["space"]
		var units_that_fit: int = int(floor(remaining_space / space_per_unit + UNIT_FIT_EPSILON))
		var units: int = mini(int(candidate["available"]), units_that_fit)
		# Tetto di calorie: unita' fino a raggiungerlo, l'ultima puo' superarlo (ceil).
		if not is_inf(remaining_room):
			units = mini(units, int(ceil(remaining_room / float(candidate["calories"]) - UNIT_FIT_EPSILON)))
		if units <= 0:
			continue
		result["quantities"][candidate["name"]] = units
		result["space_used"] += float(units) * space_per_unit
		result["calories"] += float(units) * float(candidate["calories"])
		remaining_space -= float(units) * space_per_unit
		remaining_room -= float(units) * float(candidate["calories"])

	_log_selection(source_label, free_space, candidates, result)
	return result


# true se tra le voci c'è almeno un'unità di cibo commestibile (calories_per_unit > 0 e space_per_unit > 0, stesso
# criterio della scelta). Usata per decidere se il rifornimento può partire dallo zaino.
static func has_edible_food(entries: Dictionary) -> bool:
	for resource_name in entries.keys():
		if int((entries[resource_name] as Dictionary).get("quantity", 0)) <= 0:
			continue
		var rules := CaloricCalculator.get_caloric_source_rules(String(resource_name))
		if rules != null and rules.calories_per_unit > 0.0 and rules.space_per_unit > 0.0:
			return true
	return false


# Log diagnostico (DebugLogging.SHOW_FOOD_SELECTION_LOGS, spento di default): candidati in ordine di
# calorie/spazio e scelta fatta. Solo print.
static func _log_selection(source_label: String, free_space: float, candidates: Array, result: Dictionary) -> void:
	if not DebugLogging.ENABLED or not DebugLogging.SHOW_FOOD_SELECTION_LOGS:
		return
	var candidate_texts: Array[String] = []
	for candidate in candidates:
		candidate_texts.append("%s(disp=%d spazio/u=%.2f cal/u=%.2f cal/spazio=%.2f)" % [
			candidate["name"], candidate["available"], candidate["space"], candidate["calories"], candidate["ratio"]
		])
	print("[FOOD SELECTION DEBUG] sorgente=%s spazio_libero=%.2f candidati=[%s] -> riserva=%s calorie_riserva=%.2f | provviste=%s spazio_usato=%.2f calorie=%.2f" % [
		source_label,
		free_space, ", ".join(candidate_texts), str(result["body_quantities"]), result["body_calories"],
		str(result["quantities"]), result["space_used"], result["calories"]
	])
