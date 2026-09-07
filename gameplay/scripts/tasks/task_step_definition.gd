class_name TaskStepDefinition
extends Resource

# Uno step ASTRATTO di una TaskDefinition (2026-09-07, richiesta utente, riorganizzazione Action/
# Task) — descrive COSA fare (action_type) e DOVE prendere il target (context_key), non ancora
# un'Action concreta: TaskFactory.build_task (vedi task_factory.gd) risolve context_key contro il
# Dictionary di contesto concreto passato a runtime e istanzia l'Action giusta secondo
# action_type. Resource (non RefCounted) perché va salvato come sotto-risorsa dentro un
# TaskDefinition.tres (vedi task_definition.gd) — stesso principio/stessa scelta già fatta per
# SubtypeRules (vedi CLAUDE.md, Resource simulation): una classe Resource generica, riusabile,
# pensata per essere scritta a mano in un .tres.

@export var action_type: TaskTypes.ActionType = TaskTypes.ActionType.WALK

# Chiave libera nel Dictionary di contesto runtime di una Task (Task.context, es. "source"/
# "destination") — stringa libera, non un enum chiuso: stesso motivo per cui Task.context stesso è
# un Dictionary libero (nessun consumatore reale ancora, nessuna lista fissa di chiavi da imporre
# qui prima del tempo).
@export var context_key: String = ""

# Descrizione di QUESTO step per l'info panel individuo (2026-09-07, richiesta utente) — chiave
# tr(), stesso principio di BuildingRules.building_name/Idea.display_name (mai testo già tradotto
# qui, ogni consumatore avvolge in tr() al momento di mostrarla — vedi Task.get_activity_
# description). Vive QUI (per singolo step), non su Action, perché lo stesso ActionType (es. WALK)
# significa cose diverse a seconda della Task e di QUALE step è: "vagando nei dintorni" per il
# primo Walk di Daydream, "tornando al centro del villaggio" per il secondo — l'Action stessa
# (WalkAction) non lo sa e non deve saperlo. "" = nessuna descrizione specifica per questo step,
# get_activity_description ripiega sul nome grezzo della classe Action.
@export var step_description: String = ""
