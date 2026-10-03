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
# Spazio tra le righe: ci passano le linee che saltano una o più colonne (corsie orizzontali, vedi _build_edges).
const ROW_GAP := 34.0
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
# Linee (2026-10-03, richiesta utente — una linea per ogni coppia prerequisito -> idea, niente tronchi condivisi):
# distanza tra due punti di attacco sullo stesso lato di un riquadro, spessore normale ed evidenziato, opacità delle linee
# non collegate al riquadro sotto il mouse.
const LINE_ATTACH_STEP := 10.0
const LINE_WIDTH := 2.0
const LINE_WIDTH_HIGHLIGHT := 3.0
const LINE_DIMMED_ALPHA := 0.18

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
# Linee da disegnare, ricostruite ad ogni refresh_content: {"points": PackedVector2Array, "from_id", "to_id", "met"}
# in coordinate locali di tree_canvas (vedi _build_edges e _on_tree_canvas_draw).
var _edges: Array[Dictionary] = []
# Riquadro sotto il mouse ("" = nessuno): le sue linee in entrata e in uscita si accendono, le altre si attenuano.
var _hovered_idea_id: String = ""
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

	# Linee: una per ogni coppia prerequisito -> idea (vedi _build_edges). Prerequisiti non risolvibili (id senza .tres)
	# non hanno riquadro, nessuna linea. Le linee verso idee coperte restano (richiesta utente).
	if not cells.has(_hovered_idea_id):
		_hovered_idea_id = ""
	_build_edges(ideas, cells, layout["first_parents"])

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
# "last_col"}], "first_parents": id -> id del primo prerequisito ("" = radice)}. L'era è un limite minimo di colonna:
# le idee di un'era iniziano dopo l'ultima colonna dell'era precedente (che occupa tante colonne quanta la sua profondità
# locale massima + 1; un'era senza idee non occupa colonne né ha fascia); dentro l'era la colonna segue i prerequisiti.
# Righe (2026-10-03, richiesta utente — prima il baricentro dei prerequisiti): albero per PRIMO prerequisito (il primo
# dell'elenco nei dati che ha un riquadro in una colonna precedente, _first_parent). Ogni idea sta sulla riga del primo
# prerequisito; con più figli dello stesso primo prerequisito (in ordine di id) il primo prende la riga del padre, gli
# altri le righe libere subito sotto il sottoalbero del fratello precedente, e tutto ciò che segue scala in basso. Le
# radici (nessun primo prerequisito) in ordine di colonna e poi di id, ognuna con lo spazio per i suoi discendenti
# (_place_subtree).
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

	var column_of: Dictionary = {}
	for column_index in columns.size():
		for idea_id in columns[column_index]:
			column_of[idea_id] = column_index

	var first_parents: Dictionary = {}
	var children: Dictionary = {}
	var roots: Array[String] = []
	for idea_id in IdeaCalculator.list_idea_ids():
		if not column_of.has(idea_id):
			continue
		var parent := _first_parent(idea_id, ideas, column_of)
		first_parents[idea_id] = parent
		if parent == "":
			roots.append(idea_id)
		else:
			if not children.has(parent):
				children[parent] = []
			(children[parent] as Array).append(idea_id)
	roots.sort_custom(func(a: String, b: String) -> bool:
		if column_of[a] != column_of[b]:
			return column_of[a] < column_of[b]
		return a < b
	)

	var cells: Dictionary = {}
	var next_row := 0
	for root_id in roots:
		next_row += _place_subtree(root_id, next_row, children, column_of, cells)
	return {"cells": cells, "bands": bands, "first_parents": first_parents}


# Primo prerequisito di `idea_id` che ha un riquadro in una colonna PRECEDENTE (il primo dell'elenco nei dati; un
# prerequisito senza .tres o di un'era successiva — errore di dati — viene saltato). "" = nessuno: radice.
func _first_parent(idea_id: String, ideas: Dictionary, column_of: Dictionary) -> String:
	for prerequisite_id in ideas[idea_id].prerequisites:
		if column_of.has(prerequisite_id) and column_of[prerequisite_id] < column_of[idea_id]:
			return prerequisite_id
	return ""


# Mette `idea_id` sulla riga `row` e i suoi figli (idee che l'hanno come primo prerequisito) a partire dalla stessa
# riga, ognuno sotto il sottoalbero del precedente. Ritorna le righe occupate dal sottoalbero (almeno 1). Il padre è
# sempre in una colonna precedente (_first_parent), quindi niente cicli; un riquadro già occupato (dati anomali) scende
# alla prima riga libera della sua colonna.
func _place_subtree(idea_id: String, row: int, children: Dictionary, column_of: Dictionary, cells: Dictionary) -> int:
	var column: int = column_of[idea_id]
	var placed_row := row
	while _is_cell_taken(cells, column, placed_row):
		placed_row += 1
	cells[idea_id] = Vector2i(column, placed_row)
	var kids: Array = children.get(idea_id, [])
	kids.sort()
	var used := 0
	for kid in kids:
		used += _place_subtree(String(kid), row + used, children, column_of, cells)
	return maxi(used, placed_row - row + 1)


func _is_cell_taken(cells: Dictionary, column: int, row: int) -> bool:
	for cell in cells.values():
		if cell.x == column and cell.y == row:
			return true
	return false


# Linee (2026-10-03, richiesta utente): una per ogni coppia prerequisito -> idea, mai un tronco condiviso.
#   - primo prerequisito sulla stessa riga e nessun riquadro in mezzo: linea dritta, al centro dei due lati;
#   - tutti gli altri casi: gomito. Uscita dal lato destro del prerequisito, discesa/salita in un CANALE verticale proprio
#     nello spazio dopo la sua colonna, ingresso dal lato sinistro dell'idea. Se l'idea non è nella colonna subito
#     dopo, la linea attraversa le colonne in mezzo in una CORSIA orizzontale nello spazio sopra o sotto la riga
#     dell'idea, dalla parte da cui arriva (_lane_key), e
#     scende/sale in un secondo canale nello spazio prima della sua colonna: mai dietro un riquadro.
# Niente sovrapposizioni: ogni linea ha un punto di attacco proprio su ciascun lato (passo LINE_ATTACH_STEP attorno al
# centro, il centro riservato alla linea dritta, in ordine di posizione dell'altro capo), un canale proprio in ogni
# spazio tra colonne e una corsia propria in ogni spazio tra righe (posizioni distribuite in modo uniforme). Due linee
# possono incrociarsi ad angolo retto, mai correre sullo stesso tratto.
func _build_edges(ideas: Dictionary, cells: Dictionary, first_parents: Dictionary) -> void:
	var raw: Array[Dictionary] = []
	for idea_id in IdeaCalculator.list_idea_ids():
		if not cells.has(idea_id):
			continue
		var target: Vector2i = cells[idea_id]
		for prerequisite_id in ideas[idea_id].prerequisites:
			if not cells.has(prerequisite_id):
				continue
			var source: Vector2i = cells[prerequisite_id]
			if target.x <= source.x:
				continue
			var straight: bool = String(first_parents.get(idea_id, "")) == prerequisite_id and source.y == target.y \
				and not _has_card_between(cells, source, target)
			raw.append({
				"from_id": prerequisite_id, "to_id": idea_id, "source": source, "target": target, "straight": straight,
				"met": _human_folk.completed_ideas.has(prerequisite_id),
			})

	# Punti di attacco: uscite sul lato destro di ogni prerequisito, entrate sul lato sinistro di ogni idea.
	var out_offsets := _assign_attach_offsets(raw, "from_id", "source", "target")
	var in_offsets := _assign_attach_offsets(raw, "to_id", "target", "source")

	# Canali verticali (indice = colonna a sinistra dello spazio) e corsie orizzontali (indice = riga sotto lo spazio).
	var channel_users: Dictionary = {}
	var lane_users: Dictionary = {}
	for edge_index in raw.size():
		var edge: Dictionary = raw[edge_index]
		if edge["straight"]:
			continue
		var source: Vector2i = edge["source"]
		var target: Vector2i = edge["target"]
		_add_user(channel_users, source.x, edge_index)
		if target.x > source.x + 1:
			_add_user(lane_users, _lane_key(source, target), edge_index)
			_add_user(channel_users, target.x - 1, edge_index)

	var step_x := CARD_SIZE.x + COLUMN_GAP
	var step_y := CARD_SIZE.y + ROW_GAP
	for edge_index in raw.size():
		var edge: Dictionary = raw[edge_index]
		var source: Vector2i = edge["source"]
		var target: Vector2i = edge["target"]
		var source_right := CANVAS_MARGIN + source.x * step_x + CARD_SIZE.x
		var target_left := CANVAS_MARGIN + target.x * step_x
		var y_out: float = CANVAS_MARGIN + BAND_HEADER_HEIGHT + source.y * step_y + CARD_SIZE.y * 0.5 + out_offsets[edge_index]
		var y_in: float = CANVAS_MARGIN + BAND_HEADER_HEIGHT + target.y * step_y + CARD_SIZE.y * 0.5 + in_offsets[edge_index]
		var points := PackedVector2Array()
		if edge["straight"]:
			points.append(Vector2(source_right, y_out))
			points.append(Vector2(target_left, y_out))
		else:
			var channel_out := _slot_position(
				source_right, COLUMN_GAP, channel_users[source.x], edge_index
			)
			points.append(Vector2(source_right, y_out))
			points.append(Vector2(channel_out, y_out))
			if target.x == source.x + 1:
				points.append(Vector2(channel_out, y_in))
			else:
				var lane_key := _lane_key(source, target)
				var lane_top: float = CANVAS_MARGIN + BAND_HEADER_HEIGHT + lane_key * step_y - ROW_GAP
				var lane_y := _slot_position(lane_top, ROW_GAP, lane_users[lane_key], edge_index)
				var channel_in := _slot_position(
					target_left - COLUMN_GAP, COLUMN_GAP, channel_users[target.x - 1], edge_index
				)
				points.append(Vector2(channel_out, lane_y))
				points.append(Vector2(channel_in, lane_y))
				points.append(Vector2(channel_in, y_in))
			points.append(Vector2(target_left, y_in))
		_edges.append({"points": points, "from_id": edge["from_id"], "to_id": edge["to_id"], "met": edge["met"]})


# Corsia orizzontale di una linea che salta colonne (indice = riga subito sotto lo spazio tra righe): dalla parte da cui
# arriva la linea, così l'ultimo tratto verticale raggiunge il punto di attacco senza attraversare la linea dritta del
# riquadro di arrivo (2026-10-03). Da una riga più in alto: lo spazio sopra la riga dell'idea; dalla stessa riga o da
# più in basso: lo spazio sotto.
func _lane_key(source: Vector2i, target: Vector2i) -> int:
	return target.y if source.y < target.y else target.y + 1


# true se sulla riga di `source` c'è un riquadro in una colonna tra `source` e `target` (esclusi).
func _has_card_between(cells: Dictionary, source: Vector2i, target: Vector2i) -> bool:
	for cell in cells.values():
		if cell.y == source.y and cell.x > source.x and cell.x < target.x:
			return true
	return false


# Scostamento verticale dal centro del lato per ogni linea, per lato di riquadro: `card_key` = "from_id" (lato destro,
# uscite) o "to_id" (lato sinistro, entrate); `own_key`/`other_key` = cella di questo riquadro e dell'altro capo.
# Regola (2026-10-03, richiesta utente — prima gli scostamenti erano assegnati senza guardare da che parte arriva la
# linea, e una linea dal basso poteva attaccarsi sopra la dritta, incrociandola):
#   - la linea dritta tiene il centro;
#   - una linea che viene da una riga più in ALTO si attacca SOPRA il centro, una da una riga più in BASSO SOTTO;
#   - sullo stesso lato le linee sono ordinate per distanza: la più vicina al centro è quella della riga più vicina (a
#     parità, quella della colonna più vicina). Una linea a gomito dalla stessa riga prende il centro se è libero,
#     altrimenti la prima posizione sotto.
# Così il tratto verticale nel canale si ferma all'altezza del proprio attacco senza mai superare la linea dritta.
# Indice = posizione nell'array `raw`.
func _assign_attach_offsets(raw: Array[Dictionary], card_key: String, own_key: String, other_key: String) -> Dictionary:
	var by_card: Dictionary = {}
	for edge_index in raw.size():
		var card_id := String(raw[edge_index][card_key])
		if not by_card.has(card_id):
			by_card[card_id] = []
		(by_card[card_id] as Array).append(edge_index)
	var offsets: Dictionary = {}
	for card_id in by_card:
		var above: Array = []
		var below: Array = []
		var same_row: Array = []
		var center_taken := false
		for edge_index in by_card[card_id]:
			if raw[edge_index]["straight"]:
				offsets[edge_index] = 0.0
				center_taken = true
				continue
			var own_cell: Vector2i = raw[edge_index][own_key]
			var other_cell: Vector2i = raw[edge_index][other_key]
			if other_cell.y < own_cell.y:
				above.append(edge_index)
			elif other_cell.y > own_cell.y:
				below.append(edge_index)
			else:
				same_row.append(edge_index)
		var by_distance := func(a: int, b: int) -> bool:
			var own_a: Vector2i = raw[a][own_key]
			var other_a: Vector2i = raw[a][other_key]
			var own_b: Vector2i = raw[b][own_key]
			var other_b: Vector2i = raw[b][other_key]
			var row_a := absi(other_a.y - own_a.y)
			var row_b := absi(other_b.y - own_b.y)
			if row_a != row_b:
				return row_a < row_b
			return absi(other_a.x - own_a.x) < absi(other_b.x - own_b.x)
		above.sort_custom(by_distance)
		below.sort_custom(by_distance)
		same_row.sort_custom(by_distance)
		# Stessa riga: il centro se libero, il resto subito sotto, prima delle linee che vengono dal basso.
		if not same_row.is_empty() and not center_taken:
			offsets[same_row[0]] = 0.0
			same_row.remove_at(0)
		below = same_row + below
		for i in above.size():
			offsets[above[i]] = -float(i + 1) * LINE_ATTACH_STEP
		for i in below.size():
			offsets[below[i]] = float(i + 1) * LINE_ATTACH_STEP
	return offsets


func _add_user(users: Dictionary, key: int, edge_index: int) -> void:
	if not users.has(key):
		users[key] = []
	(users[key] as Array).append(edge_index)


# Posizione della linea `edge_index` nello spazio che parte da `start` largo `width`, condiviso dalle linee `users`:
# distribuite in modo uniforme, mai sul bordo dei riquadri.
func _slot_position(start: float, width: float, users: Array, edge_index: int) -> float:
	var slot := users.find(edge_index)
	return start + width * float(slot + 1) / float(users.size() + 1)


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
	_connect_card_hover(card, idea.id)

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
	_connect_card_hover(card, idea.id)

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


# Passaggio del mouse su un riquadro (2026-10-03): le sue linee si accendono, le altre si attenuano.
func _connect_card_hover(card: Control, idea_id: String) -> void:
	card.mouse_entered.connect(func() -> void:
		_hovered_idea_id = idea_id
		tree_canvas.queue_redraw()
	)
	card.mouse_exited.connect(func() -> void:
		if _hovered_idea_id == idea_id:
			_hovered_idea_id = ""
			tree_canvas.queue_redraw()
	)


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


# Fasce (sfondo per era) e linee (percorsi già calcolati da _build_edges). Disegnate sul canvas PRIMA dei suoi figli
# (i riquadri), quindi restano sempre sotto. Colore per singola linea: verde se quel prerequisito è completato, grigio
# se no. Con un riquadro sotto il mouse le sue linee (entrata e uscita) sono più spesse e disegnate per ultime, le altre
# attenuate.
func _on_tree_canvas_draw() -> void:
	# Fasce delle ere, dietro a tutto: altezza = l'intero canvas (min size o area visibile).
	var band_height := maxf(tree_canvas.size.y, tree_canvas.custom_minimum_size.y)
	for band in _bands:
		var band_rect := Rect2(band["x0"], 0.0, band["x1"] - band["x0"], band_height)
		tree_canvas.draw_rect(band_rect, band["color"])
		tree_canvas.draw_rect(band_rect, Color(0.3, 0.34, 0.42, 0.6), false, 1.0)
	var highlighted: Array[Dictionary] = []
	for edge in _edges:
		var color: Color = LINE_COLOR_MET if edge["met"] else LINE_COLOR_UNMET
		if _hovered_idea_id != "":
			if edge["from_id"] == _hovered_idea_id or edge["to_id"] == _hovered_idea_id:
				highlighted.append(edge)
				continue
			color.a = LINE_DIMMED_ALPHA
		tree_canvas.draw_polyline(edge["points"], color, LINE_WIDTH, true)
	for edge in highlighted:
		var color: Color = (LINE_COLOR_MET if edge["met"] else LINE_COLOR_UNMET).lightened(0.25)
		tree_canvas.draw_polyline(edge["points"], color, LINE_WIDTH_HIGHLIGHT, true)


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
