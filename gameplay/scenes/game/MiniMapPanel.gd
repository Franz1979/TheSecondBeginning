class_name MiniMapPanel
extends VBoxContainer

# Minimappa della sidebar di GameScene (un pixel per macrocella, stesso schema colori di
# WorldRenderer/TerrainColors — mari/fiumi/montagne/colline inclusi, nessun dettaglio di
# vegetazione/fauna). _base_image (i colori terreno pieni) è costruita una sola volta in setup();
# quale porzione mostrarne a colori è invece dinamico, vedi update_visibility sotto.
#
# Zoom con bottoni +/-, non con la rotellina: la mappa vive dentro una ScrollContainer che usa
# già la rotellina per scorrere una volta ingrandita — sovrapporci lo zoom sullo stesso gesto
# renderebbe ambiguo "sto scorrendo o sto zoomando" (scelta discussa con l'utente). Zoomare
# aumenta semplicemente il custom_minimum_size di map_texture_rect oltre la dimensione fissa
# della ScrollContainer: questa mostra da sola le scrollbar non appena il contenuto la supera,
# nessuna logica di scroll manuale necessaria.
#
# Visibilità (richiesta utente, 2026-08-30): mostra a colori SOLO le macrocelle attualmente vive
# (live_cells) — tutto il resto è nero uniforme, esplorato o no non fa differenza (scelta
# esplicita: la distinzione a tre stati provata in sessione è stata scartata). _base_image (a
# colori pieni, costruita una sola volta in setup()) resta la sorgente da cui update_visibility
# pesca i pixel delle sole celle vive, così non serve ricalcolare i colori terreno ad ogni refresh.
const VOID_COLOR := Color(0.0, 0.0, 0.0)

const BASE_SIZE: float = 220.0
const MIN_ZOOM: float = 1.0
const MAX_ZOOM: float = 4.0
const ZOOM_STEP: float = 0.5

# Emesso al click su una macrocella (viva o no, vedi _on_map_gui_input) — GameScene decide cosa
# farne (sposta solo la camera, nessuna attivazione: scelta esplicita confermata con l'utente,
# cliccare sul vuoto/nero non genera nulla, semplicemente mostra il vuoto del canvas lì).
signal cell_clicked(macro_coords: Vector2i)

@onready var map_texture_rect: TextureRect = $ScrollContainer/MapTextureRect
@onready var zoom_in_button: Button = $ZoomControls/ZoomInButton
@onready var zoom_out_button: Button = $ZoomControls/ZoomOutButton
@onready var player_marker: Panel = $ScrollContainer/MapTextureRect/PlayerMarker

var _zoom: float = MIN_ZOOM
var _base_image: Image
# Ultima posizione player nota (negativa = mai impostata, vedi _update_player_marker) — serve a
# riposizionare il bordo rosso anche quando cambia solo lo zoom (_apply_zoom), non solo quando
# arriva un nuovo update_visibility con dati freschi.
var _player_macro_coords := Vector2i(-1, -1)
# Costruito in codice invece che nel .tscn (bugfix, 2026-08-30: a zoom=1 una cella è ~2.2px e un
# bordo fisso da 2px per lato la "mangiava" quasi tutta, facendo sembrare il marker disallineato —
# prima, da riempimento pieno, non succedeva) — border_width ricalcolato ad ogni riposizionamento
# in _update_player_marker, mai più di metà cella per lato così resta sempre dentro i suoi confini.
var _player_marker_style := StyleBoxFlat.new()


func _ready() -> void:
	map_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	map_texture_rect.gui_input.connect(_on_map_gui_input)
	zoom_in_button.pressed.connect(_on_zoom_in_pressed)
	zoom_out_button.pressed.connect(_on_zoom_out_pressed)
	_player_marker_style.bg_color = Color(0, 0, 0, 0)
	_player_marker_style.border_color = Color(1, 0, 0, 1)
	player_marker.add_theme_stylebox_override("panel", _player_marker_style)
	_update_zoom_buttons()


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


# Dimensione (in pixel schermo) di UNA macrocella all'attuale zoom — calcolata da BASE_SIZE/_zoom,
# MAI da map_texture_rect.size (bugfix, 2026-08-30: Godot ricalcola size in modo differito dopo un
# cambio di custom_minimum_size, non nello stesso frame — leggerla subito dopo _apply_zoom dava un
# valore ancora vecchio di uno step, disallineando il marker del player appena si zoomava). La
# mappa è sempre quadrata (World.WIDTH == World.HEIGHT), quindi un solo valore per entrambi gli assi.
func _cell_px() -> float:
	return (BASE_SIZE * _zoom) / float(World.WIDTH)


func _on_map_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var local_pos: Vector2 = map_texture_rect.get_local_mouse_position()
	var cell_px: float = _cell_px()
	var mx: int = clampi(int(local_pos.x / cell_px), 0, World.WIDTH - 1)
	var my: int = clampi(int(local_pos.y / cell_px), 0, World.HEIGHT - 1)
	cell_clicked.emit(Vector2i(mx, my))


func _on_zoom_in_pressed() -> void:
	_zoom = min(_zoom + ZOOM_STEP, MAX_ZOOM)
	_apply_zoom()


func _on_zoom_out_pressed() -> void:
	_zoom = max(_zoom - ZOOM_STEP, MIN_ZOOM)
	_apply_zoom()


func _apply_zoom() -> void:
	map_texture_rect.custom_minimum_size = Vector2(BASE_SIZE, BASE_SIZE) * _zoom
	_update_zoom_buttons()
	_update_player_marker()


# Bordo rosso (non riempimento pieno, richiesta utente 2026-08-30: un quadrato pieno nascondeva
# il terreno sottostante) sulla macrocella del player — un Panel figlio di map_texture_rect,
# ridimensionato/riposizionato in coordinate LOCALI ad esso, così eredita automaticamente scroll e
# zoom esattamente come farebbe un pixel dell'immagine, nessuna trasformazione aggiuntiva da
# calcolare qui. mouse_filter = IGNORE (impostato nel .tscn) perché non deve intercettare i click
# destinati alla mappa sotto di lui.
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
