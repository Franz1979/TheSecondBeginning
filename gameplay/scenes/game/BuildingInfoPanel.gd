class_name BuildingInfoPanel
extends VBoxContainer

# Corpo del pannello edificio dentro GameInfoTabs.selection_content — Step 5 del piano "centra
# generalizzato + selezione edifici" (richiesta utente, 2026-09-04), stesso principio "muto" di
# VegetationInfoPanel/HumanIndividualInfoPanel: istanziato dinamicamente da GameScene, riceve solo
# l'oggetto Building già risolto (stesso schema di HumanIndividualInfoPanel.show_individual, che
# prende l'HumanIndividual intero) — non conosce GameScene/selezione/BuildingCalculator. Label
# tr()-wrapped (richiesta utente 2026-09-06, insieme a VegetationInfoPanel/HumanIndividualInfoPanel/
# DeadBodyInfoPanel): solo le chiavi, nessuna riga aggiunta ancora a strings.csv/
# strings.it.translation. building.rules.building_name già tr()-wrapped da prima (documentato in
# BuildingRules stessa). Nascosto di default (nessuna selezione all'apertura della scena). Solo
# consultazione, nessuna interazione (a differenza di VegetationInfoPanel.cut_requested) — non
# esiste ancora alcuna azione giocatore su un edificio già piazzato.
#
# TypeLabel (Step 6, richiesta utente 2026-09-04): mai esistita qui come nodo separato dall'inizio
# — sollevata direttamente dentro GameInfoTabs.title_label, sulla STESSA riga del bottone "🎯".
# GameScene la imposta (game_info_tabs.set_selection_title) subito insieme a show_building, con la
# stessa formula tr(building.rules.building_name)/building_type_name che sarebbe finita qui.
#
# StorageGrid (2026-09-09, richiesta utente — sostituisce StoredResourcesLabel, un flat testo
# "resource_name quantity, ..." che non comunicava lo spazio/slot occupati) — griglia di
# building.rules.storage_slot_count riquadri (es. deposit_site = 9 -> 3x3), uno per SLOT, non uno
# per tipo di risorsa: vedi BuildingStorageService.get_slot_breakdown per il modello "slot univoci"
# (una risorsa può occupare più slot consecutivi, mai condivisi con un'altra risorsa). Ogni slot
# pieno mostra l'icona della risorsa (stesso fallback a 3 livelli — icona disegnata/emoji/iniziale
# — già in uso in HumanIndividualInfoPanel per il riquadro trasportato) più il numero di OGGETTI
# presenti (non lo spazio occupato — 2026-09-10, richiesta utente, vedi _build_storage_slot per il
# perché), con tooltip al passaggio del mouse (solo nome risorsa) e una barra verticale di
# riempimento sul bordo destro (spazio_occupato/capacità, a colpo d'occhio). Slot oltre quelli
# restituiti da
# get_slot_breakdown sono vuoti (grigio spento, nessuna icona/tooltip/barra).
#
# Sezione "Impostazioni" (2026-09-09, richiesta utente) — DENTRO questo pannello, non un menu/
# popup a parte (deciso esplicitamente con l'utente: nessun pattern "icona in un pannello di
# selezione apre un secondo pannello" esiste già nel progetto, costruirne uno per due checkbox +
# un bottone placeholder è prematuro — se le impostazioni-edificio cresceranno, estrarle in un
# pannello dedicato resta un refactor contenuto). Strutturata GENERICA/estensibile per tipo, non
# hardcoded al solo storage: _refresh_settings_section sotto è il punto in cui una futura
# capacità diversa (edificio X ha la caratteristica Y) aggiungerebbe il proprio blocco — oggi
# l'unico blocco esistente è "building.rules.storage_slot_count > 0 -> mostra i toggle categoria".
# Toggle categoria (Building.enabled_categories, il filtro PER-ISTANZA — vedi BuildingStorageService.
# can_accept) mostrati SOLO tra le categorie che il TIPO già accetta (building.rules.
# accepted_categories, o TUTTE le categorie esistenti se il tipo non ha restrizioni proprie — vuoto
# = nessun limite di tipo) — richiesta esplicita utente: l'istanza può solo restringere, mai
# scegliere tra categorie che il tipo comunque rifiuterebbe.

# Emesso quando il player preme EmptyAllButton (2026-09-11, richiesta utente — "abilita il button
# empty all con il comando che davvero azzera tutto il materiale... per ora non pensiamo a dove
# vada, lo fai solo sparire dal gioco e dal deposito") — stesso principio "muto" di
# VegetationInfoPanel.cut_requested: questo pannello non tocca mai Building.stored_resources da sé,
# si limita a segnalare l'intenzione, GameScene decide se/come agire (qui: svuota per davvero + le
# necessarie chiamate di refresh alla mappa, che questo pannello non ha modo di raggiungere). A
# DIFFERENZA di cut_requested (nessun payload, GameScene tiene la propria selezione a parte), qui
# building è passato ESPLICITO nel segnale: più diretto che far ri-risolvere a GameScene lo stesso
# _current_building che questo pannello ha già in mano.
signal empty_all_requested(building: Building)

# Emesso al click su un'icona OCCUPATA della griglia residenti (2026-09-12, richiesta utente —
# "puoi fare che la icona delle persone nella vista edificio funzioni come un centra su di loro?")
# — stesso principio "muto" di empty_all_requested sopra: questo pannello non sa cosa significhi
# "centrare la camera"/selezionare un individuo (nessun riferimento a GameScene/human_individuals
# oltre ai Dictionary già risolti che gli arrivano), si limita a segnalare QUALE individuo (per id,
# l'unico dato stabile che ha in mano — mai un riferimento HumanIndividual vivo, che questo
# pannello non possiede). GameScene risolve l'id sul vero oggetto e riusa la STESSA funzione già
# dietro al bottone "🎯" per-riga del pannello popolazione (_on_population_individual_center_
# requested) — stesso comportamento "seleziona+centra" ovunque nel progetto, non una variante
# diversa solo per questo pannello.
signal resident_center_requested(individual_id: int)

const STORAGE_SLOT_SIZE: float = 32.0
const EMPTY_STORAGE_SLOT_COLOR := Color(0.3, 0.3, 0.3, 0.4)

# Griglia residenti (2026-09-12, richiesta utente — "quadrati simili a quelli dello storage per
# rappresentare individui residenti") — STESSA dimensione/STESSO colore slot-vuoto di StorageGrid
# sopra, costanti DUPLICATE apposta (non condivise) invece di riusare STORAGE_SLOT_SIZE/
# EMPTY_STORAGE_SLOT_COLOR direttamente: stesso principio già in uso altrove nel progetto per due
# concetti visivamente simili ma concettualmente indipendenti (es. BuildingGhost/MicroCellRenderer
# duplicano la stessa geometria invece di condividerla) — un domani le due griglie potrebbero
# divergere (dimensione slot diversa, ecc.) senza che l'una trascini l'altra.
const RESIDENT_SLOT_SIZE: float = 32.0
const EMPTY_RESIDENT_SLOT_COLOR := Color(0.3, 0.3, 0.3, 0.4)
# Sfondo neutro/caldo per uno slot OCCUPATO (a differenza degli slot storage, che usano
# IconRegistry.get_resource_color per tipo di risorsa — qui non esiste un "tipo" di persona da
# colorare diversamente, un solo colore neutro per ogni residente, l'icona sopra fa la
# distinzione uomo/donna/bimbo/bimba).
const OCCUPIED_RESIDENT_SLOT_COLOR := Color(0.72, 0.62, 0.48, 1.0)

# "Serbatoietto" di riempimento slot (2026-09-10, richiesta utente — "se vogliamo esagerare
# potremmo provare a mettere sull'icona una specie di serbatoietto") — striscia verticale sul bordo
# destro dello slot, alta quanto lo slot intero (track, sempre visibile, semitrasparente) con sopra
# una seconda striscia (fill) ancorata al FONDO la cui altezza è space_used/space_capacity ×
# STORAGE_SLOT_SIZE — si riempie dal basso verso l'alto come un vero serbatoio. Posizione/size
# ESPLICITI (non anchor), non serve l'anchor math altrove usato per icon_node/space_label: box è
# sempre esattamente STORAGE_SLOT_SIZE×STORAGE_SLOT_SIZE (custom_minimum_size fissa), nessun
# ridimensionamento dinamico da inseguire.
const STORAGE_SLOT_FILL_BAR_WIDTH: float = 4.0
const STORAGE_SLOT_FILL_BAR_TRACK_COLOR := Color(0.0, 0.0, 0.0, 0.5)
const STORAGE_SLOT_FILL_BAR_FILL_COLOR := Color(1.0, 1.0, 1.0, 0.85)

@onready var status_label: Label = $StatusLabel
@onready var construction_phase_label: Label = $ConstructionPhaseLabel
@onready var construction_progress_bar: ProgressBar = $ConstructionProgressBar
@onready var awaiting_material_label: Label = $AwaitingMaterialLabel
@onready var durability_label: Label = $DurabilityLabel
@onready var built_year_label: Label = $BuiltYearLabel
@onready var residents_caption: Label = $ResidentsCaption
@onready var residents_grid: GridContainer = $ResidentsGrid
@onready var storage_caption: Label = $StorageCaption
@onready var storage_grid: GridContainer = $StorageGrid
@onready var id_label: Label = $IdLabel
@onready var settings_separator: HSeparator = $SettingsSeparator
@onready var settings_caption: Label = $SettingsCaption
@onready var accepted_categories_caption: Label = $AcceptedCategoriesCaption
@onready var category_toggles_container: VBoxContainer = $CategoryTogglesContainer
@onready var empty_all_button: Button = $EmptyAllButton

# Edificio correntemente mostrato (2026-09-09) — MAI esistito prima come campo: show_building
# riceveva `building` solo come parametro locale, nessun consumatore ne aveva bisogno dopo il
# ritorno della funzione. I toggle categoria sotto sono l'eccezione: un CheckBox premuto dal
# player deve sapere SU QUALE Building scrivere enabled_categories, in un momento (il callback
# `toggled`) in cui `building` del parametro originale non è più in scope — stesso motivo per cui
# un riferimento va tenuto qui, non ricavato altrove (questo pannello non conosce GameScene/
# selezione, resta "muto" come dichiarato in testa al file).
var _current_building: Building = null


func _ready() -> void:
	clear()
	residents_caption.text = tr("building_residents_caption")
	storage_caption.text = tr("building_storage_caption")
	settings_caption.text = tr("building_settings_caption")
	accepted_categories_caption.text = tr("building_settings_accepted_categories_caption")
	empty_all_button.text = tr("building_settings_empty_all_button")
	# BUGFIX (2026-09-11, richiesta utente) — il bottone esisteva già (testo/visibilità gestiti da
	# _refresh_settings_section) ma non era MAI stato collegato a nulla: un puro decoro che non
	# faceva niente alla pressione. `_current_building` letto FRESCO dentro la lambda (non bindato
	# ora, che sarebbe sempre null: questo _ready() gira una volta sola all'avvio della scena, ben
	# prima che qualunque edificio venga selezionato) — stesso principio di VegetationInfoPanel.
	# cut_requested, un solo collegamento in _ready() che resta valido per tutta la vita del
	# pannello, indipendentemente da quale edificio sia mostrato in un dato momento.
	empty_all_button.pressed.connect(func(): empty_all_requested.emit(_current_building))


# residents_display_data (2026-09-12, richiesta utente — griglia residenti): Array di Dictionary
# {"id","name","age","sex","is_child"}, GIÀ RISOLTI dal chiamante (GameScene._resolve_building_
# residents_display_data) — questo pannello resta "muto" su human_individuals/game_data/
# HumanCalculator, stesso principio dichiarato in testa al file. Default [] così ogni chiamante che
# non lo passa ancora (nessuno oggi, ma comportamento difensivo) mostra semplicemente una griglia
# residenti vuota invece di un errore.
func show_building(building: Building, residents_display_data: Array[Dictionary] = []) -> void:
	visible = true
	_current_building = building
	status_label.text = tr("building_status_label").format({
		"status": tr("building_status_complete") if building.is_complete else tr("building_status_under_construction")
	})
	_refresh_construction_progress(building)
	# "In attesa di materiale" (2026-09-14, richiesta utente — segnalazione player per un cantiere
	# bloccato per mancanza di materiale) — SOLO visibile/valorizzata mentre building.is_awaiting_
	# material resta true (Building.gd/HumanIndividualActionService._resolve_material_shortage
	# gestiscono la transizione, questo pannello resta "muto": legge, non decide). Sparisce da sé al
	# prossimo show_building() successivo alla risoluzione (bonus/deposito manuale sufficiente),
	# stesso principio "ricostruito per intero ad ogni chiamata" già dichiarato per l'intero
	# pannello. TESTO ARRICCHITO (2026-09-14, richiesta utente — "specifica solo quale [materiale] e
	# per quale fase", STESSO trigger di prima, is_awaiting_material invariato: solo il contenuto
	# del messaggio cambia) — quantità/materiale/nome-fase risolti da _resolve_setup_site_material_
	# shortage sotto, STESSA formula/STESSA fonte (BuildingRules.setup_site_material_name/
	# setup_site_material_per_cell) già usata da SetupSiteAction.get_missing_material_quantity/
	# BuildingStorageService — "fase" oggi è sempre "allestimento del cantiere" (SetupSite, l'unica
	# fase con un vero fabbisogno materiale, vedi BuildingRules.required_materials per quella
	# futura/non ancora attiva), esplicitato comunque nel testo per non dare per scontato che sia
	# ovvio al player, e per restare corretto il giorno in cui una seconda fase (costruzione vera e
	# propria) avrà il proprio fabbisogno.
	awaiting_material_label.visible = building.is_awaiting_material
	if building.is_awaiting_material:
		var shortage := _resolve_setup_site_material_shortage(building)
		awaiting_material_label.text = tr("building_awaiting_material_label").format({
			"quantity": shortage["quantity"],
			"material": shortage["material_display_name"],
		})

	var max_durability: int = building.rules.max_durability if building.rules != null else 0
	durability_label.text = tr("building_durability_label").format({"current": building.current_durability, "max": max_durability})

	built_year_label.text = (
		tr("building_built_year_label").format({"year": building.built_year}) if building.built_year >= 0
		else tr("building_not_yet_built")
	)

	_refresh_residents_grid(building, residents_display_data)
	_refresh_storage_grid(building)
	_refresh_settings_section(building)

	id_label.text = tr("building_id_label").format({"id": building.id})


func clear() -> void:
	visible = false
	_current_building = null


# Barra di avanzamento della fase di lavorazione CORRENTE (2026-09-14, richiesta utente — "75% di
# setup site, o 33% di build, o 19% di clear site") — nascosta del tutto per un edificio già
# completo (building.is_complete), stesso principio "nessun elemento fuorviante" già seguito da
# StorageGrid/ResidentsGrid per una capacità assente. Identifica la fase ATTIVA leggendo tre flag
# già esistenti su Building (nessun nuovo "stato di fase" introdotto, solo la ricomposizione di dati
# già lì), nello stesso ordine sequenziale delle tre fasi vere: site_setup_complete (SetupSiteAction,
# vedi Building.gd) -> construction_progress["space_reserved"] (settato UNA SOLA VOLTA da
# ClearAction.on_complete, riusato qui come "Clear è concluso" — STESSA chiave già usata per
# l'idempotenza della riserva di spazio, non una nuova) -> building.is_complete (BuildAction.
# on_complete). Le prime due fasi non ancora raggiunte restano implicitamente "non attive" per
# costruzione (l'ordine dei tre `if` sotto le prova in sequenza, la prima non ancora conclusa vince).
#
# Durata di ciascuna fase: SetupSite ha una soglia FISSA (SetupSiteAction.DURATION_DAYS, uguale per
# ogni edificio) — letta come costante di classe, nessuna istanza necessaria. Clear ha una soglia
# CALCOLATA per-edificio (dipende dalla vegetazione della microcella al momento della costruzione,
# vedi ClearAction._compute_duration) — PRIMA viveva solo dentro l'istanza ClearAction, irraggiungibile
# da questo pannello "muto"; ora persistita da ClearAction._init su Building.construction_progress
# ["clear_duration_days"] la prima volta che una Build Task viene costruita per questo edificio
# (vedi quel file), quindi già disponibile qui appena il cantiere esiste. Build usa building.rules.
# required_labor (dato di tipo, sempre disponibile). duration_days<=0.0 (fase senza alcun lavoro da
# fare, es. microcella già priva di vegetazione per Clear) mostra 100% invece di dividere per zero.
func _refresh_construction_progress(building: Building) -> void:
	if building.is_complete:
		construction_phase_label.visible = false
		construction_progress_bar.visible = false
		return

	var phase_name_key: String
	var progress_days: float
	var duration_days: float
	if not building.site_setup_complete:
		phase_name_key = "building_construction_phase_setup_site"
		progress_days = float(building.construction_progress.get("site_setup_days_done", 0.0))
		duration_days = SetupSiteAction.DURATION_DAYS
	elif not bool(building.construction_progress.get("space_reserved", false)):
		phase_name_key = "building_construction_phase_clear_site"
		progress_days = float(building.construction_progress.get("clear_days_done", 0.0))
		duration_days = float(building.construction_progress.get("clear_duration_days", 0.0))
	else:
		phase_name_key = "building_construction_phase_build"
		progress_days = float(building.construction_progress.get("labor_accumulated", 0.0))
		duration_days = float(building.rules.required_labor) if building.rules != null else 0.0

	var percent: float = (clampf(progress_days / duration_days, 0.0, 1.0) * 100.0) if duration_days > 0.0 else 100.0
	construction_phase_label.visible = true
	construction_progress_bar.visible = true
	construction_phase_label.text = tr("building_construction_phase_label").format({
		"phase": tr(phase_name_key),
		"percent": int(round(percent)),
	})
	construction_progress_bar.value = percent


# Fabbisogno materiale della fase SetupSite (2026-09-14, richiesta utente — testo arricchito
# dell'alert "in attesa di materiale" già esistente, vedi show_building sopra) — STESSA formula di
# SetupSiteAction.get_missing_material_quantity()/BuildingStorageService.can_accept (ramo cantiere),
# letta direttamente da BuildingRules.setup_site_material_name/setup_site_material_per_cell: questo
# pannello non ha un'istanza di SetupSiteAction a disposizione (solo il Building), nessuna
# duplicazione di STATO qui, solo della stessa formula pura già usata altrove (unica fonte di
# verità sul DATO, vedi il commento esteso su BuildingRules per il perché). Chiamata SOLO quando
# building.is_awaiting_material è già true (vedi show_building) — building.rules null resta
# comunque gestito difensivamente (0/"" innocuo, mai un crash), stesso principio già seguito
# ovunque in questo pannello per building.rules assente.
func _resolve_setup_site_material_shortage(building: Building) -> Dictionary:
	if building.rules == null:
		return {"quantity": 0, "material_display_name": ""}
	var material_name: String = building.rules.setup_site_material_name
	var required: int = building.rules.setup_site_material_per_cell * building.rules.required_space
	var stored_entry: Dictionary = building.stored_resources.get(material_name, {})
	var stored: int = int(stored_entry.get("quantity", 0))
	return {
		"quantity": max(required - stored, 0),
		"material_display_name": IconRegistry.get_resource_display_name(material_name),
	}


# Ricostruita per intero ad ogni show_building (stesso principio "rebuild da zero" già in uso
# ovunque nel progetto per contenuto derivato, es. MicroCellRenderer._rebuild_pebble_multimeshes) —
# nessuna logica di aggiornamento incrementale slot-per-slot, il costo è trascurabile (al più
# storage_slot_count nodi, oggi 4-9). Nascosta del tutto per un edificio senza storage
# (storage_slot_count <= 0, es. Pebble Circle) — nessuna griglia vuota fuorviante per un edificio
# che non può mai stoccare nulla.
func _refresh_storage_grid(building: Building) -> void:
	for child in storage_grid.get_children():
		child.queue_free()

	var slot_count: int = building.rules.storage_slot_count if building.rules != null else 0
	if slot_count <= 0:
		storage_caption.visible = false
		storage_grid.visible = false
		return

	storage_caption.visible = true
	storage_grid.visible = true
	# Colonne = ceil(sqrt(slot_count)) — 3x3 per 9 (deposit_site), 2x2 per 4 (hut), un default
	# ragionevole/generico per qualunque futuro slot_count senza doverlo configurare a mano per tipo.
	storage_grid.columns = max(int(ceil(sqrt(float(slot_count)))), 1)

	var breakdown: Array = BuildingStorageService.get_slot_breakdown(building)
	for i in range(slot_count):
		var slot_data: Dictionary = breakdown[i] if i < breakdown.size() else {}
		storage_grid.add_child(_build_storage_slot(slot_data))


# slot_data vuoto ({}) = slot libero — riquadro grigio spento, nessuna icona/testo/tooltip. Slot
# occupato ({"resource_name","quantity","space_used","space_capacity"}, vedi BuildingStorageService.
# get_slot_breakdown): stesso schema icona a 3 livelli (disegnata/emoji/iniziale) già in uso per
# HumanIndividualInfoPanel._update_carried_resource_box, qui riletto da IconRegistry invece di
# duplicato — colore di sfondo/nome tooltip risolti dalla STESSA fonte (IconRegistry.
# get_resource_color/get_resource_display_name), quindi una risorsa ha sempre lo stesso colore/nome
# sia nello zaino individuo che qui.
#
# quantity/tooltip/serbatoietto (2026-09-10, richiesta utente — "se deposito 4 bastoni, mi dice
# 40/100... avrebbe più senso indicare il numero degli oggetti"): la scritta grande sull'icona ora
# mostra `quantity` (numero di oggetti, non più lo spazio occupato); il tooltip resta il solo nome
# risorsa (un tentativo intermedio ci aveva aggiunto anche spazio/capacità, tolto su richiesta
# esplicita — quell'informazione si legge dalla barra sotto); una striscia verticale
# ("serbatoietto", STORAGE_SLOT_FILL_BAR_*) sul bordo destro dello slot mostra il livello di
# riempimento a colpo d'occhio senza dover leggere numeri — vedi sotto per l'ordine esatto in cui
# questi elementi vengono aggiunti a `box` (il numero è ristretto di STORAGE_SLOT_FILL_BAR_WIDTH sul
# lato destro apposta per non finire coperto dalla barra, disegnata per ultima/sopra).
func _build_storage_slot(slot_data: Dictionary) -> Control:
	var box := ColorRect.new()
	box.custom_minimum_size = Vector2(STORAGE_SLOT_SIZE, STORAGE_SLOT_SIZE)

	if slot_data.is_empty():
		box.color = EMPTY_STORAGE_SLOT_COLOR
		return box

	var resource_name: String = String(slot_data["resource_name"])
	var space_used: int = int(slot_data["space_used"])
	var space_capacity: int = int(slot_data["space_capacity"])
	box.color = IconRegistry.get_resource_color(resource_name)
	# Tooltip TORNATO al solo nome risorsa (2026-09-10, richiesta utente — "tooltip togli 80/100,
	# lascia solo il nome della risorsa": lo spazio occupato/capacità restano leggibili dalla barra
	# di riempimento sotto, non serve più ripeterli anche qui).
	box.tooltip_text = IconRegistry.get_resource_display_name(resource_name)

	var icon_node: Control = IconRegistry.get_resource_icon_node(resource_name)
	if icon_node != null:
		box.add_child(icon_node)
		# PRESET_FULL_RECT via ancore+offset DIRETTI (stesso bugfix già documentato in
		# IconButtonRow.configure_slot/HumanIndividualInfoPanel._update_carried_resource_box per
		# queste stesse icone: il preset di default userebbe la minimum size del figlio, zero per
		# un Control senza testo/figli come queste icone).
		icon_node.anchor_left = 0.0
		icon_node.anchor_top = 0.0
		icon_node.anchor_right = 1.0
		icon_node.anchor_bottom = 1.0
		icon_node.offset_left = 0.0
		icon_node.offset_top = 0.0
		icon_node.offset_right = 0.0
		icon_node.offset_bottom = 0.0
	else:
		var initial_label := Label.new()
		var icon_text: String = IconRegistry.get_resource_icon(resource_name)
		initial_label.text = icon_text if icon_text != "" else resource_name.substr(0, 1).to_upper()
		initial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial_label.anchor_right = 1.0
		initial_label.anchor_bottom = 1.0
		box.add_child(initial_label)

	# Quantità di OGGETTI in questo slot (2026-09-10, richiesta utente — "avrebbe più senso indicare
	# il numero degli oggetti": prima qui c'era lo spazio occupato "80/100", che si leggeva come "80
	# bastoni" anche quando erano solo 4 — RIMPIAZZATO, non affiancato: lo spazio ora si legge dalla
	# barra di riempimento sotto) — basso a destra, stesso trattamento ombra/colore di
	# CarriedResourceBox/QuantityLabel in HumanIndividualInfoPanel.tscn per coerenza visiva tra i due
	# riquadri risorsa del progetto.
	#
	# offset_right = -STORAGE_SLOT_FILL_BAR_WIDTH (BUGFIX 2026-09-10, richiesta utente — "non hai
	# messo il numero di oggetti sopra l'icona": era presente ma INVISIBILE, la barra di riempimento
	# sotto viene disegnata DOPO — quindi SOPRA nell'ordine di disegno — e occupa esattamente lo
	# stesso angolo in basso a destra dove il numero era ancorato, coprendolo. Restringere il rect
	# del label di STORAGE_SLOT_FILL_BAR_WIDTH sul lato destro libera esattamente lo spazio dov'è la
	# barra, così i due elementi convivono senza sovrapporsi.
	var quantity_label := Label.new()
	quantity_label.text = str(int(slot_data["quantity"]))
	quantity_label.add_theme_font_size_override("font_size", 8)
	quantity_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	quantity_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	quantity_label.add_theme_constant_override("shadow_offset_x", 1)
	quantity_label.add_theme_constant_override("shadow_offset_y", 1)
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	quantity_label.anchor_right = 1.0
	quantity_label.anchor_bottom = 1.0
	quantity_label.offset_right = -STORAGE_SLOT_FILL_BAR_WIDTH
	box.add_child(quantity_label)

	# "Serbatoietto" di riempimento (2026-09-10, richiesta utente, opzione scelta esplicitamente tra
	# le due proposte) — vedi le costanti STORAGE_SLOT_FILL_BAR_* in testa al file per il principio.
	# Aggiunto PER ULTIMO (sopra icona/quantity_label nell'ordine di disegno) così resta sempre
	# visibile sul bordo destro invece di finire coperto.
	var fill_bar_track := ColorRect.new()
	fill_bar_track.color = STORAGE_SLOT_FILL_BAR_TRACK_COLOR
	fill_bar_track.size = Vector2(STORAGE_SLOT_FILL_BAR_WIDTH, STORAGE_SLOT_SIZE)
	fill_bar_track.position = Vector2(STORAGE_SLOT_SIZE - STORAGE_SLOT_FILL_BAR_WIDTH, 0.0)
	fill_bar_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(fill_bar_track)

	var fill_ratio: float = clampf(float(space_used) / float(space_capacity), 0.0, 1.0) if space_capacity > 0 else 0.0
	var fill_height: float = STORAGE_SLOT_SIZE * fill_ratio
	var fill_bar_fill := ColorRect.new()
	fill_bar_fill.color = STORAGE_SLOT_FILL_BAR_FILL_COLOR
	fill_bar_fill.size = Vector2(STORAGE_SLOT_FILL_BAR_WIDTH, fill_height)
	fill_bar_fill.position = Vector2(STORAGE_SLOT_SIZE - STORAGE_SLOT_FILL_BAR_WIDTH, STORAGE_SLOT_SIZE - fill_height)
	fill_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(fill_bar_fill)

	return box


# Griglia residenti (2026-09-12, richiesta utente — "quadrati simili a quelli dello storage per
# rappresentare individui residenti") — STESSO principio/STESSA struttura di _refresh_storage_grid
# sopra: un riquadro per SLOT (building.rules.max_residents, non per residente effettivo — uno
# slot senza residente resta vuoto/grigio, stesso trattamento di uno slot storage libero), colonne
# = ceil(sqrt(max_residents)). Nascosta del tutto per un edificio non residenziale
# (max_residents<=0, es. Pebble Circle/Deposit Site) — stesso principio "nessuna griglia vuota
# fuorviante" già seguito da StorageGrid. Piazzata SOPRA StorageGrid nell'ordine dei nodi (vedi
# BuildingInfoPanel.tscn) — richiesta esplicita utente: "se residential, sopra quello dei
# residenti" — un edificio come Hut, che ha ENTRAMBE le griglie (storage_slot_count E
# max_residents valorizzati), le mostra impilate con un caption ciascuna per restare leggibili.
func _refresh_residents_grid(building: Building, residents_display_data: Array[Dictionary]) -> void:
	for child in residents_grid.get_children():
		child.queue_free()

	var max_residents: int = building.rules.max_residents if building.rules != null else 0
	if max_residents <= 0:
		residents_caption.visible = false
		residents_grid.visible = false
		return

	residents_caption.visible = true
	residents_grid.visible = true
	residents_grid.columns = max(int(ceil(sqrt(float(max_residents)))), 1)

	for i in range(max_residents):
		var resident_data: Dictionary = residents_display_data[i] if i < residents_display_data.size() else {}
		residents_grid.add_child(_build_resident_slot(resident_data))


# resident_data vuoto ({}) = slot libero — riquadro grigio spento, nessuna icona/tooltip, stesso
# trattamento di uno slot storage libero. Slot occupato ({"id","name","age","sex","is_child"}, vedi
# GameScene._resolve_building_residents_display_data): sfondo neutro/caldo (OCCUPIED_RESIDENT_
# SLOT_COLOR, nessuna distinzione di colore per tipo — a differenza degli slot storage, qui la
# distinzione visiva è tutta nell'icona), icona uomo/donna/bimbo/bimba (vedi _resident_icon sotto)
# ed hover-tooltip "{nome} ({età})" (richiesta esplicita utente: "facendo hover sull'icona
# pipottino tooltip con nome ed età").
func _build_resident_slot(resident_data: Dictionary) -> Control:
	var box := ColorRect.new()
	box.custom_minimum_size = Vector2(RESIDENT_SLOT_SIZE, RESIDENT_SLOT_SIZE)

	if resident_data.is_empty():
		box.color = EMPTY_RESIDENT_SLOT_COLOR
		return box

	box.color = OCCUPIED_RESIDENT_SLOT_COLOR
	box.tooltip_text = tr("building_resident_tooltip").format({
		"name": String(resident_data.get("name", "")),
		"age": int(resident_data.get("age", 0)),
	})

	# Click -> resident_center_requested (2026-09-12, richiesta utente) — gui_input invece di un
	# vero Button (che avrebbe portato con sé lo stile/padding di default del tema, da annullare
	# apposta per un semplice quadrato colorato): stesso principio "Control puro + gui_input" già
	# accettato altrove nel progetto per un'area cliccabile senza i decori di un Button. Cursore a
	# manina (CURSOR_POINTING_HAND) per segnalare che è cliccabile, dato che visivamente è identico
	# a un riquadro storage (mai cliccabile) se non per questo indizio.
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# STOP esplicito (non l'eventuale default ereditato) — gui_input sotto non scatterebbe con
	# MOUSE_FILTER_IGNORE, servirebbe a nulla collegarlo senza questa riga.
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var individual_id: int = int(resident_data.get("id", -1))
	box.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			resident_center_requested.emit(individual_id)
	)

	var icon_label := Label.new()
	icon_label.text = _resident_icon(int(resident_data.get("sex", HumanTypes.Sex.MALE)), bool(resident_data.get("is_child", false)))
	icon_label.add_theme_font_size_override("font_size", 20)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_label.anchor_right = 1.0
	icon_label.anchor_bottom = 1.0
	box.add_child(icon_label)

	return box


# Emoji uomo/donna/bimbo/bimba (2026-09-12, richiesta utente: "proponi icona per donna/uomo,
# bimbo/bimba, usa donna/uomo per tutte le età superiori a child, bimbo/bimba per le età di
# child") — stesso principio "emoji quando già leggibile da sé" di IconRegistry.BUILDING_ICONS
# ["stick_tent"]="⛺": nessuna icona disegnata a mano necessaria qui, questi quattro emoji sono già
# ampiamente distinguibili. is_child = (age_band == HumanTypes.AgeBand.CHILD), risolto dal
# chiamante — TEENAGER/FERTILE_ADULT/MATURE_ADULT/OLD sono TUTTE "adulto" qui, nessuna ulteriore
# distinzione (richiesta esplicita).
func _resident_icon(sex: int, is_child: bool) -> String:
	if is_child:
		return "👧" if sex == HumanTypes.Sex.FEMALE else "👦"
	return "👩" if sex == HumanTypes.Sex.FEMALE else "👨"


# Punto di estensione GENERICO per contenuto condizionale-al-tipo (2026-09-09, richiesta utente —
# vedi commento in testa al file): oggi un solo blocco (storage -> toggle categoria), una futura
# capacità diversa aggiungerebbe il proprio `if`/blocco qui, ciascuno responsabile di mostrare/
# nascondere SOLO i propri nodi — mai un blocco che nasconde ciò che un altro ha appena mostrato.
# Nessun edificio con capacità da configurare oggi -> l'intera sezione (separatore+titolo compresi)
# resta nascosta, stesso principio già seguito da StorageGrid per storage_slot_count<=0.
func _refresh_settings_section(building: Building) -> void:
	var has_storage: bool = building.rules != null and building.rules.storage_slot_count > 0
	_refresh_accepted_categories_toggles(building, has_storage)

	# Almeno un blocco visibile -> mostra la "chrome" condivisa (separatore/titolo/bottone
	# placeholder). Oggi has_storage è l'unica condizione, ma scritta così non richiede modifiche
	# quando un secondo blocco esisterà (basterà aggiungerlo all'OR).
	var any_section_visible: bool = has_storage
	settings_separator.visible = any_section_visible
	settings_caption.visible = any_section_visible
	empty_all_button.visible = any_section_visible


# Toggle CheckBox per Building.enabled_categories (2026-09-09, richiesta utente) — SOLO per edifici
# con storage (has_storage, dal chiamante): un edificio senza storage non ha categorie da filtrare.
# Categorie mostrate: building.rules.accepted_categories se il TIPO ne ha (vuoto = nessuna
# restrizione di tipo, in quel caso mostra TUTTE le categorie esistenti — SecondaryResourceTypes.
# Category.values()) — richiesta esplicita: l'istanza può scegliere solo tra ciò che il tipo già
# accetta, mai categorie che il tipo rifiuterebbe comunque.
#
# Stato checkbox: checked = categoria attualmente abilitata per QUESTA istanza — building.
# enabled_categories VUOTO significa "nessuna restrizione propria, tutto ciò che il tipo accetta è
# abilitato" (vedi Building.gd), quindi ogni checkbox parte spuntata finché il player non ne
# deflagga almeno una esplicitamente (vedi _on_category_toggled sotto per come si materializza
# l'elenco esplicito al primo deflag).
func _refresh_accepted_categories_toggles(building: Building, has_storage: bool) -> void:
	for child in category_toggles_container.get_children():
		child.queue_free()

	accepted_categories_caption.visible = has_storage
	category_toggles_container.visible = has_storage
	if not has_storage:
		return

	var categories_to_show: Array = (
		building.rules.accepted_categories if not building.rules.accepted_categories.is_empty()
		else SecondaryResourceTypes.Category.values()
	)
	for category in categories_to_show:
		var check_box := CheckBox.new()
		check_box.text = _category_display_name(category)
		# Font ridotto (richiesta utente 2026-09-09) — stessa taglia di AcceptedCategoriesCaption/
		# DurabilityLabel/BuiltYearLabel/IdLabel sopra, più piccola del default tema per un elenco
		# di opzioni secondarie come questo.
		check_box.add_theme_font_size_override("font_size", 10)
		check_box.button_pressed = building.enabled_categories.is_empty() or building.enabled_categories.has(category)
		check_box.toggled.connect(_on_category_toggled.bind(category, building, categories_to_show))
		category_toggles_container.add_child(check_box)


# Chiave tr() "category_name_<nome_enum_minuscolo>" (es. FOOD -> "category_name_food") — deriva la
# chiave dal nome dell'enum invece di un match hardcoded: una futura categoria aggiunta a
# SecondaryResourceTypes.Category compare qui da sola (con la chiave grezza come fallback finché
# non le si aggiunge una riga in strings.csv, stesso idioma "tr() ritorna la chiave se non trovata"
# già in uso altrove nel progetto, es. IconRegistry.get_resource_display_name).
func _category_display_name(category: int) -> String:
	var key := "category_name_%s" % SecondaryResourceTypes.Category.keys()[category].to_lower()
	return tr(key)


# ENTRAMBI i rami scrivono direttamente su Building.enabled_categories, MAI su BuildingRules
# (quello resta il tipo, condiviso — vedi Building.gd/BuildingStorageService.can_accept per la
# spiegazione completa dei due livelli). Solo controllo IN ENTRATA (richiesta esplicita utente):
# questo toggle non tocca mai building.stored_resources, solo cosa store() accetterà d'ora in poi.
#
# `categories_to_show` (bind, dallo stesso elenco già risolto da _refresh_accepted_categories_
# toggles) — necessario per materializzare "tutto tranne questa" al primo deflag (pressed=false con
# enabled_categories ancora vuoto, cioè "implicitamente tutto abilitato": vedi Building.gd) E per
# la normalizzazione inversa sotto (se il player riabilita l'ultima categoria mancante, l'elenco
# esplicito torna a coincidere con categories_to_show — a quel punto si ricollassa a [] per
# restare nella forma canonica "nessuna restrizione propria", equivalente ma più pulita).
func _on_category_toggled(pressed: bool, category: int, building: Building, categories_to_show: Array) -> void:
	if pressed:
		if not building.enabled_categories.is_empty() and not building.enabled_categories.has(category):
			building.enabled_categories.append(category)
	else:
		if building.enabled_categories.is_empty():
			for shown_category in categories_to_show:
				if shown_category != category:
					building.enabled_categories.append(shown_category)
		else:
			building.enabled_categories.erase(category)

	# Normalizzazione (vedi commento sopra): elenco esplicito che ormai copre di nuovo TUTTO
	# categories_to_show -> ricollassa a [] (forma canonica "nessuna restrizione propria").
	if not building.enabled_categories.is_empty():
		var covers_everything := true
		for shown_category in categories_to_show:
			if not building.enabled_categories.has(shown_category):
				covers_everything = false
				break
		if covers_everything:
			building.enabled_categories.clear()

	if _current_building == building:
		_refresh_settings_section(building)
