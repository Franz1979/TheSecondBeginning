class_name HumanIndividualActionService
extends RefCounted

# Emesso QUANDO Building.is_awaiting_material passa da false a true — SOLO la transizione, MAI ad
# ogni tentativo fallito successivo (2026-09-14, richiesta utente — segnalazione player per un
# cantiere bloccato per mancanza di materiale) — vedi _resolve_material_shortage per il punto
# esatto in cui scatta. GameScene (che possiede sia questa istanza, individual_action_service, sia
# notification_popup) si collega una volta in _ready(), stesso principio già seguito per
# GameTimeService.individual_resource_decayed -> GameScene._on_individual_resource_decayed
# (l'unico altro segnale di dominio che già finisce in un popup) — non un nuovo canale, la stessa
# convenzione. Portare un segnale (non una chiamata diretta a NotificationPopup) mantiene questo
# service ignaro di UI/NotificationPopup, esattamente come richiesto per ogni altro *Service del
# progetto.
signal building_material_blocked(building: Building)

# Emesso QUANDO _handle_pending_warehouse_search scarta DAVVERO il carico di un individuo per
# mancanza di destinazione (2026-09-14, richiesta utente — step C del piano "rerouting": "rendiamo
# esplicito il discard con un simbolo sulla mappa") — copre ENTRAMBI gli scenari B1/B2 di quella
# funzione (nessun candidato trovato, sia per una ricerca iniziale sia per un re-routing), stesso
# unico punto in cui individual.discard_carried_resource() viene chiamato da questo file. Portato
# come segnale (non una chiamata diretta a un effetto visivo) per lo stesso motivo di
# building_material_blocked sopra: questo service resta ignaro di GameScene/MicroCellRenderer,
# chi ascolta decide come e se reagire visivamente. resource_name/quantity passati ESPLICITI (non
# letti da individual dopo il fatto, che discard_carried_resource() ha già azzerato) — sono gli
# stessi valori locali già risolti da search["resource_name"]/search["quantity"] in
# _handle_pending_warehouse_search, il vero residuo scartato.
signal carried_resource_discarded(individual: HumanIndividual, resource_name: String, quantity: int)

# Servizio single-responsibility (stesso pattern di HumanIndividualMovementService, stesso
# livello/cartella): applica lo step ATTIVO della Task corrente di un HumanIndividual
# (individual.current_task), se presente — costo/recupero di stamina E happiness (2026-09-13,
# richiesta utente — secondo meccanismo parallelo, vedi Action.get_happiness_delta) per questo
# istante, poi verifica se quello step è concluso e fa avanzare la Task di conseguenza. Girato ogni
# frame da GameScene._process, DOPO individual_movement_service.advance_movement (vedi lì per il
# perché dell'ordine: WalkAction.get_stamina_delta calcola la distanza percorsa confrontando
# individual.position con l'ultima nota, quindi deve leggere la position già aggiornata di questo
# frame — e advance_movement NON chiama più individual.stop() all'arrivo, vedi lì: è QUESTO
# servizio, non quello, a decidere quando una Task è davvero conclusa).
#
# current_happiness è clampata a 0 verso il basso (2026-09-19, richiesta utente: nessun parametro
# vitale scende sotto 0; prima poteva andare in negativo) — l'auto-interrupt quando si esaurisce
# arriverà in uno step successivo. Il tetto massimo GIORNALIERO (non per-frame) resta responsabilità di
# HumanStaminaIndividualService/HumanVitalsIndividualService, mai di questo servizio.
# current_stamina INVECE è clampata a 0 verso il basso qui sotto (richiesta utente — blocco task
# sotto la soglia di Emergency Rest): non deve mai scendere sotto zero, altrimenti il rapporto
# current_stamina/max_stamina usato da _resolve_active_stamina_need_priority/can_assign_task
# risulterebbe negativo invece di restare fermo a 0.0.

# Sistema di interrupt/coda da stamina critica (2026-09-13, richiesta utente) — soglie sul
# rapporto current_stamina/max_stamina, valutate OGNI frame per l'individuo attivo (vedi
# _resolve_active_stamina_need_priority/_handle_stamina_interrupt sotto). Numero più BASSO =
# priorità più urgente, STESSO significato/STESSI valori di Task.interrupt_priority (10 =
# emergency_rest.tres, 30 = rest.tres, passo 10 per lasciare spazio ai bisogni futuri come fame e sete) — le due soglie sotto sono la fonte di verità che decide
# QUANDO ciascuna delle due priorità è "attiva", non duplicate altrove.
const STAMINA_EMERGENCY_REST_THRESHOLD: float = 0.05
const STAMINA_REST_THRESHOLD: float = 0.20

# Priorita' di interrupt delle due Task-bisogno di stamina (2026-09-19, richiesta utente): rinumerate da
# 1/2 a 10/30 (passo 10, spazio per i bisogni futuri: fame, sete). Devono coincidere con
# interrupt_priority di emergency_rest.tres e rest.tres. Numero piu' BASSO = piu' urgente. Usate da
# _resolve_active_stamina_need_priority, dai confronti in _handle_stamina_interrupt/
# resolve_idle_individual e da HumanIndividual.can_assign_task (soglia di emergenza).
const INTERRUPT_PRIORITY_EMERGENCY_REST: int = 10
const INTERRUPT_PRIORITY_REST: int = 30

# Priorita' di interrupt del bisogno di PROVVISTE (2026-09-19, richiesta utente): stesso schema di
# quelle di stamina sopra, in un blocco a se' (mai fuso con esse): UNA sola priorita', l'emergenza
# restock (20), tra Emergency Rest (10) e Rest (30). Numero piu' BASSO = piu' urgente. Il rifornimento
# NON emergenziale non e' un bisogno-interrupt: sara' una Task perditempo (leisure_restock) con
# interrupt_priority -1, come wander e leisure_rest. Letta da _resolve_active_food_need_priority, da HumanIndividual.can_assign_task e dagli agganci
# automatici (_handle_food_interrupt, resolve_idle_individual) che assegnano emergency_restock.
const INTERRUPT_PRIORITY_EMERGENCY_RESTOCK: int = 20

# Soglia di autonomia delle provviste, in giorni (food_calories_held / consumo calorico giornaliero):
# fino a questa (compresa) e' emergenza.
const FOOD_AUTONOMY_EMERGENCY_DAYS: float = 1.0
# Tolleranza sul confronto dell'emergenza (2026-09-19): l'autonomia e' un rapporto di float e le
# calorie scendono per sottrazioni ripetute, quindi "esattamente 1 giorno" puo' risultare 1.0000000002.
# Senza tolleranza il confronto <= mancherebbe proprio il caso che deve scattare.
const FOOD_AUTONOMY_EPSILON: float = 0.001

# `world` (2026-09-09, richiesta utente — nato per il re-routing UnloadAction su magazzino pieno,
# poi GENERALIZZATO alla ricerca magazzino post-PickUp, vedi _handle_pending_warehouse_search
# sotto) — DEVIAZIONE rispetto alla firma precedente (solo individual/delta): necessario per passare
# a WarehouseSelectionService.find_best, che deve conoscere World.buildings per scegliere un
# magazzino. Default null (non `world: World` obbligatorio) così qualunque futuro chiamante che non
# ha ancora un World a portata di mano non rompe la compilazione — _handle_pending_warehouse_search
# tratta world null come "nessun candidato disponibile" (stesso comportamento del ramo "nessun
# magazzino trovato", vedi lì), mai un crash. UNICO call site oggi: GameScene._process, che passa
# macro_world.
#
# `game_data` (2026-09-13, richiesta utente, sistema di interrupt/coda da stamina critica) — STESSA
# DEVIAZIONE/STESSO principio di `world` sopra: necessario per risolvere l'age_band dell'individuo
# (vedi _resolve_age_band sotto) quando questo service assegna da sé una Task-bisogno tramite
# NeedTaskAssignmentService, che richiede un age_band per individual.assign_task(). Default null —
# se assente, l'intero sistema di interrupt automatico resta disattivato per questa chiamata
# (_handle_stamina_interrupt/_handle_task_completion_need_and_queue tornano no-op), mai un crash:
# stesso comportamento "difensivo, non un caso reale" già riservato a world null sopra. UNICO call
# site oggi: GameScene._process, che passa il proprio game_data.
func apply_action(individual: HumanIndividual, delta: float, world: World = null, game_data: GameData = null) -> void:
	# Fallback di rest implicito RIMOSSO (2026-09-12, richiesta utente — "un individuo senza
	# current_task valida deve semplicemente non fare nulla qui: nessun recupero automatico, nessun
	# consumo automatico"). Un individuo con current_task null/conclusa resta a stamina invariata
	# indefinitamente finché non gli viene assegnata manualmente una nuova Task — il vero recupero
	# stamina tornerà a breve dentro una Rest Task esplicita (Walk verso casa + RestAction), non
	# più come fallback implicito di questa funzione. Verificato (indagine dedicata, giro
	# precedente): ogni lettore di current_task/current_action nel codebase è già null-safe, e
	# questo era l'UNICO punto dell'intero progetto che rigenerava current_stamina — rimuoverlo
	# senza sostituto è quindi una regressione di gameplay attesa/temporanea, non un bug.
	if individual.current_task == null or individual.current_task.is_finished():
		return
	# Avanzamento automatico Task (2026-09-07, richiesta utente, introdotto insieme a Task) —
	# applica lo step ATTIVO (mai la Task intera: Task non sa nulla di stamina, vedi Task.gd), poi
	# se quello step è concluso fa avanzare l'indice: se la Task risulta conclusa DOPO l'avanzamento
	# ferma per davvero l'individuo (stop(), che azzera is_moving/current_task — vedi HumanIndividual.
	# gd), altrimenti attiva subito il nuovo step attivo (activate(), vedi Action.gd/WalkAction.gd)
	# così il movimento prosegue senza soluzione di continuità verso la destinazione successiva,
	# nello stesso frame in cui il precedente è arrivato — nessun frame "fermo" in mezzo.
	# `task` tenuto in una variabile locale (2026-09-07, necessario per il log di costo sotto):
	# individual.stop() azzera individual.current_task, quindi senza questo riferimento la Task non
	# sarebbe più raggiungibile nel momento in cui va stampato il suo riepilogo costi.
	var task := individual.current_task

	# Fabbisogno materiale (2026-09-13, richiesta utente — Build Task collegata a un vero
	# fabbisogno di materiale) — controllato QUI, PRIMA di risolvere `action`/calcolare qualunque
	# delta di questo frame: se SetupSiteAction.activate() ha scritto una richiesta (vedi
	# SetupSiteAction.gd per il perché "ad ogni attivazione", non solo la prima), questo step non
	# deve accumulare NULLA questo frame — stesso principio già seguito da _handle_stamina_interrupt
	# sotto (bool di ritorno, return immediato se ha sostituito individual.current_task: `task`
	# locale non sarebbe più valido). A differenza di _handle_stamina_interrupt (valutato DOPO i
	# delta, righe sotto), questo va PRIMA: quel meccanismo reagisce a uno stato che è già maturato
	# questo frame, questo invece deve IMPEDIRE che una Action bloccata maturi alcunché.
	if _handle_pending_material_shortage(individual, task, world, game_data):
		return

	var action := task.get_current_action()
	var stamina_delta := action.get_stamina_delta(individual, task.context, delta)
	individual.current_stamina = max(individual.current_stamina + stamina_delta, 0.0)
	# happiness (2026-09-13, richiesta utente) — STESSO ciclo/STESSO frame di stamina sopra, secondo
	# metodo parallelo e indipendente (vedi Action.get_happiness_delta per il perché non è un
	# secondo valore di ritorno dello stesso metodo). Nessun clamp qui: stesso principio di stamina
	# sopra, il tetto giornaliero vive in HumanVitalsIndividualService, non per-frame.
	var happiness_delta := action.get_happiness_delta(individual, task.context, delta)
	# Mai sotto zero (2026-09-19, richiesta utente: nessun parametro vitale puo' andare sotto 0), come
	# current_stamina sopra. Il tetto massimo resta quello giornaliero.
	individual.current_happiness = maxf(individual.current_happiness + happiness_delta, 0.0)

	# Interrupt/coda da bisogno stamina (2026-09-13, richiesta utente) - valutato QUI, SUBITO DOPO
	# i due delta sopra (stesso frame, stessa lettura di current_stamina appena aggiornata), PRIMA
	# di record_step_cost/is_complete: se scatta, individual.current_task punta ORA a una
	# Task-bisogno diversa da `task` - `task`/`action` locali sono a questo punto riferimenti alla
	# Task VECCHIA (scartata o messa in coda), quindi ritorna immediatamente per non continuare a
	# operare su di loro in questo stesso frame. La nuova Task-bisogno riceve il proprio primo
	# apply_action dal prossimo frame, stesso principio gia' in uso per un normale cambio di step
	# (activate() ora, delta dal prossimo giro del ciclo).
	if _handle_stamina_interrupt(individual, task, world, game_data):
		return
	# Bisogno di PROVVISTE (2026-09-19, richiesta utente): blocco a se', MAI fuso con quello di stamina
	# sopra (come dice il commento su _resolve_active_stamina_need_priority). Stesso schema: bool di
	# ritorno, return immediato se ha sostituito individual.current_task.
	if _handle_food_interrupt(individual, task, world, game_data):
		return

	# Accumulo costo per-step (2026-09-07, richiesta utente; happiness aggiunta 2026-09-13) — stessi
	# stamina_delta/happiness_delta/delta appena applicati sopra, nessun ricalcolo: vedi Task.
	# record_step_cost/print_cost_summary.
	task.record_step_cost(stamina_delta, happiness_delta, delta)
	if action.is_complete(individual, task.context):
		finish_current_step(individual, task, world, game_data)


# ESTRATTA (2026-09-16, richiesta utente, fix bordo macrocella per le task perditempo) dal corpo
# del blocco `if action.is_complete(...)` di apply_action sopra — STESSO comportamento esatto,
# nessun cambio: SECONDO chiamante ora GameScene._block_border_crossing, che la richiama per le
# SOLE task perditempo (TaskDefinition.is_idle_activity, vedi task_definition.gd) quando il
# movimento viene bloccato al bordo di una macrocella (macrocella inesistente o ingresso in
# acqua) — in quel caso la gamba bloccata viene trattata come conclusa, STESSA identica sequenza
# di chiusura/avanzamento di un arrivo naturale (skill growth/chiusura Task/fallback perditempo
# inclusi se era l'ultima gamba), invece di lasciare l'individuo bloccato per sempre. Per ogni
# altra Task questo metodo continua a essere raggiunto SOLO da qui sotto, in apply_action, quando
# is_complete() è davvero vero — comportamento sul bordo bloccato INVARIATO per loro (nessuna
# chiamata a questo metodo da _block_border_crossing per una Task non idle, vedi quel file).
func finish_current_step(individual: HumanIndividual, task: Task, world: World, game_data: GameData) -> void:
	var action := task.get_current_action()
	# on_complete() (2026-09-07, richiesta utente, introdotta con ThinkAction) — SEMPRE PRIMA di
	# advance_to_next_step()/stop(): quello che uno step lascia sull'individuo al proprio termine
	# (es. ThinkAction -> individual.pending_thought = true) deve essere scritto mentre quello
	# step è ancora "il current" per costruzione, non dopo che la Task è già passata oltre.
	action.on_complete(individual, task.context)
	# Ricerca magazzino (2026-09-09, richiesta utente — nata come re-routing UnloadAction su
	# magazzino pieno, poi GENERALIZZATA per servire anche la ricerca iniziale post-PickUp di
	# haul_resource, stesso canale/stesso Dictionary per entrambe, vedi _handle_pending_
	# warehouse_search sotto) e "cammina via" dopo un deposito riuscito (vedi _handle_pending_
	# walk_away sotto) — ENTRAMBE DOPO on_complete(), PRIMA di advance_to_next_step(): quello che
	# uno step ha appena scritto in context va consumato mentre è ancora "il current" per
	# costruzione, accodando eventuali nuovi step alla Task corrente PRIMA che l'indice avanzi,
	# così is_finished()/il nuovo current_action sotto vedono già i nuovi step come parte della
	# stessa Task, mai una Task separata. Ordine fra le due chiamate irrilevante in pratica: sono
	# mutuamente esclusive per costruzione (pending_warehouse_search lo scrive solo un deposito
	# NON riuscito/ricerca iniziale, pending_walk_away_position solo un deposito RIUSCITO — mai
	# entrambe nello stesso passaggio, vedi unload_action.gd). Per le task perditempo (secondo
	# chiamante, bordo bloccato) questi tre handler sono no-op garantiti: nessuno dei loro step
	# (Walk/Run/LookAround/Rest/Jump) scrive mai queste chiavi di context.
	_handle_pending_warehouse_search(individual, task, world)
	_handle_pending_thought_target_search(individual, task, world)
	_handle_pending_walk_away(task)
	task.advance_to_next_step()
	if task.is_finished():
		if DebugLogging.ENABLED and DebugLogging.SHOW_TASK_LIFECYCLE_LOGS:
			task.print_cost_summary(individual)
		# Punto ESATTO di completamento naturale con successo (2026-09-13, richiesta utente) —
		# QUI, non dentro individual.stop(): stop() è condiviso anche con l'interruzione
		# MANUALE (tasto H, vedi HumanIndividual.stop()), quindi non distingue da sé "arrivo
		# naturale" da "interrotta a metà" — is_finished() qui invece è vero SOLO quando tutti
		# gli step sono stati completati con successo. Garanzia "una volta sola": individual.
		# current_task cambia sempre (via _handle_task_completion_need_and_queue sotto, che
		# assegna una nuova Task-bisogno/riprende dalla coda/chiama stop()), quindi QUESTA
		# istanza di Task non è più raggiungibile da nessuna chiamata futura di apply_action —
		# lo stesso identico principio già sfruttato da print_cost_summary sopra.
		# Effetti del completamento su skill e parametri vitali: TaskCompletionEffectService (dati in
		# task_completion_effects.tres), non qui - questo servizio parla di singole Action.
		TaskCompletionEffectService.apply_effects(individual, task)
		# Bisogno/coda (2026-09-13, richiesta utente, Punto 5) — PRIMA di considerare
		# l'individuo libero: se un bisogno stamina è ANCORA attivo, assegna la Task-bisogno
		# corrispondente; altrimenti riprende l'ultima Task sospesa in coda (se presente);
		# solo se nessuna delle due condizioni vale, individual.stop() come prima di questo
		# passo. Vedi _handle_task_completion_need_and_queue per il dettaglio dei tre rami.
		_handle_task_completion_need_and_queue(individual, task, world, game_data)
	else:
		task.get_current_action().activate(individual, task.context)


# Consuma task.context["pending_warehouse_search"] (2026-09-09, richiesta utente — GENERALIZZATO da
# _handle_pending_reroute: un unico canale/Dictionary riusato sia dal re-routing UnloadAction su
# magazzino pieno — UnloadAction.activate, vedi lì — sia dalla ricerca magazzino INIZIALE dopo un
# PickUp riuscito — PickUpAction.on_complete, vedi lì). No-op immediato se la chiave non è presente
# (il caso comune, nessuno step ha appena richiesto una ricerca) — questa funzione è chiamata ad OGNI
# step completato di OGNI Task, non solo dopo un PickUp/Unload, quindi deve restare economica quando
# non c'è nulla da fare.
#
# pending_warehouse_search viene SEMPRE rimosso qui (in ENTRAMBI i casi sotto, trovato o non trovato
# un candidato) — mai lasciato oltre questa chiamata, altrimenti lo step successivo (che potrebbe non
# essere affatto un Unload) lo rileggerebbe per errore.
#
# warehouse_search_excluded_building_ids (la lista persistente, NON il campo excluded_building_ids
# dentro il Dictionary appena letto/rimosso — vedi commento su quella chiave in unload_action.gd)
# invece non viene mai toccato qui: è UnloadAction.activate, non questa funzione, a farlo crescere
# quando scopre un nuovo magazzino pieno.
#
# discard_on_failure (dentro il Dictionary) distingueva in origine DUE esiti diversi per "nessun
# candidato" (true = re-routing, perdita; false/assente = ricerca iniziale, nessuna perdita) — dal
# fix unificato "scarico a terra" (2026-09-12, richiesta utente) i DUE esiti ora CONVERGONO sullo
# stesso risultato pratico (HumanIndividual.discard_carried_resource, vedi lì per il log/il TODO sul
# futuro sistema di scarico a terra): true = re-routing fallito (Scenario B2, un edificio già
# raggiunto è risultato pieno), false/assente = ricerca iniziale fallita (Scenario B1, nessun
# edificio da abbandonare, ma comunque nessuna destinazione disponibile). Il campo resta comunque
# utile per distinguere i due CONTESTI nel log stampato subito prima di ciascuna chiamata, anche se
# l'esito finale (scarto) è oggi identico.

# Consuma task.context["pending_material_shortage"], scritto da SetupSiteAction.activate() quando
# il Building bersaglio non ha ancora abbastanza del proprio materiale di setup site (BuildingRules.
# setup_site_material_name, 2026-09-13/14, richiesta utente — Build Task collegata a un vero
# fabbisogno di materiale, SOLO per SetupSiteAction) —
# STESSO canale generico/STESSO principio di _handle_pending_warehouse_search sotto, ma chiamato
# da un punto DIVERSO di apply_action (in cima, PRIMA di calcolare qualunque delta — vedi il
# commento lì per il perché): a differenza di pending_warehouse_search (scritto da un'Action che ha
# già consumato il proprio istante, un deposito/raccolta appena riuscita), questo deve essere
# intercettato PRIMA che SetupSiteAction "lavori" anche solo per un frame senza materiale.
#
# Ritorna bool (2026-09-14, RICALIBRATO — prima del bugfix "elimina la Transport automatica" questo
# indicava "ha sostituito individual.current_task"; ora _resolve_material_shortage non riassegna
# più nulla, quindi ritorna sempre false — mantenuto bool solo per coerenza di firma con
# _handle_stamina_interrupt sotto, non void come gli altri _handle_pending_*), STESSO contratto di
# _handle_stamina_interrupt sotto, non void come gli altri _handle_pending_*.
#
# world/game_data (2026-09-14, RICALIBRATO) — `individual`/`game_data` non sono più usati dal corpo
# di risoluzione (nessuna Transport da assegnare, nessun age_band da risolvere) — restano parametri
# di questa funzione/di _resolve_material_shortage solo perché quest'ultima li tiene ancora in
# firma per il bonus di partenza (che oggi legge solo `world`) e per non rompere gli altri call
# site senza istruzioni esplicite in merito. `world == null` continua a disattivare l'intero
# meccanismo (il cantiere resta semplicemente "fermo" — is_complete() di SetupSiteAction è già
# bloccata da sé in quel caso, vedi quel file, nessun avanzamento scorretto), mai un crash.
func _handle_pending_material_shortage(individual: HumanIndividual, task: Task, world: World, game_data: GameData) -> bool:
	if not task.context.has("pending_material_shortage"):
		return false
	var shortage: Dictionary = task.context["pending_material_shortage"]
	task.context.erase("pending_material_shortage")
	if world == null or game_data == null:
		return false

	# "missing" (2026-09-14, richiesta utente — GENERALIZZATO da resource_name/quantity_needed
	# singoli a Dictionary[String, int]): BuildAction può avere PIÙ risorse mancanti insieme (vedi
	# BuildAction.get_missing_materials), SetupSiteAction ne scrive sempre e sola una — STESSA forma
	# per entrambe, nessun ramo speciale qui per distinguerle.
	var missing: Dictionary = shortage.get("missing", {})
	var target_building_id := int(shortage.get("target_building_id", -1))
	if missing.is_empty():
		return false
	var target_building := _find_building_by_id(world, target_building_id)
	if target_building == null:
		return false

	return _resolve_material_shortage(individual, world, game_data, target_building, missing)


# Corpo condiviso di risoluzione del fabbisogno materiale (2026-09-14, richiesta utente — controllo
# giornaliero di ritentativo per un individuo bloccato) — ESTRATTO da _handle_pending_material_
# shortage sopra (che lo consumava una volta sola, al momento in cui SetupSiteAction.activate()
# scrive pending_material_shortage) perché ora serve un SECONDO chiamante: retry_blocked_material_
# shortages sotto, che lo richiama ad ogni giorno di gioco per QUALUNQUE individuo ancora bloccato,
# senza dover passare da un context/flag one-shot (quel canale resta comunque il percorso normale,
# invariato — questa funzione è ora il nucleo comune a entrambi).
#
# RICALIBRATO 2026-09-14 (richiesta utente — "va eliminato totalmente... il pipottino resta in
# attesa del materiale, non può avanzare se non c'è materiale"): la ricerca sorgente + Transport
# Task automatica è stata RIMOSSA — restano solo due esiti, bonus di partenza (SOLO deposit_site +
# nessuno storage nel mondo, vedi sotto) oppure "bloccato in attesa", MAI più una riassegnazione di
# individual.current_task. Ritorna SEMPRE false ora (il vecchio contratto "true = Transport
# riassegnata" non ha più modo di verificarsi) — il valore di ritorno resta bool per non toccare la
# firma di retry_blocked_material_shortages, ma il suo ramo "if resolved" (log [BUILD MATERIAL
# RETRY]) è di fatto irraggiungibile ora: lasciato così in attesa di istruzioni su come procedere
# per il resto del meccanismo di sblocco (richiesta utente, stesso turno).
func _resolve_material_shortage(
	individual: HumanIndividual, world: World, game_data: GameData,
	target_building: Building, missing: Dictionary
) -> bool:
	# BONUS DI PARTENZA (2026-09-13/14, richiesta utente) — SOLO per un cantiere di tipo
	# "deposit_site" (Building.building_type_name, STESSA stringa/STESSO campo già usato ovunque nel
	# progetto per questo confronto — vedi GameScene._demolish_building/microCellRenderer.gd/
	# BuildingGhost.gd, tutti `building.building_type_name == "deposit_site"`), MAI per hut/
	# stick_tent/qualunque altro tipo, indipendentemente da quanti storage esistano o meno nel
	# mondo (CORREZIONE 2026-09-14: la condizione sul tipo mancava nella prima versione di questo
	# ramo, che applicava il bonus a QUALUNQUE cantiere). ENTRAMBE le condizioni devono valere:
	# 1) è un deposit_site, 2) nel mondo non esiste ANCORA nessun edificio COMPLETO con vera
	# capacità di storage (BuildingStorageService.world_has_any_storage_building) — SOLO questo
	# bonus fa arrivare il materiale automaticamente: hut/stick_tent/qualunque altro tipo (e un
	# deposit_site quando la condizione sopra non vale) restano bloccati finché il player non
	# deposita il materiale a mano (vedi il ramo sotto — comportamento voluto, "il player si
	# arrangia").
	#
	# Scritto QUI (non in SetupSiteAction.activate(), dove il fabbisogno viene rilevato) perché
	# quella classe non ha accesso a `world` (Action.activate riceve solo individual/context, per
	# design — vedi Action.gd) — questo è già il punto in cui `world` diventa disponibile per
	# risolvere qualunque cosa riguardi altri edifici (world_has_any_storage_building sotto).
	#
	# Struttura dati IDENTICA a store()/withdraw() ({"quantity", "decay_fraction"}) ma decay_fraction
	# SEMPRE 0.0 (richiesta esplicita, non una media pesata con quanto già presente): il materiale è
	# "garantito" dal nulla, non arriva fisicamente da nessuna parte da cui ereditare un decadimento.
	# quantity_needed è già ESATTAMENTE il residuo mancante (SetupSiteAction.
	# get_missing_material_quantity = required - stored), sommarlo allo stored attuale porta quindi
	# ESATTAMENTE al tetto richiesto, mai oltre.
	#
	# Ricontrollato ad OGNI chiamata (mai una sola volta/mai cachato) — vedi world_has_any_storage_
	# building per il perché: se l'unico storage esistente venisse distrutto, il prossimo deposit_
	# site tornerebbe a ricevere il bonus automaticamente, nessuna logica "solo alla prima Task" qui.
	#
	# `return false` (non un'assegnazione di Transport, mai un cambio di individual.current_task) —
	# SetupSiteAction resta lo step attivo: il chiamante (apply_action) prosegue nello STESSO frame
	# a calcolare get_stamina_delta/is_complete su di essa, che rilegge get_missing_material_
	# quantity() dal vivo e lo trova ora a 0 — "procede direttamente come se il materiale fosse già
	# arrivato", nello stesso istante, nessun frame di ritardo aggiuntivo.
	if target_building.building_type_name == "deposit_site" and not BuildingStorageService.world_has_any_storage_building(world):
		# Loop su TUTTE le risorse mancanti (2026-09-14, richiesta utente — generalizzato per
		# BuildAction, che può averne più di una insieme): ciascuna garantita al proprio tetto
		# esatto, stessa formula/stessa struttura dati di prima, solo ripetuta per voce.
		for resource_name in missing.keys():
			var quantity_needed: int = int(missing[resource_name])
			var existing_entry: Dictionary = target_building.stored_resources.get(resource_name, {})
			var current_quantity: int = int(existing_entry.get("quantity", 0))
			target_building.stored_resources[resource_name] = {
				"quantity": current_quantity + quantity_needed,
				"decay_fraction": 0.0,
			}
		# is_awaiting_material -> false (2026-09-14, richiesta utente — segnalazione player) — il
		# bonus risolve il fabbisogno all'istante, nessun motivo per restare "in attesa" anche se lo
		# era da un tentativo precedente. Nessuna notifica per la transizione true->false (punto 3
		# della richiesta: "nessuna notifica necessaria", il progresso visibile del cantiere basta).
		target_building.is_awaiting_material = false
		if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
			print("[BUILD MATERIAL BONUS] Building #%d: nessun edificio di storage completo esiste ancora nel mondo — garantiti direttamente (bonus di partenza), nessuna Transport generata: %s." % [
				target_building.id, str(missing)
			])
		return false

	# Transport Task automatica RIMOSSA (2026-09-14, richiesta utente — "va eliminato totalmente...
	# il pipottino resta in attesa del materiale, non può avanzare se non c'è materiale"): fuori dal
	# bonus di partenza sopra, questo servizio non cerca più una sorgente né assegna più nessuna
	# Transport Task da sé — il cantiere resta semplicemente bloccato (is_complete() di
	# SetupSiteAction resta false, get_stamina_delta/get_happiness_delta restano a 0, vedi quel
	# file) finché il materiale non arriva per un'altra via (oggi: solo il bonus sopra, o un
	# deposito MANUALE del player — BuildingStorageService.can_accept continua ad accettare il
	# materiale di setup site su un cantiere non finito). `individual`/`game_data` restano parametri
	# di questa funzione ma NON sono più letti da nessun ramo (il bonus sopra usa solo `world`) —
	# lasciati in firma per non rompere i due call site senza istruzioni esplicite in merito.
	#
	# is_awaiting_material — TRANSIZIONE, non stato (2026-09-14, richiesta utente — segnalazione
	# player) — il segnale building_material_blocked scatta SOLO al passaggio false->true (punto 2
	# della richiesta originale: "nessuna ripetizione se il blocco persiste nei giorni successivi").
	if not target_building.is_awaiting_material:
		target_building.is_awaiting_material = true
		building_material_blocked.emit(target_building)
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[BUILD MATERIAL NEEDED] Building #%d: manca ancora %s — cantiere bloccato in attesa (nessuna Transport automatica)." % [
			target_building.id, str(missing)
		])
	return false


# Controllo giornaliero di ritentativo per un individuo bloccato su SetupSiteAction in attesa di
# materiale (2026-09-14, richiesta utente) — oggi la ricerca di una sorgente scatta UNA SOLA volta,
# quando SetupSiteAction.activate() scrive pending_material_shortage (vedi _handle_pending_
# material_shortage sopra): se in quel momento nessun magazzino ha ancora scorte, il context flag
# viene comunque consumato/cancellato e l'individuo resta bloccato per sempre su quello step, anche
# se un magazzino viene rifornito minuti/giorni dopo (verificato in un'indagine dedicata, giro
# precedente — "bloccato ma stabile", nessun loop/spam, ma nessun ritentativo automatico). Questa
# funzione richiama lo STESSO corpo di risoluzione (_resolve_material_shortage sopra, nessuna
# logica duplicata) una volta al giorno per OGNI individuo ancora fermo in quello stato esatto.
#
# Chiamata da GameTimeService._on_day_advanced (2026-09-14), stesso hook giornaliero già usato per
# _recalculate_daily_max_stamina/_recalculate_daily_carry_capacity/ecc. — INCONDIZIONATA, nessun
# `if giorno == X`, stesso principio "periodico, non event-driven" già seguito da quei ricalcoli.
#
# Filtro a 3 condizioni, TUTTE necessarie:
#   1) current_task != null e current_task.task_name == "task_build_name" — SOLO la Build Task,
#      stessa stringa già usata altrove (TaskCompletionEffects, task_completion_effects.tres).
#   2) lo step ATTIVO è un SetupSiteAction (`is`) — BuildAction/ClearAction non hanno un fabbisogno
#      materiale in questo giro (bypassate per costruzione, vedi SetupSiteAction.gd), quindi non
#      possono mai essere "bloccate" per questo motivo.
#   3) SetupSiteAction.get_missing_material_quantity() > 0 — lettura pura, ESATTAMENTE la stessa
#      formula/lo stesso dato già usato da activate()/get_stamina_delta/is_complete di quella
#      classe: nessun secondo calcolo che potrebbe disallinearsi.
#
# `world`/`game_data` obbligatori qui (a differenza di apply_action, che li accetta null per
# difesa) — GameTimeService li ha sempre entrambi disponibili al momento della chiamata, nessun
# caso reale in cui mancherebbero: un guard difensivo resta comunque in testa, coerente con lo
# stile "mai un crash" del resto del file.
#
# Log [BUILD MATERIAL RETRY] (richiesta utente) — SOLO quando _resolve_material_shortage ritorna
# true, cioè SOLO quando il ritentativo genera davvero una NUOVA Transport Task (una sorgente che
# prima non c'era è stata trovata ORA): il bonus di partenza stampa già il proprio
# [BUILD MATERIAL BONUS] dentro _resolve_material_shortage, e "ancora nessuna sorgente" stampa già
# [BUILD MATERIAL NEEDED] lì — nessun log duplicato per quei due casi, questo tag esiste apposta per
# confermare lo SBLOCCO, non ogni tentativo (anche quelli falliti, silenziosi qui, sono già coperti
# dal log esistente dentro _resolve_material_shortage).
#
# NON static (bugfix, 2026-09-14 — "Cannot call non-static function _resolve_material_shortage()
# from the static function retry_blocked_material_shortages()"): _resolve_material_shortage è
# un'istanza (mai stata static), e ora deve anche poter emettere building_material_blocked (segnale
# d'istanza — vedi sopra) — questa funzione deve quindi girare sulla STESSA istanza di
# HumanIndividualActionService che GameScene già possiede (individual_action_service, la stessa che
# guida apply_action ogni frame), non più chiamabile per nome di classe. GameTimeService la riceve
# ora da GameScene._setup_clock (vedi connect_to_clock), la tiene in _individual_action_service.
func retry_blocked_material_shortages(
	world: World, all_individuals: Array[HumanIndividual], game_data: GameData
) -> void:
	if world == null or game_data == null:
		return
	for individual in all_individuals:
		var task := individual.current_task
		if task == null or task.task_name != "task_build_name":
			continue
		var action := task.get_current_action()
		# ESTESO a BuildAction (2026-09-14, richiesta utente — "step 2 della build", il quarto step
		# ora ha un proprio fabbisogno materiale) — STESSO principio, due rami paralleli invece di
		# uno solo: ciascuno risolve `missing`/`target_building` dalla propria Action, poi convergono
		# sulla STESSA _resolve_material_shortage sotto (nessuna logica duplicata tra i due tipi).
		var missing: Dictionary = {}
		var target_building: Building = null
		if action is SetupSiteAction:
			var setup_action := action as SetupSiteAction
			target_building = setup_action.target_building
			var missing_quantity := setup_action.get_missing_material_quantity()
			if target_building != null and missing_quantity > 0:
				missing[target_building.rules.setup_site_material_name] = missing_quantity
		elif action is BuildAction:
			var build_action := action as BuildAction
			target_building = build_action.target_building
			missing = build_action.get_missing_materials()
		if target_building == null or missing.is_empty():
			continue
		var resolved := _resolve_material_shortage(individual, world, game_data, target_building, missing)
		if resolved and DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
			print("[BUILD MATERIAL RETRY] Individuo #%d %s: ritentativo giornaliero riuscito — Building #%d: %s." % [
				individual.id, individual.name, target_building.id, str(missing)
			])


# Scansione lineare di World.buildings (2026-09-13) — STESSA identica funzione/STESSO principio di
# TaskPersistenceService._find_building_by_id, duplicata qui apposta (quella resta privata a quel
# file, nessuna funzione condivisa tra file per questo lookup, stesso principio già seguito
# ovunque in questo progetto). null se non trovato (world null, o building_id non più esistente).
static func _find_building_by_id(world: World, building_id: int) -> Building:
	if world == null:
		return null
	for building in world.buildings:
		if building.id == building_id:
			return building
	return null


func _handle_pending_warehouse_search(individual: HumanIndividual, task: Task, world: World) -> void:
	if not task.context.has("pending_warehouse_search"):
		return
	var search: Dictionary = task.context["pending_warehouse_search"]
	task.context.erase("pending_warehouse_search")

	var resource_name := String(search.get("resource_name", ""))
	var quantity := int(search.get("quantity", 0))
	if resource_name == "" or quantity <= 0:
		return

	# Costruita manualmente (int(id) per elemento), non Array[int](search.get(...)) — stesso motivo
	# di UnloadAction.activate (vedi lì): gestisce anche un context deserializzato da JSON (numeri
	# sempre float, mai int).
	var excluded_building_ids: Array[int] = []
	for raw_id in search.get("excluded_building_ids", []):
		excluded_building_ids.append(int(raw_id))

	var candidate := WarehouseSelectionService.find_best(
		world, individual.position, individual.home_macro_coords, resource_name, quantity, excluded_building_ids
	)
	if candidate != null:
		var macro_offset: Vector2 = Vector2(Vector2i(candidate.macro_x, candidate.macro_y) - individual.home_macro_coords) * World.WIDTH
		# Jitter (2026-09-17, richiesta utente — bugfix "i pipottini si fermano sempre nell'angolo in
		# alto a sinistra della microcella", sovrapposti quando più portatori consegnano allo stesso
		# magazzino) — STESSO principio di GameScene._assign_pickup_task/Building.get_resumable_
		# task_context, offset casuale interno alla cella applicato SOLO al punto di arrivo del Walk.
		var target_position_jitter: Vector2 = Vector2(randf_range(0.15, 0.85), randf_range(0.15, 0.85))
		var candidate_position: Vector2 = Vector2(candidate.micro_x, candidate.micro_y) + macro_offset + target_position_jitter
		# DepositKind.RESOURCE passato esplicitamente (2026-09-10, richiesta utente — scollegare il
		# ramo di UnloadAction dalla nullità di target_building): `candidate` qui è sempre un Building
		# risolto (vedi guardia `if candidate != null` sopra), stesso comportamento di ramo fisico di
		# prima di questo passo, ora reso esplicito invece che dedotto dalla non-nullità dell'argomento.
		var new_steps: Array[Action] = [WalkAction.new(candidate_position), UnloadAction.new(candidate, UnloadAction.DepositKind.RESOURCE)]
		task.append_steps(new_steps)
		if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
			print("[WAREHOUSE SEARCH] magazzino trovato: id=%d — Walk+Unload accodati alla Task corrente (esclusi finora: %s)." % [
				candidate.id, str(excluded_building_ids)
			])
		return

	if bool(search.get("discard_on_failure", false)):
		# Scenario B2 — re-routing fallito (2026-09-09, richiesta utente iniziale — nota di
		# contesto in fase di indagine; UNIFICATO 2026-09-12 sotto discard_carried_resource, che
		# prima duplicava qui lo stesso azzeramento inline senza log/commento dedicato): nessun
		# magazzino alternativo trovato dopo che il target originale è risultato pieno all'arrivo.
		# Vedi HumanIndividual.discard_carried_resource per il log/il TODO sul futuro sistema di
		# scarico a terra — questo print resta qui SOLO per il contesto SPECIFICO del re-routing
		# (perché la ricerca è scattata: magazzino pieno), non duplicato dal log generico della
		# funzione condivisa.
		if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
			print("[WAREHOUSE SEARCH] nessun magazzino alternativo trovato per resource_name='%s' quantity=%d dopo re-routing (magazzino originale pieno all'arrivo)." % [
				resource_name, quantity
			])
		individual.discard_carried_resource()
		carried_resource_discarded.emit(individual, resource_name, quantity)
		return

	# Scenario B1 — ricerca INIZIALE (PickUpAction) senza candidato (2026-09-12, richiesta utente
	# — fix unificato "scarico a terra": DECISIONE CAMBIATA rispetto al comportamento precedente,
	# che qui lasciava l'individuo "con la merce in spalla, nessuna perdita" — ora invece scarta
	# anche questo caso, stessa funzione condivisa di B2/Scenario A) — nessun edificio "vicino da
	# abbandonare" in questo caso (a differenza di B2, qui non c'è mai stato un target da cui
	# ripartire), ma il risultato pratico è lo stesso: la Task (solo [Walk, PickUp] per
	# haul_resource) termina qui SENZA aver mai raggiunto un Unload — individual.stop() poco dopo,
	# in apply_action, chiuderebbe comunque lo zaino via il proprio hook di sicurezza (vedi
	# HumanIndividual.stop()), ma scartare QUI, PRIMA della terminazione, è più diretto e
	# corrisponde esattamente al punto richiesto ("prima o durante la terminazione della Task").
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[WAREHOUSE SEARCH] nessun magazzino trovato per resource_name='%s' quantity=%d — nessun edificio da abbandonare in questo caso, ma nessuna destinazione disponibile." % [
			resource_name, quantity
		])
	individual.discard_carried_resource()
	carried_resource_discarded.emit(individual, resource_name, quantity)


# Consuma task.context["pending_thought_target_search"] (2026-09-10, richiesta utente — handler di
# ricerca per i pensieri, PARALLELO a _handle_pending_warehouse_search sopra ma per il ramo PENSIERO
# di UnloadAction: stesso canale generico/stesso momento di consumo — DOPO on_complete(), PRIMA di
# advance_to_next_step(), vedi apply_action) — usa ThoughtTargetSelectionService invece di
# WarehouseSelectionService come unica differenza di dominio. No-op immediato se la chiave non è
# presente, stesso motivo/stessa economicità di _handle_pending_warehouse_search: questa funzione è
# chiamata ad OGNI step completato di OGNI Task.
#
# Struttura del Dictionary DELIBERATAMENTE più piccola di pending_warehouse_search — SOLO
# excluded_building_ids (nessun resource_name/quantity, che non hanno senso per un pensiero: nessuna
# categoria/capacità residua da verificare, vedi ThoughtTargetSelectionService.find_best) e nessun
# discard_on_failure: quel campo esiste sull'altro canale per distinguere re-routing (perdita
# TEMPORANEA della merce) da ricerca iniziale (nessuna perdita) — qui non esiste ancora uno scenario
# di re-routing (nessun chiamante reale scrive ancora questa chiave, vedi nota in testa al file), e
# comunque non c'è alcun side-effect distruttivo equivalente a carried_* da poter scartare: un
# pensiero non depositato semplicemente resta pending sull'individuo (vedi ramo "nessun candidato"
# sotto), stesso trattamento "nessuna perdita" già riservato alla ricerca INIZIALE del magazzino.
# `excluded_building_ids` viene comunque letto/passato per permettere a un futuro chiamante di
# escludere edifici già provati (es. un secondo tentativo dopo un fallimento), stesso principio
# dell'omonimo campo sull'altro canale — semplicemente non c'è ancora nessuno che lo faccia crescere.
func _handle_pending_thought_target_search(individual: HumanIndividual, task: Task, world: World) -> void:
	if not task.context.has("pending_thought_target_search"):
		return
	var search: Dictionary = task.context["pending_thought_target_search"]
	task.context.erase("pending_thought_target_search")

	# Costruita manualmente (int(id) per elemento), non Array[int](search.get(...)) — stesso motivo
	# di _handle_pending_warehouse_search sopra: gestisce anche un context deserializzato da JSON
	# (numeri sempre float, mai int).
	var excluded_building_ids: Array[int] = []
	for raw_id in search.get("excluded_building_ids", []):
		excluded_building_ids.append(int(raw_id))

	var candidate := ThoughtTargetSelectionService.find_best(
		world, individual.position, individual.home_macro_coords, excluded_building_ids
	)
	if candidate != null:
		var macro_offset: Vector2 = Vector2(Vector2i(candidate.macro_x, candidate.macro_y) - individual.home_macro_coords) * World.WIDTH
		# Jitter — STESSO principio di _handle_pending_warehouse_search sopra (2026-09-17, richiesta
		# utente, bugfix "angolo in alto a sinistra"/sovrapposizione).
		var target_position_jitter: Vector2 = Vector2(randf_range(0.15, 0.85), randf_range(0.15, 0.85))
		var candidate_position: Vector2 = Vector2(candidate.micro_x, candidate.micro_y) + macro_offset + target_position_jitter
		# DepositKind.THOUGHT passato esplicitamente (stesso principio di DepositKind.RESOURCE in
		# _handle_pending_warehouse_search sopra) — `candidate` qui è sempre un Building risolto
		# (vedi guardia `if candidate != null`), coerente con target_building ora indipendente da
		# deposit_kind (vedi nota in testa a unload_action.gd).
		var new_steps: Array[Action] = [WalkAction.new(candidate_position), UnloadAction.new(candidate, UnloadAction.DepositKind.THOUGHT)]
		task.append_steps(new_steps)
		if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
			print("[THOUGHT TARGET SEARCH] edificio trovato: id=%d — Walk+Unload(THOUGHT) accodati alla Task corrente (esclusi finora: %s)." % [
				candidate.id, str(excluded_building_ids)
			])
		return

	# Nessun edificio con accepts_thoughts trovato — nessun side-effect equivalente a carried_* da
	# ripulire (vedi nota in testa alla funzione): il pensiero resta semplicemente pending
	# sull'individuo (individual.pending_thought, se già true, non viene toccato qui), la Task
	# prosegue/termina senza aver depositato. Nessuna perdita, non un fallimento distruttivo —
	# stesso trattamento "nessun candidato" già riservato alla ricerca INIZIALE del magazzino sopra.
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[THOUGHT TARGET SEARCH] nessun edificio con accepts_thoughts trovato — nessun deposito, la Task prosegue/termina senza aver depositato il pensiero.")


# Consuma task.context["pending_walk_away_position"] scritto da UnloadAction.on_complete() (vedi lì)
# subito dopo un deposito FISICO riuscito (2026-09-09, richiesta utente — haul_resource, ultimo
# step "cammina via" — stesso schema di walk_away in Daydream). No-op se la chiave non è presente
# (il caso comune). A differenza di _handle_pending_warehouse_search sopra, non ha bisogno di
# `individual`/`world`: la posizione è già completamente risolta da chi ha scritto la chiave.
func _handle_pending_walk_away(task: Task) -> void:
	if not task.context.has("pending_walk_away_position"):
		return
	var walk_away_position: Vector2 = task.context["pending_walk_away_position"]
	task.context.erase("pending_walk_away_position")
	var new_steps: Array[Action] = [WalkAction.new(walk_away_position)]
	task.append_steps(new_steps)
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[WALK AWAY] WalkAction accodato verso %s dopo un deposito riuscito." % str(walk_away_position))


# Priorità del bisogno stamina più urgente ATTIVO ORA per `individual`, o -1 se nessuno (2026-09-13,
# richiesta utente, sistema di interrupt/coda da stamina critica) — SOLO stamina in questo passo:
# un futuro bisogno fame/sete si aggiungerà con lo stesso schema (una soglia/un blocco a sé), MAI
# fuso con questo. Guardia difensiva su max_stamina <= 0 (mai un caso reale con i dati attuali, ma
# eviterebbe una divisione per zero se mai accadesse).
#
# STATIC (2026-09-13, richiesta utente — bugfix "individuo mai avviato resta fermo per sempre") —
# non tocca mai `self`, mai l'ha fatto: reso static solo perché resolve_idle_individual sotto
# (anch'essa static, per lo stesso motivo) deve poterla chiamare da un contesto SENZA istanza —
# nessun impatto sui chiamanti esistenti (_handle_stamina_interrupt/_handle_task_completion_need_
# and_queue, entrambi metodi d'istanza), che continuano a chiamarla identica.
static func _resolve_active_stamina_need_priority(individual: HumanIndividual) -> int:
	if individual.max_stamina <= 0.0:
		return -1
	var stamina_percent: float = individual.current_stamina / individual.max_stamina
	if stamina_percent < STAMINA_EMERGENCY_REST_THRESHOLD:
		return INTERRUPT_PRIORITY_EMERGENCY_REST
	if stamina_percent < STAMINA_REST_THRESHOLD:
		return INTERRUPT_PRIORITY_REST
	return -1


# Priorita' del bisogno di PROVVISTE piu' urgente ATTIVO ORA per `individual`, o -1 se nessuno
# (2026-09-19, richiesta utente) - parallela a _resolve_active_stamina_need_priority sopra, in un blocco
# a se'. Autonomia in giorni = food_calories_held / consumo calorico giornaliero
# (HumanCalculator.get_daily_calorie_consumption): fino a FOOD_AUTONOMY_EMERGENCY_DAYS (1 giorno,
# compreso) -> INTERRUPT_PRIORITY_EMERGENCY_RESTOCK; altrimenti -1 (nessun'altra priorita': il
# rifornimento normale e' una Task perditempo, non un bisogno-interrupt). Consumo 0 (INFANT) =
# autonomia infinita -> -1. Regole non risolvibili -> -1.
#
# `era_rules` (opzionale, in coda alla firma richiesta): serve al moltiplicatore dell'allattamento
# (dependent_child_calorie_multiplier) cosi' l'autonomia usa lo STESSO consumo che apply_daily_
# calorie_consumption toglie davvero; senza, il costo del figlio a carico non viene considerato.
#
# STATIC, stesso motivo di _resolve_active_stamina_need_priority. Solo lettura: chi assegna
# emergency_restock e' _handle_food_interrupt (via _active_food_need_priority) e resolve_idle_individual.
static func _resolve_active_food_need_priority(
	individual: HumanIndividual, human_rules: HumanRules, age_band: HumanTypes.AgeBand, sex: HumanTypes.Sex,
	era_rules: EraRules = null
) -> int:
	if human_rules == null:
		return -1
	var daily_consumption: float = HumanCalculator.get_daily_calorie_consumption(
		human_rules, age_band, sex, individual.dependent_child_id != -1, era_rules
	)
	if daily_consumption <= 0.0:
		return -1
	var autonomy_days: float = individual.food_calories_held / daily_consumption
	# <= (non <): l'emergenza scatta GIA' a 1 giorno di autonomia. Le calorie calano di un consumo intero
	# al giorno, quindi l'autonomia vale 5, 4, 3, 2, 1, 0: con < l'emergenza scattava solo a 0.
	if autonomy_days <= FOOD_AUTONOMY_EMERGENCY_DAYS + FOOD_AUTONOMY_EPSILON:
		return INTERRUPT_PRIORITY_EMERGENCY_RESTOCK
	return -1


# Priorita' del bisogno di provviste per `individual` risolvendo regole ed era da soli (2026-09-19):
# HumanRules dalla catena source_group_ref -> folk_ref -> human_rules_ref, EraRules da
# GameSettings.active_game_data (resolve_idle_individual e' statica e non riceve game_data). Usa
# _resolve_active_food_need_priority (20 o -1). Regole non risolvibili -> -1.
static func _active_food_need_priority(individual: HumanIndividual, age_band: HumanTypes.AgeBand) -> int:
	var human_rules: HumanRules = null
	if individual.source_group_ref != null and individual.source_group_ref.folk_ref != null:
		human_rules = individual.source_group_ref.folk_ref.human_rules_ref
	var era_rules: EraRules = null
	if GameSettings.active_game_data != null:
		era_rules = EraCalculator.get_era_rules(GameSettings.active_game_data.current_era_name)
	return _resolve_active_food_need_priority(individual, human_rules, age_band, individual.sex, era_rules)


# Interrupt da bisogno di PROVVISTE (2026-09-19, richiesta utente), in un blocco a se' accanto a
# _handle_stamina_interrupt: se il bisogno e' l'emergenza (20) e la Task in corso puo' essere
# interrotta, assegna emergency_restock (che sospende la Task in corso se sospendibile, vedi
# HumanIndividual.assign_task). Nessun guard sullo spazio libero. Ritorna true SOLO se emergency_restock
# e' stata davvero assegnata (l'individuo ha cambiato Task): se nessun magazzino ha cibo la Task non
# nasce e la Task in corso prosegue indisturbata.
#
# FRENO AI TENTATIVI: valutato al massimo UNA VOLTA al giorno di gioco per individuo
# (HumanIndividual.food_need_last_check_day). Le calorie cambiano solo col consumo giornaliero, quindi
# rivalutare a ogni frame non serve; soprattutto, senza magazzino con cibo la ricerca (e il log
# [RESTOCK]) si ripeterebbe a ogni frame. Ricontrollo al giorno successivo.
#
# Uscita rapida, PRIMA di qualunque calcolo: una Task con priorita' <= 20 (Emergency Rest 10,
# Emergency Restock 20) non puo' essere interrotta da questo bisogno; Rest (30) si'.
func _handle_food_interrupt(individual: HumanIndividual, task: Task, world: World, game_data: GameData) -> bool:
	if game_data == null:
		return false
	if task.interrupt_priority != -1 and task.interrupt_priority <= INTERRUPT_PRIORITY_EMERGENCY_RESTOCK:
		return false
	var today: int = game_data.get_absolute_day()
	if individual.food_need_last_check_day == today:
		return false
	var age_band := _resolve_age_band(individual, game_data)
	var needed_priority := _active_food_need_priority(individual, age_band)
	if needed_priority == -1:
		individual.food_need_last_check_day = today
		return false
	if task.interrupt_priority != -1 and needed_priority >= task.interrupt_priority:
		return false
	individual.food_need_last_check_day = today
	if DebugLogging.should_log_restock(individual.id):
		print("[RESTOCK] #%d %s: bisogno di provviste di emergenza (calorie=%.1f) - Task '%s' in corso, provo emergency_restock." % [
			individual.id, individual.name, individual.food_calories_held, task.task_name
		])
	return NeedTaskAssignmentService.assign_emergency_restock_task(individual, world, age_band, true)


# Age band dell'individuo, risolta con le durate EFFETTIVE per l'Era corrente — STESSO principio
# già fissato ovunque nel dominio umano (es. HumanVitalsIndividualService.recalculate_vitals),
# duplicato qui (non condiviso con GameScene._resolve_age_band) perché questo service non ha
# accesso a quel Node — necessaria per individual.assign_task(task, age_band) quando questo
# service assegna da sé una Task-bisogno (2026-09-13, richiesta utente).
#
# STATIC — stesso motivo/stesso identico trattamento di _resolve_active_stamina_need_priority
# sopra: non tocca mai `self`, reso static solo perché resolve_idle_individual la chiama da un
# contesto senza istanza.
static func _resolve_age_band(individual: HumanIndividual, game_data: GameData) -> HumanTypes.AgeBand:
	var age := float(game_data.year - individual.birth_year_virtual)
	return HumanCalculator.get_age_band(
		game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female,
		individual.sex, age
	)


# Risolve cosa fare per un individuo LIBERO (current_task == null, o comunque da trattare come
# tale — il chiamante garantisce questo) — UNICA fonte di verità per la sequenza "bisogno attivo?
# -> Task-bisogno automatica; altrimenti coda non vuota? -> riprendi l'ultima sospesa; altrimenti
# -> fallback perditempo; altrimenti -> resta libero" (2026-09-13, richiesta utente — bugfix: un
# individuo APPENA creato (seeding), appena nato, o ricostruito da un salvataggio con current_task
# già null non passava MAI da questa logica, restando fermo indefinitamente anche a stamina piena
# — prima viveva SOLO dentro _handle_task_completion_need_and_queue, raggiungibile solo al
# completamento naturale di una Task PREESISTENTE, mai per un individuo che una Task non l'ha mai
# avuta). Riusata da QUATTRO punti: completamento naturale di una Task (_handle_task_completion_
# need_and_queue sotto, che ora delega qui), seeding iniziale (HumanSeedingService.
# seed_player_start), nascita (HumanBirthIndividualService._create_newborn), fine caricamento
# salvataggio (GameLoadService.load_game) — vedi quei file per i rispettivi call site.
#
# STATIC (a differenza degli altri metodi di questa classe, che restano d'istanza per coerenza con
# lo stile "instanzia una volta" della classe — vedi doc di testa al file): i tre chiamanti esterni
# (HumanSeedingService/HumanBirthIndividualService/GameLoadService) non hanno né vogliono
# un'istanza di HumanIndividualActionService — questa funzione (come le due che chiama sopra) non
# tocca mai `self`/stato d'istanza, quindi renderla static non cambia nulla per i chiamanti
# esistenti (_handle_task_completion_need_and_queue, un metodo d'istanza, continua a chiamarla
# identica).
#
# Garantisce SEMPRE uno stato finale ben definito (2026-09-13) — se nessuno dei tre rami sopra si
# applica, individual.stop() esplicito (mai lasciare current_task in un limbo): per un individuo
# GIÀ a current_task null (seeding/nascita/load) questo è un no-op innocuo (TaskDebugRegistry.
# on_task_closed(null) è già un caso esplicitamente previsto — "individuo appena creato, mai
# assegnato" — vedi TaskDebugRegistry.gd; discard_carried_resource() no-op su zaino già vuoto).
static func resolve_idle_individual(individual: HumanIndividual, age_band: HumanTypes.AgeBand, world: World) -> void:
	var needed_priority := _resolve_active_stamina_need_priority(individual)
	if needed_priority != -1:
		if DebugLogging.ENABLED and DebugLogging.SHOW_TASK_LIFECYCLE_LOGS:
			print("[INTERRUPT DEBUG] #%d %s: individuo libero, bisogno stamina attivo (priorità %d, stamina=%.1f/%.1f)." % [
				individual.id, individual.name, needed_priority, individual.current_stamina, individual.max_stamina
			])
		if needed_priority == INTERRUPT_PRIORITY_EMERGENCY_REST:
			NeedTaskAssignmentService.assign_emergency_rest_task(individual, age_band, true)
		else:
			NeedTaskAssignmentService.assign_rest_task(individual, world, age_band, true)
		return

	# Individuo libero con bisogno di provviste di emergenza (2026-09-19, richiesta utente): riceve
	# emergency_restock invece di una perditempo. Nessun guard sullo spazio libero. Se nessun magazzino
	# ha cibo la Task non nasce e si prosegue con coda/perditempo (il caso "resta ad aspettare" verra'
	# dopo). Dopo il bisogno di stamina sopra (che ha la precedenza).
	if _active_food_need_priority(individual, age_band) == INTERRUPT_PRIORITY_EMERGENCY_RESTOCK:
		if DebugLogging.should_log_restock(individual.id):
			print("[RESTOCK] #%d %s: individuo libero con bisogno di provviste di emergenza (calorie=%.1f) - provo emergency_restock." % [
				individual.id, individual.name, individual.food_calories_held
			])
		if NeedTaskAssignmentService.assign_emergency_restock_task(individual, world, age_band, true):
			return

	var resumed_task := TaskQueueService.pop_suspended_task(individual)
	# ZOMBIE GUARD (2026-09-16, richiesta utente, fix "task zombie") — scarta ogni task già
	# conclusa estratta dalla coda (residuo possibile da un salvataggio precedente a questo fix, o
	# difesa in profondità rispetto alla guardia in HumanIndividual.assign_task che oggi impedisce
	# di accodarne di nuove) e passa alla successiva, finché non se ne trova una valida o la coda si
	# svuota — MAI impostare current_task su una task già finita: activate_resumed_task la
	# troverebbe già conclusa e non farebbe nulla, lasciando l'individuo bloccato per sempre.
	while resumed_task != null and resumed_task.is_finished():
		if DebugLogging.ENABLED and DebugLogging.SHOW_SAFETY_LOGS:
			print("[ZOMBIE GUARD] Individuo #%d %s: task '%s' (step %d/%d) scartata dalla coda perché già conclusa — resolve_idle_individual, ripresa da coda." % [
				individual.id, individual.name, resumed_task.task_name, resumed_task.current_step_index, resumed_task.steps.size()
			])
		resumed_task = TaskQueueService.pop_suspended_task(individual)
	if resumed_task != null:
		if DebugLogging.ENABLED and DebugLogging.SHOW_TASK_LIFECYCLE_LOGS:
			print("[INTERRUPT DEBUG] #%d %s: individuo libero, nessun bisogno attivo — riprende '%s' dalla coda." % [
				individual.id, individual.name, resumed_task.task_name
			])
		TaskDebugRegistry.on_task_closed(individual.current_task)
		individual.current_task = resumed_task
		TaskDebugRegistry.on_task_assigned(individual, resumed_task)
		activate_resumed_task(individual, resumed_task)
		return

	if IdleTaskAssignmentService.assign_idle_fallback(individual, age_band, world):
		return
	individual.stop()


# Attiva l'azione corrente di una Task appena RIPRESA dalla coda — ESTRATTO da resolve_idle_
# individual sopra (2026-09-15, richiesta utente, "click ripetuto"... no, questo è il giro
# successivo: "se sto facendo C non persistente con A in coda a zaino pieno, riprendo subito A") —
# ORA un SECONDO chiamante, HumanIndividual.assign_task: quando un nuovo comando manuale sostituisce
# una Task in corso NON persistente (Rest/Emergency Rest/Daydream/Wander/Play) mentre lo zaino ha
# ancora il carico di una Task persistente sospesa in coda, quella Task va ripresa SUBITO al posto
# del nuovo comando (che va lui in coda) — STESSA identica logica "Walk di ritorno alla ripresa" di
# sempre, nessun motivo di duplicarla per il nuovo chiamante invece di riusarla.
#
# STATIC — non tocca mai `self`, stesso motivo/stesso trattamento di _resolve_active_stamina_need_
# priority sopra: nessun impatto sul chiamante esistente (resolve_idle_individual, che continua a
# chiamarla identica), HumanIndividual.gd la richiama da un contesto senza istanza di questa classe.
#
# No-op se resumed_task è già conclusa — stesso guard già presente prima di questa estrazione.
static func activate_resumed_task(individual: HumanIndividual, resumed_task: Task) -> void:
	if resumed_task.is_finished():
		return
	# "Walk di ritorno alla ripresa" (2026-09-13, richiesta utente, in preparazione al fix generico
	# per QUALUNQUE Task sospesa il cui step corrente è un'Action stazionaria con una posizione
	# fisica precisa — PickUp/Unload(RESOURCE)/Retrieve/SetupSite/Clear/Build, vedi Action.
	# get_required_position) — QUI, non dentro TaskQueueService.pop_suspended_task: quel service si
	# dichiara esplicitamente "il meccanismo, non la policy" (vedi il suo commento di testata),
	# mentre questa funzione è il punto che decide cosa fare al momento della ripresa. MAI per un
	# WalkAction (skip esplicito, richiesta utente — riprenderebbe comunque da solo ricalcolando la
	# distanza residua al proprio activate(), nessun secondo Walk sopra un Walk): tecnicamente
	# ridondante con la classe base di get_required_position (WalkAction non la sovrascrive,
	# tornerebbe comunque null), ma reso esplicito per chiarezza e per non dipendere in futuro da
	# quell'omissione se mai qualcuno la aggiungesse per errore.
	var resumed_action := resumed_task.get_current_action()
	if not (resumed_action is WalkAction):
		var required_position: Variant = resumed_action.get_required_position(individual, resumed_task.context)
		if required_position != null and individual.position != required_position:
			if DebugLogging.ENABLED and DebugLogging.SHOW_TASK_LIFECYCLE_LOGS:
				print("[RESUME WALKBACK] #%d %s: '%s' riprende su %s, ma l'individuo è a %s invece di %s — inserito Walk di ritorno." % [
					individual.id, individual.name, resumed_task.task_name,
					resumed_action.get_script().get_global_name(),
					str(individual.position), str(required_position)
				])
			resumed_task.insert_step_before_current(WalkAction.new(required_position))
			resumed_action = resumed_task.get_current_action()
	resumed_action.activate(individual, resumed_task.context)


# Interrupt/coda da bisogno stamina (2026-09-13, richiesta utente) — chiamata da apply_action
# SUBITO DOPO l'applicazione dei delta stamina/happiness di questo frame, PRIMA di
# record_step_cost/is_complete: valuta se `task` (la Task ATTUALMENTE attiva) va interrotta a
# favore di una Task-bisogno più urgente. Ritorna true se ha sostituito individual.current_task
# (il chiamante deve fermarsi per questo frame — `task`/`action` locali non sono più validi).
#
# no-op (ritorna false) se game_data è null: senza game_data non è risolvibile un age_band per
# individual.assign_task(), quindi l'intero sistema resta disattivato per questa chiamata — stesso
# principio difensivo già riservato a world null altrove in questo file.
#
# Regola di NON-downgrade (richiesta esplicita, Punto 3): se l'individuo sta GIÀ eseguendo una
# Task-bisogno (task.interrupt_priority != -1), interrompe SOLO per una priorità di urgenza
# MAGGIORE (numero più basso); a parità o priorità inferiore, lascia proseguire `task` fino al suo
# naturale is_complete() — mai downgradare una Task-bisogno già in corso solo perché la soglia che
# l'ha attivata non è più superata. Se invece task.interrupt_priority == -1 (lavoro/Task non-
# bisogno), un bisogno attivo interrompe SEMPRE.
func _handle_stamina_interrupt(individual: HumanIndividual, task: Task, world: World, game_data: GameData) -> bool:
	if game_data == null:
		return false
	var needed_priority := _resolve_active_stamina_need_priority(individual)
	if needed_priority == -1:
		return false
	if task.interrupt_priority != -1 and needed_priority >= task.interrupt_priority:
		return false

	if DebugLogging.ENABLED and DebugLogging.SHOW_TASK_LIFECYCLE_LOGS:
		print("[INTERRUPT DEBUG] #%d %s: bisogno stamina attivo (priorità %d, stamina=%.1f/%.1f) — Task '%s' in corso sostituita." % [
			individual.id, individual.name, needed_priority, individual.current_stamina, individual.max_stamina, task.task_name
		])

	# Disposizione della Task sostituita (sospesa in coda se is_suspendable, altrimenti scartata se
	# applicabile) — RIMOSSA da qui (2026-09-13, richiesta utente, CAMBIO COMPORTAMENTO: la
	# sospendibilità conta SEMPRE, indipendentemente da chi causa la sostituzione): ORA interamente
	# gestita da HumanIndividual.assign_task() sotto (chiamata da NeedTaskAssignmentService), un
	# solo punto invece di due copie della stessa logica — vedi quel file per il dettaglio dei due
	# rami (sospendibile -> TaskQueueService.push_suspended_task; non sospendibile -> discard se
	# is_interrupt_transition è false, mai qui che è sempre true).
	var age_band := _resolve_age_band(individual, game_data)
	if needed_priority == INTERRUPT_PRIORITY_EMERGENCY_REST:
		NeedTaskAssignmentService.assign_emergency_rest_task(individual, age_band, true)
	else:
		NeedTaskAssignmentService.assign_rest_task(individual, world, age_band, true)
	return true


# Cosa succede quando una Task termina NATURALMENTE (is_finished() diventa vero) — chiamata da
# apply_action SOLO in quel punto, DOPO la skill growth (2026-09-13, richiesta utente, sistema di
# interrupt/coda da stamina critica, Punto 5). Thin wrapper (2026-09-13, richiesta utente, bugfix
# "individuo mai avviato resta fermo per sempre") — la sequenza bisogno/coda/fallback perditempo
# ORA vive SOLO in resolve_idle_individual sopra (riusata da altri 3 punti fuori da questo file,
# vedi quel commento): qui resta solo il log SPECIFICO di questa transizione ("Task X conclusa"),
# che resolve_idle_individual non potrebbe scrivere da sé (non riceve/non deve ricevere `task`, i
# suoi tre chiamanti esterni non hanno mai una "Task appena conclusa" a cui riferirsi). game_data
# null (mai un caso reale, difensivo) salta direttamente a individual.stop().
func _handle_task_completion_need_and_queue(individual: HumanIndividual, task: Task, world: World, game_data: GameData) -> void:
	if game_data == null:
		individual.stop()
		return
	if DebugLogging.ENABLED and DebugLogging.SHOW_TASK_LIFECYCLE_LOGS:
		print("[INTERRUPT DEBUG] #%d %s: Task '%s' conclusa — valuto bisogno/coda/fallback perditempo." % [
			individual.id, individual.name, task.task_name
		])
	# ZOMBIE GUARD — causa alla radice (2026-09-16, richiesta utente, fix "task zombie") — rilascia
	# QUI la task appena conclusa, PRIMA di chiamare resolve_idle_individual sotto: senza questo,
	# individual.current_task restava puntato alla task già finita (current_step_index ==
	# steps.size()) per tutta la durata di resolve_idle_individual/assign_idle_fallback/assign_task,
	# che la trovava ancora "in corso" e — se is_suspendable (vero per transport/build/
	# haul_resource) — la sospendeva in coda COSÌ COM'È non appena una Task-bisogno o un idle-
	# fallback veniva assegnato a seguire. Alla ripresa, activate_resumed_task la trovava già
	# conclusa e non faceva nulla: individuo bloccato per sempre (vedi ricognizione). Nessun altro
	# punto di questa funzione/di resolve_idle_individual legge ancora `task` dopo questo azzeramento
	# (usano solo `individual`/`age_band`/`world`) — TaskDebugRegistry.on_task_closed PRIMA
	# dell'azzeramento, stesso ordine già in uso da HumanIndividual.stop()/assign_task per lo stesso
	# scopo (mai una entry del pannello 🐞 lasciata "in corso" per una task in realtà già conclusa).
	TaskDebugRegistry.on_task_closed(task)
	individual.current_task = null
	var age_band := _resolve_age_band(individual, game_data)
	resolve_idle_individual(individual, age_band, world)


# ZOMBIE GUARD — recupero da salvataggio (2026-09-16, richiesta utente, fix "task zombie") —
# chiamata da GameScene._ready() PRIMA di valutare se un individuo caricato è libero: un
# salvataggio fatto PRIMA di questo fix può ancora contenere una current_task già conclusa
# (current_step_index >= steps.size()), prodotta dal bug ora corretto alla radice sopra. No-op
# (ritorna false) se current_task è null o non ancora conclusa — il caso comune, nessun log per
# quello. Log gated dalla categoria SAFETY (2026-09-16, richiesta utente — riordino log di debug:
# prima stampava sempre, indipendentemente da DebugLogging.ENABLED; SHOW_SAFETY_LOGS default true
# mantiene la stessa visibilità di prima a impostazioni invariate, ma ora rispetta anche il master
# switch ENABLED come ogni altro log del progetto).
static func recover_zombie_current_task(individual: HumanIndividual) -> bool:
	if individual.current_task == null or not individual.current_task.is_finished():
		return false
	var zombie_task := individual.current_task
	if DebugLogging.ENABLED and DebugLogging.SHOW_SAFETY_LOGS:
		print("[ZOMBIE GUARD] Individuo #%d %s: current_task '%s' (step %d/%d) già conclusa ma mai rilasciata — rilasciata ora, HumanIndividualActionService.recover_zombie_current_task." % [
			individual.id, individual.name, zombie_task.task_name, zombie_task.current_step_index, zombie_task.steps.size()
		])
	TaskDebugRegistry.on_task_closed(zombie_task)
	individual.current_task = null
	return true
