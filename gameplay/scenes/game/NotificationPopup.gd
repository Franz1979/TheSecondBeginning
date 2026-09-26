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

const DISPLAY_SECONDS := 3.0 # ridotto da 5.0 a 3.0 (2026-09-09, richiesta utente)
const TOP_MARGIN := 24.0

# Prefisso triangolo (2026-09-14, richiesta utente — variante "alert" per MATERIAL_NEEDED) — un
# vero glifo, non solo un colore diverso: "⚠️ " anteposto al testo già formattato dal chiamante,
# stesso principio "questa classe non compone mai il messaggio da sé" già dichiarato sopra — il
# prefisso è un dettaglio di STILE (come lo sfondo), non di contenuto, quindi resta di competenza
# di questa classe, non del chiamante.
const ALERT_ICON_PREFIX := "⚠️ "

# Emesso quando si entra/esce da una voce requires_ack in attesa di OK (una sola volta per sequenza
# di voci consecutive con OK) — GameScene lo usa per fermare il tempo come per i dialoghi bloccanti.
signal ack_wait_changed(waiting: bool)

var _waiting_ack: bool = false
var _label: Label
var _ok_button: Button
var _timer: Timer
var _queue: Array[Dictionary] = []

# Due StyleBoxFlat pronti in _ready(), MAI ricreati ad ogni _show_next() (2026-09-14, richiesta
# utente — variante "alert" gialla/triangolo per MATERIAL_NEEDED, PRIMA distinzione visiva tra tipi
# di popup in questo sistema, finora un unico stile per tutti — vedi NotificationTypes.gd). Scambiati
# via add_theme_stylebox_override("panel", ...) in _show_next() in base al tipo dell'entry corrente,
# stesso principio "componente muto" già dichiarato in testa al file: NIENTE logica di dominio qui,
# solo "questo tipo usa questo stile".
var _style_default: StyleBoxFlat
var _style_alert: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	# Sfondo esplicito (richiesta implicita "popup" — un PanelContainer nudo rischia di restare
	# quasi invisibile sopra la mappa di gioco col tema di default): pannello scuro semi-opaco,
	# nessuna pretesa stilistica oltre alla leggibilità minima.
	_style_default = StyleBoxFlat.new()
	_style_default.bg_color = Color(0.05, 0.05, 0.05, 0.75)
	_style_default.content_margin_left = 16.0
	_style_default.content_margin_right = 16.0
	_style_default.content_margin_top = 8.0
	_style_default.content_margin_bottom = 8.0

	# Variante "alert" (2026-09-14, richiesta utente) — sfondo giallo acceso, bordo più scuro per
	# leggibilità del bordo su mappe chiare, stessi margini del default (nessuna ragione per un
	# layout diverso, solo il colore/il triangolo cambiano).
	_style_alert = StyleBoxFlat.new()
	_style_alert.bg_color = Color(0.95, 0.75, 0.1, 0.92)
	_style_alert.border_color = Color(0.55, 0.4, 0.0, 1.0)
	_style_alert.border_width_left = 2.0
	_style_alert.border_width_right = 2.0
	_style_alert.border_width_top = 2.0
	_style_alert.border_width_bottom = 2.0
	_style_alert.content_margin_left = 16.0
	_style_alert.content_margin_right = 16.0
	_style_alert.content_margin_top = 8.0
	_style_alert.content_margin_bottom = 8.0

	add_theme_stylebox_override("panel", _style_default)

	# VBox (label + OK) invece del solo Label: il pulsante OK serve alle voci "richiede conferma"
	# (vedi enqueue/requires_ack) — nascosto per tutte le altre, che restano identiche a prima.
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(_label)

	_ok_button = Button.new()
	_ok_button.text = tr("notification_ok")
	_ok_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_ok_button.visible = false
	_ok_button.pressed.connect(_on_ok_pressed)
	box.add_child(_ok_button)

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = DISPLAY_SECONDS
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)


# Punto d'ingresso pubblico — il chiamante (oggi solo GameScene, per la morte di un individuo)
# passa il tipo (non ancora usato per differenziare stile/icona, solo DEATH esiste — il
# parametro c'è già così quando arriveranno altri tipi non serve toccare la firma) e il testo già
# formattato (questa classe non compone mai il messaggio da sé).
#
# requires_ack (2026-09-21, richiesta utente — popup "Nuova idea completata"): invece del Timer,
# la voce resta visibile finché il giocatore preme OK. Le voci successive in coda attendono.
func enqueue(popup_type: NotificationTypes.NotificationPopupType, text: String, requires_ack: bool = false) -> void:
	_queue.append({"type": popup_type, "text": text, "requires_ack": requires_ack})
	if not visible:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		visible = false
		# DOPO visible = false: chi ascolta visibility_changed (es. l'apertura automatica del
		# TechTreePanel) riparte prima che il tempo venga rilasciato, senza un frame di clock attivo.
		_set_waiting_ack(false)
		return
	var entry: Dictionary = _queue.pop_front()
	# Variante "alert" (2026-09-14, richiesta utente) — SOLO per MATERIAL_NEEDED: sfondo giallo +
	# triangolo anteposto + testo scuro (leggibile su sfondo chiaro, a differenza del bianco di
	# default su sfondo scuro). Ogni altro tipo esistente (DEATH/BIRTH/IDEA_COMPLETED/
	# RESOURCE_DECAYED) resta sullo stile scorso finora, invariato.
	# Stile alert anche per BODY_RESERVE_IN_USE (2026-09-19).
	var is_alert: bool = [
		NotificationTypes.NotificationPopupType.MATERIAL_NEEDED,
		NotificationTypes.NotificationPopupType.BODY_RESERVE_IN_USE,
		NotificationTypes.NotificationPopupType.TOOL_REQUIRED,
		NotificationTypes.NotificationPopupType.TASK_REJECTED,
	].has(entry["type"])
	add_theme_stylebox_override("panel", _style_alert if is_alert else _style_default)
	_label.add_theme_color_override("font_color", Color(0.15, 0.1, 0.0) if is_alert else Color.WHITE)
	_label.text = (ALERT_ICON_PREFIX + String(entry["text"])) if is_alert else entry["text"]
	var requires_ack: bool = entry.get("requires_ack", false)
	_ok_button.visible = requires_ack
	_set_waiting_ack(requires_ack)
	# Reset esplicito: un PanelContainer cresce con il contenuto ma non si restringe da solo, e le
	# voci con OK/testo multiriga sono più alte delle altre.
	size = Vector2.ZERO
	visible = true
	# Un frame di attesa: lascia che il PanelContainer si ridimensioni sul nuovo testo prima di
	# ricentrare in base alla sua size reale (più robusto di calcolare offset via anchor a mano).
	await get_tree().process_frame
	position = Vector2((get_viewport_rect().size.x - size.x) / 2.0, TOP_MARGIN)
	if not requires_ack:
		_timer.start()


func _on_timer_timeout() -> void:
	_show_next()


func _set_waiting_ack(waiting: bool) -> void:
	if waiting == _waiting_ack:
		return
	_waiting_ack = waiting
	ack_wait_changed.emit(waiting)


func _on_ok_pressed() -> void:
	_show_next()
