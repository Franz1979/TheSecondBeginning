class_name GameInfoTabs
extends TabContainer

# Controllo a schede nel body_container di GameInfoPanel (richiesta utente, 2026-09-01) — stesso
# pattern di WorldInfoPanel/MacroCellDetailPanel: tab con solo un'icona/emoji (nessun tr(), non è
# testo), tooltip leggibile a parte via tab_bar. Sostituisce lo spacer elastico che body_container
# aveva prima: questo nodo stesso, con size_flags_vertical=3 (impostato nel .tscn), occupa la
# parte ALTA di body_container — GameScene aggiunge minimap_panel come sibling FISSO sotto questo
# TabContainer, non più dentro una tab (richiesta utente, 2026-09-02: schermo ingrandito, la
# minimappa deve restare sempre visibile in basso invece di essere una scheda tra le altre — vedi
# GameScene per l'ordine di aggiunta a body_container, che determina l'impilamento verticale
# tabs-sopra/minimappa-fissa-sotto). Muto come gli altri componenti di questa famiglia: non
# conosce World/GameData, si limita a esporre population_tab/selection_content (pubblici) perché
# GameScene ci aggiunga i propri contenuti — più center_requested/set_selection_title (Step 3/6,
# 2026-09-04): l'unico bottone "🎯" condiviso da qualunque cosa selection_content stia mostrando, e
# la riga titolo che gli sta accanto, vedi lì sotto.
#
# PopulationTab ospita HumanPopulationInfoPanel (aggiunto da GameScene, richiesta utente,
# 2026-09-01 — stesso schema "componente muto, GameScene lo istanzia/popola" di vegetation_info_
# panel/human_individual_info_panel). PlaceholderTab è un puro placeholder — nessun contenuto,
# nessun significato assegnato ancora, pronta per una futura sezione senza dover ritoccare la
# struttura delle tab.
#
# SelectionTab (richiesta utente, 2026-09-01) mostra il dettaglio di QUALUNQUE cosa sia
# selezionata sulla mappa — oggi solo vegetazione/individuo controllabile (VegetationInfoPanel/
# HumanIndividualInfoPanel, aggiunti qui da GameScene invece che sopra le tab come prima), in
# futuro potenzialmente edifici/altri personaggi. SEMPRE presente in barra (correzione rispetto
# alla prima versione, stesso giorno: comparire/sparire dalla barra a seconda della selezione
# risultava spiazzante) — quando non c'è selezione mostra semplicemente empty_selection_label
# ("Nessuna selezione") al posto del contenuto vero, invece di nascondersi. Il salto automatico
# sulla scheda quando selezioni qualcosa, e il ritorno automatico a quella precedente quando
# deselezioni, restano invariati. show_selection_tab()/hide_selection_tab() sono l'unica
# interfaccia che GameScene deve conoscere, nessun dettaglio di implementazione trapela fuori da
# questa classe. Deliberatamente NIENTE logica specifica-vegetazione/individuo qui dentro (niente
# show_vegetation/clear ecc. — quelli restano sui singoli pannelli, che gestiscono già da sé la
# propria visibilità): questa classe sa solo "sono in modalità selezione oppure no", così il
# giorno in cui quel contenuto dovesse diventare un popup invece di una tab, questa classe non ha
# alcun bisogno di cambiare.

const TAB_POPULATION := 0
# BuildingsTab (2026-09-12, richiesta utente — pannello edifici "concettualmente simile a quella
# population", con etichetta "tra population e la lente di ingrandimento") — inserita in mezzo
# nell'ordine dei nodi (vedi GameInfoTabs.tscn), TAB_SELECTION/TAB_PLACEHOLDER spostati avanti di
# uno di conseguenza. PlaceholderTab NON rimossa (resta comunque "pronta per una futura sezione",
# solo un indice più in là).
const TAB_BUILDINGS := 1
const TAB_SELECTION := 2
const TAB_PLACEHOLDER := 3
# DebugTab (2026-09-12, richiesta utente — "una tab di debug (colore etichetta del debug) nell'info
# panel" per TaskDebugPanel, elenco di tutte le Task assegnate in sessione) — AGGIUNTA IN CODA
# (dopo Placeholder, non prima: nessuna posizione specifica richiesta per questa, a differenza di
# BuildingsTab). Nascosta con set_tab_hidden quando DebugLogging.ENABLED è false (vedi _ready sotto)
# — stesso principio "mai visibile in una build pulita" già seguito da ogni altro elemento debug
# del progetto (tasti T/Y/Z/U, SpeedDebugButton).
const TAB_DEBUG := 4

# Segnale "🎯 centra" (Step 3, richiesta utente 2026-09-04) — sostituisce il bottone che prima
# viveva dentro HumanIndividualInfoPanel (funzionava solo per individui): un solo bottone qui,
# nell'header della SelectionTab, sopra a QUALUNQUE cosa selection_content stia mostrando in quel
# momento (individuo, vegetazione, in futuro edifici) — GameScene lo ascolta e decide cosa fare
# (_center_camera_on_selection, che risolve la posizione in base a GameScene._selection_kind).
# Stesso principio "muto" del resto di questa classe: emette solo il segnale, non sa nulla di COSA
# sta centrando.
signal center_requested

# population_tab/buildings_tab puntano allo ScrollContainer INTERNO di ciascuna tab (Population
# Scroll/BuildingsScroll — bugfix 2026-09-13, richiesta utente: "la scrollbar fa scorrere in alto
# anche le tab"), non più al MarginContainer della tab stessa — GameScene continua a fare
# .add_child(...) su questi due campi esattamente come prima, ignaro del cambio: uno ScrollContainer
# accetta comunque un solo figlio, stesso contratto implicito di prima. La barra schede di questo
# TabContainer (nativa, mai dentro l'area che scorre) resta così SEMPRE fissa in alto qualunque sia
# l'altezza del contenuto aggiunto qui dentro — vedi GameInfoTabs.tscn per la struttura
# MarginContainer > ScrollContainer aggiunta in questo stesso passo.
@onready var population_tab: Control = $PopulationTab/PopulationScroll
@onready var buildings_tab: Control = $BuildingsTab/BuildingsScroll
@onready var selection_tab: Control = $SelectionTab
@onready var debug_tab: Control = $DebugTab
# Contenitore in cui GameScene aggiunge/rimuove i pannelli di dettaglio (VegetationInfoPanel/
# HumanIndividualInfoPanel, in futuro BuildingInfoPanel) — SEPARATO da selection_tab stesso da
# quando è stato introdotto SelectionHeader (Step 3): selection_tab non può più ospitarli
# direttamente come figli sovrapposti, altrimenti si sovrapporrebbero anche all'header invece di
# starci sotto. GameScene usa questo, non più selection_tab, come parent per add_child.
#
# ORA dentro SelectionScroll (bugfix 2026-09-13, stesso motivo di population_tab/buildings_tab
# sopra) — SelectionHeader (titolo + bottone 🎯) resta un sibling FISSO di SelectionScroll dentro
# SelectionTabBody, mai dentro l'area che scorre: un pannello di selezione lungo (es. un individuo
# con molte righe di stato) ora scorre SOTTO l'header, senza mai portarselo via.
@onready var selection_content: Control = $SelectionTab/SelectionTabBody/SelectionScroll/SelectionContent
@onready var selection_header: Control = $SelectionTab/SelectionTabBody/SelectionHeader
# Prima riga di identità della selezione corrente ("Name: X"/"Type: X" — richiesta utente,
# 2026-09-04): vive QUI, sulla stessa riga del bottone "🎯", invece che come prima riga di
# ciascun pannello sotto — l'utente voleva il bottone allineato con "l'inizio" delle info, cosa
# impossibile in senso stretto (il bottone vive un livello sopra rispetto ai singoli pannelli),
# quindi la soluzione concordata è spostare QUELLA riga qui invece. Restiamo "muti" comunque: set_
# selection_title riceve una stringa già pronta dal chiamante (GameScene), non decide mai da sé
# cosa scrivere — stesso principio di empty_selection_label/center_requested sopra.
@onready var title_label: Label = $SelectionTab/SelectionTabBody/SelectionHeader/TitleLabel
@onready var center_button: Button = $SelectionTab/SelectionTabBody/SelectionHeader/CenterButton
@onready var empty_selection_label: Label = $SelectionTab/SelectionTabBody/SelectionScroll/SelectionContent/EmptySelectionLabel

# Scheda su cui si era prima di saltare su SelectionTab — ripristinata da hide_selection_tab().
# Aggiornato da show_selection_tab() SOLO quando non si è già su SelectionTab (vedi lì): così una
# nuova selezione mentre si è già sulla scheda selezione non sovrascrive il "prima" originale, ma
# una selezione fatta dopo essere passati manualmente a un'altra scheda sì — comportamento voluto,
# "torna a dove stavi guardando l'ultima volta prima di entrare in modalità selezione".
var _tab_before_selection: int = TAB_POPULATION


func _ready() -> void:
	# Font/margini ridotti sulla barra delle tab (non sul contenuto) — stesso schema di
	# WorldInfoPanel._ready(), ma leggermente più grande del suo 11 (richiesta utente,
	# 2026-09-01: poche tab qui contro le 6 di WorldInfoPanel, c'è margine per etichette/icone un
	# po' più leggibili senza rischiare le freccette di scroll di TabBar).
	add_theme_font_size_override("font_size", 15)
	add_theme_constant_override("side_margin", 0)

	set_tab_title(TAB_POPULATION, "🧍")
	set_tab_title(TAB_BUILDINGS, "🏠")
	set_tab_title(TAB_SELECTION, "🔍")
	set_tab_title(TAB_PLACEHOLDER, "❔")
	# 🐞 (2026-09-12, richiesta utente) — icona GIÀ di per sé "colorata/riconoscibile come debug"
	# (nessuna infrastruttura di per-tab font color in TabBar/TabContainer da costruire apposta per
	# un'unica scheda) — l'etichetta "DEBUG" vera e propria, in un colore acceso, vive DENTRO il
	# pannello (vedi TaskDebugPanel.tscn), dove uno stile per-Label è banale da applicare.
	set_tab_title(TAB_DEBUG, "🐞")

	var tab_bar := get_tab_bar()
	tab_bar.add_theme_constant_override("h_separation", 0)
	tab_bar.set_tab_tooltip(TAB_POPULATION, tr("game_info_tab_population"))
	tab_bar.set_tab_tooltip(TAB_BUILDINGS, tr("game_info_tab_buildings"))
	tab_bar.set_tab_tooltip(TAB_SELECTION, tr("game_info_tab_selection"))
	tab_bar.set_tab_tooltip(TAB_PLACEHOLDER, tr("game_info_tab_placeholder"))
	tab_bar.set_tab_tooltip(TAB_DEBUG, tr("game_info_tab_debug"))

	# Nascosta fuori da DebugLogging.ENABLED (2026-09-12, richiesta utente — implicito, stesso
	# principio "mai visibile in una build pulita" di ogni altro elemento debug del progetto) —
	# set_tab_hidden, non .visible sul nodo (che TabContainer sovrascrive comunque, vedi CLAUDE.md/
	# MacroCellDetailPanel per lo stesso avvertimento).
	set_tab_hidden(TAB_DEBUG, not DebugLogging.ENABLED)

	empty_selection_label.text = tr("game_info_selection_empty")

	center_button.tooltip_text = tr("center_on_selection_tooltip")
	center_button.pressed.connect(func() -> void: center_requested.emit())


# Chiamata da GameScene quando qualcosa viene selezionato sulla mappa (oggi vegetazione/individuo
# controllabile). Ripetibile: selezionare qualcos'altro mentre si è già su questa tab non fa altro
# che aggiornarne il contenuto (già fatto dal chiamante prima di questa chiamata) — qui serve solo
# a nascondere il messaggio "nessuna selezione" e a saltare sulla tab.
func show_selection_tab() -> void:
	if current_tab != TAB_SELECTION:
		_tab_before_selection = current_tab
	empty_selection_label.visible = false
	selection_header.visible = true
	current_tab = TAB_SELECTION


# Chiamata da GameScene quando la selezione viene tolta. Torna alla scheda su cui si era prima di
# entrare in modalità selezione (vedi _tab_before_selection sopra) e ripristina il messaggio
# "nessuna selezione" per la prossima volta che si apre questa tab senza nulla selezionato.
func hide_selection_tab() -> void:
	empty_selection_label.visible = true
	selection_header.visible = false
	current_tab = _tab_before_selection


# Testo della riga identità (vedi title_label sopra) — GameScene la chiama subito prima/dopo aver
# popolato il pannello vero (show_individual/show_vegetation/show_building), con la stessa stringa
# che quel pannello avrebbe mostrato in prima riga se questa non fosse stata sollevata qui.
func set_selection_title(text: String) -> void:
	title_label.text = text
