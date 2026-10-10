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

# Ordine di produzione cambiato dalla griglia delle ricette (2026-09-27, richiesta utente — sostituisce i bottoni
# "Produci …" e il campo Quantità): clic sinistro su un'icona +1, destro −1. Stesso principio "muto" di
# empty_all_requested: GameScene, con quantity > 0, entra (o resta) nella modalità di scelta del lavoratore con la
# quantità aggiornata; con quantity 0 ne esce. Una ricetta alla volta: un ordine (Produce Task) ne contiene una sola.
# deliver_to_warehouse (2026-09-26): spunta "Consegna al magazzino" sotto la griglia (RetrieveAction.deliver_to_warehouse).
# keep_for_building (2026-10-04, Attrezzeria): spunta "Tieni per l'edificio", esclusiva con deliver_to_warehouse.
signal production_order_changed(building: Building, resource_name: String, quantity: int, deliver_to_warehouse: bool, keep_for_building: bool)
# Attrezzeria (2026-10-04, BuildingToolkitService): clic su un attrezzo del magazzino (from_output false) o dei prodotti
# finiti (true) per metterne un pezzo nell'Attrezzeria; clic su un attrezzo dell'Attrezzeria per rimetterlo nel magazzino.
signal toolkit_deposit_requested(building: Building, tool_name: String, from_output: bool)
signal toolkit_withdraw_requested(building: Building, tool_name: String)

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

# X rossa accanto a "Stato" (2026-09-26, richiesta utente — annullare il lavoro dall'edificio): stesso
# principio "muto" di empty_all_requested. GameScene chiude le Task di costruzione/produzione su questo
# edificio di chi ci lavora (in corso e in coda), lasciando intatto il lavoro accumulato sull'edificio.
# Visibile solo se qualcuno ci lavora: con il costruttore/lavoratore "mancante" non c'è nulla da annullare.
signal work_cancel_requested(building: Building)
# X su una riga "In produzione" (2026-10-04, ordini separati): annulla solo quell'ordine (chiave in
# Building.production_progress). GameScene._on_production_order_cancel_requested.
signal production_order_cancel_requested(building: Building, order_key: String)
# "Assegna" su una riga di un ordine senza lavoratore (2026-10-04): GameScene._on_production_order_assign_requested.
signal production_order_assign_requested(building: Building, order_key: String)

# Bottone "Demolisci" (2026-09-27, richiesta utente — prima era un bottone della BuildBar): stesso principio "muto" di
# empty_all_requested, GameScene apre la conferma (DemolishConfirmationDialog). Nascosto per un edificio già "da
# demolire".
signal demolish_requested(building: Building)
# Bottone "Migliora in …" (2026-10-03, richiesta utente — miglioramento): GameScene apre la scelta del lavoratore col
# mirino (_on_upgrade_requested) e, alla scelta, avvia il miglioramento.
signal upgrade_requested(building: Building)
# "Ripara" (2026-10-10, richiesta utente): GameScene apre il mirino per scegliere chi ripara (_on_repair_requested).
signal repair_requested(building: Building)
# "Sgombera" (2026-10-10, macerie): GameScene avvia lo sgombero (_on_clear_rubble_requested).
signal clear_rubble_requested(building: Building)

# Icone di influenza (2026-10-02, richiesta utente — sostituiscono il bottone "Mostra influenza"): una per tipo
# (politica, cultura, religione), nell'intestazione della scheda accanto al 🎯. Clic: GameScene mostra per qualche
# secondo il cerchio del solo tipo cliccato. `influence_type` = InfluenceService.InfluenceType.
signal influence_footprint_requested(building: Building, influence_type: int)
# Anteprima al passaggio del mouse (2026-10-02, richiesta utente): con il puntatore su un'icona ABILITATA il cerchio di
# quel tipo resta visibile fisso; influence_preview_ended lo toglie subito (puntatore uscito, icona disabilitata,
# pannello nascosto o edificio cambiato). Nessuna anteprima sulle icone disabilitate.
signal influence_preview_started(building: Building, influence_type: int)
signal influence_preview_ended

# Icone di influenza: ordine, voce di MapLayerRegistry da cui prendere l'emoji e chiavi dei tooltip per tipo.
const INFLUENCE_BUTTONS: Array[Dictionary] = [
	{"type": InfluenceService.InfluenceType.POLITICAL, "layer_id": "political_influence", "tooltip_key": "building_influence_political_tooltip", "none_key": "building_influence_political_none_tooltip"},
	{"type": InfluenceService.InfluenceType.CULTURAL, "layer_id": "cultural_influence", "tooltip_key": "building_influence_cultural_tooltip", "none_key": "building_influence_cultural_none_tooltip"},
	{"type": InfluenceService.InfluenceType.RELIGIOUS, "layer_id": "religious_influence", "tooltip_key": "building_influence_religious_tooltip", "none_key": "building_influence_religious_none_tooltip"},
]
const INFLUENCE_BUTTON_SIZE := Vector2(22, 22)
const INFLUENCE_BUTTON_DISABLED_COLOR := Color(0.5, 0.5, 0.5)
# Riga comandi (2026-10-03): icone disegnate (BuildingCommandIcon) dentro pulsanti del tema di base, grandi quanto il
# 🎯 "centra" (misurato da un pulsante di prova con lo stesso testo). Margine dell'icona dal bordo del pulsante, e
# opacità dell'icona a comando spento (lo sfondo spento è già quello del tema).
const COMMAND_ICON_SIZE_PROBE_TEXT := "🎯"
const COMMAND_ICON_INSET: float = 4.0
const COMMAND_ICON_DISABLED_MODULATE := Color(1, 1, 1, 0.35)


# Bottone "Annulla demolizione" (2026-09-27, richiesta utente): visibile per un edificio "da demolire" finché il
# lavoro di demolizione non è iniziato (DemolishAction.LABOR_KEY a 0); GameScene chiude le Demolish Task e toglie
# il flag.
signal demolition_cancel_requested(building: Building)

# Colore della scritta di stato "In demolizione" (2026-09-27): arancio, demolizione iniziata e non più annullabile.
const DEMOLITION_IN_PROGRESS_STATUS_COLOR := Color(1.0, 0.55, 0.15, 1.0)

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
# Slot oltre la capienza di un edificio danneggiato (2026-10-10): tinta rossastra.
const STORAGE_SLOT_OVER_CAPACITY_MODULATE := Color(1.0, 0.5, 0.5, 0.75)

@onready var status_label: Label = $StatusRow/StatusLabel
# X accanto a "Stato" (2026-09-26, richiesta utente): annulla il lavoro in corso sull'edificio
# (costruzione o produzione) di TUTTI gli individui che ci lavorano — vedi work_cancel_requested.
@onready var cancel_work_button: Button = $StatusRow/CancelWorkButton
@onready var construction_phase_label: Label = $ConstructionPhaseLabel
@onready var construction_progress_bar_margin: MarginContainer = $ConstructionProgressBarMargin
@onready var construction_progress_bar: ProgressBar = $ConstructionProgressBarMargin/ConstructionProgressBar
@onready var awaiting_material_label: Label = $AwaitingMaterialLabel
# Costruttore assegnato di un cantiere (dal 2026-09-27 solo cantiere: il lavoratore di una workstation ha la propria
# riga, AssignedWorkerLabel, nella sezione Produzione).
@onready var assigned_builder_label: Label = $AssignedBuilderLabel
# Avvisi "attrezzi mancanti" dei lavoratori della workstation (2026-09-25, richiesta utente): riga a
# parte, arancione, sotto "Lavoratore assegnato" — testi già risolti da GameScene
# (_resolve_production_tool_wait_lines), nascosta se non ce ne sono.
@onready var tool_wait_label: Label = $ToolWaitLabel
# Terza riga dell'intestazione (2026-09-27, richiesta utente): "Costruito anno X" (prima due righe; l'Integrità dal
# 2026-10-10 ha la propria riga con barra, vedi _durability_label).
@onready var built_year_label: Label = $BuiltYearLabel
# "Influenza ricevuta: …" (2026-10-02, richiesta utente): solo per un edificio RESIDENTIAL completo, tipi di influenza
# che coprono la casa (InfluenceService.get_house_coverage) o "nessuna".
@onready var influence_received_label: Label = $InfluenceReceivedLabel
@onready var residents_caption: Label = $ResidentsCaption
# Residenti in fila (2026-10-10, richiesta utente — prima una griglia quadrata, es. 2×2): da sinistra a destra, a capo
# da sola quando non ci stanno più in larghezza. Nome del nodo invariato.
@onready var residents_grid: HFlowContainer = $ResidentsGrid
@onready var storage_caption: Label = $StorageCaption
@onready var storage_grid: GridContainer = $StorageGrid
# Buffer di uscita della produzione (2026-09-23, richiesta utente) — caption con pezzi usati/capienza,
# griglia di chip col contenuto, avviso giallo quando il buffer pieno blocca la produzione. Nascosti
# per un edificio senza buffer (BuildingRules.production_output_slots <= 0).
# Voci in avanzamento automatico (2026-10-03, essiccatoio): una riga per risorsa, al posto delle sezioni della produzione
# con lavoratore — vedi _refresh_auto_progress.
@onready var auto_progress_label: Label = $AutoProgressLabel
@onready var output_buffer_caption: Label = $OutputBufferCaption
@onready var output_buffer_grid: HFlowContainer = $OutputBufferGrid
@onready var output_buffer_full_label: Label = $OutputBufferFullLabel
# Materiali consegnati (2026-09-24, richiesta utente) — contenuto di stored_resources per una
# workstation SENZA storage (storage_slot_count <= 0), dove StorageGrid resta nascosta: senza questa
# sezione il materiale consegnato per le ricette non compariva da nessuna parte. Distinta dal buffer
# di uscita (prodotti) sopra. Vedi _refresh_delivered_materials.
@onready var delivered_materials_caption: Label = $DeliveredMaterialsCaption
@onready var delivered_materials_grid: HFlowContainer = $DeliveredMaterialsGrid
# Produzioni sospese (2026-09-24, richiesta utente) — record presenti su production_progress senza
# nessuna Produce Task che ci lavori: "Produzione sospesa: X, N% completata", una riga per ricetta.
@onready var suspended_production_label: Label = $SuspendedProductionLabel
# Sezione Produzione (2026-09-27, richiesta utente — riorganizzazione del pannello delle workstation): separatore,
# titolo, griglia delle ricette (4 per riga) con la spunta "Consegna al magazzino", poi lo stato della produzione in
# corso ("In produzione:" con icone, quantità e X di annullo; lavoratore assegnato; cosa serve ancora, combustibile
# compreso). Tutto nascosto per un edificio che non è una workstation completa.
@onready var production_separator: HSeparator = $ProductionSeparator
@onready var production_recipes_caption: Label = $ProductionRecipesCaption
@onready var production_recipes_container: VBoxContainer = $ProductionRecipesContainer
@onready var production_status_row: HBoxContainer = $ProductionStatusRow
@onready var production_status_caption: Label = $ProductionStatusRow/ProductionStatusCaption
@onready var production_status_items: HFlowContainer = $ProductionStatusRow/ProductionStatusItems
@onready var production_cancel_button: Button = $ProductionStatusRow/ProductionCancelButton
@onready var assigned_worker_label: Label = $AssignedWorkerLabel
@onready var production_needs_caption: Label = $ProductionNeedsCaption
@onready var production_needs_grid: HFlowContainer = $ProductionNeedsGrid
# Mucchio a terra nella microcella dell'edificio (2026-09-26, ground drop — tipicamente un sentiero o un altro
# edificio MOVEMENT, dove un mucchio può stare): vedi show_ground_pile.
@onready var ground_pile_caption: Label = $GroundPileCaption
@onready var ground_pile_container: VBoxContainer = $GroundPileContainer
@onready var settings_separator: HSeparator = $SettingsSeparator
@onready var settings_caption: Label = $SettingsCaption
@onready var accepted_categories_caption: Label = $AcceptedCategoriesCaption
@onready var category_toggles_container: VBoxContainer = $CategoryTogglesContainer
# Riga dei comandi a icone (2026-10-03, richiesta utente — sostituisce i bottoni larghi a testo; dal 2026-10-10 in alto,
# fuori dallo scroll, vedi _mount_command_bar):
# tutte a sinistra: Migliora, Svuota tutto, un piccolo spazio fisso, Demolisci per ultimo. "Annulla cantiere" (stesso
# DemolishButton su un cantiere) e "Annulla demolizione" prendono il posto di Demolisci. Pulsanti come il 🎯 con
# un'icona disegnata (_setup_command_icon_buttons); il nome del comando è la prima riga del tooltip. Visibili solo quando hanno senso; esistenti ma non disponibili = spenti con il motivo.
@onready var command_icon_row: HBoxContainer = $CommandIconRow
@onready var upgrade_button: TooltipButton = $CommandIconRow/UpgradeButton
@onready var empty_all_button: Button = $CommandIconRow/EmptyAllButton
@onready var demolish_button: Button = $CommandIconRow/DemolishButton
@onready var cancel_demolition_button: Button = $CommandIconRow/CancelDemolitionButton
# Pulsante -> la sua BuildingCommandIcon.
var _command_icons: Dictionary = {}
# Spaziatore elastico della riga comandi (2026-10-10): separa i comandi a sinistra da Demolisci a destra.
var _command_icon_spacer: Control = null
# "Ripara" (2026-10-10, richiesta utente): creato in codice subito dopo Migliora (_build_repair_controls), stesso stile
# delle altre icone. Riga di stato "Riparazione in corso: Nome (#id)" sotto lo stato, mentre qualcuno ha la Task.
var repair_button: TooltipButton = null
# "Sgombera" (2026-10-10, richiesta utente — macerie): l'unico comando del pannello delle macerie, a sinistra, creato in
# codice come Ripara (_build_repair_controls). Su ogni altro edificio resta nascosto.
var clear_rubble_button: Button = null
var _repair_status_label: Label = null
# Riparazione ferma per materiale (2026-10-10, passo 4): riga arancione subito sotto _repair_status_label.
var _repair_wait_label: Label = null
# Effetti dello stato "Danneggiato" (2026-10-10): riga breve sotto lo stato.
var _damaged_effects_label: Label = null
# "Nome (#id)" di chi ha la Repair Task su questo edificio (in corso o in coda), da show_building.
var _repairer_names: Array[String] = []

# Edificio correntemente mostrato (2026-09-09) — MAI esistito prima come campo: show_building
# riceveva `building` solo come parametro locale, nessun consumatore ne aveva bisogno dopo il
# ritorno della funzione. I toggle categoria sotto sono l'eccezione: un CheckBox premuto dal
# player deve sapere SU QUALE Building scrivere enabled_categories, in un momento (il callback
# `toggled`) in cui `building` del parametro originale non è più in scope — stesso motivo per cui
# un riferimento va tenuto qui, non ricavato altrove (questo pannello non conosce GameScene/
# selezione, resta "muto" come dichiarato in testa al file).
var _current_building: Building = null

# Ordine in preparazione nella griglia delle ricette (2026-09-27, richiesta utente): una ricetta alla volta
# (_order_recipe, "" = nessuna) e la sua quantità (0 = nessun ordine). Tenuto qui perché la griglia si ricostruisce
# a ogni show_building, anche al refresh giornaliero. Torna a 0 cambiando edificio, dopo l'assegnazione o uscendo
# dalla scelta del lavoratore (reset_production_order).
var _order_recipe: String = ""
var _order_quantity: int = 0
var _order_quantity_building_id: int = -1
# Nomi di chi produce qui, dall'ultimo show_building: servono a ricostruire la griglia dopo un clic.
var _last_production_claimant_names: Array[String] = []
# Spunta "Consegna al magazzino" (2026-09-26): riparte dal default di UserOptions a ogni cambio di edificio, come
# la quantità; il cambio vale per gli ordini di questo pannello (stesso schema di "Ripeti" nei dialog).
var _order_deliver: bool = true
var _order_keep_for_building: bool = false
# Ordini in coda (2026-10-09, richiesta utente — con l'idea dell'assegnazione, set_production_queue_mode): la griglia
# non prepara più un ordine per il mirino, ma mostra l'ordine appena messo in coda da questo pannello (GameScene ne tiene
# la chiave) e le ricette restano accese anche a edificio al completo (gli ordini in più aspettano in coda).
var _production_queue_mode: bool = false
# Suggerimento "come assegnarlo" (2026-10-09, richiesta utente): sotto "Costruttore assegnato: mancante" di un cantiere
# (anche di miglioramento) e, per un edificio da demolire senza demolitore, sopra la riga dei comandi a icone (dove
# c'era il bottone "Assegna demolitore", tolto lo stesso giorno: resta il clic destro con un individuo selezionato);
# arancione come gli altri avvisi, va a capo (il pannello resta largo 300 px). Il testo dipende dall'idea
# dell'assegnazione e dallo stato del lavoro in coda, passati da GameScene prima di ogni show_building
# (set_assign_hint_state). Sparisce appena c'è un lavoratore.
var _assign_hint_label: Label = null
var _assign_hint_queue_enabled: bool = false
var _assign_hint_locked: bool = false
# Riga "Uscita piena: si fermerà dopo N" sotto le spunte dell'ordine (2026-10-08, _update_order_output_warning).
var _order_output_warning_label: Label = null
# Stesso colore dell'avviso "Prodotti finiti pieni" (OutputBufferFullLabel nella scena).
const ORDER_OUTPUT_WARNING_COLOR := Color(0.95, 0.75, 0.1, 1.0)
# Sezione "Attrezzeria" nel corpo (2026-10-04): creata in codice, sotto i prodotti finiti. Visibile su ogni edificio
# completo con l'Attrezzeria (BuildingToolkitService.has_toolkit), nessun tipo di edificio nominato.
var _toolkit_box: VBoxContainer = null
var _toolkit_caption: Label = null
var _toolkit_grid: HFlowContainer = null


# Elenco dei sepolti di un cumulo (2026-10-04, cumulo sepolcrale passo 3b): nel corpo del pannello, subito sotto lo stato
# — intestazione "Sepolti: N/max", poi un nome per riga con l'anno di sepoltura (Building.buried). Creato in codice;
# righe su una sola riga tagliate con i puntini (testo intero nel tooltip): il pannello non si allarga mai.
const BURIED_FONT_SIZE: int = 10
const BURIED_ROW_INDENT: int = 8
var _buried_box: VBoxContainer = null

# Sacralità (2026-10-04, richiesta utente): punti di influenza religiosa nel corpo del pannello, sotto lo stato e sopra
# l'elenco dei sepolti, per gli edifici completi con raggio religioso — "Sacralità: 20 / 100" (punti e soglia
# successiva), una barra sottile dalla soglia precedente alla successiva, "Raggio: 5 (+0)" (base più bonus delle soglie).
# Oltre l'ultima soglia: solo il valore, senza barra. Il tooltip dell'icona dell'influenza religiosa resta com'è.
const SACREDNESS_BAR_HEIGHT: float = 4.0
var _sacredness_box: VBoxContainer = null
var _sacredness_label: Label = null
var _sacredness_bar: ProgressBar = null
var _sacredness_radius_label: Label = null

# Integrità (2026-10-10, richiesta utente): solo per un edificio completo, sotto "Costruito: anno N" — "Integrità: 90%"
# e una barra con lo stile e le dimensioni di quella della costruzione, colorata per soglie (Building.DURABILITY_*_RATIO).
# Tooltip con i punti interi "54/60". Creata in codice.
const DURABILITY_FILL_COLOR_GOOD := Color(0.3, 0.68, 0.3, 1)
const DURABILITY_FILL_COLOR_DAMAGED := Color(0.85, 0.72, 0.2, 1)
const DURABILITY_FILL_COLOR_CRITICAL := Color(0.82, 0.25, 0.2, 1)
var _durability_label: Label = null
var _durability_bar_margin: MarginContainer = null
var _durability_bar: ProgressBar = null
var _durability_fill_style: StyleBoxFlat = null


func _ready() -> void:
	_assign_hint_label = Label.new()
	_assign_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_assign_hint_label.custom_minimum_size.x = 0.0
	_assign_hint_label.add_theme_font_size_override("font_size", 10)
	_assign_hint_label.add_theme_color_override("font_color", ORDER_OUTPUT_WARNING_COLOR)
	_assign_hint_label.visible = false
	add_child(_assign_hint_label)
	# Righe degli ordini (2026-10-04, ordini separati) subito sotto "In produzione:".
	_production_orders_box = VBoxContainer.new()
	_production_orders_box.add_theme_constant_override("separation", 2)
	_production_orders_box.visible = false
	add_child(_production_orders_box)
	move_child(_production_orders_box, production_status_row.get_index() + 1)
	_build_toolkit_box()
	add_child(_toolkit_box)
	# Ordine delle sezioni (2026-10-04): Magazzino -> Attrezzeria -> Produzione -> Prodotti finiti -> Impostazioni. I
	# prodotti finiti (didascalia, icone, avviso "pieni") scendono sotto la produzione, prima dei mucchi a terra.
	move_child(_toolkit_box, auto_progress_label.get_index() + 1)
	# Ognuno subito prima della didascalia dei mucchi, nell'ordine didascalia -> icone -> avviso (BUGFIX 2026-10-05: lo
	# spostamento in avanti metteva ogni nodo DOPO quello spostato prima, invertendo l'ordine — le icone finivano sopra
	# la didascalia). move_child lascia il nodo esattamente all'indice dato: se il nodo sta prima della didascalia dei
	# mucchi, quell'indice va preso di uno più piccolo per finirle davanti.
	for output_node in [output_buffer_caption, output_buffer_grid, output_buffer_full_label]:
		var target_index := ground_pile_caption.get_index()
		if output_node.get_index() < target_index:
			target_index -= 1
		move_child(output_node, target_index)
	_build_sacredness_box()
	add_child(_sacredness_box)
	move_child(_sacredness_box, $StatusRow.get_index() + 1)
	_buried_box = VBoxContainer.new()
	_buried_box.add_theme_constant_override("separation", 0)
	add_child(_buried_box)
	move_child(_buried_box, _sacredness_box.get_index() + 1)
	_build_durability_rows()
	_build_repair_materials_rows()
	clear()
	residents_caption.text = tr("building_residents_caption")
	storage_caption.text = tr("building_storage_caption")
	settings_caption.text = tr("building_settings_caption")
	accepted_categories_caption.text = tr("building_settings_accepted_categories_caption")
	# BUGFIX (2026-09-11, richiesta utente) — il bottone esisteva già (testo/visibilità gestiti da
	# _refresh_settings_section) ma non era MAI stato collegato a nulla: un puro decoro che non
	# faceva niente alla pressione. `_current_building` letto FRESCO dentro la lambda (non bindato
	# ora, che sarebbe sempre null: questo _ready() gira una volta sola all'avvio della scena, ben
	# prima che qualunque edificio venga selezionato) — stesso principio di VegetationInfoPanel.
	# cut_requested, un solo collegamento in _ready() che resta valido per tutta la vita del
	# pannello, indipendentemente da quale edificio sia mostrato in un dato momento.
	empty_all_button.pressed.connect(func(): empty_all_requested.emit(_current_building))
	cancel_work_button.tooltip_text = tr("building_cancel_work_tooltip")
	cancel_work_button.pressed.connect(func(): work_cancel_requested.emit(_current_building))
	# X della produzione in corso (2026-09-27): stessa azione di annullamento della X accanto allo stato.
	production_cancel_button.tooltip_text = tr("building_cancel_work_tooltip")
	production_cancel_button.pressed.connect(func(): work_cancel_requested.emit(_current_building))
	production_separator.visible = false
	_build_influence_buttons()
	# Il gruppo vive fuori dal pannello (intestazione della scheda): si nasconde con lui, e l'anteprima finisce.
	visibility_changed.connect(_on_visibility_changed_for_influence)
	_build_info_button()
	demolish_button.pressed.connect(func(): demolish_requested.emit(_current_building))
	upgrade_button.pressed.connect(func(): upgrade_requested.emit(_current_building))
	cancel_demolition_button.pressed.connect(func(): demolition_cancel_requested.emit(_current_building))
	_build_repair_controls()
	_setup_command_icon_buttons()
	visibility_changed.connect(_update_command_bar_visibility)
	# Dopo l'ingresso in scena: il genitore dello scroll può essere ancora occupato a sistemare i propri figli.
	_mount_command_bar.call_deferred()


# residents_display_data (2026-09-12, richiesta utente — griglia residenti): Array di Dictionary
# {"id","name","age","sex","is_child"}, GIÀ RISOLTI dal chiamante (GameScene._resolve_building_
# residents_display_data) — questo pannello resta "muto" su human_individuals/game_data/
# HumanCalculator, stesso principio dichiarato in testa al file. Default [] così ogni chiamante che
# non lo passa ancora (nessuno oggi, ma comportamento difensivo) mostra semplicemente una griglia
# residenti vuota invece di un errore.
# production_claimant_names (2026-09-24, richiesta utente — blocco ricette): "Nome (#id)" di chi ha
# una Produce Task su questo edificio (attiva o in coda, anche se non ancora arrivato), risolti da
# GameScene._resolve_production_claimant_names. Non vuoto = edificio già impegnato: ricette spente.
#
# production_orders (2026-10-04, ordini separati — prima production_claimed_recipes): una voce per ordine
# dell'edificio, {"key", "recipe", "units", "percent", "worker_name" ("" = nessuno)}, da
# GameScene._resolve_production_orders. production_claimant_names ha un nome per ogni ordine con un lavoratore.
# Storico, production_claimed_recipes (2026-09-24, richiesta utente — produzioni sospese): ricette con almeno
# una Produce Task che ci lavora (GameScene._resolve_production_claimed_recipes). Un record di
# production_progress la cui ricetta non è qui è SOSPESO: il pannello lo segnala come tale e non ne
# mostra il fabbisogno di materiale/combustibile come se qualcuno ci stesse lavorando.
# demolisher_names (2026-09-27): "Nome (#id)" di chi ha la Demolish Task su questo edificio (in corso o in coda) —
# vuoto su un edificio "da demolire" = suggerimento "come assegnarla" (dal 2026-10-09, prima il bottone "Assegna
# demolitore").
# repairer_names (2026-10-10): stesso formato per la Repair Task — riga "Riparazione in corso" e "Ripara" spento.
func show_building(building: Building, residents_display_data: Array[Dictionary] = [], assigned_builder_names: Array[String] = [], production_claimant_names: Array[String] = [], production_orders: Array[Dictionary] = [], production_tool_wait_lines: Array[String] = [], demolisher_names: Array[String] = [], repairer_names: Array[String] = []) -> void:
	visible = true
	_current_building = building
	_repairer_names = repairer_names
	# Ordini separati (2026-10-04): ricette degli ordini con un lavoratore (fabbisogno "Materiali per la produzione") e
	# produzioni sospese dagli ordini annullati (Building.production_suspended).
	var working_recipes: Array[String] = []
	for order in production_orders:
		if String(order["worker_name"]) != "" and not working_recipes.has(String(order["recipe"])):
			working_recipes.append(String(order["recipe"]))
	var suspended_recipes: Array[String] = []
	for suspended_name in building.production_suspended.keys():
		suspended_recipes.append(String(suspended_name))
	# "Da demolire" (2026-09-27, Building.is_marked_for_demolition) prima di completo/in costruzione.
	var status_key: String = "building_status_complete" if building.is_complete else "building_status_under_construction"
	# Danneggiato (2026-10-10, Building.is_damaged): al posto di "Completo".
	if building.is_damaged():
		status_key = "building_status_damaged"
	# Demolizione iniziata (2026-09-27, richiesta utente): "In demolizione" in arancio, non più annullabile.
	var demolition_started: bool = building.is_marked_for_demolition and float(building.construction_progress.get(DemolishAction.LABOR_KEY, 0.0)) > 0.0
	if building.is_marked_for_demolition:
		status_key = "building_status_demolition_in_progress" if demolition_started else "building_status_marked_for_demolition"
	# Macerie (2026-10-10): "Crollato", poi "Da sgomberare" / "Sgombero in corso" al posto delle voci della demolizione.
	if building.is_rubble():
		status_key = "building_status_collapsed"
		if building.is_marked_for_demolition:
			status_key = "building_status_rubble_clearing" if demolition_started else "building_status_rubble_marked"
	var status_text: String = tr(status_key)
	# Miglioramento in corso (2026-10-03, richiesta utente): "da <partenza> a <destinazione>" al posto di "in costruzione".
	var upgrade_from_rules := BuildingUpgradeService.get_upgrade_from_rules(building)
	if upgrade_from_rules != null and not building.is_marked_for_demolition:
		status_text = tr("building_status_upgrade_in_progress").format({
			"from": tr(upgrade_from_rules.building_name),
			"to": tr(building.rules.building_name) if building.rules != null else building.building_type_name,
		})
	status_label.text = tr("building_status_label").format({"status": status_text})
	if demolition_started:
		status_label.add_theme_color_override("font_color", DEMOLITION_IN_PROGRESS_STATUS_COLOR)
	else:
		status_label.remove_theme_color_override("font_color")
	_refresh_influence_buttons(building)
	_refresh_sacredness(building)
	_refresh_buried_list(building)
	_refresh_info(building)
	_refresh_command_icon_row(building, demolition_started)
	# Riparazione richiesta e non ancora assegnata (2026-10-10, coda dei lavori): "Riparazione in attesa di assegnazione".
	var repair_waiting: bool = repairer_names.is_empty() and building.repair_requested
	# Escluso dalla riparazione automatica (2026-10-10, X del cassetto): riga breve, solo se non c'è altro da dire.
	var repair_excluded: bool = repairer_names.is_empty() and not building.repair_requested and building.repair_auto_excluded
	_repair_status_label.visible = (not repairer_names.is_empty() or repair_waiting or repair_excluded) and building.is_complete
	if _repair_status_label.visible:
		if repair_excluded:
			_repair_status_label.text = tr("building_repair_auto_excluded_label")
		else:
			_repair_status_label.text = tr("building_repair_waiting_label") if repair_waiting else tr("building_repair_in_progress_label").format({"names": ", ".join(repairer_names)})
	_damaged_effects_label.visible = building.is_damaged()
	# Riparazione ferma per materiale (2026-10-10, passo 4): riga arancione sotto lo stato della riparazione.
	var repair_missing := RepairAction.get_supply_missing(building) if building.repair_awaiting_material and not repairer_names.is_empty() else {}
	_repair_wait_label.visible = not repair_missing.is_empty()
	if _repair_wait_label.visible:
		var material_names: Array[String] = []
		for material_name in repair_missing.keys():
			material_names.append(IconRegistry.get_resource_display_name(String(material_name)).to_lower())
		_repair_wait_label.text = tr("building_repair_waiting_material_label").format({"materials": ", ".join(material_names)})
	_refresh_construction_progress(building)
	# "In attesa di materiale" (2026-09-14, richiesta utente — segnalazione player per un cantiere
	# bloccato per mancanza di materiale) — SOLO visibile/valorizzata mentre building.is_awaiting_
	# material resta true (HumanIndividualActionService._resolve_material_shortage gestisce la
	# transizione, questo pannello resta "muto": legge, non decide). Sparisce da sé al prossimo
	# show_building() successivo alla risoluzione (bonus/deposito manuale sufficiente).
	#
	# Solo per la fase setup_site (o is_awaiting_material rimasto true in una transizione limite): in fase "build" la
	# riga "Per completare la costruzione servono:" è stata tolta (2026-10-02, richiesta utente) — ripeteva gli stessi
	# dati (required_materials - stored_resources) della riga "Materiale (consegnato/richiesto):", vedi
	# _refresh_delivered_materials.
	var is_build_phase: bool = _resolve_active_construction_phase(building) == "build"
	# Solo per un cantiere (2026-09-29): una workstation completa può essere "in attesa" per la produzione (rifornimento
	# automatico, ProduceAction) — il suo fabbisogno è già nella sezione Produzione, non nelle righe del cantiere.
	var show_site_awaiting: bool = building.is_awaiting_material and not building.is_complete
	awaiting_material_label.visible = show_site_awaiting and not is_build_phase
	# Produzione in attesa di materiale (2026-09-23, richiesta utente — Produce Task): su un edificio
	# completo con una produzione in corso (Building.production_progress) a cui mancano input, stessa
	# caption+griglia di chip della fase build, con una caption dedicata. Letto da ProductionService,
	# nessun flag su Building: "in attesa" = produzione registrata e input mancanti. Solo le ricette
	# con una Task che ci lavora (2026-09-24): quelle sospese hanno la propria riga sotto.
	# Il fabbisogno della produzione in corso è nella sezione Produzione dal 2026-09-27 (_refresh_production_status).
	_refresh_suspended_production(building, suspended_recipes)
	if show_site_awaiting and not is_build_phase:
		var shortage := _resolve_setup_site_material_shortage(building)
		awaiting_material_label.text = tr("building_awaiting_material_label").format({
			"quantity": shortage["quantity"],
			"material": shortage["material_display_name"],
		})

	# Costruttore assegnato (2026-09-18, richiesta utente — "durante la fase di costruzione... puoi
	# indicare costruttore assegnato: con il nome? e se non c'è scrivere che è mancante") — visibile
	# in TUTTE le fasi di lavorazione attiva (setup_site/clear_site/build), stesso gate di
	# construction_phase_label/construction_progress_bar_margin sopra (_resolve_active_construction_
	# phase != ""), nascosto per un edificio completo. assigned_builder_names arriva già risolto da
	# GameScene._resolve_assigned_builder_names (pannello "muto", stesso principio di
	# residents_display_data): current_task ATTIVA o SOSPESA in task_queue, può contenere più di un
	# nome (BuildingRules.max_builders). Array vuoto -> messaggio "mancante" invece di una riga vuota.
	var is_under_construction: bool = _resolve_active_construction_phase(building) != ""
	assigned_builder_label.visible = is_under_construction
	if is_under_construction:
		assigned_builder_label.text = (
			tr("building_assigned_builder_label").format({"names": ", ".join(assigned_builder_names)})
			if not assigned_builder_names.is_empty()
			else tr("building_assigned_builder_missing")
		)
	# Suggerimento "come assegnarlo" (2026-10-09): cantiere senza costruttore sotto "Costruttore assegnato: mancante";
	# edificio da demolire senza demolitore sopra la riga dei comandi a icone.
	var hint_key := ""
	if building.is_marked_for_demolition:
		if demolisher_names.is_empty():
			# Macerie (2026-10-10): il suggerimento parla di sgombero.
			hint_key = "rubble" if building.is_rubble() else "demolition"
	elif is_under_construction and assigned_builder_names.is_empty():
		hint_key = "site"
	_assign_hint_label.visible = hint_key != ""
	if hint_key != "":
		var state := "locked" if _assign_hint_queue_enabled and _assign_hint_locked else ("queued" if _assign_hint_queue_enabled else "manual")
		_assign_hint_label.text = tr("building_assign_hint_%s_%s" % [hint_key, state])
		if hint_key == "site":
			move_child(_assign_hint_label, assigned_builder_label.get_index() + 1)
		else:
			# Dal 2026-10-10 la riga dei comandi è in alto, fuori dal pannello: il suggerimento va subito sotto lo stato.
			move_child(_assign_hint_label, $StatusRow.get_index() + 1)
	# Workstation completa (2026-09-24; dal 2026-09-27 nella sezione Produzione): "In produzione:" con la X di annullo,
	# lavoratore assegnato, attesa attrezzi e cosa serve ancora — vedi _refresh_production_status.
	# Postazione che lavora da sola (2026-10-03, ProductionService.has_only_auto_progress_recipes — l'essiccatoio): niente
	# "In produzione", lavoratore assegnato e materiali dell'ordine, al loro posto le voci in avanzamento.
	var is_auto_only: bool = ProductionService.has_only_auto_progress_recipes(building)
	var is_active_workstation: bool = building.is_complete and building.rules != null and building.rules.is_workstation and not is_auto_only
	# X di annullo accanto allo stato (2026-09-26): dal 2026-09-27 solo per i costruttori di un cantiere; la produzione
	# ha la propria X nella riga "In produzione:". Con "mancante" resta nascosta: nessuna Task da annullare.
	# Tolta dal 2026-10-03 (richiesta utente): sul cantiere c'erano due croci, questa e "Annulla cantiere" nella riga dei
	# comandi. Il nodo resta, sempre nascosto.
	cancel_work_button.visible = false
	tool_wait_label.visible = is_active_workstation and not production_tool_wait_lines.is_empty()
	tool_wait_label.text = "\n".join(production_tool_wait_lines) if tool_wait_label.visible else ""
	_refresh_production_status(building, is_active_workstation, production_orders, working_recipes)

	# Terza riga dell'intestazione (2026-09-27): "Costruito anno X". "Non ancora costruito" SOLO per
	# un edificio non completo; completo ma senza anno registrato (built_year < 0, es. salvataggio vecchio) -> "anno non
	# noto", mai la contraddizione con "Stato: Completo".
	var built_text: String
	if building.built_year >= 0:
		built_text = tr("building_built_year_label").format({"year": building.built_year})
	elif building.is_complete:
		built_text = tr("building_built_year_unknown")
	else:
		built_text = tr("building_not_yet_built")
	# Macerie (2026-10-10): "Crollo di <edificio>" al posto dell'anno di costruzione.
	if building.is_rubble():
		var source_rules := BuildingCalculator.get_building_rules(building.rubble_source_name) if building.rubble_source_name != "" else null
		built_text = tr("building_rubble_source_label").format({
			"building": tr(source_rules.building_name) if source_rules != null else building.rubble_source_name,
		})
	# Dal 2026-10-10 l'Integrità non è più su questa riga: ha la propria riga con barra sotto (_refresh_durability).
	built_year_label.text = built_text
	_refresh_durability(building)

	_refresh_influence_received(building)
	_refresh_residents_grid(building, residents_display_data)
	_refresh_storage_grid(building)
	_refresh_auto_progress(building, building.is_complete and is_auto_only)
	_refresh_output_buffer(building)
	_refresh_toolkit(building)
	_refresh_delivered_materials(building)
	_refresh_repair_materials(building)
	_refresh_production_recipes(building, production_claimant_names)
	_refresh_settings_section(building)


# Riga dei comandi a icone (2026-10-03, richiesta utente): stato di ogni icona e visibilità della riga (nascosta se
# nessuna icona è visibile).
func _refresh_command_icon_row(building: Building, demolition_started: bool) -> void:
	_refresh_upgrade_button(building)
	_refresh_empty_all_button(building)
	# Demolisci / Annulla cantiere (2026-09-27: su un cantiere la conferma annulla il cantiere): stesso bottone, icona
	# e tooltip diversi. Nascosto per un edificio "da demolire", dove al suo posto c'è Annulla demolizione.
	# Macerie (2026-10-10): niente Demolisci, al suo posto "Sgombera" a sinistra.
	demolish_button.visible = not building.is_marked_for_demolition and not building.is_rubble()
	clear_rubble_button.visible = building.is_rubble() and not building.is_marked_for_demolition
	clear_rubble_button.tooltip_text = "%s\n%s" % [tr("building_clear_rubble_button"), tr("building_command_clear_rubble_detail").format({
		"labor": roundi(float(building.rules.required_labor) * DemolishAction.LABOR_FRACTION_OF_BUILD) if building.rules != null else 0,
	})]
	if building.is_complete:
		(_command_icons[demolish_button] as BuildingCommandIcon).kind = BuildingCommandIcon.KIND_DEMOLISH
		demolish_button.tooltip_text = "%s\n%s" % [tr("building_demolish_button"), tr("building_command_demolish_detail")]
	else:
		var is_upgrade_site := BuildingUpgradeService.is_upgrade_site(building)
		(_command_icons[demolish_button] as BuildingCommandIcon).kind = BuildingCommandIcon.KIND_CANCEL_UPGRADE if is_upgrade_site else BuildingCommandIcon.KIND_CANCEL_SITE
		var detail_key := "building_command_cancel_upgrade_detail" if is_upgrade_site else "building_command_cancel_site_detail"
		demolish_button.tooltip_text = "%s\n%s" % [tr("building_cancel_site_button"), tr(detail_key)]
	# Annulla demolizione: visibile per tutto il tempo in cui l'edificio è "da demolire"; spento, con il motivo, a
	# demolizione iniziata (non più annullabile).
	cancel_demolition_button.visible = building.is_marked_for_demolition
	# Macerie (2026-10-10): la pala barrata al posto della dinamite barrata.
	(_command_icons[cancel_demolition_button] as BuildingCommandIcon).kind = \
		BuildingCommandIcon.KIND_CANCEL_CLEAR_RUBBLE if building.is_rubble() else BuildingCommandIcon.KIND_CANCEL_DEMOLITION
	cancel_demolition_button.disabled = demolition_started
	cancel_demolition_button.tooltip_text = "%s\n%s" % [
		tr("building_cancel_demolition_button"),
		tr("building_command_cancel_demolition_started") if demolition_started else tr("building_command_cancel_demolition_detail"),
	]
	# Sgombero delle macerie (2026-10-10): stesso bottone, testi dello sgombero.
	if building.is_rubble():
		cancel_demolition_button.tooltip_text = "%s\n%s" % [
			tr("building_cancel_clear_rubble_button"),
			tr("building_command_cancel_clear_rubble_started") if demolition_started else tr("building_command_cancel_clear_rubble_detail"),
		]
	# Demolisci da solo a destra (2026-10-10): dopo lo spaziatore elastico; come "Annulla cantiere"/"Annulla miglioramento"
	# lo stesso bottone torna a sinistra con gli altri comandi.
	var spacer_index := _command_icon_spacer.get_index()
	if building.is_complete:
		command_icon_row.move_child(demolish_button, command_icon_row.get_child_count() - 1)
	elif demolish_button.get_index() > spacer_index:
		command_icon_row.move_child(demolish_button, spacer_index)
	_refresh_repair_button(building)
	for button in [upgrade_button, repair_button, clear_rubble_button, empty_all_button, demolish_button, cancel_demolition_button]:
		_style_command_icon_button(button)
	command_icon_row.visible = upgrade_button.visible or repair_button.visible or clear_rubble_button.visible or empty_all_button.visible \
		or demolish_button.visible or cancel_demolition_button.visible
	_update_command_bar_visibility()


# Riga dei comandi in alto (2026-10-10, richiesta utente): subito sotto la riga del nome, prima di "Stato", con una linea
# sottile sotto, sempre in quel punto. Non scorre con il contenuto: se il pannello sta dentro uno ScrollContainer (la
# scheda Selezione), la riga e la linea vanno nel genitore dello scroll, subito prima di lui (sotto l'intestazione col
# nome, che è già fuori dallo scroll); altrimenti in cima al pannello. Visibile solo col pannello visibile e almeno un
# comando visibile: niente riga vuota né linea da sola.
var _command_bar: VBoxContainer = null


func _mount_command_bar() -> void:
	if _command_bar != null:
		return
	_command_bar = VBoxContainer.new()
	_command_bar.add_theme_constant_override("separation", 2)
	_command_bar.visible = false
	command_icon_row.get_parent().remove_child(command_icon_row)
	_command_bar.add_child(command_icon_row)
	_command_bar.add_child(HSeparator.new())
	var scroll := _find_ancestor_scroll()
	if scroll != null and scroll.get_parent() != null:
		var host := scroll.get_parent()
		host.add_child(_command_bar)
		host.move_child(_command_bar, scroll.get_index())
		# Il pannello non è più il genitore della barra: se sparisce lui, sparisce anche lei.
		tree_exiting.connect(func() -> void:
			if is_instance_valid(_command_bar):
				_command_bar.queue_free()
		)
	else:
		add_child(_command_bar)
		move_child(_command_bar, 0)
	_update_command_bar_visibility()


func _find_ancestor_scroll() -> ScrollContainer:
	var node := get_parent()
	while node != null:
		if node is ScrollContainer:
			return node
		node = node.get_parent()
	return null


func _update_command_bar_visibility() -> void:
	if _command_bar != null and is_instance_valid(_command_bar):
		_command_bar.visible = visible and command_icon_row.visible


# "Ripara" e la riga di stato della riparazione (2026-10-10), creati una volta in _ready. Il pulsante sta subito dopo
# Migliora; la riga subito sotto lo stato, a capo se lunga (il pannello non si allarga).
func _build_repair_controls() -> void:
	# TooltipButton (2026-10-10, materiali della riparazione): tooltip con le icone dei materiali, come Migliora.
	repair_button = TooltipButton.new()
	repair_button.visible = false
	command_icon_row.add_child(repair_button)
	command_icon_row.move_child(repair_button, upgrade_button.get_index() + 1)
	repair_button.pressed.connect(func(): repair_requested.emit(_current_building))
	# Sgombera (2026-10-10): primo della riga, a sinistra.
	clear_rubble_button = Button.new()
	clear_rubble_button.visible = false
	command_icon_row.add_child(clear_rubble_button)
	command_icon_row.move_child(clear_rubble_button, 0)
	clear_rubble_button.pressed.connect(func(): clear_rubble_requested.emit(_current_building))
	_repair_status_label = Label.new()
	_repair_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_repair_status_label.custom_minimum_size.x = 0.0
	_repair_status_label.add_theme_font_size_override("font_size", 10)
	_repair_status_label.visible = false
	add_child(_repair_status_label)
	move_child(_repair_status_label, $StatusRow.get_index() + 1)
	_damaged_effects_label = Label.new()
	_damaged_effects_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_damaged_effects_label.custom_minimum_size.x = 0.0
	_damaged_effects_label.add_theme_font_size_override("font_size", 10)
	_damaged_effects_label.add_theme_color_override("font_color", ORDER_OUTPUT_WARNING_COLOR)
	_damaged_effects_label.text = tr("building_damaged_effects_label")
	_damaged_effects_label.visible = false
	add_child(_damaged_effects_label)
	move_child(_damaged_effects_label, $StatusRow.get_index() + 1)
	_repair_wait_label = Label.new()
	_repair_wait_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_repair_wait_label.custom_minimum_size.x = 0.0
	_repair_wait_label.add_theme_font_size_override("font_size", 10)
	_repair_wait_label.add_theme_color_override("font_color", ORDER_OUTPUT_WARNING_COLOR)
	_repair_wait_label.visible = false
	add_child(_repair_wait_label)
	move_child(_repair_wait_label, _repair_status_label.get_index() + 1)


# Ripara (2026-10-10, richiesta utente): visibile su un edificio completo con Integrità; acceso solo se non è "da
# demolire", nessuno lo sta già riparando e l'Integrità è sotto Building.DURABILITY_REPAIRABLE_RATIO. Tooltip: il
# comando e il lavoro che serve ora (intero), o il motivo per cui è spento.
func _refresh_repair_button(building: Building) -> void:
	repair_button.visible = building.is_complete and building.rules != null and building.rules.max_durability > 0
	if not repair_button.visible:
		return
	var ratio: float = building.current_durability / float(building.rules.max_durability)
	var reason := ""
	if building.is_marked_for_demolition:
		reason = tr("building_command_repair_marked_for_demolition")
	elif not _repairer_names.is_empty():
		reason = tr("building_command_repair_in_progress")
	elif building.repair_requested:
		reason = tr("building_command_repair_already_requested")
	elif ratio >= Building.DURABILITY_REPAIRABLE_RATIO:
		reason = tr("building_command_repair_threshold").format({"percent": roundi(Building.DURABILITY_REPAIRABLE_RATIO * 100.0)})
	repair_button.disabled = reason != ""
	var detail := reason if reason != "" else tr("building_command_repair_labor").format({"labor": ceili(RepairAction.get_labor_to_full(building))})
	repair_button.tooltip_text = "%s\n%s" % [tr("building_repair_button"), detail]
	# Acceso (2026-10-10): tooltip con i materiali che servirebbero adesso (icone come nei tooltip di costruzione) e il
	# lavoro; spento: il testo semplice sopra, con il motivo.
	repair_button.tooltip_builder = _repair_tooltip if reason == "" else Callable()


func _repair_tooltip(_for_text: String) -> Control:
	var building := _current_building
	if building == null:
		return null
	return BuildingCostTooltip.build(
		tr("building_repair_button"), "", RepairAction.compute_plan_materials(building), ceili(RepairAction.get_labor_to_full(building))
	)


# Svuota tutto (2026-10-03, richiesta utente — ora un'icona della riga comandi): su ogni edificio completo con uno
# storage (storage_slot_count > 0), non solo sui depositi. Spento con il motivo se non c'è nulla da svuotare (né
# magazzino né prodotti finiti: GroundPileService.drop_building_contents svuota entrambi).
func _refresh_empty_all_button(building: Building) -> void:
	empty_all_button.visible = building.rules != null and building.rules.storage_slot_count > 0 and building.is_complete
	if not empty_all_button.visible:
		return
	var has_contents := BuildingUpgradeService.has_stored_resources(building)
	for output_name in building.production_output.keys():
		if int(building.production_output[output_name]) > 0:
			has_contents = true
	empty_all_button.disabled = not has_contents
	empty_all_button.tooltip_text = "%s\n%s" % [
		tr("building_settings_empty_all_button"),
		tr("building_command_empty_all_detail") if has_contents else tr("building_command_empty_all_nothing"),
	]


# Pulsanti della riga comandi: grandi quanto il 🎯 "centra" (misurato col tema di base), ciascuno con la sua icona
# disegnata a tutto riquadro meno COMMAND_ICON_INSET. Aspetto da tasto (2026-10-10): IconButtonStyle, stessa dimensione.
# Disposizione (2026-10-10, richiesta utente): i comandi a sinistra, attaccati (un comando nascosto non occupa posto);
# CommandIconSpacer, prima un vuoto fisso di 10 px, ora si allarga e spinge Demolisci tutto a destra
# (_refresh_command_icon_row). "Annulla demolizione" sta a sinistra, prima dello spaziatore.
func _setup_command_icon_buttons() -> void:
	_command_icon_spacer = $CommandIconRow/CommandIconSpacer
	_command_icon_spacer.custom_minimum_size = Vector2.ZERO
	_command_icon_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_command_icon_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	command_icon_row.move_child(cancel_demolition_button, _command_icon_spacer.get_index())
	var probe := Button.new()
	probe.text = COMMAND_ICON_SIZE_PROBE_TEXT
	add_child(probe)
	var button_size := probe.get_combined_minimum_size()
	remove_child(probe)
	probe.free()
	var kinds := {
		upgrade_button: BuildingCommandIcon.KIND_UPGRADE,
		repair_button: BuildingCommandIcon.KIND_REPAIR,
		clear_rubble_button: BuildingCommandIcon.KIND_CLEAR_RUBBLE,
		empty_all_button: BuildingCommandIcon.KIND_EMPTY_ALL,
		demolish_button: BuildingCommandIcon.KIND_DEMOLISH,
		cancel_demolition_button: BuildingCommandIcon.KIND_CANCEL_DEMOLITION,
	}
	for button: Button in kinds:
		button.text = ""
		button.custom_minimum_size = button_size
		button.focus_mode = Control.FOCUS_NONE
		IconButtonStyle.apply(button)
		var icon := BuildingCommandIcon.new()
		icon.kind = kinds[button]
		button.add_child(icon)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = COMMAND_ICON_INSET
		icon.offset_top = COMMAND_ICON_INSET
		icon.offset_right = -COMMAND_ICON_INSET
		icon.offset_bottom = -COMMAND_ICON_INSET
		_command_icons[button] = icon


# Comando spento: icona attenuata (fondo e bordo spenti li dà IconButtonStyle).
func _style_command_icon_button(button: Button) -> void:
	var icon: BuildingCommandIcon = _command_icons.get(button)
	if icon != null:
		icon.modulate = COMMAND_ICON_DISABLED_MODULATE if button.disabled else Color(1, 1, 1, 1)


# Bottone "Migliora in <destinazione>" (2026-10-03, richiesta utente — miglioramento passo 1): per un edificio completo,
# non "da demolire", con BuildingRules.upgrades_to. Spento con il motivo se l'idea della destinazione non è scoperta.
# Tooltip (2026-10-07, richiesta utente): stesso formato dei bottoni della barra degli edifici (BuildingCostTooltip) —
# "Migliora in <edificio>", descrizione breve della destinazione, materiali da portare (già scontati,
# BuildingUpgradeService.get_upgrade_cost), lavoro, poi l'eventuale motivo per cui è spento. Costruito al passaggio
# del mouse (_upgrade_tooltip). Capienza, conservazione, residenti e riposo non stanno più qui (blocco Info e help).
func _refresh_upgrade_button(building: Building) -> void:
	var target := BuildingUpgradeService.get_upgrade_rules(building)
	upgrade_button.visible = target != null and building.is_complete and not building.is_marked_for_demolition
	if not upgrade_button.visible:
		return
	upgrade_button.disabled = _get_upgrade_missing_idea_line(target) != ""
	# Testo semplice di riserva (e perché il tooltip compaia): il nome del comando.
	upgrade_button.tooltip_text = tr("building_upgrade_button").format({"building": tr(target.building_name)})
	if not upgrade_button.tooltip_builder.is_valid():
		upgrade_button.tooltip_builder = _upgrade_tooltip


func _upgrade_tooltip(_for_text: String) -> Control:
	var building := _current_building
	var target := BuildingUpgradeService.get_upgrade_rules(building) if building != null else null
	if target == null:
		return null
	var cost := BuildingUpgradeService.get_upgrade_cost(building.rules, target)
	var extra_lines: Array[String] = []
	var missing_idea_line := _get_upgrade_missing_idea_line(target)
	if missing_idea_line != "":
		extra_lines.append(missing_idea_line)
	return BuildingCostTooltip.build(
		tr("building_upgrade_button").format({"building": tr(target.building_name)}), building.rules.upgrades_to,
		cost["to_bring"], int(cost["labor"]), extra_lines
	)


# "Serve l'idea «…»" se l'idea della destinazione non è scoperta, altrimenti "".
func _get_upgrade_missing_idea_line(target: BuildingRules) -> String:
	var folk: Folk = GameSettings.active_human_folk
	if target.required_idea_id == "" or (folk != null and folk.completed_ideas.has(target.required_idea_id)):
		return ""
	var idea := IdeaCalculator.get_idea(target.required_idea_id)
	return tr("tech_tree_requires").format({"ideas": tr(idea.display_name) if idea != null else target.required_idea_id})


# Moltiplicatore di conservazione di una categoria (BuildingRules.durability_multiplier_by_category, indice = categoria);
# 1.0 se l'elenco è più corto.
func _durability_multiplier(rules: BuildingRules, category_index: int) -> float:
	if rules == null or category_index >= rules.durability_multiplier_by_category.size():
		return 1.0
	return rules.durability_multiplier_by_category[category_index]


# Un decimale, come il moltiplicatore di riposo ("1.2").
# Moltiplicatore come scarto percentuale (2026-10-04, richiesta utente — conservazione dei magazzini, riposo delle
# abitazioni, lavoro e combustibile richiesti dalle postazioni): ×1.1 -> "+10%", ×1.0 -> "—", ×0.7 -> "−30%".
func _format_percent_bonus(multiplier: float) -> String:
	var percent := roundi((multiplier - 1.0) * 100.0)
	if percent == 0:
		return "—"
	return ("+%d%%" % percent) if percent > 0 else ("−%d%%" % -percent)


# "3 Corda di fibre, 20 Pelle" in ordine di nome; "nessuno" se vuoto.
func _format_material_list(materials: Dictionary) -> String:
	if materials.is_empty():
		return tr("building_upgrade_nothing")
	var names: Array = materials.keys()
	names.sort()
	var parts: Array[String] = []
	for material_name in names:
		parts.append("%d %s" % [int(materials[material_name]), IconRegistry.get_resource_display_name(String(material_name))])
	return ", ".join(parts)


# Gruppo delle icone di influenza (2026-10-02): creato qui, aggiunto da GameScene a GameInfoTabs.header_actions.
var influence_buttons_box: HBoxContainer = null
var _influence_buttons: Dictionary = {}  # InfluenceService.InfluenceType -> Button
# Tipo in anteprima (puntatore sopra la sua icona abilitata), -1 = nessuna anteprima.
var _previewed_influence_type: int = -1


func _build_influence_buttons() -> void:
	influence_buttons_box = HBoxContainer.new()
	influence_buttons_box.add_theme_constant_override("separation", 2)
	influence_buttons_box.visible = false
	for entry in INFLUENCE_BUTTONS:
		var influence_type: int = entry["type"]
		var button := Button.new()
		# Emoji della voce del layer (MapLayerRegistry): non si può tingere, quindi il colore del cerchio va su bordo
		# e sfondo (_style_influence_button).
		button.text = String(MapLayerRegistry.get_layer(String(entry["layer_id"])).get("icon", "?"))
		button.custom_minimum_size = INFLUENCE_BUTTON_SIZE
		button.add_theme_font_size_override("font_size", 11)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func(): influence_footprint_requested.emit(_current_building, influence_type))
		button.mouse_entered.connect(func(): _start_influence_preview(influence_type))
		button.mouse_exited.connect(_on_influence_button_mouse_exited.bind(influence_type))
		influence_buttons_box.add_child(button)
		_influence_buttons[influence_type] = button


func _start_influence_preview(influence_type: int) -> void:
	var button: Button = _influence_buttons.get(influence_type)
	if button == null or button.disabled or _current_building == null:
		return
	_previewed_influence_type = influence_type
	influence_preview_started.emit(_current_building, influence_type)


func _on_influence_button_mouse_exited(influence_type: int) -> void:
	if _previewed_influence_type == influence_type:
		_end_influence_preview()


func _end_influence_preview() -> void:
	if _previewed_influence_type < 0:
		return
	_previewed_influence_type = -1
	influence_preview_ended.emit()


func _on_visibility_changed_for_influence() -> void:
	if visible:
		return
	influence_buttons_box.visible = false
	_end_influence_preview()


func _style_influence_button(button: Button, color: Color, enabled: bool) -> void:
	var tint := color if enabled else INFLUENCE_BUTTON_DISABLED_COLOR
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(tint.r, tint.g, tint.b, 0.35 if state == "hover" else 0.2)
		style.border_color = Color(tint.r, tint.g, tint.b, 1.0 if enabled else 0.6)
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		button.add_theme_stylebox_override(state, style)
	# Emoji in grigio e semitrasparente da disabilitata.
	button.modulate = Color(1, 1, 1, 1) if enabled else Color(0.6, 0.6, 0.6, 0.6)


# Gruppo nascosto per un edificio non completo o senza alcun raggio; altrimenti ogni icona attiva solo se l'edificio
# ha quel raggio (InfluenceService.get_effective_radius), con il raggio nel tooltip. Un'anteprima in corso finisce se
# il gruppo sparisce o la sua icona diventa disabilitata; altrimenti segue l'edificio mostrato.
func _refresh_influence_buttons(building: Building) -> void:
	if influence_buttons_box == null:
		return
	influence_buttons_box.visible = building.is_complete and InfluenceService.has_any_influence(building)
	for entry in INFLUENCE_BUTTONS:
		var influence_type: int = entry["type"]
		var button: Button = _influence_buttons[influence_type]
		var radius := InfluenceService.get_effective_radius(building, influence_type)
		button.disabled = radius <= 0
		button.tooltip_text = _influence_tooltip(building, entry, radius)
		_style_influence_button(button, InfluenceFootprintOverlay.COLORS.get(influence_type, Color.WHITE), radius > 0)
	if _previewed_influence_type >= 0:
		var previewed_button: Button = _influence_buttons[_previewed_influence_type]
		if not influence_buttons_box.visible or previewed_button.disabled:
			_end_influence_preview()
		else:
			influence_preview_started.emit(building, _previewed_influence_type)


# Tooltip di un'icona di influenza. Politica e cultura: solo il raggio. Religiosa (2026-10-03, punti e soglie): raggio,
# punti (parte intera) e prossima soglia, solo i punti oltre l'ultima soglia; più la perdita annua se da almeno un
# anno non si celebra un rito (InfluenceService.has_neglected_rites).
func _influence_tooltip(building: Building, entry: Dictionary, radius: int) -> String:
	if radius <= 0:
		return tr(String(entry["none_key"]))
	var influence_type: int = entry["type"]
	if influence_type != InfluenceService.InfluenceType.RELIGIOUS:
		return tr(String(entry["tooltip_key"])).format({"radius": radius})
	# Valori effettivi (2026-10-10): sacralità a metà su un edificio danneggiato.
	var effective_points := InfluenceService.get_effective_points(building, influence_type)
	var points := floori(effective_points)
	var next_threshold := InfluenceService.get_next_threshold(building, influence_type, effective_points)
	var text: String
	if next_threshold < 0.0:
		text = tr("building_influence_religious_max_tooltip").format({"radius": radius, "points": points})
	else:
		text = tr(String(entry["tooltip_key"])).format({"radius": radius, "points": points, "next": floori(next_threshold)})
	var game_data: GameData = GameSettings.active_game_data
	if game_data != null and InfluenceService.has_neglected_rites(building, influence_type, game_data.get_absolute_day()):
		text += "\n" + tr("building_influence_no_rite_tooltip").format({"loss": roundi(InfluenceService.get_neglected_rites_loss(building, influence_type))})
	return text


# Icona ℹ delle caratteristiche dell'edificio (2026-10-04, richiesta utente — stesso schema del pannello dell'individuo):
# nell'intestazione della scheda selezione accanto alle icone di influenza e al 🎯 (GameScene aggiunge info_button_box a
# GameInfoTabs.header_actions), visibile quando lo è il pannello. Tooltip con le caratteristiche; al clic apre e chiude
# il blocco _info_block in cima al pannello, chiuso di base, che resta aperto o chiuso passando da un edificio all'altro.
# Le righe vengono dalle regole del tipo (_build_info_lines): magazzini, abitazioni, postazioni di lavoro, e per tutti
# durabilità massima e raggi di influenza di base.
#
# Impaginazione (2026-10-04, richiesta utente): riquadro con lo stesso stile dei riquadri dei parametri vitali del
# pannello dell'individuo (INFO_BOX_COLOR, angoli 4, margini 6); una voce per riga senza andare a capo (etichette che
# tagliano con i puntini, così non allargano mai il pannello; il testo intero resta nel tooltip dell'icona); la
# conservazione su un'intestazione e una riga rientrata per categoria, in percentuale (_format_percent_bonus).
const INFO_BUTTON_TEXT := "ℹ"
# Riquadro e righe dal componente comune InfoCardBlock (2026-10-05, estratto da qui, condiviso con la scheda del tipo
# dei pipottini): stesso aspetto di prima.
const INFO_TOOLTIP_INDENT := "    "
var info_button_box: HBoxContainer = null
var _info_button: Button = null
var _info_block: InfoCardBlock = null
var _info_open: bool = false


func _build_info_button() -> void:
	info_button_box = HBoxContainer.new()
	info_button_box.visible = false
	_info_button = Button.new()
	_info_button.text = INFO_BUTTON_TEXT
	_info_button.focus_mode = Control.FOCUS_NONE
	_info_button.toggle_mode = true
	_info_button.toggled.connect(_on_info_toggled)
	info_button_box.add_child(_info_button)
	_info_block = InfoCardBlock.new()
	_info_block.visible = false
	add_child(_info_block)
	move_child(_info_block, 0)
	visibility_changed.connect(func(): info_button_box.visible = visible)


func _on_info_toggled(pressed: bool) -> void:
	_info_open = pressed
	_info_block.visible = _info_open


func _refresh_info(building: Building) -> void:
	if _info_block == null:
		return
	var rows := _build_info_lines(building.rules)
	_info_button.tooltip_text = _info_block.set_rows(rows)
	_info_button.set_pressed_no_signal(_info_open)
	_info_block.visible = _info_open
	info_button_box.visible = visible


# Righe del blocco Info: dal tipo dell'edificio (BuildingInfoLines.build, condivisa — 2026-10-07, spostata da qui per
# usarla anche dove l'edificio non esiste in mappa). Nessuna riga dipende dall'edificio costruito.
func _build_info_lines(rules: BuildingRules) -> Array[Dictionary]:
	return BuildingInfoLines.build(rules)


func _build_sacredness_box() -> void:
	_sacredness_box = VBoxContainer.new()
	_sacredness_box.add_theme_constant_override("separation", 1)
	_sacredness_box.visible = false
	_sacredness_label = _build_sacredness_label()
	_sacredness_box.add_child(_sacredness_label)
	_sacredness_bar = ProgressBar.new()
	_sacredness_bar.show_percentage = false
	_sacredness_bar.custom_minimum_size = Vector2(0, SACREDNESS_BAR_HEIGHT)
	_sacredness_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sacredness_box.add_child(_sacredness_bar)
	_sacredness_radius_label = _build_sacredness_label()
	_sacredness_box.add_child(_sacredness_radius_label)


func _build_sacredness_label() -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.add_theme_font_size_override("font_size", BURIED_FONT_SIZE)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


# Riga "Integrità: N%" e barra (vedi _durability_label): stessi parametri di ConstructionPhaseLabel/
# ConstructionProgressBarMargin del .tscn (font 10, a capo, margini 4, altezza 14, sfondo e angoli della barra della
# costruzione); il riempimento è una copia dello stile della costruzione, ricolorata in _refresh_durability.
func _build_durability_rows() -> void:
	_durability_label = Label.new()
	_durability_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_durability_label.add_theme_font_size_override("font_size", 10)
	_durability_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_durability_label.visible = false
	add_child(_durability_label)
	move_child(_durability_label, built_year_label.get_index() + 1)
	_durability_bar_margin = MarginContainer.new()
	_durability_bar_margin.add_theme_constant_override("margin_left", 4)
	_durability_bar_margin.add_theme_constant_override("margin_right", 4)
	_durability_bar_margin.visible = false
	_durability_bar = ProgressBar.new()
	_durability_bar.custom_minimum_size = construction_progress_bar.custom_minimum_size
	_durability_bar.min_value = 0.0
	_durability_bar.max_value = 100.0
	_durability_bar.show_percentage = false
	_durability_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	_durability_bar.add_theme_stylebox_override("background", construction_progress_bar.get_theme_stylebox("background"))
	_durability_fill_style = construction_progress_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	if _durability_fill_style != null:
		_durability_bar.add_theme_stylebox_override("fill", _durability_fill_style)
	_durability_bar_margin.add_child(_durability_bar)
	add_child(_durability_bar_margin)
	move_child(_durability_bar_margin, _durability_label.get_index() + 1)


# Materiali per la riparazione (2026-10-10, Building.repair_materials): didascalia e chip delle risorse presenti con la
# quantità, nello stile di "Materiali consegnati" (stessa didascalia e stessa griglia a capo, duplicate dal .tscn), subito
# sotto la barra dell'Integrità. Visibili solo con il contenitore non vuoto.
var _repair_materials_caption: Label = null
var _repair_materials_grid: HFlowContainer = null


func _build_repair_materials_rows() -> void:
	_repair_materials_caption = delivered_materials_caption.duplicate() as Label
	_repair_materials_caption.visible = false
	add_child(_repair_materials_caption)
	move_child(_repair_materials_caption, _durability_bar_margin.get_index() + 1)
	_repair_materials_grid = delivered_materials_grid.duplicate() as HFlowContainer
	_repair_materials_grid.visible = false
	add_child(_repair_materials_grid)
	move_child(_repair_materials_grid, _repair_materials_caption.get_index() + 1)


func _refresh_repair_materials(building: Building) -> void:
	for child in _repair_materials_grid.get_children():
		child.queue_free()
	var entries: Dictionary = {}
	for resource_name in building.repair_materials.keys():
		var quantity: int = int(building.repair_materials[resource_name])
		if quantity > 0:
			entries[String(resource_name)] = quantity
	_repair_materials_caption.visible = not entries.is_empty()
	_repair_materials_grid.visible = not entries.is_empty()
	if entries.is_empty():
		return
	_repair_materials_caption.text = tr("building_repair_materials_caption")
	for resource_name in entries.keys():
		_repair_materials_grid.add_child(_build_missing_material_chip(resource_name, int(entries[resource_name])))


# Integrità dell'edificio completo (cantieri e upgrade in corso: nascosta). Percentuale per difetto, così non segna
# 100% prima di essere davvero intatto; il colore segue il numero mostrato (69,6% -> "69%", giallo).
func _refresh_durability(building: Building) -> void:
	var max_durability: int = building.rules.max_durability if building.rules != null else 0
	var show := building.is_complete and max_durability > 0
	_durability_label.visible = show
	_durability_bar_margin.visible = show
	if not show:
		return
	var ratio: float = clampf(building.current_durability / float(max_durability), 0.0, 1.0)
	var percent: int = floori(ratio * 100.0 + 0.000001)
	_durability_label.text = tr("building_integrity_percent_label").format({"percent": percent})
	var points_text: String = "%d/%d" % [roundi(building.current_durability), max_durability]
	_durability_label.tooltip_text = points_text
	_durability_bar.tooltip_text = points_text
	_durability_bar.value = percent
	if _durability_fill_style != null:
		var fill_color := DURABILITY_FILL_COLOR_GOOD
		if percent < roundi(Building.DURABILITY_DAMAGED_RATIO * 100.0):
			fill_color = DURABILITY_FILL_COLOR_CRITICAL
		elif percent < roundi(Building.DURABILITY_REPAIRABLE_RATIO * 100.0):
			fill_color = DURABILITY_FILL_COLOR_DAMAGED
		_durability_fill_style.bg_color = fill_color


# Sacralità e raggio religioso attuali (vedi _sacredness_box): solo edifici completi con raggio religioso di base.
func _refresh_sacredness(building: Building) -> void:
	var religious := InfluenceService.InfluenceType.RELIGIOUS
	var base := InfluenceService.get_base_radius(building, religious)
	_sacredness_box.visible = building != null and building.is_complete and not building.is_demolished and base > 0
	if not _sacredness_box.visible:
		return
	# Valori effettivi (2026-10-10): sacralità a metà su un edificio danneggiato (i punti salvati restano interi).
	var points := InfluenceService.get_effective_points(building, religious)
	var next_threshold := InfluenceService.get_next_threshold(building, religious, points)
	if next_threshold < 0.0:
		_sacredness_label.text = tr("building_sacredness_max").format({"points": floori(points)})
		_sacredness_bar.visible = false
	else:
		_sacredness_label.text = tr("building_sacredness").format({"points": floori(points), "next": floori(next_threshold)})
		var previous_threshold := 0.0
		for threshold in InfluenceService.get_thresholds(building):
			if threshold <= points:
				previous_threshold = threshold
		_sacredness_bar.visible = true
		_sacredness_bar.min_value = 0.0
		_sacredness_bar.max_value = maxf(next_threshold - previous_threshold, 0.001)
		_sacredness_bar.value = clampf(points - previous_threshold, 0.0, _sacredness_bar.max_value)
	_sacredness_label.tooltip_text = _sacredness_label.text
	var radius := InfluenceService.get_effective_radius(building, religious)
	_sacredness_radius_label.text = tr("building_sacredness_radius").format({"radius": radius, "bonus": radius - base})
	_sacredness_radius_label.tooltip_text = _sacredness_radius_label.text


# Elenco dei sepolti (vedi _buried_box): solo per un cumulo (BuildingRules.max_buried > 0).
func _refresh_buried_list(building: Building) -> void:
	for child in _buried_box.get_children():
		_buried_box.remove_child(child)
		child.queue_free()
	var rules: BuildingRules = building.rules if building != null else null
	_buried_box.visible = rules != null and rules.max_buried > 0
	if not _buried_box.visible:
		return
	_buried_box.add_child(_build_buried_label(
		tr("building_info_buried").format({"count": building.buried.size(), "max": rules.max_buried}), 0
	))
	for entry in building.buried:
		var buried_entry: Dictionary = entry if entry is Dictionary else {}
		_buried_box.add_child(_build_buried_label(tr("building_buried_entry").format({
			"name": String(buried_entry.get("name", "?")), "year": int(buried_entry.get("year", 0)),
		}), BURIED_ROW_INDENT))


func _build_buried_label(text: String, indent: int) -> Control:
	var label := Label.new()
	label.text = text
	label.tooltip_text = text
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.add_theme_font_size_override("font_size", BURIED_FONT_SIZE)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if indent <= 0:
		return label
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", indent)
	margin.add_child(label)
	return margin


func clear() -> void:
	if _buried_box != null:
		_buried_box.visible = false
	if _toolkit_box != null:
		_toolkit_box.visible = false
	if _sacredness_box != null:
		_sacredness_box.visible = false
	visible = false
	_end_influence_preview()
	_current_building = null
	show_ground_pile([])


# Contenuto del mucchio a terra nella stessa microcella dell'edificio (2026-09-26, ground drop), una riga per
# risorsa già formattata da GameScene; lista vuota = nessun mucchio, sezione nascosta. Chiamata dopo
# show_building, allo stesso modo in cui il pannello del mucchio mostra le risorse naturali della microcella.
func show_ground_pile(lines: Array[String]) -> void:
	for child in ground_pile_container.get_children():
		child.queue_free()
	ground_pile_caption.visible = not lines.is_empty()
	ground_pile_container.visible = not lines.is_empty()
	ground_pile_caption.text = tr("building_ground_pile_caption")
	for line in lines:
		var label := Label.new()
		label.text = line
		label.add_theme_font_size_override("font_size", 10)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ground_pile_container.add_child(label)


# Fase di lavorazione ATTIVA (2026-09-14, richiesta utente — ESTRATTA da _refresh_construction_
# progress: ora serve anche alla logica dell'alert materiale sotto, un solo punto che decide "in che
# fase siamo" invece di due copie della stessa logica) — "" = edificio completo/nessuna fase attiva.
# Legge tre flag già esistenti su Building (nessun nuovo "stato di fase" introdotto): site_setup_
# complete (SetupSiteAction, vedi Building.gd) -> construction_progress["space_reserved"] (settato
# UNA SOLA VOLTA da ClearAction.on_complete, riusato qui come "Clear è concluso" — STESSA chiave già
# usata per l'idempotenza della riserva di spazio, non una nuova) -> building.is_complete
# (BuildAction.on_complete). Le fasi non ancora raggiunte restano implicitamente "non attive" per
# costruzione (l'ordine dei tre `if` sotto le prova in sequenza, la prima non ancora conclusa vince).
func _resolve_active_construction_phase(building: Building) -> String:
	if building.is_complete:
		return ""
	if not building.site_setup_complete:
		return "setup_site"
	if not bool(building.construction_progress.get("space_reserved", false)):
		return "clear_site"
	return "build"


# Barra di avanzamento della fase di lavorazione CORRENTE (2026-09-14, richiesta utente — "75% di
# setup site, o 33% di build, o 19% di clear site") — nascosta del tutto per un edificio già
# completo, stesso principio "nessun elemento fuorviante" già seguito da StorageGrid/ResidentsGrid
# per una capacità assente.
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
func _has_live_plants_on_site(building: Building) -> bool:
	var world: World = GameSettings.active_world
	if world == null:
		return false
	return BuildingSiteClearingService.has_woody_vegetation(
		world.get_cell_state_at(building.macro_x, building.macro_y), Vector2i(building.micro_x, building.micro_y)
	)


func _refresh_construction_progress(building: Building) -> void:
	var phase := _resolve_active_construction_phase(building)
	if phase == "":
		construction_phase_label.visible = false
		construction_progress_bar_margin.visible = false
		return

	var phase_name_key: String
	var progress_days: float
	var duration_days: float
	match phase:
		"setup_site":
			phase_name_key = "building_construction_phase_setup_site"
			progress_days = float(building.construction_progress.get("site_setup_days_done", 0.0))
			duration_days = SetupSiteAction.DURATION_DAYS
		"clear_site":
			phase_name_key = "building_construction_phase_clear_site"
			progress_days = float(building.construction_progress.get("clear_days_done", 0.0))
			duration_days = float(building.construction_progress.get("clear_duration_days", 0.0))
		_:
			phase_name_key = "building_construction_phase_build"
			progress_days = float(building.construction_progress.get("labor_accumulated", 0.0))
			duration_days = float(building.rules.required_labor) if building.rules != null else 0.0

	var percent: float = (clampf(progress_days / duration_days, 0.0, 1.0) * 100.0) if duration_days > 0.0 else 100.0
	construction_phase_label.visible = true
	construction_progress_bar_margin.visible = true
	construction_phase_label.text = tr("building_construction_phase_label").format({
		"phase": tr(phase_name_key),
		"percent": int(round(percent)),
	})
	# Pulizia ferma per piante vive nel lotto (2026-10-04, ClearAction.has_live_plants): a capo nella stessa etichetta
	# (autowrap), il pannello non si allarga.
	if phase == "clear_site" and _has_live_plants_on_site(building):
		construction_phase_label.text += "\n" + tr("build_blocked_cut_trees_first")
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


# Riga di un ordine (2026-10-04, ordini separati): icona del prodotto con i pezzi ancora dovuti (percentuale del ciclo
# nel tooltip), nome del pipottino troncato con i puntini (intero nel tooltip) o l'avviso di lavoratore mancante, e la X
# che annulla solo quell'ordine. Il nome si restringe, la riga non allarga mai il pannello.
var _production_orders_box: VBoxContainer = null


# `is_full` (2026-10-09): edificio con già production_concurrent_orders ordini in lavorazione — "Assegna" spento con il
# motivo nel tooltip, invece di aprire il mirino e poi rifiutare.
func _build_production_order_row(building: Building, order: Dictionary, is_full: bool = false) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var recipe := String(order["recipe"])
	var units := int(order["units"])
	var chip := _build_missing_material_chip(recipe, units)
	chip.tooltip_text = tr("building_production_status_item_tooltip").format({
		"resource": IconRegistry.get_resource_display_name(recipe), "quantity": units, "percent": int(order["percent"]),
	})
	row.add_child(chip)
	var worker_name := String(order["worker_name"])
	var name_label := Label.new()
	name_label.text = worker_name if worker_name != "" else tr("building_assigned_worker_missing")
	name_label.tooltip_text = name_label.text
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)
	var order_key := String(order["key"])
	# Ordine senza lavoratore (2026-10-04): pulsante "Assegna", piccolo e a larghezza fissa del testo; il nome accanto si
	# restringe, la riga non allarga il pannello.
	if worker_name == "":
		var assign_button := Button.new()
		assign_button.text = tr("building_assign_production_worker_button")
		assign_button.tooltip_text = tr("building_assign_production_worker_tooltip")
		if is_full:
			assign_button.disabled = true
			assign_button.tooltip_text = tr("building_assign_production_worker_busy")
		assign_button.focus_mode = Control.FOCUS_NONE
		assign_button.add_theme_font_size_override("font_size", 10)
		assign_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		assign_button.pressed.connect(func(): production_order_assign_requested.emit(building, order_key))
		row.add_child(assign_button)
	# Stessa X rossa della riga di stato (copia di production_cancel_button, stesso stile; flag 0 = senza i suoi
	# collegamenti, così non annulla tutto il lavoro dell'edificio).
	var cancel_button := production_cancel_button.duplicate(0) as Button
	cancel_button.visible = true
	cancel_button.tooltip_text = tr("building_cancel_production_order_tooltip")
	cancel_button.pressed.connect(func(): production_order_cancel_requested.emit(building, order_key))
	row.add_child(cancel_button)
	return row


# Stato della produzione in corso (2026-09-27, richiesta utente — sezione Produzione della workstation):
#   - "In produzione:" con un'icona per ricetta con una Produce Task che ci lavora (pezzi ancora dovuti, percentuale
#     del ciclo nel tooltip) o "nulla", e la X di annullo se qualcuno ci lavora (stessa azione di work_cancel_requested);
#   - "Lavoratore assegnato: …" (chi ha una Produce Task qui, attiva o in coda) o "mancante";
#   - "Per questa produzione serve:" con le icone e le quantità mancanti delle ricette al lavoro, combustibile compreso
#     (ProductionService.get_missing_inputs_for_recipes/get_missing_fuel_for_recipes).
# Tutto nascosto per un edificio che non è una workstation completa.
func _refresh_production_status(
	building: Building, is_active_workstation: bool, production_orders: Array[Dictionary], working_recipes: Array[String]
) -> void:
	for child in production_status_items.get_children():
		child.queue_free()
	for child in production_needs_grid.get_children():
		child.queue_free()
	for child in _production_orders_box.get_children():
		_production_orders_box.remove_child(child)
		child.queue_free()
	production_status_row.visible = is_active_workstation
	_production_orders_box.visible = is_active_workstation and not production_orders.is_empty()
	# Ordini separati (2026-10-04): il lavoratore è sulla riga di ciascun ordine; la riga unica e la X comune spariscono.
	assigned_worker_label.visible = false
	production_cancel_button.visible = false
	if not is_active_workstation:
		production_needs_caption.visible = false
		production_needs_grid.visible = false
		return
	production_status_caption.text = tr("building_production_status_caption")
	if production_orders.is_empty():
		var none_label := Label.new()
		none_label.text = tr("building_production_status_none")
		none_label.add_theme_font_size_override("font_size", 10)
		production_status_items.add_child(none_label)
	# "Assegna" spento con l'edificio al completo (2026-10-09): ordini con un lavoratore = production_concurrent_orders.
	var working_count := 0
	for order in production_orders:
		if String(order["worker_name"]) != "":
			working_count += 1
	var is_full := ProductionService.has_max_concurrent_orders(building, working_count)
	for order in production_orders:
		_production_orders_box.add_child(_build_production_order_row(building, order, is_full))
	# Disponibili/richiesti per l'ordine intero (2026-09-29, richiesta utente — prima solo il mancante): ogni input delle
	# ricette in lavorazione (input × cicli ancora dovuti, disponibile = deposito + buffer, get_input_available) e il
	# combustibile, anche quando sono già coperti — la sezione resta visibile finché c'è una produzione in lavorazione
	# con materiali richiesti.
	var required_inputs: Dictionary = {}
	var reserved_inputs: Dictionary = {}
	var required_fuel := 0.0
	for recipe_name in working_recipes:
		var recipe_rules := CaloricCalculator.get_caloric_source_rules(recipe_name)
		if recipe_rules == null:
			continue
		var cycles := ProductionService.get_cycles_due(building, recipe_name)
		required_fuel += ProductionService.get_required_fuel(building, recipe_name) * cycles
		for input_name in recipe_rules.recipe_inputs.keys():
			var required: int = int(recipe_rules.recipe_inputs[input_name]) * cycles
			if required > 0:
				required_inputs[String(input_name)] = int(required_inputs.get(String(input_name), 0)) + required
				reserved_inputs[input_name] = int(reserved_inputs.get(input_name, 0)) + required
	var has_needs: bool = not required_inputs.is_empty() or required_fuel > 0.0
	production_needs_caption.visible = has_needs
	production_needs_grid.visible = has_needs
	if not has_needs:
		return
	production_needs_caption.text = tr("building_production_materials_caption")
	for resource_name in required_inputs.keys():
		var required: int = int(required_inputs[resource_name])
		var available: int = mini(ProductionService.get_input_available(building, resource_name), required)
		production_needs_grid.add_child(_build_missing_material_chip(resource_name, available, "%d/%d" % [available, required]))
	if required_fuel > 0.0:
		var available_fuel: float = minf(ProductionService.get_available_fuel(building, reserved_inputs), required_fuel)
		production_needs_grid.add_child(_build_fuel_chip(
			maxf(required_fuel - available_fuel, 0.0), "%s/%s" % [_format_fuel(available_fuel), _format_fuel(required_fuel)]
		))


# Chip del combustibile mancante (2026-09-27): "🔥" con il valore mancante; nel tooltip il valore e le risorse che
# fanno da combustibile (fuel_value > 0).
const FUEL_CHIP_COLOR := Color(0.55, 0.3, 0.12, 1.0)

# `amount_text` (2026-09-29): testo del chip, es. "3/10" (disponibile/richiesto); "" = il solo mancante, come prima.
# Il tooltip riporta sempre il mancante.
func _build_fuel_chip(missing_fuel: float, amount_text: String = "") -> Control:
	var shown_text: String = amount_text if amount_text != "" else _format_fuel(missing_fuel)
	var box := ColorRect.new()
	box.custom_minimum_size = Vector2(maxf(MISSING_MATERIAL_CHIP_SIZE, 6.0 * shown_text.length()), MISSING_MATERIAL_CHIP_SIZE)
	box.color = FUEL_CHIP_COLOR
	var fuel_names: Array[String] = []
	for resource_name in CaloricCalculator.list_secondary_resource_names():
		if ProductionService.get_fuel_value(resource_name) > 0.0:
			fuel_names.append(IconRegistry.get_resource_display_name(resource_name))
	box.tooltip_text = tr("building_awaiting_fuel_production_label").format({
		"amount": "%.1f" % missing_fuel,
		"fuels": ", ".join(fuel_names),
	})
	var icon_label := Label.new()
	icon_label.text = "🔥"
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.anchor_right = 1.0
	icon_label.anchor_bottom = 1.0
	box.add_child(icon_label)
	var amount_label := Label.new()
	amount_label.text = shown_text
	amount_label.add_theme_font_size_override("font_size", 8)
	amount_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	amount_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	amount_label.add_theme_constant_override("shadow_offset_x", 1)
	amount_label.add_theme_constant_override("shadow_offset_y", 1)
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	amount_label.anchor_right = 1.0
	amount_label.anchor_bottom = 1.0
	box.add_child(amount_label)
	return box


# "Produzione sospesa: Corda di fibre, 40% completata" (2026-09-24, richiesta utente) — una riga per
# ogni record senza Task che ci lavori; percentuale = lavoro del ciclo corrente
# (ProductionService.get_cycle_progress). Nascosta se non c'è nulla di sospeso.
# Valore combustibile a una cifra decimale, senza ".0" finale (stesso formato di prima nel chip).
static func _format_fuel(value: float) -> String:
	return ("%.1f" % value).trim_suffix(".0")


func _refresh_suspended_production(building: Building, suspended_recipes: Array[String]) -> void:
	suspended_production_label.visible = building.is_complete and not suspended_recipes.is_empty()
	if not suspended_production_label.visible:
		return
	var lines: Array[String] = []
	for recipe_name in suspended_recipes:
		lines.append(tr("building_production_suspended_label").format({
			"resource": IconRegistry.get_resource_display_name(recipe_name),
			"percent": int(round(ProductionService.get_suspended_progress(building, recipe_name) * 100.0)),
		}))
	suspended_production_label.text = "\n".join(lines)


# "Materiali consegnati" (2026-09-24, richiesta utente) — SOLO per una workstation senza storage
# (storage_slot_count <= 0): lì StorageGrid è nascosta e il materiale consegnato per le ricette
# (input e combustibile, anche di produzioni sospese) non comparirebbe altrimenti. Una chip per
# risorsa di stored_resources, stesso stile del buffer di uscita. Nascosta se vuota; per gli edifici
# CON storage quel contenuto è già nella StorageGrid.
# Cantiere (2026-09-27, richiesta utente): per un edificio non completo, con o senza storage, la stessa sezione
# mostra il materiale da costruzione consegnato (caption "Materiale consegnato") — la StorageGrid resta nascosta
# finché l'edificio non è completo, vedi _refresh_storage_grid.
func _refresh_delivered_materials(building: Building) -> void:
	for child in delivered_materials_grid.get_children():
		child.queue_free()
	var has_storage: bool = building.rules != null and building.rules.storage_slot_count > 0
	var is_workstation: bool = building.rules != null and building.rules.is_workstation
	var entries: Dictionary = {}
	for resource_name in building.stored_resources.keys():
		var quantity: int = int(building.stored_resources[resource_name].get("quantity", 0))
		if quantity > 0:
			entries[String(resource_name)] = quantity
	var is_site: bool = not building.is_complete
	# Cantiere (2026-09-29, richiesta utente): sempre, finché la fase non è completa, consegnato/richiesto per ogni
	# materiale della fase in corso (es. "11/100"), non solo quanto consegnato — anche durante i giri di rifornimento,
	# quando il cantiere non è "in attesa". Il messaggio arancione resta solo per l'attesa vera (show_building).
	if is_site:
		var requirements := _resolve_site_phase_requirements(building)
		delivered_materials_caption.visible = not requirements.is_empty()
		delivered_materials_grid.visible = not requirements.is_empty()
		if requirements.is_empty():
			return
		delivered_materials_caption.text = tr("building_site_materials_progress_caption")
		for resource_name in requirements.keys():
			var required: int = int(requirements[resource_name])
			var delivered: int = mini(int(entries.get(resource_name, 0)), required)
			# Materiale completo (2026-10-02, richiesta utente): numero in verde.
			var quantity_color: Color = MATERIAL_COMPLETE_COLOR if delivered >= required else Color(1, 1, 1, 1)
			delivered_materials_grid.add_child(
				_build_missing_material_chip(resource_name, delivered, "%d/%d" % [delivered, required], quantity_color)
			)
		return
	var show_section: bool = (is_workstation and not has_storage) and not entries.is_empty()
	delivered_materials_caption.visible = show_section
	delivered_materials_grid.visible = show_section
	if not show_section:
		return
	delivered_materials_caption.text = tr("building_site_delivered_materials_caption" if is_site else "building_delivered_materials_caption")
	for resource_name in entries.keys():
		delivered_materials_grid.add_child(_build_missing_material_chip(resource_name, int(entries[resource_name])))


# Materiali richiesti dalla fase in corso del cantiere: setup → il materiale di allestimento; sgombero e costruzione →
# required_materials (consegnabili già durante lo sgombero). {nome: quantità richiesta}, vuoto se nulla è richiesto.
func _resolve_site_phase_requirements(building: Building) -> Dictionary:
	var requirements: Dictionary = {}
	if building.rules == null:
		return requirements
	if _resolve_active_construction_phase(building) == "setup_site":
		var setup_required: int = building.rules.setup_site_material_per_cell * building.rules.required_space
		if building.rules.setup_site_material_name != "" and setup_required > 0:
			requirements[building.rules.setup_site_material_name] = setup_required
		return requirements
	for resource_name in building.rules.required_materials.keys():
		var required: int = int(building.rules.required_materials[resource_name])
		if required > 0:
			requirements[String(resource_name)] = required
	return requirements


# Chip singola: STESSO schema a 3 livelli (icona disegnata/emoji/iniziale) + sfondo colorato per
# risorsa + numero in basso a destra già usato da _build_storage_slot sopra — coerenza visiva tra
# "cosa manca" e "cosa c'è già in magazzino" invece di inventare un terzo stile. Più piccola dello
# slot storage (MISSING_MATERIAL_CHIP_SIZE < STORAGE_SLOT_SIZE): qui è un'indicazione secondaria,
# non la griglia principale del pannello. Nessuna barra di riempimento (non ha senso per una
# quantità mancante, che non ha una "capacità").
const MISSING_MATERIAL_CHIP_SIZE: float = 24.0

# `quantity_text` (2026-09-29): testo alternativo alla quantità, es. "11/100" (consegnato/richiesto) — il chip si
# allarga per contenerlo. "" = la sola quantità, come sempre. `quantity_color` (2026-10-02): colore del numero.
const MATERIAL_COMPLETE_COLOR := Color(0.45, 0.95, 0.45, 1.0)

func _build_missing_material_chip(
	resource_name: String, quantity: int, quantity_text: String = "", quantity_color: Color = Color(1, 1, 1, 1)
) -> Control:
	var box := ColorRect.new()
	var shown_text: String = quantity_text if quantity_text != "" else str(quantity)
	box.custom_minimum_size = Vector2(maxf(MISSING_MATERIAL_CHIP_SIZE, 6.0 * shown_text.length()), MISSING_MATERIAL_CHIP_SIZE)
	box.color = IconRegistry.get_resource_color(resource_name)
	# "%s (%s)" — STESSO formato già in uso in OptionChoiceDialog.gd per le voci dell'OptionButton,
	# non una nuova convenzione per il solo tooltip di questa chip.
	box.tooltip_text = "%s (%s)" % [IconRegistry.get_resource_display_name(resource_name), shown_text]

	var icon_node: Control = IconRegistry.get_resource_icon_node(resource_name)
	if icon_node != null:
		box.add_child(icon_node)
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

	var quantity_label := Label.new()
	quantity_label.text = shown_text
	quantity_label.add_theme_font_size_override("font_size", 8)
	quantity_label.add_theme_color_override("font_color", quantity_color)
	quantity_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	quantity_label.add_theme_constant_override("shadow_offset_x", 1)
	quantity_label.add_theme_constant_override("shadow_offset_y", 1)
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	quantity_label.anchor_right = 1.0
	quantity_label.anchor_bottom = 1.0
	box.add_child(quantity_label)

	return box


# Griglia delle ricette (2026-09-27, richiesta utente — sostituisce i bottoni "Produci …" e il campo Quantità): una
# icona per risorsa producibile presso questo edificio (ProductionService.get_producible_resources), RECIPE_GRID_COLUMNS
# per riga. Clic sinistro +1, destro −1 (mai sotto 0, mai sopra ProductionService.get_max_order_quantity); la quantità
# si legge sull'icona. Una ricetta alla volta: un ordine (Produce Task) contiene una sola ricetta, quindi dare +1 a
# un'altra ricetta azzera la precedente. Ogni cambio emette production_order_changed: GameScene apre (o aggiorna) la
# scelta del lavoratore con quantity > 0, la chiude con 0. Sotto la griglia la spunta "Consegna al magazzino".
#
# Icona spenta (2026-09-24, stesse regole dei vecchi bottoni) con il motivo nel tooltip: postazione già impegnata
# (Produce Task assegnate arrivate a ProductionService.get_max_concurrent_orders) e/o buffer di uscita senza posto per un
# ciclo di QUESTA ricetta. Il tooltip di ogni icona ha nome, ingredienti, combustibile, lavoro e attrezzi richiesti.
const RECIPE_GRID_COLUMNS: int = 4
const RECIPE_ICON_SIZE: float = 32.0
const RECIPE_SELECTED_BORDER_COLOR := Color(1.0, 0.85, 0.2, 1.0)

func _refresh_production_recipes(building: Building, production_claimant_names: Array[String]) -> void:
	for child in production_recipes_container.get_children():
		child.queue_free()
	_last_production_claimant_names = production_claimant_names
	var producible := ProductionService.get_producible_resources(building)
	production_separator.visible = not producible.is_empty()
	production_recipes_caption.visible = not producible.is_empty()
	production_recipes_container.visible = not producible.is_empty()
	production_recipes_caption.text = tr("building_production_recipes_caption")
	if producible.is_empty():
		return

	if _order_quantity_building_id != building.id:
		_order_quantity_building_id = building.id
		_order_recipe = ""
		_order_quantity = 0
		_order_deliver = UserOptions.production_delivery_default
		_order_keep_for_building = false
	var max_quantity := ProductionService.get_max_order_quantity(building)
	if not producible.has(_order_recipe):
		_order_recipe = ""
		_order_quantity = 0
	_order_quantity = clampi(_order_quantity, 0, max_quantity)

	var grid := GridContainer.new()
	grid.columns = RECIPE_GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	production_recipes_container.add_child(grid)
	var is_busy := not _production_queue_mode and ProductionService.has_max_concurrent_orders(building, production_claimant_names.size())
	for resource_name in producible:
		var disabled_reasons: Array[String] = []
		if is_busy:
			# Un nome per ordine (2026-10-04): lo stesso pipottino con due ordini compare una volta.
			var busy_names: Array[String] = []
			for claimant_name in production_claimant_names:
				if not busy_names.has(claimant_name):
					busy_names.append(claimant_name)
			disabled_reasons.append(tr("produce_recipe_disabled_busy").format({"workers": ", ".join(busy_names)}))
		# Buffer di uscita pieno (2026-09-23, richiesta utente): nessuna nuova assegnazione finché il
		# prodotto non viene ritirato.
		if not ProductionService.has_output_room(building, resource_name):
			disabled_reasons.append(tr("produce_recipe_disabled_output_full"))
		# Coda dell'edificio piena (2026-10-09, solo con l'idea): production_max_orders ordini in tutto. Resta accesa la
		# ricetta dell'ordine in preparazione, i cui clic ne cambiano la quantità senza crearne un altro.
		if _production_queue_mode and ProductionService.has_max_orders(building) \
				and not (resource_name == _order_recipe and _order_quantity > 0):
			disabled_reasons.append(tr("produce_recipe_disabled_queue_full"))
		var quantity: int = _order_quantity if resource_name == _order_recipe else 0
		grid.add_child(_build_recipe_icon(building, resource_name, quantity, max_quantity, disabled_reasons))

	var deliver_check_box := CheckBox.new()
	deliver_check_box.text = tr("produce_deliver_checkbox")
	deliver_check_box.add_theme_font_size_override("font_size", 10)
	deliver_check_box.button_pressed = _order_deliver
	var keep_check_box := CheckBox.new()
	deliver_check_box.toggled.connect(func(pressed: bool) -> void:
		_order_deliver = pressed
		# Spunte esclusive (2026-10-04): consegnare al magazzino toglie "Tieni per l'edificio".
		if pressed and _order_keep_for_building:
			_order_keep_for_building = false
			keep_check_box.set_pressed_no_signal(false)
		# Ordine già in preparazione: la scelta del lavoratore riceve la spunta aggiornata.
		if _order_quantity > 0 and _current_building != null:
			production_order_changed.emit(_current_building, _order_recipe, _order_quantity, _order_deliver, _order_keep_for_building)
	)
	production_recipes_container.add_child(deliver_check_box)
	# "Tieni per l'edificio" (2026-10-04, Attrezzeria): i pezzi finiti che sono attrezzi vanno nell'Attrezzeria se c'è
	# posto. Esclusiva con "Consegna al magazzino". Dal 2026-10-08 compare solo se la ricetta scelta fa un attrezzo E
	# l'Attrezzeria ha posto per lui (BuildingToolkitService.can_add: tipo presente con pezzi liberi, o tipo libero) e, dal
	# 2026-10-08, solo se l'attrezzo serve a una ricetta dell'edificio (is_accepted_tool, controllo dentro can_add);
	# nascosta = spenta, "Porta al deposito" resta com'è.
	keep_check_box.visible = BuildingToolkitService.can_add(building, _order_recipe)
	keep_check_box.text = tr("produce_keep_for_building_checkbox")
	keep_check_box.tooltip_text = tr("produce_keep_for_building_tooltip")
	keep_check_box.add_theme_font_size_override("font_size", 10)
	if not keep_check_box.visible:
		_order_keep_for_building = false
	keep_check_box.button_pressed = _order_keep_for_building
	keep_check_box.toggled.connect(func(pressed: bool) -> void:
		_order_keep_for_building = pressed
		if pressed and _order_deliver:
			_order_deliver = false
			deliver_check_box.set_pressed_no_signal(false)
		if _order_quantity > 0 and _current_building != null:
			production_order_changed.emit(_current_building, _order_recipe, _order_quantity, _order_deliver, _order_keep_for_building)
		_update_order_output_warning(building)
	)
	production_recipes_container.add_child(keep_check_box)
	# Avviso dell'ordine (2026-10-08): va a capo, il pannello non si allarga.
	_order_output_warning_label = Label.new()
	_order_output_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_order_output_warning_label.custom_minimum_size.x = 0.0
	_order_output_warning_label.add_theme_font_size_override("font_size", 10)
	_order_output_warning_label.add_theme_color_override("font_color", ORDER_OUTPUT_WARNING_COLOR)
	production_recipes_container.add_child(_order_output_warning_label)
	deliver_check_box.toggled.connect(func(_pressed: bool) -> void: _update_order_output_warning(building))
	_update_order_output_warning(building)


# Avviso "Uscita piena: si fermerà dopo N" (2026-10-08, richiesta utente): con "Porta al deposito" spenta e i pezzi
# ordinati oltre i posti liberi nei Prodotti finiti (più, con "Tieni per l'edificio" accesa, i posti liberi
# nell'Attrezzeria per quell'attrezzo). Solo un avviso: l'ordine si può dare lo stesso. Con "Porta al deposito" accesa il
# pipottino porta via i pezzi a metà ordine (ProduceAction, consegna a metà ordine): nessun avviso.
func _update_order_output_warning(building: Building) -> void:
	if _order_output_warning_label == null or not is_instance_valid(_order_output_warning_label):
		return
	var should_warn := false
	var free_places := 0
	if building != null and _order_recipe != "" and _order_quantity > 0 and not _order_deliver:
		free_places = maxi(ProductionService.get_output_capacity(building) - ProductionService.get_output_used(building), 0)
		if _order_keep_for_building:
			free_places += BuildingToolkitService.get_free_units_for(building, _order_recipe)
		should_warn = _order_quantity > free_places
	_order_output_warning_label.visible = should_warn
	_order_output_warning_label.text = tr("produce_output_full_warning").format({"count": free_places}) if should_warn else ""


# Ordini in coda (2026-10-09): chiamata da GameScene prima di ogni show_building. `enabled` = idea dell'assegnazione
# completata; con lei la ricetta e la quantità della griglia sono quelle dell'ordine in coda creato da questo pannello
# per `building_id` (`recipe` "" / `units` 0 = nessuno, o già preso da un pipottino). Cambiando edificio le spunte
# ripartono dal default, come senza l'idea.
func set_production_queue_mode(enabled: bool, building_id: int = -1, recipe: String = "", units: int = 0) -> void:
	_production_queue_mode = enabled
	if not enabled:
		return
	if _order_quantity_building_id != building_id:
		_order_deliver = UserOptions.production_delivery_default
		_order_keep_for_building = false
	_order_quantity_building_id = building_id
	_order_recipe = recipe if units > 0 else ""
	_order_quantity = maxi(units, 0) if recipe != "" else 0


# Suggerimento "come assegnarlo" (2026-10-09): `queue_enabled` = idea dell'assegnazione completata; `locked` = il lavoro
# dell'edificio (cantiere, miglioramento o demolizione) è bloccato in coda. Chiamata da GameScene prima di show_building.
func set_assign_hint_state(queue_enabled: bool, locked: bool) -> void:
	_assign_hint_queue_enabled = queue_enabled
	_assign_hint_locked = locked


# Riporta l'ordine in preparazione a 0 (2026-09-27): chiamata da GameScene dopo l'assegnazione o quando si esce dalla
# scelta del lavoratore senza sceglierne uno. Ricostruisce la griglia se il pannello mostra un edificio.
func reset_production_order() -> void:
	_order_recipe = ""
	_order_quantity = 0
	if _current_building != null and visible:
		_refresh_production_recipes(_current_building, _last_production_claimant_names)


# Icona di una ricetta nella griglia: stesso stile delle altre chip (icona della risorsa su fondo colorato), la
# quantità ordinata in basso a destra (solo se > 0) e un bordo evidenziato sulla ricetta dell'ordine in preparazione.
func _build_recipe_icon(
	building: Building, resource_name: String, quantity: int, max_quantity: int, disabled_reasons: Array[String]
) -> Control:
	var box := _build_missing_material_chip(resource_name, quantity)
	box.custom_minimum_size = Vector2(RECIPE_ICON_SIZE, RECIPE_ICON_SIZE)
	# La chip mostra sempre il numero: qui solo se l'icona fa parte dell'ordine.
	for child in box.get_children():
		if child is Label and (child as Label).text == str(quantity) and (child as Label).horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
			(child as Label).visible = quantity > 0
			(child as Label).add_theme_font_size_override("font_size", 11)
	if quantity > 0:
		var border := ReferenceRect.new()
		border.border_color = RECIPE_SELECTED_BORDER_COLOR
		border.border_width = 2.0
		border.editor_only = false
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		border.anchor_right = 1.0
		border.anchor_bottom = 1.0
		box.add_child(border)
	var tooltip_lines: Array[String] = [_describe_recipe(building, resource_name)]
	if not disabled_reasons.is_empty():
		tooltip_lines.append("\n".join(disabled_reasons))
	box.tooltip_text = "\n".join(tooltip_lines)
	if not disabled_reasons.is_empty():
		box.modulate = Color(1, 1, 1, 0.4)
		return box
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	box.gui_input.connect(func(event: InputEvent) -> void:
		if not (event is InputEventMouseButton) or not event.pressed:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			_change_production_order(building, resource_name, 1, max_quantity)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			accept_event()
			_change_production_order(building, resource_name, -1, max_quantity)
	)
	return box


# +1/−1 sull'ordine: un'altra ricetta azzera la precedente (un ordine contiene una sola ricetta). Emette
# production_order_changed e ricostruisce la griglia.
func _change_production_order(building: Building, resource_name: String, delta: int, max_quantity: int) -> void:
	if resource_name != _order_recipe:
		if delta < 0:
			return
		_order_recipe = resource_name
		_order_quantity = 0
	_order_quantity = clampi(_order_quantity + delta, 0, max_quantity)
	if _order_quantity == 0:
		_order_recipe = ""
	# "Tieni per l'edificio" vale solo per un attrezzo con posto nell'Attrezzeria (2026-10-08): spenta prima di avvisare.
	if not BuildingToolkitService.can_add(building, _order_recipe):
		_order_keep_for_building = false
	production_order_changed.emit(building, resource_name, _order_quantity, _order_deliver, _order_keep_for_building)
	_refresh_production_recipes(building, _last_production_claimant_names)


# Tooltip di una ricetta: nome, ingredienti con quantità, combustibile (con il moltiplicatore della postazione), lavoro
# (idem) e attrezzi richiesti.
func _describe_recipe(building: Building, resource_name: String) -> String:
	var recipe_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	var lines: Array[String] = [IconRegistry.get_resource_display_name(resource_name)]
	if recipe_rules == null:
		return lines[0]
	var inputs: Array[String] = []
	for input_name in recipe_rules.recipe_inputs.keys():
		inputs.append("%d %s" % [int(recipe_rules.recipe_inputs[input_name]), IconRegistry.get_resource_display_name(String(input_name))])
	lines.append(tr("recipe_tooltip_ingredients").format({"items": ", ".join(inputs) if not inputs.is_empty() else "-"}))
	var fuel := ProductionService.get_required_fuel(building, resource_name)
	if fuel > 0.0:
		lines.append(tr("recipe_tooltip_fuel").format({"amount": ("%.1f" % fuel).trim_suffix(".0")}))
	lines.append(tr("recipe_tooltip_labor").format({"labor": int(round(ProductionService.get_required_labor(building, resource_name)))}))
	if not recipe_rules.recipe_required_tool_categories.is_empty():
		var tools: Array[String] = []
		for category in recipe_rules.recipe_required_tool_categories:
			tools.append(tr("tool_category_" + String(TaskTypes.ToolCategory.keys()[category]).to_lower()))
		lines.append(tr("recipe_tooltip_tools").format({"tools": ", ".join(tools)}))
	return "\n".join(lines)


# Buffer di uscita della produzione (2026-09-23, richiesta utente): "Prodotti: {used}/{capacity}",
# una chip per risorsa (stesso stile delle chip "materiale mancante") e l'avviso di buffer pieno
# quando blocca la produzione in corso (ProductionService.is_output_blocking). Tutto nascosto per un
# edificio senza buffer. Ricostruita da zero ad ogni show_building, come le altre griglie.
# Una riga per ogni voce dello storage in avanzamento automatico, sempre visibile (2026-10-03, essiccatoio): risorsa,
# quantità e giorni mancanti (ProductionService.get_auto_progress_days_left); "nulla" se non c'è niente.
func _refresh_auto_progress(building: Building, show_section: bool) -> void:
	auto_progress_label.visible = show_section
	if not show_section:
		return
	var lines: Array[String] = []
	for resource_name in building.stored_resources.keys():
		var days_left := ProductionService.get_auto_progress_days_left(building, String(resource_name))
		if days_left < 0:
			continue
		var quantity: int = int((building.stored_resources[resource_name] as Dictionary).get("quantity", 0))
		if quantity <= 0:
			continue
		var key := "building_auto_progress_line_ready" if days_left <= 0 else "building_auto_progress_line"
		lines.append(tr(key).format({
			"resource": IconRegistry.get_resource_display_name(String(resource_name)),
			"quantity": quantity,
			"days": days_left,
		}))
	auto_progress_label.text = "\n".join(lines) if not lines.is_empty() else tr("building_auto_progress_none")


func _refresh_output_buffer(building: Building) -> void:
	for child in output_buffer_grid.get_children():
		child.queue_free()
	var capacity := ProductionService.get_output_capacity(building)
	var has_buffer: bool = capacity > 0
	# Titolo e icone solo con almeno un prodotto (2026-10-05, richiesta utente): dove finiscono i prodotti lo dice la riga
	# del blocco Info (building_info_output_*). L'avviso "pieni" resta indipendente.
	var has_products: bool = has_buffer and not building.production_output.is_empty()
	output_buffer_caption.visible = has_products
	output_buffer_grid.visible = has_products
	output_buffer_full_label.visible = has_buffer and ProductionService.is_output_blocking(building)
	if not has_buffer:
		return
	output_buffer_caption.text = tr("building_output_buffer_caption").format({
		"used": ProductionService.get_output_used(building),
		"capacity": capacity,
	})
	for output_name in building.production_output.keys():
		var output_chip := _build_missing_material_chip(String(output_name), int(building.production_output[output_name]))
		_make_toolkit_deposit_target(output_chip, String(output_name), true)
		output_buffer_grid.add_child(output_chip)
	output_buffer_full_label.text = tr("building_output_buffer_full")


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
	# Solo a edificio completo (2026-09-27, richiesta utente): su un cantiere stored_resources contiene il materiale
	# da costruzione consegnato, mostrato come "Materiale consegnato" da _refresh_delivered_materials.
	if slot_count <= 0 or not building.is_complete:
		storage_caption.visible = false
		storage_grid.visible = false
		return

	storage_caption.visible = true
	storage_grid.visible = true
	# Colonne = ceil(sqrt(slot_count)): 3x3 per 9 (deposit_site), 3x2 per 6 (campfire, toolmaker_hut), 2x2 per 4 (hut)
	# — regola generica per qualunque slot_count, nessuna configurazione per tipo. (La riga unica provata il 2026-09-27
	# allargava troppo il pannello: tolta.)
	storage_grid.columns = max(int(ceil(sqrt(float(slot_count)))), 1)

	# Danneggiato (2026-10-10, passo 2): slot effettivi (BuildingStorageService.get_slot_count); quelli oltre che contengono
	# ancora qualcosa restano visibili, segnati come fuori capienza. Colonne sempre dagli slot del tipo: la griglia non
	# cambia forma né si allarga.
	var effective_slots: int = BuildingStorageService.get_slot_count(building)
	var breakdown: Array = BuildingStorageService.get_slot_breakdown(building)
	for i in range(maxi(effective_slots, mini(breakdown.size(), slot_count))):
		var slot_data: Dictionary = breakdown[i] if i < breakdown.size() else {}
		var slot := _build_storage_slot(slot_data)
		if i >= effective_slots:
			_mark_slot_over_capacity(slot)
		storage_grid.add_child(slot)


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
# Slot oltre la capienza effettiva (edificio danneggiato): tinta rossastra e motivo nel tooltip.
func _mark_slot_over_capacity(slot: Control) -> void:
	slot.modulate = STORAGE_SLOT_OVER_CAPACITY_MODULATE
	slot.tooltip_text = ("%s\n%s" % [slot.tooltip_text, tr("storage_slot_over_capacity_tooltip")]) if slot.tooltip_text != "" \
		else tr("storage_slot_over_capacity_tooltip")


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
	# Avanzamento automatico (2026-10-03, essiccazione passo 2): giorni mancanti alla trasformazione.
	if slot_data.has("auto_days_left"):
		box.tooltip_text += "\n" + tr("storage_slot_auto_progress_tooltip").format({"days": int(slot_data["auto_days_left"])})

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

	_make_toolkit_deposit_target(box, resource_name, false)
	return box


# Attrezzeria (2026-10-04): un attrezzo nel magazzino o nei prodotti finiti di un edificio con l'Attrezzeria diventa
# cliccabile (clic sinistro, prima nessuna azione su queste icone): un pezzo passa nell'Attrezzeria. Riga nel tooltip.
func _make_toolkit_deposit_target(box: Control, resource_name: String, from_output: bool) -> void:
	var building := _current_building
	# Solo gli attrezzi che servono alle ricette dell'edificio (2026-10-08, BuildingToolkitService.is_accepted_tool): gli
	# altri (armi, attrezzi che nessuna sua ricetta usa) non diventano cliccabili.
	if not BuildingToolkitService.is_accepted_tool(building, resource_name):
		return
	box.tooltip_text += "\n" + tr("toolkit_click_to_store")
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	box.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			toolkit_deposit_requested.emit(building, resource_name, from_output)
	)


# Tooltip di un'icona dell'Attrezzeria (2026-10-04): "Nome · N pezzi", "In uso: u su max" (il pezzo più consumato),
# "Di scorta: …" per gli altri (il numero e il valore pieno se tutti nuovi, altrimenti gli usi di ciascuno; assente con
# un pezzo solo) e cosa fa il clic. `uses_list`: usi rimasti di ogni pezzo, dal più consumato.
func _toolkit_tooltip(tool_name: String, quantity: int, uses_list: Array[int], max_uses: int) -> String:
	var lines: Array[String] = []
	var display_name := IconRegistry.get_resource_display_name(tool_name)
	lines.append(tr("toolkit_tooltip_count_one" if quantity == 1 else "toolkit_tooltip_count").format({"name": display_name, "count": quantity}))
	if not uses_list.is_empty():
		lines.append(tr("toolkit_tooltip_in_use").format({"uses": uses_list[0], "max": max_uses}))
	if uses_list.size() > 1:
		var spare := uses_list.slice(1)
		var all_new := true
		for uses in spare:
			if int(uses) < max_uses:
				all_new = false
		var spare_text := ""
		if all_new:
			spare_text = tr("toolkit_tooltip_uses_of").format({"uses": max_uses, "max": max_uses})
		else:
			var parts: PackedStringArray = []
			for uses in spare:
				parts.append(tr("toolkit_tooltip_uses_of").format({"uses": int(uses), "max": max_uses}))
			spare_text = ", ".join(parts)
		lines.append(tr("toolkit_tooltip_spare").format({"count": spare.size(), "uses": spare_text}))
	lines.append(tr("toolkit_click_to_return_spare" if quantity > 1 else "toolkit_click_to_return"))
	return "\n".join(lines)


# Barra degli usi in basso sull'icona (2026-10-04, stesso aspetto di quella della cintura in HumanIndividualInfoPanel):
# sfondo scuro e riempimento dal rosso al verde in proporzione a `ratio`.
const TOOLKIT_USES_BAR_HEIGHT_FRACTION := 0.14
const TOOLKIT_USES_BAR_BACKGROUND := Color(0, 0, 0, 0.55)


func _build_uses_bar(ratio: float) -> Control:
	ratio = clampf(ratio, 0.0, 1.0)
	var bar := ColorRect.new()
	bar.color = TOOLKIT_USES_BAR_BACKGROUND
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0 - TOOLKIT_USES_BAR_HEIGHT_FRACTION
	bar.anchor_bottom = 1.0
	var fill := ColorRect.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.anchor_left = 0.0
	fill.anchor_top = 0.0
	fill.anchor_bottom = 1.0
	fill.anchor_right = ratio
	fill.color = Color.RED.lerp(Color.GREEN, ratio)
	bar.add_child(fill)
	return bar


# Sezione "Attrezzeria" (2026-10-04): un'icona per tipo con la quantità e la barra degli usi del pezzo in uso; tooltip
# in _toolkit_tooltip; clic sinistro = il pezzo meno usato torna nel magazzino. Solo su un edificio completo con
# l'Attrezzeria.
func _build_toolkit_box() -> void:
	_toolkit_box = VBoxContainer.new()
	_toolkit_box.visible = false
	_toolkit_caption = Label.new()
	_toolkit_caption.add_theme_font_size_override("font_size", 10)
	_toolkit_caption.clip_text = true
	_toolkit_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_toolkit_box.add_child(_toolkit_caption)
	_toolkit_grid = HFlowContainer.new()
	_toolkit_grid.add_theme_constant_override("h_separation", 4)
	_toolkit_grid.add_theme_constant_override("v_separation", 4)
	_toolkit_box.add_child(_toolkit_grid)


func _refresh_toolkit(building: Building) -> void:
	for child in _toolkit_grid.get_children():
		_toolkit_grid.remove_child(child)
		child.queue_free()
	_toolkit_box.visible = building != null and building.is_complete and BuildingToolkitService.has_toolkit(building)
	if not _toolkit_box.visible:
		return
	var tool_names := BuildingToolkitService.get_tool_names(building)
	_toolkit_caption.text = tr("toolkit_caption").format({
		"used": tool_names.size(), "types": BuildingToolkitService.get_type_capacity(building),
	})
	if tool_names.is_empty():
		var empty_label := Label.new()
		empty_label.text = tr("toolkit_empty")
		empty_label.add_theme_font_size_override("font_size", 10)
		_toolkit_grid.add_child(empty_label)
		return
	for tool_name in tool_names:
		var quantity := BuildingToolkitService.get_quantity(building, tool_name)
		var chip := _build_missing_material_chip(tool_name, quantity)
		var uses_list := BuildingToolkitService.get_remaining_uses_list(building, tool_name)
		var max_uses := ToolInstance.get_max_uses(tool_name)
		chip.tooltip_text = _toolkit_tooltip(tool_name, quantity, uses_list, max_uses)
		# Barra degli usi del pezzo in uso (il più consumato), come in cintura al pipottino.
		if max_uses > 0 and not uses_list.is_empty():
			chip.add_child(_build_uses_bar(float(uses_list[0]) / float(max_uses)))
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var chip_tool := tool_name
		chip.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				accept_event()
				toolkit_withdraw_requested.emit(building, chip_tool)
		)
		_toolkit_grid.add_child(chip)


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
# Chiave tr() del nome di ogni tipo di influenza nella riga "Influenza ricevuta".
const INFLUENCE_TYPE_NAME_KEYS := {
	InfluenceService.InfluenceType.POLITICAL: "influence_type_political",
	InfluenceService.InfluenceType.CULTURAL: "influence_type_cultural",
	InfluenceService.InfluenceType.RELIGIOUS: "influence_type_religious",
}


func _refresh_influence_received(building: Building) -> void:
	var is_house: bool = building.rules != null and building.rules.category == BuildingTypes.Category.RESIDENTIAL \
		and building.is_complete and not building.is_demolished
	influence_received_label.visible = is_house
	if not is_house:
		return
	var names: Array[String] = []
	for influence_type in InfluenceService.get_house_coverage(building.id):
		names.append(tr(String(INFLUENCE_TYPE_NAME_KEYS.get(influence_type, ""))))
	influence_received_label.text = tr("building_influence_received_label").format({
		"types": ", ".join(names) if not names.is_empty() else tr("building_influence_received_none")
	})


func _refresh_residents_grid(building: Building, residents_display_data: Array[Dictionary]) -> void:
	for child in residents_grid.get_children():
		child.queue_free()

	# Posti effettivi (2026-10-10): a metà se la casa è danneggiata; chi è ancora in più fino allo sfratto del giorno resta
	# visibile.
	var max_residents: int = maxi(AssignHouseService.get_max_residents(building), residents_display_data.size()) \
		if building.rules != null and building.rules.max_residents > 0 else 0
	if max_residents <= 0:
		residents_caption.visible = false
		residents_grid.visible = false
		return

	residents_caption.visible = true
	residents_grid.visible = true

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
	# Solo a edificio completo (2026-09-27, richiesta utente): su un cantiere "Svuota tutto" e le categorie
	# accettate non hanno senso (stored_resources contiene solo il materiale da costruzione).
	var has_storage: bool = building.rules != null and building.rules.storage_slot_count > 0 and building.is_complete
	_refresh_accepted_categories_toggles(building, has_storage)

	# Almeno un blocco visibile -> mostra la "chrome" condivisa (separatore/titolo). Oggi has_storage è l'unica
	# condizione, ma scritta così non richiede modifiche quando un secondo blocco esisterà (basterà aggiungerlo
	# all'OR). "Svuota tutto" è nella riga dei comandi a icone dal 2026-10-03 (_refresh_empty_all_button).
	var any_section_visible: bool = has_storage
	settings_separator.visible = any_section_visible
	settings_caption.visible = any_section_visible


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
		# Categorie bloccate (2026-09-27, BuildingRules.categories_locked — campfire): sempre spuntate e
		# disattivate, nessun toggle collegato (BuildingStorageService ignora comunque enabled_categories).
		if building.rules.categories_locked:
			check_box.button_pressed = true
			check_box.disabled = true
			category_toggles_container.add_child(check_box)
			continue
		check_box.button_pressed = not building.restricts_categories or building.enabled_categories.has(category)
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
#
# Filtro attivo (2026-09-28, Building.restricts_categories): il primo deflag attiva il filtro con "tutto tranne questa";
# togliendo l'ultima spunta l'elenco resta vuoto CON il filtro attivo, quindi l'edificio non accetta niente (prima un
# elenco vuoto tornava a voler dire "accetta tutto").
func _on_category_toggled(pressed: bool, category: int, building: Building, categories_to_show: Array) -> void:
	if pressed:
		if building.restricts_categories and not building.enabled_categories.has(category):
			building.enabled_categories.append(category)
	else:
		if not building.restricts_categories:
			building.restricts_categories = true
			building.enabled_categories.clear()
			for shown_category in categories_to_show:
				if shown_category != category:
					building.enabled_categories.append(shown_category)
		else:
			building.enabled_categories.erase(category)

	# Normalizzazione (vedi commento sopra): elenco esplicito che ormai copre di nuovo TUTTO
	# categories_to_show -> filtro spento e elenco vuoto (forma canonica "nessuna restrizione propria").
	if building.restricts_categories:
		var covers_everything := true
		for shown_category in categories_to_show:
			if not building.enabled_categories.has(shown_category):
				covers_everything = false
				break
		if covers_everything:
			building.enabled_categories.clear()
			building.restricts_categories = false

	if _current_building == building:
		_refresh_settings_section(building)
