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
# Due granularità DELIBERATAMENTE etichettate in modo distinto (richiesta esplicita dell'utente,
# per evitare ambiguità tra le due): pebble_quantity è ESATTO per la singola posizione cliccata
# (MacroCellState.pebble_quantities, indicizzato per Vector2i); zone_stone_quantity è l'aggregato
# dell'INTERA macrocella (MacroCellState.resource_quantity[ROCK]), mostrato solo come contesto —
# mai presentato come se fosse un valore della singola posizione.

@onready var pebble_label: Label = $PebbleLabel
@onready var zone_stone_label: Label = $ZoneStoneLabel


func _ready() -> void:
	clear()


func show_stone(pebble_quantity: int, zone_stone_quantity: int) -> void:
	visible = true
	pebble_label.text = tr("stone_pebble_here_label").format({"quantity": NumberFormatter.format_int(pebble_quantity)})
	zone_stone_label.text = tr("stone_zone_aggregate_label").format({"quantity": NumberFormatter.format_int(zone_stone_quantity)})


func clear() -> void:
	visible = false
