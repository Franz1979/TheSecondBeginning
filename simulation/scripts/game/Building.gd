class_name Building
extends RefCounted

# Istanza runtime di un edificio piazzato — stato di PARTITA (salvato/caricato da GameSaveService/
# GameLoadService, sezione "world.buildings", mai come .tres: i parametri di TIPO restano su
# BuildingRules, stesso schema di PopulationGroup/AnimalRules). Nessun controllo di
# sovrapposizione/spazio libero ancora scritto qui — solo il dato.

# ID progressivo assegnato UNA volta alla creazione (vedi World.allocate_building_id), mai
# ricalcolato — stesso principio di PopulationGroup.id: resta stabile per tutta la vita
# dell'edificio, indipendente da quanti altri ne esistono o vengono distrutti nel frattempo.
var id: int = 0

# Nome file/tipo (es. "hut", per BuildingCalculator.get_building_rules) — NON la chiave tr() di
# BuildingRules.building_name (es. "building_hut"), sono stringhe diverse. Serve a ricaricare
# `rules` da GameLoadService: `rules` stesso non viene mai serializzato (è dato statico di tipo,
# stesso principio di PopulationGroup che salva species_name e non l'AnimalRules).
var building_type_name: String = ""
var rules: BuildingRules = null

# Coordinate MACRO della cella che ospita l'edificio.
var macro_x: int = 0
var macro_y: int = 0

# Coordinate MICRO (0..World.WIDTH*CELL_SIZE-1 in unità di microcella, non pixel) all'interno
# della macrocella ospitante — dove esattamente disegnare l'edificio (vedi GameScene.
# _place_building_at/MicroCellRenderer._draw_buildings). Non usate per alcuna logica di
# simulazione (spazio/dedicated_space resta a livello di macrocella intera, vedi
# MacroCellState.dedicated_space), solo per il rendering.
var micro_x: int = 0
var micro_y: int = 0

# -1 = costruzione non ancora iniziata. Absolute_day (GameData.get_absolute_day()) del giorno in
# cui è iniziata, non un countdown — stesso principio già usato altrove nel progetto (es.
# FogOfWarMemory.last_seen_by_position) per non dover ritoccare questo campo ogni giorno.
var construction_started_day: int = -1
var is_complete: bool = false

# true dal momento in cui GameScene._demolish_building rimuove questo edificio da world.buildings
# (2026-09-12, richiesta utente — bugfix "deposito nel vuoto": un individuo con una Task già in
# corso verso questo edificio — Walk+Unload, ramo risorsa o pensiero — tiene un riferimento diretto
# a QUESTA istanza (UnloadAction.target_building), che resta viva in memoria anche dopo la
# demolizione (Building è RefCounted: sparisce dalla LISTA world.buildings, non dalla memoria,
# finché qualcosa la referenzia ancora). Questo flag è l'unico modo per quel riferimento residuo di
# scoprire "nel frattempo sono stato demolito" — UnloadAction.activate() lo consulta per riverificare
# la validità del deposito nello stesso istante in cui l'individuo arriva (vedi lì e
# BuildingStorageService.can_accept/get_max_depositable). Mai riportato a false: un Building
# demolito non torna mai in vita, nessun bisogno di un percorso di "ripristino".
var is_demolished: bool = false

# Edificio "da demolire" (2026-09-27, richiesta utente — Demolish Task): impostato alla conferma della demolizione
# di un edificio COMPLETO (GameScene._mark_building_for_demolition), resta true finché una DemolishAction non lo
# abbatte davvero (GameScene._demolish_building, che poi imposta is_demolished). Da quel momento l'edificio non
# funziona più — niente depositi, prelievi o produzione (BuildingStorageService/ProductionService), nessun
# residente (AssignHouseService.get_free_slots) — ma resta in world.buildings e resta un ostacolo. Salvato.
var is_marked_for_demolition: bool = false

# Riparazione richiesta dal giocatore con l'idea dell'assegnazione (2026-10-10, richiesta utente): il lavoro "repair:<id>"
# entra nella coda dei lavori (GameScene._repair_jobs_collect). Si chiude da sola a Integrità piena, o se l'edificio va in
# demolizione o in miglioramento (GameScene._settle_repair_requests); la X del cassetto la toglie. Salvata con l'edificio.
var repair_requested: bool = false
# Escluso dalla riparazione automatica (2026-10-10): la X del cassetto su una riga di riparazione lo accende; si spegne
# con il martello (riparazione chiesta a mano) o a Integrità piena. Salvato con l'edificio.
var repair_auto_excluded: bool = false
# Macerie (2026-10-10, crollo): building_type_name dell'edificio crollato da cui sono nate ("" per ogni altro edificio).
# Salvato con l'edificio.
var rubble_source_name: String = ""
# Macerie escluse dallo sgombero automatico (2026-10-10): lo sgombero annullato dal giocatore (X del cassetto o "Annulla
# sgombero") lo accende; "Sgombera" lo spegne. Salvato con l'edificio.
var rubble_auto_excluded: bool = false

# true quando questo cantiere (SetupSiteAction) è bloccato perché nessuna sorgente ha materiale da
# costruzione disponibile (2026-09-14, richiesta utente — segnalazione player) — valorizzato/
# azzerato ESCLUSIVAMENTE da HumanIndividualActionService._resolve_material_shortage: true alla
# transizione (nessuna sorgente trovata, emesso anche building_material_blocked UNA volta sola per
# quella transizione), false non appena il fabbisogno è risolto (bonus di partenza applicato, o una
# Transport Task viene assegnata — non serve attendere che consegni davvero, vedi quel file per il
# perché). Consultato da GameScene.BuildingInfoPanel per mostrare la riga "In attesa di materiale"
# finché resta true. Default false — comportamento invariato per ogni edificio che non passa mai da
# questo stato (edifici già completi, o senza required_materials valorizzato).
var is_awaiting_material: bool = false

# true dal momento in cui SetupSiteAction completa per questo edificio (impostato da SetupSiteAction.
# on_complete insieme al consumo del materiale di setup — 2026-09-24, bugfix: prima lo impostava solo
# GameScene._spawn_build_site_placeholders, gestore grafico del segnale site_setup_completed che non
# sempre gira; ora quel gestore disegna soltanto i rametti)
# — DIVERSO da is_complete: un cantiere allestito non è ancora un edificio finito (ClearAction, terzo
# step, rimuove la vegetazione e riserva lo spazio ma non tocca is_complete; BuildAction, quarto e
# ultimo step arrivato il 2026-09-11, è quella che davvero lo valorizza a true — vedi BuildAction.
# on_complete), ma non è più "in attesa che qualcuno ci arrivi". MicroCellRenderer._draw_buildings
# lo usa per decidere COSA disegnare sulla microcella finché is_complete resta false (2026-09-11,
# richiesta utente — RIVISTO nello stesso giorno: PRIMA tentativo era rendere l'edificio in bianco e
# nero, scartato non appena visto in-game — la sagoma dell'edificio torna colorata insieme ai
# bastoncini, comportamento indesiderato): false = cartello "work in progress" sopra la microcella
# (vegetazione/altro contenuto resta visibile sotto); true = nessun cartello, solo i bastoncini
# spawnati da _spawn_build_site_placeholders (rimossi da GameScene._on_building_construction_
# completed quando BuildAction completa davvero) — in NESSUno dei due casi la sagoma vera
# dell'edificio (capanna/Pebble Circle/Deposit Site) viene disegnata: quella resta riservata a
# is_complete=true. Sempre true per gli edifici piazzati istantaneamente da GameScene.
# _place_building_at (nessuna fase "in attesa" per quel percorso, sagoma vera visibile da subito) e
# per quelli caricati da un save che non conosce ancora questo campo (vedi GameLoadService, fallback
# su is_complete).
var site_setup_complete: bool = false

# Valorizzata al completamento (= rules.max_durability), mai prima — scende per attacchi (futuro,
# non ancora implementato) e ogni giorno per il degrado da rules.lifespan_years (2026-10-10:
# WorldTimeService._advance_building_durability_decay). Float perché il calo giornaliero è frazionario;
# a schermo va mostrata arrotondata.
var current_durability: float = 0.0

# Soglie dell'Integrità come frazione di rules.max_durability (2026-10-10, richiesta utente). Sotto
# DURABILITY_REPAIRABLE_RATIO l'edificio si può riparare (comando "Ripara"), sotto DURABILITY_DAMAGED_RATIO è
# "danneggiato". Le usano la barra del pannello (verde/giallo/rosso) e il comando "Ripara"; DAMAGED servirà per lo stato
# "Danneggiato".
const DURABILITY_REPAIRABLE_RATIO: float = 0.7
const DURABILITY_DAMAGED_RATIO: float = 0.3


# Macerie di un edificio crollato (2026-10-10): tipo della categoria RUINS ("rubble"), da sgomberare con la Demolish.
func is_rubble() -> bool:
	return rules != null and rules.category == BuildingTypes.Category.RUINS


# Effetti dello stato "Danneggiato" (2026-10-10, richiesta utente — passo 1): regola unica, capienze a metà per difetto e
# mai sotto 1, moltiplicatori a 1; sopra la soglia tutto torna normale. BuildingRules non si tocca: i service restituiscono
# il valore effettivo passando da qui.
func get_effective_capacity(value: int) -> int:
	if value <= 0 or not is_damaged():
		return value
	return maxi(value / 2, 1)


func get_effective_multiplier(value: float) -> float:
	return 1.0 if is_damaged() else value


# Difesa effettiva (oggi solo da mostrare): a metà se danneggiato.
func get_effective_defense() -> int:
	return get_effective_capacity(rules.defense) if rules != null else 0


# Stato "Danneggiato" (2026-10-10, richiesta utente): edificio completo, non "da demolire" né demolito, con l'Integrità
# sotto DURABILITY_DAMAGED_RATIO — stesso criterio che colora di rosso la barra del pannello (percentuale intera per
# difetto). Cantieri e miglioramenti in corso (is_complete == false) non lo sono mai. Punto unico: pannello, campanella e,
# più avanti, i malus.
func is_damaged() -> bool:
	if not is_complete or is_demolished or is_marked_for_demolition or rules == null or rules.max_durability <= 0:
		return false
	var percent: int = floori(clampf(current_durability / float(rules.max_durability), 0.0, 1.0) * 100.0 + 0.000001)
	return percent < roundi(DURABILITY_DAMAGED_RATIO * 100.0)

# -1 = non ancora completato. Anno di GIOCO (GameData.year) in cui la costruzione è terminata,
# usato insieme a rules.lifespan_years per calcolare quando l'edificio scadrà.
var built_year: int = -1

# Punti di influenza per tipo (2026-10-03, richiesta utente — sostituiscono il raggio corrente del passo 4c):
# InfluenceService.InfluenceType (int) -> float. Voce assente = 0 (valore iniziale e salvataggi vecchi). Con loro il
# giorno assoluto dell'ultimo guadagno di punti per tipo (int -> int, assente = mai), da cui parte la perdita annua senza riti. Letti e
# scritti SOLO da InfluenceService (add_points/advance_daily_neglected_rites); salvati da GameSaveService.
var influence_points: Dictionary = {}
var influence_last_gain_day: Dictionary = {}
# Defunti sepolti in questo edificio (2026-10-04, richiesta utente — cumulo sepolcrale, passo 1): per ora sempre vuoto,
# lo riempirà la task di sepoltura. Un Dictionary JSON-nativo per defunto, salvato così com'è da GameSaveService.
# Capienza: BuildingRules.max_buried.
var buried: Array = []

# Giorno assoluto (GameData.get_absolute_day) dell'ultimo rito completato presso questo edificio, manuale o spontaneo
# (2026-10-02 — scritto da RiteEffectService). -1 = mai. Letto dalla regola giornaliera della fede
# (HumanVitalsInteractionService) per le case coperte da questo edificio.
var last_rite_absolute_day: int = -1

# Nome risorsa -> {"quantity": int, "decay_fraction": float} (2026-09-09, richiesta utente — Step 3
# decadimento a lotto unico: PRIMA era resource_name -> int diretto, vedi GameLoadService per la
# retrocompatibilità con save salvati nel vecchio formato). decay_fraction è una MEDIA PESATA sulla
# quantità di tutto ciò che è stato depositato nel tempo per quella risorsa in questo edificio — un
# "lotto unico" per tipo di risorsa per edificio (vedi BuildingStorageService.store per la formula
# di fusione), non un lotto per singolo deposito separato. Avanzata di 1/day_durability al giorno da
# ResourceDecayService.advance_building_decay; la entry viene rimossa dal Dictionary quando
# raggiunge 1.0 (risorsa deperita). Vuoto finché non esiste un vero inventario da cui prelevare/
# depositare.
var stored_resources: Dictionary = {}

# Progresso di costruzione (2026-09-10, richiesta utente — preparazione Build Task, Step 1: SOLO il
# campo; PRIMO vero consumatore arrivato il 2026-09-11 con BuildAction, poi ESTESO lo stesso giorno
# a SetupSiteAction/ClearAction). Untyped oltre Dictionary (stesso principio di stored_resources
# sopra: contenuto eterogeneo/annidato, un Dictionary tipizzato non lo rappresenterebbe comunque
# meglio). Contenuto REALE oggi:
#   {"site_setup_days_done": float, "clear_days_done": float, "labor_accumulated": float,
#    "space_reserved": bool}
# — le prime tre scritte in modo incrementale ad ogni get_stamina_delta() del rispettivo step
# (SetupSiteAction/ClearAction/BuildAction), MAI cachate su un campo interno dell'Action: questa è
# la ragione per cui il progresso sopravvive a un'interruzione (una nuova Task assegnata allo stesso
# individuo a metà step, che scarta l'istanza Action corrente SENZA passare da
# TaskPersistenceService — quel percorso esiste solo per salvataggio/reload, non per una
# riassegnazione in-sessione) — una nuova istanza dello stesso tipo di step, per lo stesso Building,
# legge il valore già presente qui e riparte da lì, per costruzione, senza bisogno di alcun
# ripristino esplicito. Vedi le tre classi per la formula/soglia di ciascuna chiave (SetupSiteAction.
# DURATION_DAYS fissa; ClearAction._duration calcolata da grass/tree/shrub della microcella;
# BuildAction.rules.required_labor). "space_reserved" (2026-09-12, richiesta utente — bugfix
# idempotenza) è un caso A PARTE, non una soglia progressiva come le altre tre: un booleano scritto
# UNA SOLA VOLTA da ClearAction.on_complete (mai da get_stamina_delta), marca che dedicated_space
# [BUILDING] è già stato incrementato per questo edificio — DISTINTO da "clear_days_done >=
# _duration" (che dice solo che il tempo è maturato): serve a evitare che una ClearAction
# ricostruita da zero per un edificio già "clear" (auto-skip immediato) rieseguisca la riserva di
# spazio una seconda volta, vedi ClearAction._get_space_reserved/on_complete. "materials_delivered"
# (previsto nella convenzione originale di
# questo campo, mai imposto da alcun codice) resta FUORI SCOPE per ora — richiesta esplicita utente:
# nessun consumo/verifica di rules.required_materials in questo giro, arriverà con una futura Bring
# Task dedicata, che allora scriverà qui una chiave "materials_delivered": {resource_name: quantity,
# ...} pensata per rispecchiare le stesse chiavi di BuildingRules.required_materials (confronto
# "consegnato ≥ richiesto" campo per campo diretto). Vuoto finché nessuna Build Task esiste (edifici
# piazzati istantaneamente da GameScene._place_building_at restano con questo campo vuoto per
# sempre, coerentemente con is_complete=true assegnato subito — vedi quella funzione, non toccata
# qui). Non tocca construction_started_day: resta come oggi, nessun consumatore ancora.
var construction_progress: Dictionary = {}

# Produzione in corso presso questa workstation (2026-09-23, richiesta utente — ProduceAction) —
# stesso principio di construction_progress sopra: letto e scritto DAL VIVO dall'Action ad ogni
# get_stamina_delta, mai cachato sull'istanza, così il progresso sopravvive a interruzioni e
# salvataggi (serializzato per intero da GameSaveService/GameLoadService). Contenuto:
#   {resource_name: {"labor_accumulated": float}} — UN RECORD PER RICETTA in corso (2026-09-24,
#   richiesta utente), al più BuildingRules.production_concurrent_orders record.
# Vuoto = nessuna produzione in corso. Scritto/rimosso SOLO da ProductionService (start_production/
# add_labor/complete_production/make_room_for). Ogni ricetta con un record = produzione in corso:
# BuildingStorageService.can_accept restringe i materiali delle ricette in corso alla quantità
# esatta mancante (vedi ProductionService.get_missing_inputs, che somma i fabbisogni).
var production_progress: Dictionary = {}
# Ordini separati (2026-10-04, ProductionService "ORDINI SEPARATI"): production_progress è chiave d'ordine -> record;
# production_suspended è ricetta -> lavoro del ciclo interrotto da un ordine annullato (il più alto);
# production_order_counter genera le chiavi d'ordine ("o<n>"), mai riusate. Tutti salvati.
var production_suspended: Dictionary = {}
var production_order_counter: int = 0
# Attrezzeria (2026-10-04, BuildingToolkitService): nome attrezzo -> {"quantity", "used_instances"}, come il magazzino
# per gli attrezzi. Separata da stored_resources. Salvata; vuota per i save precedenti.
var toolkit: Dictionary = {}

# Buffer di uscita della produzione (2026-09-23, richiesta utente) — nome risorsa -> quantità (int),
# SEPARATO da stored_resources: qui finisce il prodotto al completamento di un ciclo
# (ProductionService.complete_production), con capienza a pezzi BuildingRules.production_output_slots.
# Travasato automaticamente nello storage quando l'edificio ha slot liberi (ProductionService.
# flush_output_to_storage); altrimenti si svuota solo con un Retrieve (BuildingStorageService.withdraw
# preleva da stored_resources e poi da qui). Nessun decadimento mentre resta nel buffer: il prodotto
# riparte da decay_fraction 0.0 quando ne esce.
var production_output: Dictionary = {}

# Materiali della riparazione (2026-10-10, richiesta utente — materiali della Ripara, passo 1: solo il contenitore) —
# nome risorsa -> quantità (int), SEPARATO da stored_resources come production_output e toolkit: riservato ai materiali
# portati per la riparazione, mai visto da scorte, prelievi, ricerca del magazzino e depositi normali. Oggi nessuno ci
# scrive; lo legge solo il pannello dell'edificio. Salvato con l'edificio (vuoto per i salvataggi precedenti).
var repair_materials: Dictionary = {}
# Piano dei materiali della riparazione in corso (2026-10-10, passo 2 — vedi RepairAction, chiavi PLAN_*): fissato alla
# prima unità di lavoro, cancellato alla fine o all'abbandono della riparazione; {} = nessun piano. Salvato con l'edificio.
var repair_plan: Dictionary = {}
# Riparazione ferma perché un materiale del piano non si trova in nessun magazzino (2026-10-10, passo 4): acceso da
# HumanIndividualActionService quando il rifornimento non trova sorgenti, spento appena parte un giro, il lavoro riprende o
# la riparazione finisce. Letto da campanella e pannello. Non salvato: dopo un caricamento lo riaccende il primo tentativo.
var repair_awaiting_material: bool = false

# Restrizione PER-ISTANZA delle categorie accettate (2026-09-09, richiesta utente) — DIVERSO da
# BuildingRules.accepted_categories: quello è per TIPO (condiviso — vedi BuildingCalculator.
# get_building_rules, che cacha il .tres per path: ogni edificio dello stesso tipo punta allo
# STESSO oggetto BuildingRules, mai una copia per istanza — modificarlo lì cambierebbe TUTTI i
# depositi/capanne del mondo). enabled_categories invece vive QUI, su questa singola istanza:
# vuoto (default) = nessuna restrizione propria, accetta tutto ciò che il TIPO già accetta —
# un ulteriore filtro che il player può restringere (mai ampliare: BuildingStorageService.
# can_accept controlla ENTRAMBI i livelli, il tipo resta comunque il tetto massimo) solo tra le
# categorie che il tipo ammette, edificio per edificio (es. "il magazzino #3 accetta solo cibo,
# il #7 solo materiali grezzi", pur essendo entrambi lo stesso tipo di edificio generico).
#
# Controllo SOLO IN ENTRATA (richiesta esplicita utente) — togliere una categoria da qui non
# rimuove/butta fuori ciò che è già in stored_resources con quella categoria, impedisce solo
# nuovi depositi futuri di quella categoria: BuildingStorageService.can_accept è consultato SOLO
# da store() (il momento del deposito), mai da get_used_space/get_slots_used/get_slot_breakdown
# (che restano una lettura pura di ciò che è già stoccato, a prescindere da questo filtro).
var enabled_categories: Array[SecondaryResourceTypes.Category] = []
# true = il filtro per-istanza è attivo e enabled_categories è l'elenco ESATTO delle categorie accettate, anche vuoto
# ("nessuna categoria": togliendo tutte le spunte l'edificio non accetta niente). false = nessuna restrizione propria,
# enabled_categories ignorato (2026-09-28, richiesta utente — prima "vuoto" valeva sempre "accetta tutto"). Salvataggi
# precedenti: GameLoadService lo deduce da enabled_categories (non vuoto = attivo), stesso comportamento di prima.
var restricts_categories: bool = false

# Orientamento (dove guarda la porta) — scelto dal player durante il piazzamento (vedi
# BuildingGhost.rotation/GameScene, tasto R per ruotare), fissato al momento del piazzamento
# stesso (nessun modo per ruotare un edificio già costruito, per ora). Default SOUTH = porta
# verso il basso/il player.
var rotation: GameTypes.Direction = GameTypes.Direction.SOUTH


func _init(_rules: BuildingRules = null, _macro_x: int = 0, _macro_y: int = 0, _building_type_name: String = "") -> void:
	rules = _rules
	macro_x = _macro_x
	macro_y = _macro_y
	building_type_name = _building_type_name


# Interfaccia "target riassegnabile" (2026-09-12, richiesta utente — sostituzione di
# _pending_build_tasks con un percorso generico di riassegnazione Task). Duck-typed, non un'
# interfaccia/classe base formale — stessa convenzione già in uso da SpatialSelectionService.
# find_nearest (assume solo che il candidato esponga certi campi/metodi, nessun contratto GDScript
# esplicito): un futuro secondo tipo di target (non-Building) può implementare questi stessi tre
# metodi senza ereditare da qui. Building.gd resta nel layer di simulazione (simulation/scripts/
# game/) e non può dipendere da concetti di gameplay/rendering (LiveMacroCell/MicroCellRenderer/
# GameScene) — per questo get_resumable_task_context sotto NON risolve is_currently_grass (serve il
# renderer live): quel dato resta responsabilità del chiamante (vedi TaskReassignmentService/
# GameScene._try_assign_build_command_on_right_click, extra_context).

# true finché esiste ancora lavoro da fare su questo edificio — è la condizione che decide se il
# click destro su di esso deve (ri)avviare/riprendere una Task invece di essere ignorato: la Build
# Task per un cantiere non completo, la Demolish Task (2026-09-27) per un edificio "da demolire".
# Un edificio completo e non da demolire non è un target riassegnabile.
func has_resumable_task() -> bool:
	return not is_complete or is_marked_for_demolition


# Path del TaskDefinition da ricostruire da zero per riprendere il lavoro su questo edificio. Vive
# QUI (non su GameScene, dove stava prima come BUILD_TASK_DEFINITION_PATH) perché è un dato di TIPO
# di target riassegnabile, non un dettaglio del chiamante — un futuro secondo tipo di target
# riassegnabile fornirà il proprio path allo stesso modo. demolish.tres (Walk → Demolish) per un
# edificio "da demolire" (2026-09-27).
func get_resumable_task_definition_path() -> String:
	if is_marked_for_demolition:
		return "res://gameplay/scripts/tasks/definitions/demolish.tres"
	return "res://gameplay/scripts/tasks/definitions/build.tres"


# Contesto minimo per TaskFactory.build_task — SOLO "target_position"/"target_building", le due
# chiavi che Building può risolvere da sé (stesse chiavi/stessa formula Vector2(micro_pos) già usate
# da _start_building_task_at). "macro_state"/"is_currently_grass" (le altre due chiavi lette da
# build.tres, vedi TaskFactory/ClearAction) restano FUORI: la prima serve MacroCellState (World non
# è raggiungibile da qui, layer di simulazione — vedi nota sopra), la seconda il renderer live
# (layer di gameplay/rendering) — entrambe responsabilità del chiamante, fuse come extra_context da
# TaskReassignmentService.reassign_task.
func get_resumable_task_context() -> Dictionary:
	# Jitter (2026-09-17, richiesta utente — bugfix "i pipottini si fermano sempre nell'angolo in
	# alto a sinistra della microcella", sovrapposti quando più lavoratori si alternano sullo stesso
	# cantiere): offset casuale interno alla cella, RICALCOLATO ad ogni chiamata (nessuna posizione
	# "canonica" da tenere stabile tra un'assegnazione e la successiva — un individuo diverso che
	# riprende questo stesso cantiere può benissimo fermarsi in un punto diverso dal precedente).
	var target_position_jitter: Vector2 = Vector2(randf_range(0.15, 0.85), randf_range(0.15, 0.85))
	return {
		"target_position": Vector2(micro_x, micro_y) + target_position_jitter,
		"target_building": self,
	}


# Quarto metodo dell'interfaccia "target riassegnabile" sopra (2026-09-12, richiesta utente — fix
# righe duplicate/fantasma nel pannello di debug 🐞 Task quando una Build Task viene ricostruita per
# lo stesso edificio, magari da/per un individuo diverso da quello che la stava già lavorando):
# chiave stabile e leggibile, indipendente da quale Task/individuo la sta lavorando in un dato
# momento — a differenza di Task.id (nuovo ad ogni ricostruzione, vedi TaskReassignmentService.
# reassign_task) o HumanIndividual.id (può cambiare tra una ricostruzione e l'altra), `id` sopra
# resta lo stesso per tutta la vita di QUESTO edificio. Consumata SOLO da TaskDebugRegistry (via
# TaskReassignmentService, che la scrive su Task.debug_target_key) — nessuna logica di simulazione.
func get_debug_target_key() -> String:
	return "building:%d" % id
