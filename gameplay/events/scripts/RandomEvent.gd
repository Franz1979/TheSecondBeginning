class_name RandomEvent
extends RefCounted

# Comportamento di un evento casuale (2026-09-26, richiesta utente — sistema di eventi casuali). Ogni evento ha
# una propria sottoclasse in gameplay/events/scripts/events/, collegata dal suo .tres (RandomEventRules.
# event_script). Istanza nuova per ogni applicazione (RandomEventService.apply_event): niente stato tra un
# evento e l'altro.
#
# apply() applica gli effetti sul mondo; get_popup_text() restituisce il testo (già tradotto) del popup non di
# allarme mostrato dopo l'applicazione — "" = nessun popup. Entrambi ricevono lo stesso RandomEventContext.


func apply(context: RandomEventContext) -> void:
	pass


func get_popup_text(context: RandomEventContext) -> String:
	return ""
