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

# Simbolo "ha una casa" per riga (2026-09-12, richiesta utente) — stessa icona già in uso per la
# scheda 🏠/BuildingsInfoPanel, coerenza visiva: lo stesso glifo identifica "casa" ovunque nel
# progetto, non un'icona nuova da imparare. Mostrato SOLO se member.house_id != -1 (stessa
# sentinella "nessuna casa" già in uso ovunque per questo campo).
const HOUSE_ICON_TEXT := "🏠"

# Icone di salute per riga (2026-10-25, richiesta utente): gli stessi distintivi sopra la testa (HealthConditionIcon,
# senza punta), in fondo alla riga del task (sulla riga del nome coprivano i pulsanti delle azioni). Scala 3: distintivo di
# ~13 px, si riconosce senza alzare troppo la riga (a 2.0 era un pallino). Con i task nascosti non si vedono.
const HEALTH_ICON_SCALE: float = 3.0
# Larghezza di un distintivo e spazio tra due affiancati, in pixel della lista.
const HEALTH_BADGE_WIDTH: float = (HealthConditionIcon.RADIUS + HealthConditionIcon.OUTLINE_WIDTH) * 2.0 * HEALTH_ICON_SCALE
const HEALTH_BADGE_GAP: float = HealthConditionIcon.GAP * HEALTH_ICON_SCALE

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
# Tornato il 2026-10-07 (richiesta utente: la riga cliccabile si è rivelata poco intuitiva negli elenchi dell'info panel).
const CENTER_BUTTON_TEXT := "🎯"

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
@onready var village_label: Label = $SummaryRow/GroupLabel
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
# Una voce per riga: {"member", "wrapper" (blocco nome + task), "name_row", "house_icon" (dove finisce il riquadro dei
# pulsanti), "health_slot", "health_icon", "name_spacer", "task_spacer", "task_label"}.
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
	hide_tasks_button.text = tr("population_hide_tasks") if _show_tasks else tr("population_show_tasks")
	hide_tasks_button.pressed.connect(_on_hide_tasks_pressed)
	# Disabilitato quando la lista pipottini è compattata (2026-09-19, richiesta utente: "se il
	# button + è raggruppato, spegni il pulsante mostra/nascondi task, tanto non funziona") — con
	# list_container invisibile non c'è alcuna riga task da mostrare/nascondere, quindi il click non
	# avrebbe alcun effetto visibile: disabled invece di semplicemente nasconderlo, così il player
	# vede comunque che il controllo esiste ma non è applicabile finché la lista resta chiusa.
	hide_tasks_button.disabled = not _expanded
	_build_sort_button()


# Pulsante dell'ordinamento, accanto a "Nascondi compiti" sulla riga del Folk: piatto e stretto come il 🎯 di riga, così
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
	_sort_button.tooltip_text = TooltipText.wrap(tr("population_sort_tooltip").format({"option": tr(String(SORT_OPTIONS[active]["label_key"]))}))


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


# total_count = abitanti del Folk, contati da GameScene (Folk.count_members).
#
# folk_name/village_name/village_count (2026-10-12, sostituiscono folk_id/group_id): già risolti da GameScene, questo pannello
# riceve solo dati pronti, mai gli oggetti di gioco. Prima riga "<nome popolo>: total %d" (FolkLabel); seconda riga di
# stato "<nome villaggio>: total %d" — "No village" con village_name vuoto — insieme a ♂/♀ e al bottone +/- (nodo
# GroupLabel).
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
	folk_name: String, village_name: String, village_count: int, housing_capacity: int, sort_id: String = DEFAULT_SORT_ID
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
	folk_label.text = "%s: total %d" % [folk_name, total_count]
	# Riga di stato del villaggio (2026-10-12): "No village" finché non esiste (nasce col village center).
	# TODO col secondo villaggio: sostituirla con un selettore Tutti/Village N/Senza villaggio che filtra elenco e ♂/♀.
	village_label.text = "%s: total %d" % [village_name, village_count] if village_name != "" else "No village"
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
	housing_label.tooltip_text = TooltipText.wrap("%d pipottini vivi su %d posti letto totali (edifici residenziali completi)%s" % [
		total_count, housing_capacity,
		" — non bastano per tutti!" if total_count > housing_capacity else ""
	])

	var sorted_members := _sorted_individuals(individuals)
	# Righe riusate (2026-10-28, scatti: ~43 ms al giorno a scheda aperta per rifare tutti i nodi): stessi abitanti nello
	# stesso ordine -> si aggiornano solo le scritte, la casa e la salute. Nascite, morti o ordine cambiato: lista rifatta.
	if _rows_match(sorted_members):
		for i in range(sorted_members.size()):
			var entry: Dictionary = _command_rows[i]
			var member: HumanIndividual = sorted_members[i]
			var name_label: Label = entry["name_label"]
			var name_text := _row_name_text(member, current_year, era_effective_age_band_durations_male, era_effective_age_band_durations_female)
			if name_label.text != name_text:
				name_label.text = name_text
			_apply_house_icon(entry["house_icon"], member)
		refresh_task_texts()
		return
	for child in list_container.get_children():
		child.queue_free()
	_task_rows.clear()
	_command_rows.clear()
	_hovered_command_row = -1
	_clear_command_overlay()
	for member in sorted_members:
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
		center_button.tooltip_text = TooltipText.wrap("Centra e seleziona")
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
		label.text = _row_name_text(member, current_year, era_effective_age_band_durations_male, era_effective_age_band_durations_female)
		row.add_child(label)

		# Spaziatore largo quanto i pulsanti delle azioni quando la riga è sotto il mouse, a sinistra della casa.
		var name_spacer := Control.new()
		name_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(name_spacer)

		# Simbolo casa (2026-09-12, richiesta utente). Posto riservato anche senza casa (2026-10-25): stesso glifo
		# trasparente, così le case restano in colonna su tutte le righe.
		var house_icon := Label.new()
		house_icon.text = HOUSE_ICON_TEXT
		house_icon.add_theme_font_size_override("font_size", 10)
		_apply_house_icon(house_icon, member)
		row.add_child(house_icon)

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
		task_label.tooltip_text = TooltipText.wrap(task_label.text)
		task_label.mouse_filter = Control.MOUSE_FILTER_PASS
		task_line.add_child(task_label)
		var task_spacer := Control.new()
		task_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		task_line.add_child(task_spacer)
		# Icone di salute in fondo alla riga del task (2026-10-25, spostate dalla riga del nome dove coprivano i pulsanti
		# delle azioni): larghe quanto i distintivi presenti, nascoste mentre la riga mostra i pulsanti.
		var health_slot := Control.new()
		health_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var health_icon := HealthConditionIcon.new()
		health_icon.show_tail = false
		health_icon.scale = Vector2.ONE * HEALTH_ICON_SCALE
		health_icon.visible = false
		health_slot.add_child(health_icon)
		health_slot.resized.connect(func() -> void: health_icon.position = health_slot.size * 0.5)
		task_line.add_child(health_slot)
		_update_health_slot(member, health_slot, health_icon)
		task_margin.add_child(task_line)
		row_wrapper.add_child(task_margin)
		_task_rows.append(task_margin)
		_command_rows.append({
			"member": member, "wrapper": row_wrapper, "name_row": row, "name_label": label, "house_icon": house_icon,
			"health_slot": health_slot, "health_icon": health_icon,
			"name_spacer": name_spacer, "task_spacer": task_spacer, "task_label": task_label,
		})

		list_container.add_child(row_wrapper)
		# Misura DOPO l'inserimento (font/tema risolti dall'albero) e a prescindere dalla visibilita' della lista
		# o della riga task: get_combined_minimum_size non dipende dalla visibilita' del nodo stesso.
		_widest_row = maxf(_widest_row, row.get_combined_minimum_size().x)
		_widest_row = maxf(_widest_row, TASK_ROW_INDENT + task_label.get_combined_minimum_size().x)

	custom_minimum_size.x = maxf(custom_minimum_size.x, _widest_row)


# true se le righe in lista sono degli stessi abitanti, nello stesso ordine, ancora valide.
func _rows_match(sorted_members: Array[HumanIndividual]) -> bool:
	if _command_rows.size() != sorted_members.size() or _command_rows.is_empty():
		return false
	for i in range(sorted_members.size()):
		var entry: Dictionary = _command_rows[i]
		if entry["member"] != sorted_members[i] or not is_instance_valid(entry["wrapper"]) or entry["wrapper"].is_queued_for_deletion():
			return false
	return true


# "Nome — F, 34 (Adult)": nome, sesso, età e fascia d'età.
func _row_name_text(
	member: HumanIndividual, current_year: int, durations_male: Array[float], durations_female: Array[float]
) -> String:
	var age: int = current_year - member.birth_year_virtual
	var age_band := HumanCalculator.get_age_band(durations_male, durations_female, member.sex, float(age))
	return "%s — %s, %d (%s)" % [
		member.name,
		"F" if member.sex == HumanTypes.Sex.FEMALE else "M",
		age,
		HumanTypes.AgeBand.keys()[age_band].capitalize(),
	]


# Simbolo casa della riga: visibile con tooltip e clic propri se l'abitante ha una casa, trasparente altrimenti (il posto
# resta, così le case restano in colonna).
func _apply_house_icon(house_icon: Label, member: HumanIndividual) -> void:
	if member.house_id != -1:
		house_icon.modulate = Color(1, 1, 1, 1)
		house_icon.tooltip_text = TooltipText.wrap("ID Casa: %d" % member.house_id)
		# Tiene il suo clic (2026-10-07): un clic sulla casa non seleziona la riga.
		house_icon.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		house_icon.modulate = Color(1, 1, 1, 0)
		house_icon.tooltip_text = ""
		house_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE


# Testo dell'attività di ogni riga riallineato alla task attiva (2026-10-09, bugfix "la lista mostra un'attività
# vecchia"): la lista si ricostruisce solo a eventi e una volta al giorno di gioco; questo aggiorna le sole scritte,
# senza ricostruire le righe (pulsanti della riga sotto il mouse e scorrimento restano), chiamato da GameScene una volta
# al secondo con la scheda visibile.
func refresh_task_texts() -> void:
	for row_data in _command_rows:
		var member: HumanIndividual = row_data["member"]
		var task_label: Label = row_data.get("task_label")
		if not is_instance_valid(member) or task_label == null or not is_instance_valid(task_label):
			continue
		var text := "↳ " + (member.current_task.get_activity_description() if member.current_task != null else IDLE_TASK_TEXT)
		if task_label.text != text:
			task_label.text = text
			task_label.tooltip_text = TooltipText.wrap(text)
		# Icone di salute (2026-10-25) allo stesso giro: compaiono e spariscono senza ricostruire la lista.
		_update_health_slot(member, row_data["health_slot"], row_data["health_icon"])


# Stati delle icone di salute dalle condizioni dell'individuo (HealthConditionIcon.states_for, la stessa della testa),
# larghezza secondo i distintivi presenti (0 senza condizioni: il task usa tutta la riga); tooltip con i nomi delle
# condizioni, come accanto a "Salute" nel pannello individuo.
func _update_health_slot(member: HumanIndividual, health_slot: Control, health_icon: HealthConditionIcon) -> void:
	if not is_instance_valid(health_slot) or not is_instance_valid(health_icon):
		return
	var states := HealthConditionIcon.states_for(member)
	health_icon.set_states(states[0], states[1])
	var badge_count := int(states[0] != HealthConditionIcon.State.NONE) + int(states[1] != HealthConditionIcon.State.NONE)
	var width := 0.0 if badge_count == 0 else HEALTH_BADGE_WIDTH * badge_count + HEALTH_BADGE_GAP * (badge_count - 1)
	health_slot.custom_minimum_size = Vector2(width, HEALTH_BADGE_WIDTH if badge_count > 0 else 0.0)
	if health_icon.visible:
		health_slot.tooltip_text = TooltipText.wrap(HealthConditionService.display_names(member))
		health_slot.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		health_slot.tooltip_text = ""
		health_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE


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
	# Icone di salute nascoste mentre la riga mostra i pulsanti (starebbero sotto il loro riquadro).
	var health_slot: Variant = entry.get("health_slot")
	if health_slot != null and is_instance_valid(health_slot):
		(health_slot as Control).visible = not shown
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


# Riquadro a destra, con il bordo destro dove inizia l'icona della casa (posto sempre presente, anche senza casa),
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
	button.tooltip_text = TooltipText.wrap(String(state.get("tooltip", "")))
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
	hide_tasks_button.text = tr("population_hide_tasks") if _show_tasks else tr("population_show_tasks")
	for task_row in _task_rows:
		task_row.visible = _show_tasks
	# Pulsanti della riga sotto il mouse spostati sulla riga giusta (task o nome).
	if _hovered_command_row >= 0:
		_set_command_row_buttons(_hovered_command_row, true)
