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
# WoodLabel (2026-09-09, richiesta utente — sostituisce ZoneWoodLabel/zone_wood_quantity, rimosso:
# (1) il dato era SBAGLIATO per questo contesto — MacroCellState.resource_quantity[TREE] è
# l'aggregato di TUTTA la macrocella, non ha alcun legame col lotto singolo cliccato, leggeva come
# "legno di questo lotto" mentre non lo era; (2) il testo lungo interpolato ("Legno nella zona (non
# ancora disponibile): {quantity}", nessun autowrap) costringeva l'intero pannello laterale ad
# allargarsi per contenerlo — vedi anche StickLabel sotto, ora con autowrap_mode per lo stesso
# motivo). Nessun valore da mostrare finché "wood" non è una vera risorsa (nessun .tres/quantità
# tracciata, vedi hut.tres.required_materials) — solo la chiave tr(), testo statico auto-esplicativo
# ("Legno: non ancora disponibile"), niente da interpolare finché non esisterà un dato reale.

@onready var stick_label: Label = $StickLabel
@onready var wood_label: Label = $WoodLabel


func _ready() -> void:
	clear()


func show_stick_lot(available_sticks: int) -> void:
	visible = true
	stick_label.text = tr("stick_lot_available_here_label").format({"quantity": NumberFormatter.format_int(available_sticks)})
	wood_label.text = tr("stick_lot_wood_label")


func clear() -> void:
	visible = false
