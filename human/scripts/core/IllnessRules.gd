class_name IllnessRules
extends Resource

# Una malattia (2026-10-24, richiesta utente — evento malattia): dati in human/data/illnesses/{id}.tres, letti da
# IllnessService. Chi ce l'ha è malato (HumanIndividual.is_sick) finché dura, qualunque sia la salute.

@export var id: String = ""
# Chiave di traduzione del nome (pannello dell'individuo, popup dell'evento).
@export var display_name: String = ""
# Salute persa ogni giorno finché dura (a 0 si muore di malattia, GameTimeService._apply_daily_illness_deaths).
@export var daily_health_loss: float = 0.0
# Durata in giorni, estratta all'inizio tra min e max (compresi). Il giocatore non la vede.
@export var min_duration_days: int = 1
@export var max_duration_days: int = 1
# Malattie gravi (per il futuro, con i rimedi): finita la durata guarisce solo con la salute almeno a questo valore,
# altrimenti continua. 0 = guarisce sempre a fine durata.
@export var recovery_health_threshold: float = 0.0
# Contagio (per il futuro): nessun sistema lo legge ancora.
@export var contagion_probability: float = 0.0
