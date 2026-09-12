class_name BuildingStorageService
extends RefCounted

# Storage per un SINGOLO edificio (2026-09-09, richiesta utente — Step 2, gestione a SLOT: uno slot
# contiene UNA SOLA risorsa alla volta, "slot univoci" — sostituisce il modello Step 1, dove
# storage_slot_count/storage_space_per_slot erano solo moltiplicati insieme per una capacità totale
# di SPAZIO, senza vincolo su quanti TIPI di risorsa diversi potessero convivere) — funzioni
# statiche stateless, stesso pattern di TaskFactory/TerrainScatteredResourceService: nessuna
# istanza, opera sempre su un Building passato dal chiamante. Legge/scrive Building.stored_resources
# e BuildingRules.storage_slot_count/storage_space_per_slot/accepted_categories (già esistenti).
#
# FORMATO stored_resources (2026-09-09, richiesta utente — Step 3 decadimento a lotto unico):
# resource_name -> {"quantity": int, "decay_fraction": float}, non più resource_name -> int diretto
# (vecchio formato Step 1/2). decay_fraction è una MEDIA PESATA sulla quantità di tutto ciò che è
# stato depositato nel tempo per quel resource_name in questo edificio (vedi store() sotto per la
# formula) — un "lotto unico" per tipo di risorsa per edificio, non un lotto per singolo deposito:
# depositare pietre già leggermente decadute sopra pietre fresche fa avanzare la decay_fraction
# media di tutte, mai due sotto-pile separate tracciate a parte. ResourceDecayService.
# advance_building_decay è l'unico altro punto che scrive decay_fraction (avanzamento giornaliero);
# ogni funzione qui sotto che legge una entry usa SEMPRE .get("quantity"/"decay_fraction", ...) —
# mai un cast diretto a int come nel vecchio formato — retrocompatibilità con save pre-decadimento
# gestita da GameLoadService (vedi lì), non qui: questo file assume SEMPRE il formato nuovo.
#
# MODELLO A SLOT: ogni risorsa occupa ceil(spazio_totale_risorsa / storage_space_per_slot) slot
# INTERI (arrotondati per eccesso — un'unità non si spezza mai tra due slot), mai condivisi con
# un'altra risorsa (es. 6 slot pietre + 3 slot rami = 9/9, nessuno spazio residuo nell'ultimo slot
# di ciascun gruppo utilizzabile da un tipo diverso). Questo è PIÙ RESTRITTIVO del semplice
# "spazio totale libero" del modello Step 1 in caso di frammentazione: due risorse che insieme
# userebbero meno spazio della capacità totale possono comunque riempire tutti gli slot se ciascuna
# lascia un resto parziale nel proprio ultimo slot (vedi store() sotto per il calcolo esatto).
#
# Spazio sempre in termini di SecondaryResourceRules.space_per_unit (stessa unità già usata da
# PickUpAction/HumanIndividual.max_carry_capacity per lo zaino individuale) — un edificio non ha
# un'unità di misura propria diversa, stesso "spazio" astratto su entrambi i lati.


static func get_capacity(building: Building) -> int:
	if building == null or building.rules == null:
		return 0
	return building.rules.storage_slot_count * building.rules.storage_space_per_slot


static func get_used_space(building: Building) -> int:
	if building == null:
		return 0
	var used := 0
	for resource_name in building.stored_resources.keys():
		var entry: Dictionary = building.stored_resources[resource_name]
		var quantity: int = int(entry.get("quantity", 0))
		var resource_rules := CaloricCalculator.get_caloric_source_rules(String(resource_name))
		if resource_rules == null:
			continue
		used += quantity * int(resource_rules.space_per_unit)
	return used


# Spazio totale libero — metrica GENERICA (usata da nessun calcolo di accettazione qui dentro:
# store() sotto usa get_free_slots, più preciso perché tiene conto della frammentazione a slot).
# Resta utile come cifra riassuntiva "quanto spazio resta in totale", non come garanzia che una
# specifica risorsa possa davvero riempirlo tutto (vedi commento in testa al file).
static func get_free_space(building: Building) -> int:
	return max(get_capacity(building) - get_used_space(building), 0)


# Quante unità della risorsa (dato il suo space_per_unit) entrano in UN singolo slot — 0 se
# un'unità da sola non entra nemmeno in uno slot vuoto (spazio_per_unità > storage_space_per_slot):
# caso limite, nessuna risorsa esistente oggi (pebble/stick) lo incontra mai (spazio_per_unità
# 1.0/10.0 contro slot da 50-100), ma store()/get_slots_used sotto lo trattano comunque come
# "questa risorsa non può mai essere stoccata qui" invece di un crash/comportamento indefinito.
static func _units_per_slot(building: Building, space_per_unit: float) -> int:
	if building == null or building.rules == null or space_per_unit <= 0.0:
		return 0
	return int(floor(float(building.rules.storage_space_per_slot) / space_per_unit))


# Slot INTERI necessari per `quantity` unità dato `units_per_slot` (arrotondato per eccesso — un
# ultimo slot parzialmente pieno conta comunque come 1 intero, coerente col principio "slot
# univoci" dichiarato in testa al file). units_per_slot <= 0 (risorsa che non entra mai in uno slot,
# vedi _units_per_slot sopra) ritorna comunque 1 per quantity > 0 — difensivo, non dovrebbe accadere
# con dati coerenti (store() sotto rifiuta il deposito prima di arrivare a usare questo valore).
static func _slots_for_quantity(quantity: int, units_per_slot: int) -> int:
	if quantity <= 0:
		return 0
	if units_per_slot <= 0:
		return 1
	return int(ceil(float(quantity) / float(units_per_slot)))


# Slot interi TOTALI già occupati da TUTTE le risorse stoccate (somma per tipo, ciascuno arrotondato
# per eccesso indipendentemente — vedi _slots_for_quantity) — la cifra che store() confronta con
# building.rules.storage_slot_count per decidere se un TIPO NUOVO (o l'ampliamento di uno esistente
# oltre il proprio ultimo slot) ha ancora posto.
static func get_slots_used(building: Building) -> int:
	if building == null or building.rules == null:
		return 0
	var total := 0
	for resource_name in building.stored_resources.keys():
		var entry: Dictionary = building.stored_resources[resource_name]
		var quantity: int = int(entry.get("quantity", 0))
		if quantity <= 0:
			continue
		var resource_rules := CaloricCalculator.get_caloric_source_rules(String(resource_name))
		if resource_rules == null:
			continue
		total += _slots_for_quantity(quantity, _units_per_slot(building, resource_rules.space_per_unit))
	return total


static func get_free_slots(building: Building) -> int:
	if building == null or building.rules == null:
		return 0
	return max(building.rules.storage_slot_count - get_slots_used(building), 0)


# DUE livelli, ENTRAMBI devono passare (2026-09-09, richiesta utente — Building.enabled_
# categories, il filtro per-istanza): il TIPO (BuildingRules.accepted_categories, condiviso da
# ogni istanza di quel tipo) resta il tetto massimo — un'istanza non può mai accettare una
# categoria che il proprio TIPO non accetta già, indipendentemente da cosa contenga enabled_
# categories. L'ISTANZA (Building.enabled_categories) può solo RESTRINGERE ulteriormente, mai
# ampliare. Array vuoto in ENTRAMBI i campi = nessuna restrizione a quel livello (stesso
# principio di AnimalRules.suitable_biomes/SubtypeRules.suitable_biomes) — un'istanza appena
# creata (enabled_categories vuoto di default, vedi Building.gd) accetta quindi esattamente tutto
# ciò che il proprio tipo accetta, nessun comportamento diverso finché il player non deflagga
# qualcosa esplicitamente. Una risorsa non risolvibile (resource_name senza .tres valido) non è
# mai accettabile, indipendentemente da entrambi i filtri: nessuna categoria da confrontare.
#
# SOLO categoria — non dice nulla su SE c'è ancora posto (vedi store() sotto, che può comunque
# depositare 0 anche con can_accept true se gli slot sono pieni): stesso principio "domande
# diverse" già separato in get_capacity/get_used_space. Consultato SOLO da store() (controllo IN
# ENTRATA) — mai da get_used_space/get_slots_used/get_slot_breakdown, che restano una lettura pura
# di stored_resources a prescindere da questo filtro: togliere una categoria da enabled_categories
# non tocca mai ciò che è già stoccato, impedisce solo nuovi depositi futuri di quella categoria.
static func can_accept(building: Building, resource_name: String) -> bool:
	if building == null or building.rules == null:
		return false
	# Guard is_complete (2026-09-11, richiesta utente — un cantiere non ancora finito non deve poter
	# ricevere depositi da NESSUN percorso, non solo da quello automatico di WarehouseSelectionService:
	# questa funzione è già il gate consultato sia da store() sotto sia dal comando manuale a destro-
	# click, GameScene._try_assign_unload_command_on_right_click — un solo punto, copre entrambi senza
	# doverlo ripetere altrove. Prima di questo fix un cantiere STORAGE era già utilizzabile come
	# magazzino PRIMA di essere completo, sia via ricerca automatica sia via deposito manuale (vedi la
	# nota "DA SEGNALARE" lasciata in GameScene._start_building_task_at quando la Build Task fu
	# introdotta, il 2026-09-10).
	if not building.is_complete:
		return false
	var resource_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if resource_rules == null:
		return false
	if not building.rules.accepted_categories.is_empty() and not building.rules.accepted_categories.has(resource_rules.category):
		return false
	if not building.enabled_categories.is_empty() and not building.enabled_categories.has(resource_rules.category):
		return false
	return true


# Elenco degli slot OCCUPATI (mai quelli vuoti — il chiamante, es. BuildingInfoPanel, sa già
# building.rules.storage_slot_count e riempie il resto con slot vuoti nella UI), un Dictionary
# {"resource_name", "quantity", "space_used", "space_capacity"} per slot, ordinati per tipo di
# risorsa nell'ordine di building.stored_resources (ordine di INSERIMENTO, stabile — Dictionary in
# GDScript preserva l'ordine di inserimento, sopravvive a save/load perché stored_resources viene
# serializzato/deserializzato come lo stesso Dictionary). Ultimo slot di ogni gruppo tipicamente
# parziale (space_used < space_capacity) — è esattamente quello il "posto residuo" che una
# quantità aggiuntiva della STESSA risorsa riempirebbe prima di aprirne uno nuovo (vedi store()).
static func get_slot_breakdown(building: Building) -> Array:
	var slots: Array = []
	if building == null or building.rules == null:
		return slots
	var slot_capacity_space: int = building.rules.storage_space_per_slot
	for resource_name in building.stored_resources.keys():
		var entry: Dictionary = building.stored_resources[resource_name]
		var quantity: int = int(entry.get("quantity", 0))
		if quantity <= 0:
			continue
		var resource_rules := CaloricCalculator.get_caloric_source_rules(String(resource_name))
		if resource_rules == null:
			continue
		var space_per_unit: float = resource_rules.space_per_unit
		var units_per_slot := _units_per_slot(building, space_per_unit)
		var remaining: int = quantity
		while remaining > 0:
			var quantity_in_slot: int = min(remaining, units_per_slot) if units_per_slot > 0 else remaining
			slots.append({
				"resource_name": String(resource_name),
				"quantity": quantity_in_slot,
				"space_used": int(round(float(quantity_in_slot) * space_per_unit)),
				"space_capacity": slot_capacity_space,
			})
			remaining -= quantity_in_slot
	return slots


# Deposita il massimo possibile dato lo SLOT libero (non il semplice spazio totale libero — vedi
# commento in testa al file sulla frammentazione) — stesso arrotondamento floor già usato in
# PickUpAction.activate (mai frazionario). Ritorna quanto è stato EFFETTIVAMENTE depositato (può
# essere 0 se non c'è più slot disponibile, o se la categoria non è accettata) — il chiamante
# (UnloadAction) decide cosa fare del resto non depositato, questo service non lo sa né lo tocca.
#
# Formula slot: il TOTALE di slot che questa risorsa può occupare (i propri, GIÀ contati dentro
# questo budget — non sommati una seconda volta) è tutto ciò che resta dopo aver sottratto gli slot
# delle ALTRE risorse dal totale ("slot univoci", mai condivisi con un tipo diverso). Quindi:
#   slot_usati_da_altri = slot_totali_usati - slot_già_usati_da_questa_risorsa
#   slot_massimi_per_questa_risorsa = storage_slot_count - slot_usati_da_altri
#   unità_massime_raggiungibili = slot_massimi_per_questa_risorsa × unità_per_slot
#   depositabile = min(quantity_richiesta, unità_massime_raggiungibili - quantità_già_presente)
#
# `decay_fraction` (2026-09-09, richiesta utente — Step 3 decadimento) — la frazione di
# decadimento di CIÒ CHE ARRIVA (tipicamente HumanIndividual.carried_decay_fraction, vedi
# UnloadAction.on_complete, il chiamante). Se la risorsa è già presente in questo edificio, si
# FONDE con quella esistente via MEDIA PESATA sulla quantità (mai sostituita, mai scartata):
#   nuova_decay_fraction = (quantità_esistente × decay_fraction_esistente
#                            + quantità_depositata × decay_fraction_in_arrivo) / quantità_totale
# Se non ancora presente, la entry nasce direttamente con decay_fraction (nessuna media, un solo
# termine). Default 0.0 (mai deperito) per chiamanti che non hanno ancora un concetto di decadimento
# da passare — comportamento invariato per loro.
static func store(building: Building, resource_name: String, quantity: int, decay_fraction: float = 0.0) -> int:
	if quantity <= 0 or not can_accept(building, resource_name):
		return 0

	var deposit_amount: int = min(quantity, get_max_depositable(building, resource_name))
	if deposit_amount <= 0:
		return 0

	var existing_entry: Dictionary = building.stored_resources.get(resource_name, {})
	var current_quantity: int = int(existing_entry.get("quantity", 0))
	var current_decay_fraction: float = float(existing_entry.get("decay_fraction", 0.0))

	var new_quantity: int = current_quantity + deposit_amount
	var new_decay_fraction: float = decay_fraction
	if current_quantity > 0:
		new_decay_fraction = (
			float(current_quantity) * current_decay_fraction + float(deposit_amount) * decay_fraction
		) / float(new_quantity)

	building.stored_resources[resource_name] = {"quantity": new_quantity, "decay_fraction": new_decay_fraction}
	return deposit_amount


# Quante unità di resource_name entrerebbero ANCORA in questo edificio ORA (2026-09-09, richiesta
# utente — estratto dalla prima metà della formula di store() sopra, per riuso da
# WarehouseSelectionService.find_best e da UnloadAction.activate, che devono chiedere "ci sta?"
# SENZA scrivere nulla — store() sotto ora chiama semplicemente questa funzione invece di duplicare
# la formula). Pura lettura: non modifica building.stored_resources. can_accept NON è ripetuto qui
# dentro (il chiamante che vuole anche il filtro di categoria lo controlla a parte, stesso principio
# "domande diverse" già dichiarato sopra per get_capacity/get_used_space/can_accept) — una risorsa
# la cui categoria non è accettata ritorna comunque un numero (probabilmente positivo) da questa
# funzione, il rifiuto sta SOLO in can_accept.
static func get_max_depositable(building: Building, resource_name: String) -> int:
	if building == null or building.rules == null:
		return 0
	# Guard is_complete (2026-09-11, richiesta utente) — STESSO motivo/STESSO commento esteso di
	# can_accept sopra: questa funzione è chiamata anche DIRETTAMENTE (non tramite can_accept, vedi il
	# commento in testa a questa funzione — "can_accept NON è ripetuto qui dentro") da
	# WarehouseSelectionService.find_best (has_capacity) e da UnloadAction.activate (riverifica
	# still_fits) — senza questo guard ANCHE qui, un cantiere incompleto sarebbe stato escluso da
	# store() (bloccato da can_accept) ma NON dalla selezione automatica del magazzino più vicino: un
	# individuo avrebbe potuto camminare fin lì e scoprire solo all'arrivo che il deposito fallisce
	# (deposited=0), un viaggio sprecato invece di scartare subito il candidato.
	if not building.is_complete:
		return 0
	var resource_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if resource_rules == null:
		return 0
	var units_per_slot := _units_per_slot(building, resource_rules.space_per_unit)
	if units_per_slot <= 0:
		return 0

	var existing_entry: Dictionary = building.stored_resources.get(resource_name, {})
	var current_quantity: int = int(existing_entry.get("quantity", 0))

	var slots_used_by_this_resource: int = _slots_for_quantity(current_quantity, units_per_slot)
	var slots_used_by_others: int = get_slots_used(building) - slots_used_by_this_resource
	var max_slots_for_this_resource: int = max(building.rules.storage_slot_count - slots_used_by_others, 0)
	var max_units_reachable: int = max_slots_for_this_resource * units_per_slot

	return max(max_units_reachable - current_quantity, 0)
