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
var move_speed: float = 4.5 # microcelle/secondo — in linea con AnimalRules.hop_speed (boar/mouflon)
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
