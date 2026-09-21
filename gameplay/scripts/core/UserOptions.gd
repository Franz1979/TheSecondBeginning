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
# Aggiunto insieme a translations/strings.en.csv (richiesta utente, 2026-09-06) — prima ENGLISH
# era un placeholder puro (vedi apply_language sotto), caricava silenziosamente l'IT come tutte le
# altre lingue non ancora reali.
const EN_TRANSLATION_PATH := "res://translations/strings.en.translation"

var show_notification_popups: bool = true
# SettingsTypes.Language — NONE (default, richiesta utente 2026-09-05: NON forzare ITALIAN come
# default di questo campo) = nessuna lingua forzata, si usa il comportamento tr() di default
# (locale di sistema + fallback di progetto, vedi project.godot). Che oggi questo mostri comunque
# l'italiano è un effetto del fallback di progetto (locale/fallback="it", unica traduzione reale
# presente), non di questo campo — resta NONE finché l'utente non sceglie esplicitamente una
# lingua dal menu Opzioni. Nessuna logica di cambio lingua reale collegata a questo campo ancora
# (arriverà con l'Options vera).
var language: SettingsTypes.Language = SettingsTypes.Language.NONE

# Preselezione del dialog di raccolta (2026-09-20, richiesta utente, zaino multi-risorsa): quale voce del menu
# Tutto / categoria / risorsa e' preselezionata quando si apre il PickupChoiceDialog. Tre campi:
#   - pickup_default_kind: PickUpAction.CriterionKind (ALL = "Tutto", il default; CATEGORY; NAME = una risorsa);
#   - pickup_default_category: SecondaryResourceTypes.Category come int (solo con CATEGORY, altrimenti -1);
#   - pickup_default_resource: nome della risorsa (solo con NAME, altrimenti "").
# Se la voce non e' presente nella microcella il dialog ripiega risalendo (categoria, poi "Tutto") — vedi
# PickupChoiceDialog._resolve_default_index. Letto da GameScene tramite get_pickup_default_choice().
var pickup_default_kind: int = PickUpAction.CriterionKind.ALL
var pickup_default_category: int = -1
var pickup_default_resource: String = ""
# Ripetizione automatica di raccolta E trasporto (2026-09-20, richiesta utente; era solo "pickup"): default del
# flag "Ripeti fino a TaskRepeatRules.MAX_REPEATS volte" dei dialog di raccolta e di trasporto. Vale anche quando il
# dialog di raccolta non compare (cella con una sola risorsa). Chiave in options.cfg: "repeat_default" (con lettura
# di ripiego della vecchia "pickup_repeat_default").
var repeat_default: bool = false
# Minimappa della sidebar chiusa (2026-09-20, richiesta utente): true = nascosta, resta solo il bottone per
# riaprirla; false (default) = visibile. Salvato a ogni click sul bottone.
var minimap_collapsed: bool = false


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
	# Preselezione raccolta: valori fuori range (file modificato a mano, enum cambiato) ripiegano su "Tutto".
	var loaded_kind: int = int(config.get_value(SECTION, "pickup_default_kind", PickUpAction.CriterionKind.ALL))
	if loaded_kind < PickUpAction.CriterionKind.NAME or loaded_kind > PickUpAction.CriterionKind.ALL:
		loaded_kind = PickUpAction.CriterionKind.ALL
	pickup_default_kind = loaded_kind
	pickup_default_category = int(config.get_value(SECTION, "pickup_default_category", -1))
	pickup_default_resource = String(config.get_value(SECTION, "pickup_default_resource", ""))
	repeat_default = bool(config.get_value(SECTION, "repeat_default", config.get_value(SECTION, "pickup_repeat_default", false)))
	minimap_collapsed = bool(config.get_value(SECTION, "minimap_collapsed", false))


# Pubblico per un futuro menu Options — nessun chiamante reale ancora (i campi sopra si cambiano
# solo da codice/debug per ora).
func save_to_disk() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "show_notification_popups", show_notification_popups)
	config.set_value(SECTION, "language", language)
	config.set_value(SECTION, "pickup_default_kind", pickup_default_kind)
	config.set_value(SECTION, "pickup_default_category", pickup_default_category)
	config.set_value(SECTION, "pickup_default_resource", pickup_default_resource)
	config.set_value(SECTION, "repeat_default", repeat_default)
	config.set_value(SECTION, "minimap_collapsed", minimap_collapsed)
	config.save(OPTIONS_FILE_PATH)


# La preselezione del dialog di raccolta nel formato atteso da PickupChoiceDialog.open_dialog:
# {"kind", "category", "resource_name"}. Con kind NAME la categoria e' ricavata dalle regole della risorsa (non
# dal valore salvato), cosi' il ripiego "categoria" resta corretto anche se una .tres cambia categoria; se la
# risorsa non ha piu' regole si usa il valore salvato.
func get_pickup_default_choice() -> Dictionary:
	var category: int = pickup_default_category
	if pickup_default_kind == PickUpAction.CriterionKind.NAME:
		var rules := CaloricCalculator.get_caloric_source_rules(pickup_default_resource)
		if rules != null:
			category = int(rules.category)
	return {
		"kind": pickup_default_kind,
		"category": category,
		"resource_name": pickup_default_resource if pickup_default_kind == PickUpAction.CriterionKind.NAME else "",
	}


# TEMPORANEO/DEBUG (richiesta utente, 2026-09-05, esplicitamente da rimuovere a fine debug): con
# NONE, svuota tutte le traduzioni caricate (TranslationServer.clear()) così tr() ritorna la CHIAVE
# grezza invece del testo tradotto — un modo visivo per distinguere "nessuna lingua scelta" da
# "lingua applicata", visto che oggi coincidono per via del fallback di progetto (locale/
# fallback="it", vedi project.godot). ENGLISH ora ha contenuto reale anch'essa (strings.en.csv,
# 2026-09-06) — GERMAN/FRENCH/SPANISH restano segnaposto (nessun file dedicato ancora, vedi
# SettingsTypes.gd) e ricadono sull'IT come le altre lingue non ancora reali facevano tutte prima
# di questo cambio. NON è il futuro sistema di cambio lingua reale (quello dovrà coprire tutte le
# lingue, non solo IT/EN) — solo un aiuto di debug per verificare il flusso NONE, va ripulito
# quando arriverà una vera gestione multi-lingua.
func apply_language() -> void:
	TranslationServer.clear()
	if language == SettingsTypes.Language.NONE:
		return
	var translation_path := (
		EN_TRANSLATION_PATH if language == SettingsTypes.Language.ENGLISH else IT_TRANSLATION_PATH
	)
	var translation: Translation = load(translation_path)
	if translation != null:
		TranslationServer.add_translation(translation)
