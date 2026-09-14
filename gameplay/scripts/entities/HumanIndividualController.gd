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

# min_movement_age_years() RIMOSSA (2026-09-12, richiesta utente — collegamento di HumanTypes.
# AgeBand.INFANT al gameplay): l'eccezione booleana numerica basata su era_rules.min_birth_spacing_
# years è sostituita da un vero age_band (age_band == HumanTypes.AgeBand.INFANT, vedi _try_set_
# target sotto), coerente con l'introduzione della fascia INFANT come fascia a pieno titolo
# (HumanTypes.gd). Nessun altro punto del progetto la referenziava (verificato — solo _try_set_
# target qui e GameScene._sync_dependent_child_position, entrambi aggiornati in questo stesso
# passo), quindi rimossa per intero invece di lasciata come funzione morta.

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


# Reietta silenziosamente un click-to-move su un individuo INFANT — stesso identico pattern del
# controllo is_selected subito sopra (return silenzioso, nessun log/segnale: qui il comando
# semplicemente non è disponibile, non è un errore da segnalare all'utente). Esercitato per la
# prima volta col piano "trasporto neonati" (2026-09-06, vedi HumanBirthIndividualService) — prima
# nessun individuo in gioco aveva mai età sotto soglia.
#
# age_band == INFANT (2026-09-12, richiesta utente — collegamento di HumanTypes.AgeBand.INFANT al
# gameplay) SOSTITUISCE il precedente confronto numerico "age < min_movement_age_years()" (funzione
# rimossa, vedi sopra) — stessa identica formula già in uso ovunque nel progetto per risolvere
# l'age_band corrente di un individuo (HumanCalculator.get_age_band + game_data.era_effective_
# age_band_durations_male/female, mai le durate BASE di HumanRules). Risolto QUI, non delegato a
# GameScene: questo controller ha già game_data (vedi sopra), nessuna nuova dipendenza necessaria.
# Anche PASSATO a individual.set_target sotto (ora obbligatorio, vedi HumanIndividual.assign_task)
# così il guard generico "questo individuo può eseguire questa Task?" lo riverifica una seconda
# volta a valle — nessuna contraddizione: qui il rifiuto è silenzioso e mirato (niente Task
# costruita affatto), il guard generico è il backstop per ogni ALTRO percorso di assegnazione che
# non ha un proprio controllo dedicato come questo.
func _try_set_target(mouse_pos_microcells: Vector2) -> void:
	if not individual.is_selected:
		return
	var age := float(game_data.year - individual.birth_year_virtual)
	var age_band := HumanCalculator.get_age_band(
		game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female,
		individual.sex, age
	)
	if age_band == HumanTypes.AgeBand.INFANT:
		return
	individual.set_target(Vector2(
		clamp(mouse_pos_microcells.x, -CROSS_BORDER_MARGIN, float(World.WIDTH) + CROSS_BORDER_MARGIN),
		clamp(mouse_pos_microcells.y, -CROSS_BORDER_MARGIN, float(World.HEIGHT) + CROSS_BORDER_MARGIN)
	), age_band)
