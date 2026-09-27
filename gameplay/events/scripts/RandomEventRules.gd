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
# Probabilità che l'evento accada nei 365 giorni successivi al sorteggio annuale (0..1).
@export var annual_probability: float = 0.0
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
