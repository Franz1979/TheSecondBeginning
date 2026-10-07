class_name GameInfoPanel
extends PanelContainer

# REGOLA FISSA DEL PROGETTO (2026-10-03, richiesta utente): l'info panel NON SI ALLARGA MAI, qualunque contenuto
# mostri. La larghezza è quella della Sidebar di GameScene.tscn (offset_left -300, l'unico punto in cui cambiarla;
# cresce verso sinistra: ogni aumento della larghezza minima di un figlio la allargherebbe). Prima del 2026-10-03 la
# larghezza vera la decideva il contenuto più largo (circa questa); ora è fissa e il contenuto deve starci dentro. Per qualunque modifica futura a questo pannello o alle schede
# di GameInfoTabs (individui, edifici, selezione, debug, altre):
#   - testi variabili (nomi, stati, valori, elenchi): Label con autowrap_mode (WORD_SMART) — va a capo nella larghezza;
#     in un HBoxContainer serve anche size_flags_horizontal = EXPAND_FILL, altrimenti si stringe a niente;
#   - testi che devono restare su una riga (titoli): clip_text + text_overrun_behavior ellissi;
#   - righe di elementi affiancati (icone, chip): HFlowContainer, o comunque una larghezza totale sicura;
#   - mai custom_minimum_size.x più largo della scheda.
# Garanzia strutturale (GameInfoTabs._lock_content_width): il contenuto di ogni scheda sta in un WidthClampContainer,
# che non propaga la larghezza minima dei figli e li dimensiona esattamente alla larghezza della scheda; quello che non
# può stringersi viene tagliato a destra, mai allarga il pannello. Gli scroll delle schede hanno lo scorrimento
# orizzontale disattivato: attivarlo darebbe ai figli la sola larghezza minima (testi a capo larghi zero, un carattere
# per riga). Un pannello nuovo aggiunto a una scheda va dentro quel contenitore (population_tab, buildings_tab,
# selection_content, debug_tab lo sono già).

# Pannello sidebar di GameScene (vista player su una singola macrocella). A differenza di
# WorldInfoPanel/MacroCellDetailPanel/MacroCellInfoPanel — dove le action bar vivono come
# sibling separati nella Sidebar della scena, non dentro il pannello — qui PrimaryActionsBar/
# SecondaryActionsBar sono DENTRO questo componente insieme al corpo: struttura confermata
# esplicitamente con l'utente, deliberatamente diversa dalla convenzione degli altri pannelli.
#
# Questo pannello resta comunque "muto" sul resto: non conosce GameSettings, world, game_data
# ne' change_scene_to_file — si limita a esporre le due IconButtonRow (pubbliche) e a
# configurarne icone/tooltip. Chi ascolta action_pressed e decide cosa fare è sempre
# GameScene.gd, stesso principio di separazione già in uso per gli altri pannelli.
#
# Nessun TitleLabel/CoordsLabel qui (rimossi/spostati nella DebugBar viola, richiesta utente
# 2026-09-01, per liberare due righe — coordinate ridondanti col resto della UI, titolo puramente
# decorativo). body_container ospita oggi UN SOLO figlio statico, GameInfoTabs (istanziato da
# GameScene._ready(), non qui — vedi commento in testa al file) — vegetation_info_panel/
# human_individual_info_panel vivono ANNIDATI dentro una delle sue tab (selection_tab), non
# sibling diretti qui.
#
# BodyScrollContainer RIMOSSO (2026-09-13, richiesta utente — bugfix: "la scrollbar fa scorrere in
# alto anche le tab", nascondendole) — introdotto il 2026-09-01 come rete di sicurezza generale
# attorno a body_container (vedi git history), ma con GameInfoTabs (un TabContainer, la cui barra
# schede è fissa SOLO se non è essa stessa dentro un contenitore che scorre) come suo unico figlio,
# avvolgerlo in uno ScrollContainer esterno faceva scorrere la barra schede insieme al contenuto
# invece di lasciarla ancorata in alto. Lo scroll è stato spostato DENTRO ciascuna tab di
# GameInfoTabs (PopulationScroll/BuildingsScroll/SelectionScroll, vedi GameInfoTabs.tscn/.gd) —
# così solo il contenuto SOTTO la barra schede (fissa, gestita nativamente da TabContainer) scorre,
# mai la barra stessa. Effetto collaterale positivo sul motivo originale del 2026-09-01 (MiniMapPanel
# + contenuto che spingeva SecondaryActionsBar fuori schermo): uno ScrollContainer riporta un
# minimo quasi nullo come proprio, quindi GameInfoTabs (size_flags_vertical=3 sotto) ora si limita
# a riempire lo spazio verticale disponibile tra MinimapSlot/SecondaryActionsBar e a scorrere
# internamente per QUALUNQUE tab, invece di dipendere da una rete di sicurezza esterna.
# size_flags_vertical=3 ora su BodyContainer stesso (prima solo sul BodyScrollContainer rimosso):
# nessuno ScrollContainer intermedio più a cui delegare l'espansione.
#
# minimap_panel NON vive più dentro body_container (bugfix, 2026-09-02: l'altezza di body_
# container/GameInfoTabs varia da scheda a scheda — TabContainer riporta come minimo solo quello
# della tab CORRENTE, non il massimo tra tutte — quindi la minimappa, come secondo figlio dentro
# quello stesso spazio a dimensione variabile, saliva/scendeva ad ogni cambio scheda). Vive invece
# in minimap_slot, un sibling FISSO di body_container/HSeparator2 nella VBoxContainer esterna —
# l'unico elemento con size_flags_vertical=EXPAND lì è body_container, quindi
# minimap_slot mantiene sempre la stessa altezza/posizione (appena sopra HSeparator2/
# SecondaryActionsBar) qualunque sia il contenuto delle tab sopra di lui, davvero "ancorato in
# basso" come richiesto.

@onready var primary_actions_bar: IconButtonRow = $MarginContainer/VBoxContainer/PrimaryActionsBar
@onready var body_container: VBoxContainer = $MarginContainer/VBoxContainer/BodyContainer
@onready var minimap_slot: Control = $MarginContainer/VBoxContainer/MinimapSlot
@onready var secondary_actions_bar: IconButtonRow = $MarginContainer/VBoxContainer/SecondaryActionsBar

# Tre zone, una funzione ciascuna (2026-10-07, richiesta utente):
#   - primary_actions_bar (in alto): solo il governo del villaggio — Idee, Assegnazione delle task, in futuro la gestione
#     dei magazzini (un bottone nuovo = uno slot libero configurato qui, la riga ha slot_count=5 posti). I bottoni ancora
#     da sbloccare sono visibili e SPENTI, con "Serve l'idea «…»" (stessa regola di Caccia/Taglia/Estrai); i posti liberi,
#     non usati da nessun bottone, sono nascosti. Senza nessuno slot visibile spariscono la riga e il separatore sotto
#     (refresh_governance_bar), nessun buco;
#   - le schede (BodyContainer), invariate;
#   - secondary_actions_bar (in basso): Statistiche, Livelli, stacco (tre volte lo spazio normale), Aiuto, Menu, centrati
#     come gruppo unico (IconButtonRow.add_group_gap_after).
# La riga in alto è allineata in colonna alle linguette delle schede (align_governance_bar_to_tabs): il primo posto,
# sopra la scheda degli abitanti, resta vuoto; Idee sopra la seconda scheda, Assegnazione sopra la terza, i posti
# successivi sopra le schede seguenti.
# Slot 0 di primary_actions_bar: albero delle idee (GameScene._refresh_tech_tree_button lo abilita/disabilita, regola di
# sempre: resta visibile).
const TECH_TREE_SLOT_INDEX := 0
# Slot 1 di primary_actions_bar: Assegnazione delle task (cassetto SideDrawer con TaskAssignmentPanel), spento finché
# l'idea TaskAssignmentPanel.REQUIRED_IDEA_ID non è completata (GameScene._refresh_task_assignment_button).
const TASK_ASSIGNMENT_SLOT_INDEX := 1
# Slot della barra in basso.
const STATISTICS_SLOT_INDEX := 0
# Bottone "Layer" (2026-09-27, richiesta utente — menu dei layer della mappa): dal 2026-10-07 nella barra in basso.
# L'icona disegnata è tenuta qui perché GameScene ne accende il segnale (LayersIcon.active) quando un layer è attivo; il
# menu lo apre GameScene (_open_map_layers_menu).
const MAP_LAYERS_SLOT_INDEX := 1
const HELP_SLOT_INDEX := 2
const MENU_SLOT_INDEX := 3
var map_layers_icon: LayersIcon = null

@onready var _governance_separator: HSeparator = $MarginContainer/VBoxContainer/HSeparator


func _ready() -> void:
	# toggle_animals_visibility/toggle_flora_updates e i due bottoni di navigazione debug
	# (world_debug/macro_cell_debug) sono stati spostati fuori da questo pannello, dentro
	# DebugBar (gameplay/scenes/game/DebugBar.gd/.tscn) — quella barra, non questa, resta
	# "muta" sullo stato reale (animals_visible/flora_daily_updates_enabled), GameScene decide
	# ancora tutto.
	#
	# 🎯 (era qui, slot 0) spostato dentro HumanIndividualInfoPanel/SelectionTab (richiesta
	# utente, 2026-09-04): concettualmente centriamo sempre sull'individuo mostrato in quella tab
	# (quello selezionato/sottolineato), quindi il bottone appartiene lì, non a una barra generica
	# sopra le tab — vedi HumanIndividualInfoPanel.center_requested/GameScene._ready.
	#
	# Slot 0 era un placeholder "statistiche" disabilitato (richiesta utente, 2026-09-04) — attivato
	# (Step A del piano statistiche, 2026-09-05): enabled=true (default), nessuna description (la
	# seconda riga del tooltip aveva senso solo per spiegare perché fosse disabilitato, non più
	# pertinente ora che apre davvero StatisticsPanel — vedi GameScene._on_primary_action_pressed).
	# Riga del governo (2026-10-07): Idee (apre TechTreePanel, abilitato/disabilitato da GameScene._refresh_tech_tree_button:
	# serve un edificio completo con accepts_thoughts) e Assegnazione (cassetto SideDrawer). Gli altri slot (slot_count=5
	# in .tscn) restano liberi e nascosti per i bottoni futuri.
	primary_actions_bar.configure_slot(TECH_TREE_SLOT_INDEX, "💡", tr("tech_tree_tooltip"), &"tech_tree")
	primary_actions_bar.configure_slot(TASK_ASSIGNMENT_SLOT_INDEX, "📋", tr("task_assignment_tooltip"), &"task_assignment")
	for slot_index in range(primary_actions_bar.slot_count):
		if slot_index != TECH_TREE_SLOT_INDEX and slot_index != TASK_ASSIGNMENT_SLOT_INDEX:
			primary_actions_bar.set_slot_visible(slot_index, false)
	refresh_governance_bar()

	# Barra in basso (2026-10-07): Statistiche e Livelli (prima nella riga in alto, stessi id e tooltip), poi ☰/❓ (mai
	# strumenti di debug: il menu di sistema e l'help sono UI definitiva).
	secondary_actions_bar.configure_slot(STATISTICS_SLOT_INDEX, "📊", tr("statistics_tooltip"), &"statistics")
	map_layers_icon = LayersIcon.new()
	secondary_actions_bar.configure_slot(MAP_LAYERS_SLOT_INDEX, "", tr("map_layers_tooltip"), &"map_layers", "", true, map_layers_icon)
	secondary_actions_bar.configure_slot(HELP_SLOT_INDEX, "❓", tr("help_tooltip"), &"help")
	secondary_actions_bar.configure_slot(MENU_SLOT_INDEX, "☰", tr("menu"), &"menu")
	# Due coppie al centro (2026-10-07): stacco largo tre volte lo spazio normale tra Livelli e Aiuto.
	secondary_actions_bar.add_group_gap_after(MAP_LAYERS_SLOT_INDEX, 3.0)


# Riga del governo in colonna con le linguette di `tab_bar` (GameInfoTabs, aggiunte da GameScene in body_container):
# il posto i sta sopra la linguetta visibile i + 1, largo quanto lei (la prima linguetta resta senza bottone sopra).
# Ricalcolata a ogni ridisegno delle linguette (una linguetta può cambiare larghezza, es. il numero di 🔔); assegna
# solo ciò che cambia. Le linguette stanno già nella larghezza del pannello, quindi anche la riga.
var _governance_tab_bar: TabBar = null


func align_governance_bar_to_tabs(tab_bar: TabBar) -> void:
	if tab_bar == null or _governance_tab_bar == tab_bar:
		return
	_governance_tab_bar = tab_bar
	tab_bar.draw.connect(_align_governance_bar)
	primary_actions_bar.item_rect_changed.connect(_align_governance_bar)
	_align_governance_bar()


func _align_governance_bar() -> void:
	if _governance_tab_bar == null or not is_instance_valid(_governance_tab_bar):
		return
	var tab_rects: Array[Rect2] = []
	for tab_index in range(_governance_tab_bar.tab_count):
		if not _governance_tab_bar.is_tab_hidden(tab_index):
			tab_rects.append(_governance_tab_bar.get_tab_rect(tab_index))
	if tab_rects.size() < 2:
		return
	var tabs_left := _governance_tab_bar.get_global_rect().position.x - primary_actions_bar.get_global_rect().position.x
	var slot_widths: Array[float] = []
	for tab_index in range(1, tab_rects.size()):
		slot_widths.append(tab_rects[tab_index].size.x)
	primary_actions_bar.align_to_columns(tabs_left + tab_rects[1].position.x, slot_widths)


# Riga del governo e separatore sotto nascosti se nessuno slot è visibile.
func refresh_governance_bar() -> void:
	var any_visible := primary_actions_bar.has_visible_slots()
	primary_actions_bar.visible = any_visible
	if _governance_separator != null:
		_governance_separator.visible = any_visible
