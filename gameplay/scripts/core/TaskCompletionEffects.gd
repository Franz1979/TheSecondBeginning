class_name TaskCompletionEffects
extends Resource

# Effetti del COMPLETAMENTO di una Task su skill e parametri vitali (2026-09-19, richiesta utente):
# un unico file dati (res://gameplay/data/task_completion/task_completion_effects.tres) invece di
# costanti nel codice. Letto da TaskCompletionEffectService, che li applica UNA SOLA VOLTA quando
# l'INTERA Task termina con successo (mai per singola Action/step, mai se interrotta).
#
# Entrambi i Dictionary sono indicizzati per task.task_name (la stessa stringa di
# TaskDefinition.task_name, es. "task_wander_name"):
#
# skill_effects_by_task_name: task_name -> {nome property skill_* su HumanIndividual: incremento}.
#   Es. {"task_build_name": {"skill_builder": 1.0}}. Piu' skill per task sono ammesse. Nessun tetto:
#   le skill non hanno ancora un massimo enforced.
#
# vital_effects_by_task_name: task_name -> {nome property current_* su HumanIndividual: delta}.
#   Es. {"task_wander_name": {"current_happiness": 5.0}}. Un delta positivo non supera il max_*
#   corrispondente (ne' abbassa un valore gia' sopra il max); il risultato non scende mai sotto 0.
#
# Un task_name con Dictionary vuoto {} = "nessun effetto, apposta"; un task_name assente = nessun
# effetto, ma il caso e' distinguibile (task non ancora considerato). Al primo uso il servizio segnala
# con push_warning ogni chiave che non corrisponde a nessuna TaskDefinition (refusi).
@export var skill_effects_by_task_name: Dictionary = {}
@export var vital_effects_by_task_name: Dictionary = {}
