class_name HumanIndividualController
extends RefCounted

# Input handling di MOVIMENTO per il bersaglio corrente (GameScene.individual — non più fisso sul
# leader/human_individuals[0], vedi Step 2 del piano movimento indipendente, 2026-09-02) — stesso
# pattern di CellSelectorController (RefCounted, converte mouse->coordinate tramite CELL_SIZE,
# GameScene resta il chiamante che lo istanzia e gli inoltra gli eventi da _unhandled_input). Click
# destro (solo con l'individuo agganciato selezionato) imposta il target di movimento — SOLO
# movimento: la selezione (click sinistro, su un individuo QUALSIASI) vive in
# HumanIndividualSelectorController. Separare i due concern evita di dover istanziare un controller
# per individuo: UN SOLO controller esiste in GameScene, ri-agganciato (setup()) all'individuo
# selezionato ogni volta che cambia (vedi GameScene._set_movement_target) — mai più di un individuo
# in movimento contemporaneamente in questo step (scope concordato, 2026-09-02).

const CELL_SIZE: int = 10 # stesso fattore pixel/microcella di MicroCellRenderer/HumanIndividualView

# Soglia d'immobilità (anni) — richiesta utente, 2026-09-04: un individuo con età < 1 anno non può
# ricevere un ordine di movimento. Eccezione booleana indipendente da HumanTypes.AgeBand (NON una
# fascia a sé, vedi HumanTypes.gd) — un semplice confronto contro birth_year_virtual/game_data.year,
# stesso identico calcolo di "età" già usato altrove (es. GameScene._select_individual), solo qui
# ripetuto invece di richiamare un getter perché HumanIndividual non ne espone uno (l'età non è mai
# un campo salvato, sempre ricalcolata al volo — vedi HumanIndividual.birth_year_virtual).
const MIN_MOVEMENT_AGE_YEARS: float = 1.0

var individual: HumanIndividual
var reference_node: Node2D # nodo il cui spazio locale coincide con la griglia microcella (renderer)
# Serve solo a leggere .year per il controllo d'età sopra — GameScene resta l'unico proprietario,
# questo controller non lo modifica mai (stesso trattamento di reference_node: riferimento esterno
# passato da setup(), mai istanziato qui).
var game_data: GameData


func setup(p_individual: HumanIndividual, p_reference_node: Node2D, p_game_data: GameData) -> void:
	individual = p_individual
	reference_node = p_reference_node
	game_data = p_game_data


func handle_input(event: InputEvent) -> void:
	if individual == null or reference_node == null:
		return
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT:
		return

	var mouse_pos_microcells: Vector2 = reference_node.get_local_mouse_position() / CELL_SIZE
	_try_set_target(mouse_pos_microcells)


# CROSS_BORDER_MARGIN: margine minimo oltre il bordo [0, WIDTH)/[0, HEIGHT) entro cui è ancora
# possibile impostare un target — senza questo margine, il clamp coinciderebbe esattamente col
# bordo e individual.position non potrebbe mai raggiungere <0 o >=WIDTH/HEIGHT (il target verrebbe
# sempre raggiunto prima di uscire dalla griglia, impedendo per costruzione l'attraversamento). Un
# margine minimo basta: il controllo di attraversamento gira ogni frame in GameScene._process,
# quindi scatta a metà tragitto molto prima che il target clampato oltre il bordo venga davvero
# raggiunto. Il vero bordo di gioco resta sempre 0/WIDTH (GameScene._check_macro_cell_border_
# crossing) — la cella vicina, ora, è già resa per intero PRIMA che il player la raggiunga (vedi
# GameScene.live_cells/attivazione per prossimità), quindi non serve più rallentare
# l'attraversamento con una soglia di commit estesa.
const CROSS_BORDER_MARGIN: float = 1.0


# Reietta silenziosamente un click-to-move su un individuo troppo giovane (< MIN_MOVEMENT_AGE_
# YEARS) — stesso identico pattern del controllo is_selected subito sopra (return silenzioso,
# nessun log/segnale: qui il comando semplicemente non è disponibile, non è un errore da segnalare
# all'utente). NON TESTATO end-to-end (nota utente, 2026-09-04): oggi nessun individuo in gioco ha
# età < 1 anno (il seeding parte sempre da fasce più vecchie, vedi HumanSeedingService), quindi
# questo ramo non è mai stato effettivamente esercitato — nessun modo di forzare l'età di un
# individuo esiste ancora (né in game né da debug bar). Verificare quando arriverà un modo di
# generare/osservare un neonato (es. un vero HumanBirthService).
func _try_set_target(mouse_pos_microcells: Vector2) -> void:
	if not individual.is_selected:
		return
	var age: float = float(game_data.year - individual.birth_year_virtual)
	if age < MIN_MOVEMENT_AGE_YEARS:
		return
	individual.set_target(Vector2(
		clamp(mouse_pos_microcells.x, -CROSS_BORDER_MARGIN, float(World.WIDTH) + CROSS_BORDER_MARGIN),
		clamp(mouse_pos_microcells.y, -CROSS_BORDER_MARGIN, float(World.HEIGHT) + CROSS_BORDER_MARGIN)
	))
