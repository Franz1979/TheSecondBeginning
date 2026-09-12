class_name TaskDebugPanel
extends VBoxContainer

# Corpo della tab di debug 🐞 (2026-09-12, richiesta utente — "una tab di debug (colore etichetta
# del debug)... elencami tutte le task con id, nome task, l'assegnatario, lo stato... in ordine
# dalla più recente sopra, con un piccolo button clear") — A DIFFERENZA di ogni altro pannello del
# progetto, questo NON è "muto": legge direttamente TaskDebugRegistry (uno strumento diagnostico,
# non uno stato di simulazione — stesso principio per cui DebugLogging stessa è consultata
# direttamente ovunque nel progetto, senza dover passare da GameScene). Nessuna interazione con
# World/HumanIndividual VIVI: le entry sono già dati "morti" (id/nome copiati al momento della
# registrazione, vedi TaskDebugRegistry.gd) — non c'è nulla qui che possa corrompere lo stato di
# simulazione, solo lettura.
#
# GameScene richiama refresh() in due punti automatici (non un binding push in tempo reale, che
# avrebbe richiesto un signal per OGNI assegnazione/chiusura Task nel progetto — sproporzionato per
# un pannello diagnostico): quando la tab diventa quella attiva (GameInfoTabs.tab_changed) e al
# tick giornaliero (stesso schema di _refresh_population_panel/_refresh_buildings_panel).
#
# BUGFIX 1 (2026-09-12, richiesta utente — "il pannello debug task non si riempie mai di nessuna
# task"): quei due punti automatici NON bastavano da soli — restando fermi sulla tab 🐞 mentre si
# assegnano Task (il modo più naturale di testare questa funzione: apri la tab, premi R/G, guarda),
# tab_changed non scatta più (nessun cambio scheda) e il tick giornaliero è troppo raro per un test
# rapido. Aggiunto un bottone "🔄" di refresh manuale sotto: nessuna scommessa sulla cadenza
# automatica, il player controlla direttamente quando rileggere il registro.
#
# BUGFIX 2 (2026-09-12, richiesta utente, stesso giro — "non si vede nulla... in altezza non
# cresce mai, è al minimo") — VERIFICATO con log temporanei (poi rimossi): i dati arrivavano
# perfettamente (TaskDebugRegistry.get_entries() tornava le entry giuste, list_container le
# riceveva come figli) — il problema era SOLO di layout. ScrollContainer (vedi TaskDebugPanel.tscn)
# di per sé richiede una dimensione minima quasi nulla (il suo scopo è far scorrere il contenuto in
# eccesso, non spingere il layout esterno a crescere per farcelo stare) — senza un custom_minimum_
# size esplicito, il pannello restava schiacciato all'altezza della sola HeaderRow (~26px, visto
# nei log), qualunque fosse il contenuto sotto. Risolto impostando custom_minimum_size = (0, 220)
# sul nodo ScrollContainer nel .tscn — garantisce un'area visibile decente indipendentemente da
# quante righe ci siano davvero in un dato momento.
const REFRESH_BUTTON_TEXT := "🔄"

const STATUS_COLOR_IN_PROGRESS := Color(0.95, 0.85, 0.3)
const STATUS_COLOR_COMPLETED := Color(0.4, 0.9, 0.4)
const STATUS_COLOR_INTERRUPTED := Color(0.9, 0.35, 0.35)
# Colore acceso per l'etichetta "DEBUG" (2026-09-12, richiesta utente: "colore etichetta del
# debug") — vive QUI, non sulla tab stessa (GameInfoTabs.set_tab_title usa solo un'icona 🐞, nessuna
# infrastruttura di per-tab font color in TabBar/TabContainer da costruire apposta per un'unica
# scheda) — uno stile per-Label dentro il pannello è invece banale.
const DEBUG_LABEL_COLOR := Color(0.95, 0.45, 0.15)

@onready var header_label: Label = $HeaderRow/HeaderLabel
@onready var refresh_button: Button = $HeaderRow/RefreshButton
@onready var clear_button: Button = $HeaderRow/ClearButton
@onready var list_container: VBoxContainer = $ScrollContainer/ListContainer


func _ready() -> void:
	header_label.text = "🐞 " + tr("task_debug_panel_header")
	header_label.add_theme_color_override("font_color", DEBUG_LABEL_COLOR)
	refresh_button.text = REFRESH_BUTTON_TEXT
	refresh_button.tooltip_text = tr("task_debug_panel_refresh_button_tooltip")
	refresh_button.pressed.connect(refresh)
	clear_button.text = tr("task_debug_panel_clear_button")
	clear_button.pressed.connect(_on_clear_pressed)
	refresh()


# Ricostruita per intero ad ogni chiamata (stesso principio "rebuild da zero" già in uso ovunque
# nel progetto per contenuto derivato) — TaskDebugRegistry.get_entries() è già ordinato più-
# recente-in-testa (push_front all'inserimento, vedi TaskDebugRegistry.gd), nessun sort qui.
# remove_child() PRIMA di queue_free() (2026-09-12) — rimozione immediata dall'albero invece di
# aspettare la deallocazione differita, così due refresh() ravvicinati non vedono mai transitoriamente
# sia le righe vecchie che quelle nuove insieme.
func refresh() -> void:
	for child in list_container.get_children():
		list_container.remove_child(child)
		child.queue_free()
	for entry in TaskDebugRegistry.get_entries():
		list_container.add_child(_build_row(entry))


func _build_row(entry: Dictionary) -> Control:
	var row := Label.new()
	row.add_theme_font_size_override("font_size", 10)
	var task_name: String = String(entry.get("task_name", ""))
	if task_name == "":
		task_name = tr("task_debug_panel_unnamed_task")
	var status: String = String(entry.get("status", ""))
	row.text = "#%d — %s — %s (#%d) — %s" % [
		int(entry.get("id", 0)),
		task_name,
		String(entry.get("individual_name", "")),
		int(entry.get("individual_id", 0)),
		status,
	]
	row.add_theme_color_override("font_color", _status_color(status))
	return row


func _status_color(status: String) -> Color:
	match status:
		TaskDebugRegistry.STATUS_COMPLETED:
			return STATUS_COLOR_COMPLETED
		TaskDebugRegistry.STATUS_INTERRUPTED:
			return STATUS_COLOR_INTERRUPTED
		_:
			return STATUS_COLOR_IN_PROGRESS


func _on_clear_pressed() -> void:
	TaskDebugRegistry.clear()
	refresh()
