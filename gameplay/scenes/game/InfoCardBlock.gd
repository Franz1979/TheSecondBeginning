class_name InfoCardBlock
extends PanelContainer

# Scheda del tipo (2026-10-05, estratta da BuildingInfoPanel senza cambiarne l'aspetto): riquadro con lo stesso stile dei
# riquadri dei parametri vitali del pannello dell'individuo (INFO_BOX_COLOR, angoli 4, margini 6), una voce per riga.
# Righe {"text": String, "indent": bool, "wrap": bool}: di base una riga sola che taglia con i puntini (non allarga mai
# il pannello; il testo intero va nel tooltip dell'icona ℹ), rientrata se "indent"; "wrap" = va a capo (descrizioni).
# Usata dalla "i" degli edifici (BuildingInfoPanel) e da quella del tipo dei pipottini (HumanIndividualInfoPanel).

const INFO_BOX_COLOR := Color(0.28, 0.42, 0.6, 1)
const INFO_BOX_MARGIN: int = 6
const INFO_ROW_INDENT: int = 10
const INFO_TOOLTIP_INDENT := "    "
const ROW_FONT_SIZE: int = 10

var _rows: VBoxContainer = null


func _init() -> void:
	var box_style := StyleBoxFlat.new()
	box_style.bg_color = INFO_BOX_COLOR
	box_style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", box_style)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, INFO_BOX_MARGIN)
	add_child(margin)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 0)
	margin.add_child(_rows)


# Sostituisce le righe e ritorna il testo per il tooltip dell'icona (una riga per voce, rientrate con spazi).
func set_rows(rows: Array[Dictionary]) -> String:
	var tooltip_lines: Array[String] = []
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for row in rows:
		var indented: bool = bool(row.get("indent", false))
		tooltip_lines.append((INFO_TOOLTIP_INDENT if indented else "") + String(row["text"]))
		var label := Label.new()
		label.text = String(row["text"])
		if bool(row.get("wrap", false)):
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		else:
			label.clip_text = true
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
		if indented:
			var indent := MarginContainer.new()
			indent.add_theme_constant_override("margin_left", INFO_ROW_INDENT)
			indent.add_child(label)
			_rows.add_child(indent)
		else:
			_rows.add_child(label)
	return "\n".join(tooltip_lines)
