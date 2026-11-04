class_name AnimalInfoPanel
extends VBoxContainer

# Pannello informativo di un individuo animale selezionato (2026-09-25, richiesta utente) — sibling
# nella SelectionTab di GameInfoTabs, stesso principio "componente muto" di StoneInfoPanel/
# VegetationInfoPanel: riceve testi già risolti da GameScene (_refresh_animal_panel), non conosce
# renderer, regole né popolazioni. Specie e fascia d'età per tutti; per gli animali seguiti per individuo
# (WildAnimal, 2026-10-28 lupi L1b) anche sesso, anni, riproduttore e aggressività come barra (show_wild_details).

# Macella (cane, passo 7): ordine del giocatore su un animale domestico. GameScene decide lista o mirino.
signal slaughter_requested
signal slaughter_assign_requested
signal slaughter_cancel_requested
signal butcher_destination_chosen(destination: String)

@onready var species_label: Label = $SpeciesLabel
@onready var age_band_label: Label = $AgeBandLabel
@onready var wild_details: VBoxContainer = $WildDetails
@onready var sex_label: Label = $WildDetails/SexLabel
@onready var age_years_label: Label = $WildDetails/AgeYearsLabel
@onready var breeder_label: Label = $WildDetails/BreederLabel
@onready var aggression_label: Label = $WildDetails/AggressionRow/AggressionLabel
@onready var aggression_bar: ProgressBar = $WildDetails/AggressionRow/AggressionBar

var _slaughter_row: HBoxContainer = null
var _slaughter_button: Button = null
var _slaughter_assign_button: Button = null
var _slaughter_cancel_button: Button = null
var _destination_pair: ButcherDestinationPair = null


func _ready() -> void:
	aggression_label.text = tr("animal_aggression_label")
	_build_slaughter_row()
	clear()


func _build_slaughter_row() -> void:
	_slaughter_row = HBoxContainer.new()
	wild_details.add_child(_slaughter_row)
	_slaughter_button = _add_slaughter_button("animal_slaughter_button", "animal_slaughter_tooltip", slaughter_requested)
	_slaughter_assign_button = _add_slaughter_button("building_assign_production_worker_button", "animal_slaughter_assign_tooltip", slaughter_assign_requested)
	_slaughter_cancel_button = _add_slaughter_button("animal_slaughter_cancel_button", "animal_slaughter_cancel_tooltip", slaughter_cancel_requested)
	_destination_pair = ButcherDestinationPair.new()
	_destination_pair.tooltip_key = "animal_slaughter_destination_tooltip"
	_destination_pair.destination_chosen.connect(func(destination: String) -> void: butcher_destination_chosen.emit(destination))
	_slaughter_row.add_child(_destination_pair)


func _add_slaughter_button(text_key: String, tooltip_key: String, pressed_signal: Signal) -> Button:
	var button := Button.new()
	button.text = tr(text_key)
	button.tooltip_text = TooltipText.wrap(tr(tooltip_key))
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void: pressed_signal.emit())
	_slaughter_row.add_child(button)
	return button


# has_details: righe degli animali seguiti per individuo, riempite subito dopo da show_wild_details o show_domestic_details.
# Non si nascondono e rimostrano a ogni aggiornamento: un pulsante nascosto anche per un istante perde il clic in corso.
func show_animal(species_text: String, age_band_text: String, has_details: bool = false) -> void:
	visible = true
	species_label.text = tr("animal_species_label").format({"species": species_text})
	age_band_label.text = tr("animal_age_band_label").format({"age_band": age_band_text})
	wild_details.visible = has_details


# Aggressività 0..100, mostrata solo come barra (nessun numero, richiesta utente 2026-10-28).
func show_wild_details(is_male: bool, age_years: int, is_breeder: bool, aggression: float) -> void:
	wild_details.visible = true
	sex_label.text = tr("animal_sex_label").format({"sex": tr("animal_sex_male" if is_male else "animal_sex_female")})
	age_years_label.text = tr("animal_age_years_label").format({"years": age_years})
	breeder_label.text = tr("animal_breeder_label")
	breeder_label.visible = is_breeder
	aggression_label.text = tr("animal_aggression_label")
	aggression_bar.value = clampf(aggression, 0.0, 100.0)
	_slaughter_row.visible = false


# Animale domestico (2026-11-03, cane passo 3): sesso, anni e salute (passo 4, 0..1) nella riga della barra; niente
# riproduttore né aggressività.
func show_domestic_details(is_male: bool, age_years: int, health_ratio: float) -> void:
	wild_details.visible = true
	sex_label.text = tr("animal_sex_label").format({"sex": tr("animal_sex_male" if is_male else "animal_sex_female")})
	age_years_label.text = tr("animal_age_years_label").format({"years": age_years})
	breeder_label.visible = false
	aggression_label.text = tr("individual_health_label")
	aggression_bar.value = clampf(health_ratio * 100.0, 0.0, 100.0)
	_slaughter_row.visible = true


# Quali pulsanti di Macella si vedono (passo 7). Solo .visible, mai ricreati: l'aggiornamento periodico non perde i clic.
func show_slaughter_state(can_order: bool, can_assign: bool, can_cancel: bool) -> void:
	_slaughter_button.visible = can_order
	_slaughter_assign_button.visible = can_assign
	_slaughter_cancel_button.visible = can_cancel


func set_butcher_destination(current: Dictionary, options: Array[Dictionary]) -> void:
	_destination_pair.set_destination(true, current, options)


func clear() -> void:
	visible = false
