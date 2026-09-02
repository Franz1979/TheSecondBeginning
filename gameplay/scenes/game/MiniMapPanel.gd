class_name MiniMapPanel
extends VBoxContainer

# Minimappa della sidebar di GameScene (un pixel per macrocella, stesso schema colori di
# WorldRenderer/TerrainColors — mari/fiumi/montagne/colline inclusi, nessun dettaglio di
# vegetazione/fauna). _base_image (i colori terreno pieni) è costruita una sola volta in setup();
# quale porzione mostrarne a colori è invece dinamico, vedi update_visibility sotto.
#
# ButtonRow (focus/zoom out/zoom in) GALLEGGIA sopra la mappa — MapArea è un Control semplice
# (non un altro VBoxContainer): a differenza di un Container, un Control non impone ai figli di
# impilarsi, quindi MapViewport (ancorato a tutto il rect di MapArea) e ButtonRow (ancorato in
# alto a destra, offset negativo per restare dentro il bordo) si sovrappongono invece di occupare
# righe separate.
#
# Zoom = AVVICINAMENTO, non ingrandimento del riquadro (richiesta utente, 2026-09-01: niente
# scrollbar sulla minimappa). MapViewport ha dimensione FISSA (_square_size x _square_size) e
# clip_contents=true (non una ScrollContainer — nessuna barra nativa): zoomare fa crescere solo
# map_texture_rect al suo interno, e _pan_offset (posizione del ritaglio mostrato) viene
# riposizionato manualmente (map_texture_rect.position = -_pan_offset) invece che scrollato da
# un contenitore. _clamp_pan_offset tiene _pan_offset sempre dentro [0, dimensione_mappa_corrente
# - _square_size] per asse, così il ritaglio non mostra mai oltre il bordo della mappa cresciuta —
# a MIN_ZOOM=1.0 quel range collassa a zero, mappa e riquadro coincidono esattamente, nessun
# ritaglio, comportamento identico a prima dell'introduzione dello zoom "vero".
#
# Come ci si sposta senza scrollbar: un click su una cella (_on_map_gui_input) ricentra il
# ritaglio su quella cella oltre a emettere cell_clicked come già faceva (GameScene sposta la
# camera principale) — nessun drag-to-pan per ora, non richiesto, aggiungibile in seguito se
# serve. Il bottone 🎯 fa la stessa cosa ma centrato sul player invece che sull'ultimo click
# (stesso concetto del 🎯 di GameScene/_center_camera_on_individual, applicato al ritaglio della
# minimappa invece che alla camera principale).
#
# Visibilità (richiesta utente, 2026-08-30): mostra a colori SOLO le macrocelle attualmente vive
# (live_cells) — tutto il resto è nero uniforme, esplorato o no non fa differenza (scelta
# esplicita: la distinzione a tre stati provata in sessione è stata scartata). _base_image (a
# colori pieni, costruita una sola volta in setup()) resta la sorgente da cui update_visibility
# pesca i pixel delle sole celle vive, così non serve ricalcolare i colori terreno ad ogni refresh.
const VOID_COLOR := Color(0.0, 0.0, 0.0)

# Larghezza (= altezza, quadrata) del riquadro visibile SIA della mappa a MIN_ZOOM=1.0 — NON più
# una costante fissa (richiesta utente 2026-09-01: la minimappa deve occupare tutta la larghezza
# disponibile nella Sidebar, qualunque essa sia, restando quadrata), vedi _square_size più sotto
# tra i campi istanza.
const MIN_ZOOM: float = 1.0
const MAX_ZOOM: float = 4.0
const ZOOM_STEP: float = 0.5

# Emesso al click su una macrocella (viva o no, vedi _on_map_gui_input) — GameScene decide cosa
# farne (sposta solo la camera, nessuna attivazione: scelta esplicita confermata con l'utente,
# cliccare sul vuoto/nero non genera nulla, semplicemente mostra il vuoto del canvas lì).
signal cell_clicked(macro_coords: Vector2i)

@onready var map_area: Control = $MapArea
@onready var map_viewport: Control = $MapArea/MapViewport
@onready var map_texture_rect: TextureRect = $MapArea/MapViewport/MapTextureRect
@onready var focus_button: Button = $MapArea/ButtonRow/FocusButton
@onready var zoom_out_button: Button = $MapArea/ButtonRow/ZoomOutButton
@onready var zoom_in_button: Button = $MapArea/ButtonRow/ZoomInButton
@onready var player_marker: Panel = $MapArea/MapViewport/MapTextureRect/PlayerMarker

var _zoom: float = MIN_ZOOM
var _base_image: Image
# Dimensione (px) del riquadro quadrato a MIN_ZOOM — calcolata da _on_panel_resized in base alla
# larghezza reale disponibile (self.size.x, connesso al segnale resized di QUESTO nodo: la
# larghezza non è ancora nota nello stesso frame in cui _ready() gira, stessa classe di problema
# già affrontata altrove in questo file per map_texture_rect.size). 150.0 è solo il valore di
# fallback prima del primo resize reale.
var _square_size: float = 150.0
# Ultima posizione player nota (negativa = mai impostata, vedi _update_player_marker) — serve a
# riposizionare il bordo rosso anche quando cambia solo lo zoom (_apply_zoom), non solo quando
# arriva un nuovo update_visibility con dati freschi.
var _player_macro_coords := Vector2i(-1, -1)
# Angolo in alto a sinistra (px, spazio locale di map_texture_rect) del ritaglio mostrato dentro
# MapViewport — Vector2.ZERO a zoom minimo (nessun ritaglio possibile, vedi _clamp_pan_offset).
# Scritto SOLO da _pan_to/_clamp_pan_offset, mai altrove.
var _pan_offset := Vector2.ZERO
# Costruito in codice invece che nel .tscn (bugfix, 2026-08-30: a zoom=1 una cella è ~2.2px e un
# bordo fisso da 2px per lato la "mangiava" quasi tutta, facendo sembrare il marker disallineato —
# prima, da riempimento pieno, non succedeva) — border_width ricalcolato ad ogni riposizionamento
# in _update_player_marker, mai più di metà cella per lato così resta sempre dentro i suoi confini.
var _player_marker_style := StyleBoxFlat.new()


func _ready() -> void:
	map_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	map_texture_rect.gui_input.connect(_on_map_gui_input)
	focus_button.pressed.connect(_on_focus_pressed)
	zoom_in_button.pressed.connect(_on_zoom_in_pressed)
	zoom_out_button.pressed.connect(_on_zoom_out_pressed)
	_player_marker_style.bg_color = Color(0, 0, 0, 0)
	_player_marker_style.border_color = Color(1, 0, 0, 1)
	player_marker.add_theme_stylebox_override("panel", _player_marker_style)
	_update_zoom_buttons()
	# resized (non una chiamata diretta e basta) perché la larghezza vera che Sidebar/body_
	# container concedono a questo pannello non è nota nello stesso frame — si autocorregge non
	# appena il layout reale si assesta, e resta corretta anche se in futuro la Sidebar cambiasse
	# larghezza a runtime (oggi non succede, ma non richiede alcuna logica speciale qui).
	resized.connect(_on_panel_resized)
	_on_panel_resized()


func setup(world: World) -> void:
	_base_image = Image.create_empty(World.WIDTH, World.HEIGHT, false, Image.FORMAT_RGB8)
	for cell in world.cells:
		_base_image.set_pixel(cell.x, cell.y, TerrainColors.get_cell_color(cell))


# `live_cells` è un Dictionary[Vector2i, bool] (stesso formato di GameScene.live_cells/
# World.lod_focus_live_cells, solo le chiavi contano). `player_macro_coords` posiziona il bordo
# rosso (_update_player_marker, un Panel separato — non un pixel dell'immagine, così il terreno
# sottostante resta visibile) sulla macrocella del player — un Vector2i negativo (nessun player
# ancora posizionato) nasconde il marker.
func update_visibility(live_cells: Dictionary, player_macro_coords: Vector2i) -> void:
	if _base_image == null:
		return
	var display := Image.create_empty(World.WIDTH, World.HEIGHT, false, Image.FORMAT_RGB8)
	display.fill(VOID_COLOR)
	for coords in live_cells:
		if coords.x < 0 or coords.x >= World.WIDTH or coords.y < 0 or coords.y >= World.HEIGHT:
			continue
		display.set_pixel(coords.x, coords.y, _base_image.get_pixel(coords.x, coords.y))
	map_texture_rect.texture = ImageTexture.create_from_image(display)
	_player_macro_coords = player_macro_coords
	_update_player_marker()


# Dimensione (in pixel schermo) di UNA macrocella all'attuale zoom, calcolata da _square_size/_zoom
# invece che da map_texture_rect.size — singola fonte di verità, coerente con come _apply_zoom
# calcola la stessa identica dimensione per map_texture_rect.size stesso. La mappa è sempre
# quadrata (World.WIDTH == World.HEIGHT), quindi un solo valore per entrambi gli assi.
func _cell_px() -> float:
	return (_square_size * _zoom) / float(World.WIDTH)


func _on_map_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var local_pos: Vector2 = map_texture_rect.get_local_mouse_position()
	var cell_px: float = _cell_px()
	var mx: int = clampi(int(local_pos.x / cell_px), 0, World.WIDTH - 1)
	var my: int = clampi(int(local_pos.y / cell_px), 0, World.HEIGHT - 1)
	_pan_to(local_pos)
	cell_clicked.emit(Vector2i(mx, my))


# Stesso concetto del bottone 🎯 di GameScene (_center_camera_on_individual) ma applicato al
# ritaglio della minimappa invece che alla camera principale: ricentra su dove si trova il
# player, non sul centro geometrico della mappa. No-op se il player non ha ancora una posizione
# nota (_player_macro_coords negativo, stesso guard di _update_player_marker).
func _on_focus_pressed() -> void:
	if _player_macro_coords.x < 0 or _player_macro_coords.y < 0:
		return
	var cell_px: float = _cell_px()
	var player_center := Vector2(
		(_player_macro_coords.x + 0.5) * cell_px, (_player_macro_coords.y + 0.5) * cell_px
	)
	_pan_to(player_center)


# Ricentra il ritaglio (MapViewport) su target_px (coordinate nello spazio LOCALE di
# map_texture_rect, stesso spazio di _cell_px()/get_local_mouse_position()) — riusato sia dal
# click sulla mappa sia dal bottone 🎯.
func _pan_to(target_px: Vector2) -> void:
	_pan_offset = target_px - Vector2(_square_size, _square_size) / 2.0
	_clamp_pan_offset()
	map_texture_rect.position = -_pan_offset


# Range valido per asse: [0, dimensione_mappa_corrente - _square_size] — a MIN_ZOOM=1.0 la mappa
# misura esattamente _square_size, quindi il range collassa a [0,0] e _pan_offset resta sempre zero
# (nessun ritaglio possibile, coerente con "a zoom minimo si vede tutta la mappa").
func _clamp_pan_offset() -> void:
	var map_size: float = _square_size * _zoom
	var max_pan: float = maxf(0.0, map_size - _square_size)
	_pan_offset.x = clampf(_pan_offset.x, 0.0, max_pan)
	_pan_offset.y = clampf(_pan_offset.y, 0.0, max_pan)


# Ricalcola _square_size dalla larghezza REALE che questo pannello ha ricevuto (self.size.x —
# MiniMapPanel è un VBoxContainer, quindi la sua larghezza è quella che body_container/
# BodyScrollContainer/Sidebar gli concedono, qualunque essa sia). Guardia is_equal_approx per
# evitare loop: cambiare map_area/map_viewport.custom_minimum_size cambia anche l'altezza
# minima riportata da QUESTO nodo (essendo un VBoxContainer con un solo figlio MapArea), il che
# fa scattare un nuovo resized — ma con la larghezza invariata, quindi la guardia lo ignora senza
# rifare lavoro.
func _on_panel_resized() -> void:
	var available_width := size.x
	if available_width <= 0.0 or is_equal_approx(available_width, _square_size):
		return
	_square_size = available_width
	map_area.custom_minimum_size = Vector2(_square_size, _square_size)
	map_viewport.custom_minimum_size = Vector2(_square_size, _square_size)
	_apply_zoom()


func _on_zoom_in_pressed() -> void:
	_zoom = min(_zoom + ZOOM_STEP, MAX_ZOOM)
	_apply_zoom()


func _on_zoom_out_pressed() -> void:
	_zoom = max(_zoom - ZOOM_STEP, MIN_ZOOM)
	_apply_zoom()


# map_texture_rect NON vive più dentro una Container (MapViewport è un Control semplice, vedi
# commento in testa al file): la sua dimensione va quindi impostata direttamente su .size, non
# basta più custom_minimum_size da solo (che un Container avrebbe applicato automaticamente, un
# Control no) — impostati entrambi comunque, custom_minimum_size resta utile come riferimento
# nell'Inspector.
func _apply_zoom() -> void:
	var new_size := Vector2(_square_size, _square_size) * _zoom
	map_texture_rect.custom_minimum_size = new_size
	map_texture_rect.size = new_size
	_clamp_pan_offset()
	map_texture_rect.position = -_pan_offset
	_update_zoom_buttons()
	_update_player_marker()


# Bordo rosso (non riempimento pieno, richiesta utente 2026-08-30: un quadrato pieno nascondeva
# il terreno sottostante) sulla macrocella del player — un Panel figlio di map_texture_rect,
# ridimensionato/riposizionato in coordinate LOCALI ad esso, così eredita automaticamente
# ritaglio/zoom esattamente come farebbe un pixel dell'immagine, nessuna trasformazione
# aggiuntiva da calcolare qui. mouse_filter = IGNORE (impostato nel .tscn) perché non deve
# intercettare i click destinati alla mappa sotto di lui.
func _update_player_marker() -> void:
	if _player_macro_coords.x < 0 or _player_macro_coords.y < 0:
		player_marker.visible = false
		return
	var cell_px: float = _cell_px()
	player_marker.position = Vector2(_player_macro_coords.x * cell_px, _player_macro_coords.y * cell_px)
	player_marker.size = Vector2(cell_px, cell_px)
	var border_width: int = maxi(1, int(cell_px / 4.0))
	_player_marker_style.border_width_left = border_width
	_player_marker_style.border_width_top = border_width
	_player_marker_style.border_width_right = border_width
	_player_marker_style.border_width_bottom = border_width
	player_marker.visible = true


func _update_zoom_buttons() -> void:
	zoom_in_button.disabled = _zoom >= MAX_ZOOM
	zoom_out_button.disabled = _zoom <= MIN_ZOOM
