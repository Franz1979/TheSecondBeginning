class_name HelpDialog
extends Window

# Popup di aiuto di GameScene — stesso pattern di SystemMenuDialog/SaveConfirmationDialog (Window,
# popup_centered, close_requested -> hide), trattato come dialogo bloccante da GameScene
# (visibility_changed collegato a _on_blocking_dialog_visibility_changed, stesso schema degli
# altri due): mette in pausa il clock mentre è aperto, non il movimento dell'individuo
# (indipendente dal clock per design).
#
# Struttura a indice con link ipertestuali (richiesta utente, 2026-08-30): un solo
# RichTextLabel riusato per tutte le "pagine" — l'indice (PAGE_MAIN, con un [url=...] per voce)
# e ogni pagina foglia (oggi solo PAGE_SHORTCUTS). meta_clicked cambia pagina, back_button
# (nascosto sull'indice, non c'è dove tornare) riporta a PAGE_MAIN. Aggiungere una nuova voce di
# help significa: una nuova costante PAGE_*, una riga [url=...] in _build_main_menu_text, e un
# nuovo _build_*_text/branch nel match di _show_page.

@onready var content_label: RichTextLabel = $MarginContainer/VBoxContainer/ContentLabel
@onready var back_button: Button = $MarginContainer/VBoxContainer/BackButton
@onready var close_button: Button = $MarginContainer/VBoxContainer/CloseButton

const PAGE_MAIN := "main"
const PAGE_SHORTCUTS := "shortcuts"
const PAGE_FOG_OF_WAR := "fog_of_war"

var _current_page: String = PAGE_MAIN


func _ready() -> void:
	title = tr("help_dialog_title")
	close_button.text = tr("close")
	close_button.pressed.connect(hide)
	close_requested.connect(hide)
	back_button.text = tr("back")
	back_button.pressed.connect(_show_page.bind(PAGE_MAIN))

	content_label.bbcode_enabled = true
	content_label.meta_clicked.connect(_on_meta_clicked)
	_show_page(PAGE_MAIN)


func open_dialog() -> void:
	# Riparte sempre dall'indice quando il popup si riapre — nessuna pagina foglia resta "aperta"
	# da una sessione precedente, coerente con com'era il comportamento prima di questa modifica
	# (il contenuto era sempre lo stesso ad ogni apertura).
	_show_page(PAGE_MAIN)
	exclusive = true
	popup_centered(Vector2i(420, 400))


func _on_meta_clicked(meta: Variant) -> void:
	_show_page(str(meta))


func _show_page(page: String) -> void:
	_current_page = page
	back_button.visible = page != PAGE_MAIN
	match page:
		PAGE_SHORTCUTS:
			content_label.text = _build_shortcuts_text()
		PAGE_FOG_OF_WAR:
			content_label.text = _build_fog_of_war_text()
		_:
			content_label.text = _build_main_menu_text()


func _build_main_menu_text() -> String:
	var lines: Array[String] = [
		"[b]%s[/b]" % tr("help_dialog_title"),
		"",
		"[url=%s]%s[/url]" % [PAGE_SHORTCUTS, tr("help_shortcuts_menu_link")],
		"[url=%s]%s[/url]" % [PAGE_FOG_OF_WAR, tr("help_fog_of_war_menu_link")],
	]
	return "\n".join(lines)


func _build_fog_of_war_text() -> String:
	# I tre livelli usano [ol]/[li] (lista numerata) invece di prefissare "1."/"2."/"3." dentro le
	# chiavi tradotte — la formattazione è responsabilità del codice, il testo tradotto resta puro
	# senza markup da dover replicare/mantenere in ogni lingua.
	var lines: Array[String] = [
		"[b]%s[/b]" % tr("help_fog_of_war_title"),
		"",
		tr("help_fog_of_war_intro"),
		"",
		tr("help_fog_of_war_memory_intro"),
		"[ol]",
		"[li]%s[/li]" % tr("help_fog_of_war_tier_detail"),
		"[li]%s[/li]" % tr("help_fog_of_war_tier_resources"),
		"[li]%s[/li]" % tr("help_fog_of_war_tier_terrain"),
		"[/ol]",
		tr("help_fog_of_war_full_forget"),
		"",
		tr("help_fog_of_war_persistence"),
		"",
		tr("help_fog_of_war_per_macrocell"),
	]
	return "\n".join(lines)


func _build_shortcuts_text() -> String:
	var lines: Array[String] = [
		"[b]%s[/b]" % tr("help_shortcuts_title"),
		"",
		"[b]W A S D[/b] / %s — %s" % [tr("help_arrow_keys"), tr("help_pan_camera")],
		"[b]X[/b] — %s" % tr("help_center_camera"),
		"[b]+[/b] — %s" % tr("help_zoom_max"),
		"[b]-[/b] — %s" % tr("help_zoom_min"),
		"[b]R[/b] — %s" % tr("help_rotate_building"),
	]
	return "\n".join(lines)
