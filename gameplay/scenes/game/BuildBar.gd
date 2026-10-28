class_name BuildBar
extends CenterContainer

# Barra di costruzione sotto la mappa di GameScene, centrata in basso — il martello naviga dentro
# il sottomenu dei tipi di edificio (oggi capanna/stone circle/deposit site/stick tent, più
# placeholder vuoti), SOSTITUENDO la riga principale invece di affiancarla. UN SOLO bottone di
# controllo (niente back separato, deciso con l'utente) il cui significato/icona cambia in base al
# livello corrente: ▼ minimizza (da livello 1), ▲ riespande (da minimizzato), ← torna indietro (dalle
# categorie o dagli edifici) — sempre "un passo indietro nella gerarchia", mai un secondo bottone dedicato.
# Dal 2026-10-16 il martello apre prima le categorie (category_row), poi gli edifici della categoria scelta.
# (Il bottone 🧨 Demolisci di main_row, tolto il 2026-09-27, è tornato il 2026-10-14 accanto al martello: scegli
# l'edificio sulla mappa, confermi, l'edificio resta "da demolire" finché non assegni un demolitore. Resta anche il
# pulsante nel pannello edificio.)
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
# Riferimenti presi prima di _build_title_row, che sposta la riga dei pulsanti (i percorsi $ sotto non varrebbero più).
@onready var buttons_row: HBoxContainer = $Panel/MarginContainer/HBoxContainer
@onready var control_separator: VSeparator = $Panel/MarginContainer/HBoxContainer/VSeparator
@onready var main_row: IconButtonRow = $Panel/MarginContainer/HBoxContainer/ContentContainer/MainRow
@onready var submenu_row: IconButtonRow = $Panel/MarginContainer/HBoxContainer/ContentContainer/SubmenuRow
# Categorie degli edifici (2026-10-16, richiesta utente — "il costruisci comincia a essere complicato"): il martello apre
# questa riga; il clic su una categoria mostra submenu_row con i soli edifici di quella categoria (set_slot_visible: gli
# slot, le azioni "build_*" e il collegamento con GameScene restano quelli di prima). Gestita tutta qui dentro.
@onready var category_row: IconButtonRow = $Panel/MarginContainer/HBoxContainer/ContentContainer/CategoryRow
# I comandi del pipottino (CommandBar) non stanno più qui (2026-10-01, richiesta utente): pannello a sé alla sinistra di
# questa barra, sulla stessa riga in basso (GameScene._setup_command_bar, che sposta anche questa barra dentro la riga
# centrata a sinistra della sidebar). Questa barra resta per ciò che si piazza nel mondo (edifici, zone).

const OPEN_BUILD_MENU_ACTION := &"open_build_menu"
# Zone di lavoro (2026-09-27, richiesta utente — work areas): slot 1 di main_row, accanto al martello. Il clic emette
# action_pressed(WORK_AREAS_ACTION), ascoltato da GameScene (modalità "disegna area"); acceso solo a idea completata
# (set_work_areas_available, chiamata da GameScene come set_building_buildable).
const WORK_AREAS_ACTION := &"work_areas"
const WORK_AREAS_MAIN_ROW_SLOT_INDEX := 2
# Demolisci (2026-10-14, richiesta utente): slot 1 di main_row, accanto al martello. Il clic emette
# action_pressed(DEMOLISH_PICK_ACTION), ascoltato da GameScene (modalità "scegli l'edificio da demolire").
const DEMOLISH_PICK_ACTION := &"demolish_pick"
const DEMOLISH_MAIN_ROW_SLOT_INDEX := 1

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
	# Deposito coperto (2026-10-04, richiesta utente) — slot 12, prima della capanna di stoccaggio (ora 13);
	# submenu_row.slot_count portato a 15 in BuildBar.tscn; Hut resta l'ultimo a destra (slot 14).
	"covered_depot": 12,
	"storage_hut": 13,
	# Legnaia (2026-10-08, richiesta utente — segnaposto) — slot 14, submenu_row.slot_count portato a 16 in BuildBar.tscn;
	# Hut resta l'ultimo a destra (slot 15).
	"woodshed": 14,
	# Capanna del vestiario (2026-10-11, richiesta utente — segnaposto) — slot 15, submenu_row.slot_count portato a 17 in
	# BuildBar.tscn; Hut resta l'ultimo a destra (slot 16).
	"clothing_hut": 15,
	# Ceppo dell'insegnamento (2026-10-16, richiesta utente) — slot 16, submenu_row.slot_count portato a 18 in
	# BuildBar.tscn; Hut resta l'ultimo a destra (slot 17).
	"teaching_stump": 16,
	# Sentiero di ciottoli (2026-10-16, richiesta utente) — slot 17, submenu_row.slot_count portato a 19 in
	# BuildBar.tscn; Hut resta l'ultimo a destra (slot 18).
	"pebble_path": 17,
	# Spiazzo delle feste (2026-10-17, docs/design/feast_ground.md) — slot 18, submenu_row.slot_count portato a 20 in
	# BuildBar.tscn; Hut resta l'ultimo a destra (slot 19). Richiede paleolithic_constructions.
	"feast_ground": 18,
	# Fossa dei rifiuti (2026-10-18, richiesta utente) — slot 19, submenu_row.slot_count portato a 21 in BuildBar.tscn;
	# Hut resta l'ultimo a destra (slot 20). Categoria OTHER.
	"waste_pit": 19,
	# Palizzata (2026-10-23, richiesta utente) — slot 20, submenu_row.slot_count portato a 22 in BuildBar.tscn; Hut resta
	# l'ultimo a destra (slot 21). Categoria MILITARY, evoluzione del vallo. Richiede advanced_paleolithic_constructions.
	"palisade": 20,
	# Cancello (2026-10-23, richiesta utente) — slot 21, submenu_row.slot_count portato a 23; Hut resta l'ultimo (slot 22).
	"gate": 21,
	# Appoggio per travois (2026-10-23, richiesta utente) — slot 22, submenu_row.slot_count portato a 24; Hut resta l'ultimo
	# (slot 23). Categoria OTHER.
	"travois_rack": 22,
	# Capanna del guaritore (2026-10-25, richiesta utente) — slot 23, submenu_row.slot_count portato a 25; Hut resta
	# l'ultimo (slot 24).
	"healer_hut": 23,
	# Cerchio delle stelle (2026-10-27, era il Cerchio del consiglio dal 2026-10-26) — slot 24, submenu_row.slot_count 26;
	# Hut resta l'ultimo (slot 25). Categoria RELIGIOUS, richiede star_knowledge. Il Cerchio sacro (council_circle) non
	# ha slot: nasce solo migliorando questo.
	"star_circle": 24,
	"hut": 25,
}

# Ordine delle categorie in category_row, uno slot ciascuna (BuildBar.tscn: CategoryRow.slot_count = 10). RUINS esclusa:
# le macerie non si costruiscono. Una categoria nuova va aggiunta qui e allo slot_count.
const CATEGORY_ORDER: Array[int] = [
	BuildingTypes.Category.RESIDENTIAL,
	BuildingTypes.Category.STORAGE,
	BuildingTypes.Category.PRODUCTION,
	BuildingTypes.Category.CULTURAL,
	# Ricreativo (2026-10-17): CategoryRow.slot_count portato a 9.
	BuildingTypes.Category.RECREATIONAL,
	BuildingTypes.Category.RELIGIOUS,
	BuildingTypes.Category.POLITICAL,
	BuildingTypes.Category.MILITARY,
	BuildingTypes.Category.MOVEMENT,
	# Altro (2026-10-18, Fossa dei rifiuti): CategoryRow.slot_count portato a 10.
	BuildingTypes.Category.OTHER,
]
const CATEGORY_ICON_SIDE: float = 32.0

# LEVEL_1 = martello/Demolisci/Zone; CATEGORIES = category_row (titolo "Edifici"); BUILDINGS = submenu_row filtrata sulla
# categoria scelta (titolo = nome della categoria).
enum _ViewState { MINIMIZED, LEVEL_1, CATEGORIES, BUILDINGS }

var _state: _ViewState = _ViewState.LEVEL_1
# Categoria (BuildingTypes.Category) di ogni tipo in BUILDING_SLOT_INDEX_BY_TYPE, letta dalle regole in _ready.
var _category_by_type: Dictionary = {}
# Categoria aperta in BUILDINGS (-1 = nessuna).
var _current_category: int = -1
# Per ogni slot di category_row: il contenitore dell'icona (sostituita quando cambia l'edificio rappresentativo) e il
# tipo che mostra adesso ("" = ancora nessuno).
var _category_icon_holders: Array[Control] = []
var _category_icon_types: Array[String] = []
# Spunta "Nascondi superati" nella riga del titolo (UserOptions.build_bar_hide_superseded), visibile con le categorie e
# con gli edifici.
var _hide_superseded_check: Button = null
# Riga di titolo (2026-10-03, richiesta utente — stessa altezza della barra dei comandi): etichetta piccola sopra i
# pulsanti, stesso stile di "Azioni"/"Opzioni" (CommandBar.make_group_label). "Costruzione" a barra chiusa o al primo
# livello, "Edifici" nel sottomenu, "Zone di lavoro" mentre si disegna una zona (set_work_areas_mode, da GameScene).
var _title_label: Label = null
var _work_areas_mode: bool = false
# Scelta dell'orientamento di un miglioramento (2026-10-04, richiesta utente — sostituisce la striscia gialla in alto):
# titolo "<edificio> — Orientamento della porta" e, al posto di pulsante di controllo e icone, i tre comandi (R ruota,
# clic conferma, Esc annulla). Stesso pannello, stessa altezza (_orientation_hint_row alta quanto gli slot). Accesa e
# spenta da GameScene (set_upgrade_orientation_mode); spenta, la barra torna esattamente nello stato di prima.
const ORIENTATION_HINT_HEIGHT: float = 32.0
const ORIENTATION_HINT_FONT_SIZE: int = 12
const ORIENTATION_KEY_FONT_SIZE: int = 11
const ORIENTATION_HINT_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const ORIENTATION_KEY_BG := Color(0.0, 0.0, 0.0, 0.3)
const ORIENTATION_KEY_BORDER := Color(1.0, 1.0, 1.0, 0.55)
var _orientation_mode: bool = false
var _orientation_building_name: String = ""
var _orientation_hint_row: HBoxContainer = null


func _ready() -> void:
	main_row.configure_slot(0, "🔨", tr("build_bar_build_tooltip"), OPEN_BUILD_MENU_ACTION)
	var demolish_icon := BuildingCommandIcon.new()
	demolish_icon.kind = BuildingCommandIcon.KIND_DEMOLISH
	demolish_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	demolish_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_row.configure_slot(
		DEMOLISH_MAIN_ROW_SLOT_INDEX, "", tr("build_bar_demolish_tooltip"), DEMOLISH_PICK_ACTION, "", true, demolish_icon
	)
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
	# Legnaia (2026-10-08): richiede advanced_paleolithic_constructions, disabilitata da _refresh_building_slots_buildable.
	# Capanna del vestiario (2026-10-11): richiede advanced_paleolithic_constructions, come la legnaia.
	for placeholder_type in ["drying_rack", "smokehouse", "burial", "earthwork", "palisade", "gate", "stacked_stones", "woodshed", "clothing_hut", "teaching_stump", "pebble_path", "waste_pit", "travois_rack", "healer_hut", "star_circle"]:
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
	# Deposito coperto (2026-10-04, richiesta utente): richiede paleolithic_constructions; la capanna di stoccaggio ora
	# richiede advanced_paleolithic_constructions. Disabilitati da GameScene._refresh_building_slots_buildable finché manca.
	submenu_row.configure_slot(
		BUILDING_SLOT_INDEX_BY_TYPE["covered_depot"], "", tr("build_bar_covered_depot_tooltip"), &"build_covered_depot", "", true,
		IconRegistry.get_building_icon_node("covered_depot")
	)
	submenu_row.configure_slot(
		BUILDING_SLOT_INDEX_BY_TYPE["storage_hut"], "", tr("build_bar_storage_hut_tooltip"), &"build_storage_hut", "", true,
		IconRegistry.get_building_icon_node("storage_hut")
	)
	submenu_row.configure_slot(
		BUILDING_SLOT_INDEX_BY_TYPE["feast_ground"], "", tr("build_bar_feast_ground_tooltip"), &"build_feast_ground", "", true,
		IconRegistry.get_building_icon_node("feast_ground")
	)
	submenu_row.configure_slot(BUILDING_SLOT_INDEX_BY_TYPE["hut"], IconRegistry.get_building_icon("hut"), tr("build_bar_hut_tooltip"), &"build_hut")
	# Tooltip degli edifici (2026-10-07, richiesta utente): formato unico di BuildingCostTooltip, uguale a "Migliora".
	for building_type_name in BUILDING_SLOT_INDEX_BY_TYPE.keys():
		var slot_button := submenu_row.get_slot_button(BUILDING_SLOT_INDEX_BY_TYPE[building_type_name]) as TooltipButton
		if slot_button != null:
			slot_button.tooltip_builder = _building_tooltip.bind(String(building_type_name), slot_button)
	main_row.action_pressed.connect(_on_main_row_action_pressed)
	control_button.pressed.connect(_on_control_button_pressed)
	_build_category_row()
	_build_title_row()
	_build_orientation_hint_row()
	_refresh_building_filter()
	_apply_state()


# Slot delle categorie: icona in un contenitore (riempito da _refresh_building_filter), tooltip = nome della categoria.
func _build_category_row() -> void:
	for building_type_name in BUILDING_SLOT_INDEX_BY_TYPE.keys():
		var rules := BuildingCalculator.get_building_rules(String(building_type_name))
		_category_by_type[building_type_name] = int(rules.category) if rules != null else -1
	for i in range(CATEGORY_ORDER.size()):
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_category_icon_holders.append(holder)
		_category_icon_types.append("")
		category_row.configure_slot(
			i, "", _category_name(CATEGORY_ORDER[i]), StringName("build_category_%d" % i), "", true, holder
		)
	category_row.action_pressed.connect(_on_category_action_pressed)


func _category_name(category: int) -> String:
	return tr("building_category_" + String(BuildingTypes.Category.keys()[category]).to_lower())


# Abilitazione di un tipo = quella dello slot (set_building_buildable, decisa da GameScene): un'unica fonte.
func _is_type_buildable(building_type_name: String) -> bool:
	var slot := submenu_row.get_slot_button(int(BUILDING_SLOT_INDEX_BY_TYPE.get(building_type_name, -1))) as Button
	return slot != null and not slot.disabled


# Superato (2026-10-16, richiesta utente): con la spunta accesa, un edificio il cui miglioramento si può già costruire
# (non solo sbloccato: così non sparisce mai l'unica scelta, es. il sito di deposito finché il deposito coperto è spento).
func _is_type_hidden_as_superseded(building_type_name: String) -> bool:
	if not UserOptions.build_bar_hide_superseded:
		return false
	var rules := BuildingCalculator.get_building_rules(building_type_name)
	return rules != null and rules.upgrades_to != "" and _is_type_buildable(rules.upgrades_to)


# Edifici della categoria non nascosti, in ordine di slot.
func _visible_types_of_category(category: int) -> Array[String]:
	var result: Array[String] = []
	for building_type_name in BUILDING_SLOT_INDEX_BY_TYPE.keys():
		if int(_category_by_type.get(building_type_name, -1)) == category and not _is_type_hidden_as_superseded(building_type_name):
			result.append(String(building_type_name))
	result.sort_custom(func(a: String, b: String) -> bool: return int(BUILDING_SLOT_INDEX_BY_TYPE[a]) < int(BUILDING_SLOT_INDEX_BY_TYPE[b]))
	return result


# Ricalcola cosa si vede: slot degli edifici (categoria aperta, superati nascosti) e slot delle categorie (icona
# dell'edificio rappresentativo = l'ultimo costruibile in ordine di slot, altrimenti il primo; spenta se nessuno è
# costruibile; nascosta se la categoria non ha edifici nella barra).
func _refresh_building_filter() -> void:
	for building_type_name in BUILDING_SLOT_INDEX_BY_TYPE.keys():
		var shown := int(_category_by_type.get(building_type_name, -1)) == _current_category \
			and not _is_type_hidden_as_superseded(building_type_name)
		submenu_row.set_slot_visible(int(BUILDING_SLOT_INDEX_BY_TYPE[building_type_name]), shown)
	for i in range(CATEGORY_ORDER.size()):
		var types := _visible_types_of_category(CATEGORY_ORDER[i])
		category_row.set_slot_visible(i, not types.is_empty())
		if types.is_empty():
			continue
		var representative := types[0]
		var any_buildable := false
		for building_type_name in types:
			if _is_type_buildable(building_type_name):
				representative = building_type_name
				any_buildable = true
		category_row.set_slot_disabled(i, not any_buildable, tr("build_bar_category_none_available"))
		if representative != _category_icon_types[i]:
			_category_icon_types[i] = representative
			for child in _category_icon_holders[i].get_children():
				child.queue_free()
			_category_icon_holders[i].add_child(IconRegistry.build_building_icon_box(representative, CATEGORY_ICON_SIDE))


func _on_category_action_pressed(action_id: StringName) -> void:
	var index := int(String(action_id).trim_prefix("build_category_"))
	if index < 0 or index >= CATEGORY_ORDER.size():
		return
	_current_category = CATEGORY_ORDER[index]
	_state = _ViewState.BUILDINGS
	_refresh_building_filter()
	_apply_state()


func _on_hide_superseded_toggled(pressed: bool) -> void:
	UserOptions.build_bar_hide_superseded = pressed
	UserOptions.save_to_disk()
	_refresh_hide_superseded_text()
	_refresh_building_filter()


func _refresh_hide_superseded_text() -> void:
	_hide_superseded_check.text = ("☑ " if _hide_superseded_check.button_pressed else "☐ ") + tr("build_bar_hide_superseded")


# Tooltip di un bottone edificio (BuildingCostTooltip): nome, descrizione breve, materiali (senza l'allestimento),
# lavoro. Bottone spento: in fondo il motivo (`for_text` = tooltip di set_building_buildable, se diverso dal nome).
func _building_tooltip(for_text: String, building_type_name: String, slot_button: TooltipButton) -> Control:
	var title := tr("build_bar_%s_tooltip" % building_type_name)
	var rules := BuildingCalculator.get_building_rules(building_type_name)
	var extra_lines: Array[String] = []
	if slot_button.disabled and for_text != title:
		extra_lines.append(for_text)
	return BuildingCostTooltip.build(
		title, building_type_name, BuildingCostTooltip.get_build_materials(rules),
		rules.required_labor if rules != null else 0, extra_lines
	)


# Mette la riga dei pulsanti sotto un'etichetta di titolo, con la stessa separazione dei gruppi della barra dei comandi:
# a parità di margini le due barre hanno la stessa altezza e i pulsanti la stessa linea di base.
func _build_title_row() -> void:
	var margin: MarginContainer = $Panel/MarginContainer
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", CommandBar.GROUP_LABEL_SEPARATION)
	_title_label = CommandBar.make_group_label("")
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Titolo a sinistra, "Nascondi superati" a destra (2026-10-16): pulsante piatto a due stati con ☑/☐ nel testo, stesso
	# carattere piccolo del titolo e senza margini, così la riga del titolo non si alza (una CheckBox vera, con la sua
	# casella, la renderebbe più alta di quella della barra dei comandi).
	var title_row := HBoxContainer.new()
	title_row.add_child(_title_label)
	_hide_superseded_check = Button.new()
	_hide_superseded_check.toggle_mode = true
	_hide_superseded_check.flat = true
	_hide_superseded_check.focus_mode = Control.FOCUS_NONE
	_hide_superseded_check.tooltip_text = TooltipText.wrap(tr("build_bar_hide_superseded_tooltip"))
	_hide_superseded_check.add_theme_font_size_override("font_size", CommandBar.GROUP_LABEL_FONT_SIZE)
	for color_name in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color"]:
		_hide_superseded_check.add_theme_color_override(color_name, CommandBar.GROUP_LABEL_COLOR)
	for style_name in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		_hide_superseded_check.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
	_hide_superseded_check.set_pressed_no_signal(UserOptions.build_bar_hide_superseded)
	_refresh_hide_superseded_text()
	_hide_superseded_check.toggled.connect(_on_hide_superseded_toggled)
	title_row.add_child(_hide_superseded_check)
	margin.remove_child(buttons_row)
	margin.add_child(column)
	column.add_child(title_row)
	column.add_child(buttons_row)


# Riga dei tre comandi della scelta dell'orientamento, accanto (nascosta) a ContentContainer nella stessa riga dei pulsanti.
func _build_orientation_hint_row() -> void:
	_orientation_hint_row = HBoxContainer.new()
	_orientation_hint_row.custom_minimum_size.y = ORIENTATION_HINT_HEIGHT
	_orientation_hint_row.add_theme_constant_override("separation", 14)
	_orientation_hint_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_orientation_hint_row.visible = false
	_orientation_hint_row.add_child(_make_orientation_hint("R", tr("build_bar_orientation_rotate")))
	_orientation_hint_row.add_child(_make_orientation_hint(tr("build_bar_orientation_key_click"), tr("build_bar_orientation_confirm")))
	_orientation_hint_row.add_child(_make_orientation_hint("Esc", tr("build_bar_orientation_cancel")))
	buttons_row.add_child(_orientation_hint_row)


# Un comando: il tasto in un riquadro bordato, poi l'azione.
func _make_orientation_hint(key_text: String, action_text: String) -> HBoxContainer:
	var item := HBoxContainer.new()
	item.add_theme_constant_override("separation", 5)
	item.alignment = BoxContainer.ALIGNMENT_CENTER
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var key_style := StyleBoxFlat.new()
	key_style.bg_color = ORIENTATION_KEY_BG
	key_style.border_color = ORIENTATION_KEY_BORDER
	key_style.set_border_width_all(1)
	key_style.set_corner_radius_all(3)
	key_style.content_margin_left = 5
	key_style.content_margin_right = 5
	key_style.content_margin_top = 1
	key_style.content_margin_bottom = 1
	var key_panel := PanelContainer.new()
	key_panel.add_theme_stylebox_override("panel", key_style)
	key_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	key_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var key_label := Label.new()
	key_label.text = key_text
	key_label.add_theme_font_size_override("font_size", ORIENTATION_KEY_FONT_SIZE)
	key_label.add_theme_color_override("font_color", ORIENTATION_HINT_COLOR)
	key_panel.add_child(key_label)
	item.add_child(key_panel)
	var action_label := Label.new()
	action_label.text = action_text
	action_label.add_theme_font_size_override("font_size", ORIENTATION_HINT_FONT_SIZE)
	action_label.add_theme_color_override("font_color", ORIENTATION_HINT_COLOR)
	action_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	item.add_child(action_label)
	return item


# Scelta dell'orientamento di un miglioramento in corso o finita (GameScene._enter/_exit_upgrade_orientation_mode).
# `building_name` = nome già tradotto dell'edificio di destinazione.
func set_upgrade_orientation_mode(active: bool, building_name: String = "") -> void:
	if _orientation_mode == active and _orientation_building_name == building_name:
		return
	_orientation_mode = active
	_orientation_building_name = building_name
	_apply_state()


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
	if _orientation_mode:
		_title_label.text = tr("build_bar_title_upgrade_orientation").format({"building": _orientation_building_name})
	elif _work_areas_mode:
		_title_label.text = tr("build_bar_title_work_areas")
	elif _state == _ViewState.CATEGORIES:
		_title_label.text = tr("build_bar_title_buildings")
	elif _state == _ViewState.BUILDINGS:
		_title_label.text = _category_name(_current_category)
	else:
		_title_label.text = tr("build_bar_title_build")


# true se la barra è aperta sugli edifici (categorie o edifici di una categoria). Dal 2026-10-03 i comandi del pipottino
# restano visibili anche così (GameScene._sync_command_bar).
func is_build_menu_open() -> bool:
	return _state == _ViewState.CATEGORIES or _state == _ViewState.BUILDINGS


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
	# Categorie e superati dipendono dall'abilitazione (2026-10-16).
	_refresh_building_filter()


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
		_state = _ViewState.CATEGORIES
		_apply_state()


# Comportamento contestuale, sempre "un passo indietro": edifici -> categorie -> livello 1 -> minimizzato, e ▲ da
# minimizzato al livello 1; mai un salto di più livelli in un solo click.
func _on_control_button_pressed() -> void:
	match _state:
		_ViewState.MINIMIZED:
			_state = _ViewState.LEVEL_1
		_ViewState.LEVEL_1:
			_state = _ViewState.MINIMIZED
		_ViewState.CATEGORIES:
			_state = _ViewState.LEVEL_1
		_ViewState.BUILDINGS:
			_state = _ViewState.CATEGORIES
			_current_category = -1
			_refresh_building_filter()
	_apply_state()


func _apply_state() -> void:
	# Scelta dell'orientamento: solo i tre comandi; lo stato di menu (_state) non cambia e torna visibile all'uscita.
	control_button.visible = not _orientation_mode
	control_separator.visible = not _orientation_mode
	if _orientation_hint_row != null:
		_orientation_hint_row.visible = _orientation_mode
	content_container.visible = _state != _ViewState.MINIMIZED and not _orientation_mode
	main_row.visible = _state == _ViewState.LEVEL_1
	category_row.visible = _state == _ViewState.CATEGORIES
	submenu_row.visible = _state == _ViewState.BUILDINGS
	if _hide_superseded_check != null:
		_hide_superseded_check.visible = is_build_menu_open() and not _orientation_mode
	match _state:
		_ViewState.MINIMIZED:
			control_button.text = "▲"
		_ViewState.LEVEL_1:
			control_button.text = "▼"
		_ViewState.CATEGORIES, _ViewState.BUILDINGS:
			control_button.text = "←"
	_refresh_title()
