class_name GameInfoPanel
extends PanelContainer

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
# sibling diretti qui. body_container vive dentro un BodyScrollContainer (bugfix, 2026-09-01: il
# minimo fisso di MiniMapPanel.ScrollContainer (originariamente 220x220, poi ridotto a 150x150
# nello stesso bugfix — vedi MiniMapPanel.BASE_SIZE) sommato al resto del contenuto poteva
# superare l'altezza reale della Sidebar su schermi/finestre meno alte, spingendo
# SecondaryActionsBar — l'ultima riga, con menu/help — fuori dall'area visibile invece di scorrere)
# — questo ScrollContainer resta comunque come rete di sicurezza generale, per qualunque contenuto
# futuro di body_container che tornasse a non starci. size_flags_vertical=3 solo sullo
# ScrollContainer (mai su BodyContainer stesso, che dentro uno ScrollContainer deve riportare la
# propria dimensione reale per far comparire la scrollbar quando serve, non richiedere tutto lo
# spazio disponibile).
#
# minimap_panel NON vive più dentro body_container (bugfix, 2026-09-02: l'altezza di body_
# container/GameInfoTabs varia da scheda a scheda — TabContainer riporta come minimo solo quello
# della tab CORRENTE, non il massimo tra tutte — quindi la minimappa, come secondo figlio dentro
# quello stesso spazio a dimensione variabile, saliva/scendeva ad ogni cambio scheda). Vive invece
# in minimap_slot, un sibling FISSO di BodyScrollContainer/HSeparator2 nella VBoxContainer
# esterna — l'unico elemento con size_flags_vertical=EXPAND lì è BodyScrollContainer, quindi
# minimap_slot mantiene sempre la stessa altezza/posizione (appena sopra HSeparator2/
# SecondaryActionsBar) qualunque sia il contenuto delle tab sopra di lui, davvero "ancorato in
# basso" come richiesto.

@onready var primary_actions_bar: IconButtonRow = $MarginContainer/VBoxContainer/PrimaryActionsBar
@onready var body_container: VBoxContainer = $MarginContainer/VBoxContainer/BodyScrollContainer/BodyContainer
@onready var minimap_slot: Control = $MarginContainer/VBoxContainer/MinimapSlot
@onready var secondary_actions_bar: IconButtonRow = $MarginContainer/VBoxContainer/SecondaryActionsBar


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
	primary_actions_bar.configure_slot(0, "📊", tr("statistics_tooltip"), &"statistics")

	# ☰/❓ restano qui (mai strumenti di debug): il menu di sistema e l'help sono UI definitiva.
	secondary_actions_bar.configure_slot(0, "☰", tr("menu"), &"menu")
	secondary_actions_bar.configure_slot(1, "❓", tr("help_tooltip"), &"help")
