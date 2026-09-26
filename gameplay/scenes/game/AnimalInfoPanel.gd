class_name AnimalInfoPanel
extends VBoxContainer

# Pannello informativo di un individuo animale selezionato (2026-09-25, richiesta utente) — sibling
# nella SelectionTab di GameInfoTabs, stesso principio "componente muto" di StoneInfoPanel/
# VegetationInfoPanel: riceve testi già risolti da GameScene (_refresh_animal_panel), non conosce
# renderer, regole né popolazioni. Per ora solo specie e fascia d'età.

@onready var species_label: Label = $SpeciesLabel
@onready var age_band_label: Label = $AgeBandLabel


func _ready() -> void:
	clear()


func show_animal(species_text: String, age_band_text: String) -> void:
	visible = true
	species_label.text = tr("animal_species_label").format({"species": species_text})
	age_band_label.text = tr("animal_age_band_label").format({"age_band": age_band_text})


func clear() -> void:
	visible = false
