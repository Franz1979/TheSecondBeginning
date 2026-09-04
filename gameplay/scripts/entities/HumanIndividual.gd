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
var move_speed: float = 1.2
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
# Sentinella -1 = genitore/partner sconosciuto o non applicabile (es. un fondatore senza
# genitori nella partita, o nessun partner ancora assegnato) — stesso principio del sentinella -1
# già usato altrove nel progetto (es. PopulationGroup.years_since_last_split,
# Building.construction_started_day) per "non ancora valorizzato/non applicabile".
var mother_id: int = -1
var father_id: int = -1
# Nessuna logica di formazione coppie qui: solo il campo, valorizzato da un futuro service.
var partner_id: int = -1
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
	if mother == null or father == null:
		var pool := HumanTypes.HairColor.values()
		hair_color = pool[randi() % pool.size()]
		return
	var roll := randf()
	if roll < HAIR_INHERITANCE_MOTHER_CHANCE:
		hair_color = mother.hair_color
	elif roll < HAIR_INHERITANCE_MOTHER_CHANCE + HAIR_INHERITANCE_FATHER_CHANCE:
		hair_color = father.hair_color
	else:
		var pool := HumanTypes.HairColor.values()
		hair_color = pool[randi() % pool.size()]


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


func set_target(target: Vector2) -> void:
	target_position = target
	is_moving = true
	path.clear()


func stop() -> void:
	is_moving = false
	path.clear()
