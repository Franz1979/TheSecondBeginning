class_name TooltipButton
extends Button

# Tooltip a due righe: titolo (tooltip_text, invariato) + descrizione opzionale più piccola
# sotto, per bottoni-icona il cui solo nome non basta a spiegare cosa fanno (es. i toggle
# mostra/nascondi in MacroCellScene). Se tooltip_description resta vuota, _make_custom_tooltip
# ritorna null e Godot mostra il tooltip di default a una riga — nessuna differenza per i
# bottoni che non la impostano.
var tooltip_description: String = ""
# Tooltip costruito da chi configura il bottone (2026-10-07, es. BuildingCostTooltip): Callable(for_text: String) ->
# Control, chiamato a ogni comparsa del tooltip; vince su tooltip_description. tooltip_text deve restare non vuoto.
var tooltip_builder: Callable = Callable()

func _make_custom_tooltip(for_text: String) -> Object:
	if tooltip_builder.is_valid():
		return tooltip_builder.call(for_text)
	if tooltip_description.is_empty():
		return null

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var title_label := Label.new()
	title_label.text = for_text
	box.add_child(title_label)

	var description_label := Label.new()
	description_label.text = tooltip_description
	description_label.add_theme_font_size_override("font_size", 11)
	description_label.modulate = Color(1, 1, 1, 0.75)
	box.add_child(description_label)

	return box
