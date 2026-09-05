class_name NotificationPopup
extends PanelContainer

# Sistema minimo di popup di notifica in-game (richiesta utente, 2026-09-05) — parte da un solo
# caso d'uso (morte di un individuo, vedi NotificationTypes.NotificationPopupType.DEATH) ma
# pensato per essere esteso: enqueue() accetta qualunque tipo/testo già pronto, questa classe non
# sa NULLA del dominio umano/morte — muta, stesso principio "componente muto, il chiamante
# istanzia/popola" già seguito da VegetationInfoPanel/HumanIndividualInfoPanel ecc.
#
# Costruita interamente via codice, nessun .tscn — stesso pattern già usato da HumanIndividualView
# per un componente visivo minimale senza bisogno dell'editor di scene.
#
# Coda semplice in RAM, non persistita (richiesta utente: "non serve una vera coda persistita,
# basta uno scheduling semplice") — un popup alla volta, il successivo parte quando il Timer del
# precedente scade, mai in sovrapposizione.

const DISPLAY_SECONDS := 5.0
const TOP_MARGIN := 24.0

var _label: Label
var _timer: Timer
var _queue: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	# Sfondo esplicito (richiesta implicita "popup" — un PanelContainer nudo rischia di restare
	# quasi invisibile sopra la mappa di gioco col tema di default): pannello scuro semi-opaco,
	# nessuna pretesa stilistica oltre alla leggibilità minima.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05, 0.75)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", style)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(_label)

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = DISPLAY_SECONDS
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)


# Punto d'ingresso pubblico — il chiamante (oggi solo GameScene, per la morte di un individuo)
# passa il tipo (non ancora usato per differenziare stile/icona, solo DEATH esiste — il
# parametro c'è già così quando arriveranno altri tipi non serve toccare la firma) e il testo già
# formattato (questa classe non compone mai il messaggio da sé).
func enqueue(popup_type: NotificationTypes.NotificationPopupType, text: String) -> void:
	_queue.append({"type": popup_type, "text": text})
	if not visible:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		visible = false
		return
	var entry: Dictionary = _queue.pop_front()
	_label.text = entry["text"]
	visible = true
	# Un frame di attesa: lascia che il PanelContainer si ridimensioni sul nuovo testo prima di
	# ricentrare in base alla sua size reale (più robusto di calcolare offset via anchor a mano).
	await get_tree().process_frame
	position = Vector2((get_viewport_rect().size.x - size.x) / 2.0, TOP_MARGIN)
	_timer.start()


func _on_timer_timeout() -> void:
	_show_next()
