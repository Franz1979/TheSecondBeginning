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
	# Riga nuova nella campanella "In sospeso" (2026-10-08, GameScene.pending_entry_added).
	&"pending_entry_added": &"bell",
	# Mondo
	# Thoughts (2026-10-08): file nuovo thought.wav al posto di idea_spark.wav, che non c'è più.
	&"idea_completed": &"thought",
	# Richiamo del coordinatore (2026-10-09, GameScene.coordinator_called): "hey" alla sua posizione.
	&"coordinator_call": &"hey",
	# Talk (2026-10-13, GameScene.talk_sound_requested): chi chiama, chi risponde, poi uno a testa a inizio conversazione.
	&"talk_call": &"hey_2",
	&"talk_answer": &"yeah",
	&"talk_caller": &"talk_1",
	&"talk_partner": &"talk_2",
	# Inizio di un rito sociale (2026-10-14, SocialRiteRules.start_sound_id): evento "social_rite_started:<id>".
	&"social_rite_started:paleolithic_banquet": &"paleolithic_banquet",
	# Lezione al Ceppo dell'insegnamento (2026-10-16).
	&"social_rite_started:oral_lesson": &"lesson",
	# Veglia delle stelle (2026-10-29): coro all'inizio, richiamo della guida alla chiamata (StarVigilService).
	&"social_rite_started:star_vigil": &"chorus_for_stars_fest",
	&"star_vigil_call": &"call_for_stars_fest",
	# Suono predefinito dei riti completati (2026-10-04, richiesta utente — prima church_bell, che resta nel banco per
	# usi futuri): quello di una ricetta con RiteRules.completion_sound_id vuoto.
	&"rite_completed": &"rite_paleolithic",
	# Suoni di rito scelti dalla ricetta (RiteRules.completion_sound_id, 2026-10-04): evento "rite_completed:<id>".
	&"rite_completed:funeral_paleolithic": &"funeral_paleolithic",
}


# Id sonoro dell'evento, &"" se l'evento non è in tabella.
static func get_sound_id(event: StringName) -> StringName:
	return EVENTS.get(event, &"")
