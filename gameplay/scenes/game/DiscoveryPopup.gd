class_name DiscoveryPopup
extends Window

# Popup "Scoperta" (2026-09-28, richiesta utente): al centro, bloccante, testo BBCode, solo OK. Sostituisce il
# NotificationPopup IDEA_COMPLETED e mostra le spiegazioni dei DiscoveryHintRules. Una o più SEZIONI (una per idea
# completata o scoperta scattata nello stesso momento), ognuna con icona per tipo di trigger, titolo e righe.
# "Pannello muto" come EventDecisionDialog: riceve testi già tradotti, non conosce idee né azioni di chiusura —
# alla chiusura emette `acknowledged` e GameScene esegue le azioni raccolte.
#
# Mai due popup consecutivi: se arrivano sezioni mentre è aperto, append_sections le aggiunge a quello visibile.
#
# Bloccante: GameScene collega visibility_changed a _on_blocking_dialog_visibility_changed (tempo e camera fermi).
# X nativa nascosta e close_requested non collegato (stesso meccanismo di EventDecisionDialog): si chiude solo con OK.
# Costruita interamente via codice, nessun .tscn.
#
# Sezione: {"trigger": DiscoveryTypes.TriggerType, "title": String, "lines": Array[String]}.

signal acknowledged

const DIALOG_WIDTH: int = 460
const MAX_TEXT_HEIGHT: int = 420
const CONTENT_MARGIN: int = 12
const TITLE_FONT_SIZE: int = 18

const TRIGGER_ICONS := {
	DiscoveryTypes.TriggerType.IDEA_COMPLETED: "💡",
	DiscoveryTypes.TriggerType.BUILDING_COMPLETED: "🏛️",
}

var _sections: Array[Dictionary] = []
var _scroll: ScrollContainer
var _text_label: RichTextLabel
var _ok_button: Button


func _init() -> void:
	visible = false
	exclusive = true
	transient = true
	unresizable = true
	wrap_controls = true


func _ready() -> void:
	var transparent := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	add_theme_icon_override("close", transparent)
	add_theme_icon_override("close_pressed", transparent)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, CONTENT_MARGIN)
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", CONTENT_MARGIN)
	margin.add_child(box)

	# Testo lungo (più sezioni): scorre oltre MAX_TEXT_HEIGHT invece di allungare la finestra fuori schermo.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_scroll)

	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.scroll_active = false
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(DIALOG_WIDTH - 2 * CONTENT_MARGIN, 0)
	_text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_text_label)

	_ok_button = Button.new()
	_ok_button.custom_minimum_size = Vector2(120, 32)
	_ok_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_ok_button.pressed.connect(_on_ok_pressed)
	box.add_child(_ok_button)


func open_popup(sections: Array[Dictionary]) -> void:
	if sections.is_empty():
		return
	_sections = sections.duplicate()
	title = tr("discovery_popup_title")
	_ok_button.text = tr("notification_ok")
	_refresh()
	popup_centered(Vector2i(DIALOG_WIDTH, 0))
	_fit_to_content()


# Aggiunge sezioni al popup già aperto (mai un secondo popup in coda).
func append_sections(sections: Array[Dictionary]) -> void:
	if not visible:
		open_popup(sections)
		return
	_sections.append_array(sections)
	_refresh()
	_fit_to_content()


func _refresh() -> void:
	var parts: Array[String] = []
	for section in _sections:
		var icon: String = TRIGGER_ICONS.get(section.get("trigger", -1), "✨")
		var block: Array[String] = ["[font_size=%d]%s [b]%s[/b][/font_size]" % [TITLE_FONT_SIZE, icon, section.get("title", "")]]
		for line in section.get("lines", []):
			block.append(String(line))
		parts.append("\n".join(block))
	_text_label.text = "\n\n".join(parts)


# Altezza del testo nota solo dopo un frame di layout: la finestra si adatta fino a MAX_TEXT_HEIGHT, poi scorre.
func _fit_to_content() -> void:
	await get_tree().process_frame
	if not visible:
		return
	_scroll.custom_minimum_size = Vector2(0, mini(_text_label.get_content_height(), MAX_TEXT_HEIGHT))
	size = Vector2i(DIALOG_WIDTH, 0)
	size = Vector2i(get_contents_minimum_size())
	move_to_center()


func _on_ok_pressed() -> void:
	_sections.clear()
	hide()
	acknowledged.emit()
