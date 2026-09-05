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
@onready var close_button: Button = $MarginContainer/VBoxContainer/CloseButton

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
func _resize_to_content() -> void:
	size = Vector2i(get_contents_minimum_size()) + Vector2i(0, 20)


# Estratta da _ready() per poter essere richiamata anche dopo un cambio lingua (vedi sopra) senza
# duplicare le stringhe da (ri)tradurre.
func _refresh_texts() -> void:
	title = tr("options")
	notification_popups_label.text = tr("options_show_notification_popups")
	language_label.text = tr("options_language")
	# "close_and_save" (non "close_menu", richiesta utente 2026-09-05): stesso identico
	# comportamento (hide()), solo l'etichetta comunica che le modifiche sono già salvate — coerente
	# con UserOptions che persiste ad ogni singola modifica, non solo alla chiusura.
	close_button.text = tr("close_and_save")
	for i in LANGUAGE_LABEL_KEYS.size():
		language_option_button.set_item_text(i, tr(LANGUAGE_LABEL_KEYS[i]))
