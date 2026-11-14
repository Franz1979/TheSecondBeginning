class_name PendingPanel
extends VBoxContainer

# Scheda "In sospeso" dell'info panel (2026-10-04, richiesta utente): elenco delle cose ferme — corpi non sepolti che
# nessuno ha in carico, poi lavori senza nessuno assegnato. Componente "muto" come gli altri pannelli: riceve le voci
# già calcolate e ordinate da GameScene (set_entries) e segnala solo il clic (entry_activated); creato in codice.
#
# Riga sul modello della lista degli abitanti: a sinistra il tasto 🎯, poi il testo su una riga, troncato con i puntini
# (intero nel tooltip), così la scheda non allarga mai il pannello. Solo il 🎯 centra e seleziona (dal 2026-10-07 il
# testo non è più cliccabile). Voce che non si può centrare: riga spenta, spiegazione nel tooltip. Le righe vengono rifatte solo quando cambiano davvero (per chiave).
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
# Righe per chiave della voce: {"row": Control, "signature": String}; voce attuale di ogni chiave (il 🎯 manda questa).
var _rows_by_key: Dictionary = {}
var _row_entries: Dictionary = {}
var _empty_label: Label = null


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


# Scheda chiusa (2026-11-14, richiesta utente): le righe non si fanno se il pannello non si vede (numero e lampeggio della
# linguetta li aggiorna GameScene comunque); l'ultimo elenco arrivato si mette in righe quando la scheda torna visibile.
var _waiting_entries: Variant = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree() and _waiting_entries != null:
		var waiting: Array[Dictionary] = _waiting_entries
		_waiting_entries = null
		set_entries(waiting)


func set_entries(entries: Array[Dictionary]) -> void:
	if not is_visible_in_tree():
		_waiting_entries = entries
		return
	_waiting_entries = null
	var parts: PackedStringArray = []
	var row_signatures: Array[String] = []
	for entry in entries:
		var row_signature := "%s|%s|%s|%s|%s|%s" % [
			entry["key"], entry["text"], entry.get("name", ""), entry.get("detail", ""), str(entry.get("enabled", true)),
			entry.get("disabled_reason", ""),
		]
		row_signatures.append(row_signature)
		parts.append(row_signature)
	var signature := "
".join(parts)
	if signature == _signature or _rows_box == null:
		return
	_signature = signature
	if entries.is_empty():
		_clear_rows()
		_show_empty()
		return
	if _empty_label != null:
		_rows_box.remove_child(_empty_label)
		_empty_label.queue_free()
		_empty_label = null
	# Righe tenute per chiave (2026-11-14, scattini — ~16 ms a ricreare tutte le righe per un "Restano 3 gg" diventato
	# "2 gg"): si rifà solo la riga cambiata, le nuove si aggiungono, le sparite si tolgono, poi l'ordine.
	var kept: Dictionary = {}
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var key := String(entry["key"])
		_row_entries[key] = entry
		var existing: Variant = _rows_by_key.get(key)
		if existing != null and String(existing["signature"]) == row_signatures[i]:
			kept[key] = existing
			continue
		if existing != null:
			_rows_box.remove_child(existing["row"])
			(existing["row"] as Control).queue_free()
		var row := _build_row(entry)
		_rows_box.add_child(row)
		kept[key] = {"row": row, "signature": row_signatures[i]}
	for key in _rows_by_key.keys():
		if not kept.has(key):
			_rows_box.remove_child(_rows_by_key[key]["row"])
			(_rows_by_key[key]["row"] as Control).queue_free()
			_row_entries.erase(key)
	_rows_by_key = kept
	for i in range(entries.size()):
		var row: Control = kept[String(entries[i]["key"])]["row"]
		if row.get_index() != i:
			_rows_box.move_child(row, i)


func _clear_rows() -> void:
	for key in _rows_by_key.keys():
		_rows_box.remove_child(_rows_by_key[key]["row"])
		(_rows_by_key[key]["row"] as Control).queue_free()
	_rows_by_key.clear()
	_row_entries.clear()


func _show_empty() -> void:
	if _rows_box == null or _empty_label != null:
		return
	_empty_label = _make_label(tr("pending_empty"), FONT_SIZE)
	_empty_label.modulate = DETAIL_MODULATE
	_rows_box.add_child(_empty_label)


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
	center_button.tooltip_text = TooltipText.wrap(tr("pending_center_tooltip") if enabled else String(entry.get("disabled_reason", "")))
	var entry_key := String(entry["key"])
	center_button.pressed.connect(func(): entry_activated.emit(_row_entries.get(entry_key, entry)))
	row.add_child(center_button)
	# Il testo non è cliccabile (2026-10-07, richiesta utente): il gesto è solo il 🎯. Resta il tooltip.
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 0)
	row.add_child(text_box)
	var name_label := _make_label(String(entry.get("name", entry["text"])), FONT_SIZE)
	name_label.tooltip_text = TooltipText.wrap(tooltip)
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	if not enabled:
		name_label.modulate = DISABLED_MODULATE
	text_box.add_child(name_label)
	var detail := String(entry.get("detail", ""))
	if detail != "":
		var detail_label := _make_label(detail, DETAIL_FONT_SIZE)
		detail_label.tooltip_text = TooltipText.wrap(tooltip)
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
