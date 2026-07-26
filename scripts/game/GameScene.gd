extends Node2D

var world: World
var game_data: GameData
var renderer: WorldRenderer
var game_controller: CellSelectorController
var clock: GameClockController
var _clock_was_playing_before_dialogs: bool = false
var _open_dialog_count: int = 0
var _pending_leave_action: StringName = &""

@onready var primary_actions_bar: IconButtonRow = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/PrimaryActionsBar
@onready var secondary_actions_bar: IconButtonRow = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/SecondaryActionsBar
@onready var system_menu_dialog: SystemMenuDialog = $SystemMenuDialog
@onready var save_confirmation_dialog: SaveConfirmationDialog = $SaveConfirmationDialog
@onready var save_game_file_dialog: FileDialog = $SaveGameFileDialog
@onready var macro_cell_info_panel: MacroCellInfoPanel = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/MacroCellInfoPanel
@onready var year_title_label: Label = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/CalendarHeaderContainer/YearTitleLabel
@onready var year_label: Label = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/YearLabel
@onready var play_pause_button: Button = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/PlayPauseButton
@onready var speed_buttons: Dictionary = {
	GameClockController.Speed.X1: $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/Speed1xButton,
	GameClockController.Speed.X2: $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/Speed2xButton,
	GameClockController.Speed.X3: $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/Speed3xButton,
	GameClockController.Speed.X4: $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/Speed4xButton,
}
@onready var advance_year_button: Button = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/CalendarHeaderContainer/AdvanceYearButton
@onready var season_progress_bar: SeasonProgressBar = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/SeasonProgressBar
@onready var debug_secondary_stock_container: HBoxContainer = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/DebugSecondaryStockContainer
@onready var debug_consume_spin_box: SpinBox = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/DebugSecondaryStockContainer/DebugConsumeSpinBox
@onready var debug_consume_button: Button = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/DebugSecondaryStockContainer/DebugConsumeButton
@onready var debug_consume_acorn_container: HBoxContainer = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/DebugConsumeAcornContainer
@onready var debug_consume_acorn_spin_box: SpinBox = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/DebugConsumeAcornContainer/DebugConsumeAcornSpinBox
@onready var debug_consume_acorn_button: Button = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/DebugConsumeAcornContainer/DebugConsumeAcornButton
@onready var debug_consume_fruit_container: HBoxContainer = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/DebugConsumeFruitContainer
@onready var debug_consume_fruit_spin_box: SpinBox = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/DebugConsumeFruitContainer/DebugConsumeFruitSpinBox
@onready var debug_consume_fruit_button: Button = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/DebugConsumeFruitContainer/DebugConsumeFruitButton
@onready var debug_rabbit_container: HBoxContainer = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/DebugRabbitContainer
@onready var debug_rabbit_spin_box: SpinBox = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/DebugRabbitContainer/DebugRabbitSpinBox
@onready var debug_set_rabbit_button: Button = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/DebugRabbitContainer/DebugSetRabbitButton

func _ready() -> void:
	year_title_label.text = tr("calendar_label")
	advance_year_button.text = "+1"
	advance_year_button.tooltip_text = tr("advance_year_tooltip")
	advance_year_button.pressed.connect(_on_advance_year_pressed)
	save_game_file_dialog.access = FileDialog.ACCESS_USERDATA
	save_game_file_dialog.current_dir = GameSettings.SAVES_DIR
	save_game_file_dialog.file_selected.connect(_on_save_game_file_selected)

	secondary_actions_bar.configure_slot(0, "☰", tr("menu"), &"menu")
	secondary_actions_bar.action_pressed.connect(_on_secondary_action_pressed)
	system_menu_dialog.add_action(tr("save_game"), &"save")
	system_menu_dialog.add_action(tr("back_to_menu"), &"back_to_main_menu")
	system_menu_dialog.add_action(tr("exit"), &"exit_game")
	system_menu_dialog.action_selected.connect(_on_system_menu_action_selected)
	system_menu_dialog.visibility_changed.connect(_on_blocking_dialog_visibility_changed.bind(system_menu_dialog))
	save_confirmation_dialog.option_selected.connect(_on_save_confirmation_option_selected)
	save_confirmation_dialog.visibility_changed.connect(_on_blocking_dialog_visibility_changed.bind(save_confirmation_dialog))

	# TEMPORANEO: pannello per testare a mano il consumo/stock di berry/acorn/fruit sulla cella
	# (50,50) durante il gioco, senza fermarsi nel debugger. Va rimosso quando esisterà un vero
	# consumatore (fauna) per le fonti caloriche a stock persistente.
	debug_secondary_stock_container.visible = DebugLogging.ENABLED
	debug_consume_acorn_container.visible = DebugLogging.ENABLED
	debug_consume_fruit_container.visible = DebugLogging.ENABLED
	debug_rabbit_container.visible = DebugLogging.ENABLED
	debug_consume_button.pressed.connect(_on_debug_consume_pressed)
	debug_consume_acorn_button.pressed.connect(_on_debug_consume_acorn_pressed)
	debug_consume_fruit_button.pressed.connect(_on_debug_consume_fruit_pressed)
	debug_set_rabbit_button.pressed.connect(_on_debug_set_rabbit_pressed)

	var returning_from_macro_cell := GameSettings.returning_to_game_scene
	if returning_from_macro_cell:
		GameSettings.returning_to_game_scene = false
		world = GameSettings.active_world
		game_data = GameSettings.active_game_data
	else:
		_load_world()
	_create_renderer()
	_setup_clock()
	_update_calendar_display()

	game_controller = CellSelectorController.new()
	game_controller.setup(world, renderer)
	game_controller.cell_selected.connect(_on_cell_selected)
	macro_cell_info_panel.visible = true

	if returning_from_macro_cell:
		var cell := world.get_cell_at(GameSettings.selected_macro_cell_x, GameSettings.selected_macro_cell_y)
		if cell != null:
			_on_cell_selected(cell, world.get_cell_state_at(cell.x, cell.y))


func _load_world() -> void:
	if GameSettings.selected_save_file != "":
		var load_service := GameLoadService.new()
		var loaded_game := load_service.load_game_from_json(GameSettings.selected_save_file)
		if loaded_game == null:
			print("Caricamento partita fallito. Genero mondo vuoto.")
			game_data = GameData.new()
			world = World.new()
			world.generate_empty_world()
			return
		world = loaded_game.world
		game_data = loaded_game.game_data
		return

	if GameSettings.selected_map_type == "saved" and GameSettings.selected_map_file != "":
		var load_service := WorldLoadService.new()
		world = load_service.load_world_from_json(GameSettings.selected_map_file)
		if world == null:
			print("Caricamento mappa fallito. Genero mondo vuoto.")
			world = World.new()
			world.generate_empty_world()
		else:
			world.ensure_cell_states()
	elif GameSettings.selected_map_type == "random":
		world = World.new()
		world.generate_empty_world()
	else:
		world = World.new()
		world.generate_empty_world()

	if game_data == null:
		game_data = GameData.new()

	var resource_service := InitialResourceSetupService.new()
	resource_service.populate_resources(world)

func _create_renderer() -> void:
	renderer = WorldRenderer.new()
	add_child(renderer)
	renderer.setup(world, game_data)

func _setup_clock() -> void:
	clock = GameClockController.new()
	add_child(clock)
	clock.setup(world, game_data)
	clock.is_playing = GameSettings.active_clock_is_playing
	clock.speed = GameSettings.active_clock_speed
	clock.day_advanced.connect(_on_day_advanced)
	play_pause_button.pressed.connect(_on_play_pause_pressed)
	for speed in speed_buttons.keys():
		speed_buttons[speed].pressed.connect(_on_speed_button_pressed.bind(speed))
	_update_play_pause_button()
	speed_buttons[clock.speed].button_pressed = true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
		_open_macro_cell_scene()
		return
	if game_controller != null:
		game_controller.handle_input(event)

func _open_macro_cell_scene() -> void:
	var mouse_pos: Vector2 = renderer.get_local_mouse_position()
	var cell_x := int(mouse_pos.x / WorldRenderer.CELL_SIZE)
	var cell_y := int(mouse_pos.y / WorldRenderer.CELL_SIZE)
	var cell := world.get_cell_at(cell_x, cell_y)
	if cell == null:
		return
	GameSettings.selected_macro_cell_x = cell.x
	GameSettings.selected_macro_cell_y = cell.y
	GameSettings.active_world = world
	GameSettings.active_game_data = game_data
	GameSettings.active_clock_is_playing = clock.is_playing
	GameSettings.active_clock_speed = clock.speed
	get_tree().change_scene_to_file("res://scenes/game/MacroCellScene.tscn")


func _on_cell_selected(cell: MacroCellData, state: MacroCellState) -> void:
	macro_cell_info_panel.show_cell(cell, state)
	renderer.set_selected_cell(cell)

func _on_save_game_pressed() -> void:
	save_game_file_dialog.popup_centered()

func _on_save_game_file_selected(path: String) -> void:
	var save_service := GameSaveService.new()

	save_service.save_game_to_json(
		world,
		game_data,
		path
	)

	if _pending_leave_action != &"":
		_execute_pending_leave_action()

func _on_secondary_action_pressed(action_id: StringName) -> void:
	match action_id:
		&"menu":
			system_menu_dialog.open_menu()

func _on_blocking_dialog_visibility_changed(dialog: Window) -> void:
	if dialog.visible:
		if _open_dialog_count == 0:
			_clock_was_playing_before_dialogs = clock.is_playing
			if clock.is_playing:
				clock.toggle_play_pause()
				_update_play_pause_button()
		_open_dialog_count += 1
	else:
		_open_dialog_count -= 1
		if _open_dialog_count == 0 and _clock_was_playing_before_dialogs and not clock.is_playing:
			clock.toggle_play_pause()
			_update_play_pause_button()

func _on_system_menu_action_selected(action_id: StringName) -> void:
	match action_id:
		&"save":
			_on_save_game_pressed()
		&"back_to_main_menu":
			_pending_leave_action = &"back_to_main_menu"
			save_confirmation_dialog.open_dialog()
		&"exit_game":
			_pending_leave_action = &"exit_game"
			save_confirmation_dialog.open_dialog()

func _on_save_confirmation_option_selected(option: StringName) -> void:
	match option:
		&"save_and_leave":
			_on_save_game_pressed()
		&"leave_without_saving":
			_execute_pending_leave_action()
		&"cancel":
			_pending_leave_action = &""

func _execute_pending_leave_action() -> void:
	var action := _pending_leave_action
	_pending_leave_action = &""
	match action:
		&"back_to_main_menu":
			get_tree().change_scene_to_file("res://scenes/menus/MainMenu.tscn")
		&"exit_game":
			get_tree().quit()

func _on_play_pause_pressed() -> void:
	clock.toggle_play_pause()
	_update_play_pause_button()

func _on_speed_button_pressed(speed: GameClockController.Speed) -> void:
	clock.set_speed(speed)

func _update_play_pause_button() -> void:
	if clock.is_playing:
		play_pause_button.text = "❚❚"
		play_pause_button.tooltip_text = tr("pause")
	else:
		play_pause_button.text = "▶"
		play_pause_button.tooltip_text = tr("play")

func _on_day_advanced(checkpoint_ran: bool, animals_changed: bool) -> void:
	_update_calendar_display()
	if not (checkpoint_ran or animals_changed):
		return
	renderer.queue_redraw()
	if renderer.selected_cell != null:
		var state := world.get_cell_state_at(renderer.selected_cell.x, renderer.selected_cell.y)
		macro_cell_info_panel.show_cell(renderer.selected_cell, state)

func _on_advance_year_pressed() -> void:
	clock.force_advance_to_year_end()

func _on_debug_consume_pressed() -> void:
	var state := world.get_cell_state_at(50, 50)
	if state == null:
		return
	CaloricCalculator.debug_consume_secondary_resource(state, "berry", debug_consume_spin_box.value)

func _on_debug_consume_acorn_pressed() -> void:
	var state := world.get_cell_state_at(50, 50)
	if state == null:
		return
	CaloricCalculator.debug_consume_secondary_resource(state, "acorn", debug_consume_acorn_spin_box.value)

func _on_debug_consume_fruit_pressed() -> void:
	var state := world.get_cell_state_at(50, 50)
	if state == null:
		return
	CaloricCalculator.debug_consume_secondary_resource(state, "fruit", debug_consume_fruit_spin_box.value)

func _on_debug_set_rabbit_pressed() -> void:
	var state := world.get_cell_state_at(50, 50)
	if state == null:
		return
	var count := int(debug_rabbit_spin_box.value)
	state.set_animal_population("rabbit", count)
	print("[DEBUG] rabbit population (50,50) impostata a %d" % count)

func _update_calendar_display() -> void:
	year_label.text = "Day %d of %d, Year %d" % [game_data.current_day + 1, GameData.DAYS_PER_YEAR, game_data.year]
	season_progress_bar.set_current_day(game_data.current_day)
