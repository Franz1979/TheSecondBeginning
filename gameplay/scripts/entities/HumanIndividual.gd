class_name HumanIndividual
extends RefCounted

# Stato puro del singolo individuo controllabile in GameScene — nessuna grafica, nessun
# bisogno/statistica/inventario/IA (scope futuro, deliberatamente escluso qui). Stesso principio
# di PopulationGroup: RefCounted, non Node — la resa visiva vive solo in HumanIndividualView, che
# legge questo stato ma non viceversa.
#
# position/target_position sono in coordinate MICROCELLA continue (float), locali a
# home_macro_coords sotto (NON necessariamente "la macrocella corrente"/center_macro_coords di
# GameScene — vedi lì: solo il bersaglio di movimento corrente coincide sempre con quella, chiunque
# altro resta ancorato a qualunque macrocella occupasse l'ultima volta che la sua position è stata
# scritta) — stesso spazio di MicroCellRenderer/AnimalGroupRenderer (CELL_SIZE = 10px per
# microcella), NON le coordinate macro di GameData.player_macro_cell_x/y (quelle restano di
# competenza di GameScene).

var position: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO
var is_moving: bool = false
# Verso cui l'individuo è rivolto ORA (2026-09-04, richiesta utente: persistere l'orientamento nel
# salvataggio) — PRIMA viveva solo su HumanIndividualView (resa, mai salvata: le view sono
# ricreate da zero ad ogni caricamento, ripartendo da un default fisso). Spostato qui perché la
# persistenza passa SOLO da HumanIndividual (GameSaveService/GameLoadService non toccano mai le
# view) — non è più un puro dettaglio di resa: è "verso dove guarda" un individuo, un dato di
# stato legittimo (utile in futuro anche per meccaniche non visive, es. un cono di visione).
# Aggiornato da HumanIndividualMovementService.advance_movement (l'unico scrittore di position,
# stesso principio) — CONGELATO all'ultimo valore quando fermo, mai azzerato: HumanIndividualView
# lo legge direttamente per `rotation`, non ne mantiene più una copia propria.
var facing_direction: Vector2 = Vector2.RIGHT
# Coordinate macro ASSOLUTE della macrocella a cui `position` è locale (bugfix, 2026-09-02 — PRIMA
# implicito/assunto sempre "la cella centrale corrente", assunzione vera finché ogni individuo si
# spostava rigidamente col leader; rotta da Step 1/2 del piano movimento indipendente: un individuo
# lasciato indietro resta nella macrocella in cui si trovava, che può smettere di essere il centro).
# Valorizzato dal seeding iniziale (stessa cella per tutto il gruppo) e poi SOLO da GameScene quando
# la posizione di un individuo viene ri-scritta in una macrocella diversa (oggi: solo il bersaglio
# corrente, quando attraversa un bordo — vedi GameScene._attempt_macro_cell_transition). Sentinella
# (-1,-1) = non ancora valorizzato, stessa convenzione già in uso altrove nel progetto (es.
# GameData.player_macro_cell_x/y). GameScene lo usa per parentare/ri-parentare HumanIndividualView
# sotto il container della macrocella giusta (vedi LiveMacroCell.container) — mai per calcoli di
# simulazione, solo rendering.
var home_macro_coords: Vector2i = Vector2i(-1, -1)
# Waypoint intermedi per un futuro pathfinding — vuoto oggi: HumanIndividualMovementService muove
# sempre in linea retta verso target_position finché questo campo non verrà popolato altrove.
var path: Array[Vector2] = []
# microcelle/secondo — ridotto da 4.5 a 2.0 (richiesta utente, 2026-09-04: troppo veloce per
# leggere l'animazione delle gambe appena aggiunta a HumanIndividualView), poi ulteriormente a 1.2
# (richiesta utente, 2026-09-04: ancora troppo veloce, indipendentemente dal ritmo delle gambe —
# vedi HumanIndividualView.WALK_PHASE_SPEED, parametro deliberatamente NON accoppiato a questo).
# NON più allineato ad AnimalRules.hop_speed (boar/mouflon) come prima: se in futuro serve
# ripristinare quel confronto come riferimento di bilanciamento, va ridiscusso esplicitamente, non
# è più valido as-is.
# 10.0 (richiesta utente, 2026-09-07, ritarato dal precedente 4.8 in coppia con la ritaratura di
# SECONDS_PER_DAY_BY_SPEED — vedi GameClockController): con game_delta espresso come frazione di
# giorno di gioco, questo valore rappresenta ora DIRETTAMENTE le microcelle percorse in un giorno
# intero di cammino continuo, qualunque sia la velocità di gioco (delta=1.0 giorno → move_speed
# microcelle), non più un tarocco derivato da un microcelle/secondo reale. Scala linearmente con la
# velocità di gioco (2x=doppio, 4x=quadruplo) per costruzione.
var move_speed: float = 10.0
var is_selected: bool = false

# --- Dati anagrafici — solo campi per ora, nessuna logica di riproduzione/formazione coppie ---

# Identificatore stabile assegnato UNA volta alla creazione, mai ricalcolato — stesso principio
# di PopulationGroup.id lato animale.
var id: int = 0
var sex: HumanTypes.Sex = HumanTypes.Sex.MALE
# Anno di nascita virtuale (calendario di gioco) — l'età si ricava sempre al volo altrove come
# anno_corrente - birth_year_virtual, mai salvata come campo separato (evita un secondo dato da
# tenere sincronizzato ad ogni avanzamento anno).
var birth_year_virtual: int = 0
# Giorno (0..GameData.DAYS_PER_YEAR-1) in cui questo individuo morirà quest'anno, se
# HumanMortalityIndividualService.check_mortality l'ha marcato — Step 4 del piano mortalità.
# Sentinella -1 = nessuna morte programmata quest'anno (default, e valore di TUTTI gli individui
# non marcati: check_mortality non tocca mai questo campo per loro). A differenza di età/age_band
# (mai persistiti, sempre ricalcolati al volo da birth_year_virtual) questo VA persistito: è
# un'estrazione singola non ricalcolabile — ritirare il dado una seconda volta darebbe un giorno
# diverso, quindi il valore va salvato non appena estratto. Azzerato a -1 al rollover d'anno
# (nessun individuo può "morire" per un giorno dell'anno scorso) — non ancora implementato in
# questo step, arriverà insieme all'aggancio al tick giornaliero (Step 6).
var scheduled_death_day: int = -1
# Causa della morte programmata sopra — irrilevante finché scheduled_death_day resta -1 (nessuna
# morte in corso). Step 9 del piano mortalità (2026-09-05): scheduled_death_day da solo non diceva
# PERCHÉ un individuo stava morendo, serviva per distinguere OLD_AGE (HumanMortalityIndividualService)
# da MURDER (bottone di debug "Kill" — vedi GameTimeService.kill_individual_now, che non passa MAI
# da scheduled_death_day/scheduled_death_cause, uccide immediatamente). Default OLD_AGE puramente
# come placeholder innocuo (mai letto finché scheduled_death_day è -1).
var scheduled_death_cause: DeathTypes.DeathCause = DeathTypes.DeathCause.OLD_AGE
# Sentinella -1 = genitore/partner sconosciuto o non applicabile (es. un fondatore senza
# genitori nella partita, o nessun partner ancora assegnato) — stesso principio del sentinella -1
# già usato altrove nel progetto (es. PopulationGroup.years_since_last_split,
# Building.construction_started_day) per "non ancora valorizzato/non applicabile".
var mother_id: int = -1
var father_id: int = -1
# Nessuna logica di formazione coppie qui: solo il campo, valorizzato da un futuro service.
var partner_id: int = -1
# Step 3 del piano riproduzione (2026-09-06): valorizzato da HumanConceptionIndividualService al giorno 110,
# nessun'altra logica lo tocca in questo passo — il parto (che lo riazzererà) è un task separato,
# non ancora scritto. Default false, come ogni HumanIndividual appena creato (fondatore o figlio).
var is_pregnant: bool = false
# Tratti/padre del figlio in arrivo, PRECALCOLATI da HumanConceptionIndividualService nello stesso
# istante in cui is_pregnant diventa true (padre = partner ATTUALE della donna in quel momento,
# sicuramente vivo — zero ambiguità) — Step 2 del piano riproduzione (2026-09-06). Il motivo:
# capelli/carnagione sono ereditari (HumanIndividual.roll_inherited_hair_color/
# roll_inherited_skin_color) e richiedono i DUE genitori nel momento in cui il tiro avviene; al
# day 20 (nascita, HumanBirthIndividualService), il padre potrebbe essere morto nel frattempo — ma
# il tiro è già cristallizzato qui, quindi lo stato del padre a quel punto (vivo o morto) non ha
# alcuna importanza. Default = valore enum zero/placeholder innocuo, mai letto finché is_pregnant
# è false (stesso principio di HumanIndividual.scheduled_death_cause).
var pending_child_hair_color: HumanTypes.HairColor = HumanTypes.HairColor.BLONDE
var pending_child_skin_color: HumanTypes.SkinColor = HumanTypes.SkinColor.LIGHT
# -1 = nessuna gravidanza in corso (stessa convenzione -1 di mother_id/father_id/partner_id sopra)
# — mai letto finché is_pregnant è false. HumanBirthIndividualService lo usa come father_id del
# neonato, MAI woman.partner_id (che potrebbe essere già stato azzerato da _free_partner_if_any
# se il padre è morto tra il concepimento e la nascita).
var pending_child_father_id: int = -1
# Id del figlio da trasportare finché non cammina da solo (richiesta utente, 2026-09-06, piano
# "trasporto neonati") — valorizzato UNA VOLTA alla nascita (HumanBirthIndividualService, stesso
# momento in cui il neonato riceve mother_id = questo individuo), MAI più scritto altrove per
# tutta la vita del figlio TRANNE dal consumatore stesso (GameScene._sync_dependent_child_position,
# chiamato ad ogni frame in cui questo individuo è il bersaglio di movimento corrente), che lo
# riporta a -1 in due casi: il figlio non si trova più (morto) o ha superato la soglia d'età
# (era_rules.min_birth_spacing_years). Deliberatamente NIENT'ALTRO scrive mai -1 qui (né la morte
# del figlio né il compleanno hanno un proprio hook dedicato) — la query di consumo si "auto-
# manutiene" da sola nell'unico punto in cui il campo viene letto, invece di richiedere due
# invalidazioni sincronizzate sparse nel codice (rischio di stato stantio se una delle due venisse
# dimenticata in futuro). -1 = nessun figlio da trasportare, stessa convenzione già in uso per
# mother_id/father_id/partner_id/pending_child_father_id sopra.
var dependent_child_id: int = -1
var name: String = ""
# Collegamento inverso al gruppo/insediamento di appartenenza — nullable (un HumanIndividual
# potrebbe in teoria esistere senza un gruppo, es. durante la costruzione incrementale di questo
# sistema), valorizzato dal chiamante che crea l'individuo, mai da questa classe stessa.
var source_group_ref: HumanPopulationGroup = null

# Tratti d'aspetto (2026-09-04, richiesta utente) — vedi HumanTypes.HairColor/ClothingColor per il
# perché sono enum e non Color diretti qui. Assegnati UNA volta alla creazione (vedi
# assign_hair_color/assign_random_clothing sotto, stesso momento di assign_random_name) e mai più
# ricalcolati: stato che persiste per tutta la vita dell'individuo, salvato/caricato come
# sex/birth_year_virtual (vedi GameSaveService/GameLoadService). La mappatura enum->Color vera
# resta in HumanIndividualView (l'aspetto): questa classe resta puro stato, come sempre in questo
# file.
var hair_color: HumanTypes.HairColor = HumanTypes.HairColor.BROWN
var clothing_color: HumanTypes.ClothingColor = HumanTypes.ClothingColor.TAN
# Carnagione (2026-09-06) — stesso trattamento genetico di hair_color (vedi assign_skin_color
# sotto), un solo valore possibile oggi (HumanTypes.SkinColor.LIGHT) ma già persistito/ereditato
# come se non lo fosse, pronto per quando arriveranno altri valori.
var skin_color: HumanTypes.SkinColor = HumanTypes.SkinColor.LIGHT


# --- Sistema Stamina/Action/Task (2026-09-06/07, refactor Stamina, richiesta utente) ---

# Task correntemente in corso — nullable, default null (nessuna task, individuo implicitamente a
# Rest, vedi HumanIndividualActionService.apply_action). RINOMINATO da current_action: Action
# (2026-09-07, richiesta utente) — SOSTITUISCE del tutto il vecchio campo, mai affiancato: un
# individuo ora esegue sempre una SEQUENZA di step (Task, anche a un solo step, vedi set_target
# sotto), mai una singola Action isolata. Valorizzato da set_target sotto (comando esplicito del
# player) e da HumanIndividualActionService.apply_action (avanzamento automatico/completamento);
# azzerato da stop() sotto.
var current_task: Task = null

# Impostato a true da ThinkAction.on_complete quando un ciclo di riflessione si conclude
# (2026-09-07, richiesta utente, primo passo del futuro Daydream) — un flag "in sospeso", non un
# contatore: NESSUNA logica lo consuma/azzera ancora in questo passo (arriverà con la futura
# DepositThoughtAction, che leggerà questo flag per sapere se c'è un pensiero da depositare e lo
# rimetterà a false). Default false, mai toccato da Walk/Rest.
var pending_thought: bool = false

# Fallback usato da _resolve_initial_max_stamina sotto quando la catena source_group_ref->
# folk_ref->human_rules_ref non è ancora risolvibile — stesso valore del nuovo default di
# HumanRules.base_max_stamina, deliberatamente (un fallback "onesto": nessun consumatore reale
# esiste ancora, quindi qualunque numero coerente col resto del sistema va bene).
const FALLBACK_MAX_STAMINA: float = 5000.0

# Stamina attuale e massima — entrambe inizializzate SUBITO alla creazione, allo STESSO valore
# (vedi _init/_resolve_initial_max_stamina sotto), chiamando HumanCalculator.get_max_stamina() con
# i dati anagrafici già noti su self (sex/is_pregnant/dependent_child_id) e gli HumanRules risolti
# tramite source_group_ref.folk_ref.human_rules_ref. Nessun sistema di consumo/reset reale esiste
# ancora per current_stamina (arriverà con Walk/Rest collegati a un service esterno, step
# successivo) — questo campo parte semplicemente già pieno. max_stamina invece (2026-09-06,
# richiesta utente) viene già RICALCOLATO ogni giorno da HumanStaminaIndividualService (vedi
# human/scripts/core/HumanStaminaIndividualService.gd, agganciato a GameTimeService._on_day_
# advanced) — soluzione temporanea, vedi commento lì per il perché.
#
# TODO (limite noto, non risolto in questo passo): source_group_ref/sex/birth_year_virtual — come
# OGNI altro campo anagrafico di questa classe — vengono sempre valorizzati dal CHIAMANTE DOPO
# HumanIndividual.new() (vedi HumanSeedingService/HumanBirthIndividualService, mai passati a un
# costruttore), quindi _init() qui sotto vede quasi sempre la catena ancora null e ricade sul
# fallback sopra, per ENTRAMBI i campi. Per max_stamina questo è innocuo (il ricalcolo giornaliero
# lo corregge entro al più un giorno di gioco); current_stamina invece resta al fallback finché
# nessun sistema di consumo/reset lo tocca — non ancora un problema reale, nessun consumatore
# esiste.
var current_stamina: float = 0.0
var max_stamina: float = 0.0

# --- Capacità di trasporto (2026-09-08, richiesta utente) ---
#
# Stesso fallback/schema di FALLBACK_MAX_STAMINA sopra — usato da _resolve_initial_max_carry_
# capacity sotto quando la catena source_group_ref->folk_ref->human_rules_ref non è ancora
# risolvibile alla creazione. Stesso valore del nuovo default di HumanRules.base_carry_capacity,
# deliberatamente (un fallback "onesto", stesso principio di FALLBACK_MAX_STAMINA).
const FALLBACK_MAX_CARRY_CAPACITY: float = 30.0

# Ricalcolato ogni giorno da HumanCarryCapacityIndividualService (agganciato a GameTimeService.
# _on_day_advanced) — stesso identico pattern di max_stamina sopra, vedi quel commento per il
# perché è un ricalcolo periodico e non event-driven.
var max_carry_capacity: float = 0.0

# Nome della risorsa secondaria attualmente trasportata (SecondaryResourceRules.
# secondary_resource_name) — "" = non sta trasportando nulla. Un individuo trasporta UN SOLO tipo
# di risorsa alla volta (nessun inventario multi-risorsa) — verificato che nessun sistema
# Task/Action esistente assuma diversamente: non esiste ancora alcuna Action di raccolta/trasporto
# (TaskTypes.ActionType ha solo WALK/REST oggi), quindi nessun consumatore da rispettare/rompere.
# Nessuna logica di raccolta/deposito la valorizza ancora in questo passo — solo il dato.
var carried_resource_name: String = ""
# Quantità della risorsa in carried_resource_name — 0 quando carried_resource_name è "" (nessuna
# logica impone ancora questo invariante, dato che nulla scrive questi due campi insieme oggi, ma
# è la lettura corretta per un futuro consumatore). Spazio occupato = carried_quantity ×
# SecondaryResourceRules.space_per_unit della risorsa trasportata — calcolato al volo dal
# chiamante (mai cachato qui, vedi GameScene._update_individual_panel_content), MAI un terzo campo
# ridondante su questa classe.
var carried_quantity: int = 0

# Frazione di decadimento 0.0->1.0 della risorsa in carried_resource_name (2026-09-09, richiesta
# utente — Step 3 decadimento a lotto unico) — avanzata di 1/day_durability al giorno da
# ResourceDecayService.advance_individual_decay, azzerata insieme a carried_resource_name/
# carried_quantity quando lo zaino si svuota (per qualunque via: raggiunge 1.0 e deperisce del
# tutto, oppure viene scaricato per intero in un edificio, vedi UnloadAction.on_complete) — mai
# un valore residuo "orfano" associato a uno zaino vuoto. 0.0 di default = mai deperito, coerente
# col significato "zaino vuoto" quando accoppiato a carried_resource_name == "".
var carried_decay_fraction: float = 0.0

# Slot tool (2026-09-08, richiesta utente) — SOLO spazio/bonus per ora (vedi HumanRules.
# tool_slot_count/carry_bonus_per_empty_tool_slot), NESSUN uso funzionale: nessun sistema di equip
# esiste ancora, quindi questo resta SEMPRE 0 finché non arriverà. Letto da HumanCalculator.
# get_max_carry_capacity (bonus flat per slot VUOTO = tool_slot_count - questo campo).
var equipped_tool_count: int = 0


func _init() -> void:
	var initial_stamina := _resolve_initial_max_stamina()
	current_stamina = initial_stamina
	max_stamina = initial_stamina
	max_carry_capacity = _resolve_initial_max_carry_capacity()


# Vedi il TODO sul campo current_stamina sopra per i limiti di questa risoluzione "al volo".
# age_band: nessun riferimento a GameData esiste su questa classe (per design — vedi commento di
# testa al file, "stato puro"), quindi l'età vera (che richiede current_year) non è calcolabile da
# qui in nessun momento, non solo ora — FERTILE_ADULT è usato come default deliberato (non un
# valore a caso): è la fascia "di riferimento" con moltiplicatore 1.0 sia per età che per sesso
# nella maggior parte dei HumanRules, lo stesso principio già dichiarato per
# HumanRules.stamina_multiplier_by_age. era_rules passato null: rilevante solo per il ramo
# has_dependent_child di get_max_stamina, che quindi qui non applica mai quel moltiplicatore
# (comunque quasi sempre false a questo punto, vedi TODO sopra).
func _resolve_initial_max_stamina() -> float:
	var human_rules: HumanRules = null
	if source_group_ref != null and source_group_ref.folk_ref != null:
		human_rules = source_group_ref.folk_ref.human_rules_ref
	if human_rules == null:
		return FALLBACK_MAX_STAMINA
	return HumanCalculator.get_max_stamina(
		human_rules, HumanTypes.AgeBand.FERTILE_ADULT, sex, is_pregnant, dependent_child_id != -1, null
	)


# Stessa risoluzione "al volo" di _resolve_initial_max_stamina sopra, stessi identici limiti/
# motivazione (vedi il TODO su current_stamina sopra) — FERTILE_ADULT come default per lo stesso
# motivo (fascia di riferimento, moltiplicatore 1.0 sia per età che per sesso).
func _resolve_initial_max_carry_capacity() -> float:
	var human_rules: HumanRules = null
	if source_group_ref != null and source_group_ref.folk_ref != null:
		human_rules = source_group_ref.folk_ref.human_rules_ref
	if human_rules == null:
		return FALLBACK_MAX_CARRY_CAPACITY
	return HumanCalculator.get_max_carry_capacity(human_rules, HumanTypes.AgeBand.FERTILE_ADULT, sex, equipped_tool_count)


# Liste nomi come semplice testo (un nome per riga), non .tres — pensate per crescere a
# centinaia di voci, molto più comode da editare/versionare come file di testo puro che come
# Array in un Inspector Godot. Nessuna cultura/Folk specifica per ora (il concetto non esiste
# ancora) — un'unica coppia di liste condivisa da tutti.
const MALE_NAMES_PATH := "res://human/data/names/male_names.txt"
const FEMALE_NAMES_PATH := "res://human/data/names/female_names.txt"


# Assegna un nome casuale dalla lista corrispondente a sex — chiamata dal codice che crea
# l'individuo (non automatica in un _init(), stesso principio di prima: il chiamante decide
# quando invocarla). Rilegge il file da disco ad ogni chiamata, deliberatamente senza cache: non
# esiste ancora nessun caso d'uso che la invochi ripetutamente (oggi non è nemmeno collegata a
# nulla) — se in futuro servisse per generare tanti individui in blocco (es. popolare un intero
# villaggio), a quel punto varrà la pena introdurre una cache condivisa, non prima. randi() non
# seeded deliberatamente: a differenza di ResourcePositionService (che deve restare riproducibile
# per i save), la scelta del nome non ha alcun requisito di determinismo.
#
# excluded_names (richiesta utente, 2026-09-02, default vuoto = comportamento invariato di prima):
# nomi da NON pescare — usato da HumanSeedingService per garantire nomi tutti diversi dentro una
# FAMILY. Se l'esclusione svuota il pool (nomi finiti), ripiega sul pool intero invece di lasciare
# l'individuo senza nome: meglio un nome ripetuto per davvero esaurita la lista che nessun nome.
func assign_random_name(excluded_names: Array[String] = []) -> void:
	var path := FEMALE_NAMES_PATH if sex == HumanTypes.Sex.FEMALE else MALE_NAMES_PATH
	var pool := _load_name_pool(path)
	if pool.is_empty():
		return
	var available := pool.filter(func(candidate: String) -> bool: return not excluded_names.has(candidate))
	if available.is_empty():
		available = pool
	name = available[randi() % available.size()]


# Probabilità di ereditarietà del colore capelli (2026-09-04, richiesta utente) — vedi
# assign_hair_color sotto. Discusso esplicitamente con l'utente: nessuna base biologica "corretta"
# da rispettare (l'ereditarietà reale è poligenica/ricombinante, non un sorteggio a percentuale fissa
# tra il fenotipo di un genitore o dell'altro) — 40/40 resta comunque una scelta di game-feel
# ragionevole (80% di somiglianza a un genitore, alta ereditabilità plausibile per questo tratto),
# il restante 20% pesca dal pool intero (vedi sotto) per evitare famiglie clonate all'infinito. Il
# terzo caso ("colore a caso") NON è escluso dai due genitori — può ripescare per coincidenza lo
# stesso colore di uno di loro, esattamente come richiesto ("un colore a caso, quindi compreso
# anche madre e padre").
const HAIR_INHERITANCE_MOTHER_CHANCE: float = 0.4
const HAIR_INHERITANCE_FATHER_CHANCE: float = 0.4


# hair_color GENETICO (2026-09-04, richiesta utente) — a differenza di assign_random_clothing
# sotto (sempre puro random, i vestiti non si ereditano), questo pesca dal colore di un genitore
# con le probabilità sopra SE ENTRAMBI sono passati, altrimenti ripiega sul pool intero come prima
# (caso dei fondatori senza genitori: adulti indipendenti di HumanSeedingService._create_adult, o
# le due metà di una coppia fondatrice in _create_family_couple — nessuno dei due ha genitori
# simulati). Un solo metodo con parametri opzionali invece di due metodi separati
# (genetico/fondatore): stesso principio "un solo posto per la logica", il chiamante non deve
# nemmeno sapere se sta creando un fondatore o un figlio, passa semplicemente quello che ha.
func assign_hair_color(mother: HumanIndividual = null, father: HumanIndividual = null) -> void:
	hair_color = roll_inherited_hair_color(mother, father)


# Versione PURA di assign_hair_color sopra (2026-09-06, richiesta utente) — serve al momento del
# CONCEPIMENTO (HumanConceptionIndividualService), quando il figlio non esiste ancora come
# oggetto: lavora solo sui due genitori e ritorna il valore da salvare per dopo
# (HumanIndividual.pending_child_hair_color), invece di scrivere su un ricevente già istanziato.
# Stessa identica logica/percentuali di assign_hair_color, che ora la richiama internamente (zero
# duplicazione, comportamento esterno invariato per tutti i chiamanti esistenti in
# HumanSeedingService). mother/father senza default: a differenza di assign_hair_color, che deve
# restare chiamabile senza argomenti per i fondatori, qui i chiamanti (solo il concepimento, oggi)
# passano sempre entrambi — ma la funzione gestisce comunque null per sicurezza, visto che
# assign_hair_color sopra le delega ANCHE le proprie chiamate senza argomenti.
static func roll_inherited_hair_color(mother: HumanIndividual, father: HumanIndividual) -> HumanTypes.HairColor:
	if mother == null or father == null:
		var pool := HumanTypes.HairColor.values()
		return pool[randi() % pool.size()]
	var roll := randf()
	if roll < HAIR_INHERITANCE_MOTHER_CHANCE:
		return mother.hair_color
	elif roll < HAIR_INHERITANCE_MOTHER_CHANCE + HAIR_INHERITANCE_FATHER_CHANCE:
		return father.hair_color
	var pool := HumanTypes.HairColor.values()
	return pool[randi() % pool.size()]


# Stessa distribuzione 40/40/20 di HAIR_INHERITANCE_MOTHER_CHANCE/FATHER_CHANCE sopra, costanti
# dedicate (non condivise) così le due potranno essere ritarate indipendentemente in futuro senza
# toccarsi a vicenda — oggi hanno comunque lo stesso valore.
const SKIN_INHERITANCE_MOTHER_CHANCE: float = 0.4
const SKIN_INHERITANCE_FATHER_CHANCE: float = 0.4


# skin_color GENETICO — stessa identica struttura/logica di assign_hair_color sopra (un solo
# metodo con parametri opzionali, pool.values() invece di un conteggio hardcoded), applicata a
# HumanTypes.SkinColor invece che HairColor. Con un solo valore possibile oggi (LIGHT) il
# risultato è sempre lo stesso qualunque ramo venga preso — il meccanismo è comunque corretto e
# pronto per quando SkinColor guadagnerà altri membri.
func assign_skin_color(mother: HumanIndividual = null, father: HumanIndividual = null) -> void:
	skin_color = roll_inherited_skin_color(mother, father)


# Versione PURA di assign_skin_color sopra — stesso identico motivo/schema di
# roll_inherited_hair_color sopra, per HumanTypes.SkinColor invece che HairColor.
static func roll_inherited_skin_color(mother: HumanIndividual, father: HumanIndividual) -> HumanTypes.SkinColor:
	if mother == null or father == null:
		var pool := HumanTypes.SkinColor.values()
		return pool[randi() % pool.size()]
	var roll := randf()
	if roll < SKIN_INHERITANCE_MOTHER_CHANCE:
		return mother.skin_color
	elif roll < SKIN_INHERITANCE_MOTHER_CHANCE + SKIN_INHERITANCE_FATHER_CHANCE:
		return father.skin_color
	var pool := HumanTypes.SkinColor.values()
	return pool[randi() % pool.size()]


# clothing_color resta SEMPRE puro random (i vestiti non sono un tratto genetico) — separato da
# assign_hair_color sopra (richiesta utente, 2026-09-04: distinguere i tratti genetici da quelli
# sempre-casuali, in vista di altri tratti genetici futuri). .values() apposta (non un
# range/conteggio hardcoded), stesso motivo di sempre: si estende da sé se l'enum guadagna voci.
func assign_random_clothing() -> void:
	var clothing_colors := HumanTypes.ClothingColor.values()
	clothing_color = clothing_colors[randi() % clothing_colors.size()]


func _load_name_pool(path: String) -> Array[String]:
	var pool: Array[String] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Impossibile aprire %s per la lista nomi." % path)
		return pool
	for line in file.get_as_text().split("\n"):
		var trimmed := line.strip_edges()
		if trimmed != "":
			pool.append(trimmed)
	return pool


# Assegnazione GENERICA di una Task (2026-09-09, richiesta utente, Step 4 del piano raccolta/
# trasporto) — generalizza quanto set_target sotto faceva SOLO per il caso singolo-step Walk:
# sostituisce current_task e attiva il primo step, stesso comportamento che finora ogni chiamante
# (set_target, il debug hook tasto T in GameScene) replicava a mano con `current_task = Task.new(
# [...]); step.activate(self)`. UNICO punto ora responsabile di questa coppia di operazioni — un
# futuro TaskFactory/assegnazione da click passerà da qui, non da un terzo percorso equivalente.
#
# get_current_action() può tornare null (Task vuota, nessuno step — vedi Task.gd) — a differenza
# del vecchio set_target, che assumeva sempre un WalkAction concreto e non aveva bisogno di questa
# guardia, un chiamante generico può in teoria passare una Task senza step: stesso principio
# difensivo già richiesto da Task.get_current_action() stessa ("il chiamante non deve mai assumere
# un'Action non-null senza aver controllato prima").
func assign_task(task: Task) -> void:
	current_task = task
	var current_action := task.get_current_action()
	if current_action != null:
		current_action.activate(self, task.context)


# Riscritta in termini di assign_task sopra (2026-09-09, richiesta utente — evitare due percorsi
# paralleli che fanno la stessa cosa in modo leggermente diverso). path.clear() resta QUI, non
# dentro assign_task: è specifico del movimento (waypoint di un futuro pathfinding, vedi il campo
# `path` sopra), non ha senso azzerarlo per una Task generica che magari non contiene nemmeno un
# WalkAction (es. una futura Task che inizia con un Rest/Think) — nessuna ragione per spostarlo nel
# metodo generico.
func set_target(target: Vector2) -> void:
	path.clear()
	# Cablaggio Walk/Task (2026-09-06/07, richiesta utente) — un comando di movimento esplicito
	# crea SEMPRE una Task NUOVA a un solo step (mai riusata tra due comandi diversi, anche se la
	# precedente non era ancora conclusa — un nuovo target la sostituisce di netto): coerente col
	# design di WalkAction._last_position, pensata per vivere per la durata di UNA sola camminata.
	assign_task(Task.new([WalkAction.new(target)]))


func stop() -> void:
	is_moving = false
	path.clear()
	# Cablaggio Walk/Task (2026-09-06/07, richiesta utente) — la task associata va ripulita ogni
	# volta che il movimento finisce, sia per arrivo naturale (HumanIndividualActionService.
	# apply_action chiama stop() quando la Task risulta conclusa dopo l'ultimo step, NON più
	# HumanIndividualMovementService.advance_movement — vedi lì per il perché) sia per qualunque
	# futura interruzione che passi da qui (stesso punto unico, mai duplicato altrove).
	current_task = null
