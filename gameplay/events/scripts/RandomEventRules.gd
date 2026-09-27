class_name RandomEventRules
extends Resource

# Dati di sorteggio di un evento casuale (2026-09-26, richiesta utente — sistema di eventi casuali). Un .tres
# per evento in gameplay/events/data/, trovato per scansione da RandomEventService. Solo DATI: gli effetti e il
# testo del popup stanno nello script dell'evento (event_script, una sottoclasse di RandomEvent), perché gli
# eventi sono troppo diversi tra loro per un formato unico.

# Identificatore stabile (chiave negli eventi programmati salvati in GameData.scheduled_random_events).
@export var id: String = ""
# Chiave tr() del nome dell'evento (menu di debug, log).
@export var display_name: String = ""
# Probabilità che l'evento accada nei 365 giorni successivi al sorteggio annuale (0..1). Valore unico, usato
# quando le fasce di popolazione sotto sono vuote.
@export var annual_probability: float = 0.0

# Categoria dell'evento (2026-09-27, richiesta utente — raffreddamento condiviso): id di un RandomEventCategoryRules
# in gameplay/events/data/categories/, es. "visitors". Tutti gli eventi della stessa categoria condividono il
# raffreddamento: dopo uno qualunque di essi, la probabilità di tutti si riduce per qualche anno. La categoria
# decide anche il sorteggio (2026-09-27): al massimo un evento per categoria all'anno, un solo tiro per categoria
# (RandomEventService.roll_year). "" = nessuna: l'evento è tirato singolarmente e non ha raffreddamento.
@export var category: String = ""

@export_group("Probability by population")
# Probabilità annua a FASCE di popolazione (2026-09-27, richiesta utente — generico, riusabile da ogni evento):
# due array paralleli, limiti superiori ESCLUSIVI in ordine crescente e probabilità della fascia. Vale la prima
# fascia con popolazione < limite; oltre l'ultimo limite vale probability_above_last_band. Vuoti = si usa
# annual_probability. Esempio: limiti [10, 20], probabilità [0.2, 0.1] -> 0..9: 20%, 10..19: 10%, 20+: sopra.
# Risolta da get_base_annual_probability; i moltiplicatori (benessere, cultura, attrattiva) si applicano dopo,
# in RandomEventService.get_annual_probability.
@export var population_band_upper_limits: Array[int] = []
@export var population_band_probabilities: Array[float] = []
@export var probability_above_last_band: float = 0.0
# Stagioni in cui l'evento può cadere; vuoto = qualunque stagione.
@export var allowed_seasons: Array[GameTypes.Season] = []
# Comportamento: script che estende RandomEvent (effetti + testo del popup).
@export var event_script: Script

@export_group("Constraints")
# Vincoli di sorteggio (valutati solo dal sorteggio automatico, mai dall'attivazione manuale di debug).
# Anno minimo della partita da cui l'evento può essere sorteggiato (0 = da subito).
@export var min_year: int = 0
# Idea che il villaggio deve aver completato ("" = nessuna).
@export var required_idea_id: String = ""
# Popolazione umana minima (0 = nessun minimo).
@export var min_population: int = 0
# Richiede un edificio completo con BuildingRules.is_village_center (2026-09-27 — es. arrivo di visitatori, che
# camminano fino al centro del villaggio).
@export var requires_village_center: bool = false


# Probabilità annua PRIMA dei moltiplicatori: dalle fasce di popolazione se definite, altrimenti annual_probability.
# Fasce incoerenti (array di lunghezza diversa) -> errore e annual_probability.
func get_base_annual_probability(population: int) -> float:
	if population_band_upper_limits.is_empty():
		return annual_probability
	if population_band_upper_limits.size() != population_band_probabilities.size():
		push_error("RandomEventRules '%s': population_band_upper_limits e population_band_probabilities hanno lunghezze diverse." % id)
		return annual_probability
	for i in range(population_band_upper_limits.size()):
		if population < population_band_upper_limits[i]:
			return population_band_probabilities[i]
	return probability_above_last_band
