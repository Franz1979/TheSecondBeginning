class_name TerrainScatteredResourceInfoPanel
extends VBoxContainer

# RINOMINATO da StickLotInfoPanel (2026-09-15, richiesta utente — "cambia anche il nome perché non
# mostrerà solo stick... frutti, funghi, uova etc... tutti in questo info panel"): stesso file/
# stessa classe di sempre, nome allineato a TerrainScatteredResourceService (simulation/scripts/
# core/), il service che già calcola stick E pebble come UNA sola famiglia concettuale ("risorse
# sparse sul terreno, raccoglibili senza tagliare nulla") — questo pannello ne è la vetrina UI,
# destinata a crescere con lo stesso service man mano che copre nuove risorse (frutti/funghi/uova).
# Contenuto INVARIATO in questo passo (solo il nome cambia): show_stick_lot/stick_label/wood_label
# restano come sono, l'estensione a nuove risorse è un giro successivo.
#
# Corpo del pannello "terreno" di una microcella TREE dentro GameInfoTabs.selection_content
# (click-detection sul lotto, non su una pianta precisa, 2026-09-08, richiesta utente — vedi
# StickLotSelectorController) — istanziato dinamicamente da GameScene, stesso principio "muto" di
# StoneInfoPanel/VegetationInfoPanel: questo componente non conosce MicroCellRenderer/
# MacroCellState/GameScene, riceve solo dati già risolti. Nessun bottone azione — stesso motivo di
# StoneInfoPanel: nessun pickup/raccolta implementato in questo passo, puramente informativo.
#
# available_sticks è ESATTO per il singolo lotto cliccato (MacroCellState.stick_quantities,
# indicizzato per Vector2i).
#
# WoodLabel ("Legno: non ancora disponibile") tolta il 2026-10-04 (richiesta utente — task Cut): il tronco ora si
# ottiene tagliando gli alberi.

@onready var stick_label: Label = $StickLabel


func _ready() -> void:
	clear()


func show_stick_lot(available_sticks: int) -> void:
	visible = true
	stick_label.text = tr("stick_lot_available_here_label").format({"quantity": NumberFormatter.format_int(available_sticks)})


func clear() -> void:
	visible = false
