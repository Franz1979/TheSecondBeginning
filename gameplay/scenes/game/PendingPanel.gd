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
# Voce: {"key": String univoca, "text": String, "enabled": bool, "disabled_reason": String, ...dati per il chiamante}.

signal entry_activated(entry: Dictionary)

const CENTER_BUTTON_TEXT := "🎯"
const FONT_SIZE: int = 10
# Testo di dettaglio accanto al nome: come le righe di stato del cassetto (TaskAssignmentPanel.LIST_FONT_SIZE - 2).
const DETAIL_FONT_SIZE: int = 9
const DISABLED_MODULATE := Color(1, 1, 1, 0.45)

var _signature: String = "-"
var _empty_label: Label = null


func _ready() -> void:
	add_theme_constant_override("separation", 1)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func set_entries(entries: Array[Dictionary]) -> void:
	var parts: PackedStringArray = []
	for entry in entries:
		parts.append("%s|%s|%s|%s" % [entry["key"], entry["text"], str(entry.get("enabled", true)), entry.get("disabled_reason", "")])
	var signature := "\n".join(parts)
	if signature == _signature:
		return
	_signature = signature
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if entries.is_empty():
		_empty_label = _make_label(tr("pending_empty"))
		add_child(_empty_label)
		return
	for entry in entries:
		add_child(_build_row(entry))


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
	center_button.disabled = not enabled
	center_button.tooltip_text = tr("pending_center_tooltip") if enabled else String(entry.get("disabled_reason", ""))
	center_button.pressed.connect(func(): entry_activated.emit(entry))
	row.add_child(center_button)
	# Il testo non è cliccabile (2026-10-07, richiesta utente): il gesto è solo il 🎯. Resta il tooltip.
	# Voce con "name" e "name_detail" (2026-10-07, corpi da seppellire): il nome a dimensione normale e accanto, più in
	# piccolo, il testo di dettaglio, che si accorcia lui con i puntini se manca lo spazio. Altrimenti il testo intero.
	var name_detail := String(entry.get("name_detail", ""))
	var label := _make_label(String(entry.get("name", entry["text"])) if name_detail != "" else String(entry["text"]))
	label.tooltip_text = tooltip
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	if not enabled:
		label.modulate = DISABLED_MODULATE
	row.add_child(label)
	if name_detail != "":
		label.size_flags_horizontal = Control.SIZE_FILL
		label.clip_text = false
		label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		var detail_label := _make_label(name_detail)
		detail_label.add_theme_font_size_override("font_size", DETAIL_FONT_SIZE)
		detail_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		detail_label.tooltip_text = tooltip
		detail_label.mouse_filter = Control.MOUSE_FILTER_PASS
		detail_label.modulate = label.modulate
		row.add_child(detail_label)
	return row


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
