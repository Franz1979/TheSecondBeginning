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

# Step astratti, in ordine — untyped Array (non Array[TaskStepDefinition]): stessa scelta
# deliberata già fatta da ResourceGrowthRules.subtypes (Array di SubtypeRules, vedi CLAUDE.md,
# Resource simulation) — un array TIPIZZATO di Resource custom è più fragile da scrivere a mano in
# un .tres (sintassi Array[Tipo] meno indulgente in un file scritto a mano), un array generico no.
@export var steps: Array = []
