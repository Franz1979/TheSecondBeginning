class_name AudioEventListener
extends Node

# Ponte eventi di gioco -> suoni (2026-09-26, richiesta utente). Figlio di GameScene (creato in
# GameScene._ready): ascolta i segnali già emessi dalla scena e chiama AudioManager.play_event con gli
# eventi di SoundEventMap. Nessuna logica di simulazione qui, solo reazioni.
#
# Click dei pulsanti: collegati in modo centralizzato, senza toccare i singoli pannelli. All'ingresso si
# percorre tutto il sottoalbero di GameScene (CanvasLayer e i dialoghi/finestre figli diretti della scena);
# poi SceneTree.node_added intercetta ogni nodo aggiunto in seguito (pannelli, righe e pulsanti creati da
# codice), filtrato sui discendenti di GameScene. Collegamento idempotente (is_connected), quindi un nodo
# rimosso e riaggiunto non suona due volte.

# Pulsanti esclusi dal click: controlli di opzione, non azioni (OptionsMenu e simili). CheckBox e
# CheckButton sono interruttori; OptionButton apre un menu a tendina. Gli slider non sono BaseButton.
const EXCLUDED_BUTTON_CLASSES: Array[String] = ["CheckBox", "CheckButton", "OptionButton"]


func _ready() -> void:
	var game_scene := get_parent()
	if game_scene.has_signal(&"idea_bulb_shown"):
		game_scene.idea_bulb_shown.connect(_on_idea_bulb_shown)
	if game_scene.has_signal(&"world_object_selected"):
		game_scene.world_object_selected.connect(_on_world_object_selected)
	_connect_buttons_in(game_scene)
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


# Lampadina del daydreaming comparsa sopra l'individuo: suono posizionale nel suo punto.
func _on_idea_bulb_shown(global_pos: Vector2) -> void:
	AudioManager.play_event(&"idea_completed", global_pos)


# Oggetto del mondo selezionato con un click: suono di selezione nel punto del click.
func _on_world_object_selected(global_pos: Vector2) -> void:
	AudioManager.play_event(&"ui_selection", global_pos)


# --- Click dei pulsanti ---

func _connect_buttons_in(root: Node) -> void:
	_try_connect_button(root)
	# include_internal: anche i pulsanti interni dei dialoghi (OK/Annulla di AcceptDialog/FileDialog).
	for child in root.get_children(true):
		_connect_buttons_in(child)


func _on_node_added(node: Node) -> void:
	var game_scene := get_parent()
	if game_scene != null and game_scene.is_ancestor_of(node):
		_try_connect_button(node)


func _try_connect_button(node: Node) -> void:
	var button := node as BaseButton
	if button == null or EXCLUDED_BUTTON_CLASSES.has(button.get_class()):
		return
	if not button.pressed.is_connected(_on_button_pressed):
		button.pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	AudioManager.play_event(&"ui_click")
