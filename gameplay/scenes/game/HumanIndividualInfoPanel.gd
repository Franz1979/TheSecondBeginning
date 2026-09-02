class_name HumanIndividualInfoPanel
extends VBoxContainer

# Corpo del pannello individuo dentro GameInfoTabs.selection_tab — stesso principio "muto" di
# VegetationInfoPanel (istanziato dinamicamente da GameScene, non pre-cablato in nessun .tscn di
# livello superiore): non conosce GameScene/selezione/HumanRules, riceve solo dati già risolti.
# Nessun tr(): stesso trattamento hardcoded di VegetationInfoPanel, nessuna CSV di traduzione
# esiste ancora. Nascosto di default (nessuna selezione all'apertura della scena).
#
# name/sex/età/age_band (Passo 1, 2026-09-01) + id/folk id/group id/mother id/father id/partner
# id (richiesta utente, 2026-09-02 — solo consultazione, nessuna interazione). strength resta
# fuori, non ancora richiesto.

@onready var name_label: Label = $NameLabel
@onready var sex_label: Label = $SexLabel
@onready var age_label: Label = $AgeLabel
@onready var id_label: Label = $IdLabel
@onready var mother_label: Label = $MotherLabel
@onready var father_label: Label = $FatherLabel
@onready var partner_label: Label = $PartnerLabel


func _ready() -> void:
	clear()


# Prende l'HumanIndividual intero (non piu' i soli name/sex, richiesta utente 2026-09-02: servono
# anche id/mother_id/father_id/partner_id/source_group_ref, tutti gia' sull'oggetto) — age/
# age_band restano calcolati dal chiamante (richiedono current_year/HumanRules, che questo
# pannello non conosce, stesso principio di prima).
func show_individual(individual: HumanIndividual, age: int, age_band: HumanTypes.AgeBand) -> void:
	visible = true
	name_label.text = "Name: " + individual.name
	sex_label.text = "Sex: " + ("Female" if individual.sex == HumanTypes.Sex.FEMALE else "Male")
	age_label.text = "Age: " + str(age) + " (" + HumanTypes.AgeBand.keys()[age_band].capitalize() + ")"

	var group := individual.source_group_ref
	var folk_id: int = group.folk_ref.id if group != null and group.folk_ref != null else -1
	var group_id: int = group.id if group != null else -1
	id_label.text = "ID: %d (Folk %s, Group %s)" % [individual.id, _format_id(folk_id), _format_id(group_id)]
	mother_label.text = "Mother ID: " + _format_id(individual.mother_id)
	father_label.text = "Father ID: " + _format_id(individual.father_id)
	partner_label.text = "Partner ID: " + _format_id(individual.partner_id)


func clear() -> void:
	visible = false


# Sentinella -1 (genitore/gruppo/partner sconosciuto o non applicabile, vedi HumanIndividual) resa
# come "—" invece del numero grezzo — poco leggibile per chi guarda il pannello, "-1" sembra un
# errore piu' che un "non applicabile".
func _format_id(value: int) -> String:
	return "—" if value < 0 else str(value)
