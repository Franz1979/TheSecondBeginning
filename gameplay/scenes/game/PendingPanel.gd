class_name PendingPanel
extends VBoxContainer

# Scheda "In sospeso" dell'info panel (2026-10-04, richiesta utente): elenco delle cose ferme — corpi non sepolti che
# nessuno ha in carico, poi lavori senza nessuno assegnato. Componente "muto" come gli altri pannelli: riceve le voci
# già calcolate e ordinate da GameScene (set_entries) e segnala solo il clic (entry_activated); creato in codice.
#
# Riga sul modello della lista degli abitanti: a sinistra il tasto 🎯, poi il testo su una riga, troncato con i puntini
# (intero nel tooltip), così la scheda non allarga mai il pannello. Solo il 🎯 centra e seleziona (dal 2026-10-07 il
# testo non è più cliccabile). Voce che non si può centrare: riga spenta, spiegazione nel tooltip. Le righe vengono rifatte solo quando l'elenco cambia davvero.
#
# Dal 2026-10-09 (richiesta utente): titolo "In sospeso" in cima (stile dei titoli delle altre schede, 11 px), "Niente in
# sospeso" al posto della lista vuota, e righe su due livelli come quelle del cassetto "Assegnazione compiti": sopra il
# nome ("name", es. "Demolizione · Terra battuta"), sotto in piccolo il motivo ("detail", es. "Manca il demolitore").
# Entrambi vanno a capo, il pannello non si allarga. Tooltip: il testo lungo ("text"). Una voce senza "name" mostra
# "text" su un livello solo.
#
# Voce: {"key": String univoca, "text": String, "name": String, "detail": String, "enabled": bool,
# "disabled_reason": String, ...dati per il chiamante}.

signal entry_activated(entry: Dictionary)

const CENTER_BUTTON_TEXT := "🎯"
const TITLE_FONT_SIZE: int = 11
const FONT_SIZE: int = 10
# Riga del motivo sotto il nome: come le righe di stato del cassetto (TaskAssignmentPanel.LIST_FONT_SIZE - 2).
const DETAIL_FONT_SIZE: int = 9
const DETAIL_MODULATE := Color(1, 1, 1, 0.7)
const DISABLED_MODULATE := Color(1, 1, 1, 0.45)

var _signature: String = "-"
var _title_label: Label = null
var _rows_box: VBoxContainer = null


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label = Label.new()
	_title_label.text = tr("pending_title")
	_title_label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	add_child(_title_label)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 3)
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_rows_box)
	_show_empty()


func set_entries(entries: Array[Dictionary]) -> void:
	var parts: PackedStringArray = []
	for entry in entries:
		parts.append("%s|%s|%s|%s|%s|%s" % [
			entry["key"], entry["text"], entry.get("name", ""), entry.get("detail", ""), str(entry.get("enabled", true)),
			entry.get("disabled_reason", ""),
		])
	var signature := "\n".join(parts)
	if signature == _signature or _rows_box == null:
		return
	_signature = signature
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	if entries.is_empty():
		_show_empty()
		return
	for entry in entries:
		_rows_box.add_child(_build_row(entry))


func _show_empty() -> void:
	if _rows_box == null or _rows_box.get_child_count() > 0:
		return
	var empty_label := _make_label(tr("pending_empty"), FONT_SIZE)
	empty_label.modulate = DETAIL_MODULATE
	_rows_box.add_child(empty_label)


# Riga: 🎯 a sinistra (in alto), poi il nome e sotto il motivo, entrambi a capo se serve.
func _build_row(entry: Dictionary) -> Control:
	var enabled := bool(entry.get("enabled", true))
	var tooltip := String(entry["text"]) if enabled else "%s\n%s" % [entry["text"], entry.get("disabled_reason", "")]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var center_button := Button.new()
	center_button.text = CENTER_BUTTON_TEXT
	center_button.flat = true
	center_button.focus_mode = Control.FOCUS_NONE
	center_button.add_theme_font_size_override("font_size", FONT_SIZE)
	center_button.custom_minimum_size = Vector2(20, 0)
	center_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	center_button.disabled = not enabled
	center_button.tooltip_text = tr("pending_center_tooltip") if enabled else String(entry.get("disabled_reason", ""))
	center_button.pressed.connect(func(): entry_activated.emit(entry))
	row.add_child(center_button)
	# Il testo non è cliccabile (2026-10-07, richiesta utente): il gesto è solo il 🎯. Resta il tooltip.
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 0)
	row.add_child(text_box)
	var name_label := _make_label(String(entry.get("name", entry["text"])), FONT_SIZE)
	name_label.tooltip_text = tooltip
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	if not enabled:
		name_label.modulate = DISABLED_MODULATE
	text_box.add_child(name_label)
	var detail := String(entry.get("detail", ""))
	if detail != "":
		var detail_label := _make_label(detail, DETAIL_FONT_SIZE)
		detail_label.tooltip_text = tooltip
		detail_label.mouse_filter = Control.MOUSE_FILTER_PASS
		detail_label.modulate = DETAIL_MODULATE if enabled else DISABLED_MODULATE
		text_box.add_child(detail_label)
	return row


# Testo che va a capo: il pannello non si allarga mai (larghezza minima 0).
func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 0.0
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
