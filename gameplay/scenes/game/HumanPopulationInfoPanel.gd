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

# Bottone per-riga "centra e seleziona" (richiesta utente, 2026-09-04: "un piccolo button a fianco
# di ognuno... al clic mi centri su di loro e mi selezioni il cliccato" — a differenza del
# generico "🎯" della PrimaryActionsBar, che centra solo sull'ULTIMO selezionato, questo permette
# di saltare direttamente a un individuo specifico dalla lista). Stessa icona del bottone
# generale (vedi GameScene._center_camera_on_individual/PrimaryActionsBar) per coerenza visiva —
# stesso concetto, non un'icona nuova da imparare.
const CENTER_BUTTON_TEXT := "🎯"

# Rompe il principio "componente muto" dichiarato in testa al file SOLO per il minimo indispensabile
# (stesso schema già in uso per MinimapPanel.cell_clicked): questo pannello non decide MAI da sé
# selezione/camera, si limita a segnalare "l'utente ha chiesto questo individuo" — GameScene resta
# l'unica a decidere cosa fare col click (stesso schema di _on_minimap_cell_clicked).
signal individual_center_requested(individual: HumanIndividual)

@onready var folk_label: Label = $FolkLabel
@onready var group_label: Label = $SummaryRow/GroupLabel
@onready var male_label: Label = $SummaryRow/MaleLabel
@onready var female_label: Label = $SummaryRow/FemaleLabel
@onready var expand_button: Button = $SummaryRow/ExpandButton
@onready var list_container: VBoxContainer = $ListContainer

var _expanded: bool = false


func _ready() -> void:
	male_label.add_theme_color_override("font_color", COLOR_MALE)
	female_label.add_theme_color_override("font_color", COLOR_FEMALE)
	expand_button.text = "+"
	expand_button.pressed.connect(_on_expand_pressed)
	list_container.visible = false


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
func show_population(
	total_count: int, individuals: Array[HumanIndividual], current_year: int,
	era_effective_age_band_durations_male: Array[float], era_effective_age_band_durations_female: Array[float],
	folk_id: int, group_id: int
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

	for child in list_container.get_children():
		child.queue_free()
	for member in individuals:
		var age: int = current_year - member.birth_year_virtual
		var age_band := HumanCalculator.get_age_band(
			era_effective_age_band_durations_male, era_effective_age_band_durations_female, member.sex, float(age)
		)
		# Riga = HBoxContainer (era un Label nudo) — richiesta utente 2026-09-04: bottone
		# "centra e seleziona" per riga, vedi individual_center_requested sopra. label.
		# size_flags_horizontal EXPAND_FILL così il bottone resta compatto a destra invece di
		# essere spinto fuori dalla larghezza del testo.
		var row := HBoxContainer.new()
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 10)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s — %s, age %d (%s)" % [
			member.name,
			"Female" if member.sex == HumanTypes.Sex.FEMALE else "Male",
			age,
			HumanTypes.AgeBand.keys()[age_band].capitalize(),
		]
		row.add_child(label)
		var center_button := Button.new()
		center_button.text = CENTER_BUTTON_TEXT
		center_button.tooltip_text = "Centra e seleziona"
		center_button.pressed.connect(_on_center_button_pressed.bind(member))
		row.add_child(center_button)
		list_container.add_child(row)


func _on_center_button_pressed(member: HumanIndividual) -> void:
	individual_center_requested.emit(member)


func _on_expand_pressed() -> void:
	_expanded = not _expanded
	list_container.visible = _expanded
	expand_button.text = "-" if _expanded else "+"


# Stessa convenzione di HumanIndividualInfoPanel._format_id: sentinella -1 (non applicabile/non
# ancora valorizzato) resa come "—" invece del numero grezzo.
func _format_id(value: int) -> String:
	return "—" if value < 0 else str(value)
