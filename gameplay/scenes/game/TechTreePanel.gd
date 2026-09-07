class_name TechTreePanel
extends Window

# Pannello Albero delle Tecnologie di GameScene (2026-09-07, richiesta utente) — stesso pattern di
# apertura/chiusura di StatisticsPanel (Window standalone, X nativa nascosta e resa inerte,
# CloseButton esplicito, trattato come dialogo bloccante da GameScene — visibility_changed
# collegato a _on_blocking_dialog_visibility_changed, mette in pausa il clock mentre è aperto).
#
# Dimensione FISSA (vedi .tscn), non auto-dimensionata via get_contents_minimum_size (a differenza
# di HelpDialog/SystemMenuDialog) — STESSO motivo già documentato in StatisticsPanel: il contenuto
# di questo pannello può crescere DOPO l'apertura (l'elenco idee completate — refresh_content sotto
# è richiamato dal bottone di debug "+1 Thought" SENZA richiudere/riaprire la finestra, richiesta
# esplicita utente). Un ricalcolo dinamico della dimensione rischierebbe di spingere CloseButton
# fuori dall'area visibile, esattamente come già successo a StatisticsPanel prima del suo stesso
# bugfix. CompletedListContainer vive dentro una ScrollContainer ad altezza fissa (stesso pattern
# DeathListScroll/FertileWomenListScroll di StatisticsPanel) per lo stesso motivo: scorre invece di
# spingere la finestra a crescere.
#
# Tutto ricalcolato AL VOLO ad ogni refresh_content() — nessuna cache, coerente con Folk.
# active_idea_id/thoughts_invested/completed_ideas che restano l'unica fonte di verità (stesso
# principio di StatisticsPanel verso GameData.death_events/birth_events).

# idea_id (2026-09-07, richiesta utente — popup di sblocco) — GameScene ne ha bisogno per risolvere
# display_name e comporre il messaggio di notifica; non lo cercava prima perché l'unico ascoltatore
# (_refresh_building_slots_buildable) non ne aveva bisogno, ma un connect() con MENO parametri di
# quanti il segnale ne emetta resta valido in Godot (l'argomento in eccesso viene scartato) —
# nessuna rottura del collegamento già esistente.
signal idea_completed(idea_id: String)

@onready var active_idea_label: Label = $MarginContainer/VBoxContainer/ActiveIdeaLabel
@onready var progress_bar: ProgressBar = $MarginContainer/VBoxContainer/ProgressBar
@onready var progress_label: Label = $MarginContainer/VBoxContainer/ProgressLabel
@onready var completed_caption: Label = $MarginContainer/VBoxContainer/CompletedCaption
@onready var completed_list_container: VBoxContainer = $MarginContainer/VBoxContainer/CompletedListScroll/CompletedListContainer
@onready var debug_add_thought_button: Button = $MarginContainer/VBoxContainer/DebugAddThoughtButton
@onready var close_button: Button = $MarginContainer/VBoxContainer/CloseButton

var _human_folk: Folk = null


func _ready() -> void:
	title = tr("tech_tree_title")
	completed_caption.text = tr("tech_tree_completed_caption")
	close_button.text = tr("close_menu")
	close_button.pressed.connect(hide)
	# close_requested NON collegato a hide() + X nascosta (stesso motivo/meccanismo già in uso da
	# StatisticsPanel/SystemMenuDialog): si chiude solo dal CloseButton esplicito.
	var transparent := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	add_theme_icon_override("close", transparent)
	add_theme_icon_override("close_pressed", transparent)

	# Bottone di debug (2026-09-07, richiesta utente) — SOSTITUISCE del tutto il vecchio tasto I di
	# GameScene._unhandled_input (rimosso): un solo punto d'accesso al debug avanzamento idee, dentro
	# questo pannello. Dietro DebugLogging.ENABLED, stesso principio già in uso per SpeedDebugButton/
	# DebugBar — mai visibile in una build "pulita".
	debug_add_thought_button.visible = DebugLogging.ENABLED
	debug_add_thought_button.text = tr("tech_tree_debug_add_thought")
	debug_add_thought_button.pressed.connect(_on_debug_add_thought_pressed)


func open_dialog(human_folk: Folk) -> void:
	_human_folk = human_folk
	refresh_content()
	exclusive = true
	popup_centered()


# Pubblica e richiamabile anche a finestra già aperta (dal bottone di debug sotto, o in futuro da
# un vero Think/DepositThoughtAction) — nessuna riapertura necessaria: il pannello riflette
# l'ultimo stato di _human_folk ogni volta che viene chiamata.
func refresh_content() -> void:
	if _human_folk == null:
		return

	if _human_folk.active_idea_id != "":
		var active_idea := IdeaCalculator.get_idea(_human_folk.active_idea_id)
		var invested: int = _human_folk.thoughts_invested.get(_human_folk.active_idea_id, 0)
		var cost: int = active_idea.thoughts_cost if active_idea != null else 0
		# tr() su display_name (2026-09-07, bugfix — era stato lasciato "non ancora deciso" in
		# Idea.gd, poi risolto come chiave tr() esattamente come BuildingRules.building_name: qui il
		# primo dei tre punti che devono avvolgerlo). Fallback all'id grezzo se l'Idea non si carica
		# (mai tr()-wrapped: non è una chiave di traduzione, è già un id leggibile solo per debug).
		var display_name: String = tr(active_idea.display_name) if active_idea != null else _human_folk.active_idea_id
		active_idea_label.text = tr("tech_tree_active_idea_label").format({"idea": display_name})
		progress_bar.visible = true
		# maxi(cost, 1) — guardia difensiva contro un'Idea con thoughts_cost=0/mal configurata:
		# ProgressBar.max_value a 0 sarebbe un caso limite degenere (divisione implicita per zero
		# nel calcolo interno della percentuale), mai un dato reale nei .tres attuali.
		progress_bar.max_value = maxi(cost, 1)
		progress_bar.value = invested
		progress_label.visible = true
		progress_label.text = "%d / %d" % [invested, cost]
	else:
		# active_idea_id vuoto — o non è mai stata avviata una ricerca, o l'ultima è stata appena
		# completata (add_thoughts la svuota, vedi IdeaProgressService) e IdeaProgressService non
		# ha trovato una prossima Idea disponibile (tutte completate, o prerequisiti non
		# soddisfatti) alla chiamata successiva: in entrambi i casi, stesso messaggio — questo
		# pannello non distingue i due casi (nessun dato da mostrare in nessuno dei due).
		active_idea_label.text = tr("tech_tree_no_active_idea")
		progress_bar.visible = false
		progress_label.visible = false

	for child in completed_list_container.get_children():
		child.queue_free()
	for idea_id in _human_folk.completed_ideas:
		var idea := IdeaCalculator.get_idea(idea_id)
		var label := Label.new()
		label.text = tr(idea.display_name) if idea != null else idea_id
		completed_list_container.add_child(label)


# Sostituisce del tutto il vecchio GameScene._debug_add_thought (richiesta esplicita utente) — la
# STESSA IdeaProgressService.add_thoughts(folk, 1) di prima, ora richiamata da qui. Non conosce
# BuildBar (questo pannello resta "muto" sul resto della UI, stesso principio di GameInfoPanel/
# BuildBar): si limita a segnalare un completamento con idea_completed, GameScene decide se/come
# reagire (vedi GameScene, che la collega a _refresh_building_slots_buildable).
func _on_debug_add_thought_pressed() -> void:
	if _human_folk == null:
		return
	var completed := IdeaProgressService.add_thoughts(_human_folk, 1)
	refresh_content()
	if completed:
		# completed_ideas[-1] (2026-09-07) — IdeaProgressService.add_thoughts fa sempre
		# completed_ideas.append(id) IMMEDIATAMENTE prima di ritornare true (unico scrittore di
		# questo array in tutto il progetto, vedi IdeaProgressService.gd): l'ultimo elemento è
		# garantito essere l'id appena completato, non serve che add_thoughts stessa lo ritorni.
		idea_completed.emit(_human_folk.completed_ideas[-1])
