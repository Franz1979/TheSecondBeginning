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
# principio "muto" di stamina_bar sopra: max_carry_capacity/free_carry_capacity arrivano già
# risolti dal chiamante (GameScene, che fa il lookup di SecondaryResourceRules.space_per_unit per
# calcolare lo spazio occupato — questo pannello non conosce SecondaryResourceRules/
# CaloricCalculator). La barra si SVUOTA man mano che si trasporta di più (mostra lo spazio
# LIBERO, non quello occupato) — stessa logica di stamina_bar, che si svuota man mano che si
# consuma. Il riquadro sotto (CarriedResourceBox, un ColorRect quadrato) è un PLACEHOLDER
# (richiesta esplicita dell'utente: "le icone delle risorse non esistono ancora") — colorato
# deterministicamente in base al nome della risorsa trasportata (_placeholder_color_for_resource),
# con l'iniziale maiuscola del nome al centro e la quantità sovrapposta in basso a destra; vuoto/
# grigio e senza testo quando carried_resource_name è "".
#
# ToolSlot0..3 (2026-09-08, richiesta utente) — 4 quadratini FISSI sulla STESSA riga del
# quadratino trasporto (carry_and_tools_row, un Control puro, non un Container — vedi
# _layout_carry_and_tools_row per il perché), allineati a destra mentre il trasporto resta a
# sinistra. Stile diverso apposta dal quadratino trasporto (richiesta esplicita): un Panel con
# cornice visibile (StyleBoxFlat_tool_slot) invece di un ColorRect pieno, "T" attenuata (alpha
# 0.35) come placeholder — nessun sistema di equip tool esiste ancora (vedi HumanIndividual.
# equipped_tool_count, sempre 0), quindi sono SEMPRE vuoti/placeholder, nessuno stato da
# aggiornare qui dentro. Se la larghezza del pannello non basta per tutti e 5 i quadratini a
# dimensione naturale, vengono rimpiccioliti TUTTI con lo stesso fattore di scala (mai tagliati
# fuori) — vedi _layout_carry_and_tools_row.
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

@onready var sex_label: Label = $SexLabel
@onready var age_label: Label = $AgeLabel
@onready var activity_label: Label = $ActivityLabel
@onready var stamina_label: Label = $StaminaLabel
@onready var stamina_bar: ProgressBar = $StaminaBarMargin/StaminaBar
@onready var carry_label: Label = $CarryLabel
@onready var carry_bar: ProgressBar = $CarryBarMargin/CarryBar
@onready var carry_and_tools_row: Control = $CarryAndToolsRowMargin/CarryAndToolsRow
@onready var carried_resource_box: ColorRect = $CarryAndToolsRowMargin/CarryAndToolsRow/CarriedResourceBox
@onready var carried_resource_initial_label: Label = $CarryAndToolsRowMargin/CarryAndToolsRow/CarriedResourceBox/InitialLabel
@onready var carried_resource_quantity_label: Label = $CarryAndToolsRowMargin/CarryAndToolsRow/CarriedResourceBox/QuantityLabel

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
	$CarryAndToolsRowMargin/CarryAndToolsRow/ToolSlot0,
	$CarryAndToolsRowMargin/CarryAndToolsRow/ToolSlot1,
	$CarryAndToolsRowMargin/CarryAndToolsRow/ToolSlot2,
	$CarryAndToolsRowMargin/CarryAndToolsRow/ToolSlot3,
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
	# Layout riga trasporto+tool (2026-09-08) — ricalcolato ad ogni resize del pannello (larghezza
	# sidebar, non fissa) oltre che una volta qui subito: vedi _layout_carry_and_tools_row.
	carry_and_tools_row.resized.connect(_layout_carry_and_tools_row)
	_layout_carry_and_tools_row()
	clear()


# Prende l'HumanIndividual intero (non piu' i soli name/sex, richiesta utente 2026-09-02: servono
# anche id/mother_id/father_id/partner_id/source_group_ref, tutti gia' sull'oggetto) — age/
# age_band restano calcolati dal chiamante (richiedono current_year/HumanRules, che questo
# pannello non conosce, stesso principio di prima). max_stamina/current_stamina stesso
# principio: gia' risolti dal chiamante (HumanCalculator.get_max_stamina), vedi commento
# stamina_bar sopra.
#
# activity_text (2026-09-07, richiesta utente — "cosa sta facendo questo individuo") già risolto e
# tr()-ato dal chiamante (GameScene, via HumanIndividual.current_task.get_activity_description() o
# la stringa "a riposo" se current_task è null) — stesso identico principio "questo pannello riceve
# solo dati già pronti" di ogni altro parametro qui.
# max_carry_capacity/free_carry_capacity (2026-09-08, richiesta utente) — stesso principio di
# max_stamina/current_stamina sopra: già risolti dal chiamante. free_carry_capacity (non
# used_carry_space) perché la barra mostra spazio LIBERO, non occupato — vedi commento su
# carry_bar in testa al file. carried_resource_name/carried_quantity: letti direttamente
# dall'HumanIndividual passato (stesso identico stato grezzo, nessuna risoluzione necessaria).
func show_individual(
	individual: HumanIndividual, age: int, age_band: HumanTypes.AgeBand,
	max_stamina: float, current_stamina: float, activity_text: String,
	max_carry_capacity: float, free_carry_capacity: float
) -> void:
	visible = true
	_current_individual = individual
	sex_label.text = tr("sex_label").format({"sex": tr("sex_female") if individual.sex == HumanTypes.Sex.FEMALE else tr("sex_male")})
	# Incinta sulla STESSA riga dell'age_band (richiesta utente, 2026-09-06) — non più una
	# PregnantLabel separata sotto: appesa al valore di {band} invece che a un nodo/riga a parte.
	var band_text: String = HumanTypes.AgeBand.keys()[age_band].capitalize()
	if individual.is_pregnant:
		band_text += ", " + tr("pregnant")
	age_label.text = tr("individual_age_label").format({"age": age, "band": band_text})
	activity_label.text = activity_text

	stamina_label.text = tr("individual_stamina_label")
	stamina_bar.max_value = max_stamina
	stamina_bar.value = current_stamina
	stamina_bar.tooltip_text = "%d/%d" % [int(current_stamina), int(max_stamina)]

	carry_label.text = tr("individual_carry_label")
	carry_bar.max_value = max_carry_capacity
	carry_bar.value = free_carry_capacity
	carry_bar.tooltip_text = "%d/%d" % [int(free_carry_capacity), int(max_carry_capacity)]
	_update_carried_resource_box(individual.carried_resource_name, individual.carried_quantity)
	# Ri-layout esplicito (2026-09-08) — oltre al collegamento a carry_and_tools_row.resized in
	# _ready(): coprire anche il caso "la riga non cambia dimensione tra due individui mostrati in
	# sequenza" (nessun resize emesso, ma il pannello potrebbe comunque non essere mai stato
	# disegnato mentre era nascosto — clear() lo mette invisible, un Control invisibile non
	# garantisce dimensioni aggiornate). Economico (poche assegnazioni di position/size), nessun
	# problema a richiamarlo qui ad ogni refresh.
	_layout_carry_and_tools_row()

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


# Dimensioni/spaziatura NATURALI (2026-09-08, richiesta utente — slot tool) — usate come punto di
# partenza da _layout_carry_and_tools_row sotto, che le rimpicciolisce TUTTE proporzionalmente
# (stesso fattore di scala per il quadratino trasporto e i 4 tool) quando non entrano nella
# larghezza disponibile del pannello, invece di tagliarle fuori.
const CARRY_BOX_SIZE: float = 36.0
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


# Posiziona/dimensiona il quadratino trasporto (sinistra) e i 4 quadratini tool (destra) dentro
# carry_and_tools_row (2026-09-08, richiesta utente) — Control semplice, non un Container: i
# figli sono posizionati/dimensionati A MANO qui invece che affidati al layout automatico di un
# HBoxContainer, perché serve un comportamento che nessun Container standard di Godot offre da
# solo: quando la larghezza disponibile non basta per la dimensione NATURALE di tutti e 5 i
# quadratini, li si rimpicciolisce TUTTI con lo STESSO fattore di scala (mai un sottoinsieme
# tagliato fuori, richiesta esplicita dell'utente) — un HBoxContainer con size_flags_horizontal
# EXPAND_FILL comprimerebbe solo i figli "expand", non li scalerebbe proporzionalmente insieme,
# e comunque non saprebbe spingere SOLO il gruppo tool a destra mantenendo il trasporto a sinistra
# senza un terzo nodo spaziatore ad hoc.
#
# Se c'è spazio a sufficienza (available_width >= larghezza naturale totale): dimensioni naturali,
# i tool si allineano al bordo destro della riga con uno spazio vuoto in mezzo. Se non basta: scale
# < 1.0 applicato a box/spaziatura di ENTRAMBI i gruppi allo stesso modo, i tool restano subito a
# destra del quadratino trasporto (nessun vuoto residuo). La formula `max(...)` sotto copre
# entrambi i casi con un solo calcolo, senza un ramo if/else esplicito: quando c'è spazio la
# sottrazione (available_width - tools_group_width) domina (spinge a destra); quando è tutto
# compresso, il minimo garantito (carry_size + spacing) coincide già col punto in cui i tool
# finiscono di essere spinti a destra, dato che available_width è stato appena reso capiente esatto
# da `scale`.
func _layout_carry_and_tools_row() -> void:
	var tool_count := tool_slot_boxes.size()
	var natural_total_width: float = (
		CARRY_BOX_SIZE + BOX_SPACING + float(tool_count) * TOOL_BOX_SIZE + float(max(tool_count - 1, 0)) * BOX_SPACING
	)
	var available_width: float = carry_and_tools_row.size.x
	var scale: float = 1.0
	if available_width > 0.0 and natural_total_width > available_width:
		scale = available_width / natural_total_width

	var carry_size: float = CARRY_BOX_SIZE * scale
	var tool_size: float = TOOL_BOX_SIZE * scale
	var spacing: float = BOX_SPACING * scale
	var row_height: float = carry_and_tools_row.size.y

	carried_resource_box.position = Vector2(0.0, (row_height - carry_size) / 2.0)
	carried_resource_box.size = Vector2(carry_size, carry_size)

	var tools_group_width: float = float(tool_count) * tool_size + float(max(tool_count - 1, 0)) * spacing
	var tools_start_x: float = max(available_width - tools_group_width, carry_size + spacing)
	for i in range(tool_count):
		var box := tool_slot_boxes[i]
		box.position = Vector2(tools_start_x + float(i) * (tool_size + spacing), (row_height - tool_size) / 2.0)
		box.size = Vector2(tool_size, tool_size)
