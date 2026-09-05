class_name SettingsTypes

# Single source di verità per gli enum legati alle opzioni utente (non alla singola partita) —
# stesso ruolo di GameTypes.gd/HumanTypes.gd/NotificationTypes.gd per i rispettivi domini, ma per
# preferenze che riguardano l'INSTALLAZIONE/UTILIZZATORE, non una partita specifica (vedi
# discussione con l'utente, 2026-09-05: language è per costruzione un'opzione utente, non di
# GameData — persistita separatamente dal save di gioco, non ancora implementato).
#
# Solo le lingue più diffuse per ora (richiesta utente) — nessuna copertura esaustiva, se ne
# aggiungono altre quando servirà davvero, stesso principio "non anticipare case ipotetici" già
# seguito per NotificationTypes.
#
# NONE = nessuna lingua forzata: si usa il comportamento tr() di default (locale di sistema, con
# eventuale fallback di progetto — vedi project.godot internationalization/locale/fallback) invece
# di imporre esplicitamente una lingua. È il valore che rappresenta lo stato ATTUALE del progetto
# (prima che una vera scelta lingua in Options esista).
enum Language {
	NONE,
	ITALIAN,
	ENGLISH,
	GERMAN,
	FRENCH,
	SPANISH,
}
