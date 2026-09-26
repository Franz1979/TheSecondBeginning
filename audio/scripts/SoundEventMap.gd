class_name SoundEventMap
extends RefCounted

# Tabella evento di gioco -> id sonoro (2026-09-26, richiesta utente — banchi sonori). È l'UNICO posto da
# modificare per dare un suono a un evento: il codice di gioco chiama AudioManager.play_event(evento) con
# una delle chiavi qui sotto e non conosce mai gli id dei file. Gli id devono esistere in un banco
# (audio/banks/*.tres); un id assente produce un solo push_warning da AudioManager, nessun crash.
#
# Per aggiungere un evento: una riga qui (evento -> id), e la chiamata AudioManager.play_event nel punto
# del codice in cui l'evento avviene.

const EVENTS: Dictionary = {
	# Interfaccia
	&"ui_click": &"ui_click",
	&"ui_selection": &"ui_select",
	# Mondo
	&"idea_completed": &"idea_spark",
}


# Id sonoro dell'evento, &"" se l'evento non è in tabella.
static func get_sound_id(event: StringName) -> StringName:
	return EVENTS.get(event, &"")
