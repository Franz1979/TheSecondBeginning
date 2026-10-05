class_name StoneInfoPanel
extends VBoxContainer

# Corpo del pannello STONE dentro GameInfoTabs.selection_content (click-detection su una singola
# posizione stone, 2026-09-08, richiesta utente — vedi StoneSelectorController) — istanziato
# dinamicamente da GameScene (non pre-cablato nel .tscn di GameInfoPanel), stesso principio "muto"
# di VegetationInfoPanel/BuildingInfoPanel: questo componente non conosce MicroCellRenderer/
# MacroCellState/GameScene, riceve solo dati già risolti. Nessun bottone azione — a differenza di
# VegetationInfoPanel (CutButton), STONE non ha ancora nessuna azione implementata (nessun
# pickup/consumo, richiesta esplicita di non implementarlo in questo passo): puramente
# informativo.
#
# Una riga (RIVISTO 2026-10-05, richiesta utente — Quarry): pietra estraibile, cioè rimasta, di questa roccia
# (RockStoneService); il tipo "Roccia" è nel titolo della scheda. Valore già risolto da GameScene._refresh_stone_panel.

@onready var rock_stone_label: Label = $RockStoneLabel


func _ready() -> void:
	clear()


func show_stone(rock_stone_quantity: int) -> void:
	visible = true
	rock_stone_label.text = tr("stone_rock_label").format({"quantity": NumberFormatter.format_int(rock_stone_quantity)})


func clear() -> void:
	visible = false
