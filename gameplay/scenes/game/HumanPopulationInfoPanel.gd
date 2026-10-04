class_name HumanPopulationInfoPanel
extends VBoxContainer

# Corpo del pannello popolazione dentro GameInfoTabs.population_tab — stesso principio "muto" di
# VegetationInfoPanel/HumanIndividualInfoPanel (istanziato dinamicamente da GameScene, riceve solo
# dati già risolti). Nessun tr(): stesso trattamento hardcoded degli altri pannelli di ispezione,
# nessuna CSV di traduzione esiste ancora.
#
# Contenuto base (totale + maschi/femmine + bottone +/-, tutti sulla stessa riga — richiesta
# utente, 2026-09-02) sempre visibile aprendo la scheda — elenco completo dietro il bottone "+"/
# "-" (richiesta utente, 2026-09-01), nessuno scroll/paginazione (5/10/20 individui ci stanno
# comodamente in una lista semplice — da rivedere solo quando servirà davvero gestire numeri più
# grandi). Maschi/femmine mostrati come simbolo ♂/♀ colorato (blu/rosa, richiesta utente,
# 2026-09-02) invece del testo "Males:"/"Females:" — più compatto sulla stessa riga del totale.
#
# Interazione riga per riga (richiesta utente, 2026-09-04): un bottone "🎯" per riga (vedi
# individual_center_requested/_on_center_button_pressed sotto) — prima "nessuna interazione riga
# per riga, solo consultazione", ora sì, ma nella stessa forma "muta" del resto del pannello: la
# riga emette solo un segnale, non decide mai da sé selezione/camera (vedi il segnale per il
# perché).
#
# Popolato UNA VOLTA da GameScene subito dopo il seeding (show_population), non richiesto ancora un
# refresh dinamico: oggi nessuna simulazione umana cambia population/individui nel tempo (nessuna
# nascita/morte implementata) — se e quando arriverà, show_population() resta comunque l'unico
# punto da richiamare di nuovo, nessun'altra modifica qui.

const COLOR_MALE := Color(0.25, 0.55, 0.95)
const COLOR_FEMALE := Color(0.95, 0.4, 0.65)

# Alert visivo per housing_label (2026-09-12, richiesta utente) — rosso quando i pipottini vivi
# superano i posti letto disponibili (vedi show_population), stesso principio "colore acceso solo
# per segnalare un problema" già in uso altrove nel progetto (es. DEBUG_LABEL_COLOR in
# TaskDebugPanel, anche se per un motivo diverso).
const COLOR_HOUSING_ALERT := Color(0.9, 0.3, 0.3)

# Bottone per-riga "centra e seleziona" (richiesta utente, 2026-09-04: "un piccolo button a fianco
# di ognuno... al clic mi centri su di loro e mi selezioni il cliccato" — a differenza del
# generico "🎯" della PrimaryActionsBar, che centra solo sull'ULTIMO selezionato, questo permette
# di saltare direttamente a un individuo specifico dalla lista). Stessa icona del bottone
# generale (vedi GameScene._center_camera_on_individual/PrimaryActionsBar) per coerenza visiva —
# stesso concetto, non un'icona nuova da imparare.
const CENTER_BUTTON_TEXT := "🎯"

# Simbolo "ha una casa" per riga (2026-09-12, richiesta utente) — stessa icona già in uso per la
# scheda 🏠/BuildingsInfoPanel, coerenza visiva: lo stesso glifo identifica "casa" ovunque nel
# progetto, non un'icona nuova da imparare. Mostrato SOLO se member.house_id != -1 (stessa
# sentinella "nessuna casa" già in uso ovunque per questo campo).
const HOUSE_ICON_TEXT := "🏠"

# Riga task per-individuo (2026-09-18, richiesta utente — "accanto al pipottino anche la task che
# sta facendo... scrivilo nella riga sotto un po' indentata e metti un button hide tasks che
# ricompatta le righe") — SOTTO la riga esistente, non affiancata: allargherebbe il pannello, cosa
# esplicitamente da evitare (richiesta utente). Colore/attenuazione IDENTICI a QueuedTasksLabel di
# HumanIndividualInfoPanel (stesso identico concetto — "testo secondario sulla task" — riusato qui
# invece di inventarne un altro), solo font_size più piccolo (spazio di riga più stretto qui).
const COLOR_TASK_DIM := Color(1, 1, 1, 0.65)
const TASK_ROW_INDENT: float = 24.0
# Stessa stringa già mostrata da GameScene per HumanIndividualInfoPanel.activity_text quando
# current_task è null (tr("task_activity_idle") = "A riposo") — hardcoded qui invece di tr()
# perché questo intero file non usa tr() (vedi commento in testa, "nessuna CSV di traduzione"),
# ma il TESTO resta lo stesso per non mostrare due formulazioni diverse della stessa cosa.
const IDLE_TASK_TEXT := "A riposo"

# Rompe il principio "componente muto" dichiarato in testa al file SOLO per il minimo indispensabile
# (stesso schema già in uso per MinimapPanel.cell_clicked): questo pannello non decide MAI da sé
# selezione/camera, si limita a segnalare "l'utente ha chiesto questo individuo" — GameScene resta
# l'unica a decidere cosa fare col click (stesso schema di _on_minimap_cell_clicked).
signal individual_center_requested(individual: HumanIndividual)

# Ordinamento dell'elenco (2026-10-04, richiesta utente): pulsante a icona sulla riga del Folk (MenuButton piatto, stesso
# stile del 🎯 di riga) con una tendina delle opzioni, quella attiva spuntata. L'opzione scelta vive in
# GameData.population_list_sort (salvata con la partita): il pannello la riceve in show_population e segnala un cambio
# con sort_changed, GameScene la salva e ripopola. A parità di criterio ordine per id, così la lista non salta.
# Nuova opzione (es. famiglia, skill): una voce in SORT_OPTIONS, un caso in _sort_less, la chiave di traduzione.
signal sort_changed(sort_id: String)
const SORT_BUTTON_TEXT := "⇅"
const DEFAULT_SORT_ID := "age"
const SORT_OPTIONS: Array[Dictionary] = [
	{"id": "age", "label_key": "population_sort_age"},
	{"id": "name", "label_key": "population_sort_name"},
	{"id": "house", "label_key": "population_sort_house"},
]

@onready var folk_label: Label = $FolkRow/FolkLabel
@onready var hide_tasks_button: Button = $FolkRow/HideTasksButton
@onready var group_label: Label = $SummaryRow/GroupLabel
@onready var male_label: Label = $SummaryRow/MaleLabel
@onready var female_label: Label = $SummaryRow/FemaleLabel
@onready var expand_button: Button = $SummaryRow/ExpandButton
@onready var housing_label: Label = $SummaryRow/HousingLabel
@onready var list_container: VBoxContainer = $ListContainer

var _expanded: bool = false
# Mostrate di default (2026-09-18, richiesta utente: il button si chiama "hide tasks" — parte
# dallo stato "visibili", il click le ricompatta, non il contrario) — stesso principio del
# testo che si scambia sotto (_on_hide_tasks_pressed), mai un terzo stato intermedio.
var _show_tasks: bool = true
# Riferimenti diretti ai MarginContainer indentati (2026-09-18) — evita di dover ricostruire
# l'intera lista per un semplice toggle di visibilità: stesso principio "aggiorna, non ricrea"
# già seguito da housing_label.add/remove_theme_color_override sopra, qui applicato a un Array
# di nodi invece di un singolo Label.
var _task_rows: Array[Control] = []
# Larghezza del CASO PEGGIORE (2026-09-20, richiesta utente — la sidebar non deve allargarsi e restringersi):
# la riga piu' larga tra "riga individuo" e "riga task indentata", misurata a prescindere da lista aperta/chiusa e
# task mostrate/nascoste, e MAI ridotta (solo crescente, nella sessione). Si riporta come larghezza minima del
# pannello (custom_minimum_size.x), cosi' la tab popolazione occupa sempre la larghezza che avrebbe con tutto
# aperto. Vedi show_population.
var _widest_row: float = 0.0
var _sort_id: String = DEFAULT_SORT_ID
var _sort_button: MenuButton = null

# Pulsanti del gruppo "Azioni" sulle righe (2026-10-04, richiesta utente): le stesse azioni della barra dei comandi
# (CommandBar.ACTIONS, unica fonte: un'azione aggiunta lì compare anche qui), come piccole icone, solo sulla riga sotto
# il mouse. Lo stato di ogni pulsante (assente/spento/acceso e spiegazione) lo chiede a GameScene
# (`command_state_provider`, Callable(abitante, action_id) -> {"shown", "enabled", "tooltip"}) nel momento in cui la
# riga diventa quella sotto il mouse; il clic emette command_requested e GameScene dà l'ordine a quell'abitante con lo
# stesso flusso della barra.
# SOVRAPPOSTI (2026-10-04, richiesta utente — prima stavano dentro la riga e ne aumentavano l'altezza): un solo riquadro
# di pulsanti (_command_overlay, top_level: fuori dal flusso dell'impaginazione) posato sopra la riga sotto il mouse, a
# destra, a sinistra dell'icona della casa, centrato in verticale sull'intera riga dell'abitante (nome più task). La
# riga non cambia mai altezza: sotto i pulsanti il testo si tronca con i puntini grazie a due spaziatori (riga del nome e
# riga del task) che prendono solo la larghezza occupata dai pulsanti. Con i task nascosti la riga è una sola e i
# pulsanti si riducono alla sua altezza.
signal command_requested(individual: HumanIndividual, action_id: StringName)
const COMMAND_BUTTON_SIZE: float = 18.0
const COMMAND_BUTTON_SEPARATION: int = 1
const COMMAND_BUTTON_DISABLED_MODULATE := Color(1, 1, 1, 0.35)
var command_state_provider: Callable = Callable()
# Una voce per riga: {"member", "wrapper" (blocco nome + task), "name_row", "house_icon" (Control o null),
# "name_spacer", "task_spacer"}.
var _command_rows: Array[Dictionary] = []
var _hovered_command_row: int = -1
var _command_overlay: HBoxContainer = null


func _ready() -> void:
	_command_overlay = HBoxContainer.new()
	_command_overlay.top_level = true
	_command_overlay.add_theme_constant_override("separation", COMMAND_BUTTON_SEPARATION)
	_command_overlay.visible = false
	add_child(_command_overlay)
	male_label.add_theme_color_override("font_color", COLOR_MALE)
	female_label.add_theme_color_override("font_color", COLOR_FEMALE)
	expand_button.text = "+"
	expand_button.pressed.connect(_on_expand_pressed)
	list_container.visible = false
	hide_tasks_button.text = "Nascondi task" if _show_tasks else "Mostra task"
	hide_tasks_button.pressed.connect(_on_hide_tasks_pressed)
	# Disabilitato quando la lista pipottini è compattata (2026-09-19, richiesta utente: "se il
	# button + è raggruppato, spegni il pulsante mostra/nascondi task, tanto non funziona") — con
	# list_container invisibile non c'è alcuna riga task da mostrare/nascondere, quindi il click non
	# avrebbe alcun effetto visibile: disabled invece di semplicemente nasconderlo, così il player
	# vede comunque che il controllo esiste ma non è applicabile finché la lista resta chiusa.
	hide_tasks_button.disabled = not _expanded
	_build_sort_button()


# Pulsante dell'ordinamento, accanto a "Nascondi task" sulla riga del Folk: piatto e stretto come il 🎯 di riga, così
# sta nello spazio della riga (FolkLabel va a capo prima di allargare il pannello).
func _build_sort_button() -> void:
	_sort_button = MenuButton.new()
	_sort_button.text = SORT_BUTTON_TEXT
	_sort_button.flat = true
	_sort_button.add_theme_font_size_override("font_size", 10)
	_sort_button.custom_minimum_size = Vector2(20, 0)
	var popup := _sort_button.get_popup()
	for i in SORT_OPTIONS.size():
		popup.add_radio_check_item(tr(String(SORT_OPTIONS[i]["label_key"])), i)
	popup.id_pressed.connect(_on_sort_option_pressed)
	$FolkRow.add_child(_sort_button)
	_refresh_sort_button()


func _sort_option_index(sort_id: String) -> int:
	for i in SORT_OPTIONS.size():
		if SORT_OPTIONS[i]["id"] == sort_id:
			return i
	return -1


func _refresh_sort_button() -> void:
	if _sort_button == null:
		return
	var active := maxi(_sort_option_index(_sort_id), 0)
	var popup := _sort_button.get_popup()
	for i in SORT_OPTIONS.size():
		popup.set_item_checked(popup.get_item_index(i), i == active)
	_sort_button.tooltip_text = tr("population_sort_tooltip").format({"option": tr(String(SORT_OPTIONS[active]["label_key"]))})


func _on_sort_option_pressed(option_id: int) -> void:
	if option_id < 0 or option_id >= SORT_OPTIONS.size():
		return
	var sort_id: String = SORT_OPTIONS[option_id]["id"]
	if sort_id == _sort_id:
		return
	_sort_id = sort_id
	_refresh_sort_button()
	sort_changed.emit(sort_id)


# Copia di `individuals` nell'ordine dell'opzione attiva (id sconosciuto = predefinito).
func _sorted_individuals(individuals: Array[HumanIndividual]) -> Array[HumanIndividual]:
	var sorted: Array[HumanIndividual] = individuals.duplicate()
	var sort_id := _sort_id if _sort_option_index(_sort_id) >= 0 else DEFAULT_SORT_ID
	sorted.sort_custom(func(a: HumanIndividual, b: HumanIndividual) -> bool: return _sort_less(sort_id, a, b))
	return sorted


# true se `a` va prima di `b`. Età: più anziani prima (anno di nascita minore). Nome: alfabetico senza maiuscole/
# minuscole. Casa: per id di casa, senza casa in fondo, dentro la casa per età. Sempre id a parità.
func _sort_less(sort_id: String, a: HumanIndividual, b: HumanIndividual) -> bool:
	match sort_id:
		"name":
			var cmp := a.name.naturalnocasecmp_to(b.name)
			if cmp != 0:
				return cmp < 0
		"house":
			var a_homeless := a.house_id == -1
			var b_homeless := b.house_id == -1
			if a_homeless != b_homeless:
				return b_homeless
			if a.house_id != b.house_id:
				return a.house_id < b.house_id
			if a.birth_year_virtual != b.birth_year_virtual:
				return a.birth_year_virtual < b.birth_year_virtual
		_:
			if a.birth_year_virtual != b.birth_year_virtual:
				return a.birth_year_virtual < b.birth_year_virtual
	return a.id < b.id


# total_count separato da individuals.size() deliberatamente (anche se oggi coincidono sempre:
# ogni individuo generato dal seeding è materializzato) — total_count è il dato di GRUPPO
# (HumanPopulationGroup, equivalente umano di PopulationGroup.population lato animale), la fonte
# di verità concettualmente corretta per "quanti sono in totale"; individuals resta necessario
# comunque per il conteggio maschi/femmine e l'elenco, dati che il gruppo non tiene ancora.
#
# folk_id/group_id (richiesta utente, 2026-09-02: "come quando clicchi sul pipottino" — stesso dato
# di HumanIndividualInfoPanel.show_individual, "Folk %s, Group %s", passati qui già risolti da
# GameScene invece dell'intero Folk/HumanPopulationGroup: questo pannello, come gli altri, riceve
# solo dati già pronti, mai gli oggetti di gioco stessi). Due righe (richiesta utente, 2026-09-02):
# prima riga solo "Folk %s" (FolkLabel, da sé — un solo Folk esiste ancora, niente altro da
# affiancargli); seconda riga "Group %s: total %d" insieme a ♂/♀ e al bottone +/- (GroupLabel,
# stessa riga di prima, solo rinominata da TotalLabel — il totale/le indicazioni di genere/il
# bottone d'espansione restano tutti insieme, il totale si è solo spostato da "Folk" a "Group").
#
# era_effective_age_band_durations_male/female (bugfix, richiesta utente 2026-09-04 — sostituisce
# il precedente parametro human_rules: HumanRules, usato SOLO per HumanCalculator.get_age_band, che
# leggeva le durate age-band grezze ignorando l'Era corrente): durate GIA' scalate per l'Era,
# tipicamente game_data.era_effective_age_band_durations_male/female — vedi GameScene.
# housing_capacity (2026-09-12, richiesta utente — "quanto spazio abitativo esiste") — già
# risolto dal chiamante (GameScene, somma di rules.max_residents sui soli edifici RESIDENTIAL
# COMPLETI, vedi _refresh_population_panel): questo pannello resta "muto" come dichiarato in testa
# al file, non conosce Building/BuildingRules, riceve solo l'intero già pronto. Messo QUI (non nel
# pannello Edifici) perché "quanti pipottini vivi contro quanti posti letto esistono" è per natura
# un dato sulla POPOLAZIONE, non sugli edifici in generale (che includono anche political/storage,
# mai rilevanti per questo conteggio) — vedi housing_label sotto per il formato scelto.
func show_population(
	total_count: int, individuals: Array[HumanIndividual], current_year: int,
	era_effective_age_band_durations_male: Array[float], era_effective_age_band_durations_female: Array[float],
	folk_id: int, group_id: int, housing_capacity: int, sort_id: String = DEFAULT_SORT_ID
) -> void:
	# Ordinamento scelto (GameData.population_list_sort, vedi SORT_OPTIONS).
	if sort_id != _sort_id:
		_sort_id = sort_id
		_refresh_sort_button()
	var male_count := 0
	var female_count := 0
	for member in individuals:
		if member.sex == HumanTypes.Sex.MALE:
			male_count += 1
		else:
			female_count += 1
	folk_label.text = "Folk %s" % _format_id(folk_id)
	group_label.text = "Group %s: total %d" % [_format_id(group_id), total_count]
	male_label.text = "♂ " + str(male_count)
	female_label.text = "♀ " + str(female_count)
	# "🏠 10/4" = 10 pipottini vivi in totale contro 4 posti letto disponibili (somma rules.
	# max_residents sui residenziali completi) — richiesta utente 2026-09-12, REVISIONATA rispetto
	# alla versione precedente (che mostrava "con casa/capacità", non "vivi/capacità": chi non ha
	# ancora una casa assegnata — vedi AssignHouseService, in attesa di un posto libero — va comunque
	# contato qui, altrimenti il numero sottostimerebbe quanti posti letto servirebbero DAVVERO).
	# ROSSO quando total_count > housing_capacity (richiesta utente, confermato esplicitamente: 10
	# pipottini/4 posti è il caso ALLARME, non il contrario) — nessun posto per tutti, alert
	# visivo immediato; altrimenti colore di default del tema (posti sufficienti o in eccesso).
	housing_label.text = "🏠 %d/%d" % [total_count, housing_capacity]
	if total_count > housing_capacity:
		housing_label.add_theme_color_override("font_color", COLOR_HOUSING_ALERT)
	else:
		housing_label.remove_theme_color_override("font_color")
	housing_label.tooltip_text = "%d pipottini vivi su %d posti letto totali (edifici residenziali completi)%s" % [
		total_count, housing_capacity,
		" — non bastano per tutti!" if total_count > housing_capacity else ""
	]

	for child in list_container.get_children():
		child.queue_free()
	_task_rows.clear()
	_command_rows.clear()
	_hovered_command_row = -1
	_clear_command_overlay()
	for member in _sorted_individuals(individuals):
		var age: int = current_year - member.birth_year_virtual
		var age_band := HumanCalculator.get_age_band(
			era_effective_age_band_durations_male, era_effective_age_band_durations_female, member.sex, float(age)
		)
		# Riga = HBoxContainer (era un Label nudo) — richiesta utente 2026-09-04: bottone
		# "centra e seleziona" per riga, vedi individual_center_requested sopra. label.
		# size_flags_horizontal EXPAND_FILL così il bottone/simbolo casa restano compatti invece di
		# essere spinti fuori dalla larghezza del testo. Ordine RIVISTO (2026-09-12, richiesta
		# utente): centra a SINISTRA del nome (era a destra), simbolo casa a destra — "F"/"M" al
		# posto di "Female"/"Male" e "age %d" ridotto al solo numero, per guadagnare spazio
		# orizzontale sulla riga (stessa richiesta).
		var row := HBoxContainer.new()
		# Rimpicciolito (richiesta utente, 2026-09-06): il Button di default (padding/stylebox
		# pieno) era troppo alto rispetto alla label a fianco, allargando visibilmente ogni riga
		# della lista — flat=true toglie lo stylebox normale (niente più padding verticale extra),
		# font_size ridotto allo stesso valore della label, custom_minimum_size stringe la
		# larghezza al minimo utile per l'emoji invece di lasciarla al default del tema.
		var center_button := Button.new()
		center_button.text = CENTER_BUTTON_TEXT
		center_button.tooltip_text = "Centra e seleziona"
		center_button.flat = true
		center_button.add_theme_font_size_override("font_size", 10)
		center_button.custom_minimum_size = Vector2(20, 0)
		center_button.pressed.connect(_on_center_button_pressed.bind(member))
		row.add_child(center_button)

		var label := Label.new()
		label.add_theme_font_size_override("font_size", 10)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Su una riga, troncato con i puntini (2026-10-04): sotto i pulsanti delle azioni il testo si accorcia invece di
		# andare a capo, così la riga non cambia altezza.
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.text = "%s — %s, %d (%s)" % [
			member.name,
			"F" if member.sex == HumanTypes.Sex.FEMALE else "M",
			age,
			HumanTypes.AgeBand.keys()[age_band].capitalize(),
		]
		row.add_child(label)

		# Spaziatore largo quanto i pulsanti delle azioni quando la riga è sotto il mouse, a sinistra della casa.
		var name_spacer := Control.new()
		name_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(name_spacer)
		var house_icon_node: Control = null

		# Simbolo casa (2026-09-12, richiesta utente) — SOLO se ha una casa assegnata, nessun
		# placeholder/spazio vuoto per chi non ce l'ha (stesso principio "assente = niente" già
		# seguito altrove, es. is_pregnant sulla stessa riga dell'age_band in HumanIndividualInfoPanel).
		if member.house_id != -1:
			var house_icon := Label.new()
			house_icon.text = HOUSE_ICON_TEXT
			house_icon.add_theme_font_size_override("font_size", 10)
			house_icon.tooltip_text = "ID Casa: %d" % member.house_id
			row.add_child(house_icon)
			house_icon_node = house_icon

		# Riga task indentata, SOTTO la riga dell'individuo (2026-09-18, richiesta utente) —
		# row_wrapper (VBoxContainer) tiene insieme le due righe come un solo blocco, così l'ordine
		# nella lista resta sempre "individuo, poi la sua task" anche quando list_container viene
		# ricostruito. Testo abbreviato = Task.get_activity_description() (STESSA formula/STESSO
		# metodo già usato da GameScene per HumanIndividualInfoPanel.activity_text — "Costruire",
		# "Trasportare (Rametti)", ecc., mai l'Action/step attivo, vedi Task.gd), senza il suffisso
		# "[#id]" che ha senso solo nel pannello individuo (qui è rumore in più per una riga già
		# compatta). member.current_task letto DIRETTAMENTE (questo pannello legge già altri campi
		# di HumanIndividual senza passare da un Dictionary pre-risolto, es. member.house_id sopra —
		# non è un pannello "muto" in senso stretto come BuildingInfoPanel/VegetationInfoPanel).
		var row_wrapper := VBoxContainer.new()
		row_wrapper.add_theme_constant_override("separation", 0)
		row_wrapper.add_child(row)

		var task_margin := MarginContainer.new()
		task_margin.add_theme_constant_override("margin_left", int(TASK_ROW_INDENT))
		task_margin.add_theme_constant_override("margin_bottom", 2)
		task_margin.visible = _show_tasks

		# Testo del task su una riga, tagliato con i puntini (2026-10-04): lascia spazio ai pulsanti delle azioni a destra
		# senza mai allargare il pannello.
		var task_line := HBoxContainer.new()
		task_line.add_theme_constant_override("separation", 2)
		var task_label := Label.new()
		task_label.add_theme_font_size_override("font_size", 9)
		task_label.clip_text = true
		task_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		task_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		task_label.add_theme_color_override("font_color", COLOR_TASK_DIM)
		task_label.text = "↳ " + (
			member.current_task.get_activity_description() if member.current_task != null else IDLE_TASK_TEXT
		)
		task_label.tooltip_text = task_label.text
		task_label.mouse_filter = Control.MOUSE_FILTER_PASS
		task_line.add_child(task_label)
		var task_spacer := Control.new()
		task_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		task_line.add_child(task_spacer)
		task_margin.add_child(task_line)
		row_wrapper.add_child(task_margin)
		_task_rows.append(task_margin)
		_command_rows.append({
			"member": member, "wrapper": row_wrapper, "name_row": row, "house_icon": house_icon_node,
			"name_spacer": name_spacer, "task_spacer": task_spacer,
		})

		list_container.add_child(row_wrapper)
		# Misura DOPO l'inserimento (font/tema risolti dall'albero) e a prescindere dalla visibilita' della lista
		# o della riga task: get_combined_minimum_size non dipende dalla visibilita' del nodo stesso.
		_widest_row = maxf(_widest_row, row.get_combined_minimum_size().x)
		_widest_row = maxf(_widest_row, TASK_ROW_INDENT + task_label.get_combined_minimum_size().x)

	custom_minimum_size.x = maxf(custom_minimum_size.x, _widest_row)


# Riga sotto il mouse (2026-10-04): solo lei mostra i pulsanti delle azioni. Controllo per posizione, non con i segnali
# di entrata/uscita del mouse, che i pulsanti sovrapposti interromperebbero. A ogni fotogramma il riquadro segue la riga
# (la lista può scorrere) e gli spaziatori seguono la larghezza dei pulsanti.
func _process(_delta: float) -> void:
	var hovered := -1
	if visible and list_container.is_visible_in_tree():
		var mouse := get_global_mouse_position()
		for i in range(_command_rows.size()):
			var wrapper: Control = _command_rows[i]["wrapper"]
			if is_instance_valid(wrapper) and wrapper.get_global_rect().has_point(mouse):
				hovered = i
				break
	if hovered != _hovered_command_row:
		_set_command_row_buttons(_hovered_command_row, false)
		_hovered_command_row = hovered
		_set_command_row_buttons(_hovered_command_row, true)
	_place_command_overlay()


# Mostra (ricostruiti con lo stato attuale) o toglie i pulsanti delle azioni di una riga.
func _set_command_row_buttons(index: int, shown: bool) -> void:
	if index < 0 or index >= _command_rows.size():
		return
	var entry: Dictionary = _command_rows[index]
	_clear_command_overlay()
	_set_spacer_width(entry["name_spacer"], 0.0)
	_set_spacer_width(entry["task_spacer"], 0.0)
	if not shown or not command_state_provider.is_valid() or not is_instance_valid(entry["wrapper"]):
		return
	var member: HumanIndividual = entry["member"]
	var side := _command_button_side(entry)
	for action in CommandBar.ACTIONS:
		var state: Dictionary = command_state_provider.call(member, action["id"])
		if not bool(state.get("shown", false)):
			continue
		_command_overlay.add_child(_build_command_button(member, action, state, side))
	var count := _command_overlay.get_child_count()
	if count == 0:
		return
	var overlay_width: float = side * count + COMMAND_BUTTON_SEPARATION * (count - 1)
	_command_overlay.size = Vector2(overlay_width, side)
	_command_overlay.visible = true
	_set_spacer_width(entry["name_spacer"], overlay_width)
	_place_command_overlay()


# Lato dei pulsanti: comodo (COMMAND_BUTTON_SIZE) con nome più task; con i task nascosti, l'altezza della sola riga del
# nome, così stanno dentro la riga.
func _command_button_side(entry: Dictionary) -> float:
	if _show_tasks:
		return COMMAND_BUTTON_SIZE
	var name_row: Control = entry["name_row"]
	return minf(COMMAND_BUTTON_SIZE, maxf(name_row.size.y, 1.0))


# Riquadro a destra, con il bordo destro dove inizia l'icona della casa (o alla fine della riga del nome senza casa),
# centrato in verticale sul blocco nome più task; lo spaziatore della riga del task copre la stessa fascia, così il
# testo del task si tronca sotto i pulsanti.
func _place_command_overlay() -> void:
	if _command_overlay == null or not _command_overlay.visible:
		return
	if _hovered_command_row < 0 or _hovered_command_row >= _command_rows.size():
		_clear_command_overlay()
		return
	var entry: Dictionary = _command_rows[_hovered_command_row]
	var wrapper: Control = entry["wrapper"]
	var name_row: Control = entry["name_row"]
	if not is_instance_valid(wrapper) or not is_instance_valid(name_row):
		_clear_command_overlay()
		return
	var house_icon: Variant = entry["house_icon"]
	var right_edge: float = name_row.get_global_rect().end.x
	if house_icon != null and is_instance_valid(house_icon):
		right_edge = (house_icon as Control).get_global_rect().position.x
	var wrapper_rect := wrapper.get_global_rect()
	var overlay_size := _command_overlay.size
	_command_overlay.global_position = Vector2(
		right_edge - overlay_size.x, wrapper_rect.position.y + (wrapper_rect.size.y - overlay_size.y) * 0.5
	)
	if _show_tasks:
		_set_spacer_width(entry["task_spacer"], maxf(0.0, wrapper_rect.end.x - (right_edge - overlay_size.x)))


func _clear_command_overlay() -> void:
	if _command_overlay == null:
		return
	for child in _command_overlay.get_children():
		_command_overlay.remove_child(child)
		child.queue_free()
	_command_overlay.visible = false


func _set_spacer_width(spacer: Variant, width: float) -> void:
	if spacer == null or not is_instance_valid(spacer):
		return
	var control := spacer as Control
	if not is_equal_approx(control.custom_minimum_size.x, width):
		control.custom_minimum_size = Vector2(width, 0.0)


func _build_command_button(member: HumanIndividual, action: Dictionary, state: Dictionary, side: float) -> Button:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(side, side)
	button.tooltip_text = String(state.get("tooltip", ""))
	var enabled := bool(state.get("enabled", false))
	button.disabled = not enabled
	var icon := IconRegistry.get_command_button_icon_node(String(action["icon"]))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not enabled:
		icon.modulate = COMMAND_BUTTON_DISABLED_MODULATE
	button.pressed.connect(func(): command_requested.emit(member, action["id"]))
	return button


func _on_center_button_pressed(member: HumanIndividual) -> void:
	individual_center_requested.emit(member)


func _on_expand_pressed() -> void:
	_expanded = not _expanded
	list_container.visible = _expanded
	expand_button.text = "-" if _expanded else "+"
	hide_tasks_button.disabled = not _expanded


# Ricompatta le righe task senza toccare quelle individuo (2026-09-18, richiesta utente) — un solo
# toggle per TUTTE le righe insieme (niente per-riga: sarebbe rumore in più, la richiesta era "un
# button" al singolare), su _task_rows così non serve ricostruire l'intera lista solo per questo.
func _on_hide_tasks_pressed() -> void:
	_show_tasks = not _show_tasks
	hide_tasks_button.text = "Nascondi task" if _show_tasks else "Mostra task"
	for task_row in _task_rows:
		task_row.visible = _show_tasks
	# Pulsanti della riga sotto il mouse spostati sulla riga giusta (task o nome).
	if _hovered_command_row >= 0:
		_set_command_row_buttons(_hovered_command_row, true)


# Stessa convenzione di HumanIndividualInfoPanel._format_id: sentinella -1 (non applicabile/non
# ancora valorizzato) resa come "—" invece del numero grezzo.
func _format_id(value: int) -> String:
	return "—" if value < 0 else str(value)
