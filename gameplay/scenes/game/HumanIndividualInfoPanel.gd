class_name HumanIndividualInfoPanel
extends VBoxContainer

# Corpo del pannello individuo dentro GameInfoTabs.selection_content — stesso principio "muto" di
# VegetationInfoPanel (istanziato dinamicamente da GameScene, non pre-cablato in nessun .tscn di
# livello superiore): non conosce GameScene/selezione/HumanRules, riceve solo dati già risolti.
# Label tr()-wrapped (richiesta utente 2026-09-06, insieme a VegetationInfoPanel/
# DeadBodyInfoPanel): solo le chiavi, nessuna riga aggiunta ancora a strings.csv/
# strings.it.translation — pronte per quando le traduzioni arriveranno. Nascosto di default
# (nessuna selezione all'apertura della scena).
#
# name/sex/età/age_band (Passo 1, 2026-09-01) + id/folk id/group id/mother id/father id/partner
# id (richiesta utente, 2026-09-02 — solo consultazione, nessuna interazione). strength resta
# fuori, non ancora richiesto.
#
# stamina_bar (2026-09-04, rinominato da workforce_bar il 2026-09-06 — rename completo Workforce->
# Stamina, richiesta utente, nessuna modifica di comportamento): display-only, nessun consumo
# reale ancora esistente (nessuna classe Action) — max/current arrivano già risolti dal chiamante
# (GameScene, stesso principio di age/age_band sopra: questo pannello non conosce HumanRules/
# HumanCalculator). current oggi coincide sempre col max (nessun campo HumanIndividual.
# current_stamina ancora esistente); il chiamante è già strutturato in modo che, quando quel campo
# arriverà, sostituire quell'UNICA lettura in GameScene basti — questo pannello resta invariato,
# prende solo i due float già risolti.
#
# carry_bar/carried_resource_box (2026-09-08, richiesta utente, capacità di trasporto) — stesso
# principio "muto" di stamina_bar sopra: max_carry_capacity/used_carry_space arrivano già
# risolti dal chiamante (GameScene, che fa il lookup di SecondaryResourceRules.space_per_unit per
# calcolare lo spazio occupato — questo pannello non conosce SecondaryResourceRules/
# CaloricCalculator). La barra si RIEMPIE man mano che si trasporta di più (mostra lo spazio
# OCCUPATO, somma di quantity × space_per_unit di ogni varietà, non quello libero): vuota a zaino vuoto,
# piena a zaino pieno; tooltip occupato/massimo (invertita il 2026-09-20, richiesta utente — prima
# mostrava lo spazio libero e un carico leggero la lasciava quasi piena). Zaino multi-risorsa
# (2026-09-20): fino a HumanIndividual.MAX_CARRIED_VARIETIES (4) riquadri affiancati SOPRA la barra, uno
# per varietà, nell'ordine di inserimento di HumanIndividual.carried_resources; gli slot liberi restano
# grigi. Il riquadro (CarriedResourceBox, un ColorRect quadrato — il primo è in scena, gli altri sono
# duplicati di lui creati in _ready) è un PLACEHOLDER (richiesta
# esplicita dell'utente: "le icone delle risorse non esistono ancora") — colorato
# deterministicamente in base al nome della risorsa trasportata (_placeholder_color_for_resource),
# con l'iniziale maiuscola del nome al centro e la quantità sovrapposta in basso a destra; vuoto/
# grigio e senza testo quando lo slot non ha una varietà.
#
# CarryRow (2026-09-13, richiesta utente — riordino barre: capacità di trasporto in fondo, i tool in
# una riga a sé; RIORGANIZZATA 2026-09-20 per lo zaino multi-risorsa) — CarryRow è ora un VBoxContainer:
# la riga CarriedBoxesRow (HBoxContainer con i riquadri, ciascuno a dimensione fissa via
# custom_minimum_size) SOPRA, poi CarryBar con size_flags_horizontal=EXPAND_FILL. Bastano le size flags
# standard di Godot, nessun bisogno dello scaling proporzionale manuale che serviva quando un riquadro
# condivideva la riga con gli slot della cintura (vedi ToolSlot0 sotto per quel caso, ancora reale).
#
# ToolSlot0 (2026-09-08, richiesta utente; dal 2026-09-27 modello per gli slot generati da
# HumanIndividual.get_tool_slot_count, vedi _ensure_tool_slot_boxes) — quadratini in una riga TUTTA LORO
# (tools_row, un Control puro, non un Container — vedi _layout_tools_row per il perché: serve
# comunque rimpicciolirli TUTTI con lo stesso fattore di scala quando lo spazio non basta, cosa che
# nessun Container standard di Godot fa da solo), separata dalla riga trasporto sopra (2026-09-13,
# richiesta utente — prima condividevano la riga col quadratino trasporto, ora quel riquadro è
# salito sulla riga della barra). Stile diverso apposta dal quadratino trasporto (richiesta
# esplicita): un Panel con cornice visibile (StyleBoxFlat_tool_slot) invece di un ColorRect pieno,
# "T" attenuata (alpha 0.35) come placeholder per uno slot vuoto; uno slot pieno mostra l'attrezzo (vedi
# _update_tool_slots).
#
# Il "🎯 centra" è vissuto qui brevemente (2026-09-04) ma si è spostato di nuovo, stavolta
# nell'header di GameInfoTabs.SelectionTab (Step 3 del piano "centra generalizzato", stessa
# richiesta utente): un bottone condiviso lì funziona per QUALUNQUE cosa sia selezionata
# (individuo, vegetazione, edifici), non solo per l'individuo mostrato da questo pannello — vedi
# GameInfoTabs.center_requested/GameScene._center_camera_on_selection.
#
# NameLabel (Step 6, richiesta utente 2026-09-04): rimossa da qui, sollevata dentro GameInfoTabs.
# title_label — sulla STESSA riga del bottone "🎯" invece che come prima riga di questo pannello
# (richiesta esplicita: il bottone deve leggersi allineato all'inizio delle info). GameScene la
# imposta (game_info_tabs.set_selection_title) subito insieme a questa show_individual, con la
# stessa identica stringa che sarebbe finita qui.
#
# KillButton (Step 9d del piano mortalità, 2026-09-05; bottone TOLTO dal pannello il 2026-09-27, RIMESSO il 2026-10-04
# solo in modalità debug, vedi _build_kill_debug_button) — tasto di DEBUG per velocizzare i test ("Kill (debug)", non una vera meccanica di gioco): emetteva
# kill_requested con l'individuo
# attualmente mostrato (_current_individual, salvato da show_individual — stesso principio di
# HumanPopulationInfoPanel.individual_center_requested, che porta il payload direttamente nel
# segnale invece di far riscandire GameScene per is_selected). GameScene decide se/come agire
# (GameTimeService.kill_individual_now), questo pannello resta "muto" come il resto.
signal kill_requested(individual: HumanIndividual)
# Cintura degli attrezzi (2026-09-25, richiesta utente) — stesso schema di kill_requested: il pannello
# segnala soltanto il click, GameScene chiama HumanIndividual.equip_tool_from_backpack/
# unequip_tool_to_backpack (che fanno tutti i controlli) e poi rinfresca il pannello.
# Click su un riquadro dello zaino (qualunque risorsa: se non è un attrezzo il metodo rifiuta).
signal equip_tool_requested(individual: HumanIndividual, resource_name: String)
# Click su uno slot pieno della cintura.
signal unequip_tool_requested(individual: HumanIndividual, slot_index: int)
# Click sulla X accanto all'attività (2026-09-25): GameScene annulla la Task come il tasto H.
signal cancel_task_requested(individual: HumanIndividual)
# Click DESTRO su uno slot della cintura (2026-09-25, richiesta utente — task di equipaggiamento): slot
# vuoto -> GameScene propone gli attrezzi nei magazzini e crea la Task "prendi attrezzo"; slot pieno ->
# GameScene crea la Task "riponi attrezzo" verso il magazzino più vicino che lo accetta.
signal tool_from_storage_requested(individual: HumanIndividual, slot_index: int)
signal tool_to_storage_requested(individual: HumanIndividual, slot_index: int)

# identity_label RIMOSSA (2026-09-13, richiesta utente — "perché la riga del center è vuota"):
# nome/sesso/età/fascia vivono ORA solo nell'header di GameInfoTabs (title_label, sulla STESSA
# riga del bottone 🎯), impostati da GameScene tramite set_selection_title — mai più duplicati qui
# dentro. Vedi GameScene._update_individual_panel_content per individual_identity_line.
@onready var activity_label: Label = $ActivityRow/ActivityLabel
# Piccola X a destra dell'attività (2026-09-25, richiesta utente): annulla la Task in corso, stessa
# funzione del tasto H (GameScene._stop_selected_individual_task, via cancel_task_requested).
# Visibile solo quando l'individuo ha una Task in corso.
@onready var cancel_task_button: Button = $ActivityRow/CancelTaskButton
# Azioni in coda (2026-09-13, richiesta utente) — sotto activity_label, in corsivo (FontVariation
# con variation_transform di taglio — nessun font italico incluso nel progetto, "corsivo finto"
# via shear, tecnica standard Godot 4: non verificabile visivamente da qui, segnalare se
# l'inclinazione risultasse sbagliata/eccessiva). Nascosta di default — visible solo quando
# individual.task_queue non è vuota, vedi show_individual sotto.
@onready var queued_tasks_label: Label = $QueuedTasksLabel
# VitalsBox/SkillsBox (2026-09-13, richiesta utente — "riquadro dedicato" con sfondo leggermente
# più chiaro del blu della sidebar, STESSO colore per entrambi i riquadri pur restando separati)
# — PanelContainer con StyleBoxFlat_section_box condiviso (stesso SubResource riusato in entrambi
# i .tscn, non due StyleBox identici duplicati). I path di ogni Label/ProgressBar già esistente
# sono scesi di 3 livelli (Box/BoxMargin/BoxContent) ma il loro comportamento in show_individual
# resta identico, nessuna logica cambiata.
@onready var vitals_section_label: Label = $VitalsBox/VitalsBoxMargin/VitalsBoxContent/VitalsSectionLabel
@onready var stamina_label: Label = $VitalsBox/VitalsBoxMargin/VitalsBoxContent/StaminaLabel
@onready var stamina_bar: ProgressBar = $VitalsBox/VitalsBoxMargin/VitalsBoxContent/StaminaBarMargin/StaminaBar
@onready var carry_label: Label = $CarryLabel
@onready var carry_bar: ProgressBar = $CarryRowMargin/CarryRow/CarryBar
# 5 nuovi parametri vitali (2026-09-13, richiesta utente) — STESSO identico schema di stamina_
# label/stamina_bar sopra: un Label + un ProgressBar per parametro, nessuna differenza strutturale.
@onready var food_space_label: Label = $VitalsBox/VitalsBoxMargin/VitalsBoxContent/FoodSpaceLabel
@onready var food_space_bar: ProgressBar = $VitalsBox/VitalsBoxMargin/VitalsBoxContent/FoodSpaceBarMargin/FoodSpaceBar

# Barra delle provviste in modalita' RISERVA CORPOREA (2026-09-19, richiesta utente): quando
# food_calories_held e' 0 la barra mostra body_calories/body_calories_capacity in rosso invece dello
# spazio. Lo stile "fill" originale (dal .tscn) viene salvato alla prima lettura e ripristinato quando
# le provviste tornano a contenere qualcosa; quello rosso e' un duplicato dello stesso StyleBoxFlat
# con solo il colore cambiato (stessi angoli arrotondati).
const FOOD_BAR_BODY_RESERVE_COLOR := Color(0.85, 0.15, 0.15, 1.0)
var _food_bar_fill_normal: StyleBox = null
var _food_bar_fill_body_reserve: StyleBoxFlat = null
@onready var thirst_label: Label = $VitalsBox/VitalsBoxMargin/VitalsBoxContent/ThirstLabel
@onready var thirst_bar: ProgressBar = $VitalsBox/VitalsBoxMargin/VitalsBoxContent/ThirstBarMargin/ThirstBar
@onready var health_label: Label = $VitalsBox/VitalsBoxMargin/VitalsBoxContent/HealthLabel
@onready var health_bar: ProgressBar = $VitalsBox/VitalsBoxMargin/VitalsBoxContent/HealthBarMargin/HealthBar
# Riquadro "Animo" (2026-10-02, richiesta utente): happiness/loyalty spostate qui da VitalsBox, più faith.
@onready var mind_section_label: Label = $MindBox/MindBoxMargin/MindBoxContent/MindSectionLabel
@onready var happiness_label: Label = $MindBox/MindBoxMargin/MindBoxContent/HappinessLabel
@onready var happiness_bar: ProgressBar = $MindBox/MindBoxMargin/MindBoxContent/HappinessBarMargin/HappinessBar
@onready var loyalty_label: Label = $MindBox/MindBoxMargin/MindBoxContent/LoyaltyLabel
@onready var loyalty_bar: ProgressBar = $MindBox/MindBoxMargin/MindBoxContent/LoyaltyBarMargin/LoyaltyBar
@onready var faith_label: Label = $MindBox/MindBoxMargin/MindBoxContent/FaithLabel
@onready var faith_bar: ProgressBar = $MindBox/MindBoxMargin/MindBoxContent/FaithBarMargin/FaithBar
# Sezione Skills (2026-09-13, richiesta utente) — 7 barre VERTICALI (fill_mode = FILL_BOTTOM_TO_TOP
# nel .tscn — hunting aggiunta come 7ma dopo le prime 6, stesso trattamento identico), una per
# skill. Ordine VISIVO qui allineato all'ordine nel .tscn (richiesta utente: management/builder
# scambiati rispetto all'ordine di dichiarazione originale — leadership, management, builder,
# transporter, gathering, cognition, hunting), mai un motivo funzionale, solo leggibilità/
# preferenza visiva. Didascalie (2026-09-13, richiesta utente — nome COMPLETO invece della sigla a
# 3 lettere, per starci scritte in verticale): ciascuna vive in un CaptionWrapper (Control semplice
# a dimensione FISSA nel .tscn) che ospita la Label ruotata di -90° (rotation_degrees, pivot_offset
# centrato — STESSA tecnica già nota in Godot per "testo verticale", non esiste un autowrap/
# orientamento verticale nativo su Label) — SOTTO la barra, non sovrapposta: evita il problema di
# leggibilità su sfondo misto grigio/colorato che una label sovrapposta alla barra avrebbe
# richiesto (nessun bisogno di outline/contrasto dinamico). Geometria FISSA nel .tscn (mai
# calcolata in codice, a differenza di _layout_tools_row): qui non serve alcun ridimensionamento
# proporzionale a runtime, un solo layout costante per tutti e 7 basta.
@onready var skills_section_label: Label = $SkillsBox/SkillsBoxMargin/SkillsBoxContent/SkillsSectionLabel
@onready var skill_leadership_bar: ProgressBar = $SkillsBox/SkillsBoxMargin/SkillsBoxContent/SkillsRowMargin/SkillsRow/LeadershipColumn/LeadershipBar
@onready var skill_leadership_caption: Label = $SkillsBox/SkillsBoxMargin/SkillsBoxContent/SkillsRowMargin/SkillsRow/LeadershipColumn/LeadershipCaptionWrapper/LeadershipCaption
@onready var skill_management_bar: ProgressBar = $SkillsBox/SkillsBoxMargin/SkillsBoxContent/SkillsRowMargin/SkillsRow/ManagementColumn/ManagementBar
@onready var skill_management_caption: Label = $SkillsBox/SkillsBoxMargin/SkillsBoxContent/SkillsRowMargin/SkillsRow/ManagementColumn/ManagementCaptionWrapper/ManagementCaption
@onready var skill_builder_bar: ProgressBar = $SkillsBox/SkillsBoxMargin/SkillsBoxContent/SkillsRowMargin/SkillsRow/BuilderColumn/BuilderBar
@onready var skill_builder_caption: Label = $SkillsBox/SkillsBoxMargin/SkillsBoxContent/SkillsRowMargin/SkillsRow/BuilderColumn/BuilderCaptionWrapper/BuilderCaption
@onready var skill_transporter_bar: ProgressBar = $SkillsBox/SkillsBoxMargin/SkillsBoxContent/SkillsRowMargin/SkillsRow/TransporterColumn/TransporterBar
@onready var skill_transporter_caption: Label = $SkillsBox/SkillsBoxMargin/SkillsBoxContent/SkillsRowMargin/SkillsRow/TransporterColumn/TransporterCaptionWrapper/TransporterCaption
@onready var skill_gathering_bar: ProgressBar = $SkillsBox/SkillsBoxMargin/SkillsBoxContent/SkillsRowMargin/SkillsRow/GatheringColumn/GatheringBar
@onready var skill_gathering_caption: Label = $SkillsBox/SkillsBoxMargin/SkillsBoxContent/SkillsRowMargin/SkillsRow/GatheringColumn/GatheringCaptionWrapper/GatheringCaption
@onready var skill_cognition_bar: ProgressBar = $SkillsBox/SkillsBoxMargin/SkillsBoxContent/SkillsRowMargin/SkillsRow/CognitionColumn/CognitionBar
@onready var skill_cognition_caption: Label = $SkillsBox/SkillsBoxMargin/SkillsBoxContent/SkillsRowMargin/SkillsRow/CognitionColumn/CognitionCaptionWrapper/CognitionCaption
@onready var skill_hunting_bar: ProgressBar = $SkillsBox/SkillsBoxMargin/SkillsBoxContent/SkillsRowMargin/SkillsRow/HuntingColumn/HuntingBar
@onready var skill_hunting_caption: Label = $SkillsBox/SkillsBoxMargin/SkillsBoxContent/SkillsRowMargin/SkillsRow/HuntingColumn/HuntingCaptionWrapper/HuntingCaption
# crafting (2026-09-24, richiesta utente) — 8a barra, in coda dopo hunting, stesso trattamento.
@onready var skill_crafting_bar: ProgressBar = $SkillsBox/SkillsBoxMargin/SkillsBoxContent/SkillsRowMargin/SkillsRow/CraftingColumn/CraftingBar
@onready var skill_crafting_caption: Label = $SkillsBox/SkillsBoxMargin/SkillsBoxContent/SkillsRowMargin/SkillsRow/CraftingColumn/CraftingCaptionWrapper/CraftingCaption
# ritual (2026-10-02, richiesta utente) — 9a barra, in coda dopo crafting, stesso trattamento. Per farci stare nove
# colonne senza allargare il pannello, barre e spaziatura di tutte le colonne sono state ristrette nel .tscn.
@onready var skill_ritual_bar: ProgressBar = $SkillsBox/SkillsBoxMargin/SkillsBoxContent/SkillsRowMargin/SkillsRow/RitualColumn/RitualBar
@onready var skill_ritual_caption: Label = $SkillsBox/SkillsBoxMargin/SkillsBoxContent/SkillsRowMargin/SkillsRow/RitualColumn/RitualCaptionWrapper/RitualCaption
@onready var carried_boxes_row: HBoxContainer = $CarryRowMargin/CarryRow/CarriedBoxesRow
# Primo riquadro (slot 0), in scena: fa anche da modello per gli altri, duplicati in _build_carried_slots.
@onready var carried_resource_box: ColorRect = $CarryRowMargin/CarryRow/CarriedBoxesRow/CarriedResourceBox
# tools_row (2026-09-13, richiesta utente) — rinominato da carry_and_tools_row: ora ospita SOLO gli
# slot della cintura, il quadratino trasportato è salito sulla riga della barra (vedi CarryRow sopra).
@onready var tools_row: Control = $ToolsRowMargin/ToolsRow

# Slot dei riquadri trasportati (2026-09-20, zaino multi-risorsa) — array paralleli, indice = slot,
# riempiti da _build_carried_slots in _ready: il riquadro, la sua InitialLabel e la sua QuantityLabel.
var _carried_boxes: Array[ColorRect] = []
var _carried_initial_labels: Array[Label] = []
var _carried_quantity_labels: Array[Label] = []
# Icona DISEGNATA correntemente inserita nel riquadro di ciascuno slot (2026-09-09, richiesta utente) —
# null quando la risorsa trasportata non ne ha una (vedi IconRegistry.get_resource_icon_node), nel
# qual caso si ripiega sulla InitialLabel dello slot come prima. Tenuta a parte (non un figlio
# fisso della scena, a differenza di InitialLabel/QuantityLabel) perché QUALE icona serve
# dipende dalla risorsa trasportata, che cambia a runtime — instanziata/rimossa ad ogni refresh in
# _update_carried_resource_box.
var _carried_icon_nodes: Array[Control] = []
# Slot della cintura (2026-09-08, richiesta utente; generati dal 2026-09-27) — tanti riquadri quanti
# HumanIndividual.get_tool_slot_count() (HumanRules.tool_slot_count): ToolSlot0 è in scena, gli altri sono
# copie di un suo duplicato pulito (_tool_slot_template), creati/rimossi da _ensure_tool_slot_boxes.
@onready var tool_slot_boxes: Array[Control] = [
	$ToolsRowMargin/ToolsRow/ToolSlot0,
]
# Copia di ToolSlot0 presa in _ready, prima che vi finiscano icone o barre degli usi: modello degli slot aggiunti.
var _tool_slot_template: Control = null
@onready var tool_warning_label: Label = $ToolWarningLabel
# Identità e parentela (2026-10-04, richiesta utente): non più righe in fondo al pannello ma il blocco Info in cima
# (InfoBlock, chiuso di default, aperto/chiuso dall'icona ℹ dell'intestazione) e il tooltip della stessa icona. La casa
# vive solo nell'icona 🏠 dell'intestazione (HouseLabel tolta). Ordine dei blocchi dall'alto (.tscn): Info, task in corso
# e coda, carico e cintura (con l'avviso attrezzi), parametri vitali, animo, skill.
@onready var info_block: PanelContainer = $InfoBlock
@onready var id_label: Label = $InfoBlock/InfoBlockMargin/InfoBlockContent/IdLabel
@onready var mother_label: Label = $InfoBlock/InfoBlockMargin/InfoBlockContent/MotherLabel
@onready var father_label: Label = $InfoBlock/InfoBlockMargin/InfoBlockContent/FatherLabel
@onready var partner_label: Label = $InfoBlock/InfoBlockMargin/InfoBlockContent/PartnerLabel

# Icone 🏠 e ℹ nell'intestazione della scheda selezione, a sinistra del 🎯 (stesso schema delle icone di influenza di
# BuildingInfoPanel): gruppo creato qui, aggiunto da GameScene a GameInfoTabs.header_actions, visibile solo mentre
# questo pannello mostra un individuo. Il titolo dell'intestazione tronca con i puntini, le icone restano visibili.
signal house_center_requested(building_id: int)
const HOUSE_BUTTON_TEXT := "🏠"
# Famiglia (2026-10-05: era l'icona ℹ): apre lo stesso blocco di identità e parentela di prima (InfoBlock).
const FAMILY_BUTTON_TEXT := "👪"
# ℹ del tipo (2026-10-05, come la ℹ degli edifici): scheda della fascia d'età e del sesso del pipottino, non del singolo
# pipottino, nel riquadro comune InfoCardBlock; righe da HumanTypeInfoService, risolte da GameScene (set_type_info).
const INFO_BUTTON_TEXT := "ℹ"
var header_buttons_box: HBoxContainer = null
var _house_button: Button = null
var _info_button: Button = null
var _type_button: Button = null
var _type_block: InfoCardBlock = null
var _house_building_id: int = -1
# Blocchi aperti o chiusi: partono chiusi, poi restano come sono passando da un individuo all'altro nella sessione.
var _info_open: bool = false
var _type_open: bool = false

var _current_individual: HumanIndividual


func _ready() -> void:
	cancel_task_button.tooltip_text = tr("individual_cancel_task_tooltip")
	cancel_task_button.pressed.connect(func(): cancel_task_requested.emit(_current_individual))
	_build_kill_debug_button()
	# Layout riga tool (2026-09-08, semplificata 2026-09-13 quando il quadratino trasporto è
	# uscito da questa riga) — ricalcolato ad ogni resize del pannello (larghezza sidebar, non
	# fissa) oltre che una volta qui subito: vedi _layout_tools_row.
	tools_row.resized.connect(_layout_tools_row)
	_tool_slot_template = tool_slot_boxes[0].duplicate() as Control
	_layout_tools_row()
	_build_carried_slots()
	_connect_tool_belt_clicks()
	_ensure_tool_slot_boxes(HumanIndividual.DEFAULT_TOOL_SLOT_COUNT)
	_build_header_buttons()
	clear()


func _build_header_buttons() -> void:
	header_buttons_box = HBoxContainer.new()
	header_buttons_box.add_theme_constant_override("separation", 2)
	header_buttons_box.visible = false
	_house_button = Button.new()
	_house_button.text = HOUSE_BUTTON_TEXT
	_house_button.focus_mode = Control.FOCUS_NONE
	_house_button.pressed.connect(_on_house_pressed)
	header_buttons_box.add_child(_house_button)
	_info_button = Button.new()
	_info_button.text = FAMILY_BUTTON_TEXT
	_info_button.tooltip_text = tr("individual_family_tooltip")
	_info_button.focus_mode = Control.FOCUS_NONE
	_info_button.toggle_mode = true
	_info_button.toggled.connect(_on_info_toggled)
	header_buttons_box.add_child(_info_button)
	info_block.visible = _info_open
	_type_button = Button.new()
	_type_button.text = INFO_BUTTON_TEXT
	_type_button.focus_mode = Control.FOCUS_NONE
	_type_button.toggle_mode = true
	_type_button.toggled.connect(_on_type_toggled)
	header_buttons_box.add_child(_type_button)
	# Nascosto (2026-10-05, richiesta utente): la scheda del tipo resta pronta (set_type_info), il bottone non si mostra.
	_type_button.visible = false
	_type_block = InfoCardBlock.new()
	_type_block.visible = _type_open
	add_child(_type_block)
	move_child(_type_block, 0)
	# Icone visibili esattamente quando lo è il pannello, qualunque sia la via che lo nasconde.
	visibility_changed.connect(func(): header_buttons_box.visible = visible)


func _on_house_pressed() -> void:
	if _house_building_id != -1:
		house_center_requested.emit(_house_building_id)


# KillButton rimesso (2026-10-04, richiesta utente) — SOLO in modalità debug (DebugLogging.ENABLED, lo stesso flag del
# pulsante della velocità debug): nel gioco normale non viene nemmeno creato. Piccolo "💀" sovrapposto all'angolo in alto
# a destra del blocco Info (figlio della riga dell'id, ancorato a destra, fuori dal flusso dei container: non sposta né
# allarga nulla), visibile quando il blocco è aperto dall'icona ℹ. Emette kill_requested come prima: GameScene.
# _on_kill_requested -> GameTimeService.kill_individual_now, il percorso normale di morte (cadavere e record completi).
const KILL_DEBUG_BUTTON_SIZE: float = 16.0


func _build_kill_debug_button() -> void:
	if not DebugLogging.ENABLED:
		return
	var kill_button := Button.new()
	kill_button.text = "💀"
	kill_button.flat = true
	kill_button.focus_mode = Control.FOCUS_NONE
	kill_button.add_theme_font_size_override("font_size", 9)
	kill_button.tooltip_text = tr("individual_kill_debug_button")
	kill_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	id_label.add_child(kill_button)
	kill_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	kill_button.offset_left = -KILL_DEBUG_BUTTON_SIZE
	kill_button.offset_right = 0.0
	kill_button.offset_top = 0.0
	kill_button.offset_bottom = KILL_DEBUG_BUTTON_SIZE
	kill_button.pressed.connect(func():
		if _current_individual != null:
			kill_requested.emit(_current_individual)
	)


# Famiglia e scheda del tipo sono alternative (2026-10-05): aprirne una chiude l'altra.
func _on_info_toggled(pressed: bool) -> void:
	_info_open = pressed
	info_block.visible = _info_open
	if pressed and _type_open:
		_type_open = false
		_type_button.set_pressed_no_signal(false)
		_type_block.visible = false


func _on_type_toggled(pressed: bool) -> void:
	_type_open = pressed
	_type_block.visible = _type_open
	if pressed and _info_open:
		_info_open = false
		_info_button.set_pressed_no_signal(false)
		info_block.visible = false


# Scheda del tipo (2026-10-05): righe già risolte da GameScene (HumanTypeInfoService), stesso tooltip delle righe come
# la ℹ degli edifici.
func set_type_info(rows: Array[Dictionary]) -> void:
	_type_button.tooltip_text = _type_block.set_rows(rows)
	_type_button.set_pressed_no_signal(_type_open)
	_type_block.visible = _type_open


# Identità, parentela e casa già risolte da GameScene (2026-10-04, richiesta utente — il pannello resta muto: non
# conosce gli altri individui, i defunti né gli edifici). `details`:
#   "id", "folk", "group": int (-1 = non applicabile);
#   "mother", "father", "partner": {"id": int, "name": String, "dead": bool} ("id" -1 = non noto);
#   "partner_unknown_female": bool — quale forma di "sconosciuto" usare per il partner;
#   "house": {"id": int, "name": String} o {} senza casa.
# Stesse righe nel blocco Info e nel tooltip dell'icona ℹ; la casa solo nell'icona 🏠.
func set_identity_details(details: Dictionary) -> void:
	var id_text: String = tr("individual_id_label").format({
		"id": int(details.get("id", -1)), "folk": _format_id(int(details.get("folk", -1))), "group": _format_id(int(details.get("group", -1)))
	})
	var mother_text: String = tr("individual_mother_label").format({"person": _format_relative(details.get("mother", {}), true)})
	var father_text: String = tr("individual_father_label").format({"person": _format_relative(details.get("father", {}), false)})
	var partner_text: String = tr("individual_partner_label").format({
		"person": _format_relative(details.get("partner", {}), bool(details.get("partner_unknown_female", false)))
	})
	id_label.text = id_text
	mother_label.text = mother_text
	father_label.text = father_text
	partner_label.text = partner_text
	_info_button.set_pressed_no_signal(_info_open)
	info_block.visible = _info_open
	var house: Dictionary = details.get("house", {})
	_house_building_id = int(house.get("id", -1)) if not house.is_empty() else -1
	_house_button.disabled = _house_building_id == -1
	_house_button.tooltip_text = tr("individual_no_house") if _house_building_id == -1 else tr("individual_house_tooltip").format({
		"name": String(house.get("name", "")), "id": _house_building_id
	})
	header_buttons_box.visible = visible


# "Wenna (#4)", con il segno del defunto se morto; "sconosciuta"/"sconosciuto" se l'id non è noto; "#4" se l'id è
# noto ma il nome non si trova.
func _format_relative(relative: Dictionary, unknown_female: bool) -> String:
	var relative_id := int(relative.get("id", -1))
	if relative_id < 0:
		return tr("individual_relative_unknown_female") if unknown_female else tr("individual_relative_unknown_male")
	var relative_name := String(relative.get("name", ""))
	if relative_name == "":
		return "#%d" % relative_id
	if bool(relative.get("dead", false)):
		return tr("individual_relative_dead").format({"name": relative_name, "id": relative_id})
	return tr("individual_relative_alive").format({"name": relative_name, "id": relative_id})


# Prende l'HumanIndividual intero (non piu' i soli name/sex, richiesta utente 2026-09-02: servono
# anche id/mother_id/father_id/partner_id/source_group_ref, tutti gia' sull'oggetto). age/age_band
# NON sono più parametri di questa funzione (rimossi 2026-09-13, richiesta utente): restano
# calcolati dal chiamante (richiedono current_year/HumanRules, che questo pannello non conosce),
# ma solo per comporre l'header di GameInfoTabs (vedi GameScene._update_individual_panel_content),
# che ha sostituito la ex-IdentityLabel di questo pannello — nessun consumatore rimasto qui dentro.
# max_stamina/current_stamina stesso principio: gia' risolti dal chiamante (HumanCalculator.
# get_max_stamina), vedi commento stamina_bar sopra.
#
# activity_text (2026-09-07, richiesta utente — "cosa sta facendo questo individuo") già risolto e
# tr()-ato dal chiamante (GameScene, via HumanIndividual.current_task.get_activity_description() o
# la stringa "a riposo" se current_task è null) — stesso identico principio "questo pannello riceve
# solo dati già pronti" di ogni altro parametro qui.
# max_carry_capacity/used_carry_space (2026-09-08, richiesta utente; invertito 2026-09-20, da
# free_carry_capacity a used_carry_space) — stesso principio di max_stamina/current_stamina sopra:
# già risolti dal chiamante. La barra mostra lo spazio OCCUPATO — vedi commento su carry_bar in
# testa al file. carried_resources: letto direttamente dall'HumanIndividual passato (stesso
# identico stato grezzo, nessuna risoluzione necessaria).
#
# food_space_capacity/food_space_used (saccoccia del cibo, ex hunger)/.../max_loyalty/current_loyalty (2026-09-13, richiesta utente, 5 nuovi
# parametri vitali) — STESSA firma-stile di max_stamina/current_stamina sopra, già risolti dal
# chiamante: a differenza di max_stamina (che GameScene ricalcola fresco per i modificatori
# volatili gravidanza/figlio-a-carico), questi 5 non hanno modificatori volatili, quindi il
# chiamante li legge direttamente dai campi di HumanIndividual (stesso trattamento di
# max_carry_capacity) — questo pannello resta comunque ignaro della differenza, riceve solo 10
# float già pronti, stesso principio "muto" di ogni altro parametro qui.
func show_individual(
	individual: HumanIndividual,
	max_stamina: float, current_stamina: float, activity_text: String,
	max_carry_capacity: float, used_carry_space: float,
	food_space_capacity: float, food_space_used: float, food_calories_held: float,
	body_calories: float, body_calories_capacity: float, daily_calorie_consumption: float,
	max_thirst: float, current_thirst: float,
	max_health: float, current_health: float,
	max_happiness: float, current_happiness: float,
	max_loyalty: float, current_loyalty: float,
	max_faith: float, current_faith: float,
	skill_leadership: float, skill_builder: float, skill_management: float,
	skill_transporter: float, skill_gathering: float, skill_cognition: float,
	skill_hunting: float, skill_crafting: float, skill_ritual: float,
	queued_task_descriptions: Array[String] = []
) -> void:
	visible = true
	_current_individual = individual
	# Riga identità (nome/sesso/età/fascia) NON più impostata qui (2026-09-13, richiesta utente) —
	# vive ora SOLO nell'header di GameInfoTabs (title_label, impostato da GameScene tramite
	# set_selection_title), sulla stessa riga del bottone 🎯. age/age_band NON sono più parametri
	# di questa funzione (mai usati per altro qui dentro) — GameScene li calcola comunque per sé,
	# vedi il commento di testa a show_individual.
	activity_label.text = activity_text
	cancel_task_button.visible = individual != null and individual.current_task != null and not individual.current_task.is_finished()

	# Azioni in coda (2026-09-13, richiesta utente) — sotto l'attività corrente, nascosta quando
	# task_queue è vuota (il caso comune: oggi solo haul_resource/transport sono is_suspendable,
	# quindi la coda resta vuota per la stragrande maggioranza degli individui). Descrizioni già
	# risolte/tr()-ate dal chiamante (GameScene, stesso principio "pannello muto" di ogni altro
	# parametro qui) — intestazione fissa (individual_queued_tasks_label, nessun {tasks} da
	# formattare) + una riga numerata per elemento, richiesto esplicitamente dall'utente al posto
	# dell'elenco su riga unica separato da virgole della prima versione.
	if queued_task_descriptions.is_empty():
		queued_tasks_label.visible = false
	else:
		queued_tasks_label.visible = true
		var numbered_lines: Array[String] = []
		for i in range(queued_task_descriptions.size()):
			numbered_lines.append("%d. %s" % [i + 1, queued_task_descriptions[i]])
		queued_tasks_label.text = tr("individual_queued_tasks_label") + "\n" + "\n".join(numbered_lines)

	# Titolo sezione "Parametri vitali" (richiesta utente, stesso stile/stesso trattamento di
	# skills_section_label sotto — coerenza visiva fra le due sezioni a barre del pannello).
	vitals_section_label.text = tr("individual_vitals_section_label")

	stamina_label.text = tr("individual_stamina_label")
	stamina_bar.max_value = max_stamina
	stamina_bar.value = current_stamina
	stamina_bar.tooltip_text = "%d/%d" % [int(current_stamina), int(max_stamina)]

	# 5 nuovi parametri vitali (2026-09-13) — 5 blocchi identici al blocco stamina sopra, copiati
	# uno per uno (stessa forma esatta, nessuna astrazione condivisa: coerente con lo stile già
	# in uso qui per stamina/carry, mai un helper generico per "una barra qualsiasi"). Ordine QUI
	# allineato all'ordine VISIVO nel pannello (riordinato 2026-09-13, richiesta utente: capacità di
	# trasporto spostata in fondo) — mai un motivo funzionale, solo leggibilità.
	# Provviste (2026-09-19, richiesta utente - era la barra "Fame", poi "Saccoccia"): SPAZIO usato/capacita'.
	# Le calorie contenute NON compaiono come valore visibile accanto alla barra: solo nel tooltip,
	# insieme a spazio usato e capacita'.
	food_space_label.text = tr("individual_supplies_label")
	# Provviste vuote (food_calories_held == 0) E individuo che consuma calorie (daily_calorie_consumption
	# > 0, gia' risolto dal chiamante): la barra passa alla riserva corporea, in rosso, e il tooltip lo
	# dice. Chi non consuma (INFANT, moltiplicatore calorico 0) ha le provviste a 0 per definizione ma
	# non e' affamato: per lui resta la barra normale. Altrimenti spazio usato/capacita', con le calorie
	# nel tooltip.
	if _food_bar_fill_normal == null:
		_food_bar_fill_normal = food_space_bar.get_theme_stylebox("fill")
	if food_calories_held <= 0.0 and daily_calorie_consumption > 0.0:
		if _food_bar_fill_body_reserve == null:
			var base_fill := _food_bar_fill_normal as StyleBoxFlat
			_food_bar_fill_body_reserve = base_fill.duplicate() as StyleBoxFlat if base_fill != null else StyleBoxFlat.new()
			_food_bar_fill_body_reserve.bg_color = FOOD_BAR_BODY_RESERVE_COLOR
		food_space_bar.add_theme_stylebox_override("fill", _food_bar_fill_body_reserve)
		food_space_bar.max_value = body_calories_capacity
		food_space_bar.value = body_calories
		food_space_bar.tooltip_text = tr("individual_supplies_tooltip_body").format({
			"current": int(round(body_calories)), "max": int(round(body_calories_capacity))
		})
	else:
		food_space_bar.add_theme_stylebox_override("fill", _food_bar_fill_normal)
		food_space_bar.max_value = food_space_capacity
		food_space_bar.value = food_space_used
		food_space_bar.tooltip_text = "%s - %s" % [
			tr("individual_supplies_tooltip_pouch").format({"used": int(food_space_used), "capacity": int(food_space_capacity)}),
			tr("individual_food_calories_value").format({"calories": int(round(food_calories_held))})
		]

	thirst_label.text = tr("individual_thirst_label")
	thirst_bar.max_value = max_thirst
	thirst_bar.value = current_thirst
	thirst_bar.tooltip_text = "%d/%d" % [int(current_thirst), int(max_thirst)]

	health_label.text = tr("individual_health_label")
	health_bar.max_value = max_health
	health_bar.value = current_health
	health_bar.tooltip_text = "%d/%d" % [int(current_health), int(max_health)]

	mind_section_label.text = tr("individual_mind_section_label")

	happiness_label.text = tr("individual_happiness_label")
	happiness_bar.max_value = max_happiness
	happiness_bar.value = current_happiness
	happiness_bar.tooltip_text = "%d/%d" % [int(current_happiness), int(max_happiness)]

	loyalty_label.text = tr("individual_loyalty_label")
	loyalty_bar.max_value = max_loyalty
	loyalty_bar.value = current_loyalty
	loyalty_bar.tooltip_text = "%d/%d" % [int(current_loyalty), int(max_loyalty)]

	faith_label.text = tr("individual_faith_label")
	faith_bar.max_value = max_faith
	faith_bar.value = current_faith
	faith_bar.tooltip_text = "%d/%d" % [int(current_faith), int(max_faith)]

	# Sezione Skills (2026-09-13, richiesta utente) — 6 blocchi identici, stessa forma esatta dei
	# blocchi vitali sopra (nessuna astrazione condivisa, coerente con lo stile del file). max_value
	# = 1000.0 FISSO (non un parametro ricevuto: le skill non hanno un massimo variabile come i
	# vitali, vedi HumanIndividual.gd). Didascalie (LDR/BLD/...) tr()-ate qui insieme al resto,
	# anche se il loro testo non dipende dai dati dell'individuo — stesso trattamento "ririsolto ad
	# ogni show_individual" già riservato a carry_label/stamina_label sopra, per coerenza.
	skills_section_label.text = tr("individual_skills_section_label")

	skill_leadership_bar.max_value = 1000.0
	skill_leadership_bar.value = skill_leadership
	skill_leadership_bar.tooltip_text = "%d/1000" % [int(skill_leadership)]
	skill_leadership_caption.text = tr("skill_leadership_label")

	skill_builder_bar.max_value = 1000.0
	skill_builder_bar.value = skill_builder
	skill_builder_bar.tooltip_text = "%d/1000" % [int(skill_builder)]
	skill_builder_caption.text = tr("skill_builder_label")

	skill_management_bar.max_value = 1000.0
	skill_management_bar.value = skill_management
	skill_management_bar.tooltip_text = "%d/1000" % [int(skill_management)]
	skill_management_caption.text = tr("skill_management_label")

	skill_transporter_bar.max_value = 1000.0
	skill_transporter_bar.value = skill_transporter
	skill_transporter_bar.tooltip_text = "%d/1000" % [int(skill_transporter)]
	skill_transporter_caption.text = tr("skill_transporter_label")

	skill_gathering_bar.max_value = 1000.0
	skill_gathering_bar.value = skill_gathering
	skill_gathering_bar.tooltip_text = "%d/1000" % [int(skill_gathering)]
	skill_gathering_caption.text = tr("skill_gathering_label")

	skill_cognition_bar.max_value = 1000.0
	skill_cognition_bar.value = skill_cognition
	skill_cognition_bar.tooltip_text = "%d/1000" % [int(skill_cognition)]
	skill_cognition_caption.text = tr("skill_cognition_label")

	skill_hunting_bar.max_value = 1000.0
	skill_hunting_bar.value = skill_hunting
	skill_hunting_bar.tooltip_text = "%d/1000" % [int(skill_hunting)]
	skill_hunting_caption.text = tr("skill_hunting_label")

	skill_crafting_bar.max_value = 1000.0
	skill_crafting_bar.value = skill_crafting
	skill_crafting_bar.tooltip_text = "%d/1000" % [int(skill_crafting)]
	skill_crafting_caption.text = tr("skill_crafting_label")

	skill_ritual_bar.max_value = 1000.0
	skill_ritual_bar.value = skill_ritual
	skill_ritual_bar.tooltip_text = "%d/1000" % [int(skill_ritual)]
	skill_ritual_caption.text = tr("skill_ritual_label")

	# Capacità di trasporto (2026-09-13, richiesta utente — spostata in FONDO alle barre, dopo i 5
	# nuovi parametri vitali: nessun motivo funzionale, solo l'ordine visivo concordato) — la barra
	# stessa vive ora dentro CarryRow insieme a CarriedResourceBox (vedi commento in testa al file),
	# ma resta un ProgressBar identico a prima: stessa formula/stesso tooltip.
	carry_label.text = tr("individual_carry_label")
	# Solo in VISUALIZZAZIONE (2026-09-20, richiesta utente): barra e tooltip usano interi arrotondati
	# (la capacita' deriva dai moltiplicatori di taglia e ha decimali, es. 56.8 -> 57); i valori float
	# ricevuti dal chiamante (used_carry_space/max_carry_capacity) non vengono toccati.
	carry_bar.max_value = roundf(max_carry_capacity)
	carry_bar.value = roundf(used_carry_space)
	carry_bar.tooltip_text = "%s/%s" % [_format_space(used_carry_space), _format_space(max_carry_capacity)]

	_update_carried_resource_boxes(individual.carried_resources)
	_update_tool_slots(individual)
	# Ultimo avviso del controllo attrezzi (2026-09-25, richiesta utente — vedi ToolGateService e
	# HumanIndividual.tool_gate_warning): testo già tradotto da GameScene, nascosto se vuoto.
	tool_warning_label.text = individual.tool_gate_warning
	tool_warning_label.visible = individual.tool_gate_warning != ""
	# Ri-layout esplicito dei tool (2026-09-08) — oltre al collegamento a tools_row.resized in
	# _ready(): coprire anche il caso "la riga non cambia dimensione tra due individui mostrati in
	# sequenza" (nessun resize emesso, ma il pannello potrebbe comunque non essere mai stato
	# disegnato mentre era nascosto — clear() lo mette invisible, un Control invisibile non
	# garantisce dimensioni aggiornate). Economico (poche assegnazioni di position/size), nessun
	# problema a richiamarlo qui ad ogni refresh.
	#
	# call_deferred, non una chiamata diretta (bugfix 2026-09-13, richiesta utente) — alla PRIMA
	# selezione di un individuo in una sessione tools_row.size.x risultava ancora 0/stantio in
	# questo stesso frame — `visible` è appena passato da false a true qui sopra, e Godot
	# ricalcola/ordina i figli di un Container in modo differito, non sincrono, quindi una lettura
	# immediata di .size.x vedeva la larghezza di QUANDO il pannello era nascosto, non quella reale
	# della sidebar. call_deferred esegue dopo che Godot ha già ordinato/dimensionato i Container di
	# questo frame, quando tools_row.size.x riflette finalmente la larghezza vera.
	call_deferred("_layout_tools_row")

	# Identità, parentela e casa (2026-10-04): da set_identity_details, chiamata da GameScene subito dopo questa
	# funzione (servono nomi di altri individui, anche defunti, e il nome della casa, che questo pannello non conosce).
	if header_buttons_box != null:
		header_buttons_box.visible = true


func clear() -> void:
	visible = false
	_current_individual = null
	if header_buttons_box != null:
		header_buttons_box.visible = false


# Sentinella -1 (genitore/gruppo/partner sconosciuto o non applicabile, vedi HumanIndividual) resa
# come "—" invece del numero grezzo — poco leggibile per chi guarda il pannello, "-1" sembra un
# errore piu' che un "non applicabile".
func _format_id(value: int) -> String:
	return "—" if value < 0 else str(value)


# Dimensioni/spaziatura NATURALI degli slot della cintura (2026-09-08, richiesta utente) — usate come punto
# di partenza da _layout_tools_row sotto, che le rimpicciolisce TUTTE proporzionalmente quando non
# entrano nella larghezza disponibile del pannello, invece di tagliarle fuori. CARRY_BOX_SIZE
# RIMOSSA (2026-09-13): il quadratino trasporto è uscito da questa riga (vedi CarryRow in testa al
# file), il suo dimensionamento è ora gestito da Godot stesso (custom_minimum_size dentro un
# HBoxContainer), nessun calcolo manuale più necessario per lui.
const TOOL_BOX_SIZE: float = 28.0
const BOX_SPACING: float = 6.0

const EMPTY_CARRIED_RESOURCE_COLOR := Color(0.3, 0.3, 0.3, 0.4)

# Placeholder (2026-09-08, richiesta esplicita dell'utente: "le icone delle risorse non esistono
# ancora, usa un placeholder — il sistema icone lo definiamo dopo") — riquadro colorato
# deterministicamente in base al NOME della risorsa (hash % 360 come tinta HSV, stesso principio
# "hash della stringa -> risultato stabile" già in uso altrove nel progetto per la scelta
# deterministica, es. MicroCellRenderer._is_shrub_fruit_bearing) con l'iniziale maiuscola al
# centro e la quantità sovrapposta in basso a destra. resource_name vuoto = non sta trasportando
# nulla: riquadro grigio spento, entrambe le label vuote/nascoste.
#
# Icona vera (2026-09-09, richiesta utente) — TRE livelli di fallback, in ordine: (1)
# IconRegistry.get_resource_icon_node(resource_name), un Control disegnato a mano (oggi "pebble"/
# "stick", vedi PebbleIcon/StickIcon) — se presente sostituisce ANCHE la label testuale, non solo
# l'iniziale, perché occupa l'intero riquadro come PebbleCircleIcon dentro un IconButtonRow; (2)
# IconRegistry.get_resource_icon(resource_name), un emoji semplice (nessuna risorsa oggi, tenuto
# per una futura risorsa che un emoji rappresenta già bene); (3) l'iniziale maiuscola del nome,
# come prima. Il colore di sfondo resta comunque quello deterministico in ogni caso (nessuna
# distinzione visiva legata al livello di fallback usato).
#
# Tooltip (2026-09-09, richiesta utente — "con hover su icona esca scritto di che risorsa è") —
# vive sul CONTENITORE (il riquadro dello slot), non sull'icona disegnata (che ha mouse_filter =
# IGNORE apposta, vedi PebbleIcon/StickIcon._ready): un Control con IGNORE non riceve mai hover,
# quindi il tooltip andrebbe perso se vivesse lì. "" quando non si trasporta nulla (nessun tooltip
# su un riquadro vuoto).
func _update_carried_resource_box(slot: int, resource_name: String, quantity: int) -> void:
	var slot_box: ColorRect = _carried_boxes[slot]
	var slot_initial_label: Label = _carried_initial_labels[slot]
	var slot_quantity_label: Label = _carried_quantity_labels[slot]
	if _carried_icon_nodes[slot] != null:
		_carried_icon_nodes[slot].queue_free()
		_carried_icon_nodes[slot] = null

	if resource_name == "":
		slot_box.color = EMPTY_CARRIED_RESOURCE_COLOR
		slot_box.tooltip_text = ""
		slot_initial_label.visible = true
		slot_initial_label.text = ""
		slot_quantity_label.visible = false
		return

	slot_box.color = IconRegistry.get_resource_color(resource_name)
	slot_box.tooltip_text = IconRegistry.get_resource_display_name(resource_name)

	var icon_node: Control = IconRegistry.get_resource_icon_node(resource_name)
	if icon_node != null:
		slot_initial_label.visible = false
		slot_initial_label.text = ""
		_carried_icon_nodes[slot] = icon_node
		slot_box.add_child(icon_node)
		# Icona come PRIMO figlio (2026-09-26, richiesta utente — bugfix "113 si legge 13"): in Godot
		# l'ordine dei figli è l'ordine di disegno, quindi aggiunta in coda l'icona (a tutto riquadro,
		# opaca) copriva la QuantityLabel in basso a destra e la prima cifra dei numeri a tre cifre.
		# Spostata in testa, le etichette (InitialLabel/QuantityLabel) restano sempre sopra. Vale per
		# ogni risorsa con icona disegnata, questo è l'unico punto che la inserisce nel riquadro.
		slot_box.move_child(icon_node, 0)
		# PRESET_FULL_RECT via ancore+offset DIRETTI (stesso bugfix già documentato in
		# IconButtonRow.configure_slot per PebbleCircleIcon: il preset di default userebbe la
		# minimum size del figlio, zero per un Control senza testo/figli come queste icone).
		icon_node.anchor_left = 0.0
		icon_node.anchor_top = 0.0
		icon_node.anchor_right = 1.0
		icon_node.anchor_bottom = 1.0
		icon_node.offset_left = 0.0
		icon_node.offset_top = 0.0
		icon_node.offset_right = 0.0
		icon_node.offset_bottom = 0.0
	else:
		slot_initial_label.visible = true
		var icon: String = IconRegistry.get_resource_icon(resource_name)
		slot_initial_label.text = icon if icon != "" else resource_name.substr(0, 1).to_upper()

	slot_quantity_label.text = str(quantity)
	slot_quantity_label.visible = true


# Aggiorna TUTTI gli slot dai contenuti dello zaino (2026-09-20, zaino multi-risorsa): le varietà
# occupano gli slot nell'ordine di inserimento del dizionario, gli slot rimasti liberi tornano al
# placeholder grigio (nome vuoto).
func _update_carried_resource_boxes(carried_resources: Dictionary) -> void:
	var carried_names: Array = carried_resources.keys()
	_carried_slot_names.clear()
	for slot in range(_carried_boxes.size()):
		if slot < carried_names.size():
			var carried_name := String(carried_names[slot])
			var carried_entry: Dictionary = carried_resources[carried_name]
			_update_carried_resource_box(slot, carried_name, int(carried_entry.get("quantity", 0)))
			_carried_slot_names.append(carried_name)
			# Manina solo sugli attrezzi: sono gli unici riquadri che un click sposta nella cintura.
			_carried_boxes[slot].mouse_default_cursor_shape = (
				Control.CURSOR_POINTING_HAND if HumanIndividual.is_tool_resource(carried_name) else Control.CURSOR_ARROW
			)
		else:
			_update_carried_resource_box(slot, "", 0)
			_carried_slot_names.append("")
			_carried_boxes[slot].mouse_default_cursor_shape = Control.CURSOR_ARROW


# --- Cintura degli attrezzi (2026-09-25, richiesta utente) ---
# Nome della risorsa mostrata in ciascun riquadro dello zaino (stesso ordine di _carried_boxes, ""
# = vuoto): serve al click per sapere QUALE risorsa chiedere di equipaggiare.
var _carried_slot_names: Array[String] = []
# Icona disegnata dentro ciascuno slot della cintura (null = nessuna), stesso trattamento di
# _carried_icon_nodes per i riquadri dello zaino.
var _tool_icon_nodes: Array[Control] = [null]
# Colore della "T" segnaposto di uno slot vuoto — lo stesso impostato nella scena (alpha 0.35).
const EMPTY_TOOL_SLOT_TEXT_COLOR := Color(1, 1, 1, 0.35)


func _connect_tool_belt_clicks() -> void:
	for slot in range(_carried_boxes.size()):
		_carried_boxes[slot].gui_input.connect(_on_carried_box_gui_input.bind(slot))
	for slot in range(tool_slot_boxes.size()):
		tool_slot_boxes[slot].gui_input.connect(_on_tool_slot_gui_input.bind(slot))


func _is_left_click(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT


func _on_carried_box_gui_input(event: InputEvent, slot: int) -> void:
	if not _is_left_click(event) or _current_individual == null:
		return
	if slot >= _carried_slot_names.size() or _carried_slot_names[slot] == "":
		return
	accept_event()
	equip_tool_requested.emit(_current_individual, _carried_slot_names[slot])


# Sinistro su slot pieno: di nuovo nello zaino, subito (nessuna Task). Destro: Task verso/da un magazzino.
func _on_tool_slot_gui_input(event: InputEvent, slot: int) -> void:
	if _current_individual == null or not (event is InputEventMouseButton) or not event.pressed:
		return
	var slot_is_empty: bool = _current_individual.get_equipped_tool(slot) == ""
	if event.button_index == MOUSE_BUTTON_LEFT:
		if slot_is_empty:
			return
		accept_event()
		unequip_tool_requested.emit(_current_individual, slot)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		accept_event()
		if slot_is_empty:
			tool_from_storage_requested.emit(_current_individual, slot)
		else:
			tool_to_storage_requested.emit(_current_individual, slot)


# Stesso schema di _update_carried_resource_box: icona della risorsa (IconRegistry) a tutto riquadro,
# oppure la sua emoji/iniziale nella Label; slot vuoto = la "T" attenuata di sempre. Tooltip col nome
# dell'attrezzo e cursore a manina sugli slot pieni (cliccabili per rimetterli nello zaino).
func _update_tool_slots(individual: HumanIndividual) -> void:
	if individual != null:
		_ensure_tool_slot_boxes(individual.get_tool_slot_count())
	for slot in range(tool_slot_boxes.size()):
		var box: Control = tool_slot_boxes[slot]
		var label: Label = box.get_node("Label") as Label
		if _tool_icon_nodes[slot] != null:
			_tool_icon_nodes[slot].queue_free()
			_tool_icon_nodes[slot] = null

		var tool_name: String = individual.get_equipped_tool(slot) if individual != null else ""
		if tool_name == "":
			label.visible = true
			label.text = "T"
			label.add_theme_color_override("font_color", EMPTY_TOOL_SLOT_TEXT_COLOR)
			box.tooltip_text = tr("tool_slot_empty_tooltip")
			box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			_update_tool_uses_bar(slot, 0, 0)
			continue

		label.add_theme_color_override("font_color", Color.WHITE)
		box.tooltip_text = tr("tool_slot_full_tooltip").format({"tool": IconRegistry.get_resource_display_name(tool_name)})
		# Usi residui (2026-09-26, attrezzi come istanze — step 3): riga in più nel tooltip e barra in basso
		# nel riquadro. Un attrezzo che non si usura (max_uses <= 0) non mostra né l'una né l'altra.
		var max_uses: int = ToolInstance.get_max_uses(tool_name)
		var remaining_uses: int = individual.get_equipped_tool_uses(slot)
		if max_uses > 0:
			box.tooltip_text += "\n" + tr("tool_slot_uses_line").format({"uses": remaining_uses, "max": max_uses})
		# Bonus di capacità di trasporto (2026-09-27, richiesta utente — sacca di pelle): SecondaryResourceRules.
		# carry_capacity_bonus dell'attrezzo, se ne ha uno.
		var tool_rules := CaloricCalculator.get_caloric_source_rules(tool_name)
		if tool_rules != null and tool_rules.carry_capacity_bonus > 0.0:
			box.tooltip_text += "\n" + tr("tool_slot_carry_bonus_line").format({"bonus": int(roundf(tool_rules.carry_capacity_bonus))})
		_update_tool_uses_bar(slot, remaining_uses, max_uses)
		box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var icon_node: Control = IconRegistry.get_resource_icon_node(tool_name)
		if icon_node != null:
			label.visible = false
			_tool_icon_nodes[slot] = icon_node
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
			label.visible = true
			var icon: String = IconRegistry.get_resource_icon(tool_name)
			label.text = icon if icon != "" else tool_name.substr(0, 1).to_upper()
		# L'icona appena aggiunta va in coda ai figli e coprirebbe la barra: la barra torna sopra.
		if _tool_uses_bars[slot] != null:
			box.move_child(_tool_uses_bars[slot], -1)


# Barra degli usi residui di uno slot della cintura (2026-09-26, attrezzi come istanze — step 3):
# striscia sottile in fondo al riquadro, sfondo scuro e riempimento proporzionale agli usi, dal verde
# (pieno) al rosso (quasi rotto). Creata al primo uso e poi riusata; nascosta per slot vuoti e per
# attrezzi che non si usurano (max_uses <= 0). mouse_filter IGNORE: hover e click restano al riquadro.
var _tool_uses_bars: Array[ColorRect] = [null]
const TOOL_USES_BAR_HEIGHT_FRACTION := 0.14
const TOOL_USES_BAR_BACKGROUND := Color(0, 0, 0, 0.55)


func _update_tool_uses_bar(slot: int, remaining_uses: int, max_uses: int) -> void:
	if slot >= _tool_uses_bars.size():
		return
	var bar: ColorRect = _tool_uses_bars[slot]
	if max_uses <= 0:
		if bar != null:
			bar.visible = false
		return
	if bar == null:
		bar = ColorRect.new()
		bar.name = "UsesBar"
		bar.color = TOOL_USES_BAR_BACKGROUND
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		bar.anchor_top = 1.0 - TOOL_USES_BAR_HEIGHT_FRACTION
		bar.anchor_bottom = 1.0
		var fill := ColorRect.new()
		fill.name = "Fill"
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.anchor_left = 0.0
		fill.anchor_top = 0.0
		fill.anchor_bottom = 1.0
		bar.add_child(fill)
		tool_slot_boxes[slot].add_child(bar)
		_tool_uses_bars[slot] = bar
	var ratio: float = clampf(float(remaining_uses) / float(max_uses), 0.0, 1.0)
	var fill_rect := bar.get_node("Fill") as ColorRect
	fill_rect.anchor_right = ratio
	fill_rect.color = Color.RED.lerp(Color.GREEN, ratio)
	bar.visible = true


# Porta i riquadri della cintura a `slot_count` (2026-09-27, richiesta utente — prima 4 nodi fissi in scena): i nuovi
# sono duplicati di _tool_slot_template (stesso stile e stessa "T"), con lo stesso collegamento del clic
# (_on_tool_slot_gui_input); quelli in più vengono rimossi. Tiene allineati _tool_icon_nodes/_tool_uses_bars e
# rifà il layout della riga. No-op se il numero è già giusto.
func _ensure_tool_slot_boxes(slot_count: int) -> void:
	slot_count = maxi(slot_count, 1)
	if tool_slot_boxes.size() == slot_count:
		return
	while tool_slot_boxes.size() < slot_count:
		var slot: int = tool_slot_boxes.size()
		var box: Control = _tool_slot_template.duplicate() as Control
		box.name = "ToolSlot%d" % slot
		tools_row.add_child(box)
		box.gui_input.connect(_on_tool_slot_gui_input.bind(slot))
		tool_slot_boxes.append(box)
		_tool_icon_nodes.append(null)
		_tool_uses_bars.append(null)
	while tool_slot_boxes.size() > slot_count:
		var removed: Control = tool_slot_boxes.pop_back()
		removed.queue_free()
		_tool_icon_nodes.pop_back()
		_tool_uses_bars.pop_back()
	_layout_tools_row()


# Costruisce gli slot dei riquadri trasportati (una volta, da _ready): il riquadro in scena è lo slot 0,
# gli altri fino a HumanIndividual.MAX_CARRIED_VARIETIES sono suoi duplicati (con InitialLabel/
# QuantityLabel figlie), affiancati nella stessa riga. Va chiamata PRIMA che qualunque icona venga
# inserita nel riquadro modello, altrimenti i duplicati la erediterebbero.
func _build_carried_slots() -> void:
	_carried_boxes = [carried_resource_box]
	while _carried_boxes.size() < HumanIndividual.MAX_CARRIED_VARIETIES:
		var extra_box: ColorRect = carried_resource_box.duplicate() as ColorRect
		extra_box.name = "CarriedResourceBox%d" % _carried_boxes.size()
		carried_boxes_row.add_child(extra_box)
		_carried_boxes.append(extra_box)
	_carried_initial_labels = []
	_carried_quantity_labels = []
	_carried_icon_nodes = []
	for box in _carried_boxes:
		_carried_initial_labels.append(box.get_node("InitialLabel") as Label)
		_carried_quantity_labels.append(box.get_node("QuantityLabel") as Label)
		_carried_icon_nodes.append(null)


# Posiziona/dimensiona gli slot della cintura dentro tools_row (2026-09-08, richiesta utente —
# SEMPLIFICATA 2026-09-13 quando il quadratino trasporto è uscito da questa riga, vedi CarryRow in
# testa al file: prima questa funzione posizionava ANCHE lui, ora si occupa solo degli slot)
# — Control semplice, non un Container: i figli sono posizionati/dimensionati A MANO qui invece
# che affidati al layout automatico di un HBoxContainer, perché serve un comportamento che nessun
# Container standard di Godot offre da solo: quando la larghezza disponibile non basta per la
# dimensione NATURALE di tutti i quadratini, li si rimpicciolisce TUTTI con lo STESSO fattore
# di scala (mai un sottoinsieme tagliato fuori, richiesta esplicita dell'utente) — un HBoxContainer
# con size_flags_horizontal EXPAND_FILL comprimerebbe solo i figli "expand", non li scalerebbe
# proporzionalmente insieme.
#
# Allineati a SINISTRA (da x=0), non più al bordo destro come quando condividevano la riga col
# quadratino trasporto (quel push-a-destra serviva a tenerli visivamente separati da lui sulla
# STESSA riga — ora che sono soli sulla propria riga, quel motivo non esiste più: partire da
# sinistra è la posizione più naturale, coerente con ogni altra label/riga di questo pannello).
func _layout_tools_row() -> void:
	var tool_count := tool_slot_boxes.size()
	var natural_total_width: float = (
		float(tool_count) * TOOL_BOX_SIZE + float(max(tool_count - 1, 0)) * BOX_SPACING
	)
	var available_width: float = tools_row.size.x
	var scale: float = 1.0
	if available_width > 0.0 and natural_total_width > available_width:
		scale = available_width / natural_total_width

	var tool_size: float = TOOL_BOX_SIZE * scale
	var spacing: float = BOX_SPACING * scale
	var row_height: float = tools_row.size.y

	for i in range(tool_count):
		var box := tool_slot_boxes[i]
		box.position = Vector2(float(i) * (tool_size + spacing), (row_height - tool_size) / 2.0)
		box.size = Vector2(tool_size, tool_size)


# Spazio per il tooltip del carico, arrotondato all'intero piu' vicino (2026-09-20, richiesta utente: "30/57"
# invece di "30/56.8") — solo testo mostrato, il calcolo interno resta float.
static func _format_space(value: float) -> String:
	return str(int(roundf(value)))
