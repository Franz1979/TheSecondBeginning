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
# Folk/HumanPopulationGroup/HumanIndividual). Sostituisce player_micro_x/y (RIMOSSI, ridondanti
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

# true dopo che il completamento del PRIMO edificio con accepts_thoughts della partita ha già
# aperto l'albero delle idee (vedi GameScene._on_building_construction_completed) — persistito
# perché il trigger è "una volta per partita", non "una volta per sessione".
var thought_building_tech_tree_shown: bool = false

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
