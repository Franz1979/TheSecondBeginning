extends Node

# Opzioni PERSISTENTI TRA PARTITE DIVERSE (richiesta utente, 2026-09-05) — deliberatamente
# separato sia da GameData (per-partita, dentro il save JSON: sopravvive a save/load ma è legato a
# QUELLA partita) sia da GameSettings (di sola sessione, mai scritto su disco: sparisce alla
# chiusura del gioco). Queste sono preferenze dell'UTILIZZATORE/installazione — valgono per
# qualunque partita si apra, non vanno riselezionate per ogni save (stesso principio già seguito
# per lingua/notifiche in altri progetti: un giocatore che disattiva i popup li vuole disattivati
# sempre, non solo in un save specifico).
#
# Persistito in user://options.cfg tramite ConfigFile — lo strumento nativo di Godot per poche
# impostazioni chiave-valore persistenti tra riavvii, pensato esattamente per questo caso d'uso
# (risoluzione schermo, keybinding, lingua, ecc.) — non serve la macchina di save/load completa
# già usata per le partite (GameSaveService/GameLoadService restano intatti, mai toccati da qui).
#
# Nessun menu Options reale ancora — solo il dato e la persistenza, pronti per quando arriverà una
# UI vera per cambiarli (save_to_disk() già pubblico per quel momento).

const OPTIONS_FILE_PATH := "user://options.cfg"
const SECTION := "options"
const IT_TRANSLATION_PATH := "res://translations/strings.it.translation"

var show_notification_popups: bool = true
# SettingsTypes.Language — NONE (default, richiesta utente 2026-09-05: NON forzare ITALIAN come
# default di questo campo) = nessuna lingua forzata, si usa il comportamento tr() di default
# (locale di sistema + fallback di progetto, vedi project.godot). Che oggi questo mostri comunque
# l'italiano è un effetto del fallback di progetto (locale/fallback="it", unica traduzione reale
# presente), non di questo campo — resta NONE finché l'utente non sceglie esplicitamente una
# lingua dal menu Opzioni. Nessuna logica di cambio lingua reale collegata a questo campo ancora
# (arriverà con l'Options vera).
var language: SettingsTypes.Language = SettingsTypes.Language.NONE


func _ready() -> void:
	load_from_disk()
	apply_language()


# Se il file non esiste ancora (primissimo avvio su questa installazione) restano i default
# dichiarati sopra, MA li scriviamo subito su disco (richiesta utente, 2026-09-05: un file
# concreto da poter ispezionare fin da subito in user://, invece di aspettare che l'utente apra
# un pannello Options non ancora costruito).
func load_from_disk() -> void:
	var config := ConfigFile.new()
	if config.load(OPTIONS_FILE_PATH) != OK:
		save_to_disk()
		return
	show_notification_popups = bool(config.get_value(SECTION, "show_notification_popups", true))
	language = int(config.get_value(SECTION, "language", SettingsTypes.Language.NONE)) as SettingsTypes.Language


# Pubblico per un futuro menu Options — nessun chiamante reale ancora (i campi sopra si cambiano
# solo da codice/debug per ora).
func save_to_disk() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "show_notification_popups", show_notification_popups)
	config.set_value(SECTION, "language", language)
	config.save(OPTIONS_FILE_PATH)


# TEMPORANEO/DEBUG (richiesta utente, 2026-09-05, esplicitamente da rimuovere a fine debug): con
# NONE, svuota tutte le traduzioni caricate (TranslationServer.clear()) così tr() ritorna la CHIAVE
# grezza invece del testo italiano — un modo visivo per distinguere "nessuna lingua scelta" da
# "italiano applicato", visto che oggi coincidono per via del fallback di progetto
# (locale/fallback="it", vedi project.godot). Con qualunque altra lingua (solo ITALIAN ha davvero
# contenuto oggi — ENGLISH/GERMAN/FRENCH/SPANISH restano segnaposto, vedi SettingsTypes.gd),
# ricarica la traduzione IT. NON è il futuro sistema di cambio lingua reale (quello dovrà caricare
# un file per lingua, non solo IT) — solo un aiuto di debug per verificare il flusso NONE, va
# ripulito quando arriverà una vera gestione multi-lingua.
func apply_language() -> void:
	TranslationServer.clear()
	if language == SettingsTypes.Language.NONE:
		return
	var it_translation: Translation = load(IT_TRANSLATION_PATH)
	if it_translation != null:
		TranslationServer.add_translation(it_translation)
