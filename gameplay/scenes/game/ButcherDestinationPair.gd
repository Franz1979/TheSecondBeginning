class_name ButcherDestinationPair
extends HBoxContainer

# Coppia di pulsanti della destinazione della caccia (2026-10-19, richiesta utente — due pulsanti indipendenti, carne e
# pelli, invece di uno con due sezioni): un ButcherDestinationButton per tipo, affiancati. Stessa interfaccia del pulsante
# singolo di prima, così barra dei comandi, popup della Caccia, cassetto e cassetto Scorte la usano senza altri cambi:
# set_destination con la voce attuale e tutte le opzioni (ognuno prende le sue), `destination_chosen` con la coppia intera.

signal destination_chosen(destination: String)

var _meat_button: ButcherDestinationButton = null
var _hide_button: ButcherDestinationButton = null

# Chiave tr() del tooltip dei due pulsanti ({name} = tipo e destinazione).
var tooltip_key: String = "command_bar_butcher_destination_tooltip":
	set(value):
		tooltip_key = value
		if _meat_button != null:
			_meat_button.tooltip_key = value
			_hide_button.tooltip_key = value


func _init() -> void:
	add_theme_constant_override("separation", 4)
	_meat_button = ButcherDestinationButton.new()
	_meat_button.kind = ButcherDestinationService.KIND_MEAT
	_hide_button = ButcherDestinationButton.new()
	_hide_button.kind = ButcherDestinationService.KIND_HIDE
	for button in [_meat_button, _hide_button]:
		button.tooltip_key = tooltip_key
		button.destination_chosen.connect(func(destination: String) -> void: destination_chosen.emit(destination))
		add_child(button)
	visible = false


# Stessi argomenti di ButcherDestinationButton.set_destination. Ritorna true se la visibilità è cambiata.
func set_destination(is_shown: bool, current: Dictionary, options: Array[Dictionary]) -> bool:
	var visibility_changed := visible != is_shown
	visible = is_shown
	_meat_button.set_destination(is_shown, current, options)
	_hide_button.set_destination(is_shown, current, options)
	return visibility_changed
