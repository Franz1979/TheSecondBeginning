class_name TaskStepDefinition
extends Resource

# Uno step ASTRATTO di una TaskDefinition (2026-09-07, richiesta utente, riorganizzazione Action/
# Task) — descrive COSA fare (action_type) e DOVE prendere gli argomenti del costruttore
# (context_keys), non ancora un'Action concreta: TaskFactory.build_task (vedi task_factory.gd)
# risolve context_keys contro il Dictionary di contesto concreto passato a runtime e istanzia
# l'Action giusta secondo action_type. Resource (non RefCounted) perché va salvato come
# sotto-risorsa dentro un TaskDefinition.tres (vedi task_definition.gd) — stesso principio/stessa
# scelta già fatta per SubtypeRules (vedi CLAUDE.md, Resource simulation): una classe Resource
# generica, riusabile, pensata per essere scritta a mano in un .tres.

@export var action_type: TaskTypes.ActionType = TaskTypes.ActionType.WALK

# Chiavi ORDINATE nel Dictionary di contesto runtime di una Task (Task.context, es.
# ["target_position"] per WALK/THINK — un solo argomento scalare — o ["pickup_position",
# "macro_state", "resource_name"] per PICKUP) — sostituisce l'ex campo singolare `context_key:
# String` (2026-09-10, richiesta utente, estensione TaskFactory per haul_resource/PICKUP): un solo
# scalare bastava finché TaskFactory supportava solo WALK/REST, ma PICKUP richiede 3 argomenti
# eterogenei (target_position: Vector2i, macro_state: MacroCellState, resource_name: String)
# nell'ordine atteso dal costruttore di PickUpAction — TaskFactory.build_task legge
# context_keys[i] in quest'ordine per ciascun ActionType (vedi task_factory.gd per la mappa
# esatta indice->argomento per tipo). Stringhe libere, non un enum chiuso — stesso motivo per cui
# Task.context stesso è un Dictionary libero (nessuna lista fissa di chiavi imposta qui). Nessun
# consumatore reale scriveva ancora l'ex context_key (nessuna TaskDefinition.tres esisteva prima
# di questo passo), quindi nessuna migrazione di dati è stata necessaria — solo il nome/tipo del
# campo cambia. REST non ne richiede nessuna (RestAction non ha un target, vedi RestAction.gd):
# resta un array vuoto per quello step. ATTENZIONE al TIPO concreto dietro ogni chiave: WALK vuole
# un Vector2 (WalkAction._init), PICKUP vuole un Vector2i per la posizione (PickUpAction._init) —
# TaskFactory passa context[chiave] così com'è, senza conversioni implicite, quindi una stessa
# posizione logica letta da due step diversi con tipi diversi richiede DUE chiavi di contesto
# distinte (vedi GameScene._assign_pickup_task: "target_position"/Vector2 per WALK, "pickup_
# position"/Vector2i per PICKUP), mai la stessa chiave riusata con un solo valore.
@export var context_keys: Array[String] = []

# Descrizione di QUESTO step per l'info panel individuo (2026-09-07, richiesta utente) — chiave
# tr(), stesso principio di BuildingRules.building_name/Idea.display_name (mai testo già tradotto
# qui, ogni consumatore avvolge in tr() al momento di mostrarla — vedi Task.get_activity_
# description). Vive QUI (per singolo step), non su Action, perché lo stesso ActionType (es. WALK)
# significa cose diverse a seconda della Task e di QUALE step è: "vagando nei dintorni" per il
# primo Walk di Daydream, "tornando al centro del villaggio" per il secondo — l'Action stessa
# (WalkAction) non lo sa e non deve saperlo. "" = nessuna descrizione specifica per questo step,
# get_activity_description ripiega sul nome grezzo della classe Action.
@export var step_description: String = ""
