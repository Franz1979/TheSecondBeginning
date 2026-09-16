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
# Una sola granularità (RIVISTO 2026-09-16, richiesta utente — "se clicco singolo su stone mi esce
# sassi qui e pietra nella zona, togli sassi qui"): il click SINGOLO mostra solo l'aggregato di
# ZONA (MacroCellState.resource_quantity[ROCK]) — la quantità ESATTA della singola posizione
# cliccata (MacroCellState.pebble_quantities) resta comunque visibile, ma SOLO tramite l'ispezione
# a DOPPIO click (MicroCellInspectionPanel, che la mostra già tra i candidati raccoglibili) — due
# gesti diversi, due domande diverse ("quanta pietra c'è in questa zona" vs "cosa raccolgo qui"),
# non più sovrapposte nello stesso pannello.

@onready var zone_stone_label: Label = $ZoneStoneLabel


func _ready() -> void:
	clear()


func show_stone(zone_stone_quantity: int) -> void:
	visible = true
	zone_stone_label.text = tr("stone_zone_aggregate_label").format({"quantity": NumberFormatter.format_int(zone_stone_quantity)})


func clear() -> void:
	visible = false
