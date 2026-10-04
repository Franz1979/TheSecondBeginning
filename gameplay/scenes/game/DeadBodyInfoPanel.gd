class_name DeadBodyInfoPanel
extends VBoxContainer

# Corpo del pannello corpo morto dentro GameInfoTabs.selection_content — stesso principio "muto",
# stesso stile "sempre presente, mostra/nasconde" di HumanIndividualInfoPanel/VegetationInfoPanel/
# BuildingInfoPanel (Step 6 del sistema oggetti-scaduti, 2026-09-05): non conosce GameScene/
# ExpiredObjectCalculator/game_data/expired_objects, riceve solo dati già risolti dal chiamante.
# Riga di stato della sepoltura dal 2026-10-04 (vedi bury_status_label; il comando è il click destro sul corpo). Label tr()-wrapped (richiesta utente 2026-09-06, insieme a
# VegetationInfoPanel/HumanIndividualInfoPanel): solo le chiavi, nessuna riga aggiunta ancora a
# strings.csv/strings.it.translation.
#
# days_remaining arriva già calcolato dal chiamante (GameScene, via ExpiredObjectCalculator.
# get_days_remaining) — "calcolato al volo" per il chiamante, non per questo pannello: stesso
# principio già seguito per age/age_band in HumanIndividualInfoPanel.show_individual, mai
# ricalcolato qui dentro.

@onready var sex_label: Label = $SexLabel
@onready var age_label: Label = $AgeLabel
@onready var cause_label: Label = $CauseLabel
@onready var days_remaining_label: Label = $DaysRemainingLabel
# Stato della sepoltura (2026-10-04, richiesta utente): "Da seppellire" o "Sepoltura assegnata a X", già tradotto dal
# chiamante. Una riga tagliata con i puntini (testo intero nel tooltip): il pannello non si allarga mai.
@onready var bury_status_label: Label = $BuryStatusLabel


func _ready() -> void:
	clear()


func show_dead_body(
	sex: HumanTypes.Sex, age_at_death: int, cause: DeathTypes.DeathCause, days_remaining: int, bury_status: String = ""
) -> void:
	bury_status_label.text = bury_status
	bury_status_label.tooltip_text = bury_status
	visible = true
	# Nome NON mostrato qui — vive nel titolo condiviso di GameInfoTabs.SelectionTab
	# ("Name: ..."), stesso posto/convenzione già usata per gli individui vivi (vedi GameScene.
	# _refresh_dead_body_panel), non duplicato dentro questo pannello.
	sex_label.text = tr("sex_label").format({"sex": tr("sex_female") if sex == HumanTypes.Sex.FEMALE else tr("sex_male")})
	age_label.text = tr("dead_body_age_label").format({"age": age_at_death})
	cause_label.text = tr("dead_body_cause_label").format({"cause": String(DeathTypes.DeathCause.keys()[cause]).capitalize()})
	days_remaining_label.text = tr("dead_body_decomposes_label").format({"days": days_remaining})


func clear() -> void:
	visible = false
