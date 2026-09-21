class_name OptionsMenu
extends Window

# Menu Opzioni riusabile — stesso pattern di SystemMenuDialog (Window standalone, MarginContainer/
# VBoxContainer, CloseButton + close_requested->hide). Istanziato da MainMenu (avvio, sostituisce
# il vecchio popup placeholder "_show_not_ready_popup") — un secondo punto d'ingresso dal
# SystemMenuDialog in-game è previsto come step successivo, stessa scena/script, nessuna
# duplicazione (richiesta utente, 2026-09-05).
#
# Legge/scrive direttamente l'autoload UserOptions — nessuno stato locale, ogni modifica si applica
# e persiste subito (UserOptions.save_to_disk()), niente pulsanti Salva/Annulla: coerente con
# UserOptions stesso, pensato per essere scritto da una UI reale non appena esiste.
#
# Solo i 2 campi esistenti oggi (show_notification_popups, language) — nessun campo audio/video
# ancora, per scelta esplicita (vedi discussione con l'utente sulla lista di opzioni di Dawn of
# Man). Entrambi liberamente modificabili in qualunque contesto (nessuno dei due richiede un
# vincolo "solo pre-partita" — quella distinzione si riconsidera solo quando esisterà davvero un
# campo così, es. futuri campi video).

@onready var notification_popups_check_box: CheckBox = $MarginContainer/VBoxContainer/NotificationPopupsRow/CheckBox
@onready var notification_popups_label: Label = $MarginContainer/VBoxContainer/NotificationPopupsRow/Label
@onready var language_row: HBoxContainer = $MarginContainer/VBoxContainer/LanguageRow
@onready var language_option_button: OptionButton = $MarginContainer/VBoxContainer/LanguageRow/OptionButton
@onready var language_label: Label = $MarginContainer/VBoxContainer/LanguageRow/Label
@onready var pickup_default_label: Label = $MarginContainer/VBoxContainer/PickupDefaultRow/Label
@onready var pickup_default_option_button: OptionButton = $MarginContainer/VBoxContainer/PickupDefaultRow/OptionButton
@onready var repeat_label: Label = $MarginContainer/VBoxContainer/RepeatRow/Label
@onready var repeat_check_box: CheckBox = $MarginContainer/VBoxContainer/RepeatRow/CheckBox
@onready var close_button: Button = $MarginContainer/VBoxContainer/CloseButton

# Bugfix (richiesta utente, 2026-09-06): _resize_to_content() prima si limitava a INSEGUIRE il
# contenuto corrente (size = get_contents_minimum_size() ogni volta) — passando a una lingua col
# testo reale più corto (es. Italiano, una volta caricata la traduzione) la finestra si RIMPICCIOLIVA
# fin sotto lo spazio che la dropdown/testo servono davvero, tagliandoli. Osservazione dell'utente:
# lo stato di default (NONE, prima di scegliere una lingua — chiavi tr() grezze, tipicamente le
# stringhe più lunghe di tutte) è già la dimensione "massima" che serve. Invece di ricalcolare da
# zero ogni volta, si tiene il PIÙ GRANDE mai visto (mai ridotto), partendo naturalmente da quello
# stato NONE alla primissima apertura.
var _max_content_size := Vector2i.ZERO

# Ordine di visualizzazione nella dropdown = ordinale di SettingsTypes.Language (indice
# OptionButton == valore enum), nessuna mappa separata necessaria.
const LANGUAGE_LABEL_KEYS := [
	"language_none",
	"language_italian",
	"language_english",
	"language_german",
	"language_french",
	"language_spanish",
]


func _ready() -> void:
	for key in LANGUAGE_LABEL_KEYS:
		language_option_button.add_item(tr(key))
	_refresh_texts()

	notification_popups_check_box.toggled.connect(_on_notification_popups_toggled)
	language_option_button.item_selected.connect(_on_language_selected)
	pickup_default_option_button.item_selected.connect(_on_pickup_default_selected)
	repeat_check_box.toggled.connect(_on_repeat_toggled)
	close_button.pressed.connect(hide)
	# close_requested NON collegato a hide() + X nascosta (richiesta utente, 2026-09-05, stesso
	# motivo/meccanismo di SystemMenuDialog._hide_native_close_button): si chiude solo dal
	# CloseButton esplicito.
	var transparent := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	add_theme_icon_override("close", transparent)
	add_theme_icon_override("close_pressed", transparent)


# Richiamata ad ogni apertura (non solo alla creazione) — rilegge da UserOptions così il menu
# riflette sempre lo stato attuale anche se cambiato altrove (es. da codice/debug).
#
# show_language (richiesta utente, 2026-09-05): il menu di sistema IN-GAME passa false — lì si
# vuole mostrare solo il toggle notifiche, non la scelta lingua (decisione esplicita dell'utente
# per questo contesto, non un vincolo tecnico come per show_notification_popups). MainMenu
# continua a passare il default true. Nasconde l'intera riga, non solo la disabilita — un campo
# non pertinente in quel contesto non deve nemmeno occupare spazio.
func open_menu(show_language: bool = true) -> void:
	notification_popups_check_box.set_pressed_no_signal(UserOptions.show_notification_popups)
	language_option_button.select(UserOptions.language)
	language_row.visible = show_language
	# La preselezione raccolta e' pertinente sia dal menu principale sia in partita: la riga c'e' sempre.
	_select_pickup_default_from_options()
	repeat_check_box.set_pressed_no_signal(UserOptions.repeat_default)
	exclusive = true
	_resize_to_content()
	popup_centered()


func _on_notification_popups_toggled(pressed: bool) -> void:
	UserOptions.show_notification_popups = pressed
	UserOptions.save_to_disk()


func _on_language_selected(index: int) -> void:
	UserOptions.language = index as SettingsTypes.Language
	UserOptions.save_to_disk()
	UserOptions.apply_language()
	# Rinfresca subito i testi di QUESTA finestra (titolo/label/voci dropdown) così l'effetto del
	# debug NONE->chiavi grezze (vedi UserOptions.apply_language) è visibile senza dover chiudere e
	# riaprire il menu. Il resto della UI del gioco (scene già aperte altrove) non si aggiorna da
	# solo — nessun sistema di retranslation live esiste, non necessario per questo aiuto di debug
	# temporaneo.
	_refresh_texts()
	# Riadatta anche la dimensione della finestra (richiesta utente, 2026-09-05, bugfix: prima solo
	# open_menu() la ricalcolava, quindi passando a NONE a finestra già aperta la chiave grezza
	# lunga restava tagliata finché non si richiudeva e riapriva il menu).
	_resize_to_content()


# size = get_contents_minimum_size() ESPLICITO (popup_centered() da solo non ridimensiona) —
# richiamata sia all'apertura sia dopo ogni cambio lingua (vedi sopra), non solo alla creazione:
# la lunghezza del testo cambia in entrambi i casi. +20px di margine per respiro visivo.
#
# MAI ridotta sotto la più grande già vista (vedi _max_content_size sopra per il perché) — solo
# cresce se il contenuto corrente richiede più spazio, non si restringe mai per un contenuto più
# corto (es. dopo aver scelto una lingua con testo reale più breve delle chiavi grezze di NONE).
func _resize_to_content() -> void:
	var content_size := Vector2i(get_contents_minimum_size()) + Vector2i(0, 20)
	_max_content_size = _max_content_size.max(content_size)
	size = _max_content_size


# Estratta da _ready() per poter essere richiamata anche dopo un cambio lingua (vedi sopra) senza
# duplicare le stringhe da (ri)tradurre.
func _refresh_texts() -> void:
	title = tr("options")
	notification_popups_label.text = tr("options_show_notification_popups")
	language_label.text = tr("options_language")
	pickup_default_label.text = tr("options_pickup_default")
	repeat_label.text = tr("options_repeat_default").format({"count": TaskRepeatRules.MAX_REPEATS})
	_rebuild_pickup_default_options()
	# "close_and_save" (non "close_menu", richiesta utente 2026-09-05): stesso identico
	# comportamento (hide()), solo l'etichetta comunica che le modifiche sono già salvate — coerente
	# con UserOptions che persiste ad ogni singola modifica, non solo alla chiusura.
	close_button.text = tr("close_and_save")
	for i in LANGUAGE_LABEL_KEYS.size():
		language_option_button.set_item_text(i, tr(LANGUAGE_LABEL_KEYS[i]))


# --- Preselezione del dialog di raccolta (2026-09-20, richiesta utente) ---

# Ricostruisce l'elenco COMPLETO delle scelte possibili (non solo quelle presenti in una cella), con i testi
# nella lingua corrente — chiamata da _refresh_texts, quindi anche dopo un cambio lingua:
#   Tutto
#   -- Categoria --   Tutto il cibo / Tutti i materiali / Tutti i medicinali
#   -- Risorsa --     tutte le risorse raccoglibili (TerrainScatteredResourceService.is_pickable), raggruppate per
#                      categoria nell'ordine di PickUpAction.PRIORITY_CATEGORIES e, dentro, per nome leggibile.
# Ogni voce selezionabile porta come metadata {"kind", "category", "resource_name"}; le intestazioni sono
# separatori (senza metadata). Poi riseleziona la voce salvata in UserOptions.
func _rebuild_pickup_default_options() -> void:
	pickup_default_option_button.clear()
	_add_pickup_default_item(tr("pickup_choice_all"), PickUpAction.CriterionKind.ALL, -1, "")

	pickup_default_option_button.add_separator(tr("options_pickup_default_group_category"))
	for category in PickUpAction.PRIORITY_CATEGORIES:
		var text_keys: Array = PickupChoiceDialog.CATEGORY_TEXT_KEYS.get(category, ["", ""])
		if text_keys[1] == "":
			continue
		_add_pickup_default_item(tr(text_keys[1]), PickUpAction.CriterionKind.CATEGORY, int(category), "")

	pickup_default_option_button.add_separator(tr("options_pickup_default_group_resource"))
	var names_by_category: Dictionary = {}
	for resource_name in CaloricCalculator.list_secondary_resource_names():
		if not TerrainScatteredResourceService.is_pickable(resource_name):
			continue
		var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
		if rules == null:
			continue
		var category: int = int(rules.category)
		if not names_by_category.has(category):
			names_by_category[category] = []
		names_by_category[category].append(resource_name)
	for category in PickUpAction.PRIORITY_CATEGORIES:
		var category_names: Array = names_by_category.get(int(category), [])
		category_names.sort_custom(func(a: String, b: String) -> bool:
			return IconRegistry.get_resource_display_name(a) < IconRegistry.get_resource_display_name(b)
		)
		for resource_name in category_names:
			_add_pickup_default_item(IconRegistry.get_resource_display_name(resource_name), PickUpAction.CriterionKind.NAME, int(category), resource_name)

	_select_pickup_default_from_options()


func _add_pickup_default_item(text: String, kind: int, category: int, resource_name: String) -> void:
	pickup_default_option_button.add_item(text)
	var index: int = pickup_default_option_button.item_count - 1
	pickup_default_option_button.set_item_metadata(index, {"kind": kind, "category": category, "resource_name": resource_name})


# Seleziona nel menu la voce salvata in UserOptions; se non c'e' (risorsa non piu' esistente, categoria non
# valida) ripiega su "Tutto" (indice 0).
func _select_pickup_default_from_options() -> void:
	var selected_index: int = 0
	for i in range(pickup_default_option_button.item_count):
		if pickup_default_option_button.is_item_separator(i):
			continue
		var meta: Variant = pickup_default_option_button.get_item_metadata(i)
		if not (meta is Dictionary):
			continue
		if int(meta["kind"]) != UserOptions.pickup_default_kind:
			continue
		if int(meta["kind"]) == PickUpAction.CriterionKind.CATEGORY and int(meta["category"]) != UserOptions.pickup_default_category:
			continue
		if int(meta["kind"]) == PickUpAction.CriterionKind.NAME and String(meta["resource_name"]) != UserOptions.pickup_default_resource:
			continue
		selected_index = i
		break
	pickup_default_option_button.select(selected_index)


func _on_pickup_default_selected(index: int) -> void:
	var meta: Variant = pickup_default_option_button.get_item_metadata(index)
	if not (meta is Dictionary):
		return
	UserOptions.pickup_default_kind = int(meta["kind"])
	UserOptions.pickup_default_category = int(meta["category"]) if int(meta["kind"]) != PickUpAction.CriterionKind.ALL else -1
	UserOptions.pickup_default_resource = String(meta["resource_name"])
	UserOptions.save_to_disk()


# Default del flag "Ripeti fino a N volte" dei dialog di raccolta e di trasporto (2026-09-20, richiesta utente).
func _on_repeat_toggled(pressed: bool) -> void:
	UserOptions.repeat_default = pressed
	UserOptions.save_to_disk()
