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
# OCCUPATO, carried_quantity × space_per_unit, non quello libero): vuota a zaino vuoto, piena a zaino
# pieno; tooltip occupato/massimo (invertita il 2026-09-20, richiesta utente — prima mostrava lo
# spazio libero e un carico leggero la lasciava quasi piena). Il riquadro (CarriedResourceBox, un ColorRect quadrato) è un PLACEHOLDER (richiesta
# esplicita dell'utente: "le icone delle risorse non esistono ancora") — colorato
# deterministicamente in base al nome della risorsa trasportata (_placeholder_color_for_resource),
# con l'iniziale maiuscola del nome al centro e la quantità sovrapposta in basso a destra; vuoto/
# grigio e senza testo quando carried_resource_name è "".
#
# CarryRow (2026-09-13, richiesta utente — riordino barre: capacità di trasporto in fondo, il
# riquadro trasportato sulla STESSA riga della barra, i tool in una riga a sé) — CarriedResourceBox
# e CarryBar vivono ora insieme dentro CarryRow, un HBoxContainer semplice (non un Control
# posizionato a mano come prima): bastano le size flags standard di Godot qui, CarriedResourceBox a
# dimensione fissa (custom_minimum_size) e CarryBar con size_flags_horizontal=EXPAND_FILL per
# occupare lo spazio restante — nessun bisogno dello scaling proporzionale manuale che serviva
# quando questo riquadro condivideva la riga con i 4 tool (vedi ToolSlot0..3 sotto per quel caso,
# ancora reale).
#
# ToolSlot0..3 (2026-09-08, richiesta utente) — 4 quadratini FISSI, ORA in una riga TUTTA LORO
# (tools_row, un Control puro, non un Container — vedi _layout_tools_row per il perché: serve
# comunque rimpicciolirli TUTTI con lo stesso fattore di scala quando lo spazio non basta, cosa che
# nessun Container standard di Godot fa da solo), separata dalla riga trasporto sopra (2026-09-13,
# richiesta utente — prima condividevano la riga col quadratino trasporto, ora quel riquadro è
# salito sulla riga della barra). Stile diverso apposta dal quadratino trasporto (richiesta
# esplicita): un Panel con cornice visibile (StyleBoxFlat_tool_slot) invece di un ColorRect pieno,
# "T" attenuata (alpha 0.35) come placeholder — nessun sistema di equip tool esiste ancora (vedi
# HumanIndividual.equipped_tool_count, sempre 0), quindi sono SEMPRE vuoti/placeholder, nessuno
# stato da aggiornare qui dentro.
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
# KillButton (Step 9d del piano mortalità, 2026-09-05) — tasto di DEBUG per velocizzare i test
# ("Kill (debug)", non una vera meccanica di gioco): emette kill_requested con l'individuo
# attualmente mostrato (_current_individual, salvato da show_individual — stesso principio di
# HumanPopulationInfoPanel.individual_center_requested, che porta il payload direttamente nel
# segnale invece di far riscandire GameScene per is_selected). GameScene decide se/come agire
# (GameTimeService.kill_individual_now), questo pannello resta "muto" come il resto.
signal kill_requested(individual: HumanIndividual)

# identity_label RIMOSSA (2026-09-13, richiesta utente — "perché la riga del center è vuota"):
# nome/sesso/età/fascia vivono ORA solo nell'header di GameInfoTabs (title_label, sulla STESSA
# riga del bottone 🎯), impostati da GameScene tramite set_selection_title — mai più duplicati qui
# dentro. Vedi GameScene._update_individual_panel_content per individual_identity_line.
@onready var activity_label: Label = $ActivityLabel
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
@onready var happiness_label: Label = $VitalsBox/VitalsBoxMargin/VitalsBoxContent/HappinessLabel
@onready var happiness_bar: ProgressBar = $VitalsBox/VitalsBoxMargin/VitalsBoxContent/HappinessBarMargin/HappinessBar
@onready var loyalty_label: Label = $VitalsBox/VitalsBoxMargin/VitalsBoxContent/LoyaltyLabel
@onready var loyalty_bar: ProgressBar = $VitalsBox/VitalsBoxMargin/VitalsBoxContent/LoyaltyBarMargin/LoyaltyBar
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
@onready var carried_resource_box: ColorRect = $CarryRowMargin/CarryRow/CarriedResourceBox
@onready var carried_resource_initial_label: Label = $CarryRowMargin/CarryRow/CarriedResourceBox/InitialLabel
@onready var carried_resource_quantity_label: Label = $CarryRowMargin/CarryRow/CarriedResourceBox/QuantityLabel
# tools_row (2026-09-13, richiesta utente) — rinominato da carry_and_tools_row: ora ospita SOLO i
# 4 ToolSlot, il quadratino trasportato è salito sulla riga della barra (vedi CarryRow sopra).
@onready var tools_row: Control = $ToolsRowMargin/ToolsRow

# Icona DISEGNATA correntemente inserita in carried_resource_box (2026-09-09, richiesta utente) —
# null quando la risorsa trasportata non ne ha una (vedi IconRegistry.get_resource_icon_node), nel
# qual caso si ripiega su carried_resource_initial_label come prima. Tenuta a parte (non un figlio
# fisso della scena, a differenza di InitialLabel/QuantityLabel sopra) perché QUALE icona serve
# dipende dalla risorsa trasportata, che cambia a runtime — instanziata/rimossa ad ogni refresh in
# _update_carried_resource_box.
var _carried_resource_icon_node: Control = null
# Slot tool (2026-09-08, richiesta utente) — 4 riquadri FISSI in scena (non generati da
# HumanRules.tool_slot_count, che oggi potrebbe anche valere un numero diverso da 4 per un
# eventuale futuro HumanRules non-player: questa UI resta un mockup a conteggio fisso finché non
# servirà davvero rispecchiare quel campo). Sempre vuoti/placeholder oggi (nessun sistema di equip,
# vedi HumanIndividual.equipped_tool_count) — nessuna logica di stato per slot, solo layout.
@onready var tool_slot_boxes: Array[Control] = [
	$ToolsRowMargin/ToolsRow/ToolSlot0,
	$ToolsRowMargin/ToolsRow/ToolSlot1,
	$ToolsRowMargin/ToolsRow/ToolSlot2,
	$ToolsRowMargin/ToolsRow/ToolSlot3,
]
@onready var id_label: Label = $IdLabel
@onready var mother_label: Label = $MotherLabel
@onready var father_label: Label = $FatherLabel
@onready var partner_label: Label = $PartnerLabel
@onready var house_label: Label = $HouseLabel
@onready var kill_button: Button = $KillButton

var _current_individual: HumanIndividual


func _ready() -> void:
	kill_button.text = tr("individual_kill_debug_button")
	kill_button.pressed.connect(func(): kill_requested.emit(_current_individual))
	# Layout riga tool (2026-09-08, semplificata 2026-09-13 quando il quadratino trasporto è
	# uscito da questa riga) — ricalcolato ad ogni resize del pannello (larghezza sidebar, non
	# fissa) oltre che una volta qui subito: vedi _layout_tools_row.
	tools_row.resized.connect(_layout_tools_row)
	_layout_tools_row()
	clear()


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
# testa al file. carried_resource_name/carried_quantity: letti direttamente
# dall'HumanIndividual passato (stesso identico stato grezzo, nessuna risoluzione necessaria).
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
	skill_leadership: float, skill_builder: float, skill_management: float,
	skill_transporter: float, skill_gathering: float, skill_cognition: float,
	skill_hunting: float,
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

	happiness_label.text = tr("individual_happiness_label")
	happiness_bar.max_value = max_happiness
	happiness_bar.value = current_happiness
	happiness_bar.tooltip_text = "%d/%d" % [int(current_happiness), int(max_happiness)]

	loyalty_label.text = tr("individual_loyalty_label")
	loyalty_bar.max_value = max_loyalty
	loyalty_bar.value = current_loyalty
	loyalty_bar.tooltip_text = "%d/%d" % [int(current_loyalty), int(max_loyalty)]

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

	# Capacità di trasporto (2026-09-13, richiesta utente — spostata in FONDO alle barre, dopo i 5
	# nuovi parametri vitali: nessun motivo funzionale, solo l'ordine visivo concordato) — la barra
	# stessa vive ora dentro CarryRow insieme a CarriedResourceBox (vedi commento in testa al file),
	# ma resta un ProgressBar identico a prima: stessa formula/stesso tooltip.
	carry_label.text = tr("individual_carry_label")
	carry_bar.max_value = max_carry_capacity
	carry_bar.value = used_carry_space
	carry_bar.tooltip_text = "%s/%s" % [_format_space(used_carry_space), _format_space(max_carry_capacity)]

	_update_carried_resource_box(individual.carried_resource_name, individual.carried_quantity)
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

	var group := individual.source_group_ref
	var folk_id: int = group.folk_ref.id if group != null and group.folk_ref != null else -1
	var group_id: int = group.id if group != null else -1
	id_label.text = tr("individual_id_label").format({"id": individual.id, "folk": _format_id(folk_id), "group": _format_id(group_id)})
	mother_label.text = tr("individual_mother_id_label").format({"id": _format_id(individual.mother_id)})
	father_label.text = tr("individual_father_id_label").format({"id": _format_id(individual.father_id)})
	partner_label.text = tr("individual_partner_id_label").format({"id": _format_id(individual.partner_id)})
	# house_id (2026-09-12, richiesta utente: "metti id house nell'info panel di individual") —
	# STESSO trattamento/STESSA sentinella -1 -> "—" di mother/father/partner sopra (_format_id).
	house_label.text = tr("individual_house_id_label").format({"id": _format_id(individual.house_id)})


func clear() -> void:
	visible = false
	_current_individual = null


# Sentinella -1 (genitore/gruppo/partner sconosciuto o non applicabile, vedi HumanIndividual) resa
# come "—" invece del numero grezzo — poco leggibile per chi guarda il pannello, "-1" sembra un
# errore piu' che un "non applicabile".
func _format_id(value: int) -> String:
	return "—" if value < 0 else str(value)


# Dimensioni/spaziatura NATURALI dei 4 tool slot (2026-09-08, richiesta utente) — usate come punto
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
# vive sul CONTENITORE (carried_resource_box), non sull'icona disegnata (che ha mouse_filter =
# IGNORE apposta, vedi PebbleIcon/StickIcon._ready): un Control con IGNORE non riceve mai hover,
# quindi il tooltip andrebbe perso se vivesse lì. "" quando non si trasporta nulla (nessun tooltip
# su un riquadro vuoto).
func _update_carried_resource_box(resource_name: String, quantity: int) -> void:
	if _carried_resource_icon_node != null:
		_carried_resource_icon_node.queue_free()
		_carried_resource_icon_node = null

	if resource_name == "":
		carried_resource_box.color = EMPTY_CARRIED_RESOURCE_COLOR
		carried_resource_box.tooltip_text = ""
		carried_resource_initial_label.visible = true
		carried_resource_initial_label.text = ""
		carried_resource_quantity_label.visible = false
		return

	carried_resource_box.color = IconRegistry.get_resource_color(resource_name)
	carried_resource_box.tooltip_text = IconRegistry.get_resource_display_name(resource_name)

	var icon_node: Control = IconRegistry.get_resource_icon_node(resource_name)
	if icon_node != null:
		carried_resource_initial_label.visible = false
		carried_resource_initial_label.text = ""
		_carried_resource_icon_node = icon_node
		carried_resource_box.add_child(icon_node)
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
		carried_resource_initial_label.visible = true
		var icon: String = IconRegistry.get_resource_icon(resource_name)
		carried_resource_initial_label.text = icon if icon != "" else resource_name.substr(0, 1).to_upper()

	carried_resource_quantity_label.text = str(quantity)
	carried_resource_quantity_label.visible = true


# Posiziona/dimensiona i 4 quadratini tool dentro tools_row (2026-09-08, richiesta utente —
# SEMPLIFICATA 2026-09-13 quando il quadratino trasporto è uscito da questa riga, vedi CarryRow in
# testa al file: prima questa funzione posizionava ANCHE lui, ora si occupa solo dei 4 tool)
# — Control semplice, non un Container: i figli sono posizionati/dimensionati A MANO qui invece
# che affidati al layout automatico di un HBoxContainer, perché serve un comportamento che nessun
# Container standard di Godot offre da solo: quando la larghezza disponibile non basta per la
# dimensione NATURALE di tutti e 4 i quadratini, li si rimpicciolisce TUTTI con lo STESSO fattore
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


# Spazio per il tooltip del carico: un decimale solo se serve ("4", "2.5"), mai "4.0" — lo spazio occupato
# puo' essere frazionario (space_per_unit 0.5), un %d lo troncherebbe.
static func _format_space(value: float) -> String:
	return ("%.1f" % value).rstrip("0").rstrip(".")
