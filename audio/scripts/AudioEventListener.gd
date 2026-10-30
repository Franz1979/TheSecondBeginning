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
	if game_scene.has_signal(&"rite_effect_shown"):
		game_scene.rite_effect_shown.connect(_on_rite_effect_shown)
	if game_scene.has_signal(&"coordinator_called"):
		game_scene.coordinator_called.connect(_on_coordinator_called)
	if game_scene.has_signal(&"social_rite_effect_shown"):
		game_scene.social_rite_effect_shown.connect(_on_social_rite_effect_shown)
	if game_scene.has_signal(&"star_vigil_called"):
		game_scene.star_vigil_called.connect(_on_star_vigil_called)
	if game_scene.has_signal(&"wild_animal_arrived"):
		game_scene.wild_animal_arrived.connect(_on_wild_animal_arrived)
	if game_scene.has_signal(&"talk_sound_requested"):
		game_scene.talk_sound_requested.connect(_on_talk_sound_requested)
	if game_scene.has_signal(&"world_object_selected"):
		game_scene.world_object_selected.connect(_on_world_object_selected)
	if game_scene.has_signal(&"pending_entry_added"):
		game_scene.pending_entry_added.connect(_on_pending_entry_added)
	_connect_buttons_in(game_scene)
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


# Lampadina del daydreaming comparsa sopra l'individuo: suono posizionale nel suo punto.
func _on_idea_bulb_shown(global_pos: Vector2) -> void:
	AudioManager.play_event(&"idea_completed", global_pos)


# Richiamo del coordinatore (2026-10-09): "hey" posizionale alla sua posizione.
func _on_coordinator_called(global_pos: Vector2) -> void:
	AudioManager.play_event(&"coordinator_call", global_pos)


# Inizio di un rito sociale (2026-10-14): suono della ricetta (SocialRiteRules.start_sound_id), evento
# "social_rite_started:<id>" di SoundEventMap.
func _on_social_rite_effect_shown(global_pos: Vector2, sound_id: StringName) -> void:
	AudioManager.play_event(StringName("social_rite_started:" + String(sound_id)), global_pos)


# Chiamata della Veglia delle stelle (2026-10-29): richiamo posizionale della guida.
func _on_star_vigil_called(global_pos: Vector2) -> void:
	AudioManager.play_event(&"star_vigil_call", global_pos)


# Arrivo di un gruppo di animali selvatici in visita (2026-10-28, lupi L1): suono della specie, evento
# "wild_animal_arrived:<specie>" di SoundEventMap (il lupo ulula).
func _on_wild_animal_arrived(global_pos: Vector2, species: String) -> void:
	AudioManager.play_event(StringName("wild_animal_arrived:" + species), global_pos)


# Talk (2026-10-13): chiamata, risposta e inizio della conversazione, posizionali sul pipottino.
func _on_talk_sound_requested(global_pos: Vector2, event: StringName) -> void:
	AudioManager.play_event(event, global_pos)


# Rito concluso, icona comparsa sull'edificio (2026-10-03): suono posizionale nel punto dell'edificio. Dal 2026-10-04 il
# suono lo sceglie la ricetta (RiteRules.completion_sound_id): evento "rite_completed:<id>" di SoundEventMap; vuoto =
# l'evento predefinito "rite_completed" (rite_paleolithic).
func _on_rite_effect_shown(global_pos: Vector2, sound_id: StringName) -> void:
	var event := &"rite_completed" if sound_id == &"" else StringName("rite_completed:" + String(sound_id))
	AudioManager.play_event(event, global_pos)


# Riga nuova nella campanella "In sospeso" (2026-10-08): suono "bell" sul canale UI, non posizionale.
func _on_pending_entry_added() -> void:
	# Opzione "Suono degli avvisi (campanella)" (2026-10-08): spenta, nessun suono.
	if not UserOptions.pending_bell_sound:
		return
	AudioManager.play_event(&"pending_entry_added")


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
