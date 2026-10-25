class_name StatisticsPanel
extends Window

# Pannello Statistiche di GameScene. Stesso pattern di apertura/chiusura già in uso da HelpDialog/
# OptionsMenu/SystemMenuDialog (Window standalone, X nativa nascosta e resa inerte, CloseButton
# esplicito, trattato come dialogo bloccante da GameScene — visibility_changed collegato a
# _on_blocking_dialog_visibility_changed, stesso schema degli altri: mette in pausa il clock mentre
# è aperto). A DIFFERENZA degli altri (popup_centered auto-dimensionato al contenuto via
# get_contents_minimum_size()), questo pannello usa una dimensione FISSA (vedi .tscn) — bugfix,
# richiesta utente 2026-09-06: l'auto-dimensionamento, ricalcolato anche ad ogni cambio tab,
# considerava solo il tab ATTIVO in quel momento, tagliando fuori CloseButton per i tab più alti
# di quello con cui la finestra era stata dimensionata l'ultima volta.
#
# TabContainer con quattro tab, Mortalità/Nascite/Popolazione/Edifici (Step A/B: mortalità,
# 2026-09-05; Step 5/6 piano statistiche: nascite/popolazione, 2026-09-06; Edifici, 2026-09-12) —
# struttura pensata per tab future senza dover ristrutturare il contenitore, stesso principio già
# seguito da MacroCellDetailPanel (TAB_* + set_tab_title, mai toggle di .visible sui figli). Ogni
# tab è una ScrollContainer (non una VBoxContainer diretta, stesso pattern di MacroCellDetailPanel)
# — se il contenuto di un tab non entra nella finestra fissa, scorre per conto suo invece di far
# traboccare l'intero pannello.
#
# Tutto ricalcolato AL VOLO ad ogni chiamata a open_dialog() — nessuna cache, nessun aggregato
# salvato, coerente con GameData.death_events/birth_events restando puri log grezzi. Nessuna
# modifica a quei log o alla logica che li scrive: questo file è puramente di lettura/
# presentazione. Contenuto hardcoded (non tr()) — stessa convenzione già in uso per i pannelli di
# ispezione dati del progetto (VegetationInfoPanel/HumanIndividualInfoPanel/
# HumanPopulationInfoPanel), a differenza della "chrome" del pannello sopra (titolo finestra/tab/
# CloseButton), che invece resta tr() come il resto del sistema di menu/dialog. Grafici a linea
# (deaths/births per anno) via LineChart.gd, componente riusabile senza logica di dominio.
#
# Ordine delle schede (2026-10-25, richiesta utente): Popolazione, Par. vitali, Skills, Influenze, Natalità, Mortalità,
# Edifici. Indice = posizione del nodo figlio nel TabContainer (StatisticsPanel.tscn), mai .visible toggled da codice.
const TAB_POPULATION := 0
# Parametri vitali (2026-10-25, richiesta utente): medie attuali (barre) e per anno (linee) dei parametri dei pipottini,
# poi chi sta male e perché (HealthConditionService).
const TAB_PARAMETERS := 1
# Skill (2026-10-25, richiesta utente): stessa impostazione dei parametri sulle dieci skill, più il migliore per skill.
const TAB_SKILLS := 2
# Valori assoluti P/C/R del popolo o del villaggio scelto (2026-10-12, richiesta utente).
const TAB_INFLUENCE := 3
const TAB_BIRTHS := 4
const TAB_MORTALITY := 5
const TAB_BUILDINGS := 6
# Colori delle tre serie e ordine di visualizzazione P, C, R.
const INFLUENCE_DISPLAY := [
	{"type": InfluenceService.InfluenceType.POLITICAL, "name": "statistics_influence_political", "color": Color(0.9, 0.45, 0.35)},
	{"type": InfluenceService.InfluenceType.CULTURAL, "name": "statistics_influence_cultural", "color": Color(0.95, 0.8, 0.3)},
	{"type": InfluenceService.InfluenceType.RELIGIOUS, "name": "statistics_influence_religious", "color": Color(0.6, 0.5, 0.95)},
]
# Parametri della scheda Parametri, nell'ordine di VitalsAverageService.PARAMETERS: nome (chiave tr) e colore.
const PARAMETER_DISPLAY := {
	"health": {"name": "statistics_param_health", "color": Color(0.9, 0.35, 0.35)},
	"happiness": {"name": "statistics_param_happiness", "color": Color(0.95, 0.8, 0.3)},
	"stamina": {"name": "statistics_param_stamina", "color": Color(0.45, 0.8, 0.4)},
	"thirst": {"name": "statistics_param_thirst", "color": Color(0.35, 0.65, 0.95)},
	"loyalty": {"name": "statistics_param_loyalty", "color": Color(0.7, 0.5, 0.95)},
	"faith": {"name": "statistics_param_faith", "color": Color(0.85, 0.85, 0.85)},
}
# Skill della scheda Skill, nell'ordine di VitalsAverageService.SKILLS: nome intero (chiave tr già usata dal pannello
# dell'individuo), sigla sotto la barra e colore.
const SKILL_DISPLAY := {
	"leadership": {"name": "skill_leadership_label", "short": "skill_leadership_short", "color": Color(0.9, 0.45, 0.35)},
	"builder": {"name": "skill_builder_label", "short": "skill_builder_short", "color": Color(0.8, 0.6, 0.35)},
	"management": {"name": "skill_management_label", "short": "skill_management_short", "color": Color(0.95, 0.8, 0.3)},
	"transporter": {"name": "skill_transporter_label", "short": "skill_transporter_short", "color": Color(0.6, 0.75, 0.3)},
	"gathering": {"name": "skill_gathering_label", "short": "skill_gathering_short", "color": Color(0.35, 0.8, 0.45)},
	"cognition": {"name": "skill_cognition_label", "short": "skill_cognition_short", "color": Color(0.35, 0.8, 0.8)},
	"hunting": {"name": "skill_hunting_label", "short": "skill_hunting_short", "color": Color(0.35, 0.6, 0.95)},
	"crafting": {"name": "skill_crafting_label", "short": "skill_crafting_short", "color": Color(0.55, 0.5, 0.95)},
	"ritual": {"name": "skill_ritual_label", "short": "skill_ritual_short", "color": Color(0.85, 0.5, 0.9)},
	"social": {"name": "skill_social_label", "short": "skill_social_short", "color": Color(0.85, 0.85, 0.85)},
	"medicine": {"name": "skill_medicine_label", "short": "skill_medicine_short", "color": Color(0.4, 0.75, 0.55)},
}
# Didascalie dei grafici nella scena: percorso del Label -> chiave di traduzione.
const CHART_CAPTIONS := [
	["MarginContainer/VBoxContainer/TabContainer/MortalityTab/MortalityContent/CauseDistributionCaption", "statistics_caption_cause_distribution"],
	["MarginContainer/VBoxContainer/TabContainer/MortalityTab/MortalityContent/DeathsPerYearCaption", "statistics_caption_deaths_per_year"],
	["MarginContainer/VBoxContainer/TabContainer/BirthsTab/BirthsContent/BirthsPerYearCaption", "statistics_caption_births_per_year"],
	["MarginContainer/VBoxContainer/TabContainer/PopulationTab/PopulationContent/AgeBandDistributionCaption", "statistics_caption_age_band_distribution"],
	["MarginContainer/VBoxContainer/TabContainer/PopulationTab/PopulationContent/PopulationPerYearCaption", "statistics_caption_population_per_year"],
	["MarginContainer/VBoxContainer/TabContainer/ParametersTab/ParametersContent/CurrentParametersCaption", "statistics_caption_current_parameters"],
	["MarginContainer/VBoxContainer/TabContainer/ParametersTab/ParametersContent/ParametersPerYearCaption", "statistics_caption_parameters_per_year"],
	["MarginContainer/VBoxContainer/TabContainer/SkillsTab/SkillsContent/CurrentSkillsCaption", "statistics_caption_current_parameters"],
	["MarginContainer/VBoxContainer/TabContainer/SkillsTab/SkillsContent/SkillsPerYearCaption", "statistics_caption_parameters_per_year"],
	["MarginContainer/VBoxContainer/TabContainer/SkillsTab/SkillsContent/BestSkillsCaption", "statistics_caption_best_skills"],
	["MarginContainer/VBoxContainer/TabContainer/BuildingsTab/BuildingsContent/BuildingsPerYearCaption", "statistics_caption_buildings_per_year"],
	["MarginContainer/VBoxContainer/TabContainer/BuildingsTab/BuildingsContent/BuildingTypeDistributionCaption", "statistics_caption_building_type_distribution"],
]
# Voce "tutto il popolo" del selettore (2026-10-12): Village.id parte da 1, quindi 0 è libero.
const SCOPE_ALL := 0

@onready var tab_container: TabContainer = $MarginContainer/VBoxContainer/TabContainer
@onready var close_button: Button = $MarginContainer/VBoxContainer/CloseButton
# Selettore dell'ambito (2026-10-12, richiesta utente): tutto il popolo o un villaggio. Filtra ogni scheda.
@onready var scope_label: Label = $MarginContainer/VBoxContainer/ScopeRow/ScopeLabel
@onready var scope_selector: OptionButton = $MarginContainer/VBoxContainer/ScopeRow/ScopeSelector
@onready var total_label: Label = $MarginContainer/VBoxContainer/TabContainer/MortalityTab/MortalityContent/TotalLabel
@onready var average_age_label: Label = $MarginContainer/VBoxContainer/TabContainer/MortalityTab/MortalityContent/AverageAgeLabel
@onready var cause_distribution_chart: PieChart = $MarginContainer/VBoxContainer/TabContainer/MortalityTab/MortalityContent/CauseDistributionChart
@onready var deaths_per_year_chart: LineChart = $MarginContainer/VBoxContainer/TabContainer/MortalityTab/MortalityContent/DeathsPerYearChart
@onready var death_list_caption: Label = $MarginContainer/VBoxContainer/TabContainer/MortalityTab/MortalityContent/DeathListCaption
@onready var death_list_container: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/MortalityTab/MortalityContent/DeathListScroll/DeathListContainer

@onready var total_births_label: Label = $MarginContainer/VBoxContainer/TabContainer/BirthsTab/BirthsContent/TotalBirthsLabel
@onready var births_breakdown_label: Label = $MarginContainer/VBoxContainer/TabContainer/BirthsTab/BirthsContent/BirthsBreakdownLabel
@onready var births_per_year_chart: LineChart = $MarginContainer/VBoxContainer/TabContainer/BirthsTab/BirthsContent/BirthsPerYearChart
@onready var average_children_label: Label = $MarginContainer/VBoxContainer/TabContainer/BirthsTab/BirthsContent/AverageChildrenLabel
@onready var fertile_women_list_caption: Label = $MarginContainer/VBoxContainer/TabContainer/BirthsTab/BirthsContent/FertileWomenListCaption
@onready var fertile_women_list_container: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/BirthsTab/BirthsContent/FertileWomenListScroll/FertileWomenListContainer

@onready var total_population_label: Label = $MarginContainer/VBoxContainer/TabContainer/PopulationTab/PopulationContent/TotalPopulationLabel
@onready var male_count_label: Label = $MarginContainer/VBoxContainer/TabContainer/PopulationTab/PopulationContent/MaleCountLabel
@onready var female_count_label: Label = $MarginContainer/VBoxContainer/TabContainer/PopulationTab/PopulationContent/FemaleCountLabel
@onready var population_average_age_label: Label = $MarginContainer/VBoxContainer/TabContainer/PopulationTab/PopulationContent/PopulationAverageAgeLabel
@onready var age_band_distribution_chart: PieChart = $MarginContainer/VBoxContainer/TabContainer/PopulationTab/PopulationContent/AgeBandDistributionChart
@onready var population_per_year_chart: LineChart = $MarginContainer/VBoxContainer/TabContainer/PopulationTab/PopulationContent/PopulationPerYearChart

@onready var parameters_bar_chart: BarChart = $MarginContainer/VBoxContainer/TabContainer/ParametersTab/ParametersContent/ParametersBarChart
@onready var parameter_series_row: HFlowContainer = $MarginContainer/VBoxContainer/TabContainer/ParametersTab/ParametersContent/ParameterSeriesRow
@onready var parameters_per_year_chart: LineChart = $MarginContainer/VBoxContainer/TabContainer/ParametersTab/ParametersContent/ParametersPerYearChart
@onready var skills_bar_chart: BarChart = $MarginContainer/VBoxContainer/TabContainer/SkillsTab/SkillsContent/SkillsBarChart
@onready var skill_series_row: HFlowContainer = $MarginContainer/VBoxContainer/TabContainer/SkillsTab/SkillsContent/SkillSeriesRow
@onready var skills_per_year_chart: LineChart = $MarginContainer/VBoxContainer/TabContainer/SkillsTab/SkillsContent/SkillsPerYearChart
@onready var best_skills_container: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/SkillsTab/SkillsContent/BestSkillsContainer
@onready var sick_list_caption: Label = $MarginContainer/VBoxContainer/TabContainer/ParametersTab/ParametersContent/SickListCaption
@onready var sick_list_container: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/ParametersTab/ParametersContent/SickListScroll/SickListContainer

@onready var total_buildings_label: Label = $MarginContainer/VBoxContainer/TabContainer/BuildingsTab/BuildingsContent/TotalBuildingsLabel
@onready var buildings_per_year_chart: LineChart = $MarginContainer/VBoxContainer/TabContainer/BuildingsTab/BuildingsContent/BuildingsPerYearChart
@onready var building_type_distribution_chart: PieChart = $MarginContainer/VBoxContainer/TabContainer/BuildingsTab/BuildingsContent/BuildingTypeDistributionChart

@onready var influence_value_labels: Array[Label] = [
	$MarginContainer/VBoxContainer/TabContainer/InfluenceTab/InfluenceContent/PoliticalValueLabel,
	$MarginContainer/VBoxContainer/TabContainer/InfluenceTab/InfluenceContent/CulturalValueLabel,
	$MarginContainer/VBoxContainer/TabContainer/InfluenceTab/InfluenceContent/ReligiousValueLabel,
]
@onready var influence_checks: Array[CheckBox] = [
	$MarginContainer/VBoxContainer/TabContainer/InfluenceTab/InfluenceContent/SeriesRow/PoliticalCheck,
	$MarginContainer/VBoxContainer/TabContainer/InfluenceTab/InfluenceContent/SeriesRow/CulturalCheck,
	$MarginContainer/VBoxContainer/TabContainer/InfluenceTab/InfluenceContent/SeriesRow/ReligiousCheck,
]
@onready var influence_per_year_chart: LineChart = $MarginContainer/VBoxContainer/TabContainer/InfluenceTab/InfluenceContent/InfluencePerYearChart
# Coesione (2026-10-14, VillageCohesionService): stessa scheda, grafico a parte (scala 0–100, media e non somma).
@onready var cohesion_value_label: Label = $MarginContainer/VBoxContainer/TabContainer/InfluenceTab/InfluenceContent/CohesionValueLabel
@onready var cohesion_per_year_chart: LineChart = $MarginContainer/VBoxContainer/TabContainer/InfluenceTab/InfluenceContent/CohesionPerYearChart
@onready var influence_pies_container: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/InfluenceTab/InfluenceContent/PiesContainer
@onready var influence_pies_caption: Label = $MarginContainer/VBoxContainer/TabContainer/InfluenceTab/InfluenceContent/PiesContainer/PiesCaption
@onready var influence_pie_captions: Array[Label] = [
	$MarginContainer/VBoxContainer/TabContainer/InfluenceTab/InfluenceContent/PiesContainer/PoliticalPieCaption,
	$MarginContainer/VBoxContainer/TabContainer/InfluenceTab/InfluenceContent/PiesContainer/CulturalPieCaption,
	$MarginContainer/VBoxContainer/TabContainer/InfluenceTab/InfluenceContent/PiesContainer/ReligiousPieCaption,
]
@onready var influence_pie_charts: Array[PieChart] = [
	$MarginContainer/VBoxContainer/TabContainer/InfluenceTab/InfluenceContent/PiesContainer/PoliticalPieChart,
	$MarginContainer/VBoxContainer/TabContainer/InfluenceTab/InfluenceContent/PiesContainer/CulturalPieChart,
	$MarginContainer/VBoxContainer/TabContainer/InfluenceTab/InfluenceContent/PiesContainer/ReligiousPieChart,
]

# Input dell'ultima apertura, tenuti per ricalcolare le schede al cambio di ambito (mai modificati qui).
var _game_data: GameData = null
var _human_individuals: Array[HumanIndividual] = []
var _buildings: Array[Building] = []
# SCOPE_ALL o un Village.id; resta tra un'apertura e l'altra finché il villaggio esiste.
var _scope_village_id: int = SCOPE_ALL
var _folk: Folk = null
# Caselle delle linee della scheda Parametri, create in _ready: parametro -> CheckBox.
var _parameter_checks: Dictionary = {}
# Individui dell'ambito all'ultimo ricalcolo: il grafico per anno aggiunge il loro valore attuale come punto dell'anno in
# corso (stesso principio del grafico delle influenze).
var _parameter_individuals: Array[HumanIndividual] = []
# Stesse due cose per la scheda Skill.
var _skill_checks: Dictionary = {}
var _skill_individuals: Array[HumanIndividual] = []


func _ready() -> void:
	title = tr("statistics_tooltip")
	tab_container.set_tab_title(TAB_POPULATION, tr("statistics_tab_population"))
	tab_container.set_tab_title(TAB_PARAMETERS, tr("statistics_tab_parameters"))
	tab_container.set_tab_title(TAB_BUILDINGS, tr("statistics_tab_buildings"))
	tab_container.set_tab_title(TAB_BIRTHS, tr("statistics_tab_births"))
	tab_container.set_tab_title(TAB_MORTALITY, tr("statistics_tab_mortality"))
	tab_container.set_tab_title(TAB_INFLUENCE, tr("statistics_tab_influence"))
	tab_container.set_tab_title(TAB_SKILLS, tr("statistics_tab_skills"))
	for i in range(INFLUENCE_DISPLAY.size()):
		influence_checks[i].text = tr(INFLUENCE_DISPLAY[i]["name"])
		influence_checks[i].add_theme_color_override("font_color", INFLUENCE_DISPLAY[i]["color"])
		influence_checks[i].toggled.connect(func(_pressed: bool) -> void: _refresh_influence_chart())
		influence_pie_captions[i].text = tr(INFLUENCE_DISPLAY[i]["name"])
	influence_pies_caption.text = tr("statistics_influence_pies_caption")
	influence_per_year_chart.set_axis_labels(tr("statistics_axis_year"), tr("statistics_axis_value"))
	cohesion_per_year_chart.set_axis_labels(tr("statistics_axis_year"), tr("statistics_axis_cohesion"))
	# Titoli assi e didascalie dei grafici (2026-10-22, richiesta utente: tutti i testi del pannello in chiavi tr()).
	for chart in [deaths_per_year_chart, births_per_year_chart, population_per_year_chart]:
		chart.set_axis_labels(tr("statistics_axis_year"), tr("statistics_axis_people"))
	for caption in CHART_CAPTIONS:
		(get_node(String(caption[0])) as Label).text = tr(String(caption[1]))
	cohesion_per_year_chart.min_axis_max = VillageCohesionService.MAX_COHESION
	parameters_per_year_chart.set_axis_labels(tr("statistics_axis_year"), tr("statistics_axis_percent"))
	parameters_per_year_chart.min_axis_max = 100.0
	_parameter_checks = _build_series_checks(VitalsAverageService.PARAMETERS, PARAMETER_DISPLAY, parameter_series_row, _refresh_parameters_chart)
	skills_per_year_chart.set_axis_labels(tr("statistics_axis_year"), tr("statistics_axis_percent"))
	skills_per_year_chart.min_axis_max = 100.0
	_skill_checks = _build_series_checks(VitalsAverageService.SKILLS, SKILL_DISPLAY, skill_series_row, _refresh_skills_chart)
	# Titoli lista donne fertili/lista morti (richiesta utente, 2026-09-06) — tr(), non hardcoded
	# come il resto del CONTENUTO dati di questo pannello: sono più simili alla "chrome" strutturale
	# (titolo di una sezione, come i tab) che a un dato calcolato, stessa eccezione esplicitamente
	# richiesta per entrambi.
	fertile_women_list_caption.text = tr("fertile_women_list")
	death_list_caption.text = tr("death_list")
	close_button.text = tr("close_menu")
	scope_label.text = tr("statistics_scope_label")
	scope_selector.item_selected.connect(_on_scope_selected)
	close_button.pressed.connect(hide)
	# close_requested NON collegato a hide() + X nascosta (stesso motivo/meccanismo di
	# SystemMenuDialog._hide_native_close_button): si chiude solo dal CloseButton esplicito.
	var transparent := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	add_theme_icon_override("close", transparent)
	add_theme_icon_override("close_pressed", transparent)


# human_individuals (Step 5 piano statistiche, 2026-09-06) — NUOVO parametro: "media figli per
# donna fertile" ha bisogno della popolazione VIVA attuale (chi è FERTILE_ADULT oggi), un dato che
# GameData non possiede (vive solo su GameScene/GameTimeService, stesso principio già noto per
# _human_individuals — vedi ricognizione). Passato per riferimento dal chiamante, mai copiato né
# modificato qui (pannello di sola lettura/presentazione, come dichiarato in testa al file).
#
# buildings (2026-09-12, richiesta utente — quarto tab Edifici) — NUOVO parametro, stesso
# principio di human_individuals sopra: Array[Building] già risolto dal chiamante (GameScene ha
# macro_world.buildings a portata di mano), questo pannello resta di sola lettura/presentazione.
#
# folk (2026-10-12): popola il selettore dell'ambito (tutto il popolo + i suoi villaggi).
func open_dialog(game_data: GameData, human_individuals: Array[HumanIndividual], buildings: Array[Building], folk: Folk) -> void:
	_game_data = game_data
	_human_individuals = human_individuals
	_buildings = buildings
	_folk = folk
	_fill_scope_selector(folk)
	_refresh_all_tabs()
	# Bugfix (richiesta utente, 2026-09-06 — "solo la tab Nascite ha il tasto chiudi"): NON più
	# size = get_contents_minimum_size() (calcolato una volta sola sul tab ATTIVO in quel momento —
	# passare a un tab più alto travolgeva la finestra già dimensionata, spingendo CloseButton fuori
	# dall'area visibile; anche un ricalcolo ad ogni cambio tab si è rivelato inaffidabile, probabile
	# problema di timing sul minimum size di Godot). Finestra a dimensione FISSA e generosa (vedi
	# .tscn — size/TabContainer.custom_minimum_size), ogni tab avvolto nella propria ScrollContainer
	# (stesso pattern già in uso in MacroCellDetailPanel): se il contenuto di un tab non ci sta,
	# scorre per conto suo, la finestra non deve più sapere quanto è alto nessun tab specifico.
	exclusive = true
	popup_centered()


# Voci del selettore: "<popolo> (tutto il popolo)" e un villaggio per riga. Se il villaggio scelto non esiste più si
# torna a tutto il popolo.
func _fill_scope_selector(folk: Folk) -> void:
	scope_selector.clear()
	scope_selector.add_item(tr("statistics_scope_folk").format({"folk": folk.name if folk != null else ""}), SCOPE_ALL)
	var has_selected := false
	if folk != null:
		for village in folk.villages:
			scope_selector.add_item(village.get_display_name(), village.id)
			has_selected = has_selected or village.id == _scope_village_id
	if not has_selected:
		_scope_village_id = SCOPE_ALL
	scope_selector.select(scope_selector.get_item_index(_scope_village_id))


func _on_scope_selected(index: int) -> void:
	_scope_village_id = scope_selector.get_item_id(index)
	_refresh_all_tabs()


# Ogni scheda ricalcolata sull'ambito scelto: individui ed edifici del villaggio, eventi registrati in quel villaggio
# (village_id; quelli precedenti al campo contano solo per tutto il popolo), serie annuali del villaggio.
func _refresh_all_tabs() -> void:
	if _game_data == null:
		return
	var individuals := _scoped_individuals()
	var population_series: Dictionary = _game_data.population_snapshots
	var building_series: Dictionary = _game_data.building_snapshots
	if _scope_village_id != SCOPE_ALL:
		population_series = _game_data.village_population_snapshots.get(_scope_village_id, {})
		building_series = _game_data.village_building_snapshots.get(_scope_village_id, {})
	_refresh_mortality_tab(_scoped_events(_game_data.death_events))
	_refresh_births_tab(
		_scoped_events(_game_data.birth_events), individuals, _game_data.year,
		_game_data.era_effective_age_band_durations_male, _game_data.era_effective_age_band_durations_female
	)
	_refresh_population_tab(
		individuals, population_series, _game_data.year,
		_game_data.era_effective_age_band_durations_male, _game_data.era_effective_age_band_durations_female
	)
	_refresh_parameters_tab(individuals)
	_refresh_skills_tab(individuals)
	_refresh_buildings_tab(_scoped_buildings(), building_series)
	_refresh_influence_tab()


func _scoped_individuals() -> Array[HumanIndividual]:
	if _scope_village_id == SCOPE_ALL:
		return _human_individuals
	var result: Array[HumanIndividual] = []
	for individual in _human_individuals:
		if individual.village_ref != null and individual.village_ref.id == _scope_village_id:
			result.append(individual)
	return result


func _scoped_buildings() -> Array[Building]:
	if _scope_village_id == SCOPE_ALL:
		return _buildings
	var result: Array[Building] = []
	for building in _buildings:
		if building.village_id == _scope_village_id:
			result.append(building)
	return result


func _scoped_events(events: Array[Dictionary]) -> Array[Dictionary]:
	if _scope_village_id == SCOPE_ALL:
		return events
	var result: Array[Dictionary] = []
	for event in events:
		if int(event.get("village_id", -1)) == _scope_village_id:
			result.append(event)
	return result


func _refresh_mortality_tab(death_events: Array[Dictionary]) -> void:
	total_label.text = tr("statistics_total_deaths").format({"count": death_events.size()})

	if death_events.is_empty():
		average_age_label.text = tr("statistics_average_death_age").format({"age": tr("statistics_not_available")})
	else:
		var age_sum := 0
		for event in death_events:
			age_sum += int(event["age_at_death"])
		average_age_label.text = tr("statistics_average_death_age").format({"age": "%.1f" % (float(age_sum) / death_events.size())})

	# Itera l'ENUM (non i soli valori presenti negli eventi) — una causa futura senza eventi
	# registrati compare comunque a 0, invece di sparire silenziosamente dalla torta/legenda.
	# Step 7 piano statistiche (2026-09-06, anticipato su richiesta utente): non più un Label di
	# testo — stesso PieChart riusabile già usato per la distribuzione età nel tab Popolazione,
	# nessun lavoro aggiuntivo sul componente.
	var cause_counts := {}
	for cause_name in DeathTypes.DeathCause.keys():
		cause_counts[String(cause_name).capitalize()] = 0
	for event in death_events:
		cause_counts[String(_cause_name(int(event["cause"]))).capitalize()] += 1
	cause_distribution_chart.set_data(cause_counts)

	# Step 4 piano statistiche (2026-09-06): non più un Label di testo riga-per-anno — la stessa
	# identica aggregazione (invariata) passata al LineChart riusabile (vedi LineChart.gd), che si
	# occupa da sé di ordinamento/assi/casi limite (nessun punto, un solo punto).
	# _fill_missing_years (richiesta utente, 2026-09-06): death_events è un log di eventi puntuali
	# — un anno senza morti semplicemente non compare qui, ma il grafico deve scendere a 0 in
	# quell'anno, non saltarlo (vedi _fill_missing_years per il perché/come).
	var deaths_by_year := {}
	for event in death_events:
		var year: int = int(event["year"])
		deaths_by_year[year] = deaths_by_year.get(year, 0) + 1
	deaths_per_year_chart.set_data(_fill_missing_years(deaths_by_year))

	for child in death_list_container.get_children():
		child.queue_free()
	for event in death_events:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 10)
		label.text = tr("statistics_death_row").format({
			"name": event["name"], "age": int(event["age_at_death"]), "cause": String(_cause_name(int(event["cause"]))).capitalize(),
			"year": int(event["year"]), "day": int(event["day"]),
		})
		death_list_container.add_child(label)


func _cause_name(cause: int) -> String:
	return DeathTypes.DeathCause.keys()[cause]


# Step 5 piano statistiche (2026-09-06) — stesso principio del tab Mortalità: tutto ricalcolato al
# volo ad ogni apertura, nessuna cache. "Media figli per donna fertile" conta, per ciascuna donna
# FERTILE_ADULT VIVA oggi, quanti birth_events VIVI (child_survived == true) la hanno come
# mother_id — un conteggio STORICO (include figli eventualmente non più in vita: è "quante nascite
# vive ha generato", non "quanti figli ha ancora"), poi fa la media sul numero di donne fertili.
# Un nato-morto (Step 3 effetto nato-morto, 2026-09-06 — child_survived ora può essere false,
# prima era sempre true) NON è un figlio nel senso demografico di questa statistica, quindi va
# escluso qui — stesso principio già rispettato "naturalmente" dal vincolo di spaziatura minima
# parti in HumanConceptionIndividualService (interroga solo individui realmente esistiti/vivi in
# human_individuals, un nato-morto non vi compare mai). current_year/durations_male/female
# servono SOLO per ricavare l'age_band di ciascuna vivente (stessa formula HumanCalculator.
# get_age_band già usata ovunque nel progetto per questo scopo).
func _refresh_births_tab(
	birth_events: Array[Dictionary], human_individuals: Array[HumanIndividual], current_year: int,
	durations_male: Array[float], durations_female: Array[float]
) -> void:
	# "Parti" è il conteggio degli EVENTI di parto avvenuti (nati vivi + nati morti, richiesta
	# utente 2026-09-06: "quanti parti sono avvenuti", non "quanti bambini esistono") — la riga
	# sotto mostra quanti di quei parti sono sopravvissuti, così il numero non resta ambiguo ora che
	# child_survived è un dato reale (Step 3 effetto nato-morto) e non più sempre true. Testo
	# rivisto su richiesta utente: "nati morti" era troppo esplicito/crudo per una label di UI —
	# "Sopravvissuti" mostra solo il conteggio positivo, senza nominare l'esito negativo.
	total_births_label.text = tr("statistics_total_births").format({"count": birth_events.size()})
	var live_births_count := 0
	for event in birth_events:
		if bool(event["child_survived"]):
			live_births_count += 1
	births_breakdown_label.text = tr("statistics_survived").format({"count": live_births_count})

	# _fill_missing_years — stesso motivo/meccanismo di _refresh_mortality_tab sopra, birth_events
	# è anch'esso un log di eventi puntuali. Include ANCHE i nati morti (stesso criterio di
	# "Nascite totali" sopra: eventi di parto avvenuti, non figli esistenti).
	var births_by_year := {}
	for event in birth_events:
		var year: int = int(event["year"])
		births_by_year[year] = births_by_year.get(year, 0) + 1
	births_per_year_chart.set_data(_fill_missing_years(births_by_year))

	# Una sola passata su birth_events per donna fertile (mai due, una per la media e una per la
	# lista sotto) — {"woman": HumanIndividual, "count": int}, ordine di human_individuals.
	var fertile_women_counts: Array[Dictionary] = []
	for individual in human_individuals:
		if individual.sex != HumanTypes.Sex.FEMALE:
			continue
		var age := float(current_year - individual.birth_year_virtual)
		var age_band := HumanCalculator.get_age_band(durations_male, durations_female, individual.sex, age)
		if age_band != HumanTypes.AgeBand.FERTILE_ADULT:
			continue
		var child_count := 0
		for event in birth_events:
			if int(event["mother_id"]) == individual.id and bool(event["child_survived"]):
				child_count += 1
		fertile_women_counts.append({"woman": individual, "count": child_count})

	# Ordinata per numero di figli DECRESCENTE (richiesta utente, 2026-09-06) — dopo aver
	# calcolato la media sopra (che non dipende dall'ordine), prima di costruire la lista sotto.
	fertile_women_counts.sort_custom(func(a, b): return int(a["count"]) > int(b["count"]))

	if fertile_women_counts.is_empty():
		average_children_label.text = tr("statistics_average_children").format({"value": tr("statistics_not_available")})
	else:
		var total_children := 0
		for entry in fertile_women_counts:
			total_children += int(entry["count"])
		average_children_label.text = tr("statistics_average_children").format({"value": "%.2f" % (float(total_children) / fertile_women_counts.size())})

	for child in fertile_women_list_container.get_children():
		child.queue_free()
	for entry in fertile_women_counts:
		var woman: HumanIndividual = entry["woman"]
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 10)
		label.text = tr("statistics_fertile_woman_row").format({"name": woman.name, "count": int(entry["count"])})
		fertile_women_list_container.add_child(label)


# Step 6b piano statistiche (2026-09-06) — stesso principio degli altri due tab: tutto ricalcolato
# al volo ad ogni apertura, nessuna cache. Totali/distribuzione per fascia d'età calcolati sugli
# individui VIVI ORA (human_individuals), MAI da uno snapshot — population_snapshots serve solo
# per il grafico storico popolazione/anno, un dato diverso ("quant'era la popolazione ALLORA", non
# "quant'è ADESSO").
func _refresh_population_tab(
	human_individuals: Array[HumanIndividual], population_snapshots: Dictionary, current_year: int,
	durations_male: Array[float], durations_female: Array[float]
) -> void:
	total_population_label.text = tr("statistics_total_population").format({"count": human_individuals.size()})

	var male_count := 0
	var female_count := 0
	var age_sum := 0
	for individual in human_individuals:
		age_sum += current_year - individual.birth_year_virtual
		if individual.sex == HumanTypes.Sex.MALE:
			male_count += 1
		else:
			female_count += 1
	male_count_label.text = tr("statistics_males").format({"count": male_count})
	female_count_label.text = tr("statistics_females").format({"count": female_count})
	# Età media dei vivi nell'ambito scelto (2026-10-22, richiesta utente): stessa età della torta per fascia.
	if human_individuals.is_empty():
		population_average_age_label.text = tr("statistics_average_age").format({"age": tr("statistics_not_available")})
	else:
		population_average_age_label.text = tr("statistics_average_age").format({"age": "%.1f" % (float(age_sum) / human_individuals.size())})

	# Itera l'ENUM intero (non solo le fasce osservate) — stesso principio già seguito da
	# _refresh_mortality_tab per le cause di morte: una fascia senza individui compare comunque a
	# 0, invece di sparire silenziosamente dalla torta/legenda.
	var age_band_counts := {}
	for age_band_name in HumanTypes.AgeBand.keys():
		age_band_counts[String(age_band_name).capitalize()] = 0
	for individual in human_individuals:
		var age := float(current_year - individual.birth_year_virtual)
		var age_band := HumanCalculator.get_age_band(durations_male, durations_female, individual.sex, age)
		var age_band_name := String(HumanTypes.AgeBand.keys()[age_band]).capitalize()
		age_band_counts[age_band_name] += 1
	age_band_distribution_chart.set_data(age_band_counts)

	# Già anno->conteggio, nessuna aggregazione necessaria (a differenza di deaths_by_year/
	# births_by_year sopra, che derivano da un log di eventi grezzo) — e nessun _fill_missing_years
	# necessario: uno snapshot viene registrato OGNI anno per costruzione (GameTimeService.
	# _on_year_rolled_over), mai un buco da riempire.
	population_per_year_chart.set_data(population_snapshots)


# Scheda Parametri (2026-10-25, richiesta utente), sui vivi dell'ambito scelto, ricalcolata a ogni apertura:
# - barre: media attuale di ogni parametro in % del massimo, tooltip col valore medio reale (VitalsAverageService);
# - linee: media di fine anno per parametro (GameData.vital_snapshots) più il punto dell'anno in corso;
# - chi sta male: titolo "Malati: n - Feriti: n" (chi ha malattia e ferita conta in tutti e due; malato per salute bassa
#   senza condizioni, HumanIndividual.is_sick, conta tra i malati) ed elenco col motivo accanto al nome.
func _refresh_parameters_tab(human_individuals: Array[HumanIndividual]) -> void:
	_parameter_individuals = human_individuals
	parameters_bar_chart.set_bars(_build_bars(VitalsAverageService.PARAMETERS, PARAMETER_DISPLAY, VitalsAverageService.averages(human_individuals)))
	_refresh_parameters_chart()

	var sick: Array[HumanIndividual] = []
	var ill_count := 0
	var wounded_count := 0
	for individual in human_individuals:
		var has_conditions := not individual.health_conditions.is_empty()
		if not has_conditions and not individual.is_sick():
			continue
		sick.append(individual)
		if not has_conditions or HealthConditionService.has_category(individual, HealthConditionRules.Category.ILLNESS):
			ill_count += 1
		if HealthConditionService.has_category(individual, HealthConditionRules.Category.WOUND):
			wounded_count += 1
	sick_list_caption.text = tr("statistics_sick_title").format({"ill": ill_count, "wounded": wounded_count})

	for child in sick_list_container.get_children():
		child.queue_free()
	for individual in sick:
		var conditions := HealthConditionService.display_names(individual)
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 10)
		label.text = tr("statistics_sick_row").format({
			"name": individual.name,
			"conditions": conditions if conditions != "" else tr("statistics_condition_low_health"),
			"health": int(individual.current_health), "max": int(individual.max_health),
		})
		sick_list_container.add_child(label)


# Linee della scheda Parametri: una per parametro acceso, storia dell'ambito + punto dell'anno in corso.
func _refresh_parameters_chart() -> void:
	if _game_data == null:
		return
	var history: Dictionary = _game_data.vital_snapshots
	if _scope_village_id != SCOPE_ALL:
		history = _game_data.village_vital_snapshots.get(_scope_village_id, {})
	parameters_per_year_chart.set_series(_build_series(
		VitalsAverageService.PARAMETERS, PARAMETER_DISPLAY, _parameter_checks, history,
		VitalsAverageService.average_percents(_parameter_individuals), not _parameter_individuals.is_empty()
	))


# Scheda Skill (2026-10-25, richiesta utente): stessa impostazione di Parametri sulle dieci skill (barre con la sigla
# sotto e il nome intero nel tooltip, linee per anno da GameData.skill_snapshots), poi il migliore dell'ambito per
# ogni skill.
func _refresh_skills_tab(human_individuals: Array[HumanIndividual]) -> void:
	_skill_individuals = human_individuals
	skills_bar_chart.set_bars(_build_bars(VitalsAverageService.SKILLS, SKILL_DISPLAY, VitalsAverageService.skill_averages(human_individuals)))
	_refresh_skills_chart()

	for child in best_skills_container.get_children():
		child.queue_free()
	for i in range(VitalsAverageService.SKILLS.size()):
		var skill := VitalsAverageService.SKILLS[i]
		var best: HumanIndividual = null
		var best_value := 0.0
		for individual in human_individuals:
			var value: float = individual.get(VitalsAverageService.SKILL_FIELDS[i])
			if value > best_value:
				best = individual
				best_value = value
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", SKILL_DISPLAY[skill]["color"])
		label.text = tr("statistics_best_skill_row").format({
			"skill": tr(SKILL_DISPLAY[skill]["name"]),
			"name": best.name if best != null else tr("statistics_not_available"),
			"value": int(best_value),
		})
		best_skills_container.add_child(label)


func _refresh_skills_chart() -> void:
	if _game_data == null:
		return
	var history: Dictionary = _game_data.skill_snapshots
	if _scope_village_id != SCOPE_ALL:
		history = _game_data.village_skill_snapshots.get(_scope_village_id, {})
	skills_per_year_chart.set_series(_build_series(
		VitalsAverageService.SKILLS, SKILL_DISPLAY, _skill_checks, history,
		VitalsAverageService.skill_average_percents(_skill_individuals), not _skill_individuals.is_empty()
	))


# Caselle accese di default, una per chiave, col colore della sua linea; `on_toggled` ridisegna il grafico.
func _build_series_checks(keys: Array[String], display: Dictionary, row: Container, on_toggled: Callable) -> Dictionary:
	var checks := {}
	for key in keys:
		var check := CheckBox.new()
		check.text = tr(display[key]["name"])
		check.button_pressed = true
		check.add_theme_color_override("font_color", display[key]["color"])
		check.toggled.connect(func(_pressed: bool) -> void: on_toggled.call())
		row.add_child(check)
		checks[key] = check
	return checks


# Barre di BarChart da VitalsAverageService: sotto la barra la sigla ("short") se c'è, altrimenti il nome; nel tooltip
# il nome intero e il valore medio reale.
func _build_bars(keys: Array[String], display: Dictionary, averages: Dictionary) -> Array[Dictionary]:
	var bars: Array[Dictionary] = []
	for key in keys:
		var name := tr(display[key]["name"])
		var average: Dictionary = averages[key]
		bars.append({
			"label": tr(display[key]["short"]) if display[key].has("short") else name,
			"value": average["percent"], "color": display[key]["color"],
			"tooltip": tr("statistics_param_tooltip").format({
				"name": name, "current": int(average["current"]), "max": int(average["max"]), "percent": roundi(average["percent"]),
			}),
		})
	return bars


# Una linea per chiave accesa: storia di fine anno + (se ci sono individui) il punto dell'anno in corso.
func _build_series(
	keys: Array[String], display: Dictionary, checks: Dictionary, history: Dictionary, current: Dictionary, add_current: bool
) -> Array:
	var series: Array = []
	for key in keys:
		if not (checks[key] as CheckBox).button_pressed:
			continue
		var by_year: Dictionary = (history.get(key, {}) as Dictionary).duplicate()
		if add_current:
			by_year[_game_data.year] = current[key]
		series.append({"data": by_year, "color": display[key]["color"], "label": tr(display[key]["name"])})
	return series


# Quarto tab Edifici (2026-09-12, richiesta utente) — stesso principio degli altri tre: tutto
# ricalcolato al volo ad ogni apertura, nessuna cache. Distribuzione per CATEGORIA (BuildingTypes.
# Category: RESIDENTIAL/POLITICAL/STORAGE), non per singolo tipo di edificio (hut/pebble_circle/
# deposit_site) — richiesta esplicita dell'utente. building_snapshots passato già risolto dal
# chiamante (game_data.building_snapshots) — NON serve _fill_missing_years qui, stesso motivo di
# population_snapshots in _refresh_population_tab sopra: uno snapshot viene registrato OGNI anno
# per costruzione (StatisticsSnapshotService.record_year_end), mai un buco da riempire.
#
# MOVEMENT escluso (2026-10-03, richiesta utente — per categoria, mai per nome: le celle percorribili, es. terra
# battuta, falsavano i numeri): "Edifici totali", la torta e il grafico per anno contano solo gli altri (building_snapshots
# li esclude dal 2026-10-04, vedi StatisticsSnapshotService.record_year_end). Le celle MOVEMENT compaiono solo come nota tenue sotto
# la legenda della torta ("Vie di passaggio", PieChart.set_footer), volutamente non in evidenza.
#
# Solo edifici completi (2026-10-12, richiesta utente): i cantieri non contano; le macerie (categoria RUINS) non sono
# edifici e non compaiono né nel totale né nella torta.
func _refresh_buildings_tab(buildings: Array[Building], building_snapshots: Dictionary) -> void:
	var counted_buildings: Array[Building] = []
	var movement_count := 0
	for building in buildings:
		if not building.is_complete or building.is_demolished or building.is_rubble():
			continue
		if building.rules != null and building.rules.category == BuildingTypes.Category.MOVEMENT:
			movement_count += 1
		else:
			counted_buildings.append(building)
	total_buildings_label.text = tr("statistics_total_buildings").format({"count": counted_buildings.size()})
	building_type_distribution_chart.set_footer(tr("statistics_movement_cells").format({"count": movement_count}))

	# Itera l'ENUM intero (non solo le categorie osservate) — stesso principio già seguito sopra per
	# cause di morte/fasce d'età: una categoria senza edifici compare comunque a 0, invece di
	# sparire silenziosamente dalla torta/legenda.
	# Nomi tradotti (2026-09-26): chiave "building_category_<nome_minuscolo>", una per valore dell'enum.
	var category_counts := {}
	for category_name in BuildingTypes.Category.keys():
		if BuildingTypes.Category[category_name] in [BuildingTypes.Category.MOVEMENT, BuildingTypes.Category.RUINS]:
			continue
		category_counts[_building_category_display_name(String(category_name))] = 0
	for building in counted_buildings:
		if building.rules == null:
			continue
		var category_name := _building_category_display_name(String(BuildingTypes.Category.keys()[building.rules.category]))
		category_counts[category_name] += 1
	building_type_distribution_chart.set_data(category_counts)

	# set_axis_labels (2026-09-12) — "Year"/"People" di default (vedi LineChart.gd) non hanno senso
	# per un conteggio edifici, a differenza degli altri tre usi (morti/nascite/popolazione, tutti
	# "persone nel tempo") — primo consumatore reale di questo metodo, esisteva già pronto per
	# "un futuro consumatore con semantica diversa" (vedi LineChart.gd).
	buildings_per_year_chart.set_axis_labels(tr("statistics_axis_year"), tr("statistics_axis_buildings"))
	buildings_per_year_chart.set_data(building_snapshots)


# Scheda Influenza (2026-10-12, richiesta utente): per l'ambito scelto (popolo = somma dei villaggi) il valore attuale di
# P/C/R arrotondato con l'incremento previsto a fine anno (VillageInfluenceService.compute_annual_gains, raggi di adesso;
# gli eventi dell'anno non sono prevedibili), il grafico per anno delle serie spuntate e, solo per il popolo, una torta
# per tipo con la ripartizione tra i villaggi.
func _refresh_influence_tab() -> void:
	var villages := _scoped_villages()
	for i in range(INFLUENCE_DISPLAY.size()):
		var influence_type: int = INFLUENCE_DISPLAY[i]["type"]
		var value := 0.0
		var projected := 0
		for village in villages:
			value += village.get_influence_value(influence_type)
			projected += int(VillageInfluenceService.compute_annual_gains(village, _buildings)[influence_type])
		influence_value_labels[i].text = tr("statistics_influence_value").format({
			"name": tr(INFLUENCE_DISPLAY[i]["name"]), "value": roundi(value), "projected": projected,
		})
		influence_value_labels[i].add_theme_color_override("font_color", INFLUENCE_DISPLAY[i]["color"])
	_refresh_influence_chart()
	_refresh_cohesion()
	influence_pies_container.visible = _scope_village_id == SCOPE_ALL
	if not influence_pies_container.visible:
		return
	for i in range(INFLUENCE_DISPLAY.size()):
		var shares := {}
		for village in villages:
			shares[village.get_display_name()] = roundi(village.get_influence_value(INFLUENCE_DISPLAY[i]["type"]))
		influence_pie_charts[i].set_data(shares)


# Solo le serie spuntate. Storia: i valori registrati a ogni cambio d'anno (GameData.village_influence_snapshots),
# sommati sui villaggi dell'ambito; l'anno in corso mostra il valore di adesso, così i guadagni dell'anno si vedono subito.
func _refresh_influence_chart() -> void:
	if _game_data == null:
		return
	var villages := _scoped_villages()
	var series: Array = []
	for i in range(INFLUENCE_DISPLAY.size()):
		if not influence_checks[i].button_pressed:
			continue
		var influence_type: int = INFLUENCE_DISPLAY[i]["type"]
		var by_year := {}
		var current := 0.0
		for village in villages:
			var history: Dictionary = (_game_data.village_influence_snapshots.get(village.id, {}) as Dictionary).get(influence_type, {})
			for year in history:
				by_year[year] = float(by_year.get(year, 0.0)) + float(history[year])
			current += village.get_influence_value(influence_type)
		if not villages.is_empty():
			by_year[_game_data.year] = current
		series.append({"data": by_year, "color": INFLUENCE_DISPLAY[i]["color"], "label": tr(INFLUENCE_DISPLAY[i]["name"])})
	influence_per_year_chart.set_series(series)


# Coesione dell'ambito (2026-10-14): valore attuale (popolo = media dei villaggi) e grafico per anno con una linea per
# villaggio più, per il popolo, la media. Storia: GameData.village_cohesion_snapshots (valore di fine anno, dopo il calo);
# l'anno in corso mostra il valore di adesso, come il grafico delle influenze.
func _refresh_cohesion() -> void:
	if _game_data == null:
		return
	var villages := _scoped_villages()
	var current := 0.0
	for village in villages:
		current += village.cohesion
	if not villages.is_empty():
		current /= float(villages.size())
	cohesion_value_label.text = tr("statistics_cohesion_value").format({"value": "%.1f" % current}) if not villages.is_empty() \
		else tr("statistics_cohesion_no_village")
	var series: Array = []
	var average_by_year := {}
	var count_by_year := {}
	for i in range(villages.size()):
		var village := villages[i]
		var by_year: Dictionary = (_game_data.village_cohesion_snapshots.get(village.id, {}) as Dictionary).duplicate()
		by_year[_game_data.year] = village.cohesion
		for year in by_year:
			average_by_year[year] = float(average_by_year.get(year, 0.0)) + float(by_year[year])
			count_by_year[year] = int(count_by_year.get(year, 0)) + 1
		series.append({
			"data": by_year, "color": Color.from_hsv(fmod(0.08 + 0.17 * float(i), 1.0), 0.55, 0.9),
			"label": village.get_display_name(),
		})
	if _scope_village_id == SCOPE_ALL and villages.size() > 1:
		for year in average_by_year:
			average_by_year[year] = float(average_by_year[year]) / float(count_by_year[year])
		series.append({"data": average_by_year, "color": Color(0.95, 0.95, 0.95), "label": "Popolazione"})
	cohesion_per_year_chart.set_series(series)


# Villaggi dell'ambito: tutti quelli del popolo o solo quello scelto.
func _scoped_villages() -> Array[Village]:
	var result: Array[Village] = []
	if _folk == null:
		return result
	for village in _folk.villages:
		if _scope_village_id == SCOPE_ALL or village.id == _scope_village_id:
			result.append(village)
	return result


func _building_category_display_name(enum_key: String) -> String:
	return tr("building_category_" + enum_key.to_lower())


# Riempie con 0 ogni anno mancante nell'intervallo [0, massimo osservato] tra le chiavi di
# `counts` (richiesta utente, 2026-09-06) — death_events/birth_events sono log di EVENTI puntuali:
# un anno senza eventi semplicemente non compare nell'aggregazione anno->conteggio, ma il grafico
# deve comunque scendere a 0 in quell'anno, non saltarlo (LineChart collega i punti in ordine di
# chiave, un anno mancante diventerebbe un salto diretto invece di un avvallamento a 0). SEMPRE da
# 0 (non dal minimo osservato, come nella prima versione di questo fix) — l'anno 0 è sempre un
# riferimento valido da mostrare: morti/nascite a 0 in quel primissimo anno, prima che i relativi
# meccanismi entrino in gioco (coupling/concepimento/mortalità partono tutti da giorni/anni
# successivi), sono un dato corretto, non un buco. Dizionario vuoto in ingresso resta vuoto in
# uscita (nessun evento MAI registrato — il placeholder di LineChart resta più onesto di un
# singolo punto a (0,0) inventato senza alcun riferimento reale).
func _fill_missing_years(counts: Dictionary) -> Dictionary:
	if counts.is_empty():
		return counts
	var years := counts.keys()
	years.sort()
	var filled := {}
	for year in range(0, int(years[years.size() - 1]) + 1):
		filled[year] = int(counts.get(year, 0))
	return filled
