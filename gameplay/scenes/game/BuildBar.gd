class_name BuildBar
extends CenterContainer

# Barra di costruzione sotto la mappa di GameScene, centrata in basso — per ora SOLO presentazione:
# il martello naviga dentro il sottomenu dei tipi di edificio (oggi solo la capanna, più
# placeholder vuoti), SOSTITUENDO la riga principale invece di affiancarla. UN SOLO bottone di
# controllo (niente back separato, deciso con l'utente) il cui significato/icona cambia in base al
# livello corrente: ▼ minimizza (da livello 1), ▲ riespande (da minimizzato), ← torna indietro (da
# livello 2) — sempre "un passo indietro nella gerarchia", mai un secondo bottone dedicato. Nessuna
# azione reale collegata a GameScene (nessun piazzamento, nessuna verifica materiali/tech/spazio)
# — quei sistemi non esistono ancora.
#
# Radice CenterContainer apposta: ancorata a tutta larghezza in basso (vedi .tscn), pannello vero
# ricentrato automaticamente ad ogni cambio di contenuto (livello di menu attivo/minimizzazione)
# invece di una larghezza fissa indovinata a occhio. mouse_filter=IGNORE su questo nodo così la
# fascia vuota attorno al pannello vero (Panel, sotto) non intercetta i click destinati alla mappa.
# Stesso principio di "mutezza" di GameInfoPanel: questo componente non conosce World/GameData/
# Building, si limita a esporre main_row/submenu_row (pubblici) per un futuro collegamento a
# GameScene, quando esisterà davvero un'azione di costruzione (es. GameScene ascolterà
# submenu_row.action_pressed per il piazzamento vero).

@onready var control_button: Button = $Panel/MarginContainer/HBoxContainer/ControlButton
@onready var content_container: HBoxContainer = $Panel/MarginContainer/HBoxContainer/ContentContainer
@onready var main_row: IconButtonRow = $Panel/MarginContainer/HBoxContainer/ContentContainer/MainRow
@onready var submenu_row: IconButtonRow = $Panel/MarginContainer/HBoxContainer/ContentContainer/SubmenuRow

const OPEN_BUILD_MENU_ACTION := &"open_build_menu"

enum _ViewState { MINIMIZED, LEVEL_1, LEVEL_2 }

var _state: _ViewState = _ViewState.LEVEL_1


func _ready() -> void:
	main_row.configure_slot(0, "🔨", tr("build_bar_build_tooltip"), OPEN_BUILD_MENU_ACTION)
	# Slot 1+ di entrambe le righe restano placeholder vuoti (disabilitati/attenuati di default,
	# vedi IconButtonRow._ready) — pronti per le prossime categorie/tipi di edificio, nessuno
	# configurato ancora.
	submenu_row.configure_slot(0, "🛖", tr("build_bar_hut_tooltip"), &"build_hut")
	main_row.action_pressed.connect(_on_main_row_action_pressed)
	control_button.pressed.connect(_on_control_button_pressed)
	_apply_state()


# Il martello naviga dentro il sottomenu — lo sostituisce alla riga principale (mai simultanei).
# "build_hut" (dentro submenu_row) resta deliberatamente senza alcun listener.
func _on_main_row_action_pressed(action_id: StringName) -> void:
	if action_id == OPEN_BUILD_MENU_ACTION:
		_state = _ViewState.LEVEL_2
		_apply_state()


# Comportamento contestuale, sempre "un passo indietro": minimizzato -> livello 1 -> livello 2 ->
# livello 1 -> minimizzato, mai un salto diretto da livello 2 a minimizzato in un solo click.
func _on_control_button_pressed() -> void:
	match _state:
		_ViewState.MINIMIZED:
			_state = _ViewState.LEVEL_1
		_ViewState.LEVEL_1:
			_state = _ViewState.MINIMIZED
		_ViewState.LEVEL_2:
			_state = _ViewState.LEVEL_1
	_apply_state()


func _apply_state() -> void:
	content_container.visible = _state != _ViewState.MINIMIZED
	main_row.visible = _state == _ViewState.LEVEL_1
	submenu_row.visible = _state == _ViewState.LEVEL_2
	match _state:
		_ViewState.MINIMIZED:
			control_button.text = "▲"
		_ViewState.LEVEL_1:
			control_button.text = "▼"
		_ViewState.LEVEL_2:
			control_button.text = "←"
