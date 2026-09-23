class_name TechTreePanel
extends CanvasLayer

# Albero delle Tecnologie di GameScene, overlay a tutto schermo (2026-09-21, richiesta utente —
# prima era una Window 320x400 con solo idea attiva + elenco completate). CanvasLayer istanziato
# nella stessa GameScene.tscn (nessun cambio scena), sopra il layer 1 della UI principale.
#
# Layout a colonne per PROFONDITÀ dei prerequisiti: colonna 0 = idee senza prerequisiti, colonna N
# = idee il cui prerequisito più profondo sta in colonna N-1 (vedi _depth_of). Ogni idea è un
# riquadro (_build_card) nei 4 stati completata/in ricerca/disponibile/bloccata (_state_of); le
# linee prerequisito->idea sono disegnate da TreeCanvas (segnale draw, vedi _on_tree_canvas_draw)
# sotto i riquadri, che sono suoi figli. Tutto ricalcolato AL VOLO ad ogni refresh_content() —
# nessuna cache, Folk.active_idea_id/thoughts_invested/completed_ideas restano l'unica fonte di
# verità.
#
# Pausa della simulazione: nessun get_tree().paused — GameScene ascolta già visibility_changed di
# ogni pannello bloccante (_on_blocking_dialog_visibility_changed, ferma/riprende il clock),
# CanvasLayer emette lo stesso segnale delle Window. Root/Background (mouse_filter STOP) impedisce
# ai click di arrivare alla mappa sotto; _input sotto assorbe anche la tastiera.

# idea_id — GameScene ne ha bisogno per risolvere display_name e comporre il messaggio di
# notifica (vedi GameScene._on_idea_completed).
signal idea_completed(idea_id: String)

enum IdeaState { COMPLETED, RESEARCHING, AVAILABLE, LOCKED }

const CARD_SIZE := Vector2(220, 136)
const COLUMN_GAP := 90.0
const ROW_GAP := 24.0
const CANVAS_MARGIN := 24.0
const WHEEL_SCROLL_STEP := 80
# Spazio in cima al canvas per il nome dell'era (fascia) sopra i riquadri.
const BAND_HEADER_HEIGHT := 40.0
const BAND_COLORS := [Color(0.10, 0.13, 0.18), Color(0.14, 0.11, 0.17)]
const ERA_HIDDEN_NAME := "???"

const STATE_BG_COLORS := {
	IdeaState.COMPLETED: Color(0.14, 0.32, 0.18),
	IdeaState.RESEARCHING: Color(0.40, 0.30, 0.07),
	IdeaState.AVAILABLE: Color(0.14, 0.24, 0.38),
	IdeaState.LOCKED: Color(0.16, 0.16, 0.18),
}
const STATE_BORDER_COLORS := {
	IdeaState.COMPLETED: Color(0.40, 0.80, 0.46),
	IdeaState.RESEARCHING: Color(0.95, 0.78, 0.25),
	IdeaState.AVAILABLE: Color(0.45, 0.68, 0.95),
	IdeaState.LOCKED: Color(0.40, 0.40, 0.44),
}
const STATE_LABEL_KEYS := {
	IdeaState.COMPLETED: "tech_tree_state_completed",
	IdeaState.RESEARCHING: "tech_tree_state_researching",
	IdeaState.AVAILABLE: "tech_tree_state_available",
	IdeaState.LOCKED: "tech_tree_state_locked",
}
const COLOR_BAR_ACTIVE := Color(0.95, 0.78, 0.25)
const COLOR_BAR_DECAYING := Color(0.55, 0.62, 0.75)
const LINE_COLOR_MET := Color(0.40, 0.80, 0.46)
const LINE_COLOR_UNMET := Color(0.45, 0.45, 0.50)

@onready var title_label: Label = $Root/MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var summary_label: Label = $Root/MarginContainer/VBoxContainer/HeaderRow/SummaryLabel
@onready var debug_add_thought_button: Button = $Root/MarginContainer/VBoxContainer/HeaderRow/DebugAddThoughtButton
@onready var close_button: Button = $Root/MarginContainer/VBoxContainer/HeaderRow/CloseButton
@onready var tree_scroll: ScrollContainer = $Root/MarginContainer/VBoxContainer/ContentRow/TreeScroll
@onready var tree_canvas: Control = $Root/MarginContainer/VBoxContainer/ContentRow/TreeScroll/TreeCanvas
@onready var placeholder_label: Label = $Root/MarginContainer/VBoxContainer/ContentRow/DetailPanel/DetailMargin/DetailBox/PlaceholderLabel
@onready var detail_content: VBoxContainer = $Root/MarginContainer/VBoxContainer/ContentRow/DetailPanel/DetailMargin/DetailBox/DetailContent
@onready var detail_name_label: Label = $Root/MarginContainer/VBoxContainer/ContentRow/DetailPanel/DetailMargin/DetailBox/DetailContent/NameLabel
@onready var detail_summary_label: Label = $Root/MarginContainer/VBoxContainer/ContentRow/DetailPanel/DetailMargin/DetailBox/DetailContent/SummaryLabel
@onready var detail_description_label: Label = $Root/MarginContainer/VBoxContainer/ContentRow/DetailPanel/DetailMargin/DetailBox/DetailContent/DescriptionLabel
@onready var detail_cost_label: Label = $Root/MarginContainer/VBoxContainer/ContentRow/DetailPanel/DetailMargin/DetailBox/DetailContent/CostLabel
@onready var detail_requires_label: Label = $Root/MarginContainer/VBoxContainer/ContentRow/DetailPanel/DetailMargin/DetailBox/DetailContent/RequiresLabel
@onready var detail_unlocks_label: Label = $Root/MarginContainer/VBoxContainer/ContentRow/DetailPanel/DetailMargin/DetailBox/DetailContent/UnlocksLabel
@onready var research_button: Button = $Root/MarginContainer/VBoxContainer/ContentRow/DetailPanel/DetailMargin/DetailBox/ResearchButton

var _human_folk: Folk = null
# Serve per il giorno corrente e l'Era (decadimento pensieri, vedi _on_research_button_pressed).
var _game_data: GameData = null
# Riquadro evidenziato e mostrato nel pannello di dettaglio (click su un riquadro, qualunque sia il
# suo stato) — "" = nessuno. Non è l'idea attiva: la ricerca parte solo dal pulsante di dettaglio.
var _selected_idea_id: String = ""
# Linee da disegnare, ricostruite ad ogni refresh_content: {"from": Vector2, "to": Vector2, "met": bool}
# in coordinate locali di tree_canvas (vedi _on_tree_canvas_draw).
var _edges: Array[Dictionary] = []
# Fasce delle ere, ricostruite ad ogni refresh_content: {"x0": float, "x1": float, "color": Color}
# (coordinate locali di tree_canvas, altezza = tutto il canvas, vedi _on_tree_canvas_draw).
var _bands: Array[Dictionary] = []
# Coppie idea<-prerequisito già segnalate da _depth_of (push_warning una volta sola, non ad ogni refresh).
var _warned_era_conflicts: Dictionary = {}


func _ready() -> void:
	title_label.text = tr("tech_tree_title")
	close_button.text = tr("close_menu")
	close_button.pressed.connect(hide)
	tree_canvas.draw.connect(_on_tree_canvas_draw)
	# Le fasce riempiono l'altezza visibile: ridisegna se il canvas viene ridimensionato.
	tree_canvas.resized.connect(tree_canvas.queue_redraw)
	tree_scroll.gui_input.connect(_on_tree_scroll_gui_input)

	# Bottone di debug — stesso principio di sempre: dietro DebugLogging.ENABLED, mai visibile in
	# una build "pulita".
	debug_add_thought_button.visible = DebugLogging.ENABLED
	debug_add_thought_button.text = tr("tech_tree_debug_add_thought")
	debug_add_thought_button.pressed.connect(_on_debug_add_thought_pressed)

	research_button.pressed.connect(_on_research_button_pressed)


func open_dialog(human_folk: Folk, game_data: GameData) -> void:
	_human_folk = human_folk
	_game_data = game_data
	# All'apertura il dettaglio mostra l'idea attiva, se c'è; altrimenti resta vuoto con l'invito a
	# selezionare (vedi _update_detail).
	_selected_idea_id = human_folk.active_idea_id if human_folk != null else ""
	refresh_content()
	tree_scroll.scroll_horizontal = 0
	tree_scroll.scroll_vertical = 0
	show()


# Pubblica e richiamabile anche a pannello già aperto (dal bottone di debug sotto, o da un vero
# deposito di pensieri — vedi GameScene) — nessuna riapertura necessaria.
func refresh_content() -> void:
	if _human_folk == null:
		return

	# remove_child + queue_free (non solo queue_free): i vecchi riquadri devono sparire SUBITO, non
	# a fine frame, o convivrebbero per un frame con quelli nuovi nelle stesse posizioni.
	for child in tree_canvas.get_children():
		tree_canvas.remove_child(child)
		child.queue_free()
	_edges.clear()
	_bands.clear()

	var ideas: Dictionary = {}
	for idea_id in IdeaCalculator.list_idea_ids():
		var idea := IdeaCalculator.get_idea(idea_id)
		if idea != null:
			ideas[idea_id] = idea

	var any_available := false
	for idea in ideas.values():
		if IdeaProgressService.is_available(_human_folk, idea):
			any_available = true
			break
	_update_summary(any_available)

	var layout := _layout_ideas(ideas)
	var cells: Dictionary = layout["cells"]
	var positions: Dictionary = {}
	var column_count := 0
	var row_count := 0
	for cell in cells.values():
		column_count = maxi(column_count, cell.x + 1)
		row_count = maxi(row_count, cell.y + 1)
	var canvas_size := Vector2(
		CANVAS_MARGIN * 2.0 + column_count * CARD_SIZE.x + maxi(column_count - 1, 0) * COLUMN_GAP,
		CANVAS_MARGIN * 2.0 + BAND_HEADER_HEIGHT + row_count * CARD_SIZE.y + maxi(row_count - 1, 0) * ROW_GAP
	)

	# Fasce delle ere: rettangoli disegnati da _on_tree_canvas_draw + etichetta col nome (figlia del
	# canvas, aggiunta PRIMA dei riquadri così resta sotto). Nome visibile per l'era corrente e la
	# successiva, "???" oltre.
	var era_names := EraCalculator.list_era_names()
	var current_era_index := _current_era_index(era_names)
	var step_x := CARD_SIZE.x + COLUMN_GAP
	var band_number := 0
	for band in layout["bands"]:
		var band_x0 := maxf(CANVAS_MARGIN + band["first_col"] * step_x - COLUMN_GAP * 0.5, 0.0)
		var band_x1 := minf(CANVAS_MARGIN + band["last_col"] * step_x + CARD_SIZE.x + COLUMN_GAP * 0.5, canvas_size.x)
		_bands.append({"x0": band_x0, "x1": band_x1, "color": BAND_COLORS[band_number % BAND_COLORS.size()]})
		band_number += 1
		var era_rules := EraCalculator.get_era_rules(band["era"])
		var band_label := Label.new()
		if band["era_index"] <= current_era_index + 1 and era_rules != null:
			band_label.text = tr(era_rules.display_name)
		else:
			band_label.text = ERA_HIDDEN_NAME
		band_label.add_theme_font_size_override("font_size", 20)
		band_label.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
		band_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band_label.position = Vector2(band_x0 + 14.0, 10.0)
		tree_canvas.add_child(band_label)

	for idea_id in cells:
		var cell: Vector2i = cells[idea_id]
		var card_position := Vector2(
			CANVAS_MARGIN + cell.x * step_x,
			CANVAS_MARGIN + BAND_HEADER_HEIGHT + cell.y * (CARD_SIZE.y + ROW_GAP)
		)
		positions[idea_id] = card_position
		var card := _build_card(ideas[idea_id])
		card.position = card_position
		tree_canvas.add_child(card)

	# Linee: uscita al centro del lato destro del prerequisito, ingresso al centro del lato sinistro
	# dell'idea. Prerequisiti non risolvibili (id senza .tres) non hanno riquadro, nessuna linea.
	# Le linee verso idee coperte restano (richiesta utente).
	for idea_id in ideas:
		for prerequisite_id in ideas[idea_id].prerequisites:
			if not positions.has(prerequisite_id):
				continue
			_edges.append({
				"from": positions[prerequisite_id] + Vector2(CARD_SIZE.x, CARD_SIZE.y * 0.5),
				"to": positions[idea_id] + Vector2(0.0, CARD_SIZE.y * 0.5),
				"met": _human_folk.completed_ideas.has(prerequisite_id),
			})

	tree_canvas.custom_minimum_size = canvas_size
	tree_canvas.queue_redraw()
	_update_detail(ideas)


func _update_summary(any_available: bool) -> void:
	summary_label.remove_theme_color_override("font_color")
	summary_label.remove_theme_font_size_override("font_size")
	if _human_folk.active_idea_id == "":
		if any_available:
			# In evidenza (richiesta utente): nessuna idea attiva e almeno una scegliibile — i
			# pensieri depositati ora andrebbero persi (vedi IdeaProgressService.add_thoughts).
			summary_label.text = tr("tech_tree_select_idea_prompt")
			summary_label.add_theme_color_override("font_color", STATE_BORDER_COLORS[IdeaState.RESEARCHING])
			summary_label.add_theme_font_size_override("font_size", 20)
		else:
			# Nessuna idea disponibile (tutte completate o bloccate): niente da selezionare.
			summary_label.text = tr("tech_tree_no_active_idea")
		return
	var active_idea := IdeaCalculator.get_idea(_human_folk.active_idea_id)
	# Fallback all'id grezzo se l'Idea non si carica (mai tr()-wrapped: non è una chiave).
	var display_name: String = tr(active_idea.display_name) if active_idea != null else _human_folk.active_idea_id
	summary_label.text = tr("tech_tree_active_idea_label").format({"idea": display_name})


# Indice (nella sequenza ordinata delle Ere) dell'era corrente del gioco: GameData.current_era_name;
# se non c'è/non è nell'elenco, "paleolithic"; in ultima istanza 0.
func _current_era_index(era_names: Array[String]) -> int:
	var index := era_names.find(_game_data.current_era_name) if _game_data != null else -1
	if index == -1:
		index = era_names.find("paleolithic")
	return maxi(index, 0)


# Indice dell'era di un'idea nella sequenza ordinata; era vuota o sconosciuta -> 0 (prima era).
func _era_index_of(idea: Idea, era_names: Array[String]) -> int:
	return maxi(era_names.find(idea.era), 0)


# Profondità LOCALE all'era: 0 senza prerequisiti della stessa era, altrimenti 1 + la massima tra
# i prerequisiti della stessa era. I prerequisiti di ere precedenti non contano (l'era inizia già
# dopo di loro, vedi _layout_ideas); uno di un'era SUCCESSIVA è un errore di dati: push_warning
# (una volta per coppia) e ignorato. Prerequisiti senza .tres vengono ignorati; un ciclo (dato mal
# configurato) viene spezzato contando 0 per l'id già in visita.
func _depth_of(
	idea_id: String, ideas: Dictionary, era_index: Dictionary, memo: Dictionary, visiting: Dictionary
) -> int:
	if memo.has(idea_id):
		return memo[idea_id]
	if visiting.has(idea_id):
		return 0
	visiting[idea_id] = true
	var depth := 0
	for prerequisite_id in ideas[idea_id].prerequisites:
		if not ideas.has(prerequisite_id):
			continue
		if era_index[prerequisite_id] > era_index[idea_id]:
			var warning_key := "%s<-%s" % [idea_id, prerequisite_id]
			if not _warned_era_conflicts.has(warning_key):
				_warned_era_conflicts[warning_key] = true
				push_warning("Idea '%s' ha il prerequisito '%s' di un'era successiva." % [idea_id, prerequisite_id])
			continue
		if era_index[prerequisite_id] == era_index[idea_id]:
			depth = maxi(depth, _depth_of(prerequisite_id, ideas, era_index, memo, visiting) + 1)
	visiting.erase(idea_id)
	memo[idea_id] = depth
	return depth


# Layout: {"cells": id -> Vector2i(colonna, riga), "bands": [{"era", "era_index", "first_col",
# "last_col"}]}. L'era è un limite minimo di colonna: le idee di un'era iniziano dopo l'ultima
# colonna dell'era precedente (che occupa tante colonne quanta la sua profondità locale massima + 1;
# un'era senza idee non occupa colonne né ha fascia); dentro l'era la colonna segue i prerequisiti.
# Righe: colonna 0 alfabetica; dalle successive ogni idea cerca la riga MEDIA dei suoi prerequisiti
# (baricentro), così un'idea figlia sta sulla stessa riga del genitore e i fratelli scendono sotto;
# le righe possono avere buchi. Sort per (baricentro, id) -> deterministico; riga = max(riga
# desiderata, riga precedente + 1) per non sovrapporre due riquadri.
func _layout_ideas(ideas: Dictionary) -> Dictionary:
	var era_names := EraCalculator.list_era_names()
	var era_index: Dictionary = {}
	for idea_id in ideas:
		era_index[idea_id] = _era_index_of(ideas[idea_id], era_names)

	# eras_columns[era][colonna locale] = ids
	var eras_columns: Array = []
	for _era in maxi(era_names.size(), 1):
		eras_columns.append([])
	var memo: Dictionary = {}
	for idea_id in IdeaCalculator.list_idea_ids():
		if not ideas.has(idea_id):
			continue
		var local_columns: Array = eras_columns[era_index[idea_id]]
		var depth := _depth_of(idea_id, ideas, era_index, memo, {})
		while local_columns.size() <= depth:
			local_columns.append([])
		local_columns[depth].append(idea_id)

	var columns: Array = []  # colonne assolute, ciascuna Array di id
	var bands: Array[Dictionary] = []
	for era_i in eras_columns.size():
		var era_local_columns: Array = eras_columns[era_i]
		if era_local_columns.is_empty():
			continue
		bands.append({
			"era": era_names[era_i] if era_i < era_names.size() else "",
			"era_index": era_i,
			"first_col": columns.size(),
			"last_col": columns.size() + era_local_columns.size() - 1,
		})
		columns.append_array(era_local_columns)

	var cells: Dictionary = {}
	for column_index in columns.size():
		var column: Array = columns[column_index]
		var barycenters: Dictionary = {}
		for idea_id in column:
			var sum := 0.0
			var count := 0
			for prerequisite_id in ideas[idea_id].prerequisites:
				if cells.has(prerequisite_id):
					sum += cells[prerequisite_id].y
					count += 1
			barycenters[idea_id] = sum / count if count > 0 else 0.0
		if column_index > 0:
			column.sort_custom(func(a: String, b: String) -> bool:
				if barycenters[a] != barycenters[b]:
					return barycenters[a] < barycenters[b]
				return a < b
			)
		var last_row := -1
		for idea_id in column:
			var desired_row := roundi(barycenters[idea_id]) if column_index > 0 else 0
			var row := maxi(desired_row, last_row + 1)
			cells[idea_id] = Vector2i(column_index, row)
			last_row = row
	return {"cells": cells, "bands": bands}


# Idea coperta / filtro sblocchi: logica in IdeaProgressService (condivisa col popup di sblocco).
func _is_idea_hidden(idea: Idea) -> bool:
	return IdeaProgressService.is_hidden(_human_folk, idea)


func _is_unlock_hidden(kind: StringName, unlock_id: String) -> bool:
	return IdeaProgressService.is_unlock_hidden(_human_folk, kind, unlock_id)


func _state_of(idea: Idea) -> IdeaState:
	if _human_folk.completed_ideas.has(idea.id):
		return IdeaState.COMPLETED
	if _human_folk.active_idea_id == idea.id:
		return IdeaState.RESEARCHING
	if IdeaProgressService.is_available(_human_folk, idea):
		return IdeaState.AVAILABLE
	return IdeaState.LOCKED


func _build_card(idea: Idea) -> PanelContainer:
	if _is_idea_hidden(idea):
		return _build_hidden_card(idea)
	var state := _state_of(idea)

	var style := StyleBoxFlat.new()
	style.bg_color = STATE_BG_COLORS[state]
	style.border_color = STATE_BORDER_COLORS[state]
	style.set_border_width_all(2)
	# Riquadro selezionato (mostrato nel dettaglio): bordo bianco e più spesso.
	if idea.id == _selected_idea_id:
		style.border_color = Color.WHITE
		style.set_border_width_all(4)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)

	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.size = CARD_SIZE
	card.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	# IGNORE sul contenuto: i click devono arrivare al riquadro (card), non essere assorbiti da
	# box/label/barra figli.
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)

	# Ogni riquadro è cliccabile: seleziona (evidenzia + dettaglio), vedi _on_card_gui_input.
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(_on_card_gui_input.bind(idea.id))

	var name_label := Label.new()
	name_label.text = tr(idea.display_name)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = 2
	name_label.add_theme_font_size_override("font_size", 16)
	box.add_child(name_label)

	var cost_label := Label.new()
	cost_label.text = tr("tech_tree_cost").format({"cost": idea.thoughts_cost})
	box.add_child(cost_label)

	var status_label := Label.new()
	status_label.text = tr(STATE_LABEL_KEYS[state])
	status_label.add_theme_color_override("font_color", STATE_BORDER_COLORS[state])
	box.add_child(status_label)

	# Barra per l'idea attiva E per ogni idea non attiva con pensieri investiti (che decadono, vedi
	# IdeaDecayService), in due colori diversi: ambra per l'attiva, grigio-azzurro per le altre.
	var invested: int = int(_human_folk.thoughts_invested.get(idea.id, 0))
	if state == IdeaState.RESEARCHING or (state != IdeaState.COMPLETED and invested > 0):
		status_label.text += "  %d / %d" % [invested, idea.thoughts_cost]
		var bar := ProgressBar.new()
		var fill_style := StyleBoxFlat.new()
		fill_style.bg_color = COLOR_BAR_ACTIVE if state == IdeaState.RESEARCHING else COLOR_BAR_DECAYING
		bar.add_theme_stylebox_override("fill", fill_style)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 10)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# maxi(cost, 1) — guardia difensiva contro un'Idea con thoughts_cost=0/mal configurata.
		bar.max_value = maxi(idea.thoughts_cost, 1)
		bar.value = invested
		box.add_child(bar)

	if state == IdeaState.LOCKED:
		card.modulate = Color(1, 1, 1, 0.7)
	return card


# Riquadro di un'idea coperta: grigio, solo "?" — niente nome, costo né stato. Selezionabile come gli
# altri (il dettaglio mostra "Idea sconosciuta", vedi _update_detail).
func _build_hidden_card(idea: Idea) -> PanelContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.20, 0.20, 0.22)
	style.border_color = Color(0.36, 0.36, 0.40)
	style.set_border_width_all(2)
	if idea.id == _selected_idea_id:
		style.border_color = Color.WHITE
		style.set_border_width_all(4)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)

	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.size = CARD_SIZE
	card.add_theme_stylebox_override("panel", style)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(_on_card_gui_input.bind(idea.id))

	var question_label := Label.new()
	question_label.text = "?"
	question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	question_label.add_theme_font_size_override("font_size", 44)
	question_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	question_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(question_label)
	return card


# Pannello di dettaglio fisso a destra (2026-09-21, richiesta utente — sostituisce i tooltip dei
# riquadri): nome, summary, description, costo, prerequisiti e sblocchi (IdeaUnlocksService) per
# _selected_idea_id, più il pulsante di ricerca. Sezioni vuote nascoste. Nessuna selezione (o id non
# più risolvibile) -> solo l'invito a selezionare un'idea.
func _update_detail(ideas: Dictionary) -> void:
	if _selected_idea_id == "" or not ideas.has(_selected_idea_id):
		_selected_idea_id = ""
		placeholder_label.visible = true
		placeholder_label.text = tr("tech_tree_detail_placeholder")
		detail_content.visible = false
		research_button.visible = false
		return

	var idea: Idea = ideas[_selected_idea_id]
	if _is_idea_hidden(idea):
		# Idea coperta: nessun dettaglio, nessun pulsante.
		placeholder_label.visible = true
		placeholder_label.text = tr("tech_tree_unknown_idea")
		detail_content.visible = false
		research_button.visible = false
		return
	placeholder_label.visible = false
	detail_content.visible = true
	research_button.visible = true

	detail_name_label.text = tr(idea.display_name)
	_set_optional_text(detail_summary_label, tr(idea.summary) if idea.summary != "" else "")
	_set_optional_text(detail_description_label, tr(idea.description) if idea.description != "" else "")
	detail_cost_label.text = tr("tech_tree_cost").format({"cost": idea.thoughts_cost})

	var requires_text := ""
	if not idea.prerequisites.is_empty():
		var prerequisite_names: Array[String] = []
		for prerequisite_id in idea.prerequisites:
			var prerequisite := IdeaCalculator.get_idea(prerequisite_id)
			prerequisite_names.append(tr(prerequisite.display_name) if prerequisite != null else prerequisite_id)
		requires_text = tr("tech_tree_requires").format({"ideas": ", ".join(prerequisite_names)})
	_set_optional_text(detail_requires_label, requires_text)
	_set_optional_text(detail_unlocks_label, "\n".join(IdeaUnlocksService.format_lines(idea.id, _is_unlock_hidden)))

	# Pulsante: attivo SOLO per un'idea disponibile e non già attiva; completata/in ricerca mostrano
	# lo stato (disattivato), bloccata lascia il testo normale disattivato.
	match _state_of(idea):
		IdeaState.AVAILABLE:
			research_button.text = tr("tech_tree_research_button")
			research_button.disabled = false
		IdeaState.RESEARCHING:
			research_button.text = tr(STATE_LABEL_KEYS[IdeaState.RESEARCHING])
			research_button.disabled = true
		IdeaState.COMPLETED:
			research_button.text = tr(STATE_LABEL_KEYS[IdeaState.COMPLETED])
			research_button.disabled = true
		IdeaState.LOCKED:
			research_button.text = tr("tech_tree_research_button")
			research_button.disabled = true


func _set_optional_text(label: Label, text: String) -> void:
	label.text = text
	label.visible = text != ""


func _on_research_button_pressed() -> void:
	if _human_folk == null or _game_data == null:
		return
	var era_rules := EraCalculator.get_era_rules(_game_data.current_era_name)
	if IdeaProgressService.select_idea(_human_folk, _selected_idea_id, _game_data.get_absolute_day(), era_rules):
		refresh_content()


# Click sinistro su un riquadro (qualunque stato) -> lo seleziona: evidenziato + dettaglio a destra.
# Non cambia la ricerca (vedi _on_research_button_pressed). refresh_content in deferred: ricostruisce
# (e libera) i riquadri, incluso quello che sta ancora emettendo questo gui_input.
func _on_card_gui_input(event: InputEvent, idea_id: String) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _human_folk != null and idea_id != _selected_idea_id:
		_selected_idea_id = idea_id
		refresh_content.call_deferred()


# Fasce (sfondo per era) e linee a gomito: orizzontale dal prerequisito, verticale nel varco subito prima dell'idea,
# orizzontale fino al suo bordo sinistro. Disegnate sul canvas PRIMA dei suoi figli (i riquadri),
# quindi restano sempre sotto.
func _on_tree_canvas_draw() -> void:
	# Fasce delle ere, dietro a tutto: altezza = l'intero canvas (min size o area visibile).
	var band_height := maxf(tree_canvas.size.y, tree_canvas.custom_minimum_size.y)
	for band in _bands:
		var band_rect := Rect2(band["x0"], 0.0, band["x1"] - band["x0"], band_height)
		tree_canvas.draw_rect(band_rect, band["color"])
		tree_canvas.draw_rect(band_rect, Color(0.3, 0.34, 0.42, 0.6), false, 1.0)
	for edge in _edges:
		var from: Vector2 = edge["from"]
		var to: Vector2 = edge["to"]
		var mid_x := to.x - COLUMN_GAP * 0.5
		var color := LINE_COLOR_MET if edge["met"] else LINE_COLOR_UNMET
		tree_canvas.draw_polyline(
			PackedVector2Array([from, Vector2(mid_x, from.y), Vector2(mid_x, to.y), to]),
			color, 2.0, true
		)


# La rotella scorre in orizzontale (l'albero cresce verso destra) finché il contenuto non
# richiede anche scroll verticale — in quel caso resta il comportamento standard (verticale, con
# Shift orizzontale).
func _on_tree_scroll_gui_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed:
		return
	if tree_canvas.custom_minimum_size.y > tree_scroll.size.y:
		return
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		tree_scroll.scroll_horizontal += WHEEL_SCROLL_STEP
		tree_scroll.accept_event()
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		tree_scroll.scroll_horizontal -= WHEEL_SCROLL_STEP
		tree_scroll.accept_event()


# Overlay non-Window: la tastiera non è isolata da un focus di finestra come per i vecchi
# dialoghi, quindi va assorbita qui, altrimenti gli shortcut di GameScene (_unhandled_input)
# scatterebbero sotto il pannello. Escape chiude, come da convenzione. (Il pan WASD della camera
# usa Input.is_key_pressed in polling, non passa da qui: lo blocca CameraController.input_locked,
# impostato da GameScene._on_blocking_dialog_visibility_changed.)
func _input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if not visible or key_event == null:
		return
	if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
		hide()
	get_viewport().set_input_as_handled()


# La STESSA IdeaProgressService.add_thoughts(folk, 1) di sempre. Non conosce BuildBar (questo
# pannello resta "muto" sul resto della UI): si limita a segnalare un completamento con
# idea_completed, GameScene decide se/come reagire.
func _on_debug_add_thought_pressed() -> void:
	if _human_folk == null:
		return
	var completed := IdeaProgressService.add_thoughts(_human_folk, 1)
	refresh_content()
	if completed:
		# completed_ideas[-1] — add_thoughts fa sempre append IMMEDIATAMENTE prima di ritornare
		# true (unico scrittore di questo array): l'ultimo elemento è l'id appena completato.
		idea_completed.emit(_human_folk.completed_ideas[-1])
