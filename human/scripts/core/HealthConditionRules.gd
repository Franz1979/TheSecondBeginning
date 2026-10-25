class_name HealthConditionRules
extends Resource

# Condizione di salute (2026-10-25, richiesta utente — malattie e ferite nello stesso modello): tutto ciò che toglie
# salute a un pipottino. Una classe unica con `category` e gruppi di campi, stesso schema di SecondaryResourceRules: i
# campi che non servono a un tipo restano a 0. Dati in human/data/health_conditions/{illnesses,wounds}/{id}.tres (la
# cartella deve corrispondere a `category`, controllato da DataFileIndex), letti da HealthConditionService. I rimedi
# (futuri) guarderanno `category`: unguenti per le ferite, medicinali per le malattie.
#
# Due fasi (2026-10-25, richiesta utente): la fase ACUTA dura i giorni estratti tra min e max; alla fine, con la salute
# almeno a recovery_health_ratio × salute massima si guarisce, altrimenti si passa in CONVALESCENZA, che non ha durata:
# finisce quando la salute torna sopra la soglia (guarito) o con la morte. Ogni fase ha le sue perdite giornaliere e il
# suo "a letto"; una perdita di salute in convalescenza maggiore di quanto la salute risale da sola vuol dire che senza
# rimedi si muore.

enum Category { ILLNESS, WOUND }
enum Severity { LIGHT, SEVERE }

@export var id: String = ""
# Chiave di traduzione del nome (pannello dell'individuo, popup dell'evento, statistiche).
@export var display_name: String = ""
@export var category: Category = Category.ILLNESS
# Per ora solo informativa (le ferite leggere con i soli lavori leggeri arriveranno con gli effetti).
@export var severity: Severity = Severity.LIGHT
# Fasce d'età che possono prenderla (HumanTypes.AgeBand); vuota = tutte. Controllata da HealthConditionService.can_get.
@export var age_bands: Array[HumanTypes.AgeBand] = []
# Salute tolta subito, quando la condizione arriva (ferite, avvelenamenti).
@export var immediate_health_loss: float = 0.0

@export_group("Acute phase")
# Durata in giorni della fase acuta, estratta all'inizio tra min e max (compresi). Il giocatore non la vede.
@export var min_duration_days: int = 1
@export var max_duration_days: int = 1
# Perdite di ogni giorno della fase acuta (salute a 0 = morte, GameTimeService._apply_daily_illness_deaths).
@export var daily_health_loss: float = 0.0
@export var daily_happiness_loss: float = 0.0
# A letto (HumanIndividual.is_sick) durante la fase acuta: solo bisogni e riposo.
@export var bed_rest: bool = true

@export_group("Recovery")
# Soglia di guarigione in frazione della salute massima (0-1): a fine fase acuta e poi ogni giorno di convalescenza, con
# la salute almeno a questa quota si guarisce. 0 = guarisce sempre a fine fase acuta.
@export var recovery_health_ratio: float = 0.0

@export_group("Convalescence")
# Perdite di ogni giorno di convalescenza (0 = non peggiora).
@export var convalescence_daily_health_loss: float = 0.0
@export var convalescence_daily_happiness_loss: float = 0.0
# A letto anche in convalescenza. La regola generale "salute sotto HumanRules.sick_health_threshold = a letto" vale
# comunque.
@export var convalescence_bed_rest: bool = false

@export_group("Contagion")
# Contagio (per il futuro): nessun sistema lo legge ancora.
@export var contagion_probability: float = 0.0

@export_group("Infection")
# Infezione di una ferita (per il futuro): probabilità al giorno di prendere la condizione `infection_condition_id`.
# Nessun sistema le legge ancora.
@export var infection_probability_per_day: float = 0.0
@export var infection_condition_id: String = ""
