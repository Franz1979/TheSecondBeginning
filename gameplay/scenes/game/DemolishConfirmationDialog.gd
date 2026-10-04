class_name DemolishConfirmationDialog
extends ConfirmationDialog

# Conferma prima di demolire (2026-09-12, richiesta utente — "attiva il bottone Demolisci: ...
# mostra una conferma, stesso meccanismo già usato altrove nel progetto se esiste, altrimenti una
# semplice richiesta si/no") — STESSO schema minimale di ExitConfirmationDialog.gd (estende
# direttamente il ConfirmationDialog nativo di Godot invece di un Window custom come
# SaveConfirmationDialog, che serve tre opzioni invece di due — qui bastano OK/Annulla). A
# differenza di ExitConfirmationDialog (nessun parametro, testo sempre uguale), questo deve
# ricordare QUALE building demolire tra l'apertura e la conferma — oggi catturato nella callback
# `_pending_on_confirm` (building Variant, stesso principio "duck-typed, no import ciclico" di TaskReassignmentService: questa scena vive in
# gameplay/, Building in simulation/, nessun problema di dipendenza in questa direzione ma la firma
# resta comunque generica per coerenza con l'altro punto di introduzione recente dello stesso
# pattern).
#
# display_name/building_id passati già RISOLTI da GameScene.open_dialog (mai letti da rules/tr()
# qui dentro) — stesso principio "pannello muto, riceve solo dati già pronti" già seguito da
# BuildBar/GameInfoPanel per lo stesso genere di componente UI.
#
# GENERICO (2026-10-03, richiesta utente — conferma di "Svuota tutto"): open_confirmation apre lo stesso dialog con
# titolo, testo e pulsante di conferma dati dal chiamante e chiama `on_confirm` alla conferma. open_dialog (demolizione)
# è ora un suo caso particolare e continua a emettere demolish_confirmed.
#
# IMPAGINAZIONE (2026-10-04, richiesta utente — un testo lungo allargava il popup su tutta la mappa): la Label nativa
# del dialog è nascosta e il testo va in un contenuto proprio (_content): la domanda in prima riga, più grande; sotto,
# il resto in paragrafi che vanno a capo entro MAX_CONTENT_WIDTH (~450 px di popup); la larghezza segue la riga più
# lunga, tra MIN_CONTENT_WIDTH e MAX_CONTENT_WIDTH, così una domanda corta (demolizione) non resta in un popup largo e
# vuoto né in uno troppo stretto. I due pulsanti centrati e vicini (_center_buttons). Comportamento invariato.
signal demolish_confirmed(building: Variant)

const MAX_CONTENT_WIDTH: float = 430.0
const MIN_CONTENT_WIDTH: float = 260.0
const QUESTION_FONT_SIZE_DELTA: int = 2
const PARAGRAPH_SEPARATION: int = 8
const BUTTON_GAP: float = 16.0

var _pending_on_confirm: Callable = Callable()
var _content: VBoxContainer = null
var _question_label: Label = null
var _paragraphs: VBoxContainer = null


func _ready() -> void:
	cancel_button_text = tr("demolish_confirmation_cancel")
	confirmed.connect(_on_confirmed)
	canceled.connect(_on_canceled)
	_build_content()
	_center_buttons()


func _build_content() -> void:
	get_label().visible = false
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", PARAGRAPH_SEPARATION)
	add_child(_content)
	_question_label = Label.new()
	_question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_question_label)
	_question_label.add_theme_font_size_override(
		"font_size", _question_label.get_theme_font_size("font_size") + QUESTION_FONT_SIZE_DELTA
	)
	_paragraphs = VBoxContainer.new()
	_paragraphs.add_theme_constant_override("separation", PARAGRAPH_SEPARATION)
	_content.add_child(_paragraphs)


# Il contenitore nativo dei pulsanti alterna spaziatori espandibili ([sp] OK [sp] Annulla [sp]): con un popup largo i
# pulsanti finivano ai lati. Restano espandibili solo i due spaziatori esterni; quelli tra i pulsanti diventano un
# piccolo spazio fisso, così i pulsanti stanno insieme al centro.
func _center_buttons() -> void:
	var buttons_box := get_ok_button().get_parent()
	var children := buttons_box.get_children(true)
	var first_button := -1
	var last_button := -1
	for i in children.size():
		if children[i] is Button and (children[i] as Button).visible:
			if first_button < 0:
				first_button = i
			last_button = i
	for i in range(first_button + 1, last_button):
		var child: Node = children[i]
		if child is Control and not (child is Button):
			(child as Control).size_flags_horizontal = Control.SIZE_FILL
			(child as Control).custom_minimum_size.x = BUTTON_GAP


# is_site (2026-09-27, richiesta utente): true per un cantiere non completo — testo, titolo e pulsante di
# conferma diversi ("Annulla cantiere"), perché lì la conferma annulla subito invece di segnare "da demolire".
func open_dialog(building: Variant, display_name: String, building_id: int, is_site: bool = false) -> void:
	var prefix := "demolish_confirmation_site_" if is_site else "demolish_confirmation_"
	open_confirmation(
		tr(prefix + "title"),
		tr(prefix + "text").format({"building": display_name, "id": building_id}),
		tr(prefix + "confirm"),
		func(): demolish_confirmed.emit(building)
	)


# Conferma generica: testi già tradotti; righe separate da "\n". La prima riga è la domanda, le altre i paragrafi sotto
# (a capo automatico entro la larghezza massima). Se la prima riga continua dopo il "?" ("Annullare …? Il materiale cade
# a terra."), il seguito diventa il primo paragrafo.
func open_confirmation(title_text: String, body_text: String, confirm_text: String, on_confirm: Callable) -> void:
	_pending_on_confirm = on_confirm
	title = title_text
	dialog_text = ""
	ok_button_text = confirm_text

	var paragraphs: Array[String] = []
	for line in body_text.split("\n", false):
		paragraphs.append(line.strip_edges())
	var question: String = paragraphs.pop_front() if not paragraphs.is_empty() else ""
	var question_end := question.find("? ")
	if question_end >= 0:
		paragraphs.push_front(question.substr(question_end + 2).strip_edges())
		question = question.substr(0, question_end + 1)

	for child in _paragraphs.get_children():
		_paragraphs.remove_child(child)
		child.queue_free()
	for text in paragraphs:
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = text
		_paragraphs.add_child(label)
	_paragraphs.visible = not paragraphs.is_empty()
	_question_label.text = question
	# Sola domanda (demolizione): centrata sopra i pulsanti centrati, per non lasciare il popup sbilanciato a sinistra.
	_question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if _paragraphs.visible else HORIZONTAL_ALIGNMENT_CENTER

	var width := clampf(_widest_line_width(question, paragraphs), MIN_CONTENT_WIDTH, MAX_CONTENT_WIDTH)
	_question_label.custom_minimum_size.x = width
	for label in _paragraphs.get_children():
		(label as Label).custom_minimum_size.x = width

	exclusive = true
	size = Vector2i.ZERO
	popup_centered()
	_refit_after_layout()


# Larghezza naturale (senza a capo) della riga più lunga, +2 px perché una riga che entra di misura non vada a capo.
func _widest_line_width(question: String, paragraphs: Array[String]) -> float:
	var font := _question_label.get_theme_font("font")
	var widest := font.get_string_size(
		question, HORIZONTAL_ALIGNMENT_LEFT, -1, _question_label.get_theme_font_size("font_size")
	).x
	var paragraph_font_size := _paragraphs.get_theme_font_size("font_size", "Label")
	for text in paragraphs:
		widest = maxf(widest, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, paragraph_font_size).x)
	return widest + 2.0


# Le Label con a capo automatico conoscono la propria altezza solo dopo l'impaginazione: un frame dopo l'apertura il
# popup torna alla misura minima vera e si ricentra.
func _refit_after_layout() -> void:
	await get_tree().process_frame
	if not visible:
		return
	reset_size()
	move_to_center()


func _on_confirmed() -> void:
	var on_confirm := _pending_on_confirm
	_pending_on_confirm = Callable()
	if on_confirm.is_valid():
		on_confirm.call()


func _on_canceled() -> void:
	_pending_on_confirm = Callable()
