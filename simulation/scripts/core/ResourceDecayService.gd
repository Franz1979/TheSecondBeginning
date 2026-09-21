class_name ResourceDecayService
extends RefCounted

# Decadimento a LOTTO UNICO per risorse trasportate/stoccate (2026-09-09, richiesta utente, Step 3)
# — funzioni statiche stateless, stesso pattern di BuildingStorageService/TerrainScatteredResource
# Service: nessuna istanza, opera sempre su un HumanIndividual/Building passato dal chiamante.
#
# MODELLO: una frazione 0.0->1.0 (mai "giorni residui"), avanzata al giorno di 1/day_durability per
# lo zaino individuo (per varietà, nessun moltiplicatore ambiente lì: un individuo non ha una "categoria"), e di
# 1/(day_durability × BuildingRules.durability_multiplier_by_category[categoria]) per un edificio
# (2026-09-09, richiesta utente — moltiplicatore PER TIPO DI EDIFICIO × CATEGORIA DI RISORSA, non
# per ambiente generico: un deposit_site potrà conservare raw_material meglio/peggio di food, un
# altro tipo di edificio avrà il proprio array indipendente). "Lotto unico" perché lo zaino ha un
# solo slot per varietà (HumanIndividual.carried_resources) e un edificio fonde ogni nuovo deposito con quanto già
# presente via media pesata (vedi BuildingStorageService.store) — mai due sotto-lotti della stessa
# risorsa tracciati separatamente nello stesso contenitore.
#
# SecondaryResourceRules.day_durability == -1 (pebble/stick oggi) = mai deperisce, saltato in
# ENTRAMBE le funzioni sotto — stesso identico significato "infinito" già in uso per quel campo
# prima di questo passo (mai consultato da nessuna logica finché non è arrivato questo service).
#
# Materiale abbandonato a terra: FUORI SCOPE (richiesta esplicita) — resta "sparisce" come oggi,
# nessuna funzione qui lo tocca.


# Avanza la decay_fraction di OGNI varietà dello zaino (individual.carried_resources, multi-risorsa dal
# 2026-09-20) di 1/day_durability della rispettiva risorsa — ciascuna varietà ha il proprio
# avanzamento indipendente, come le entry di building.stored_resources (vedi advance_building_decay
# sotto). No-op per le varietà con day_durability == -1 (non decadono). Quando la frazione di una
# varietà raggiunge/supera 1.0 quella varietà è deperita per intero e persa: la entry sparisce dal
# dizionario (mai un valore orfano), le altre varietà restano.
#
# Ritorna un Array (vuoto se nulla è deperito oggi) di {"resource_name","quantity"}, una voce per
# varietà deperita — SOLO per permettere al chiamante (GameTimeService) di notificare il player
# (2026-09-09, richiesta utente: popup + pannello aggiornato) senza che questo service sappia nulla
# di UI/segnali, resta puramente una funzione di calcolo che riporta il proprio esito. Array (a
# differenza della versione mono-risorsa, che ritornava un solo Dictionary) perché più varietà
# possono deperire nello stesso giorno. Le entry da rimuovere sono raccolte a parte e cancellate DOPO
# il ciclo (mai mutare un Dictionary mentre lo si itera).
static func advance_individual_decay(individual: HumanIndividual) -> Array:
	var lost: Array = []
	if individual == null or individual.carried_resources.is_empty():
		return lost
	var expired_names: Array[String] = []
	for resource_name in individual.carried_resources.keys():
		var quantity: int = individual.get_carried_quantity(String(resource_name))
		if quantity <= 0:
			continue
		var resource_rules := CaloricCalculator.get_caloric_source_rules(String(resource_name))
		if resource_rules == null or resource_rules.day_durability == -1:
			continue
		var new_fraction: float = individual.get_carried_decay_fraction(String(resource_name)) + 1.0 / float(resource_rules.day_durability)
		if new_fraction < 1.0:
			individual.carried_resources[resource_name] = {"quantity": quantity, "decay_fraction": new_fraction}
			continue
		expired_names.append(String(resource_name))
		lost.append({"resource_name": String(resource_name), "quantity": quantity})
	for expired_name in expired_names:
		individual.carried_resources.erase(expired_name)
	return lost


# Stessa logica di advance_individual_decay sopra, per OGNI entry di building.stored_resources —
# ciascuna risorsa ha il proprio day_durability/avanzamento indipendente (a differenza dello zaino,
# un edificio può ospitare più tipi di risorsa contemporaneamente, vedi BuildingStorageService).
# Le entry che raggiungono/superano 1.0 vengono rimosse dal Dictionary per intero (mai lasciate a
# quantity>0 con una frazione "scaduta" residua) — raccolte in un array a parte e cancellate DOPO
# il ciclo principale, stesso idioma "mai mutare un Dictionary/Array mentre lo si itera" già in uso
# altrove nel progetto (es. GameTimeService._apply_scheduled_human_deaths, lì su un Array scorso
# all'indietro; qui su un Dictionary, la rimozione differita è l'equivalente corretto).
#
# Ritorna un Array (vuoto se nulla è deperito oggi) di {"resource_name","quantity"} — stesso motivo
# di advance_individual_decay sopra: permette al chiamante (WorldTimeService) di notificare il
# player senza che questo service sappia nulla di UI/segnali. Array anziché un solo Dictionary
# (a differenza della versione individuo, che ha un solo slot): un edificio può perdere più di un
# TIPO di risorsa nello stesso giorno.
static func advance_building_decay(building: Building) -> Array:
	if building == null:
		return []
	var lost: Array = []
	var keys_to_erase: Array = []
	for resource_name in building.stored_resources.keys():
		var resource_rules := CaloricCalculator.get_caloric_source_rules(String(resource_name))
		if resource_rules == null or resource_rules.day_durability == -1:
			continue
		var multiplier := _durability_multiplier(building, resource_rules.category)
		var entry: Dictionary = building.stored_resources[resource_name]
		var decay_fraction: float = float(entry.get("decay_fraction", 0.0)) + 1.0 / (float(resource_rules.day_durability) * multiplier)
		if decay_fraction >= 1.0:
			keys_to_erase.append(resource_name)
			lost.append({"resource_name": String(resource_name), "quantity": int(entry.get("quantity", 0))})
			continue
		entry["decay_fraction"] = decay_fraction
		building.stored_resources[resource_name] = entry
	for resource_name in keys_to_erase:
		building.stored_resources.erase(resource_name)
	return lost


# Moltiplicatore per `category` da BuildingRules.durability_multiplier_by_category (2026-09-09,
# richiesta utente) — 1.0 (nessun effetto) se building.rules è null, l'array non copre `category`
# (mai un crash per un array troppo corto — es. una futura categoria aggiunta senza aggiornare i
# .tres esistenti), o il valore configurato non è positivo (difensivo: un moltiplicatore <= 0.0
# produrrebbe una divisione per zero o un decadimento all'indietro in advance_building_decay sopra,
# nessuno dei due ha senso — trattato come "non configurato", mai propagato).
static func _durability_multiplier(building: Building, category: int) -> float:
	if building.rules == null:
		return 1.0
	var multipliers := building.rules.durability_multiplier_by_category
	if category < 0 or category >= multipliers.size():
		return 1.0
	var multiplier: float = multipliers[category]
	return multiplier if multiplier > 0.0 else 1.0
