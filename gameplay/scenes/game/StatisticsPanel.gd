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
const TAB_MORTALITY := 0
# Step 5/6 piano statistiche (2026-09-06) — secondo/terzo tab, stessa convenzione (indice del
# nodo figlio nel TabContainer, mai .visible toggled da codice).
const TAB_BIRTHS := 1
const TAB_POPULATION := 2
# Quarto tab (2026-09-12, richiesta utente) — stessa identica convenzione dei tre sopra.
const TAB_BUILDINGS := 3

@onready var tab_container: TabContainer = $MarginContainer/VBoxContainer/TabContainer
@onready var close_button: Button = $MarginContainer/VBoxContainer/CloseButton
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
@onready var age_band_distribution_chart: PieChart = $MarginContainer/VBoxContainer/TabContainer/PopulationTab/PopulationContent/AgeBandDistributionChart
@onready var population_per_year_chart: LineChart = $MarginContainer/VBoxContainer/TabContainer/PopulationTab/PopulationContent/PopulationPerYearChart

@onready var total_buildings_label: Label = $MarginContainer/VBoxContainer/TabContainer/BuildingsTab/BuildingsContent/TotalBuildingsLabel
@onready var buildings_per_year_chart: LineChart = $MarginContainer/VBoxContainer/TabContainer/BuildingsTab/BuildingsContent/BuildingsPerYearChart
@onready var building_type_distribution_chart: PieChart = $MarginContainer/VBoxContainer/TabContainer/BuildingsTab/BuildingsContent/BuildingTypeDistributionChart


func _ready() -> void:
	title = tr("statistics_tooltip")
	tab_container.set_tab_title(TAB_MORTALITY, tr("statistics_tab_mortality"))
	tab_container.set_tab_title(TAB_BIRTHS, tr("statistics_tab_births"))
	tab_container.set_tab_title(TAB_POPULATION, tr("statistics_tab_population"))
	tab_container.set_tab_title(TAB_BUILDINGS, tr("statistics_tab_buildings"))
	# Titoli lista donne fertili/lista morti (richiesta utente, 2026-09-06) — tr(), non hardcoded
	# come il resto del CONTENUTO dati di questo pannello: sono più simili alla "chrome" strutturale
	# (titolo di una sezione, come i tab) che a un dato calcolato, stessa eccezione esplicitamente
	# richiesta per entrambi.
	fertile_women_list_caption.text = tr("fertile_women_list")
	death_list_caption.text = tr("death_list")
	close_button.text = tr("close_menu")
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
func open_dialog(game_data: GameData, human_individuals: Array[HumanIndividual], buildings: Array[Building]) -> void:
	_refresh_mortality_tab(game_data.death_events)
	_refresh_births_tab(
		game_data.birth_events, human_individuals, game_data.year,
		game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female
	)
	_refresh_population_tab(
		human_individuals, game_data.population_snapshots, game_data.year,
		game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female
	)
	_refresh_buildings_tab(buildings, game_data.building_snapshots)
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


func _refresh_mortality_tab(death_events: Array[Dictionary]) -> void:
	total_label.text = "Morti totali: %d" % death_events.size()

	if death_events.is_empty():
		average_age_label.text = "Età media alla morte: N/D"
	else:
		var age_sum := 0
		for event in death_events:
			age_sum += int(event["age_at_death"])
		average_age_label.text = "Età media alla morte: %.1f" % (float(age_sum) / death_events.size())

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
		label.text = "%s — età %d, %s (anno %d, giorno %d)" % [
			event["name"], event["age_at_death"], String(_cause_name(int(event["cause"]))).capitalize(),
			event["year"], event["day"],
		]
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
	total_births_label.text = "Parti: %d" % birth_events.size()
	var live_births_count := 0
	for event in birth_events:
		if bool(event["child_survived"]):
			live_births_count += 1
	births_breakdown_label.text = "Sopravvissuti: %d" % live_births_count

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
		average_children_label.text = "Media figli per donna fertile: N/D"
	else:
		var total_children := 0
		for entry in fertile_women_counts:
			total_children += int(entry["count"])
		average_children_label.text = "Media figli per donna fertile: %.2f" % (float(total_children) / fertile_women_counts.size())

	for child in fertile_women_list_container.get_children():
		child.queue_free()
	for entry in fertile_women_counts:
		var woman: HumanIndividual = entry["woman"]
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 10)
		label.text = "%s — %d figli" % [woman.name, int(entry["count"])]
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
	total_population_label.text = "Popolazione totale: %d" % human_individuals.size()

	var male_count := 0
	var female_count := 0
	for individual in human_individuals:
		if individual.sex == HumanTypes.Sex.MALE:
			male_count += 1
		else:
			female_count += 1
	male_count_label.text = "Maschi: %d" % male_count
	female_count_label.text = "Femmine: %d" % female_count

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


# Quarto tab Edifici (2026-09-12, richiesta utente) — stesso principio degli altri tre: tutto
# ricalcolato al volo ad ogni apertura, nessuna cache. Distribuzione per CATEGORIA (BuildingTypes.
# Category: RESIDENTIAL/POLITICAL/STORAGE), non per singolo tipo di edificio (hut/pebble_circle/
# deposit_site) — richiesta esplicita dell'utente. building_snapshots passato già risolto dal
# chiamante (game_data.building_snapshots) — NON serve _fill_missing_years qui, stesso motivo di
# population_snapshots in _refresh_population_tab sopra: uno snapshot viene registrato OGNI anno
# per costruzione (GameScene._on_year_rolled_over), mai un buco da riempire.
func _refresh_buildings_tab(buildings: Array[Building], building_snapshots: Dictionary) -> void:
	total_buildings_label.text = "Edifici totali: %d" % buildings.size()

	# Itera l'ENUM intero (non solo le categorie osservate) — stesso principio già seguito sopra per
	# cause di morte/fasce d'età: una categoria senza edifici compare comunque a 0, invece di
	# sparire silenziosamente dalla torta/legenda.
	var category_counts := {}
	for category_name in BuildingTypes.Category.keys():
		category_counts[String(category_name).capitalize()] = 0
	for building in buildings:
		if building.rules == null:
			continue
		var category_name := String(BuildingTypes.Category.keys()[building.rules.category]).capitalize()
		category_counts[category_name] += 1
	building_type_distribution_chart.set_data(category_counts)

	# set_axis_labels (2026-09-12) — "Year"/"People" di default (vedi LineChart.gd) non hanno senso
	# per un conteggio edifici, a differenza degli altri tre usi (morti/nascite/popolazione, tutti
	# "persone nel tempo") — primo consumatore reale di questo metodo, esisteva già pronto per
	# "un futuro consumatore con semantica diversa" (vedi LineChart.gd).
	buildings_per_year_chart.set_axis_labels("Anno", "Edifici")
	buildings_per_year_chart.set_data(building_snapshots)


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
