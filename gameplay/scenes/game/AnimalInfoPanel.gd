class_name AnimalInfoPanel
extends VBoxContainer

# Pannello informativo di un individuo animale selezionato (2026-09-25, richiesta utente) — sibling
# nella SelectionTab di GameInfoTabs, stesso principio "componente muto" di StoneInfoPanel/
# VegetationInfoPanel: riceve testi già risolti da GameScene (_refresh_animal_panel), non conosce
# renderer, regole né popolazioni. Specie e fascia d'età per tutti; per gli animali seguiti per individuo
# (WildAnimal, 2026-10-28 lupi L1b) anche sesso, anni, riproduttore e aggressività come barra (show_wild_details).

@onready var species_label: Label = $SpeciesLabel
@onready var age_band_label: Label = $AgeBandLabel
@onready var wild_details: VBoxContainer = $WildDetails
@onready var sex_label: Label = $WildDetails/SexLabel
@onready var age_years_label: Label = $WildDetails/AgeYearsLabel
@onready var breeder_label: Label = $WildDetails/BreederLabel
@onready var aggression_label: Label = $WildDetails/AggressionRow/AggressionLabel
@onready var aggression_bar: ProgressBar = $WildDetails/AggressionRow/AggressionBar


func _ready() -> void:
	aggression_label.text = tr("animal_aggression_label")
	clear()


# Nasconde le righe degli animali seguiti per individuo: le rimostra show_wild_details, chiamata subito dopo.
func show_animal(species_text: String, age_band_text: String) -> void:
	visible = true
	species_label.text = tr("animal_species_label").format({"species": species_text})
	age_band_label.text = tr("animal_age_band_label").format({"age_band": age_band_text})
	wild_details.visible = false


# Aggressività 0..100, mostrata solo come barra (nessun numero, richiesta utente 2026-10-28).
func show_wild_details(is_male: bool, age_years: int, is_breeder: bool, aggression: float) -> void:
	wild_details.visible = true
	sex_label.text = tr("animal_sex_label").format({"sex": tr("animal_sex_male" if is_male else "animal_sex_female")})
	age_years_label.text = tr("animal_age_years_label").format({"years": age_years})
	breeder_label.text = tr("animal_breeder_label")
	breeder_label.visible = is_breeder
	aggression_bar.value = clampf(aggression, 0.0, 100.0)


func clear() -> void:
	visible = false
