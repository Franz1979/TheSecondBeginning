class_name BuildBar
extends CenterContainer

# Barra di costruzione sotto la mappa di GameScene, centrata in basso — il martello naviga dentro
# il sottomenu dei tipi di edificio (oggi capanna/stone circle/deposit site/stick tent, più
# placeholder vuoti), SOSTITUENDO la riga principale invece di affiancarla. UN SOLO bottone di
# controllo (niente back separato, deciso con l'utente) il cui significato/icona cambia in base al
# livello corrente: ▼ minimizza (da livello 1), ▲ riespande (da minimizzato), ← torna indietro (da
# livello 2) — sempre "un passo indietro nella gerarchia", mai un secondo bottone dedicato.
# (Il bottone 🧨 Demolisci di main_row è stato tolto il 2026-09-27: la demolizione parte dal pannello edificio.)
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
# I comandi del pipottino (CommandBar) non stanno più qui (2026-10-01, richiesta utente): pannello a sé alla sinistra di
# questa barra, sulla stessa riga in basso (GameScene._setup_command_bar, che sposta anche questa barra dentro la riga
# centrata a sinistra della sidebar). Questa barra resta per ciò che si piazza nel mondo (edifici, zone).

const OPEN_BUILD_MENU_ACTION := &"open_build_menu"
# Zone di lavoro (2026-09-27, richiesta utente — work areas): slot 1 di main_row, accanto al martello. Il clic emette
# action_pressed(WORK_AREAS_ACTION), ascoltato da GameScene (modalità "disegna area"); acceso solo a idea completata
# (set_work_areas_available, chiamata da GameScene come set_building_buildable).
const WORK_AREAS_ACTION := &"work_areas"
const WORK_AREAS_MAIN_ROW_SLOT_INDEX := 1

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
	# Terreno in terra battuta (2026-09-19, richiesta utente) — slot 3, submenu_row.slot_count portato
	# a 5 in BuildBar.tscn; Hut resta SEMPRE l'ultimo a destra (slot 4, richiesta utente).
	"dirt_ground": 3,
	# Focolare (2026-09-23, richiesta utente) — slot 4, submenu_row.slot_count portato a 6 in
	# BuildBar.tscn; Hut resta l'ultimo a destra (slot 5).
	"campfire": 4,
	# Capanna dell'attrezzista (2026-09-24, richiesta utente) — slot 5, submenu_row.slot_count portato
	# a 7 in BuildBar.tscn; Hut resta l'ultimo a destra (slot 6).
	"toolmaker_hut": 5,
	# Edifici segnaposto (2026-09-26, richiesta utente) — slot 6-9, submenu_row.slot_count portato a 11 in
	# BuildBar.tscn; Hut resta l'ultimo a destra (slot 10).
	"drying_rack": 6,
	"smokehouse": 7,
	"burial": 8,
	"earthwork": 9,
	# Tenda di pelli (2026-09-27, richiesta utente) — slot 10, submenu_row.slot_count portato a 12 in BuildBar.tscn;
	# Hut resta l'ultimo a destra (slot 11).
	"hide_tent": 10,
	# Pietre impilate (2026-10-02, richiesta utente) — slot 11, submenu_row.slot_count portato a 13 in BuildBar.tscn;
	# Hut resta l'ultimo a destra (slot 12).
	"stacked_stones": 11,
	# Capanna di stoccaggio (2026-10-03, richiesta utente) — slot 12, submenu_row.slot_count portato a 14 in
	# BuildBar.tscn; Hut resta l'ultimo a destra (slot 13).
	"storage_hut": 12,
	"hut": 13,
}

enum _ViewState { MINIMIZED, LEVEL_1, LEVEL_2 }

var _state: _ViewState = _ViewState.LEVEL_1
# Riga di titolo (2026-10-03, richiesta utente — stessa altezza della barra dei comandi): etichetta piccola sopra i
# pulsanti, stesso stile di "Azioni"/"Opzioni" (CommandBar.make_group_label). "Costruzione" a barra chiusa o al primo
# livello, "Edifici" nel sottomenu, "Zone di lavoro" mentre si disegna una zona (set_work_areas_mode, da GameScene).
var _title_label: Label = null
var _work_areas_mode: bool = false


func _ready() -> void:
	main_row.configure_slot(0, "🔨", tr("build_bar_build_tooltip"), OPEN_BUILD_MENU_ACTION)
	main_row.configure_slot(
		WORK_AREAS_MAIN_ROW_SLOT_INDEX, "", tr("build_bar_work_areas_tooltip"), WORK_AREAS_ACTION, "", true, WorkAreaIcon.new()
	)
	# Slot 1+ di main_row (e gli slot non configurati di submenu_row) restano placeholder vuoti
	# (disabilitati/attenuati di default, vedi IconButtonRow._ready) — pronti per le prossime
	# categorie/tipi di edificio, nessuno configurato ancora.
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
	submenu_row.configure_slot(
		1, "", tr("build_bar_deposit_site_tooltip"), &"build_deposit_site", "", true,
		IconRegistry.get_building_icon_node("deposit_site")
	)
	# Stick Tent (2026-09-12, richiesta utente) — stesso schema emoji-inline di deposit_site sopra
	# (icona "⛺", vedi IconRegistry.BUILDING_ICONS: già distintiva/riconoscibile da sé, un emoji
	# reale non un "placeholder" nel senso di forma disegnata a mano come i rametti di
	# SetupSiteAction — non serviva altro). Sempre abilitato di default come deposit_site (nessun
	# vincolo is_village_center/required_idea_id in stick_tent.tres, tier 0 disponibile da subito) —
	# _refresh_building_slots_buildable lo conferma sempre disponibile senza bisogno di un caso
	# speciale qui, stesso principio già valido per deposit_site. Slot 2 (scambiata con Hut,
	# richiesta utente 2026-09-12 — "inverti la tenda con hut").
	# Icona disegnata (2026-10-03, TentShapes) al posto dell'emoji ⛺.
	submenu_row.configure_slot(
		2, "", tr("build_bar_stick_tent_tooltip"), &"build_stick_tent", "", true,
		IconRegistry.get_building_icon_node("stick_tent")
	)
	# Terreno in terra battuta (2026-09-19, richiesta utente) — slot 3, sempre abilitato di default
	# (nessun required_idea_id/is_village_center in dirt_ground.tres), stesso principio degli altri.
	submenu_row.configure_slot(
		3, "", tr("build_bar_dirt_ground_tooltip"), &"build_dirt_ground", "", true,
		IconRegistry.get_building_icon_node("dirt_ground")
	)
	# Focolare (2026-09-23, richiesta utente) — slot 4, sempre abilitato di default (nessun
	# required_idea_id/is_village_center in campfire.tres).
	submenu_row.configure_slot(4, IconRegistry.get_building_icon("campfire"), tr("build_bar_campfire_tooltip"), &"build_campfire")
	# Capanna dell'attrezzista (2026-09-24, richiesta utente) — slot 5; richiede l'idea
	# paleolithic_constructions (required_idea_id in toolmaker_hut.tres), disabilitato da GameScene.
	# _refresh_building_slots_buildable finché manca, come la capanna.
	submenu_row.configure_slot(5, IconRegistry.get_building_icon("toolmaker_hut"), tr("build_bar_toolmaker_hut_tooltip"), &"build_toolmaker_hut")
	# Hut, ora slot 6 e sempre ULTIMA a destra (richiesta utente 2026-09-19; slot 6 dal 2026-09-24).
	for placeholder_type in ["drying_rack", "smokehouse", "burial", "earthwork", "stacked_stones"]:
		submenu_row.configure_slot(
			BUILDING_SLOT_INDEX_BY_TYPE[placeholder_type], "", tr("build_bar_%s_tooltip" % placeholder_type),
			StringName("build_%s" % placeholder_type), "", true, IconRegistry.get_building_icon_node(placeholder_type)
		)
	# Tenda di pelli (2026-09-27, richiesta utente): richiede paleolithic_constructions (required_idea_id in
	# hide_tent.tres), disabilitata da GameScene._refresh_building_slots_buildable finché manca.
	submenu_row.configure_slot(
		BUILDING_SLOT_INDEX_BY_TYPE["hide_tent"], "", tr("build_bar_hide_tent_tooltip"), &"build_hide_tent", "", true,
		IconRegistry.get_building_icon_node("hide_tent")
	)
	# Capanna di stoccaggio (2026-10-03, richiesta utente): richiede paleolithic_constructions (required_idea_id in
	# storage_hut.tres), disabilitata da GameScene._refresh_building_slots_buildable finché manca.
	submenu_row.configure_slot(
		BUILDING_SLOT_INDEX_BY_TYPE["storage_hut"], "", tr("build_bar_storage_hut_tooltip"), &"build_storage_hut", "", true,
		IconRegistry.get_building_icon_node("storage_hut")
	)
	submenu_row.configure_slot(BUILDING_SLOT_INDEX_BY_TYPE["hut"], IconRegistry.get_building_icon("hut"), tr("build_bar_hut_tooltip"), &"build_hut")
	main_row.action_pressed.connect(_on_main_row_action_pressed)
	control_button.pressed.connect(_on_control_button_pressed)
	_build_title_row()
	_apply_state()


# Mette la riga dei pulsanti sotto un'etichetta di titolo, con la stessa separazione dei gruppi della barra dei comandi:
# a parità di margini le due barre hanno la stessa altezza e i pulsanti la stessa linea di base.
func _build_title_row() -> void:
	var margin: MarginContainer = $Panel/MarginContainer
	var buttons_row: HBoxContainer = $Panel/MarginContainer/HBoxContainer
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", CommandBar.GROUP_LABEL_SEPARATION)
	_title_label = CommandBar.make_group_label("")
	margin.remove_child(buttons_row)
	margin.add_child(column)
	column.add_child(_title_label)
	column.add_child(buttons_row)


# Strumento delle zone di lavoro in uso (disegno di una zona): titolo "Zone di lavoro". Chiamata a ogni frame da
# GameScene._sync_command_bar; aggiorna solo quando cambia.
func set_work_areas_mode(active: bool) -> void:
	if _work_areas_mode == active:
		return
	_work_areas_mode = active
	_refresh_title()


func _refresh_title() -> void:
	if _title_label == null:
		return
	if _work_areas_mode:
		_title_label.text = tr("build_bar_title_work_areas")
	elif _state == _ViewState.LEVEL_2:
		_title_label.text = tr("build_bar_title_buildings")
	else:
		_title_label.text = tr("build_bar_title_build")


# true se la barra è aperta sugli edifici (livello 2). Dal 2026-10-03 i comandi del pipottino restano visibili anche
# così (GameScene._sync_command_bar).
func is_build_menu_open() -> bool:
	return _state == _ViewState.LEVEL_2


# Stile del pannello (stesso StyleBoxFlat del .tscn), riusato dal pannello dei comandi (GameScene._setup_command_bar).
func get_panel_style() -> StyleBox:
	return $Panel.get_theme_stylebox("panel")


# Il pannello visibile della barra (GameScene._setup_command_bar ne allinea l'altezza a quella del pannello comandi).
func get_panel() -> PanelContainer:
	return $Panel


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


# Bottone "Zone di lavoro" acceso o spento (2026-09-27): stesso schema di set_building_buildable, disabled_tooltip
# = motivo ("Richiede: …").
func set_work_areas_available(is_available: bool, disabled_tooltip: String = "") -> void:
	main_row.set_slot_disabled(WORK_AREAS_MAIN_ROW_SLOT_INDEX, not is_available, disabled_tooltip if not is_available else "")


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
	_refresh_title()
