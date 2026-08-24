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
# Corpo centrale (body_container) volutamente vuoto per ora — nessun dato ancora da mostrare
# (vedi task che ha introdotto questo file); quando ne avrà uno, questo è il contenitore
# predisposto.

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var coords_label: Label = $MarginContainer/VBoxContainer/CoordsLabel
@onready var primary_actions_bar: IconButtonRow = $MarginContainer/VBoxContainer/PrimaryActionsBar
@onready var body_container: VBoxContainer = $MarginContainer/VBoxContainer/BodyContainer
@onready var secondary_actions_bar: IconButtonRow = $MarginContainer/VBoxContainer/SecondaryActionsBar


func _ready() -> void:
	title_label.text = tr("game_info_panel_title")
	coords_label.text = ""

	# Stessa coppia di toggle di MacroCellScene (stessa icona/tooltip/action_id) — vedi
	# GameScene._on_primary_action_pressed per il comportamento: default entrambi ATTIVI
	# (animali visibili, aggiornamento giornaliero vegetazione attivo), questi bottoni servono a
	# DISATTIVARLI, non ad attivarli. Lo stato iniziale del toggle (set_slot_toggled) è
	# responsabilità di GameScene, non di questo pannello (che non conosce animals_visible/
	# flora_daily_updates_enabled).
	primary_actions_bar.configure_slot(
		0, "🐇", tr("toggle_animals_visibility_tooltip"), &"toggle_animals_visibility",
		tr("toggle_animals_visibility_description")
	)
	primary_actions_bar.configure_slot(
		1, "🌱", tr("toggle_flora_updates_tooltip"), &"toggle_flora_updates",
		tr("toggle_flora_updates_description")
	)

	# I due bottoni di navigazione debug (vedi GameScene._on_world_debug_pressed/
	# _on_macro_cell_debug_pressed) vivono qui, nella seconda riga insieme al menu — stesso
	# schema di MacroCellScene (menu/back_to_world/game_view): slot 1 lasciato apposta vuoto,
	# stesso spaziatore grigio già in uso li' per separare il bottone opzioni dai bottoni di
	# navigazione, accostati al bordo destro. Strumenti di debug (World/MacroCell): da rimuovere
	# o nascondere dietro un flag prima del player finale.
	secondary_actions_bar.configure_slot(0, "☰", tr("menu"), &"menu")
	secondary_actions_bar.configure_slot(
		2, "🌍", tr("game_info_world_debug"), &"world_debug", tr("game_info_world_debug_description")
	)
	secondary_actions_bar.configure_slot(
		3, "🔬", tr("game_info_macro_cell_debug"), &"macro_cell_debug", tr("game_info_macro_cell_debug_description")
	)


# Coordinate della macrocella del player — stesso formato di MacroCellDetailPanel.coords_label
# ("Coords: x, y"), impostate da GameScene (che conosce macro_cell) subito dopo aver risolto la
# cella di partenza. Vuote finche' GameScene non chiama questo metodo (vedi _ready() sopra).
func set_coords(x: int, y: int) -> void:
	coords_label.text = "Coords: " + str(x) + ", " + str(y)
