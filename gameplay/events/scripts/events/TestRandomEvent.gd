class_name TestRandomEvent
extends RandomEvent

# Evento di prova (2026-09-26, richiesta utente — collaudo del sistema di eventi casuali e del menu di debug):
# nessun effetto sul mondo, solo il popup.


func get_popup_text(context: RandomEventContext) -> String:
	return tr("random_event_test_popup").format({"day": context.game_data.current_day if context.game_data != null else 0})
