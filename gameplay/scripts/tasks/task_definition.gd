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
