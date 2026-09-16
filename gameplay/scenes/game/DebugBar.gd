class_name DebugBar
extends PanelContainer

# Barra di debug di GameScene — ancorata in alto a sinistra, colore volutamente diverso dal blu
# usato dal resto della UI (vedi .tscn) per segnalare visivamente che questi controlli sono
# temporanei e spariranno prima della build finale del player (stesso principio gia' scritto nei
# commenti di GameInfoPanel/GameScene per world_debug/macro_cell_debug, solo ora davvero separato
# dalla UI definitiva invece di conviverci dentro). Un solo bottone di controllo (stesso schema
# "un passo indietro" di BuildBar, qui pero' solo due stati — espanso/richiuso, nessuna gerarchia
# di sottomenu: 5 azioni piatte + un'etichetta, non categorie). Muta come GameInfoPanel/BuildBar:
# non conosce World/GameData, si limita a esporre content_row (pubblico, per set_slot_toggled) e
# set_coords() (pubblico) e a inoltrare action_pressed — GameScene resta l'unico posto che decide
# cosa fare. ContentGroup (ContentRow + CoordsLabel) e' il blocco che si nasconde/mostra insieme
# da _apply_state — coords/anno avanzamento sono debug tanto quanto i quattro toggle/salti
# originali (richiesta utente, 2026-09-01: liberare righe nella Sidebar).

@onready var control_button: Button = $MarginContainer/HBoxContainer/ControlButton
@onready var content_group: HBoxContainer = $MarginContainer/HBoxContainer/ContentGroup
@onready var content_row: IconButtonRow = $MarginContainer/HBoxContainer/ContentGroup/ContentRow
@onready var coords_label: Label = $MarginContainer/HBoxContainer/ContentGroup/CoordsLabel
# Toggle "Perditempo" (2026-09-16, richiesta utente) — un Button PIENO, non un altro slot di
# content_row/IconButtonRow: quegli slot sono quadrati 32x32 pensati per un'icona/emoji singola
# (vedi IconButtonRow.gd), qui invece serve un'etichetta leggibile che cambia testo con lo stato
# ("Perditempo: ON"/"Perditempo: OFF", richiesta esplicita) — non ci sta in 32px. Stesso principio
# già in uso per control_button sopra: un Button semplice, figlio diretto dell'HBoxContainer,
# fuori da IconButtonRow, stesso "stile" (tema di default del progetto) degli altri bottoni di
# questa barra. Dentro content_group (non accanto a control_button) cosi' si nasconde/mostra
# insieme al resto degli strumenti di debug quando la barra viene richiusa.
@onready var idle_fallback_button: Button = $MarginContainer/HBoxContainer/ContentGroup/IdleFallbackButton

signal action_pressed(action_id: StringName)

var _expanded: bool = true


func _ready() -> void:
	content_row.configure_slot(
		0, "🌱", tr("toggle_flora_updates_tooltip"), &"toggle_flora_updates", tr("toggle_flora_updates_description")
	)
	content_row.configure_slot(
		1, "🐇", tr("toggle_animals_visibility_tooltip"), &"toggle_animals_visibility",
		tr("toggle_animals_visibility_description")
	)
	content_row.configure_slot(
		2, "🌍", tr("game_info_world_debug"), &"world_debug", tr("game_info_world_debug_description")
	)
	content_row.configure_slot(
		3, "🔬", tr("game_info_macro_cell_debug"), &"macro_cell_debug", tr("game_info_macro_cell_debug_description")
	)
	# Spostato qui dalla CalendarHeaderContainer della Sidebar (richiesta utente, 2026-09-01) —
	# stesso action_id/tooltip di prima, solo il pannello che lo ospita e' cambiato.
	content_row.configure_slot(4, "+1", tr("advance_year_tooltip"), &"advance_year")
	content_row.action_pressed.connect(func(action_id: StringName) -> void: action_pressed.emit(action_id))
	control_button.pressed.connect(_on_control_button_pressed)
	# Toggle "Perditempo" (2026-09-16) — STESSO schema di content_row.action_pressed sopra: emette
	# lo stesso segnale action_pressed con un action_id proprio, cosi' GameScene continua ad avere
	# UN SOLO punto di ascolto (_on_debug_action_pressed) per ogni bottone di questa barra, incluso
	# questo pur non passando da IconButtonRow. Tooltip statico (non cambia con lo stato, a
	# differenza del testo del bottone — vedi set_idle_fallback_label sotto): spiega COSA fa il
	# bottone, non lo stato attuale, che è già leggibile direttamente nel testo.
	idle_fallback_button.tooltip_text = tr("debug_idle_fallback_button_tooltip")
	idle_fallback_button.pressed.connect(func() -> void: action_pressed.emit(&"toggle_idle_fallback"))
	_apply_state()


func _on_control_button_pressed() -> void:
	_expanded = not _expanded
	_apply_state()


func _apply_state() -> void:
	content_group.visible = _expanded
	control_button.text = "◀" if _expanded else "▶"
	# Questo nodo e' figlio diretto di CanvasLayer (non di un Container che lo ridimensiona da
	# solo), quindi il suo Rect2 resta quello scritto in .tscn finche' nessuno lo cambia
	# esplicitamente — reset_size() lo riporta alla propria dimensione minima corrente ad ogni
	# cambio di stato, cosi' il pannello si restringe davvero quando content_group si nasconde
	# invece di lasciare uno spazio viola vuoto della stessa larghezza di prima.
	reset_size()


# Inoltrato da GameScene per riflettere lo stato dei due toggle (flora/animali) — stesso schema
# di IconButtonRow.set_slot_toggled, GameScene continua a decidere QUANDO chiamarlo, questo
# metodo esiste solo perche' content_row non e' esposto direttamente al chiamante.
func set_slot_toggled(index: int, is_active: bool) -> void:
	content_row.set_slot_toggled(index, is_active)


# Spostato qui da GameInfoPanel.set_coords (richiesta utente, 2026-09-01) — stesso formato
# testuale di prima ("Coords: x, y"), GameScene chiama questo invece di quello.
func set_coords(x: int, y: int) -> void:
	coords_label.text = "Coords: " + str(x) + ", " + str(y)


# Aggiorna il TESTO del bottone "Perditempo" (2026-09-16, richiesta utente) — a differenza di
# set_slot_toggled sopra (che cambia solo la tinta di uno slot icona), qui è l'etichetta stessa a
# mostrare lo stato ("Perditempo: ON"/"Perditempo: OFF"), richiesta esplicita — nessuna icona a
# sufficienza per comunicarlo a colpo d'occhio. GameScene chiama questo sia all'avvio (stato
# iniziale di IdleTaskAssignmentService.fallback_enabled) sia ad ogni toggle riuscito — mai
# questa classe stessa, che non conosce IdleTaskAssignmentService (stesso principio "muto" già
# dichiarato in testa al file).
func set_idle_fallback_label(enabled: bool) -> void:
	idle_fallback_button.text = tr("debug_idle_fallback_on") if enabled else tr("debug_idle_fallback_off")
