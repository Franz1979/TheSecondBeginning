class_name GameData
extends RefCounted

const DAYS_PER_YEAR := 365

# Giorno di partenza di una nuova partita (2026-09-19, richiesta utente): 220 = meta' estate
# (SUMMER = 182..272, vedi SeasonCalculator), non piu' 0 = inizio inverno. Costante separata dal default
# di current_day cosi' chi ha bisogno della stagione iniziale (es. il default di
# MicroCellRenderer.current_season) la deriva da qui invece di duplicare la stagione a mano. I
# salvataggi portano il proprio current_day (GameLoadService), quindi non sono toccati.
const START_DAY := 220

var year: int = 0
var current_day: int = START_DAY # 0..DAYS_PER_YEAR-1

# Era geologico/tecnologica corrente (richiesta utente, 2026-09-04) — GLOBALE alla partita per
# ora (un solo current_era_name per l'intera GameData, non uno per Folk), coerentemente col fatto
# che oggi esiste un solo Folk simulato (il player). Potrà diventare per-Folk (spostato su Folk
# stesso, chiave di un Dictionary, o simile) quando servirà far progredire fazioni indipendenti a
# ritmi diversi — non prima, nessuna astrazione anticipata qui. Scritto SOLO dal default per ora:
# nessun trigger di avanzamento tech→era esiste ancora (vedi set_current_era sotto, il punto
# d'ingresso pronto per quella futura logica, non ancora chiamato da nessuno).
var current_era_name: String = "paleolithic"

# Cache delle durate effettive delle age band (HumanRules.age_band_durations_male/female ×
# EraRules.longevity_multiplier_by_age dell'Era corrente, vedi EraCalculator.
# compute_effective_age_band_durations) — persistita insieme a current_era_name invece di essere
# ricalcolata ogni anno: il calcolo stesso è banale, ma tenerlo cachato invece che inline evita che
# ogni chiamante debba conoscere sia HumanRules CHE EraRules solo per leggere una durata — gli
# basta questa cache già risolta. Consumata da HumanSeedingService (semina) e HumanCalculator.
# get_age_band (display/aging — collegato 2026-09-04, richiesta utente: PRIMA restava sempre vuoto,
# nessuno chiamava mai set_current_era, vedi lì). Stessa indicizzazione posizionale di HumanRules.
# age_band_durations_male/female (0=INFANT..5=OLD, ESTESO 2026-09-12 per INFANT).
var era_effective_age_band_durations_male: Array[float] = []
var era_effective_age_band_durations_female: Array[float] = []

# Opzioni scelte in NewGameOptionsMenu e difficolta' risultante, valorizzate UNA SOLA VOLTA in
# WorldScene._populate_new_world al momento della creazione di QUESTA partita — mai piu'
# modificate dopo. Non alimentano nessuna logica di simulazione: solo statistica (poter vedere a
# posteriori, su un campione di salvataggi, che opzioni/difficolta' scelgono davvero i
# giocatori). starting_difficulty_ratio e' il prodotto GREZZO dei tre moltiplicatori (vedi
# DifficultyCalculator.compute_difficulty_ratio) — MAI arrotondato, mai in percentuale qui:
# l'arrotondamento all'unita' percentuale e' solo per la barra in NewGameOptionsMenu, i dati
# salvati restano sempre il valore esatto. -1.0 = non applicabile (world_age_mode "CLASSIC").
var starting_world_age_mode: String = ""
var starting_animal_density: String = ""
var starting_population_size: String = ""
var starting_exclude_hostile_start: bool = false
var starting_exclude_predator_territories: bool = false
var starting_resource_richness_preference: String = ""
# A differenza dei campi sopra (puramente statistici), questo e' predisposto per un consumo
# FUTURO reale: quando esistera' un punto che deve sapere con quanti individui il player inizia
# la partita (modulo player, non ancora implementato), leggera' questo valore invece di
# ricalcolarlo. Oggi alimenta solo DifficultyCalculator, nessuna differenza pratica.
var starting_group_size_preference: String = ""
# Nome del popolo scelto a inizio partita (2026-10-12) — "" = casuale. Non salvato: serve solo alla semina, poi
# vive in Folk.name (già persistito).
var starting_folk_name: String = ""
# A differenza dei campi puramente statistici sopra, questo alimenta DAVVERO
# FirstStartMacroCellSelectionService (vedi GameScene._ready()), esattamente come
# starting_exclude_hostile_start/starting_exclude_predator_territories/
# starting_resource_richness_preference — non e' solo una statistica.
var starting_guarantee_animal_presence: bool = false
# Stesso trattamento di starting_guarantee_animal_presence sopra (2026-09-08, richiesta utente) —
# alimenta DAVVERO FirstStartMacroCellSelectionService (vedi GameScene._ready()), non e' solo una
# statistica.
var starting_guarantee_stone_presence: bool = false
var starting_difficulty_ratio: float = -1.0

# Coordinate della macrocella "sede" del player nella futura vista GameScene (vista principale
# player su una singola macrocella, non ancora implementata). -1 = mai inizializzata: GameScene
# la interpreta come segnale per invocare FirstStartMacroCellSelectionService la primissima
# volta. Vivono qui e non in GameSettings (che è tutto stato di sola sessione, mai scritto nel
# salvataggio — vedi i suoi commenti) perché "il player ha già scelto la sua macrocella" è un
# fatto che appartiene a QUESTA partita salvata e deve sopravvivere a save/load, non solo alla
# sessione corrente. Nessun bool separato: l'esistenza di una coordinata valida è già il segnale.
var player_macro_cell_x: int = -1
var player_macro_cell_y: int = -1

# Id dell'HumanIndividual che era il bersaglio di movimento/streaming corrente (GameScene.
# individual) al momento del salvataggio/cambio-scena — richiesta utente, 2026-09-02 (persistenza
# Folk/HumanIndividual). Sostituisce player_micro_x/y (RIMOSSI, ridondanti
# ora: la posizione di OGNI individuo, bersaglio incluso, viaggia già dentro l'array persistito di
# HumanIndividual — vedi GameSaveService/GameLoadService, sezione "human"). -1 = nessun individuo
# umano persistito in questa partita (mai il caso oggi che il player esista, ma sentinella comunque
# coerente con la convenzione già in uso nel file). GameScene lo usa per ripristinare `individual`
# sul MEDESIMO membro del gruppo invece che sempre sul primo dell'array.
var player_individual_id: int = -1

# Zoom della Camera2D di GameScene (Camera2D.zoom.x == .y sempre in questo progetto — vedi
# CameraController, lo scroll/le scorciatoie +/- applicano sempre lo stesso delta a entrambi gli
# assi — quindi un solo float basta, a differenza di camera_x/y sotto che sono davvero 2D). -1.0
# = mai valorizzato: GameScene lascia lo zoom di default della .tscn (partita nuova, o save
# precedente l'introduzione di questo campo).
var camera_zoom: float = -1.0

# Posizione della Camera2D di GameScene, in pixel — lo "sgancio camera-player" anticipato nel
# commento sopra (Step 3 del piano movimento indipendente, 2026-09-02: la camera non segue più
# nessun individuo, quindi la sua posizione non è più derivabile da quella di chi la seguiva e va
# persistita per conto proprio). camera_position_saved (booleano esplicito, non il sentinel -1.0
# usato altrove in questo file) segnala "mai valorizzato" — a differenza di player_macro_cell_x/y,
# che vivono in un intervallo stretto e sempre non negativo, CameraController non ha alcun limite
# di pan (vedi la nota "Camera bounds deferred" — memoria di progetto): camera_x/y possono quindi
# legittimamente essere negativi o qualunque valore, rendendo -1.0 un sentinel ambiguo qui.
var camera_x: float = 0.0
var camera_y: float = 0.0
var camera_position_saved: bool = false

# Id dei DiscoveryHintRules già scattati in questa partita (2026-09-28, richiesta utente — sostituisce il vecchio
# bool thought_building_tech_tree_shown, migrato in GameLoadService): una scoperta si mostra una volta per partita.
# Vedi DiscoveryHintService.
var seen_discovery_hints: Array[String] = []

# Ultimo absolute_day (vedi get_absolute_day sotto) in cui GameScene ha eseguito la pulizia
# periodica di FogOfWarMemory.last_seen_by_position (vedi FogOfWarMemory.prune_stale/
# GameScene._maybe_prune_fog_of_war_memories) — deve sopravvivere a save/load, altrimenti ogni
# ricaricamento farebbe ripartire il conteggio da zero, sfasando la cadenza reale rispetto a
# quanto tempo di gioco è davvero trascorso. Default 0 (non -1 come i sentinel sopra): "mai
# potato" equivale correttamente a "come se fosse stato potato al giorno 0 di questa partita",
# nessun caso speciale da gestire nel confronto (current_absolute_day - questo campo >= intervallo).
var fog_of_war_last_prune_absolute_day: int = 0

# Individui animali delle celle vive al momento del salvataggio (individui animali step 2) — solo
# per rendere identico "salva e ricarica": GameScene li scrive appena prima di salvare
# (_sync_animal_individuals_to_game_data) e al caricamento li ricostruisce nelle celle vive invece
# di rigenerarli dalla popolazione (_take_saved_animal_individuals), poi svuota questo campo.
# Soli tipi JSON-nativi: Array di {"macro_x", "macro_y", "individuals": [{"id", "species",
# "age_band", "x", "y"}]}. Vuoto = nessun individuo salvato (partita nuova o save precedente):
# gli individui si generano dalla popolazione come sempre.
var animal_individuals_by_cell: Array = []
# Prossimo id individuo animale (AnimalGroupRenderer._next_individual_id) al momento del
# salvataggio, così dopo un caricamento un id non viene mai riusato. 0 = non salvato (save
# precedente): il contatore della sessione resta com'è.
var next_animal_individual_id: int = 0

# Log grezzo di ogni morte umana (Step 8 del piano mortalità, 2026-09-05) — un Dictionary per
# evento (individual_id, name, sex, age_at_death, cause: DeathTypes.DeathCause, year, day,
# spouse_id), scritto da GameTimeService._apply_scheduled_human_deaths. NESSUNA statistica
# aggregata calcolata o salvata qui (life expectancy, distribuzione cause, ecc.): quella arriverà
# solo con un futuro pannello statistiche, calcolata al volo da questo array grezzo. Dictionary
# (non una classe DeathEvent dedicata) per coerenza con lo stile già in uso altrove nel progetto
# per record analoghi destinati al salvataggio (es. la sezione "human"."individuals" di
# GameSaveService) — ogni campo è un tipo JSON-nativo (int/String), nessuna conversione necessaria
# al salvataggio.
var death_events: Array[Dictionary] = []

# Log grezzo di ogni nascita (Step 2 piano statistiche, 2026-09-06) — stesso ruolo/stile/schema di
# death_events sopra: un Dictionary per evento (individual_id, mother_id, father_id, sex, year,
# day, child_survived, mother_survived), scritto da HumanBirthIndividualService._create_newborn
# (l'unico punto che crea davvero un neonato). child_survived/mother_survived SEMPRE true per ora
# (placeholder — non esiste ancora il tiro di sopravvivenza figlio/madre, arriverà in uno step
# successivo). Sostituiva un precedente total_births_recorded: int (contatore semplice, rimosso —
# birth_events.size() basta, stesso principio già seguito per le morti, che non hanno mai avuto un
# contatore separato oltre a death_events.size()).
var birth_events: Array[Dictionary] = []

# Snapshot annuale della popolazione umana totale (Step 3 piano statistiche, 2026-09-06) — year
# (int) -> conteggio individui vivi in quell'anno, un punto per anno, scritto da
# GameTimeService._on_year_rolled_over (SEMPRE, non condizionato) per ogni anno che ROTOLA
# (1, 2, 3...) — l'anno 0 non rotola mai (è l'anno di partenza, non un rollover), quindi quel primo
# punto (il conteggio dei fondatori) è scritto UNA volta a parte da GameScene, nel bootstrap di una
# partita nuova (mai per una partita caricata/ripristinata). Due soli scrittori, entrambi "una
# tantum per quell'anno specifico", mai un terzo punto che li aggiorni. NON ricavabile in modo
# affidabile dai soli death_events/birth_events
# sopra (dipenderebbe dal numero di fondatori iniziali restare sempre corretto, fragile con
# un'eventuale futura immigrazione) — da qui un log dedicato invece di un calcolo derivato.
# Dictionary (chiave int), non Array[Dictionary] come death_events/birth_events sopra: qui la
# chiave stessa (l'anno) è il dato identificante, un Array di {"year":.., "count":..} sarebbe solo
# più verboso per lo stesso contenuto. ATTENZIONE persistenza: JSON non supporta chiavi non-
# stringa — GameSaveService.stringify converte le chiavi int in stringhe automaticamente,
# GameLoadService deve invece riconvertirle esplicitamente in int al caricamento (mai un
# .get(chiave_int, ...) diretto su un Dictionary appena fatto il parsing di un JSON, le sue chiavi
# sono sempre String finché qualcuno non le converte).
var population_snapshots: Dictionary = {}

# Anno (int) -> numero totale di edifici esistenti in quell'anno, un punto per anno (2026-09-12,
# richiesta utente — tab Statistiche/Edifici, grafico "numero di edifici nel tempo") — STESSO
# identico schema/STESSA identica ragione di population_snapshots sopra (Dictionary chiave int, non
# Array[Dictionary]: la chiave stessa è il dato identificante). Due soli scrittori: GameScene.
# _on_year_rolled_over scrive un punto per ogni anno che ROTOLA (mai GameTimeService, che non
# possiede macro_world.buildings — vedi lì), GameScene scrive anche il punto anno 0 nel bootstrap
# di una partita nuova (0 edifici, coerente con population_snapshots[0] = fondatori scritto nello
# stesso punto). ATTENZIONE persistenza — stessa nota di population_snapshots: chiavi int
# convertite a String da JSON.stringify al salvataggio, riconvertite esplicitamente al caricamento.
var building_snapshots: Dictionary = {}

# Le stesse due serie per villaggio (2026-10-12, statistiche filtrabili per villaggio): Village.id (int) -> {anno (int) ->
# conteggio}. Scritte negli stessi punti delle serie totali sopra, a partire dall'anno in cui il villaggio esiste;
# stesse note di persistenza (chiavi int convertite a String da JSON, riconvertite al caricamento).
var village_population_snapshots: Dictionary = {}
var village_building_snapshots: Dictionary = {}
# Valori assoluti R/C/P per villaggio a ogni cambio d'anno, dopo la crescita annuale (2026-10-12, scheda Influenza delle
# statistiche): Village.id (int) -> {InfluenceService.InfluenceType (int) -> {anno (int) -> valore (float)}}. Il popolo
# è la somma dei villaggi, calcolata dal pannello. Stesse note di persistenza (chiavi int -> String in JSON).
var village_influence_snapshots: Dictionary = {}
# Coesione per villaggio a ogni cambio d'anno, dopo il calo annuale (2026-10-14, VillageCohesionService): Village.id (int)
# -> {anno (int) -> valore (float)}. La popolazione è la media dei villaggi, calcolata dal pannello. Stesse note di
# persistenza (chiavi int -> String in JSON).
var village_cohesion_snapshots: Dictionary = {}
# Riti sociali in corso (2026-10-14, SocialRiteService — un record per edificio, formato in testa a SocialRiteService).
# Salvati; la chiave "_frame" è solo di sessione.
var active_social_rites: Array[Dictionary] = []

# Istanze runtime del futuro sistema oggetti-scaduti (Step 2, 2026-09-05, res://gameplay/scripts/
# core/ExpiredObjectRules.gd — oggi solo DEAD_BODY) — un Dictionary per istanza nel mondo:
# object_type (ExpiredObjectTypes.ExpiredObjectType), individual_id (int, -1 = non applicabile;
# valorizzato per DEAD_BODY, riferimento all'individuo deceduto), position (Vector2),
# appeared_at_year/appeared_at_day (int). A differenza di death_events sopra, "position" NON è un
# tipo JSON-nativo — GameSaveService/GameLoadService lo appiattiscono in position_x/position_y per
# il salvataggio (stessa convenzione già usata per HumanIndividual.position), il campo qui a
# runtime resta un Vector2 vero, come richiesto.
#
# Nessuna comparsa reale/rimozione/visual in questo step — solo la struttura dati e
# ExpiredObjectCalculator.is_expired (query pura, nessuna scrittura qui dentro).
var expired_objects: Array[Dictionary] = []

# Prossimo id progressivo da assegnare a un HumanIndividual appena creato (fondatore o, in
# futuro, neonato di un BirthService) — vedi allocate_human_id sotto. A differenza di
# World.next_population_group_id/next_building_id (mai salvati come campo a sé, ricalcolati da
# GameLoadService come max(id ancora presenti nel save)+1), questo campo va salvato e ricaricato
# COSÌ COM'È (GameSaveService/GameLoadService, stesso trattamento di is_pregnant): un
# HumanIndividual morto sparisce dal roster vivo ma il suo id resta referenziato altrove
# (death_events, expired_objects, mother_id/father_id/partner_id dei superstiti) — ricalcolare
# "max(id ancora vivi)+1" dopo un caricamento potrebbe quindi riassegnare l'id di un morto a un
# neonato, violando la garanzia di unicità (confermato con l'utente, 2026-09-06).
# HumanSeedingService.seed_player_start chiama allocate_human_id() per OGNI individuo che crea
# (fondatori inclusi, un solo canale condiviso tra i tre percorsi GROUP/FAMILY/COUPLE) invece di
# generare id locali 1..N per conto proprio come faceva prima — un futuro BirthService chiamerà
# lo stesso allocatore per ogni neonato, mai un "max id + 1" calcolato al volo.
var next_human_id: int = 1

func allocate_human_id() -> int:
	var id := next_human_id
	next_human_id += 1
	return id

# Mucchi di risorse a terra (2026-09-26, ground drop — vedi GroundPile/GroundPileService), un solo mucchio
# per microcella. Salvati da GameSaveService ("ground_piles"), insieme al prossimo id da assegnare.
var ground_piles: Array[GroundPile] = []
# Eventi casuali programmati (2026-09-26, richiesta utente — gameplay/events/, RandomEventService): una voce per
# evento {"id": String, "absolute_day": int, "params": Dictionary}, solo tipi JSON-nativi. Salvati da
# GameSaveService ("scheduled_random_events"), applicati e rimossi da GameTimeService il giorno previsto.
var scheduled_random_events: Array[Dictionary] = []

# Stato dei lavori senza nessuno assegnato (2026-10-07, assegnazione compiti passo A — JobBoardService): chiave del lavoro,
# la stessa della scheda "In sospeso" (es. "build:12") -> "listed" (attivo, disponibile per chiunque) o "locked"
# (bloccato, fermo finché il giocatore non lo sblocca). Una chiave assente vale lo stato iniziale del suo tipo. Lo stato resta mentre
# qualcuno ci lavora, così un lavoro abbandonato torna dov'era; la voce si toglie quando il lavoro finisce o sparisce.
# Salvato da GameSaveService ("job_board_states"), solo String.
var job_board_states: Dictionary = {}
# Priorità della lista dei lavori (2026-10-08, JobBoardService): momento d'ingresso in coda di ogni lavoro (chiave ->
# giorni assoluti con la frazione, float), modo scelto (JobBoardService.PRIORITY_*) e ordine dei tipi per
# "Personalizzata" (vuoto = ordine iniziale). Salvati da GameSaveService ("job_board_entered_at",
# "job_board_priority_mode", "job_board_kind_order"); una partita senza questi dati parte da "Più adatto".
var job_board_entered_at: Dictionary = {}
var job_board_priority_mode: String = "best_fit"
var job_board_kind_order: Array[String] = []
# Soglia della riparazione automatica (2026-10-10, regole di assegnazione: "Ripara gli edifici sotto il …%"): dato della
# partita, salvato da GameSaveService ("job_board_auto_repair_percent"); partita nuova e salvataggi vecchi: 50
# (JobBoardService.AUTO_REPAIR_DEFAULT_PERCENT). Letto e scritto da JobBoardService.get/set_auto_repair_percent.
var job_board_auto_repair_percent: int = 50
# Sgombero automatico delle macerie (2026-10-10, regole di assegnazione: "Sgombera sempre le macerie"): dato della partita,
# salvato da GameSaveService ("job_board_auto_clear_rubble"); partita nuova e salvataggi vecchi: spento.
var job_board_auto_clear_rubble: bool = false
# Livelli minimi delle scorte (2026-10-10, cassetto "Gestione scorte"): nome risorsa -> livello (int > 0; assente =
# nessun livello) e livello del cibo in giorni di autonomia (0 = nessuno). Salvati da GameSaveService
# ("stock_min_levels", "stock_min_food_days"); partita nuova e salvataggi vecchi: nessun livello. Dal 2026-10-11 i
# livelli dei materiali grezzi raccolti, tagliati o estratti fanno nascere ordini (WarehouseManagerService.request_stock, ordini
# in drawer_orders con la chiave StockRequestService.ORDER_KEY); gli altri e i giorni del cibo restano solo visivi.
var stock_min_levels: Dictionary = {}
var stock_min_food_days: int = 0
# Massimi per risorsa (2026-10-18, richiesta utente — Fossa dei rifiuti): nome -> int > 0 (assente = nessun massimo), per
# tutto il villaggio, mai sotto il minimo. Oltre, all'Inventario il gestore delle scorte ordina di portare l'eccedenza in
# una Fossa (WarehouseManagerService._request_waste). Salvati come "stock_max_levels".
var stock_max_levels: Dictionary = {}
# Regole di stoccaggio (2026-10-11, cassetto "Gestione scorte"): dal 2026-10-19 coppia carne/pelli
# (ButcherDestinationService.compose) per ciò che, nelle cacce del magazzino, avanza dopo i minimi
# (HuntProductAllocationService). I valori di prima (una voce sola) si leggono come coppia (ButcherDestinationService.parse).
# Salvata da GameSaveService ("stock_excess_meat_destination"); partita nuova e salvataggi vecchi: il magazzino.
var stock_excess_meat_destination: String = "warehouse"
# Regola "Combustibile negli edifici che lo usano" (2026-10-16, FuelStockService): accesa/spenta e minimo per tipo di
# edificio (nome tipo -> combustibile in fuel_value) cambiato nel cassetto; un tipo assente usa BuildingRules.fuel_stock_min.
# Salvati da GameSaveService ("stock_fuel_rule_enabled", "stock_fuel_min_by_type"); partita nuova: spenta, nessun cambio.
var stock_fuel_rule_enabled: bool = false
var stock_fuel_min_by_type: Dictionary = {}
# Regola "Rifornisci le Attrezzerie" (2026-10-18, richiesta utente — ToolkitStockService): accesa/spenta e pezzi voluti
# per tipo di edificio e attrezzo (tipo -> {attrezzo -> int}). Salvati ("stock_toolkit_rule_enabled",
# "stock_toolkit_targets"); partita nuova e salvataggi precedenti: spenta, nessun desiderato.
var stock_toolkit_rule_enabled: bool = false
var stock_toolkit_targets: Dictionary = {}
# Regola "Banchetti spontanei" (2026-10-17, richiesta utente — il gestore scorte non ordina banchetti, autorizza quelli
# spontanei): la casella "al massimo un terzo delle scorte". Vale solo con il gestore scorte sbloccato
# (SocialRiteService._has_idle_food_stock). Le calorie sono la "Soglia calorie" dello spiazzo (2026-10-18; prima anche
# "stock_banquet_calories", ignorato nei salvataggi vecchi). Salvata da GameSaveService ("stock_banquet_safe_only");
# partita nuova e salvataggi vecchi: accesa.
var stock_banquet_safe_only: bool = true
# Regola di assegnazione "Riponi gli attrezzi presi per un lavoro" (2026-10-11): gli attrezzi presi in deposito per un
# ordine della coda tornano in deposito quando l'individuo è libero (HumanIndividual.borrowed_tools). Salvata da
# GameSaveService ("job_board_return_borrowed_tools"); partita nuova e salvataggi vecchi: accesa.
var job_board_return_borrowed_tools: bool = true
# Regola di assegnazione "Prendi la sacca se disponibile" (2026-10-19, richiesta utente — ToolFetchService.try_take_bag): chi
# si libera senza sacca in cintura e con un posto libero va a prendere in deposito la sacca migliore e la tiene. Salvata da
# GameSaveService ("job_board_take_bag"); partita nuova e salvataggi vecchi: spenta.
var job_board_take_bag: bool = false
# Regola di assegnazione "Indossa i capi disponibili" (2026-10-19, richiesta utente — ToolFetchService.try_wear_apparel):
# chi si libera con uno slot del vestiario vuoto va a prendere in deposito i capi che gli mancano e li indossa. Separata
# dalla sacca. Salvata da GameSaveService ("job_board_wear_apparel"); partita nuova e salvataggi vecchi: spenta.
var job_board_wear_apparel: bool = false
# Regola di assegnazione "Un solo costruttore per cantiere" (2026-10-17, più costruttori): accesa, la coda dei lavori manda
# al più un costruttore per cantiere invece che fino a BuildingRules.max_builders (BuildingJobProvider.build_limit). Il
# comando manuale non ne tiene conto. Salvata da GameSaveService ("job_board_single_builder"); partita nuova e salvataggi
# vecchi: spenta.
var job_board_single_builder: bool = false
# Inventario del magazzino (2026-10-11, gestore del magazzino — WarehouseManagerService): frequenza scelta dal giocatore
# (ore di gioco tra la fine di un inventario e la richiesta del successivo), fine dell'ultimo inventario (giorni assoluti
# con la frazione del giorno, -1 = mai), chi l'ha fatto, e la "foto" delle scorte presa all'inizio dell'ultimo
# inventario (il cassetto Scorte mostra quella, non i valori in tempo reale): risorsa -> quantità, [occupato, capienza]
# dei depositi. Salvati da GameSaveService.
var inventory_interval_hours: int = 24
var last_inventory_end: float = -1.0
var last_inventory_by: String = ""
var stock_snapshot: Dictionary = {}
var stock_snapshot_fill: Array = []
var stock_snapshot_time: float = -1.0
# Ordini creati dal cassetto "Assegnazione compiti" (2026-10-09, richiesta utente): lavori in coda senza destinatario,
# chi li prende lo decide la coda (chiave della lista "order:<id>", DrawerOrderJobProvider.collect). Una voce per
# ordine, solo tipi JSON-nativi: {"id": int stabile, "type": String, ...campi del tipo}. Oggi il solo tipo "produce":
# "recipe" (String), "quantity" (int), "deliver_to_warehouse" (bool); senza edificio, scelto alla presa. Pensato
# generico: i lavori di zona entreranno qui con un "type" loro. Salvati da GameSaveService ("drawer_orders",
# "next_drawer_order_id").
var drawer_orders: Array[Dictionary] = []
var next_drawer_order_id: int = 1
# Posti dei coordinatori (2026-10-09, CoordinatorService): id del punto di assegnazione (String, chiave JSON) ->
# {"coordinator_id": int (-1 = nessuno), "queue": [id di chi aspetta, in ordine di arrivo], "serving_id": int (chi sta
# ricevendo le istruzioni, -1 = nessuno; il coordinatore stesso = autoassegnazione), "serving_since": float (giorni di
# gioco)}. Solo tipi JSON-nativi; salvati da GameSaveService ("coordinator_posts").
var coordinator_posts: Dictionary = {}
# Primo giro di CoordinatorService su questa partita già fatto (posti caricati controllati). Mai salvato.
var coordinator_posts_checked: bool = false
# Stato della lista dei lavori che vive solo durante la partita (attese per l'assegnazione a mano, lavori aperti all'ultimo
# giro). Mai salvato (2026-10-17, refactoring GameScene blocco 2a — vedi JobBoardRuntimeState).
var job_board_runtime: JobBoardRuntimeState = JobBoardRuntimeState.new()
# Stato della manutenzione degli edifici (danneggiati all'ultimo giro, controlli giornalieri di riparazione e sgombero
# automatici). Mai salvato (2026-10-17, refactoring GameScene blocco 3a — vedi BuildingRuntimeState).
var building_runtime: BuildingRuntimeState = BuildingRuntimeState.new()
# Stato del gestore delle scorte (inventario in decisione, nomi da riempire, pausa delle cacce, avvisi dell'essiccatoio).
# Mai salvato (2026-10-17, refactoring GameScene blocco 4 — vedi StockRuntimeState).
var stock_runtime: StockRuntimeState = StockRuntimeState.new()
# Anno dell'ultimo evento avvenuto per ogni CATEGORIA di eventi casuali (2026-09-27, richiesta utente —
# raffreddamento condiviso, vedi RandomEventCategoryRules): id categoria (String) -> anno (int). Scritto da
# RandomEventService.apply_event, letto dal sorteggio. Salvato da GameSaveService ("random_event_category_last_year").
var random_event_category_last_year: Dictionary = {}
var next_ground_pile_id: int = 1

func allocate_ground_pile_id() -> int:
	var id := next_ground_pile_id
	next_ground_pile_id += 1
	return id

# Gruppi di visitatori presenti (2026-09-27, richiesta utente — gameplay/visitors/, VisitorService): fuori
# dal villaggio finché non vengono accolti o se ne vanno. Salvati da GameSaveService ("visitor_parties"),
# insieme al prossimo id da assegnare.
var visitor_parties: Array[VisitorParty] = []
var next_visitor_party_id: int = 1

func allocate_visitor_party_id() -> int:
	var id := next_visitor_party_id
	next_visitor_party_id += 1
	return id

# Zone di lavoro (2026-09-27, richiesta utente — work areas, vedi WorkArea/WorkAreaService). Salvate da
# GameSaveService ("work_areas"), insieme al prossimo id da assegnare.
var work_areas: Array[WorkArea] = []
var next_work_area_id: int = 1
# Contatore delle modifiche all'elenco delle zone (runtime, non salvato): alzato da WorkAreaService a ogni
# creazione/eliminazione, letto dalle viste (overlay del layer "Aree di lavoro", minimappa) per ridisegnarsi.
var work_areas_revision: int = 0
# Contatore delle modifiche agli edifici (2026-10-02, runtime, non salvato): alzato da GameScene.
# _refresh_building_slots_buildable (caricamento, piazzamento, completamento, demolizione), letto dagli overlay dei
# layer di influenza (InfluenceLayerOverlay) per ridisegnarsi solo quando serve.
var buildings_revision: int = 0
# Ultima destinazione dei prodotti della macellazione scelta nell'ordine di caccia (2026-10-03, ButcherDestinationService,
# salvata con la partita): proposta all'apertura del dialog e usata dalla caccia diretta. Dal 2026-10-19 coppia carne/pelli;
# un valore di prima si legge come coppia. "" = mai scelta.
var last_butcher_destination: String = ""
# Ordinamento dell'elenco dei pipottini nella scheda popolazione (2026-10-04, salvato con la partita): id di
# HumanPopulationInfoPanel.SORT_OPTIONS ("age", "name", "house"). Un id sconosciuto ricade sul predefinito.
var population_list_sort: String = "age"

func allocate_work_area_id() -> int:
	var id := next_work_area_id
	next_work_area_id += 1
	return id

# Monotonic day count since year 0, day 0 — the single source of truth for "how long ago"
# comparisons (e.g. natural-event growth-bonus expiry) that must not reset/round at a year
# boundary the way a per-year counter would.
func get_absolute_day() -> int:
	return year * DAYS_PER_YEAR + current_day

# Advances the calendar by one day. Returns true if this tick rolled the
# year over (current_day wrapped back to 0, year incremented) — callers use
# this to decide whether to run the yearly simulation pipeline.
func advance_day() -> bool:
	current_day += 1
	if current_day >= DAYS_PER_YEAR:
		current_day = 0
		year += 1
		return true
	return false


# Punto d'ingresso pronto per un futuro "on_era_changed" (richiesta utente, 2026-09-04) — ancora
# NESSUN trigger tech→era implementato (vedi current_era_name sopra), ma dal 2026-09-04 questo
# metodo viene comunque chiamato UNA volta, come bootstrap, da GameScene subito prima della semina
# (per l'Era di partenza "paleolithic" — non è un vero cambio Era, solo l'inizializzazione iniziale
# della cache sotto, prima sempre vuota perché nessuno lo chiamava affatto). Deliberatamente NON
# agganciato a nessun tick periodico (advance_day/anno): un cambio Era è un evento raro e discreto,
# non qualcosa da ricontrollare ogni giorno — quando la logica di progressione arriverà, chiamerà
# semplicemente questo metodo nel momento esatto in cui scatta, qualunque punto dell'anno sia.
# human_rules è quello del Folk la cui Era sta cambiando (oggi: sempre quello del player, l'unico
# Folk esistente) — passato esplicitamente invece che letto da un campo di questa classe perché
# GameData non possiede/referenzia alcun Folk/HumanRules (li tiene solo GameSaveService/
# GameLoadService/GameSettings.active_human_folk, vedi loro) e non è questo il posto per aggiungere
# quel collegamento solo per questo calcolo.
func set_current_era(era_name: String, human_rules: HumanRules) -> void:
	var era_rules := EraCalculator.get_era_rules(era_name)
	if era_rules == null:
		push_error("Era sconosciuta o .tres mancante: " + era_name + " — current_era_name/cache invariati.")
		return
	current_era_name = era_name
	var effective_durations := EraCalculator.compute_effective_age_band_durations(human_rules, era_rules)
	era_effective_age_band_durations_male = effective_durations["male"]
	era_effective_age_band_durations_female = effective_durations["female"]
