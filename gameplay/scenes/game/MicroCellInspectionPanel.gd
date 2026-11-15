class_name MicroCellInspectionPanel
extends VBoxContainer

# Corpo del pannello "ispezione microcella" dentro GameInfoTabs.selection_content (2026-09-16,
# richiesta utente — doppio click sinistro) — STESSO pattern di VegetationInfoPanel/StoneInfoPanel/
# TerrainScatteredResourceInfoPanel: istanziato dinamicamente da GameScene, "muto" (riceve solo
# testo già risolto/tradotto dal chiamante, non conosce MacroCellState/TerrainScatteredResourceService/
# IndividualVegetationService). Nessuna Task assegnabile a un pipottino da qui (richiesta esplicita utente); dal
# 2026-11-15 un solo pulsante, "Rimuovi tutto", che è un ordine al villaggio (lista dei lavori), vedi set_clear_action.
#
# RIVISTO 2026-09-16 (richiesta utente) — SOSTITUISCE MicroCellInspectionPopup.gd/.tscn (Window,
# rimossi): il contenuto va nella sidebar come ogni altra selezione, non in un popup separato — la
# selezione della cella deve appartenere alla STESSA mutua esclusione a 7 vie di vegetazione/
# edificio/individuo/corpo morto/sasso/lotto stick (vedi GameScene._select_microcell), non un canale
# indipendente.

@onready var content_label: Label = $ContentLabel

# Riga speciale di `lines` (2026-11-07, richiesta utente): al suo posto un tratteggio leggero (DashedSeparator) tra le
# sezioni (vegetazione | risorse raccoglibili | uccelli). Mai mostrata come testo.
const SEPARATOR_LINE := "\u0001separator"

# Separatori ed etichette aggiunte dopo ContentLabel, rifatte a ogni show_inspection.
var _extra_nodes: Array[Node] = []

# "Rimuovi tutto" (2026-11-15, richiesta utente — ClearOrderService): unico pulsante del pannello, un ordine al villaggio
# che passa dalla lista dei lavori. GameScene decide se mostrarlo e cosa scrive (set_clear_action); qui solo il segnale.
signal clear_toggled(marked: bool)
const CLEAR_ACTION_NONE := ""
const CLEAR_ACTION_MARK := "mark"
const CLEAR_ACTION_UNMARK := "unmark"
# Pulsante a icona come Demolisci del pannello edificio (2026-11-15, richiesta utente): stessa misura (il 🎯 col tema di
# base), IconButtonStyle e un BuildingCommandIcon a tutto riquadro meno CLEAR_ICON_INSET, in una riga in fondo.
const CLEAR_ICON_SIZE_PROBE_TEXT := "🎯"
const CLEAR_ICON_INSET: float = 4.0
var _clear_status_label: Label
var _clear_row: HBoxContainer
var _clear_button: Button
var _clear_icon: BuildingCommandIcon
var _clear_action: String = CLEAR_ACTION_NONE


func _ready() -> void:
	_clear_status_label = Label.new()
	_clear_status_label.add_theme_font_size_override("font_size", 11)
	_clear_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_clear_status_label)
	_clear_row = HBoxContainer.new()
	add_child(_clear_row)
	var probe := Button.new()
	probe.text = CLEAR_ICON_SIZE_PROBE_TEXT
	add_child(probe)
	var button_size := probe.get_combined_minimum_size()
	remove_child(probe)
	probe.free()
	_clear_button = Button.new()
	_clear_button.custom_minimum_size = button_size
	_clear_button.focus_mode = Control.FOCUS_NONE
	IconButtonStyle.apply(_clear_button)
	_clear_icon = BuildingCommandIcon.new()
	_clear_button.add_child(_clear_icon)
	_clear_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_clear_icon.offset_left = CLEAR_ICON_INSET
	_clear_icon.offset_top = CLEAR_ICON_INSET
	_clear_icon.offset_right = -CLEAR_ICON_INSET
	_clear_icon.offset_bottom = -CLEAR_ICON_INSET
	_clear_button.pressed.connect(func() -> void: clear_toggled.emit(_clear_action == CLEAR_ACTION_MARK))
	_clear_row.add_child(_clear_button)
	set_clear_action(CLEAR_ACTION_NONE)
	clear()


# `action`: CLEAR_ACTION_MARK ("Rimuovi tutto"), CLEAR_ACTION_UNMARK ("Annulla rimozione") o CLEAR_ACTION_NONE (nascosto).
# `status`: riga sopra il pulsante ("" = nessuna). `rock`: icona e testi della roccia (piccone) invece delle piante (ascia).
func set_clear_action(action: String, status: String = "", rock: bool = false) -> void:
	_clear_action = action
	_clear_row.visible = action != CLEAR_ACTION_NONE
	if action == CLEAR_ACTION_UNMARK:
		_clear_icon.kind = BuildingCommandIcon.KIND_CANCEL_CLEAR_ROCK if rock else BuildingCommandIcon.KIND_CANCEL_CLEAR_PLANTS
		_clear_button.tooltip_text = TooltipText.wrap("%s\n%s" % [tr("microcell_clear_cancel_button"), tr("microcell_clear_cancel_detail")])
	else:
		_clear_icon.kind = BuildingCommandIcon.KIND_CLEAR_ROCK if rock else BuildingCommandIcon.KIND_CLEAR_PLANTS
		var detail := tr("microcell_clear_rock_detail") if rock else tr("microcell_clear_plants_detail")
		_clear_button.tooltip_text = TooltipText.wrap("%s\n%s" % [tr("microcell_clear_button"), detail])
	_clear_status_label.text = status
	_clear_status_label.visible = status != ""


# Aggiunge a `lines` un separatore di sezione, solo se c'è già del testo prima e l'ultima riga non è già un separatore.
static func append_separator(lines: Array) -> void:
	if not lines.is_empty() and String(lines.back()) != SEPARATOR_LINE:
		lines.append(SEPARATOR_LINE)


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
	for node in _extra_nodes:
		node.queue_free()
	_extra_nodes.clear()
	# Blocchi di testo separati da SEPARATOR_LINE: il primo in ContentLabel, gli altri in copie con un tratteggio prima.
	var blocks: Array[Array] = [[]]
	for line in lines:
		if String(line) == SEPARATOR_LINE:
			blocks.append([])
		else:
			blocks.back().append(String(line))
	content_label.text = "\n".join(blocks[0])
	for i in range(1, blocks.size()):
		if blocks[i].is_empty():
			continue
		var separator := DashedSeparator.new()
		add_child(separator)
		_extra_nodes.append(separator)
		var label := content_label.duplicate() as Label
		label.text = "\n".join(blocks[i])
		add_child(label)
		_extra_nodes.append(label)
	# Riga dello sgombero e pulsante sempre in fondo.
	move_child(_clear_status_label, -1)
	move_child(_clear_row, -1)


func clear() -> void:
	visible = false
