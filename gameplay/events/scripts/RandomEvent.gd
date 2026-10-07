class_name RandomEvent
extends RefCounted

# Comportamento di un evento casuale (2026-09-26, richiesta utente — sistema di eventi casuali). Ogni evento ha
# una propria sottoclasse in gameplay/events/scripts/events/, collegata dal suo .tres (RandomEventRules.
# event_script). Istanza nuova per ogni applicazione (RandomEventService.apply_event): niente stato tra un
# evento e l'altro.
#
# apply() applica gli effetti sul mondo e dice se è riuscito; get_popup_text() restituisce il testo (già tradotto) del popup non di
# allarme mostrato dopo l'applicazione — "" = nessun popup. Entrambi ricevono lo stesso RandomEventContext.


# Ritorna true se l'evento è andato a buon fine (2026-09-27, richiesta utente): solo allora il raffreddamento della
# sua categoria riparte (RandomEventService.apply_event). Un evento che può fallire (es. un arrivo di visitatori
# senza centro del villaggio) ritorna false quando non produce nulla.
func apply(context: RandomEventContext) -> bool:
	return true


func get_popup_text(context: RandomEventContext) -> String:
	return ""


# Moltiplicatore della probabilità annua PROPRIO dell'evento (2026-09-27), applicato dal sorteggio
# (RandomEventService.get_probability_breakdown) insieme a quelli generali del villaggio. Per condizioni che
# dipendono dall'evento stesso (es. posti liberi per la dimensione del gruppo in arrivo). 1.0 = nessun effetto.
func get_probability_multiplier(context: RandomEventContext) -> float:
	return 1.0


# Parametri da salvare nell'appuntamento se l'evento viene estratto (2026-10-07): chiesti dal sorteggio alla STESSA
# istanza subito dopo get_probability_multiplier, scritti in GameData.scheduled_random_events (salvati con la
# partita) e restituiti all'arrivo in RandomEventContext.params. Solo tipi JSON-nativi. {} = nessun parametro.
func get_schedule_params() -> Dictionary:
	return {}
