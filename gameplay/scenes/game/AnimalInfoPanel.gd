class_name AnimalInfoPanel
extends VBoxContainer

# Pannello informativo di un individuo animale selezionato (2026-09-25, richiesta utente) — sibling
# nella SelectionTab di GameInfoTabs, stesso principio "componente muto" di StoneInfoPanel/
# VegetationInfoPanel: riceve testi già risolti da GameScene (_refresh_animal_panel), non conosce
# renderer, regole né popolazioni. Specie e fascia d'età per tutti; per gli animali seguiti per individuo
# (WildAnimal, 2026-10-28 lupi L1b) anche sesso, anni, riproduttore e aggressività come barra (show_wild_details).

# Pulsanti di debug dell'animale domestico (cane, passo 4): ferirlo e invecchiarlo per provare, mai in una build pulita.
signal debug_wound_requested
signal debug_add_year_requested

@onready var species_label: Label = $SpeciesLabel
@onready var age_band_label: Label = $AgeBandLabel
@onready var wild_details: VBoxContainer = $WildDetails
@onready var sex_label: Label = $WildDetails/SexLabel
@onready var age_years_label: Label = $WildDetails/AgeYearsLabel
@onready var breeder_label: Label = $WildDetails/BreederLabel
@onready var aggression_label: Label = $WildDetails/AggressionRow/AggressionLabel
@onready var aggression_bar: ProgressBar = $WildDetails/AggressionRow/AggressionBar

var _debug_row: HBoxContainer = null


func _ready() -> void:
	aggression_label.text = tr("animal_aggression_label")
	if DebugLogging.ENABLED:
		_debug_row = HBoxContainer.new()
		wild_details.add_child(_debug_row)
		_add_debug_button("Ferisci", debug_wound_requested)
		_add_debug_button("+1 anno", debug_add_year_requested)
	clear()


func _add_debug_button(text: String, pressed_signal: Signal) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(func() -> void: pressed_signal.emit())
	_debug_row.add_child(button)


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
	if _debug_row != null:
		_debug_row.visible = false


# Animale domestico (2026-11-03, cane passo 3): sesso, anni e salute (passo 4, 0..1) nella riga della barra; niente
# riproduttore né aggressività.
func show_domestic_details(is_male: bool, age_years: int, health_ratio: float) -> void:
	wild_details.visible = true
	sex_label.text = tr("animal_sex_label").format({"sex": tr("animal_sex_male" if is_male else "animal_sex_female")})
	age_years_label.text = tr("animal_age_years_label").format({"years": age_years})
	breeder_label.visible = false
	aggression_label.text = tr("individual_health_label")
	aggression_bar.value = clampf(health_ratio * 100.0, 0.0, 100.0)
	if _debug_row != null:
		_debug_row.visible = true


func clear() -> void:
	visible = false
