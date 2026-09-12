class_name BuildBar
extends CenterContainer

# Barra di costruzione sotto la mappa di GameScene, centrata in basso — il martello naviga dentro
# il sottomenu dei tipi di edificio (oggi capanna/stone circle/deposit site/stick tent, più
# placeholder vuoti), SOSTITUENDO la riga principale invece di affiancarla. UN SOLO bottone di
# controllo (niente back separato, deciso con l'utente) il cui significato/icona cambia in base al
# livello corrente: ▼ minimizza (da livello 1), ▲ riespande (da minimizzato), ← torna indietro (da
# livello 2) — sempre "un passo indietro nella gerarchia", mai un secondo bottone dedicato.
# Demolisci (2026-09-12) è la PRIMA azione di main_row con una vera azione collegata a GameScene
# (main_row.action_pressed, ascoltato DA GameScene — vedi DEMOLISH_ACTION sotto): questa classe resta
# comunque muta su World/Building (nessuna verifica/logica di demolizione qui dentro), si limita a
# emettere l'action_id ed esporre main_row per il feedback visivo (set_slot_toggled).
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
# da PEBBLE_CIRCLE_SLOT_INDEX: un solo indice bastava finché il controllo di disponibilità
# riguardava solo lo Pebble Circle, ora serve una mappa per qualunque tipo). Usata da
# set_building_buildable sotto — tenuta qui invece di ripetere l'indice in giro, per non
# disallinearsi silenziosamente da configure_slot(...) in _ready() se uno slot si spostasse.
const BUILDING_SLOT_INDEX_BY_TYPE := {
	"pebble_circle": 0,
	"deposit_site": 1,
	# Stick Tent PRIMA della capanna (2026-09-12, richiesta utente — "inverti la tenda con hut nei
	# bottoni sotto": Stick Tent era stata aggiunta in coda come quarto slot, ora scambiata di
	# posto con Hut, slot 3 -> 2) — submenu_row.slot_count è già 4 (vedi BuildBar.tscn), nessuna
	# modifica alla scena necessaria, solo l'indice qui e l'ordine delle configure_slot sotto.
	"stick_tent": 2,
	"hut": 3,
}

enum _ViewState { MINIMIZED, LEVEL_1, LEVEL_2 }

var _state: _ViewState = _ViewState.LEVEL_1

# Azione + indice slot per Demolisci (2026-09-12, richiesta utente — "attiva il bottone Demolisci")
# — pubblici perché GameScene deve ascoltare main_row.action_pressed per QUESTA azione specifica
# (BuildBar._on_main_row_action_pressed sotto ignora qualunque action_id diverso da
# OPEN_BUILD_MENU_ACTION, quindi "demolish" non viene consumato qui dentro) e deve poter riflettere
# lo stato "modalità selezione bersaglio attiva" sul bottone stesso (set_slot_toggled) — stesso
# principio di BUILDING_SLOT_INDEX_BY_TYPE sopra: l'indice vive UNA volta qui, non ridigitato altrove.
const DEMOLISH_ACTION := &"demolish"
const DEMOLISH_MAIN_ROW_SLOT_INDEX := 1


func _ready() -> void:
	main_row.configure_slot(0, "🔨", tr("build_bar_build_tooltip"), OPEN_BUILD_MENU_ACTION)
	# Demolisci (2026-09-12, richiesta utente — ATTIVATO in questo passo: prima SOLO presentazione,
	# enabled=false, nessuna logica collegata da nessuna parte). Ora enabled=true: un click emette
	# action_pressed(DEMOLISH_ACTION) su main_row, ascoltato da GameScene (non da questa classe, che
	# resta muta su World/Building — vedi il commento in testa al file) per entrare in "modalità
	# selezione bersaglio" (prossimo click sinistro su un edificio nel mondo).
	main_row.configure_slot(DEMOLISH_MAIN_ROW_SLOT_INDEX, "🧨", tr("build_bar_demolish_tooltip"), DEMOLISH_ACTION)
	# Slot 3+ di entrambe le righe restano placeholder vuoti (disabilitati/attenuati di default,
	# vedi IconButtonRow._ready) — pronti per le prossime categorie/tipi di edificio, nessuno
	# configurato ancora.
	#
	# Pebble Circle PRIMA della capanna (2026-09-07, richiesta utente: "il più a sinistra deve
	# essere Pebble Circle") — solo ordine visivo/slot, nessun significato di priorità/categoria
	# dietro (vedi BUILDING_SLOT_INDEX_BY_TYPE sopra, aggiornata di conseguenza). Icona DISEGNATA
	# (PebbleCircleIcon), non un emoji (richiesta utente, dopo due giri di feedback: 🗿 leggeva come
	# una testa dell'Isola di Pasqua, 🪨 come un mucchio di sassi — nessun emoji Unicode rende bene
	# "cerchio di sassolini") — vedi IconButtonRow.configure_slot per come icon_node sostituisce
	# icon_text. Il vincolo di unicità/idea richiesta NON è verificato qui dentro (questo pannello
	# resta muto su World/Building/Folk, come da principio dichiarato in testa al file): abilitato
	# di default come ogni slot configurato, GameScene lo disabilita chiamando
	# set_building_buildable(...) quando rileva che un Building con rules.is_village_center esiste
	# già, o che manca l'Idea richiesta (vedi quel metodo sotto).
	# Icona letta da IconRegistry.get_building_icon_node (2026-09-09, richiesta utente — stessa
	# migrazione già fatta per pebble/stick: "quel commento [pebble_circle assente apposta] è
	# obsoleto... farei come facciamo sia per sticks icon che per pebble icon, che passano
	# nell'icon registry") — non più PebbleCircleIcon.new() istanziata direttamente qui.
	submenu_row.configure_slot(
		0, "", tr("build_bar_pebble_circle_tooltip"), &"build_pebble_circle", "", true,
		IconRegistry.get_building_icon_node("pebble_circle")
	)
	# Deposit Site, appena a destra dello Pebble Circle (2026-09-08, richiesta utente) — sempre
	# abilitato di default come ogni slot configurato (nessun vincolo is_village_center/
	# required_idea_id in deposit_site.tres), _refresh_building_slots_buildable lo conferma sempre
	# disponibile senza bisogno di un caso speciale qui.
	# Icone lette da IconRegistry (2026-09-09, richiesta utente — prima "🟫"/"🛖" inline qui, uniche
	# fonti di verità: nessun altro punto del progetto poteva riusare la stessa icona capanna senza
	# riscriverla a mano) — chiavi = building_type_name, stessa convenzione di
	# BUILDING_SLOT_INDEX_BY_TYPE sopra.
	submenu_row.configure_slot(1, IconRegistry.get_building_icon("deposit_site"), tr("build_bar_deposit_site_tooltip"), &"build_deposit_site")
	# Stick Tent (2026-09-12, richiesta utente) — stesso schema emoji-inline di deposit_site sopra
	# (icona "⛺", vedi IconRegistry.BUILDING_ICONS: già distintiva/riconoscibile da sé, un emoji
	# reale non un "placeholder" nel senso di forma disegnata a mano come i rametti di
	# SetupSiteAction — non serviva altro). Sempre abilitato di default come deposit_site (nessun
	# vincolo is_village_center/required_idea_id in stick_tent.tres, tier 0 disponibile da subito) —
	# _refresh_building_slots_buildable lo conferma sempre disponibile senza bisogno di un caso
	# speciale qui, stesso principio già valido per deposit_site. Slot 2 (scambiata con Hut,
	# richiesta utente 2026-09-12 — "inverti la tenda con hut").
	submenu_row.configure_slot(2, IconRegistry.get_building_icon("stick_tent"), tr("build_bar_stick_tent_tooltip"), &"build_stick_tent")
	# Hut, ora slot 3 (scambiata con Stick Tent, richiesta utente 2026-09-12).
	submenu_row.configure_slot(3, IconRegistry.get_building_icon("hut"), tr("build_bar_hut_tooltip"), &"build_hut")
	main_row.action_pressed.connect(_on_main_row_action_pressed)
	control_button.pressed.connect(_on_control_button_pressed)
	_apply_state()


# Chiamato da GameScene (2026-09-07, richiesta utente — GENERALIZZATO da set_pebble_circle_buildable,
# che copriva solo lo Pebble Circle/is_village_center: ora copre qualunque tipo edificio e qualunque
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
# Le azioni "build_*" (dentro submenu_row) sono ascoltate da GameScene
# (build_bar.submenu_row.action_pressed -> _on_build_submenu_action_pressed), non da questo
# pannello — commento precedente ("resta deliberatamente senza alcun listener") superato da quel
# collegamento, corretto qui.
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
