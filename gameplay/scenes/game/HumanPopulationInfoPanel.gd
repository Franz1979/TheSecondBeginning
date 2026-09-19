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


func _ready() -> void:
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
	folk_id: int, group_id: int, housing_capacity: int
) -> void:
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
	for member in individuals:
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
		label.text = "%s — %s, %d (%s)" % [
			member.name,
			"F" if member.sex == HumanTypes.Sex.FEMALE else "M",
			age,
			HumanTypes.AgeBand.keys()[age_band].capitalize(),
		]
		row.add_child(label)

		# Simbolo casa (2026-09-12, richiesta utente) — SOLO se ha una casa assegnata, nessun
		# placeholder/spazio vuoto per chi non ce l'ha (stesso principio "assente = niente" già
		# seguito altrove, es. is_pregnant sulla stessa riga dell'age_band in HumanIndividualInfoPanel).
		if member.house_id != -1:
			var house_icon := Label.new()
			house_icon.text = HOUSE_ICON_TEXT
			house_icon.add_theme_font_size_override("font_size", 10)
			house_icon.tooltip_text = "ID Casa: %d" % member.house_id
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

		var task_label := Label.new()
		task_label.add_theme_font_size_override("font_size", 9)
		task_label.add_theme_color_override("font_color", COLOR_TASK_DIM)
		task_label.text = "↳ " + (
			member.current_task.get_activity_description() if member.current_task != null else IDLE_TASK_TEXT
		)
		task_margin.add_child(task_label)
		row_wrapper.add_child(task_margin)
		_task_rows.append(task_margin)

		list_container.add_child(row_wrapper)


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


# Stessa convenzione di HumanIndividualInfoPanel._format_id: sentinella -1 (non applicabile/non
# ancora valorizzato) resa come "—" invece del numero grezzo.
func _format_id(value: int) -> String:
	return "—" if value < 0 else str(value)
