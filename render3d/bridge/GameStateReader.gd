class_name GameStateReader
extends RefCounted

# L'UNICO file della vista 3D che conosce GameScene: legge le celle accese e la camera 2D e li passa al 3D in forma
# semplice (Cell3DSource). Se GameScene cambia, si aggiusta solo questo file.
# Non scrive mai nello stato della simulazione; tocca solo la vista 2D (visibilità, camera).

# Passi con cui la terra battuta in cantiere cresce nel 3D (10 = ogni 10% di lavoro).
const DIRT_GROUND_STEPS := 10.0
# Terra battuta anche sotto ogni edificio finito (2026-11-19, prova dell'utente, come nel 2D): le sue microcelle entrano
# nella maschera della terra battuta. false = com'era prima (terra nuda della cella vuota). Mai sotto i campi.
const BEATEN_UNDER_BUILDINGS := true
# Macerie (2026-11-23, richiesta utente): appoggiate sul terreno della cella com'è, senza la terra battuta degli edifici.
const NO_BEATEN_UNDER_TYPES := ["field", "dirt_ground", "rubble"]
# Edifici con la terra battuta un po' più scura sotto (2026-11-19, richiesta utente: il deposito non deve sembrare un
# cantiere). Vuoto = tutti uguali; quanto più scura: beaten_dark_amount in terrain.gdshader. Tolto il deposito il 2026-11-21
# (richiesta utente): col modello dei bastoni sul contorno il fondo torna chiaro come sotto la tenda di rami.
const DARKER_BEATEN_TYPES := []

var _game: Node2D
# Etichette 2D in spazio schermo nascoste mentre il 3D è acceso (work_areas), rimesse da set_2d_visible(true).
var _hidden_screen_labels: Array = []
# Sagoma 2D di ogni renderer degli animali (id del renderer -> {"length", "color"}), letta una volta (animals).
var _animal_shapes: Dictionary = {}
# Lista dei visibili rifatta a turni (animals, _visible_animals): per ogni renderer (id dell'istanza) ->
# {"shown": Array degli individui visibili, "building": id -> individuo della lista in costruzione, "seen": fotogramma}.
const ANIMAL_VISIBILITY_TURNS := 6
var _animal_lists: Dictionary = {}
var _animal_turn := 0


# Braci del focolare (2026-11-21, richiesta utente), solo vista: dopo una cottura le braci restano accese per
# HEARTH_EMBERS_AFTER_COOKING_DAYS (un giorno di gioco) anche se la ricetta ha bruciato tutto il combustibile, invece di
# passare subito a spento. Con combustibile in deposito restano sempre braci (si capisce che lì c'è legna). Il
# combustibile e la simulazione non cambiano. Ultimo momento acceso per id dell'edificio (giorni assoluti + frazione),
# solo mentre la cella è accesa e non salvato: dopo un caricamento un focolare senza combustibile riparte spento.
const HEARTH_EMBERS_AFTER_COOKING_DAYS := 1.0
var _hearth_last_burning: Dictionary = {}


func _init(game: Node2D) -> void:
	_game = game


# Momento di gioco in giorni (assoluti più la frazione del giorno in corso), come GameScene._job_board_now.
func _game_time_days() -> float:
	var game_data: GameData = GameSettings.active_game_data
	if game_data == null:
		return 0.0
	var clock: GameClockController = _game.get("clock")
	return float(game_data.get_absolute_day()) + (clock.get_day_progress() if clock != null else 0.0)


# Coordinate delle macrocelle accese adesso.
func live_cell_coords() -> Array:
	var live: Dictionary = _game.get("live_cells")
	return live.keys()


# Angolo della macrocella in microcelle rispetto al centro corrente (stesso posto del suo container 2D).
func cell_origin(coords: Vector2i) -> Vector2:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.container == null:
		return Vector2.ZERO
	return cell.container.position / float(MicroCellRenderer.CELL_SIZE)


# Nebbia della cella (2026-11-21): la STESSA texture del 2D (FogOfWarRenderer.get_fog_texture, un pixel per microcella,
# alfa = velo), nessuna copia. Col 2D nascosto il suo _draw() non gira: update_fog_texture fa lo stesso lavoro (solo il
# disegno della nebbia, non lo stato del gioco). null se la cella non ha nebbia.
func fog_texture(coords: Vector2i) -> Texture2D:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.fog_of_war_renderer == null:
		return null
	cell.fog_of_war_renderer.update_fog_texture()
	return cell.fog_of_war_renderer.get_fog_texture()


# Persone visibili, dalle stesse HumanIndividualView del 2D (una per persona nelle celle accese): grandezza per età e
# sesso, fase del passo e colori (pelle, vestito, capelli, grigi da anziani, copricapo) come li calcola il 2D.
# Riempie `snapshot` (riusato a ogni fotogramma).
func people(snapshot: PeopleSnapshot3D) -> void:
	snapshot.clear()
	var live: Dictionary = _game.get("live_cells")
	var views: Dictionary = _game.get("human_individual_views")
	for value in views.values():
		if not is_instance_valid(value):
			continue
		var view := value as HumanIndividualView
		if view == null or not view.visible or view.individual == null:
			continue
		var individual := view.individual
		var cell: LiveMacroCell = live.get(individual.home_macro_coords)
		if cell == null or cell.container == null:
			continue
		var band := view._current_age_band
		var hair: Color = HumanIndividualView.HAIR_COLOR_BY_TRAIT.get(individual.hair_color,
			HumanIndividualView.HAIR_COLOR_BY_TRAIT[HumanTypes.HairColor.BROWN])
		if band == HumanTypes.AgeBand.OLD:
			hair = HumanIndividualView.GRAY_HAIR_COLOR
		var origin := cell.container.position / float(MicroCellRenderer.CELL_SIZE)
		snapshot.ids.append(individual.id)
		snapshot.positions.append(origin + individual.position)
		snapshot.grounds.append(Vector2(individual.home_macro_coords) * float(World.WIDTH) + individual.position)
		snapshot.facings.append(individual.facing_direction)
		snapshot.sizes.append(absf(view.scale.x) / HumanIndividualView.BASE_DRAW_SCALE)
		snapshot.walk_phases.append(view.walk_phase)
		snapshot.body_colors.append(HumanIndividualView.body_draw_color(individual, band))
		snapshot.hair_colors.append(hair)
		snapshot.cap_colors.append(HumanIndividualView.head_cap_color(individual, band))
		snapshot.females.append(1 if individual.sex == HumanTypes.Sex.FEMALE else 0)
		snapshot.pregnant.append(1 if individual.is_pregnant else 0)
		snapshot.selected.append(1 if individual.is_selected else 0)
	_dead_bodies(snapshot, live)


# Armi scagliate a terra in attesa di recupero (2026-11-21): i DroppedWeaponMarker del 2D (GameScene.
# _dropped_weapon_markers, cacciatore -> segnaposto), figli del contenitore della cella del punto di caduta.
func weapon_drops(snapshot: WeaponDropsSnapshot3D) -> void:
	snapshot.clear()
	var markers: Dictionary = _game.get("_dropped_weapon_markers")
	if markers == null or markers.is_empty():
		return
	var live: Dictionary = _game.get("live_cells")
	for hunter_id in markers:
		var marker := markers[hunter_id] as DroppedWeaponMarker
		if marker == null or not is_instance_valid(marker):
			continue
		var container := marker.get_parent() as Node2D
		if container == null:
			continue
		for coords in live:
			var cell: LiveMacroCell = live[coords]
			if cell == null or cell.container != container:
				continue
			var local := marker.position / float(MicroCellRenderer.CELL_SIZE)
			snapshot.weapons.append(marker.weapon_name)
			snapshot.positions.append(container.position / float(MicroCellRenderer.CELL_SIZE) + local)
			snapshot.grounds.append(Vector2(coords) * float(World.WIDTH) + local)
			snapshot.rotations.append(marker.rotation)
			snapshot.seeds.append(int(hunter_id))
			break


# Morti a terra (2026-11-21): le DeadBodyView del 2D (GameScene.dead_body_views), figlie del contenitore di una cella
# accesa; anche quelle trascinate verso la sepoltura (la posizione la muove il 2D). Colori e grandezza come le disegna
# il 2D; la testa sta dalla parte -X locale della figurina (SUPINE_HEAD_AXIS_OFFSET < 0), ruotata con `rotation`.
func _dead_bodies(snapshot: PeopleSnapshot3D, live: Dictionary) -> void:
	var views: Dictionary = _game.get("dead_body_views")
	if views == null or views.is_empty():
		return
	var coords_of: Dictionary = {} # contenitore della cella -> coordinate
	for coords in live:
		var cell: LiveMacroCell = live[coords]
		if cell != null and cell.container != null:
			coords_of[cell.container] = coords
	for value in views.values():
		if not is_instance_valid(value):
			continue
		var view := value as DeadBodyView
		if view == null or not view.visible or not coords_of.has(view.get_parent()):
			continue
		var coords: Vector2i = coords_of[view.get_parent()]
		var container := view.get_parent() as Node2D
		var local := view.position / float(MicroCellRenderer.CELL_SIZE)
		var body_color: Color = view._body_color
		if body_color.a <= 0.0:
			body_color = HumanIndividualView.CLOTHING_COLOR_BY_TRAIT.get(view._clothing_color,
				HumanIndividualView.CLOTHING_COLOR_BY_TRAIT[HumanTypes.ClothingColor.TAN])
		snapshot.dead_positions.append(container.position / float(MicroCellRenderer.CELL_SIZE) + local)
		snapshot.dead_grounds.append(Vector2(coords) * float(World.WIDTH) + local)
		snapshot.dead_heads.append(-Vector2.from_angle(view.rotation))
		snapshot.dead_sizes.append(absf(view.scale.x) / HumanIndividualView.BASE_DRAW_SCALE)
		snapshot.dead_body_colors.append(body_color)
		snapshot.dead_hair_colors.append(HumanIndividualView.HAIR_COLOR_BY_TRAIT.get(view._hair_color,
			HumanIndividualView.HAIR_COLOR_BY_TRAIT[HumanTypes.HairColor.BROWN]))
		snapshot.dead_females.append(1 if view._sex == HumanTypes.Sex.FEMALE else 0)
		snapshot.dead_selected.append(1 if view.is_selected else 0)


# Animali visibili: tutti i renderer della fauna stanno nelle celle accese (selvatici per specie, visite degli animali
# seguiti, domestici, condotti con la cavezza), quindi si leggono tutti da lì, con lo stesso test del disegno 2D (nebbia,
# pulsante "animali"). Lunghezza e colore dalla sagoma 2D della specie (i domestici col loro colore e la loro taglia), per
# età come nel 2D. Riempie `snapshot` (riusato a ogni fotogramma).
func animals(snapshot: AnimalsSnapshot3D) -> void:
	snapshot.clear()
	_animal_turn += 1
	var live: Dictionary = _game.get("live_cells")
	for coords in live:
		var cell: LiveMacroCell = live[coords]
		if cell == null or cell.container == null:
			continue
		var origin := cell.container.position / float(MicroCellRenderer.CELL_SIZE)
		var ground := Vector2(coords) * float(World.WIDTH)
		for child in cell.container.get_children():
			var renderer := child as AnimalGroupRenderer
			if renderer == null or not renderer.are_animals_shown():
				continue
			var shape := _animal_shape(renderer)
			if shape.is_empty():
				continue
			var ages: Array = renderer.size_multiplier_by_age
			for value in _visible_animals(renderer):
				var individual := value as AnimalVisualGroup
				var age_scale := 1.0
				if individual.age_band >= 0 and individual.age_band < ages.size():
					age_scale = float(ages[individual.age_band])
				var position := renderer.position / float(MicroCellRenderer.CELL_SIZE) + individual.position
				snapshot.ids.append(individual.id)
				snapshot.species.append(renderer.species_name)
				snapshot.positions.append(origin + position)
				snapshot.grounds.append(ground + position)
				snapshot.facings.append(individual.direction)
				snapshot.lengths.append(float(shape["length"]) * age_scale)
				snapshot.colors.append(shape["color"])
				snapshot.selected.append(1 if renderer._selected_individual_id == individual.id else 0)


# Lista dei visibili rifatta a turni (2026-11-21, misura [3D TIME]: scorrere a ogni fotogramma tutti gli animali della
# cella, ~580, costava 1-2 ms anche con la nebbia a turni, per vederne 12-37). A ogni fotogramma si controlla solo un
# sesto degli individui di ogni renderer (uno ogni ANIMAL_VISIBILITY_TURNS, a partire dal turno) e si mettono da parte i
# visibili; finito il giro la lista nuova prende il posto di quella mostrata. Gli individui sono gli oggetti del 2D,
# quindi le posizioni restano di ogni fotogramma; solo comparire/sparire (nebbia, nascite, morti) arriva fino a
# ANIMAL_VISIBILITY_TURNS fotogrammi dopo. Un renderer nuovo si controlla tutto subito.
func _visible_animals(renderer: AnimalGroupRenderer) -> Array:
	var key := renderer.get_instance_id()
	var individuals: Array = renderer.get_individuals()
	var entry: Dictionary = _animal_lists.get(key, {})
	if entry.is_empty():
		var shown: Array = []
		for value in individuals:
			if renderer.is_individual_visible(value as AnimalVisualGroup):
				shown.append(value)
		entry = {"shown": shown, "building": {}, "seen": _animal_turn}
		_animal_lists[key] = entry
		_forget_old_animal_lists()
		return shown
	entry["seen"] = _animal_turn
	var phase := _animal_turn % ANIMAL_VISIBILITY_TURNS
	var building: Dictionary = entry["building"]
	for i in range(phase, individuals.size(), ANIMAL_VISIBILITY_TURNS):
		var individual := individuals[i] as AnimalVisualGroup
		if renderer.is_individual_visible(individual):
			building[individual.id] = individual
	if phase == ANIMAL_VISIBILITY_TURNS - 1:
		entry["shown"] = building.values()
		entry["building"] = {}
	return entry["shown"]


# Toglie le liste dei renderer non più letti da un po' (celle spente, specie sparite).
func _forget_old_animal_lists() -> void:
	for key in _animal_lists.keys():
		if _animal_turn - int(_animal_lists[key]["seen"]) > ANIMAL_VISIBILITY_TURNS * 10:
			_animal_lists.erase(key)


# Lunghezza (microcelle) e colore della sagoma 2D di un renderer, letti una volta dalla sua mesh e tenuti da parte.
func _animal_shape(renderer: AnimalGroupRenderer) -> Dictionary:
	var id := renderer.get_instance_id()
	if _animal_shapes.has(id):
		return _animal_shapes[id]
	var shape := {}
	var multimesh: MultiMesh = renderer._multimesh
	if multimesh != null and multimesh.mesh != null and multimesh.mesh.get_surface_count() > 0:
		var colors: PackedColorArray = multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var color: Color = colors[0] if not colors.is_empty() else Color.GRAY
		color.a = 1.0
		shape = {"length": multimesh.mesh.get_aabb().size.x / float(MicroCellRenderer.CELL_SIZE), "color": color}
	_animal_shapes[id] = shape
	return shape


# Icone e animazioni del 2D sulla mappa (2026-11-20, richiesta utente: "paro paro quelle del 2D"): lampadina dell'idea,
# icone dei comandi (costruisci, raccogli, caccia, produci...), riti, funerale, fumetto della chiacchiera, icone che salgono
# dagli edifici. Nel 2D nascono tutte come figlie della cella con z_index 2 (il segno comune di GameScene); in più, sopra
# ogni persona, l'icona di salute (malattia, ferita) e l'icona passeggera (sorso). Le si rilegge così come sono (posizione,
# trasparenza, scala animate dai tween del 2D): una voce per icona visibile, in `out` (riusato).
# Voce: {"source": CanvasItem, "origin": origine 3D della cella (x, z), "ground": origine della cella in microcelle
# assolute, "local": posizione attuale nella cella (pixel 2D), "anchor": punto della cella a cui sta attaccata (pixel 2D;
# Vector2.INF = dov'era quando è comparsa), "scale": scala nella cella, "person_size": grandezza della persona (0 = no)}.
func overhead_icons(out: Array) -> void:
	out.clear()
	var live: Dictionary = _game.get("live_cells")
	for coords in live:
		var cell: LiveMacroCell = live[coords]
		if cell == null or cell.container == null:
			continue
		var origin := cell.container.position / float(MicroCellRenderer.CELL_SIZE)
		var ground := Vector2(coords) * float(World.WIDTH)
		for child in cell.container.get_children():
			if child is HumanIndividualView:
				var view := child as HumanIndividualView
				if not view.visible:
					continue
				var size := absf(view.scale.x) / HumanIndividualView.BASE_DRAW_SCALE
				for icon in view.get_children():
					var item := icon as Node2D
					if item == null or not item.visible or not (item is HealthConditionIcon or item.z_index == 2):
						continue
					out.append({"source": item, "origin": origin, "ground": ground, "local": view.transform * item.position,
						"anchor": view.position, "scale": (item.scale * view.scale).abs(), "person_size": size})
			elif child is CanvasItem and (child as CanvasItem).z_index == 2 and not (child is FogOfWarRenderer):
				var item := child as CanvasItem
				if not item.visible:
					continue
				var local: Vector2 = item.get("position")
				var item_scale: Vector2 = item.get("scale")
				out.append({"source": item, "origin": origin, "ground": ground, "local": local, "anchor": Vector2.INF,
					"scale": item_scale, "person_size": 0.0})


func cell_source(coords: Vector2i) -> Cell3DSource:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null:
		return null
	var source := Cell3DSource.new()
	source.coords = coords
	source.origin = cell_origin(coords)
	source.world = cell.world
	source.water_type = cell.macro_cell.water_type if cell.macro_cell != null else GameTypes.WaterType.NONE
	source.river_positions = cell.river_positions
	source.stream_positions = cell.stream_positions
	if cell.macro_state != null:
		source.clay_positions = cell.macro_state.clay_positions
	var macro_world: World = _game.get("macro_world")
	if macro_world != null and cell.macro_cell != null:
		source.stream_layout = StreamMicrocellService.get_layout(macro_world, cell.macro_cell)
	return source


# Stagione della cella, come la usa il 2D (MicroCellRenderer.current_season).
func season(coords: Vector2i) -> GameTypes.Season:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return GameTypes.Season.SUMMER
	return cell.renderer.current_season


# "Impronta" del giacimento d'argilla: cambia quando una microcella si esaurisce ed esce da clay_positions.
func clay_deposit_signature(coords: Vector2i) -> Array:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.macro_state == null:
		return [0]
	return [cell.macro_state.clay_positions.size()]


# Rocce e sassi della cella, come li disegna il 2D (MicroCellRenderer: posizioni, esaurite, disponibilità dei sassi).
func stone_snapshot(coords: Vector2i) -> StoneSnapshot3D:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	var snapshot := StoneSnapshot3D.new()
	if cell == null or cell.renderer == null:
		return snapshot
	var renderer := cell.renderer
	for pos in renderer.stone_positions:
		var center := renderer.get_stone_screen_position(pos) / float(MicroCellRenderer.CELL_SIZE)
		snapshot.all_centers[pos] = center
		if not renderer.depleted_stone_positions.has(pos) and not _is_under_black_fog(cell, pos):
			snapshot.rock_centers[pos] = center
	snapshot.pebble_quantities = renderer.pebble_availability.duplicate()
	return snapshot


# Bastoni a terra della cella: la disponibilità per lotto che riceve il 2D (MicroCellRenderer.stick_availability).
func sticks_snapshot(coords: Vector2i) -> SticksSnapshot3D:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	var snapshot := SticksSnapshot3D.new()
	if cell != null and cell.renderer != null:
		snapshot.quantities = cell.renderer.stick_availability.duplicate()
	return snapshot


# "Impronta" dei bastoni: il 2D riceve un dizionario nuovo a ogni rinfresco (set_stick_availability).
func sticks_signature(coords: Vector2i) -> Array:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return []
	return [cell.renderer.stick_availability]


# "Impronta" di rocce e sassi della cella: cambia quando il 2D riceve dati nuovi (rocce esaurite, sassi raccolti).
# Confrontata con is_same/size, costa pochissimo a ogni frame.
func stone_signature(coords: Vector2i) -> Array:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return []
	var renderer := cell.renderer
	return [renderer.stone_positions, renderer.stone_positions.size(), renderer.depleted_stone_positions,
		renderer.depleted_stone_positions.size(), renderer.pebble_availability,
		black_fog_positions(coords, renderer.stone_positions).hash()]


# Le microcelle di `positions` (chiavi Vector2i di un Dictionary o elementi di un Array) che il 2D copre col nero pieno
# della nebbia, nell'ordine dato. Nelle impronte va il suo hash() (un numero, confrontato per valore: un elenco nuovo a
# ogni fotogramma sembrerebbe sempre cambiato, vedi Cell3D._same_value).
func black_fog_positions(coords: Vector2i, positions: Variant) -> Array:
	var hidden: Array = []
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null:
		return hidden
	for pos in positions:
		if _is_under_black_fog(cell, pos):
			hidden.append(pos)
	return hidden


# true se il 2D copre la microcella col nero pieno della nebbia (mai vista o dimenticata): lì il 3D non crea gli oggetti
# (rocce), invece di disegnarli e coprirli.
func _is_under_black_fog(cell: LiveMacroCell, pos: Vector2i) -> bool:
	if cell.fog_of_war_renderer == null:
		return false
	return cell.fog_of_war_renderer.get_fog_alpha(pos) >= 0.99


# Frutti caduti a terra (2026-11-21): per ogni risorsa degli alberi da frutto che ha un modello a terra
# (GroundFruit3D.MODELS_BY_RESOURCE), quanto resta su ogni lotto rispetto alla capacità piena dell'anno, con le formule
# dei lotti (LotCapacityService: capacità × moltiplicatore della stagione − raccolto). Solo lotti con un albero in vista.
func ground_fruit_snapshot(coords: Vector2i) -> GroundFruitSnapshot3D:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	var snapshot := GroundFruitSnapshot3D.new()
	if cell == null or cell.renderer == null or cell.macro_state == null:
		return snapshot
	var visible_lots: Dictionary = {}
	for key in cell.renderer.vegetation_positions.get(GameTypes.WorldObjectType.TREE, []):
		visible_lots[Vector2i(key.x, key.y)] = true
	if visible_lots.is_empty():
		return snapshot
	for resource_name: String in GroundFruit3D.MODELS_BY_RESOURCE:
		var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
		if rules == null:
			continue
		var cache: Dictionary = cell.macro_state.lot_capacity_cache.get(resource_name, {})
		var registry: Dictionary = cell.macro_state.lot_registry.get(resource_name, {})
		var fractions: Dictionary = {}
		for lot in cache:
			var base := int(cache[lot])
			if base <= 0 or not visible_lots.has(lot):
				continue
			var seasonal := LotCapacityService._apply_seasonal_availability_to_capacity(rules, base)
			var available := maxi(seasonal - int(registry.get(lot, 0)), 0)
			if available > 0:
				fractions[lot] = minf(float(available) / float(base), 1.0)
		if not fractions.is_empty():
			snapshot.fractions_by_resource[resource_name] = fractions
	return snapshot


# "Impronta" dei frutti a terra: stagione, capacità e raccolto dei lotti (LotCapacityService.get_visual_ratio_signature)
# e l'elenco degli alberi in vista (nebbia).
func ground_fruit_signature(coords: Vector2i) -> Array:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null or cell.macro_state == null:
		return []
	var positions: Array = cell.renderer.vegetation_positions.get(GameTypes.WorldObjectType.TREE, [])
	var signature: Array = [cell.renderer.vegetation_positions, positions, positions.size()]
	for resource_name: String in GroundFruit3D.MODELS_BY_RESOURCE:
		signature.append_array(LotCapacityService.get_visual_ratio_signature(cell.macro_state, resource_name))
	return signature


# Alberi vivi, tagliati (ceppi) e morti della cella, con la stessa posizione e taglia del 2D (riusa le sue formule, mai
# una copia; tagliati e morti con la taglia salvata al momento del taglio o della morte).
func tree_snapshot(coords: Vector2i) -> TreeSnapshot3D:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	var snapshot := TreeSnapshot3D.new()
	if cell == null or cell.renderer == null:
		return snapshot
	var renderer := cell.renderer
	var positions: Array = renderer.vegetation_positions.get(GameTypes.WorldObjectType.TREE, [])
	var cut: Array = renderer.cut_positions.get(GameTypes.WorldObjectType.TREE, [])
	var dead: Array = renderer.dead_positions.get(GameTypes.WorldObjectType.TREE, [])
	if positions.is_empty() and cut.is_empty() and dead.is_empty():
		return snapshot
	snapshot.season = renderer.current_season
	var lot_counts: Dictionary = renderer._lot_extent_counts(GameTypes.WorldObjectType.TREE)
	var cell_size := float(MicroCellRenderer.CELL_SIZE)
	for entry in cut:
		var key: Vector3i = entry["key"]
		if _is_under_black_fog(cell, Vector2i(key.x, key.y)):
			continue
		var t: Transform2D = renderer._build_tree_stump_transform(key, float(entry["size_multiplier"]), lot_counts)
		var width := t.x.length()
		snapshot.stump_grounds.append((t.origin + Vector2(width * 0.5, t.y.length())) / cell_size)
		snapshot.stump_widths.append(width / cell_size)
		snapshot.stump_seeds.append(hash(key))
	for entry in dead:
		var key: Vector3i = entry["key"]
		if _is_under_black_fog(cell, Vector2i(key.x, key.y)):
			continue
		var t: Transform2D = renderer._build_dead_tree_transform(key, float(entry["size_multiplier"]), lot_counts)
		# Il piede è il punto (0,5; 1) del quadrato unitario della sagoma (vedi _build_dead_tree_transform).
		snapshot.dead_grounds.append((t.origin + t.x * 0.5 + t.y) / cell_size)
		snapshot.dead_heights.append(t.y.length() / cell_size)
		snapshot.dead_seeds.append(hash(key))
	for key in positions:
		var visual: Dictionary = renderer._compute_tree_visual(key, lot_counts)
		snapshot.grounds.append(visual["ground"] / cell_size)
		snapshot.trunk_heights.append(float(visual["trunk_height"]) / cell_size)
		snapshot.trunk_widths.append(float(visual["trunk_width"]) / cell_size)
		snapshot.canopy_radii.append(float(visual["canopy_radius"]) / cell_size)
		snapshot.seeds.append(hash(visual["jitter_pos"]))
		snapshot.conifer.append(1 if visual["is_conifer"] else 0)
		snapshot.fruit_bearing.append(1 if visual["is_fruit_bearing"] else 0)
		snapshot.domesticable.append(1 if visual["is_domesticable"] else 0)
		snapshot.fruit_shown.append(1 if _tree_fruit_shown(renderer, key, visual) else 0)
	return snapshot


# Frutti di un albero in vista con le regole del 2D (_compute_tree_geometry e _draw): niente sui giovani e sulle conifere,
# solo in FRUITING_SEASONS e solo sugli alberi del lotto ancora da raccogliere (_fruit_stock_shows, sempre gli stessi
# individui). Ghiande (acorn) sui wild_fruit, frutti (fruit) sui domesticable_fruit.
static func _tree_fruit_shown(renderer: MicroCellRenderer, key: Vector3i, visual: Dictionary) -> bool:
	if visual["is_conifer"] or not visual["is_fruit_bearing"] or visual["age_band"] == GameTypes.AgeBand.YOUNG:
		return false
	if not renderer.current_season in MicroCellRenderer.FRUITING_SEASONS:
		return false
	return renderer._fruit_stock_shows("fruit" if visual["is_domesticable"] else "acorn", key, visual["jitter_pos"])


# "Impronta" degli alberi: cambia quando il 2D riceve un elenco nuovo (nascite, tagli, nebbia), cambia l'anno (età), la
# stagione o la raccolta dei frutti.
func tree_signature(coords: Vector2i) -> Array:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return []
	var renderer := cell.renderer
	var positions: Array = renderer.vegetation_positions.get(GameTypes.WorldObjectType.TREE, [])
	var cut: Array = renderer.cut_positions.get(GameTypes.WorldObjectType.TREE, [])
	var dead: Array = renderer.dead_positions.get(GameTypes.WorldObjectType.TREE, [])
	return [renderer.vegetation_positions, positions, positions.size(), renderer.tree_current_year,
		renderer.cut_positions, cut, cut.size(), renderer.dead_positions, dead, dead.size(), renderer.current_season,
		renderer.fruit_stock_available_ratio_by_lot.get("acorn", {}), renderer.fruit_stock_available_ratio_by_lot.get("fruit", {}),
		_hidden_remains_hash(cell, cut, dead)]


# Cespugli vivi, tagliati e morti della cella, con le stesse bolle (posizione, taglia, colore) del 2D: riusa le sue formule,
# mai una copia. Dagli stessi elenchi del 2D (i vivi filtrati dalla nebbia; tagliati e morti saltati qui sotto il nero).
func shrub_snapshot(coords: Vector2i) -> ShrubSnapshot3D:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	var snapshot := ShrubSnapshot3D.new()
	if cell == null or cell.renderer == null:
		return snapshot
	var renderer := cell.renderer
	var cell_size := float(MicroCellRenderer.CELL_SIZE)
	var lot_counts: Dictionary = renderer._lot_extent_counts(GameTypes.WorldObjectType.SHRUB)
	for key in renderer.vegetation_positions.get(GameTypes.WorldObjectType.SHRUB, []):
		var visual: Dictionary = renderer._compute_shrub_visual(key, lot_counts)
		var geometry: Dictionary = renderer._compute_shrub_geometry(key, lot_counts, false)
		snapshot.centers.append(visual["center"] / cell_size)
		snapshot.seeds.append(hash(visual["jitter_pos"]))
		snapshot.fruit_bearing.append(1 if visual["is_fruit_bearing"] else 0)
		snapshot.fruit_state.append(_shrub_fruit_state(renderer, key, visual))
		if _shrub_berry_candidate(renderer, visual):
			snapshot.berry_index.append(snapshot.centers.size() - 1)
			snapshot.berry_keys.append(key)
			snapshot.berry_jitters.append(visual["jitter_pos"])
		snapshot.blob_starts.append(snapshot.blob_centers.size())
		var transforms: Array = geometry["blob_transforms"]
		var colors: Array = geometry["blob_colors"]
		for i in range(transforms.size()):
			var t: Transform2D = transforms[i]
			snapshot.blob_centers.append(t.origin / cell_size)
			snapshot.blob_radii.append(t.x.length() / cell_size)
			snapshot.blob_colors.append(colors[i])
	snapshot.blob_starts.append(snapshot.blob_centers.size())
	for entry in renderer.cut_positions.get(GameTypes.WorldObjectType.SHRUB, []):
		var key: Vector3i = entry["key"]
		if _is_under_black_fog(cell, Vector2i(key.x, key.y)):
			continue
		var t: Transform2D = renderer._build_shrub_stump_transform(key, float(entry["size_multiplier"]), lot_counts)
		snapshot.cut_centers.append(t.origin / cell_size)
		snapshot.cut_radii.append(t.x.length() / cell_size)
		snapshot.cut_seeds.append(hash(key))
	for entry in renderer.dead_positions.get(GameTypes.WorldObjectType.SHRUB, []):
		var key: Vector3i = entry["key"]
		if _is_under_black_fog(cell, Vector2i(key.x, key.y)):
			continue
		var t: Transform2D = renderer._build_dead_marker_transform(GameTypes.WorldObjectType.SHRUB, key,
			float(entry["size_multiplier"]), lot_counts)
		snapshot.dead_centers.append(t.origin / cell_size)
		snapshot.dead_radii.append(t.x.length() / cell_size)
		snapshot.dead_seeds.append(hash(key))
	return snapshot


# Stato dei frutti di un cespuglio con le regole del 2D (_rebuild_shrub_multimeshes): niente frutti sui giovani, bacche
# solo in FRUITING_SEASONS e solo sui cespugli ancora da raccogliere (_fruit_stock_shows, sempre gli stessi individui);
# i fiori (solo 3D, il 2D non li ha) nella stagione prima delle bacche, la primavera.
static func _shrub_fruit_state(renderer: MicroCellRenderer, key: Vector3i, visual: Dictionary) -> int:
	if not visual["is_fruit_bearing"] or visual["age_band"] == GameTypes.AgeBand.YOUNG:
		return ShrubSnapshot3D.FRUIT_BARE
	if renderer.current_season == GameTypes.Season.SPRING:
		return ShrubSnapshot3D.FRUIT_FLOWERS
	if _shrub_berry_candidate(renderer, visual) and renderer._fruit_stock_shows("berry", key, visual["jitter_pos"]):
		return ShrubSnapshot3D.FRUIT_BERRIES
	return ShrubSnapshot3D.FRUIT_BARE


# Cespuglio che in questa stagione può avere le bacche: da frutto, adulto, estate o autunno. Se le ha davvero lo dice la
# raccolta (_fruit_stock_shows), che cambia spesso: per questi soli il 3D cambia modello senza rifare la cella.
static func _shrub_berry_candidate(renderer: MicroCellRenderer, visual: Dictionary) -> bool:
	return visual["is_fruit_bearing"] and visual["age_band"] != GameTypes.AgeBand.YOUNG \
		and renderer.current_season in MicroCellRenderer.FRUITING_SEASONS


# Per ciascun cespuglio candidato (ShrubSnapshot3D.berry_keys/berry_jitters): 1 se ha le bacche da mostrare, con la
# regola del 2D. Letto solo quando cambia la raccolta (shrub_berry_signature).
func shrub_berries_shown(coords: Vector2i, keys: Array, jitters: Array) -> PackedByteArray:
	var shown := PackedByteArray()
	shown.resize(keys.size())
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return shown
	for i in range(keys.size()):
		shown[i] = 1 if cell.renderer._fruit_stock_shows("berry", keys[i], jitters[i]) else 0
	return shown


# Impronta della raccolta delle bacche: l'elenco per lotto del 2D, che GameScene sostituisce solo quando cambia
# (set_fruit_stock_available_ratio_by_lot). A parte da shrub_signature, come il 2D che lì rifà solo i frutti.
func shrub_berry_signature(coords: Vector2i) -> Array:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return []
	return [cell.renderer.fruit_stock_available_ratio_by_lot.get("berry", {})]


# "Impronta" dei cespugli: cambia quando il 2D riceve elenchi nuovi (nascite, tagli, nebbia) o cambia l'anno (età), la
# stagione. La raccolta delle bacche no (dal 2026-11-21): ha la sua impronta, shrub_berry_signature.
func shrub_signature(coords: Vector2i) -> Array:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return []
	var renderer := cell.renderer
	var positions: Array = renderer.vegetation_positions.get(GameTypes.WorldObjectType.SHRUB, [])
	var cut: Array = renderer.cut_positions.get(GameTypes.WorldObjectType.SHRUB, [])
	var dead: Array = renderer.dead_positions.get(GameTypes.WorldObjectType.SHRUB, [])
	return [renderer.vegetation_positions, positions, positions.size(), renderer.shrub_current_year,
		renderer.cut_positions, cut, cut.size(), renderer.dead_positions, dead, dead.size(), renderer.current_season,
		_hidden_remains_hash(cell, cut, dead)]


# Tagliati e morti (alberi o cespugli) sotto il nero della nebbia: il 2D non li filtra (li copre col nero), il 3D non li
# crea (2026-11-21). Nell'impronta va questo numero, così compaiono e spariscono quando la nebbia si apre o si chiude.
func _hidden_remains_hash(cell: LiveMacroCell, cut: Array, dead: Array) -> int:
	var hidden: Array = []
	for list in [cut, dead]:
		for entry in list:
			var key: Vector3i = entry["key"]
			if _is_under_black_fog(cell, Vector2i(key.x, key.y)):
				hidden.append(key)
	return hidden.hash()


# Focolari finiti della cella (dallo stesso elenco di edifici che disegna il 2D) col loro stato: acceso mentre ci si fa
# una ricetta a combustibile (Building.smoking_now, ProductionService.refresh_smoking), braci se ha combustibile nel
# deposito, spento altrimenti. Spiazzo delle feste (2026-11-23): il falò al centro, acceso durante il banchetto.
func hearth_snapshot(coords: Vector2i) -> HearthSnapshot3D:
	var snapshot := HearthSnapshot3D.new()
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return snapshot
	for entry in _hearth_entries(cell.renderer):
		var center := MicroCellRenderer._building_entry_center(entry) / float(MicroCellRenderer.CELL_SIZE)
		# Affumicatoio (2026-11-22): il focolare sta davanti, dentro l'anello di pietre del suo modello.
		var smokehouse := String(entry.get("building_type_name", "")) == BuildingModels3D.SMOKEHOUSE_TYPE
		if smokehouse:
			center += BuildingModels3D.smokehouse_hearth_offset(TentShapes.direction_vector(entry.get("rotation", GameTypes.Direction.SOUTH)))
		snapshot.centers.append(center)
		snapshot.states.append(_hearth_state(int(entry.get("id", -1))))
		snapshot.seeds.append(hash(int(entry.get("id", -1))))
		snapshot.with_stones.append(0 if smokehouse else 1)
	return snapshot


# "Impronta" dei focolari: cambia con l'elenco degli edifici del 2D o con lo stato di un focolare (letto a ogni frame:
# i focolari sono pochi).
func hearth_signature(coords: Vector2i) -> Array:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return []
	var renderer := cell.renderer
	var signature: Array = [renderer.buildings, renderer.buildings.size()]
	for entry in _hearth_entries(renderer):
		signature.append(_hearth_state(int(entry.get("id", -1))))
	return signature


func _hearth_entries(renderer: MicroCellRenderer) -> Array:
	return _complete_entries_of_type(renderer, "campfire") + _complete_entries_of_type(renderer, BuildingModels3D.SMOKEHOUSE_TYPE) 		+ _complete_entries_of_type(renderer, BuildingModels3D.FEAST_GROUND_TYPE)


# Edifici con modello Blender (BuildingModels3D.MODELS), finiti o in cantiere, più ogni cantiere non ancora allestito
# (cartello), con la fase decisa dal gioco (BuildingConstructionStage). Stesso elenco, centro e porta del 2D.
func building_models(coords: Vector2i) -> BuildingModelsSnapshot3D:
	var snapshot := BuildingModelsSnapshot3D.new()
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return snapshot
	var by_id := _buildings_by_id()
	for entry in _model_entries(cell.renderer):
		snapshot.type_names.append(String(entry.get("building_type_name", "")))
		snapshot.ids.append(int(entry.get("id", -1)))
		snapshot.centers.append(MicroCellRenderer._building_entry_center(entry) / float(MicroCellRenderer.CELL_SIZE))
		snapshot.doors.append(_model_door(entry, cell))
		snapshot.stages.append(_stage_of_entry(entry, by_id))
		snapshot.fills.append(_pit_fill(entry, by_id))
		snapshot.rack_loads.append(_rack_loads(entry, by_id))
		snapshot.fuel_piles.append(_fuel_piles(entry, by_id))
		snapshot.linear_masks.append(int(entry.get("linear_neighbors", 0)))
		snapshot.site_debris.append(_has_site_debris(entry))
	return snapshot


# Impronta: elenco del 2D + fase di ogni edificio con modello (cambia mentre il lavoro avanza).
func building_models_signature(coords: Vector2i) -> Array:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return []
	var signature: Array = [cell.renderer.buildings, cell.renderer.buildings.size()]
	var entries := _model_entries(cell.renderer)
	if entries.is_empty():
		return signature
	var by_id := _buildings_by_id()
	for entry in entries:
		signature.append(_stage_of_entry(entry, by_id))
		signature.append(_pit_fill(entry, by_id))
		signature.append(",".join(_rack_loads(entry, by_id)))
		signature.append(",".join(_fuel_piles(entry, by_id)))
		signature.append(int(entry.get("linear_neighbors", 0)))
		signature.append(_has_site_debris(entry))
	return signature


# Verso dove si gira il modello: la porta come nel 2D; il guado di pietre (2026-11-22) invece di traverso al ruscello,
# con lo stesso angolo che usa il 2D (StreamMicrocellService.ford_angle: la fila, lungo +y, ruotata di quell'angolo).
func _model_door(entry: Dictionary, cell: LiveMacroCell) -> Vector2:
	if String(entry.get("building_type_name", "")) == BuildingModels3D.FORD_TYPE:
		return ford_door(StreamMicrocellService.ford_angle(cell.stream_positions, entry.get("position", Vector2i.ZERO)))
	return TentShapes.direction_vector(entry.get("rotation", GameTypes.Direction.SOUTH))


static func ford_door(angle: float) -> Vector2:
	return Vector2(0.0, 1.0).rotated(angle)


func _model_entries(renderer: MicroCellRenderer) -> Array:
	var entries: Array = []
	for entry in renderer.buildings:
		# Anche ogni cantiere non ancora allestito, di qualsiasi tipo: ha il cartello (come nel 2D).
		var not_set_up: bool = not entry.get("is_complete", true) and not entry.get("site_setup_complete", false)
		# E ogni cantiere coi detriti dei ceppi (2026-11-23): le macerie sopra, anche se il tipo non ha modello.
		if not_set_up or _has_site_debris(entry) or BuildingModels3D.has_models(String(entry.get("building_type_name", ""))):
			entries.append(entry)
	return entries


# Cantiere coi detriti dei ceppi ancora da portare via: lo stesso campo con cui il 2D ci disegna sopra le macerie.
static func _has_site_debris(entry: Dictionary) -> bool:
	return not entry.get("is_complete", true) and entry.get("site_debris", false)


# Cosa è appeso all'essiccatoio finito: un carico per posto occupato, nell'ordine dei posti del gioco
# (BuildingStorageService.get_slot_breakdown, gli stessi del pannello). Ingrediente in essiccazione e prodotto già secco
# restano appesi uguali finché qualcuno non lo porta via. Vuoto se l'edificio non è un essiccatoio finito.
# Affumicatoio finito (2026-11-22): carne, pesce e pelle da affumicare (posti del deposito, gli stessi del pannello) e poi
# quelli già affumicati che aspettano nei Prodotti finiti (uno per tipo), uno dopo l'altro senza buchi (combustibile e
# altro non si appendono).
# Misura del carico (2026-11-23, richiesta utente): "carne_1".."carne_3" secondo quanto è pieno il posto (spazio usato sul
# suo spazio), a terzi; l'impronta cambia solo quando un posto passa di misura.
func _rack_loads(entry: Dictionary, by_id: Dictionary) -> PackedStringArray:
	var loads := PackedStringArray()
	var type_name := String(entry.get("building_type_name", ""))
	var smokehouse := type_name == BuildingModels3D.SMOKEHOUSE_TYPE
	if (type_name != BuildingModels3D.RACK_TYPE and not smokehouse) or not entry.get("is_complete", true):
		return loads
	var building: Building = by_id.get(int(entry.get("id", -1)))
	if building == null:
		return loads
	if not smokehouse:
		for slot in BuildingStorageService.get_slot_breakdown(building):
			var item := String(BuildingModels3D.RACK_ITEM_BY_RESOURCE.get(String((slot as Dictionary).get("resource_name", "")), ""))
			loads.append(_sized_load(item, float(slot.get("space_used", 0)), float(slot.get("space_capacity", 0))))
		return loads
	for slot in BuildingStorageService.get_slot_breakdown(building):
		var item := String(BuildingModels3D.SMOKEHOUSE_ITEM_BY_RESOURCE.get(String((slot as Dictionary).get("resource_name", "")), ""))
		if not item.is_empty():
			loads.append(_sized_load(item, float(slot.get("space_used", 0)), float(slot.get("space_capacity", 0))))
	for output_name in building.production_output.keys():
		var item := String(BuildingModels3D.SMOKEHOUSE_ITEM_BY_RESOURCE.get(String(output_name), ""))
		var quantity := int(building.production_output[output_name])
		if not item.is_empty() and quantity > 0:
			var rules := CaloricCalculator.get_caloric_source_rules(String(output_name))
			var space := float(quantity) * (rules.space_per_unit if rules != null else 0.0)
			loads.append(_sized_load(item, space, float(building.rules.storage_space_per_slot)))
	return loads


# Carico con la sua misura (BuildingModels3D.RACK_LOAD_LEVELS): 1 fino a un terzo del posto, 2 fino a due terzi, 3 oltre.
# Senza capienza nota, la misura piena. "" resta "" (posto con altro).
static func _sized_load(item: String, space_used: float, space_capacity: float) -> String:
	if item.is_empty():
		return item
	var levels := BuildingModels3D.RACK_LOAD_LEVELS
	var level := levels
	if space_capacity > 0.0:
		level = clampi(ceili(space_used / space_capacity * levels - 0.0001), 1, levels)
	return "%s_%d" % [item, level]


# Catasta dell'affumicatoio finito: ceppi se ha legna da ardere, fascine se ha bastoni (nel deposito).
# Attrezzeria finita (2026-11-23): un attrezzo per tipo pronto nei Prodotti finiti (production_output), attorno alla
# rastrelliera. Vuota per gli altri edifici.
func _fuel_piles(entry: Dictionary, by_id: Dictionary) -> PackedStringArray:
	var piles := PackedStringArray()
	var type_name := String(entry.get("building_type_name", ""))
	var toolmaker := type_name == BuildingModels3D.TOOLMAKER_TYPE
	if (type_name != BuildingModels3D.SMOKEHOUSE_TYPE and not toolmaker) or not entry.get("is_complete", true):
		return piles
	var building: Building = by_id.get(int(entry.get("id", -1)))
	if building == null:
		return piles
	if toolmaker:
		for resource_name in BuildingModels3D.TOOLMAKER_TOOL_BY_RESOURCE:
			if int(building.production_output.get(resource_name, 0)) > 0:
				piles.append(String(BuildingModels3D.TOOLMAKER_TOOL_BY_RESOURCE[resource_name]))
		return piles
	for resource_name in BuildingModels3D.SMOKEHOUSE_FUEL_PILES:
		if int((building.stored_resources.get(resource_name, {}) as Dictionary).get("quantity", 0)) > 0:
			piles.append(String(BuildingModels3D.SMOKEHOUSE_FUEL_PILES[resource_name]))
	return piles


# Riempimento di una fossa dei rifiuti finita, tra 0 e 1, a passi di 1% (il modello si rifà solo quando cambia
# davvero); -1 se l'edificio non è una fossa finita. Rifiuti più detriti, come il gioco (WasteDisposalService).
func _pit_fill(entry: Dictionary, by_id: Dictionary) -> float:
	if not entry.get("is_complete", true):
		return -1.0
	var building: Building = by_id.get(int(entry.get("id", -1)))
	if not WasteDisposalService.is_pit(building):
		return -1.0
	var fill := float(WasteDisposalService.get_pit_fill(building)) / float(building.rules.waste_capacity)
	return snappedf(clampf(fill, 0.0, 1.0), 0.01)


func _stage_of_entry(entry: Dictionary, by_id: Dictionary) -> int:
	if entry.get("is_complete", true):
		return BuildingConstructionStage.COMPLETE
	return BuildingConstructionStage.stage_of(by_id.get(int(entry.get("id", -1))))


func _buildings_by_id() -> Dictionary:
	var by_id := {}
	var macro_world: World = _game.get("macro_world")
	if macro_world != null:
		for building in macro_world.buildings:
			by_id[building.id] = building
	return by_id


# Edifici finiti di un tipo nella cella (es. "deposit_site"), dallo stesso elenco e con lo stesso centro del 2D.
func building_places(coords: Vector2i, type_name: String) -> BuildingPlacesSnapshot3D:
	var snapshot := BuildingPlacesSnapshot3D.new()
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return snapshot
	for entry in _complete_entries_of_type(cell.renderer, type_name):
		snapshot.centers.append(MicroCellRenderer._building_entry_center(entry) / float(MicroCellRenderer.CELL_SIZE))
		snapshot.seeds.append(hash(int(entry.get("id", -1))))
	return snapshot


# Mattonelle dell'edificio "Terra battuta" della cella, con i lati che il 2D lascia dritti (dirt_neighbors, calcolati
# dal gioco): finite (piene) e in cantiere dopo la pulizia, battute quanto il lavoro fatto.
func dirt_ground_tiles(coords: Vector2i) -> DirtGroundSnapshot3D:
	var snapshot := DirtGroundSnapshot3D.new()
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return snapshot
	var by_id := {}
	for entry in cell.renderer.buildings:
		if entry.get("building_type_name", "") != "dirt_ground":
			continue
		var strength := 1.0
		if not entry.get("is_complete", true):
			if by_id.is_empty():
				by_id = _buildings_by_id()
			strength = _dirt_ground_strength(by_id.get(int(entry.get("id", -1))))
			if strength <= 0.0:
				continue
		snapshot.positions.append(entry["position"])
		snapshot.neighbor_masks.append(int(entry.get("dirt_neighbors", 0)))
		snapshot.strengths.append(strength)
		snapshot.shades.append(0.0)
		snapshot.tiles.append(1)
	if BEATEN_UNDER_BUILDINGS:
		for entry in cell.renderer.buildings:
			if String(entry.get("building_type_name", "")) in NO_BEATEN_UNDER_TYPES:
				continue
			# Cantieri: terra battuta già da quando l'allestimento è partito (2026-11-19, richiesta utente: non scura
			# durante i lavori e chiara alla fine).
			if not entry.get("is_complete", true) and not _occupies_ground(entry, by_id):
				continue
			var corner: Vector2i = entry["position"]
			var size: Vector2i = entry.get("size", Vector2i(1, 1))
			var shade := 1.0 if String(entry.get("building_type_name", "")) in DARKER_BEATEN_TYPES else 0.0
			for dy in range(size.y):
				for dx in range(size.x):
					snapshot.positions.append(corner + Vector2i(dx, dy))
					snapshot.neighbor_masks.append(0)
					snapshot.strengths.append(1.0)
					snapshot.shades.append(shade)
					snapshot.tiles.append(0)
	return snapshot


# Impronta della terra battuta: elenco del 2D + avanzamento dei cantieri a passi (non a ogni briciola di lavoro).
func dirt_ground_signature(coords: Vector2i) -> Array:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return []
	var signature: Array = [cell.renderer.buildings, cell.renderer.buildings.size()]
	var by_id := {}
	for entry in cell.renderer.buildings:
		if entry.get("is_complete", true):
			continue
		if entry.get("building_type_name", "") == "dirt_ground":
			if by_id.is_empty():
				by_id = _buildings_by_id()
			signature.append(_dirt_ground_strength(by_id.get(int(entry.get("id", -1)))))
		elif BEATEN_UNDER_BUILDINGS:
			signature.append(_occupies_ground(entry, by_id))
	return signature


# Cantiere con l'allestimento partito (BuildingConstructionStage.occupies_ground). by_id si riempie alla prima richiesta.
func _occupies_ground(entry: Dictionary, by_id: Dictionary) -> bool:
	if by_id.is_empty():
		by_id.merge(_buildings_by_id())
	return BuildingConstructionStage.occupies_ground(by_id.get(int(entry.get("id", -1))))


# Lavoro fatto, a passi di DIRT_GROUND_STEPS, solo dopo la pulizia del cantiere (prima la terra è solo nuda).
func _dirt_ground_strength(building: Building) -> float:
	if building == null or not bool(building.construction_progress.get("ground_cleared", false)):
		return 0.0
	return floorf(BuildingConstructionStage.labor_progress(building) * DIRT_GROUND_STEPS) / DIRT_GROUND_STEPS


# "Impronta" degli edifici della cella: cambia quando il 2D riceve un elenco nuovo.
func buildings_signature(coords: Vector2i) -> Array:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return []
	return [cell.renderer.buildings, cell.renderer.buildings.size()]


# Mucchietti dei magazzini della cella: uno per posto occupato del sito di deposito e del deposito coperto, nella stessa
# griglia del 2D (MicroCellRenderer._draw_deposit_site_storage_grid: 3×3 in ordine di riga, centrata sull'edificio).
func storage_piles(coords: Vector2i) -> StoragePilesSnapshot3D:
	var snapshot := StoragePilesSnapshot3D.new()
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return snapshot
	var px := float(MicroCellRenderer.CELL_SIZE)
	var columns := MicroCellRenderer.DEPOSIT_SITE_STORAGE_GRID_COLUMNS
	var spacing := MicroCellRenderer.DEPOSIT_SITE_STORAGE_GRID_CELL_SPACING
	for type_name in ["deposit_site", "covered_depot"]:
		for entry in _complete_entries_of_type(cell.renderer, type_name):
			var center := MicroCellRenderer._building_entry_center(entry)
			var slots: Array = entry.get("slot_breakdown", [])
			for i in range(mini(slots.size(), columns * columns)):
				var resource_name := String((slots[i] as Dictionary).get("resource_name", ""))
				if resource_name == "":
					continue
				var offset := Vector2((float(i % columns) - 1.0) * spacing, (float(i / columns) - 1.0) * spacing)
				snapshot.add((center + offset) / px, resource_name, hash([int(entry.get("id", -1)), i]))
	_add_ground_piles(snapshot, coords)
	return snapshot


# Mucchi a terra della cella (GameData.ground_piles), come GroundPileView: le prime MAX_ICONS risorse in ordine di nome,
# sparse attorno al centro della microcella con le STESSE posizioni stabili (stessa sequenza casuale, seme = id del
# mucchio), più piccole del magazzino. Le carcasse con il loro modello (_add_carcasses).
func _add_ground_piles(snapshot: StoragePilesSnapshot3D, coords: Vector2i) -> void:
	var game_data: GameData = GameSettings.active_game_data
	if game_data == null:
		return
	var px := float(MicroCellRenderer.CELL_SIZE)
	for pile in game_data.ground_piles:
		if pile.macro_coords != coords:
			continue
		_add_carcasses(snapshot, pile)
		var names := pile.get_resource_names().slice(0, GroundPileView.MAX_ICONS)
		if names.is_empty():
			continue
		# Stessa sequenza di GroundPileView._build_slots (angolo di partenza, poi per ogni posto distanza e angolo).
		var rng := RandomNumberGenerator.new()
		rng.seed = pile.id
		var start_angle := rng.randf_range(0.0, TAU)
		for i in range(names.size()):
			var distance := 0.0 if i == 0 else rng.randf_range(GroundPileView.SCATTER_RADIUS * 0.6, GroundPileView.SCATTER_RADIUS)
			var angle := start_angle + TAU * float(i) / float(GroundPileView.MAX_ICONS) + rng.randf_range(-0.5, 0.5)
			rng.randf_range(-PI, PI) # rotazione dell'icona del 2D: qui la decide Piles3D, ma la sequenza resta la stessa
			var offset := Vector2.from_angle(angle) * distance / px
			snapshot.add(pile.get_position() + offset, names[i], hash([pile.id, i]), GroundPileView.ICON_SCALE)


# Carcasse di un mucchio come GroundPileView.show_pile: stessa rotazione e spostamento stabili (seme id*31+i), stessa
# taglia (_carcass_scale), colore della sagoma 2D della specie (i domestici col loro colore).
func _add_carcasses(snapshot: StoragePilesSnapshot3D, pile: GroundPile) -> void:
	var px := float(MicroCellRenderer.CELL_SIZE)
	for i in range(pile.carcasses.size()):
		var carcass: Dictionary = pile.carcasses[i]
		var species := String(carcass.get("species", ""))
		var rng := RandomNumberGenerator.new()
		rng.seed = pile.id * 31 + i
		var rotation := rng.randf_range(-0.6, 0.6)
		var offset := Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.6, 0.6))
		var scale := GroundPileView._carcass_scale(species, int(carcass.get("age_band", GameTypes.AgeBand.ADULT)))
		var wild := species
		var color := Color.GRAY
		var domestic := DomesticAnimalCalculator.get_rules(species)
		if domestic != null:
			wild = domestic.wild_species_name
			color = domestic.body_color
		else:
			color = _species_color(species)
		color.a = 1.0
		snapshot.add_carcass(pile.get_position() + offset / px, GroundPileView.CARCASS_BODY_LENGTH * scale / px, rotation,
			color, wild == "partridge")


# Colore della sagoma 2D di una specie selvatica (AnimalGroupRenderer.build_species_mesh).
static func _species_color(species: String) -> Color:
	match species:
		"rabbit": return AnimalGroupRenderer.RABBIT_COLOR
		"deer": return AnimalGroupRenderer.DEER_COLOR
		"boar": return AnimalGroupRenderer.BOAR_COLOR
		"tarpan": return AnimalGroupRenderer.TARPAN_COLOR
		"wild_donkey": return AnimalGroupRenderer.WILD_DONKEY_COLOR
		"aurochs": return AnimalGroupRenderer.AUROCHS_COLOR
		"mouflon": return AnimalGroupRenderer.MOUFLON_COLOR
		"bezoar": return AnimalGroupRenderer.BEZOAR_COLOR
		"wolf": return AnimalGroupRenderer.WOLF_COLOR
		"partridge": return AnimalGroupRenderer.PARTRIDGE_COLOR
	return GroundPileView.CARCASS_FUR_COLOR


func _complete_entries_of_type(renderer: MicroCellRenderer, type_name: String) -> Array:
	var entries: Array = []
	for entry in renderer.buildings:
		if entry.get("building_type_name", "") == type_name and entry.get("is_complete", true):
			entries.append(entry)
	return entries


func _hearth_state(building_id: int) -> int:
	var macro_world: World = _game.get("macro_world")
	if macro_world == null:
		return HearthSnapshot3D.OUT
	for building in macro_world.buildings:
		if building.id != building_id:
			continue
		var now := _game_time_days()
		# Falò dello spiazzo delle feste: acceso solo durante il banchetto, poi braci per un po' e spento (il combustibile
		# nel deposito è quello della prossima festa, non tiene le braci).
		if building.building_type_name == BuildingModels3D.FEAST_GROUND_TYPE:
			if SocialRiteService.has_lit_bonfire(building):
				_hearth_last_burning[building_id] = now
				return HearthSnapshot3D.BURNING
			if now - float(_hearth_last_burning.get(building_id, -INF)) < HEARTH_EMBERS_AFTER_COOKING_DAYS:
				return HearthSnapshot3D.EMBERS
			return HearthSnapshot3D.OUT
		if building.smoking_now:
			_hearth_last_burning[building_id] = now
			return HearthSnapshot3D.BURNING
		var since_burning := now - float(_hearth_last_burning.get(building_id, -INF))
		if since_burning < HEARTH_EMBERS_AFTER_COOKING_DAYS:
			return HearthSnapshot3D.EMBERS
		if ProductionService.get_available_fuel(building) > 0.0:
			return HearthSnapshot3D.EMBERS
		return HearthSnapshot3D.OUT
	return HearthSnapshot3D.OUT


# Cosa copre il suolo della cella: erba, alberi e cespugli, rocce non esaurite. Dagli stessi elenchi che disegna il 2D
# (filtrati dalla nebbia come nel 2D), così con la nebbia anche in 3D resterà coerente.
func ground_cover_snapshot(coords: Vector2i) -> GroundCoverSnapshot3D:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	var snapshot := GroundCoverSnapshot3D.new()
	if cell == null or cell.renderer == null:
		return snapshot
	var renderer := cell.renderer
	snapshot.grass = renderer.vegetation_positions.get(GameTypes.WorldObjectType.GRASS, [])
	snapshot.trees = renderer.vegetation_positions.get(GameTypes.WorldObjectType.TREE, [])
	snapshot.shrubs = renderer.vegetation_positions.get(GameTypes.WorldObjectType.SHRUB, [])
	for pos in renderer.stone_positions:
		if not renderer.depleted_stone_positions.has(pos):
			snapshot.rocks.append(pos)
	return snapshot


# "Impronta" del suolo: cambia quando il 2D riceve elenchi nuovi di erba, alberi, cespugli o rocce.
func ground_cover_signature(coords: Vector2i) -> Array:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return []
	var renderer := cell.renderer
	var signature: Array = [renderer.vegetation_positions]
	for object_type in [GameTypes.WorldObjectType.GRASS, GameTypes.WorldObjectType.TREE, GameTypes.WorldObjectType.SHRUB]:
		var positions: Array = renderer.vegetation_positions.get(object_type, [])
		signature.append(positions)
		signature.append(positions.size())
	signature.append_array([renderer.stone_positions, renderer.stone_positions.size(),
		renderer.depleted_stone_positions, renderer.depleted_stone_positions.size()])
	return signature


# Erba-risorsa della cella (le microcelle d'erba del 2D) e stagione del 2D, per i ciuffi (GrassTufts3D).
func grass_snapshot(coords: Vector2i) -> GrassSnapshot3D:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	var snapshot := GrassSnapshot3D.new()
	if cell == null or cell.renderer == null:
		return snapshot
	snapshot.positions = cell.renderer.vegetation_positions.get(GameTypes.WorldObjectType.GRASS, [])
	snapshot.season = cell.renderer.current_season
	return snapshot


# "Impronta" dei ciuffi: cambia con l'elenco dell'erba del 2D o con la stagione.
func grass_signature(coords: Vector2i) -> Array:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return []
	var positions: Array = cell.renderer.vegetation_positions.get(GameTypes.WorldObjectType.GRASS, [])
	return [cell.renderer.vegetation_positions, positions, positions.size(), cell.renderer.current_season]


# Risorse "chiazza d'erba" della cella (verdure, erbe medicinali, granaglie, lino), come le riceve il 2D
# (MicroCellRenderer.grass_patch_availability), col punto della figurina del 2D (_lot_marker_offset, in microcelle).
const GROUND_PATCH_OWN_MODEL_GRAIN := "wild_flax"


func ground_patch_snapshot(coords: Vector2i) -> GroundPatchSnapshot3D:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	var snapshot := GroundPatchSnapshot3D.new()
	if cell == null or cell.renderer == null:
		return snapshot
	var renderer := cell.renderer
	var px := float(MicroCellRenderer.CELL_SIZE)
	# Granaglie (2026-11-21): il 2D le disegna tutte con una spighetta per lotto (chiave GRAIN_MARKER_KEY, unione); il 3D
	# mette nello stesso punto una spiga per OGNI granaglia del lotto (utente: si vede che sono diverse anche prima di
	# sapere quali sono), "grain" = il suo nome, "cluster" = [posto, quante] per aprirle a ciuffetto (GroundPlants3D).
	# Il lino selvatico resta a parte: avrà il suo modello.
	var grains_by_lot: Dictionary = {} # lotto -> Array di nomi
	for resource in renderer.grass_patch_availability:
		var name := String(resource)
		if name == MicroCellRenderer.GRAIN_MARKER_KEY:
			continue
		var is_grain := name != GROUND_PATCH_OWN_MODEL_GRAIN and MicroCellRenderer._is_grain_resource(name)
		var lots: Dictionary = renderer.grass_patch_availability[resource]
		for lot in lots:
			var quantity := int(lots[lot])
			if quantity <= 0:
				continue
			if is_grain:
				if not grains_by_lot.has(lot):
					grains_by_lot[lot] = []
				(grains_by_lot[lot] as Array).append(name)
				continue
			var offset: Vector2 = renderer._lot_marker_offset(lot, name) / px
			snapshot.items.append({"resource": name, "lot": lot, "pos": Vector2(lot) + Vector2(0.5, 0.5) + offset})
	# Uova (2026-11-21): il 2D le tiene a parte (egg_nest_availability, set_grass_patch_availability le devia lì); un nido
	# per lotto con uova, nello stesso punto dell'ovetto del 2D.
	for lot in renderer.egg_nest_availability:
		if int(renderer.egg_nest_availability[lot]) <= 0:
			continue
		var egg_offset: Vector2 = renderer._lot_marker_offset(lot, MicroCellRenderer.EGG_RESOURCE_NAME) / px
		snapshot.items.append({"resource": MicroCellRenderer.EGG_RESOURCE_NAME, "lot": lot, "pos": Vector2(lot) + Vector2(0.5, 0.5) + egg_offset})
	for lot in grains_by_lot:
		var offset: Vector2 = renderer._lot_marker_offset(lot, MicroCellRenderer.GRAIN_MARKER_KEY) / px
		var names: Array = grains_by_lot[lot]
		names.sort() # ordine fisso: ogni granaglia tiene il suo posto nel ciuffetto
		for i in range(names.size()):
			snapshot.items.append({"resource": MicroCellRenderer.GRAIN_MARKER_KEY, "grain": names[i], "lot": lot,
				"pos": Vector2(lot) + Vector2(0.5, 0.5) + offset, "cluster": [i, names.size()]})
	return snapshot


# "Impronta" delle risorse "chiazza d'erba": cambia quando il 2D riceve una disponibilità nuova per una risorsa.
func ground_patch_signature(coords: Vector2i) -> Array:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return []
	var availability: Dictionary = cell.renderer.grass_patch_availability
	var eggs: Dictionary = cell.renderer.egg_nest_availability
	var signature: Array = [availability, availability.size(), eggs, eggs.size()]
	for resource in availability:
		signature.append(availability[resource])
		signature.append((availability[resource] as Dictionary).size())
	return signature


# Opzione "mostra griglia" (la stessa del 2D).
func grid_visible() -> bool:
	return UserOptions.show_grid


# --- Camera 2D: il 3D la usa come punto guardato, così il gioco (celle accese, ritorno al 2D) resta allineato. ---

func _camera_2d() -> Camera2D:
	return _game.get_node_or_null("Camera2D") as Camera2D


# Punto guardato, in microcelle.
func camera_position() -> Vector2:
	var cam := _camera_2d()
	return cam.position / float(MicroCellRenderer.CELL_SIZE) if cam != null else Vector2.ZERO


func camera_zoom() -> float:
	var cam := _camera_2d()
	return cam.zoom.x if cam != null else 1.0


# Spinta di "mouse al bordo dello schermo" (x, y fra -1 e 1), con la stessa regola del 2D (margine, barra laterale e
# pannelli che coprono la mappa, mouse sopra la UI): calcolata dalla camera 2D, mai copiata.
func edge_pan_vector() -> Vector2:
	var cam := _camera_2d()
	if cam == null or not cam.has_method("_get_edge_pan_vector"):
		return Vector2.ZERO
	return cam.call("_get_edge_pan_vector")


# Attesa prima che parta lo spostamento al bordo (la stessa costante della camera 2D).
func edge_pan_delay() -> float:
	var cam := _camera_2d()
	if cam == null or cam.get_script() == null:
		return 0.3
	return float((cam.get_script() as Script).get_script_constant_map().get("EDGE_PAN_ACTIVATION_DELAY", 0.3))


func move_camera(delta_microcells: Vector2) -> void:
	var cam := _camera_2d()
	if cam != null:
		cam.position += delta_microcells * float(MicroCellRenderer.CELL_SIZE)


# true mentre un popup bloccante è aperto (GameScene blocca la camera 2D): il 3D si ferma allo stesso modo.
func camera_input_locked() -> bool:
	var cam := _camera_2d()
	return cam != null and bool(cam.get("input_locked"))


# --- Vista 2D ---

# Nasconde/mostra tutta la mappa 2D (celle, persone, animali). La UI sta nel CanvasLayer e resta visibile.
func set_2d_visible(value: bool) -> void:
	_game.visible = value
	if value:
		for labels in _hidden_screen_labels:
			if is_instance_valid(labels):
				(labels as CanvasLayer).visible = true
		_hidden_screen_labels.clear()


# Click nel 3D (2026-11-19): allinea la mappa 2D nascosta al puntatore, così il punto `ground` (microcelle, coordinate
# della vista) cade esattamente sotto `screen`. Le selezioni del gioco (click, doppio click, pannelli) leggono la posizione
# del mouse sulla mappa 2D e funzionano invariate. Solo la trasformazione della tela del mondo: la UI (CanvasLayer) e il
# 3D non cambiano; la camera 2D la rimette a posto da sola quando si muove o si torna al 2D.
func align_2d_pointer(screen: Vector2, ground: Vector2) -> void:
	var zoom := camera_zoom()
	var world := ground * float(MicroCellRenderer.CELL_SIZE)
	_game.get_viewport().canvas_transform = Transform2D(0.0, Vector2(zoom, zoom), 0.0, screen - world * zoom)


# Altezza del terreno sotto un punto della vista (microcelle), come la disegna il 3D; 0 fuori dalle celle accese.
func ground_height_at(point: Vector2) -> float:
	for coords in (_game.get("live_cells") as Dictionary):
		var origin := cell_origin(coords)
		var local := point - origin
		if local.x >= 0.0 and local.y >= 0.0 and local.x < World.WIDTH and local.y < World.HEIGHT:
			return GroundHeight3D.land_height(coords.x * World.WIDTH + local.x, coords.y * World.HEIGHT + local.y)
	return 0.0


# Selezioni del 2D nella cella (MicroCellRenderer._selected_*) con le stesse misure del 2D, più l'edificio sotto il
# mouse (hovered_building_id, -1 = nessuno). Persone e animali non ancora: non sono nel 3D.
func selection(coords: Vector2i, hovered_building_id: int) -> SelectionSnapshot3D:
	var snapshot := SelectionSnapshot3D.new()
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return snapshot
	var renderer := cell.renderer
	var px := float(MicroCellRenderer.CELL_SIZE)
	var padding := MicroCellRenderer.SELECTION_OUTLINE_PADDING_RATIO
	var none := Vector2i(-1, -1)
	for key in ["_selected_microcell", "_selected_stick_lot"]:
		var lot: Vector2i = renderer.get(key)
		if lot != none:
			snapshot.squares.append(lot)
	var selected_id: int = renderer.get("_selected_building_id")
	var building_ids: Array[int] = [selected_id]
	if hovered_building_id != selected_id:
		building_ids.append(hovered_building_id)
	for building_id in building_ids:
		if building_id == -1:
			continue
		var center := renderer.get_building_screen_position(building_id)
		if center == Vector2(-1, -1):
			continue
		var radius := MicroCellRenderer.BUILDING_FENCE_RADIUS * padding
		for entry in renderer.buildings:
			if entry.get("id", -1) == building_id:
				var rect_size: Vector2i = entry.get("size", Vector2i(1, 1))
				if rect_size != Vector2i(1, 1):
					radius = maxf(radius, (Vector2(rect_size) * px).length() / 2.0 * padding)
				break
		var is_selected: bool = building_id == selected_id
		_add_halo(snapshot, center / px, radius / px, SelectionSnapshot3D.SELECTED if is_selected else SelectionSnapshot3D.HOVER)
		if is_selected:
			snapshot.selected_building_id = building_id
		else:
			snapshot.hovered_building_id = building_id
	var stone: Vector2i = renderer.get("_selected_stone_position")
	if stone != none and renderer.stone_positions.has(stone):
		_add_halo(snapshot, renderer.get_stone_screen_position(stone) / px, MicroCellRenderer.STONE_MAX_EXTENT * padding / px, SelectionSnapshot3D.SELECTED)
	var plant_type: int = renderer.get("_selected_individual_type")
	if plant_type != -1:
		var key: Vector3i = renderer.get("_selected_individual_key")
		var radius := 1.6 * padding
		# Centro: nel 2D l'anello sta sulla chioma (vista dall'alto); nel 3D l'alone va a terra, attorno al piede del tronco.
		var center := renderer.get_individual_screen_position(plant_type, key)
		if plant_type == GameTypes.WorldObjectType.TREE:
			center = renderer._compute_tree_visual(key, renderer._lot_extent_counts(plant_type))["ground"]
		if renderer.has_individual(plant_type, key):
			if plant_type == GameTypes.WorldObjectType.TREE:
				var visual: Dictionary = renderer._compute_tree_visual(key, renderer._lot_extent_counts(plant_type))
				radius = float(visual["canopy_radius"]) * padding
			elif plant_type == GameTypes.WorldObjectType.SHRUB:
				var visual: Dictionary = renderer._compute_shrub_visual(key, renderer._lot_extent_counts(plant_type))
				radius = (MicroCellRenderer.SHRUB_BLOB_MAX_DISTANCE_RATIO * float(visual["density_scale"])
					+ MicroCellRenderer.SHRUB_BLOB_MAX_RADIUS_RATIO * float(visual["size_multiplier"])) * padding
		_add_halo(snapshot, center / px, radius / px, SelectionSnapshot3D.SELECTED)
	# Mucchio a terra selezionato (2026-11-21): la selezione sta in GameScene, non nel renderer; stesso raggio del 2D
	# (GroundPileView._draw: sparpagliamento delle icone più 0,8 lati d'icona).
	var pile_id: int = _game.get("selected_ground_pile_id")
	if pile_id != -1:
		var pile := GroundPileService.find_by_id(_game.get("game_data"), pile_id)
		if pile != null and pile.macro_coords == coords:
			var icon_side := MicroCellRenderer.DEPOSIT_SITE_STORAGE_SQUARE_SIDE * GroundPileView.ICON_SCALE
			var pile_radius := (GroundPileView.SCATTER_RADIUS + icon_side * 0.8) * padding
			_add_halo(snapshot, pile.get_position(), pile_radius / px, SelectionSnapshot3D.SELECTED)
	return snapshot


# Aree di lavoro mostrate dal 2D nella cella (WorkAreaOverlay e WorkAreaDragPreview nel container della cella), con gli
# stessi colori, bordi e riempimenti. Le loro etichette in spazio schermo (MapScreenLabels, un CanvasLayer che il 2D
# nascosto non spegne) seguirebbero la mappa 2D: le nasconde finché il 3D è acceso (set_2d_visible le rimette).
func work_areas(coords: Vector2i) -> WorkAreasSnapshot3D:
	var snapshot := WorkAreasSnapshot3D.new()
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	var game_data: GameData = GameSettings.active_game_data
	if cell == null or cell.container == null or game_data == null:
		return snapshot
	var by_id := {}
	for child in cell.container.get_children():
		if child is WorkAreaOverlay:
			var overlay := child as WorkAreaOverlay
			_hide_screen_labels(overlay)
			for area in overlay._areas_to_draw(game_data):
				var border := WorkAreaOverlay.BORDER_WIDTH
				var fill := WorkAreaOverlay.FILL_ALPHA
				if WorkAreaOverlay.pick_mode:
					border = WorkAreaOverlay.PICK_BORDER_WIDTH
					fill = WorkAreaOverlay.PICK_FILL_ALPHA
				elif area.id == WorkAreaOverlay.selected_area_id:
					border = WorkAreaOverlay.SELECTED_BORDER_WIDTH
				# Una zona sola anche se due overlay la disegnano (layer acceso + zona selezionata).
				if not by_id.has(area.id) or border > float(by_id[area.id]["border"]):
					by_id[area.id] = {"area": area, "border": border, "fill": fill}
		elif child is WorkAreaDragPreview:
			var preview := child as WorkAreaDragPreview
			_hide_screen_labels(preview)
			var rect: Rect2i = preview.get("_rect")
			if rect.size.x > 0 and rect.size.y > 0:
				snapshot.add(rect, WorkAreaDragPreview.PREVIEW_COLOR, WorkAreaOverlay.BORDER_WIDTH, WorkAreaOverlay.FILL_ALPHA,
					"%d×%d" % [rect.size.x, rect.size.y])
	for entry in by_id.values():
		var area: WorkArea = entry["area"]
		snapshot.add(area.rect, area.color, float(entry["border"]), float(entry["fill"]), area.name,
			PackedStringArray(WorkAreaOverlay.job_icon_keys(area)))
	return snapshot


func _hide_screen_labels(owner: Node) -> void:
	var labels: Node = owner.get("_screen_labels")
	if labels is CanvasLayer and (labels as CanvasLayer).visible:
		(labels as CanvasLayer).visible = false
		_hidden_screen_labels.append(labels)


func _add_halo(snapshot: SelectionSnapshot3D, center: Vector2, radius: float, strength: float) -> void:
	snapshot.halo_centers.append(center)
	snapshot.halo_radii.append(radius)
	snapshot.halo_strengths.append(strength)


# Edificio sotto un punto della vista (microcelle): {"coords": Vector2i, "id": int}, vuoto se nessuno. Come
# GameScene._find_building_at_microcell: se ci sono due strati vince quello che non è un fondo percorribile.
func building_at(point: Vector2) -> Dictionary:
	var macro_world: World = _game.get("macro_world")
	if macro_world == null:
		return {}
	for coords in (_game.get("live_cells") as Dictionary):
		var local := point - cell_origin(coords)
		if local.x < 0.0 or local.y < 0.0 or local.x >= World.WIDTH or local.y >= World.HEIGHT:
			continue
		var lot := Vector2i(int(floor(local.x)), int(floor(local.y)))
		var ground: Building = null
		for building in macro_world.buildings:
			if building.is_demolished or not BuildingFootprint.covers(building, coords, lot):
				continue
			if building.rules != null and building.rules.walkable:
				ground = building
				continue
			return {"coords": coords, "id": building.id}
		if ground != null:
			return {"coords": coords, "id": ground.id}
		return {}
	return {}


# Anteprima del piazzamento (GameScene._building_ghost): il gioco la tiene già sotto il mouse a ogni fotogramma
# (posizione al centro del rettangolo, validità, rotazione col tasto R); qui solo letta. Il fantasma è figlio della scena
# di gioco, quindi la sua posizione su CELL_SIZE è già in coordinate della vista.
func placement_ghost() -> PlacementGhostSnapshot3D:
	var snapshot := PlacementGhostSnapshot3D.new()
	var ghost := _game.get("_building_ghost") as BuildingGhost
	if ghost == null or not is_instance_valid(ghost):
		return snapshot
	var px := float(MicroCellRenderer.CELL_SIZE)
	var center := ghost.position / px
	var size := ghost._footprint_rect_px / px
	if size.x <= 0.0 or size.y <= 0.0:
		size = Vector2.ONE
	for coords in (_game.get("live_cells") as Dictionary):
		var origin := cell_origin(coords)
		var local := center - origin
		if local.x < 0.0 or local.y < 0.0 or local.x >= World.WIDTH or local.y >= World.HEIGHT:
			continue
		snapshot.active = true
		snapshot.type_name = ghost.building_type_name
		snapshot.coords = coords
		snapshot.origin = origin
		snapshot.rect = Rect2(local - size / 2.0, size)
		snapshot.door_direction = TentShapes.direction_vector(ghost.rotation_dir)
		# Guado di pietre: di traverso al ruscello sotto il mouse, come l'anteprima 2D (BuildingGhost).
		if ghost.building_type_name == BuildingModels3D.FORD_TYPE:
			snapshot.door_direction = ford_door(ghost._stream_crossing_angle)
		# Vallo: la forma dai vicini dell'anteprima 2D; i pezzi sono già girati per lato (nord a -Z).
		if ghost.building_type_name == BuildingModels3D.EARTHWORK_TYPE:
			snapshot.linear_mask = ghost._linear_mask
			snapshot.door_direction = Vector2(0.0, -1.0)
		if ghost._footprint_door_px != Vector2.INF:
			snapshot.door_offset = ghost._footprint_door_px / px
		snapshot.buildable = ghost.is_buildable
		return snapshot
	return snapshot


# Spegne il movimento della camera 2D (tasti, bordo, rotella) mentre comanda il 3D.
func set_2d_camera_enabled(value: bool) -> void:
	var cam := _camera_2d()
	if cam != null:
		cam.set_process(value)
		cam.set_process_unhandled_input(value)
		# Tornando al 2D la tela del mondo torna quella della camera (align_2d_pointer l'aveva spostata).
		if value:
			cam.force_update_scroll()
