class_name DebugBar
extends PanelContainer

# Barra di debug di GameScene — ancorata in alto a sinistra, colore volutamente diverso dal blu
# usato dal resto della UI (vedi .tscn) per segnalare visivamente che questi controlli sono
# temporanei e spariranno prima della build finale del player (stesso principio gia' scritto nei
# commenti di GameInfoPanel/GameScene per world_debug/macro_cell_debug, solo ora davvero separato
# dalla UI definitiva invece di conviverci dentro). Un solo bottone di controllo (stesso schema
# "un passo indietro" di BuildBar, qui pero' solo due stati — espanso/richiuso, nessuna gerarchia
# di sottomenu: 5 azioni piatte + un'etichetta, non categorie). Muta come GameInfoPanel/BuildBar:
# non conosce World/GameData, si limita a esporre content_row (pubblico, per set_slot_toggled) e
# set_coords() (pubblico) e a inoltrare action_pressed — GameScene resta l'unico posto che decide
# cosa fare. ContentGroup (ContentRow + CoordsLabel) e' il blocco che si nasconde/mostra insieme
# da _apply_state — coords/anno avanzamento sono debug tanto quanto i quattro toggle/salti
# originali (richiesta utente, 2026-09-01: liberare righe nella Sidebar).

@onready var control_button: Button = $MarginContainer/HBoxContainer/ControlButton
@onready var content_group: HBoxContainer = $MarginContainer/HBoxContainer/ContentGroup
@onready var content_row: IconButtonRow = $MarginContainer/HBoxContainer/ContentGroup/ContentRow
@onready var coords_label: Label = $MarginContainer/HBoxContainer/ContentGroup/CoordsLabel

signal action_pressed(action_id: StringName)

var _expanded: bool = true


func _ready() -> void:
	content_row.configure_slot(
		0, "🌱", tr("toggle_flora_updates_tooltip"), &"toggle_flora_updates", tr("toggle_flora_updates_description")
	)
	content_row.configure_slot(
		1, "🐇", tr("toggle_animals_visibility_tooltip"), &"toggle_animals_visibility",
		tr("toggle_animals_visibility_description")
	)
	content_row.configure_slot(
		2, "🌍", tr("game_info_world_debug"), &"world_debug", tr("game_info_world_debug_description")
	)
	content_row.configure_slot(
		3, "🔬", tr("game_info_macro_cell_debug"), &"macro_cell_debug", tr("game_info_macro_cell_debug_description")
	)
	# Spostato qui dalla CalendarHeaderContainer della Sidebar (richiesta utente, 2026-09-01) —
	# stesso action_id/tooltip di prima, solo il pannello che lo ospita e' cambiato.
	content_row.configure_slot(4, "+1", tr("advance_year_tooltip"), &"advance_year")
	content_row.action_pressed.connect(func(action_id: StringName) -> void: action_pressed.emit(action_id))
	control_button.pressed.connect(_on_control_button_pressed)
	_apply_state()


func _on_control_button_pressed() -> void:
	_expanded = not _expanded
	_apply_state()


func _apply_state() -> void:
	content_group.visible = _expanded
	control_button.text = "◀" if _expanded else "▶"
	# Questo nodo e' figlio diretto di CanvasLayer (non di un Container che lo ridimensiona da
	# solo), quindi il suo Rect2 resta quello scritto in .tscn finche' nessuno lo cambia
	# esplicitamente — reset_size() lo riporta alla propria dimensione minima corrente ad ogni
	# cambio di stato, cosi' il pannello si restringe davvero quando content_group si nasconde
	# invece di lasciare uno spazio viola vuoto della stessa larghezza di prima.
	reset_size()


# Inoltrato da GameScene per riflettere lo stato dei due toggle (flora/animali) — stesso schema
# di IconButtonRow.set_slot_toggled, GameScene continua a decidere QUANDO chiamarlo, questo
# metodo esiste solo perche' content_row non e' esposto direttamente al chiamante.
func set_slot_toggled(index: int, is_active: bool) -> void:
	content_row.set_slot_toggled(index, is_active)


# Spostato qui da GameInfoPanel.set_coords (richiesta utente, 2026-09-01) — stesso formato
# testuale di prima ("Coords: x, y"), GameScene chiama questo invece di quello.
func set_coords(x: int, y: int) -> void:
	coords_label.text = "Coords: " + str(x) + ", " + str(y)
