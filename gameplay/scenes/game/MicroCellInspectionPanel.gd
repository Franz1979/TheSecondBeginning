class_name MicroCellInspectionPanel
extends VBoxContainer

# Corpo del pannello "ispezione microcella" dentro GameInfoTabs.selection_content (2026-09-16,
# richiesta utente — doppio click sinistro) — STESSO pattern di VegetationInfoPanel/StoneInfoPanel/
# TerrainScatteredResourceInfoPanel: istanziato dinamicamente da GameScene, "muto" (riceve solo
# testo già risolto/tradotto dal chiamante, non conosce MacroCellState/TerrainScatteredResourceService/
# IndividualVegetationService). Nessun bottone azione — puramente informativo, nessuna Task
# assegnabile da qui (richiesta esplicita utente).
#
# RIVISTO 2026-09-16 (richiesta utente) — SOSTITUISCE MicroCellInspectionPopup.gd/.tscn (Window,
# rimossi): il contenuto va nella sidebar come ogni altra selezione, non in un popup separato — la
# selezione della cella deve appartenere alla STESSA mutua esclusione a 7 vie di vegetazione/
# edificio/individuo/corpo morto/sasso/lotto stick (vedi GameScene._select_microcell), non un canale
# indipendente.

@onready var content_label: Label = $ContentLabel


func _ready() -> void:
	clear()


# `lines` già risolte dal chiamante (tr()-ate, interpolate) — vedi GameScene._handle_microcell_
# inspection_double_click per la costruzione del contenuto. Il titolo (coordinate microcella) vive
# nell'header condiviso di GameInfoTabs (game_info_tabs.set_selection_title), STESSA convenzione già
# in uso per stone/stick_lot — non ripetuto qui dentro.
#
# `Array` generico, NON `Array[String]` (bugfix, 2026-09-16 — "Invalid type... does not have the
# same element type as the expected typed array argument"): `lines` attraversa un Dictionary non
# tipizzato (GameScene.selected_microcell) prima di arrivare qui, e un ramo del chiamante costruiva
# un array letterale `[tr(...)]` (generico per costruzione in GDScript, mai `Array[String]` senza
# un'annotazione esplicita) mentre l'altro ramo usava una variabile locale dichiarata `Array[String]`
# — stesso contenuto (solo stringhe), tipo runtime diverso, String.join() non fa distinzione.
func show_inspection(lines: Array) -> void:
	visible = true
	content_label.text = "\n".join(lines)


func clear() -> void:
	visible = false
