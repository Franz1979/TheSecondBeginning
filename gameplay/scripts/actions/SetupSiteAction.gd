class_name SetupSiteAction
extends Action

# Primo step "di lavoro" della Build Task (2026-09-10, richiesta utente — prima porzione del piano
# Build Task: trigger di piazzamento + SetupSiteAction; ClearAction è arrivata il 2026-09-11 come
# terzo step, vedi ClearAction.gd — BuildAction come quarto e ultimo). Stile ThinkAction (bersaglio
# TEMPORALE, un accumulatore confrontato con una durata fissa, stesso schema esatto get_stamina_
# delta/is_complete) — a differenza di ThinkAction, qui la durata NON arriva dal chiamante: è una
# costante interna fissa (vedi DURATION_DAYS sotto), perché oggi ogni edificio è monocella (nessuna
# variazione per dimensione/tipo ancora modellata — un futuro edificio multi-microcella richiederà
# probabilmente una durata derivata da rules, non più questa costante).
#
# target_building (2026-09-10) — iniettato dal costruttore, stesso principio "chi crea la Task
# decide già QUALE edificio" già seguito da UnloadAction.target_building/PickUpAction.macro_state:
# nessuna ricerca automatica qui. Serve a on_complete() per segnalare SU QUALE edificio il cantiere
# è stato allestito (vedi signal sotto).
#
# PROGRESSO SU Building.construction_progress["site_setup_days_done"], NON su un campo interno
# dell'istanza (2026-09-11, richiesta utente — "vogliamo che il progresso sopravviva a
# un'interruzione [riassegnazione della Task allo stesso individuo a metà step], stesso principio
# già applicato a BuildAction") — BUG CONFERMATO nella versione precedente di questo file: _elapsed
# viveva SOLO sull'istanza Action, mai scritto su Building. Un'interruzione (nuova Task assegnata
# allo stesso individuo, la vecchia Task/Action scartata SENZA passare da TaskPersistenceService —
# quel percorso esiste solo per un salvataggio/reload, non per una riassegnazione in-sessione)
# perdeva quindi silenziosamente ogni progresso maturato, ripartendo sempre da 0 alla prossima
# SetupSiteAction creata per lo stesso edificio. STESSA soluzione di BuildAction.labor_accumulated:
# _get_site_setup_days_done() sotto legge SEMPRE dal vivo da Building.construction_progress, mai da
# una cache interna — una nuova istanza costruita dopo un'interruzione la trova già lì e riparte
# da quel valore per costruzione, nessun intervento esplicito di "ripristino" necessario oltre a
# NON cachare mai il valore in un campo proprio (vedi il log in activate() sotto per la verifica a
# schermo). Nessun consumo di materiale — SOLO il passaggio di tempo/stamina e il segnale di
# completamento, per costruzione esplicita di questo passo (vedi discussione con l'utente).

# Emesso UNA VOLTA quando l'allestimento del cantiere si conclude (2026-09-10) — stesso principio
# di disaccoppiamento già seguito da PickUpAction.resource_collected/UnloadAction.thought_deposited:
# questa classe non conosce GameScene/MicroCellRenderer/live_cells, si limita a segnalare "il
# cantiere per QUESTO edificio è pronto", chi ha creato la Task (oggi GameScene._start_building_
# task_at) decide come reagire visivamente (i 4 placeholder "legnetti", vedi
# GameScene._spawn_build_site_placeholders).
signal site_setup_completed(building: Building)

# Drain di stamina al GIORNO — STESSO valore di ThinkAction.STAMINA_DRAIN_PER_DAY (10.0): nessun
# valore migliore noto per "allestire un cantiere" oggi, stesso trattamento "da bilanciare in
# seguito" di ogni altra costante di questo sistema. Costante separata (non condivisa/importata da
# ThinkAction) per lo stesso motivo già seguito ovunque nel progetto: nessuna costante condivisa
# tra Action diverse.
const STAMINA_DRAIN_PER_DAY: float = 100.0

# Costo di HAPPINESS al GIORNO (2026-09-13, richiesta utente: "-10.0/day") — costante separata,
# stesso principio "nessuna costante condivisa tra Action" già dichiarato sopra.
const HAPPINESS_DRAIN_PER_DAY: float = 10.0

# Durata FISSA — 1 giorno di gioco, edifici monocella (2026-09-10, richiesta esplicita utente: "per
# ora, edifici monocella"). Non un parametro di costruttore come ThinkAction.duration: finché ogni
# edificio occupa una sola microcella non c'è alcuna variazione da esprimere — un futuro edificio
# multi-microcella/con rules.required_space maggiore probabilmente vorrà una durata derivata,
# quel giorno questa costante diventerà un campo risolto dal chiamante, stesso schema di
# ThinkAction.duration.
const DURATION_DAYS: float = 1.0

# Fabbisogno materiale (2026-09-13, richiesta utente — Build Task collegata a un vero fabbisogno
# di materiale, SOLO per questo step, BuildAction resta bypassata; RICALIBRATO 2026-09-14, richiesta
# utente — la quantità NON va confusa con required_materials, che descrive il fabbisogno della
# COSTRUZIONE vera e propria: SEMPRE 4 stick per microcella occupata dal cantiere durante la fase
# SetupSite, un fabbisogno concettualmente distinto) — nome/quantità letti da
# BuildingRules.setup_site_material_name/setup_site_material_per_cell (vedi quel file per il
# perché il dato vive lì, non qui: BuildingStorageService.can_accept/get_max_depositable, in
# simulation/, legge la STESSA fonte per il proprio tetto di deposito su un cantiere non finito —
# un'unica fonte di verità su una classe che entrambi i livelli possono leggere).
var target_building: Building = null


func _init(p_target_building: Building = null) -> void:
	target_building = p_target_building
	target = null
	# INFANT non può eseguire questa Action (2026-09-12, richiesta utente — collegamento AgeBand.
	# INFANT al gameplay, vedi Action.disallowed_age_bands). CHILD aggiunto 2026-09-13 (richiesta
	# utente).
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


# Lettura pura di Building.construction_progress["site_setup_days_done"] — 0.0 se target_building è
# null o se la chiave non esiste ancora (primissimo giorno di lavoro su questo cantiere). STESSA
# funzione/STESSO principio di BuildAction._get_labor_accumulated.
func _get_site_setup_days_done() -> float:
	if target_building == null:
		return 0.0
	return float(target_building.construction_progress.get("site_setup_days_done", 0.0))


# Quantità del materiale di setup site (BuildingRules.setup_site_material_name) ancora mancante
# rispetto al tetto richiesto (setup_site_material_per_cell × required_space) — 0 se target_building/
# rules non risolvibili, o se ne è già stoccato a sufficienza. STESSO dato/STESSA chiave già letti
# da BuildingStorageService.can_accept/get_max_depositable per il proprio gate di deposito (vedi
# il commento esteso su BuildingRules.setup_site_material_name/setup_site_material_per_cell) —
# lettura pura, mai una scrittura, coerente col resto di questa classe (site_setup_days_done sopra
# è l'unico stato mutato da questa Action).
#
# PUBBLICA, non più "_"-prefissata (2026-09-14, richiesta utente — controllo giornaliero di
# ritentativo per un individuo bloccato): HumanIndividualActionService.retry_blocked_material_
# shortages deve poterla chiamare dall'esterno per scoprire "questo SetupSiteAction è ancora
# bloccato?" senza duplicare la formula required-meno-stored — stesso principio "unica fonte di
# verità" già dichiarato sopra, esteso ora anche al confronto stesso.
func get_missing_material_quantity() -> int:
	if target_building == null or target_building.rules == null:
		return 0
	var required: int = target_building.rules.setup_site_material_per_cell * target_building.rules.required_space
	if required <= 0:
		return 0
	var stored_entry: Dictionary = target_building.stored_resources.get(target_building.rules.setup_site_material_name, {})
	var stored: int = int(stored_entry.get("quantity", 0))
	return max(required - stored, 0)


# Fabbisogno materiale (2026-09-13, richiesta utente) — controllato ad OGNI attivazione di questo
# step: sia la primissima volta che diventa lo step corrente, sia OGNI ripresa dalla coda personale
# dopo una Transport Task consegnata (parziale o meno) — mai una verifica "una tantum". Se manca
# ancora materiale, questa Action NON procede affatto questo giro: nessun log di progresso (return
# anticipato, il vecchio log "[BUILD PROGRESS DEBUG]" sotto non viene raggiunto), si limita a
# scrivere la richiesta in context — STESSO canale/STESSO principio già usato da PickUpAction.
# on_complete/UnloadAction.activate per pending_warehouse_search (un Dictionary "di richiesta",
# consumato da un chiamante esterno che sa risolvere Building/World/WarehouseSelectionService, mai
# da questa classe — vedi HumanIndividualActionService._handle_pending_material_shortage). Il
# "blocco" vero e proprio (zero costo, mai completa) è comunque garantito ANCHE da get_stamina_
# delta/get_happiness_delta/is_complete sotto, indipendentemente da questo flag: quello che scrive
# qui serve solo a FAR PARTIRE la Transport Task il prima possibile, non a impedire da solo
# l'avanzamento (il vero gate vive nei tre metodi sotto, così anche il caso limite "nessun
# magazzino sorgente trovato" — fuori scope in questo giro, vedi quel service — resta comunque
# bloccato invece di procedere per sbaglio).
func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	# Guardia site_setup_complete (bugfix — "i rametti spariscono ricostruendo la Build Task"): una
	# volta che la fase è VERAMENTE conclusa una prima volta, questo step non deve più leggere
	# get_missing_material_quantity() da capo. required_materials della fase BUILD (BuildAction)
	# usa spesso lo STESSO resource_name di setup_site_material_name (oggi sempre "stick") sulla
	# STESSA voce di stored_resources — senza questa guardia, una SetupSiteAction ricostruita da
	# zero (TaskReassignmentService.reassign_task, ad ogni ripresa/riassegnazione) rileggeva
	# "materiale presente" ogni volta che lo stock accumulato per il Build superava per caso la
	# soglia di setup, credendo erroneamente di dover (ri)completare questa fase.
	if target_building != null and target_building.site_setup_complete:
		return
	var missing := get_missing_material_quantity()
	if missing > 0:
		# "missing" ora un Dictionary[String, int] (2026-09-14, richiesta utente — generalizzato per
		# BuildAction, che può avere PIÙ risorse mancanti insieme, vedi quel file) — SetupSiteAction
		# ne ha sempre e sola una, un Dictionary a una sola voce resta comunque la stessa forma letta
		# da HumanIndividualActionService._handle_pending_material_shortage/_resolve_material_shortage,
		# nessun ramo speciale per il caso "una sola risorsa".
		context["pending_material_shortage"] = {
			"missing": {target_building.rules.setup_site_material_name: missing},
			"target_building_id": target_building.id,
		}
		return
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS and target_building != null:
		print("[BUILD PROGRESS DEBUG] SetupSiteAction attivata per building #%d: riparte da site_setup_days_done=%.2f (era 0.0 se prima volta)" % [
			target_building.id, _get_site_setup_days_done()
		])


# Scrive l'avanzamento INCREMENTALE direttamente su Building.construction_progress ad ogni drain
# (2026-09-11) — STESSO pattern di BuildAction.get_stamina_delta: nessun accumulatore interno,
# lettura+scrittura sempre dal vivo, così il progresso resta sempre coerente con Building anche se
# questa istanza viene distrutta a metà (interruzione) o ricostruita (reload). Guardia materiale
# (2026-09-13) AGGIUNTA in testa, PRIMA di quella su site_setup_days_done: mentre manca materiale
# questo step non deve MAI accumulare progresso, indipendentemente da chi/quando consumi il
# pending_material_shortage scritto da activate() sopra (vedi quel commento esteso).
func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if target_building == null:
		return 0.0
	if target_building.site_setup_complete:
		return 0.0
	if get_missing_material_quantity() > 0:
		return 0.0
	if _get_site_setup_days_done() >= DURATION_DAYS:
		return 0.0
	target_building.construction_progress["site_setup_days_done"] = _get_site_setup_days_done() + delta
	return -STAMINA_DRAIN_PER_DAY * delta


# STESSE guardie di get_stamina_delta sopra (lettura, mai scrittura di site_setup_days_done: già
# incrementato da get_stamina_delta nello stesso frame — vedi la nota in Action.get_happiness_
# delta). Tasso fisso.
func get_happiness_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if target_building == null:
		return 0.0
	if target_building.site_setup_complete:
		return 0.0
	if get_missing_material_quantity() > 0:
		return 0.0
	if _get_site_setup_days_done() >= DURATION_DAYS:
		return 0.0
	return -HAPPINESS_DRAIN_PER_DAY * delta


# Guardia materiale (2026-09-13) AGGIUNTA — mai completa mentre manca materiale, indipendentemente
# da site_setup_days_done (che può anche essere già a target da un tentativo precedente, se mai
# possibile): il completamento resta subordinato a ENTRAMBE le condizioni.
func is_complete(individual: Variant, context: Dictionary) -> bool:
	if target_building != null and target_building.site_setup_complete:
		return true
	if get_missing_material_quantity() > 0:
		return false
	return _get_site_setup_days_done() >= DURATION_DAYS


# get_required_position (2026-09-13, richiesta utente — fix "Walk di ritorno alla ripresa", vedi
# Action.get_required_position e RetrieveAction.get_required_position per la stessa identica
# formula/stesso commento esteso, duplicata qui apposta — nessuna costante/funzione condivisa tra
# Action diverse, stesso principio già seguito ovunque in questo sistema).
func get_required_position(individual: Variant, context: Dictionary) -> Variant:
	if target_building == null:
		return null
	var macro_offset: Vector2 = Vector2(Vector2i(target_building.macro_x, target_building.macro_y) - individual.home_macro_coords) * World.WIDTH
	return Vector2(target_building.micro_x, target_building.micro_y) + macro_offset


# Consumo del materiale di setup site (2026-09-14, richiesta utente — BUG CONFERMATO: nessun punto
# del codice rimuoveva mai target_building.stored_resources[setup_site_material_name] dopo il
# completamento di questo step — i 4 stick depositati per allestire il cantiere restavano lì per
# sempre, occupando uno slot di storage vero e proprio per il resto della vita dell'edificio anche
# a costruzione COMPLETA, es. su un deposit_site/hut che hanno storage_slot_count>0). Rimossi QUI
# (non da BuildAction.on_complete, il passo successivo): il materiale ha esaurito il proprio scopo
# nell'ISTANTE in cui il cantiere è allestito, indipendentemente da quanto dureranno ancora
# Clear/Build — erase() intero (non un decremento quantità), coerente con "consumato", non "ancora
# in giacenza parziale".
func on_complete(individual: Variant, context: Dictionary) -> void:
	# Guardia site_setup_complete — idempotenza (bugfix, stesso principio di ClearAction.
	# construction_progress["space_reserved"]): senza questo return anticipato, ogni ricostruzione
	# della Build Task per un edificio la cui fase SetupSite è GIÀ conclusa (is_complete() sopra
	# ritorna comunque true, per costruzione) rieseguirebbe l'erase() sotto — cancellando lo stock
	# della STESSA risorsa che nel frattempo la fase BUILD sta accumulando per il proprio
	# required_materials (oggi sempre "stick" per entrambe le fasi, vedi BuildingRules.
	# setup_site_material_name).
	if target_building != null and target_building.site_setup_complete:
		return
	if target_building != null and target_building.rules != null:
		target_building.stored_resources.erase(target_building.rules.setup_site_material_name)
	# is_awaiting_material -> false (2026-09-14, richiesta utente — bugfix: "a edificio terminato
	# continua a uscire nell'info panel 'servono ancora 4 rametti'") — BUG CONFERMATO: questo flag
	# diventava true quando il cantiere si bloccava (HumanIndividualActionService._resolve_material_
	# shortage), ma per QUALUNQUE edificio diverso da deposit_site (l'unico con un ramo bonus che lo
	# azzerava) nulla lo rimetteva mai a false dopo che il materiale arrivava manualmente — activate()
	# (l'unico altro punto che un tempo lo azzerava) non viene richiamato di nuovo finché lo step
	# resta bloccato sullo STESSO step (nessuna riattivazione, solo get_stamina_delta/is_complete
	# rieseguiti ogni frame), quindi restava true per sempre anche a costruzione già completata. QUI,
	# non altrove: on_complete() scatta esattamente e solo quando questo step è DAVVERO concluso con
	# successo (is_complete() lo richiede, materiale già garantito presente) — punto unico e
	# affidabile per "il blocco, se c'era, è ormai risolto". Idempotente/innocuo se era già false.
	if target_building != null:
		target_building.is_awaiting_material = false
	site_setup_completed.emit(target_building)


# Persistenza (2026-09-11, richiesta utente, punto 4 del giro precedente) — SOLO target_building_id
# (dato "di identità" del costruttore): nessun progresso da salvare qui, vedi il commento in testa
# al file — site_setup_days_done vive su Building.construction_progress, già serializzato per
# intero da GameSaveService/GameLoadService, persiste "gratis" senza che questa classe debba fare
# nulla. Nessun load_save_data() sovrascritto (l'implementazione NEUTRA di Action.gd resta valida):
# nessuno stato interno da questa classe da ripristinare oltre a target_building, già risolto e
# passato al costruttore da TaskPersistenceService._build_step.
func get_save_data() -> Dictionary:
	var data := {}
	if target_building != null:
		data["target_building_id"] = target_building.id
	return data
