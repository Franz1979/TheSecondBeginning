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

# Indice slot in submenu_row per ogni tipo edificio (2026-09-07, richiesta utente — GENERALIZZATO
# da STONE_CIRCLE_SLOT_INDEX: un solo indice bastava finché il controllo di disponibilità
# riguardava solo lo Stone Circle, ora serve una mappa per qualunque tipo). Usata da
# set_building_buildable sotto — tenuta qui invece di ripetere l'indice in giro, per non
# disallinearsi silenziosamente da configure_slot(...) in _ready() se uno slot si spostasse.
const BUILDING_SLOT_INDEX_BY_TYPE := {
	"stone_circle": 0,
	"hut": 1,
}

enum _ViewState { MINIMIZED, LEVEL_1, LEVEL_2 }

var _state: _ViewState = _ViewState.LEVEL_1


func _ready() -> void:
	main_row.configure_slot(0, "🔨", tr("build_bar_build_tooltip"), OPEN_BUILD_MENU_ACTION)
	# Slot 2+ di entrambe le righe restano placeholder vuoti (disabilitati/attenuati di default,
	# vedi IconButtonRow._ready) — pronti per le prossime categorie/tipi di edificio, nessuno
	# configurato ancora.
	#
	# Stone Circle PRIMA della capanna (2026-09-07, richiesta utente: "il più a sinistra deve
	# essere Stone Circle") — solo ordine visivo/slot, nessun significato di priorità/categoria
	# dietro (vedi BUILDING_SLOT_INDEX_BY_TYPE sopra, aggiornata di conseguenza). Icona DISEGNATA
	# (StoneCircleIcon), non un emoji (richiesta utente, dopo due giri di feedback: 🗿 leggeva come
	# una testa dell'Isola di Pasqua, 🪨 come un mucchio di sassi — nessun emoji Unicode rende bene
	# "cerchio di pietre") — vedi IconButtonRow.configure_slot per come icon_node sostituisce
	# icon_text. Il vincolo di unicità/idea richiesta NON è verificato qui dentro (questo pannello
	# resta muto su World/Building/Folk, come da principio dichiarato in testa al file): abilitato
	# di default come ogni slot configurato, GameScene lo disabilita chiamando
	# set_building_buildable(...) quando rileva che un Building con rules.is_village_center esiste
	# già, o che manca l'Idea richiesta (vedi quel metodo sotto).
	submenu_row.configure_slot(
		0, "", tr("build_bar_stone_circle_tooltip"), &"build_stone_circle", "", true, StoneCircleIcon.new()
	)
	submenu_row.configure_slot(1, "🛖", tr("build_bar_hut_tooltip"), &"build_hut")
	main_row.action_pressed.connect(_on_main_row_action_pressed)
	control_button.pressed.connect(_on_control_button_pressed)
	_apply_state()


# Chiamato da GameScene (2026-09-07, richiesta utente — GENERALIZZATO da set_stone_circle_buildable,
# che copriva solo lo Stone Circle/is_village_center: ora copre qualunque tipo edificio e qualunque
# motivo di indisponibilità, es. anche BuildingRules.required_idea_id mancante da Folk.
# completed_ideas) ogni volta che la disponibilità di un tipo può essere cambiata — avvio scena
# (copre anche un salvataggio caricato con stato già avanzato) e subito dopo un piazzamento
# riuscito, così i bottoni si aggiornano immediatamente senza dover riaprire il sottomenu.
# GameScene fa il controllo vero (macro_world.buildings/human_folk.completed_ideas, che questo
# pannello non conosce), questo metodo si limita a riflettere il risultato sullo slot corrispondente:
# disabilitato + tooltip "perché" quando is_buildable è false, stato normale altrimenti.
# building_type_name sconosciuto (nessuno slot mappato) è un no-op silenzioso — non ogni tipo
# esistente ha necessariamente un bottone in questa barra.
func set_building_buildable(building_type_name: String, is_buildable: bool, disabled_tooltip: String = "") -> void:
	if not BUILDING_SLOT_INDEX_BY_TYPE.has(building_type_name):
		return
	submenu_row.set_slot_disabled(
		BUILDING_SLOT_INDEX_BY_TYPE[building_type_name], not is_buildable,
		disabled_tooltip if not is_buildable else ""
	)


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
