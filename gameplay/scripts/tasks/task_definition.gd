class_name TaskDefinition
extends Resource

# "Ricetta" statica/dati per una Task (2026-09-07, richiesta utente, riorganizzazione Action/Task)
# — Resource (non RefCounted) perché va salvata come .tres, in gameplay/scripts/tasks/definitions/
# (vuota per ora — ci vivranno i file .tres delle singole ricette, non ancora scritti in questo
# passo). Task (gameplay/scripts/tasks/Task.gd) resta la sequenza RUNTIME (RefCounted, step già
# istanziati come Action concrete, un indice di avanzamento); TaskDefinition è invece la
# descrizione ASTRATTA e riusabile ("quali step, in che ordine, quale action_type ciascuno", vedi
# TaskStepDefinition) da cui TaskFactory.build_task costruisce una Task runtime concreta, dato un
# Dictionary di contesto (es. {"source": Vector2(40,40), "destination": Vector2(60,60)}).

# Nome identificativo leggibile, solo per debug/log (es. il log del test Task in GameScene) — mai
# letto da alcuna logica di gioco.
@export var task_name: String = ""

# Numero massimo di individui assegnabili contemporaneamente a una Task nata da questa ricetta
# (2026-09-10, richiesta utente — preparazione Build Task, Step 1: SOLO il dato, TaskFactory.
# build_task NON lo legge/copia ancora in questo passo, vedi task_factory.gd — un futuro giro lo
# collegherà, stesso schema con cui task_name viene già copiato oggi su Task.task_name). Vive QUI
# (non solo come default fisso su Task, vedi Task.max_workers) perché è un dato di TIPO di Task —
# "quanti lavoratori ammette questa ricetta", non uno stato di un'istanza runtime — stesso principio
# per cui task_name/step_description vivono su TaskDefinition/TaskStepDefinition e non vengono
# inventati ad ogni Task costruita a mano. Default 1 = comportamento invariato per haul_resource.
# tres/daydreaming.tres (nessuno dei due lo valorizza ancora), coerente col default 1 di Task.
# max_workers.
@export var max_workers: int = 1

# Step astratti, in ordine — untyped Array (non Array[TaskStepDefinition]): stessa scelta
# deliberata già fatta da ResourceGrowthRules.subtypes (Array di SubtypeRules, vedi CLAUDE.md,
# Resource simulation) — un array TIPIZZATO di Resource custom è più fragile da scrivere a mano in
# un .tres (sintassi Array[Tipo] meno indulgente in un file scritto a mano), un array generico no.
@export var steps: Array = []

# Fasce d'età a cui è consentito eseguire una Task nata da questa ricetta (2026-09-13, richiesta
# utente, Play Task CHILD-only) — vincolo di TASK, indipendente dai disallowed_age_bands per-Action
# (vedi Action.disallowed_age_bands): serve a esprimere un vincolo che non appartiene a nessuna
# Action generica (es. RunAction/JumpAction restano utilizzabili a qualunque età) ma solo alla
# RICETTA specifica. Array[int] (i valori ordinali di HumanTypes.AgeBand), non Array[HumanTypes.
# AgeBand]: STESSO principio già dichiarato sopra per `steps` — qui il tipo "custom" è un enum, non
# una classe Resource, ma nessun precedente esiste nel progetto per la sintassi di un array tipizzato
# su un enum custom scritto a mano in un .tres (verificato), quindi Array[int] resta la scelta
# inequivocabile, stesso trattamento riservato ovunque nel progetto agli array "per fascia d'età"
# (es. HumanRules.size_multiplier_by_age), sebbene qui il significato sia una LISTA di membri
# ammessi, non un array indicizzato posizionalmente. Copiato su Task.allowed_age_bands da
# TaskFactory.build_task (stesso schema con cui task_name/step_descriptions sono già copiati oggi),
# stesso principio "dato di TIPO di Task" già dichiarato sopra per max_workers. Vuoto di default =
# nessun vincolo (comportamento invariato per ogni TaskDefinition esistente — nessuna la valorizza
# oggi tranne play.tres). Vedi Task.allowed_age_bands/HumanIndividual.assign_task per i consumatori.
@export var allowed_age_bands: Array[int] = []

# Priorità di interrupt (2026-09-13, richiesta utente, in preparazione al sistema di interrupt da
# stamina critica — SOLO la struttura dati in questo passo) — numero più BASSO = più urgente. -1
# (default) = "non è una Task-bisogno, la priorità non si applica a lei", invariato per ogni
# TaskDefinition esistente tranne emergency_rest.tres (1, massima urgenza) e rest.tres (2, urgenza
# minore) — vedi quei due file. Copiato su Task.interrupt_priority da TaskFactory.build_task,
# stesso schema di allowed_age_bands sopra.
@export var interrupt_priority: int = -1

# Sospendibilità (2026-09-13, richiesta utente, stesso contesto di interrupt_priority sopra) — vero
# SOLO per le Task di lavoro che un interrupt può mettere in pausa e riprendere più tardi. false
# (default) per ogni TaskDefinition esistente tranne haul_resource.tres/transport.tres (true) —
# vedi quei due file. build.tres resterà false anche in questo passo (diventerà sospendibile in un
# giro futuro dedicato, non qui). Copiato su Task.is_suspendable da TaskFactory.build_task, stesso
# schema di interrupt_priority sopra.
@export var is_suspendable: bool = false
