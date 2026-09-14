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

# Vero se esiste ALMENO UN Building COMPLETO con vera capacità di storage (2026-09-13/14, richiesta
# utente — "bonus di partenza" per il fabbisogno stick di SetupSiteAction: NON legato a "questo è il
# primo edificio della partita" — legato a "esiste GIÀ ALTROVE nel villaggio spazio di storage
# utilizzabile", indipendentemente da quanti edifici sono già stati costruiti prima o dopo: se
# l'unico storage esistente venisse in futuro demolito, il prossimo cantiere torna a ricevere il
# bonus automaticamente, nessuna logica "solo se è il primo in assoluto"). Scansione lineare di
# world.buildings, stesso principio "costo accettabile finché il numero di edifici resta piccolo"
# già assunto altrove nel progetto (es. TaskPersistenceService._find_building_by_id,
# HumanIndividualActionService._find_building_by_id). `get_capacity(building) > 0` (2026-09-14,
# richiesta utente — FIX: prima controllava solo storage_slot_count > 0, ignorando
# storage_space_per_slot: "storage slot e storage space", ENTRAMBI devono dare capacità reale >0,
# stessa formula già usata da get_capacity sotto — un tipo con uno dei due a 0, es. Stick Tent/
# Pebble Circle, storage_slot_count=storage_space_per_slot=0, non conta come "storage reale" anche
# se completo). `is_complete` obbligatorio: un cantiere che ha ricevuto il proprio bonus di
# partenza e non è ancora finito non deve "sbloccare" il ciclo normale per il PROSSIMO cantiere —
# solo uno storage DAVVERO utilizzabile lo fa. Richiamata ad OGNI attivazione di SetupSiteAction
# (mai cachata).
static func world_has_any_storage_building(world: World) -> bool:
	if world == null:
		return false
	for building in world.buildings:
		if building.is_complete and get_capacity(building) > 0:
			return true
	return false


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
	# Guard is_demolished (2026-09-12, richiesta utente — bugfix "deposito nel vuoto") — SEMPRE
	# valutato per primo, indipendentemente da is_complete sotto: un edificio demolito (completo o
	# meno) non deve mai accettare nulla da nessun percorso. Un individuo con una Task già in corso
	# verso questo edificio (Walk+Unload) tiene un riferimento diretto che resta valido anche dopo la
	# demolizione (vedi Building.is_demolished per il perché).
	if building.is_demolished:
		return false
	var resource_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if resource_rules == null:
		return false
	# Guard is_complete SOSTITUITO (2026-09-12, richiesta utente) — PRIMA (2026-09-11) rifiutava
	# INCONDIZIONATAMENTE qualunque deposito su un cantiere non finito ("un cantiere non ancora finito
	# non deve poter ricevere depositi da NESSUN percorso"), impedendo per costruzione anche il
	# trasporto dei materiali richiesti per costruirlo — un problema reale ora che la Build Task dovrà
	# poter consegnare quei materiali. Nuova condizione più fine: un cantiere può accettare SOLO la
	# risorsa del proprio fabbisogno di SETUP SITE (BuildingRules.setup_site_material_name — RICALIBRATO
	# 2026-09-14, richiesta utente: NON più rules.required_materials, che resta riservato al fabbisogno
	# della costruzione vera e propria, futura BuildAction, un fabbisogno concettualmente distinto — vedi
	# quel campo su BuildingRules.gd), e SOLO fino al tetto esatto richiesto (setup_site_material_per_cell
	# × required_space) — mai altre risorse (continua a comportarsi come un magazzino generico per
	# QUALUNQUE altra risorsa, esattamente come impediva il guard precedente), mai oltre quel tetto
	# (evita che un cantiere accumuli scorte in eccesso come se fosse un vero magazzino). Un edificio
	# COMPLETO non passa mai da questo ramo — comportamento sotto INVARIATO per lui.
	if not building.is_complete:
		# `building.site_setup_complete` (2026-09-14, richiesta utente — bugfix "il materiale non
		# spariva mai": SetupSiteAction.on_complete ora CONSUMA il materiale, vedi quel file — ma
		# senza questo guard un deposito MANUALE tardivo, durante Clear/Build dopo che il setup è
		# già concluso, potrebbe ricrearlo da capo, restando poi lì per sempre esattamente come il
		# bug originale) — return false ESPLICITO, non un fall-through alle regole "edificio
		# completo" sotto: un cantiere in Clear/Build NON è comunque un vero magazzino, il setup
		# concluso significa solo "nessun ulteriore deposito ha senso", mai "accetta come se fosse
		# finito".
		if building.site_setup_complete:
			return false
		if resource_name != building.rules.setup_site_material_name:
			return false
		var required_quantity: int = building.rules.setup_site_material_per_cell * building.rules.required_space
		if required_quantity <= 0:
			return false
		var stored_entry: Dictionary = building.stored_resources.get(resource_name, {})
		var stored_quantity: int = int(stored_entry.get("quantity", 0))
		return stored_quantity < required_quantity
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
	# Guard is_demolished (2026-09-12, richiesta utente — bugfix "deposito nel vuoto") — SEMPRE
	# valutato per primo, indipendentemente da is_complete sotto: STESSO motivo/STESSA posizione di
	# can_accept sopra (chiamata anche DIRETTAMENTE da WarehouseSelectionService.find_best/
	# UnloadAction.activate, vedi lì) — un edificio demolito deve risultare "senza posto" da
	# QUALUNQUE punto lo interroghi.
	if building.is_demolished:
		return 0
	var resource_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if resource_rules == null:
		return 0

	var existing_entry: Dictionary = building.stored_resources.get(resource_name, {})
	var current_quantity: int = int(existing_entry.get("quantity", 0))

	# Ramo CANTIERE (2026-09-13, richiesta utente — fix corretto per il vincolo di spazio durante
	# la costruzione, Parte B: DERIVATO dal fabbisogno reale, nessun campo statico per-edificio da
	# configurare) — SOSTITUISCE l'approccio precedente (spazio fisico calcolato via storage_slot_
	# count/storage_space_per_slot, poi combinato con min() al tetto di required_materials): quei
	# due campi restano il vero magazzino, valido SOLO a edificio completo (vedi sotto), MAI
	# consultati qui. RICALIBRATO 2026-09-14 (richiesta utente) — durante la costruzione il vincolo
	# LOGICO (quanto serve) e quello FISICO (quanto entra) sono ORA setup_site_material_per_cell ×
	# required_space per resource_name == setup_site_material_name (BuildingRules.gd), NON più
	# rules.required_materials[resource_name]: quel Dictionary resta riservato al fabbisogno della
	# costruzione vera e propria (futura BuildAction), un fabbisogno concettualmente DIVERSO da
	# quello del cantiere (vedi il commento esteso su BuildingRules.setup_site_material_name/
	# setup_site_material_per_cell per il perché della separazione). Qualunque altro resource_name
	# → 0: un cantiere non deve mai accettare altro che il materiale di cui ha bisogno per il
	# proprio allestimento. `building.site_setup_complete` (2026-09-14, richiesta utente — STESSO
	# guard/STESSO motivo di can_accept sopra): una volta concluso il setup, zero posto residuo per
	# il proprio materiale, indipendentemente da is_complete (Clear/Build possono durare ancora
	# a lungo dopo).
	if not building.is_complete:
		if building.site_setup_complete:
			return 0
		if resource_name != building.rules.setup_site_material_name:
			return 0
		var required_quantity: int = building.rules.setup_site_material_per_cell * building.rules.required_space
		return max(required_quantity - current_quantity, 0)

	# Ramo edificio COMPLETO — comportamento ESATTAMENTE INVARIATO rispetto a sempre: storage_slot_
	# count/storage_space_per_slot come UNICO vincolo (mai required_materials qui, un edificio finito
	# può stoccare qualunque categoria accettata, non solo i propri ex-materiali da costruzione).
	var units_per_slot := _units_per_slot(building, resource_rules.space_per_unit)
	if units_per_slot <= 0:
		return 0
	var slots_used_by_this_resource: int = _slots_for_quantity(current_quantity, units_per_slot)
	var slots_used_by_others: int = get_slots_used(building) - slots_used_by_this_resource
	var max_slots_for_this_resource: int = max(building.rules.storage_slot_count - slots_used_by_others, 0)
	var max_units_reachable: int = max_slots_for_this_resource * units_per_slot
	return max(max_units_reachable - current_quantity, 0)


# Preleva fino a `quantity_requested` unità di resource_name da questo edificio (2026-09-12,
# richiesta utente — RetrieveAction, operazione simmetrica di store() sopra ma in prelievo invece
# che in deposito). NESSUNA interazione con is_complete/is_demolished — a differenza di can_accept/
# get_max_depositable/store (che restano gate SOLO per il deposito), il prelievo funziona su
# QUALUNQUE building con stored_resources, completo o in costruzione: il caso "recupero materiale
# da un cantiere abortito" richiede esplicitamente che funzioni anche con is_complete == false.
# (Nessun guard esplicito is_demolished nemmeno qui: un edificio demolito ha già stored_resources
# svuotato da GameScene._demolish_building — punto 3 — quindi current_quantity sotto risulta
# comunque 0 per costruzione, stesso risultato di un guard esplicito senza doverne scrivere uno.)
#
# Preleva quel che c'è anche se MENO di quanto richiesto (mai un fallimento, nessuna quantità
# minima) — il chiamante (RetrieveAction) decide cosa fare della differenza, stesso principio
# "quanto è stato EFFETTIVAMENTE fatto" già seguito da store() sopra. Ritorna la quantità
# EFFETTIVAMENTE prelevata.
#
# decay_fraction della quantità RIMASTA lasciata INVARIATA (stesso principio "lotto unico" di
# store(): è una media pesata sull'INTERO stock, non cambia prelevandone una PARTE — chi preleva
# porta con sé la stessa identica media, che il chiamante legge a parte PRIMA di questa chiamata,
# mai calcolata qui dentro, vedi RetrieveAction.on_complete). Entry rimossa dal Dictionary quando la
# quantità residua arriva a 0 — stesso trattamento già riservato altrove a stored_resources quando
# una risorsa si esaurisce (es. ResourceDecayService.advance_building_decay a decadimento completo).
static func withdraw(building: Building, resource_name: String, quantity_requested: int) -> int:
	if building == null or quantity_requested <= 0:
		return 0
	var existing_entry: Dictionary = building.stored_resources.get(resource_name, {})
	var current_quantity: int = int(existing_entry.get("quantity", 0))
	if current_quantity <= 0:
		return 0

	var withdrawn: int = min(quantity_requested, current_quantity)
	var remaining_quantity: int = current_quantity - withdrawn
	if remaining_quantity <= 0:
		building.stored_resources.erase(resource_name)
	else:
		building.stored_resources[resource_name] = {
			"quantity": remaining_quantity,
			"decay_fraction": float(existing_entry.get("decay_fraction", 0.0)),
		}
	return withdrawn
