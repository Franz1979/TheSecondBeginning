class_name GameSaveService
extends RefCounted

func save_game_to_json(
	world: World,
	game_data: GameData,
	file_path: String,
	# Vector2i (coord macro) -> FogOfWarMemory — default {} per i due chiamanti (WorldScene/
	# MacroCellScene) che non tengono mai fog viva propria, solo la propagano se l'hanno ricevuta
	# da un caricamento precedente (vedi WorldScene.fog_of_war_memories). GameScene è l'unico
	# chiamante che ne ha sempre una reale da passare.
	fog_of_war_memories: Dictionary = {},
	# Folk/HumanPopulationGroup/HumanIndividual (richiesta utente, 2026-09-02 — persistenza umana)
	# — default null/[] per lo stesso motivo di fog_of_war_memories sopra: WorldScene/MacroCellScene
	# non generano mai popolazione umana propria, solo la propagano se ricevuta da GameScene tramite
	# GameSettings.active_human_* (vedi WorldScene.human_folk/human_population_group/
	# human_individuals). human_folk/human_population_group possono restare null (nessuna sezione
	# "human" scritta in quel caso, vedi sotto) se il salvataggio avviene prima che una partita
	# abbia mai seminato un popolo — non dovrebbe succedere in pratica ma resta difensivo.
	human_folk: Folk = null,
	human_population_group: HumanPopulationGroup = null,
	human_individuals: Array[HumanIndividual] = []
) -> void:
	var data := {
		"file_type": "game_save",
		"game": {
			"year": game_data.year,
			"current_day": game_data.current_day,
			# Era corrente + cache delle durate effettive delle age band (vedi GameData) — la cache
			# è persistita insieme al nome invece di essere ricalcolata al caricamento, stesso
			# principio "non ricalcolare ciò che è già stato cachato" del resto di GameData.
			"current_era_name": game_data.current_era_name,
			"era_effective_age_band_durations_male": game_data.era_effective_age_band_durations_male,
			"era_effective_age_band_durations_female": game_data.era_effective_age_band_durations_female,
			# Statistica pura (vedi GameData) — mai riletti da nessuna logica di simulazione.
			"starting_world_age_mode": game_data.starting_world_age_mode,
			"starting_animal_density": game_data.starting_animal_density,
			"starting_population_size": game_data.starting_population_size,
			"starting_exclude_hostile_start": game_data.starting_exclude_hostile_start,
			"starting_exclude_predator_territories": game_data.starting_exclude_predator_territories,
			"starting_resource_richness_preference": game_data.starting_resource_richness_preference,
			"starting_group_size_preference": game_data.starting_group_size_preference,
			"starting_guarantee_animal_presence": game_data.starting_guarantee_animal_presence,
			"starting_guarantee_stone_presence": game_data.starting_guarantee_stone_presence,
			"starting_difficulty_ratio": game_data.starting_difficulty_ratio,
			# Sede macrocella del player per GameScene (vedi GameData) — deve sopravvivere a
			# save/load, a differenza dei campi analoghi di GameSettings.
			"player_macro_cell_x": game_data.player_macro_cell_x,
			"player_macro_cell_y": game_data.player_macro_cell_y,
			# Id dell'HumanIndividual bersaglio corrente (vedi GameData — sostituisce player_micro_x/y,
			# rimossi: la posizione viaggia ora dentro human.individuals sotto, per ogni individuo).
			"player_individual_id": game_data.player_individual_id,
			# Zoom camera GameScene (vedi GameData) — deve sopravvivere a save/load come la
			# posizione del player, ma è un solo float (zoom.x == zoom.y sempre).
			"camera_zoom": game_data.camera_zoom,
			# Posizione camera GameScene (vedi GameData — Step 3, 2026-09-02: la camera non segue
			# più nessun individuo, la sua posizione va salvata per conto proprio).
			"camera_x": game_data.camera_x,
			"camera_y": game_data.camera_y,
			"camera_position_saved": game_data.camera_position_saved,
			# Ultimo giorno di pulizia periodica del fog of war (vedi GameData) — deve
			# sopravvivere a save/load per non sfasare la cadenza reale.
			"fog_of_war_last_prune_absolute_day": game_data.fog_of_war_last_prune_absolute_day,
			# Log grezzo eventi morte (Step 8, vedi GameData) — Array[Dictionary] di soli tipi
			# JSON-nativi, nessuna conversione necessaria qui a differenza di altri campi sopra.
			"death_events": game_data.death_events,
			# Log grezzo eventi nascita (Step 2 piano statistiche, 2026-09-06, vedi GameData) —
			# stesso trattamento di death_events sopra, soli tipi JSON-nativi.
			"birth_events": game_data.birth_events,
			# Snapshot popolazione/anno (Step 3 piano statistiche, 2026-09-06, vedi GameData.
			# population_snapshots) — scritto COSÌ COM'È: JSON.stringify converte da solo le
			# chiavi int in stringhe, GameLoadService le riconverte al caricamento (vedi lì).
			"population_snapshots": game_data.population_snapshots,
			# Istanze oggetti-scaduti (Step 2, vedi GameData.expired_objects) — A DIFFERENZA di
			# death_events sopra, "position" è un Vector2 (non JSON-nativo): _expired_objects_to_json
			# appiattisce ogni record in position_x/position_y, stessa convenzione già usata per
			# HumanIndividual.position poco sotto.
			"expired_objects": _expired_objects_to_json(game_data.expired_objects),
			# Allocatore id HumanIndividual (vedi GameData.next_human_id) — salvato COSÌ COM'È, mai
			# ricalcolato al caricamento (a differenza di World.next_population_group_id/
			# next_building_id): vedi il commento sul campo per il perché.
			"next_human_id": game_data.next_human_id
		},
		"world": {
			"width": World.WIDTH,
			"height": World.HEIGHT,
			"cells": [],
			"cell_states": [],
			"population_groups": [],
			"buildings": []
		}
	}
	for cell in world.cells:
		data["world"]["cells"].append({
			"x": cell.x,
			"y": cell.y,
			"terrain_base": cell.terrain_base,
			"water_type": cell.water_type,
			"river_shape": cell.river_shape,
			"coast_type": cell.coast_type,
			"biome": cell.biome
		})
	for state in world.cell_states:
		var state_data := {
			"x": state.x,
			"y": state.y,
			"resource_quantity": state.resource_quantity,
			"dedicated_space": state.dedicated_space,
			"has_ever_grown": state.has_ever_grown,
			"subtype_composition": state.subtype_composition,
			"age_composition": state.age_composition,
			"river_space": state.river_space,
			"water_dedicated_space": state.water_dedicated_space,
			"terrestrial_dedicated_space": state.terrestrial_dedicated_space,
			"active_growth_bonuses": state.active_growth_bonuses,
			"pending_migration_surplus": state.pending_migration_surplus,
			"secondary_resource_stock": state.secondary_resource_stock,
			"pending_grass_space_debt": state.pending_grass_space_debt,
			"pending_fish_space_debt": state.pending_fish_space_debt,
			"pending_bird_space_debt": state.pending_bird_space_debt
		}
		# LOD0 (vedi MacroCellState.has_ever_been_discovered): assente (= false al caricamento) per
		# la stragrande maggioranza delle macrocelle di un mondo grande, mai esplorate — stesso
		# principio "non appesantire il salvataggio" già usato per stone_positions sotto, qui ancora
		# più rilevante (potenzialmente decine di migliaia di macrocelle false contro una minoranza
		# vera).
		if state.has_ever_been_discovered:
			state_data["has_ever_been_discovered"] = true
		if state.vegetation_feeding_active:
			state_data["vegetation_feeding_active"] = true
			# Stesso principio "assente = sentinella di default" delle due sopra — grass_seed_baseline
			# resta -1 (mai catturato) per la stragrande maggioranza delle celle, solo quelle
			# congelate entrate in un territorio erbivoro attivo ne hanno uno vero (vedi
			# MacroCellState.grass_seed_baseline).
			if state.grass_seed_baseline != -1:
				state_data["grass_seed_baseline"] = state.grass_seed_baseline
		# Solo le macrocelle già aperte in MacroCellScene hanno posizioni stone generate:
		# la chiave resta assente per tutte le altre, per non appesantire il salvataggio.
		if state.stone_positions_generated:
			var stone_positions_data: Array = []
			for pos in state.stone_positions:
				stone_positions_data.append({"x": pos.x, "y": pos.y})
			state_data["stone_positions"] = stone_positions_data
			# PEBBLE (2026-09-08, richiesta utente) — nasce/vive insieme a stone_positions (stessa
			# guardia one-shot in StonePositionService.generate_if_needed), persistito nella STESSA
			# sezione: quando stone_positions_generated è true, pebble_quantities ha sempre
			# esattamente una entry per ogni posizione in stone_positions. "q" = quantità sassi
			# rimasti in quella posizione.
			var pebble_quantities_data: Array = []
			for pos in state.pebble_quantities.keys():
				pebble_quantities_data.append({"x": pos.x, "y": pos.y, "q": state.pebble_quantities[pos]})
			state_data["pebble_quantities"] = pebble_quantities_data
		# Assente se vuoto (nessun meccanismo di taglio esiste ancora, sempre il caso oggi), stesso
		# principio di stone_positions sopra — non appesantire il salvataggio per un campo mai
		# popolato. Chiave Vector3i (x, y lotto + "i" indice individuo): "i" va salvato insieme a
		# x/y, altrimenti due individui nello stesso lotto collasserebbero sulla stessa entry.
		# origin_type/cut_year sono i due campi del valore (vedi MacroCellState.
		# vegetation_cut_exceptions) — origin_type serve solo a scegliere la finestra di rientro
		# al caricamento, il blocco resta comunque unificato per qualunque tipo.
		if not state.vegetation_cut_exceptions.is_empty():
			var cut_exceptions_data: Array = []
			for key in state.vegetation_cut_exceptions.keys():
				var entry: Dictionary = state.vegetation_cut_exceptions[key]
				cut_exceptions_data.append({
					"x": key.x, "y": key.y, "i": key.z,
					"origin_type": int(entry["origin_type"]), "cut_year": int(entry["cut_year"]),
					"size_multiplier": float(entry.get("size_multiplier", 1.0))
				})
			state_data["vegetation_cut_exceptions"] = cut_exceptions_data
		# Stesso principio sopra: assenti se vuote. Popolate solo dopo che MicroCellRenderer ha
		# disegnato la cella almeno una volta (vedi MacroCellState.tree_virtual_birth_year). Chiave
		# Vector3i (x, y lotto + "i" indice individuo locale): "i" va salvato insieme a x/y,
		# altrimenti due individui nello stesso lotto collasserebbero sulla stessa entry salvata e
		# il caricamento ricostruirebbe una chiave Vector2i che non corrisponderebbe mai a nessuna
		# Vector3i cercata a runtime — l'età tornerebbe sempre "non ancora vista" ad ogni reload
		# invece di restare fissa.
		if not state.tree_virtual_birth_year.is_empty():
			var tree_birth_year_data: Array = []
			for key in state.tree_virtual_birth_year.keys():
				tree_birth_year_data.append({"x": key.x, "y": key.y, "i": key.z, "year": state.tree_virtual_birth_year[key]})
			state_data["tree_virtual_birth_year"] = tree_birth_year_data
		if not state.shrub_virtual_birth_year.is_empty():
			var shrub_birth_year_data: Array = []
			for key in state.shrub_virtual_birth_year.keys():
				shrub_birth_year_data.append({"x": key.x, "y": key.y, "i": key.z, "year": state.shrub_virtual_birth_year[key]})
			state_data["shrub_virtual_birth_year"] = shrub_birth_year_data
		# Sottotipo congelato per individuo (vedi MacroCellState.tree_individual_subtype/
		# shrub_individual_subtype) — stessa chiave Vector3i/stesso principio "assente se vuoto" di
		# tree_virtual_birth_year sopra, un campo String in più oltre a "year".
		if not state.tree_individual_subtype.is_empty():
			var tree_subtype_data: Array = []
			for key in state.tree_individual_subtype.keys():
				tree_subtype_data.append({"x": key.x, "y": key.y, "i": key.z, "subtype": state.tree_individual_subtype[key]})
			state_data["tree_individual_subtype"] = tree_subtype_data
		if not state.shrub_individual_subtype.is_empty():
			var shrub_subtype_data: Array = []
			for key in state.shrub_individual_subtype.keys():
				shrub_subtype_data.append({"x": key.x, "y": key.y, "i": key.z, "subtype": state.shrub_individual_subtype[key]})
			state_data["shrub_individual_subtype"] = shrub_subtype_data
		# Lotti rivendicati per sempre da ciascun tipo (vedi MacroCellState.tree_claimed_lots/
		# shrub_claimed_lots) — Vector2i, stesso stile {x,y} già in uso per stone_positions.
		if not state.tree_claimed_lots.is_empty():
			var tree_claimed_lots_data: Array = []
			for pos in state.tree_claimed_lots.keys():
				tree_claimed_lots_data.append({"x": pos.x, "y": pos.y})
			state_data["tree_claimed_lots"] = tree_claimed_lots_data
		if not state.shrub_claimed_lots.is_empty():
			var shrub_claimed_lots_data: Array = []
			for pos in state.shrub_claimed_lots.keys():
				shrub_claimed_lots_data.append({"x": pos.x, "y": pos.y})
			state_data["shrub_claimed_lots"] = shrub_claimed_lots_data
			# Pool bastoni per lotto (2026-09-08, richiesta utente — vedi MacroCellState.
			# stick_quantities/StickPoolService) — stesso trattamento di pebble_quantities: scrittura
			# condizionale (assente se mai calcolato per questa macrocella), nessuna pulizia/GC attiva.
			if not state.stick_quantities.is_empty():
				var stick_quantities_data: Array = []
				for pos in state.stick_quantities.keys():
					var stick_entry: Dictionary = state.stick_quantities[pos]
					stick_quantities_data.append({
						"x": pos.x, "y": pos.y,
						"checkpoint_day": int(stick_entry["checkpoint_day"]),
						"capacity": int(stick_entry["capacity"]),
						"harvested": int(stick_entry["harvested"]),
					})
				state_data["stick_quantities"] = stick_quantities_data
		# Stesso formato/principio di vegetation_cut_exceptions sopra, ma per la mortalità naturale
		# (vedi MacroCellState.vegetation_death_exceptions) — campo "death_year" invece di "cut_year".
		if not state.vegetation_death_exceptions.is_empty():
			var death_exceptions_data: Array = []
			for key in state.vegetation_death_exceptions.keys():
				var entry: Dictionary = state.vegetation_death_exceptions[key]
				death_exceptions_data.append({
					"x": key.x, "y": key.y, "i": key.z,
					"origin_type": int(entry["origin_type"]), "death_year": int(entry["death_year"]),
					"size_multiplier": float(entry.get("size_multiplier", 1.0))
				})
			state_data["vegetation_death_exceptions"] = death_exceptions_data
		data["world"]["cell_states"].append(state_data)
	# Popolazioni animali "vere" (rabbit/deer) — world-level, non più annidate dentro
	# cell_states (vedi PopulationGroup/World.population_groups). occupied_macrocells è un array
	# (1+ elementi da Step 5, vedi Territory) invece di una singola coppia x/y.
	for group in world.population_groups:
		# Garanzia esplicita AL CONFINE del salvataggio (non solo conseguenza indiretta di
		# World.remove_extinct_population_groups, che gira a fine di ogni giorno simulato): un
		# gruppo estinto (population <= 0) non finisce mai nel save, né lui né il suo territorio —
		# quest'ultimo è scritto solo dentro il record del gruppo (occupied_cells_data sotto), mai
		# come lista indipendente, quindi saltare il gruppo esclude automaticamente anche le sue
		# celle occupate.
		if group.population <= 0:
			continue
		var occupied_cells_data: Array = []
		for coords in group.territory.occupied_macrocells:
			occupied_cells_data.append({"x": coords.x, "y": coords.y})
		# hunger_buckets (giorni consecutivi di digiuno -> individui, vedi
		# AnimalHungerService/PopulationGroup): a differenza di territory_distribution_weights è
		# storia accumulata reale e va salvata — perderla al caricamento azzererebbe una crisi di
		# fame già vicina alla soglia di morte. birth_mitigation_multiplier va salvato per lo
		# stesso motivo di fondo (bug corretto: viene calcolato a inizio birth_season ma consumato
		# solo a fine — un salvataggio/caricamento nel mezzo lo perdeva, tornando al default 1.0 e
		# applicando nascite senza alcuna mitigazione). years_since_last_split (Step 10) è storia
		# reale allo stesso modo — non ricalcolabile da un checkpoint, perderla al caricamento
		# resetterebbe silenziosamente la recovery post-scissione in corso a "mai scisso".
		# hunger_split_cooldown_days (Step 11) idem: un countdown a metà perso al caricamento
		# riaprirebbe silenziosamente la porta a un nuovo split da fame prima del previsto.
		# patrol_index/patrol_direction (branchi predatori, PredatorPatrolService) sono storia
		# reale allo stesso modo di hunger_buckets — quanti giorni di percorso il branco ha già
		# camminato e in che verso, non ricostruibile dalla sola forma del territorio: perderli al
		# caricamento farebbe silenziosamente ripartire il pattugliamento da zero (vedi TODO ormai
		# risolto in PopulationGroup.gd). predation_calorie_debt/predation_surplus_carryover
		# (PredationService) sono il bookkeeping calorico del branco, stesso principio — un
		# caricamento a metà debito/surplus non deve azzerarlo silenziosamente. patrol_route NON è
		# salvato (dato derivato da territory + hunting_window_size, sempre ricalcolabile — vedi
		# GameLoadService/PredatorPatrolService.recompute_route). recent_hunt_log/
		# yearly_prey_totals (tab Fauna 3, UI — vedi PopulationGroup) sono contenuto informativo
		# reale mostrato al giocatore, non una cache di ottimizzazione: perderli al caricamento
		# sarebbe una regressione visibile (lista "ultimi 5 giorni" vuota anche dopo anni di
		# caccia), quindi salvati per intero come gli altri campi storici sopra. hunger_debt_days
		# (AnimalHungerMortalityAggregateService) è l'equivalente Livello 1 di hunger_buckets,
		# stesso principio.
		data["world"]["population_groups"].append({
			"id": group.id,
			"species_name": group.species_name,
			"population": group.population,
			"age_composition": group.age_composition,
			"occupied_macrocells": occupied_cells_data,
			"hunger_buckets": group.hunger_buckets,
			"birth_mitigation_multiplier": group.birth_mitigation_multiplier,
			"birth_mitigation_caloric_ratio": group.birth_mitigation_caloric_ratio,
			"years_since_last_split": group.years_since_last_split,
			"hunger_split_cooldown_days": group.hunger_split_cooldown_days,
			"patrol_index": group.patrol_index,
			"patrol_direction": group.patrol_direction,
			"predation_calorie_debt": group.predation_calorie_debt,
			"predation_surplus_carryover": group.predation_surplus_carryover,
			"predation_season_calories_obtained": group.predation_season_calories_obtained,
			"predation_season_calories_required": group.predation_season_calories_required,
			"hunger_debt_days": group.hunger_debt_days,
			"recent_hunt_log": group.recent_hunt_log,
			"yearly_prey_totals": group.yearly_prey_totals,
			"yearly_prey_totals_year": group.yearly_prey_totals_year
		})

	# Edifici piazzati (vedi Building.gd/World.buildings) — stesso principio di population_groups
	# sopra: rules stesso non è mai serializzato (dato statico di tipo), solo building_type_name
	# per ricaricarlo via BuildingCalculator al load. stored_resources (2026-09-09: ora resource_name
	# -> {"quantity","decay_fraction"}, vedi Building.gd — GameLoadService._parse_stored_resources
	# gestisce la retrocompatibilità col vecchio formato int diretto) salvato COSÌ COM'È, il
	# Dictionary annidato passa senza trasformazioni: JSON rappresenta nativamente sia interi che
	# Dictionary innestati, nessuna conversione necessaria qui a differenza del load.
	for building in world.buildings:
		data["world"]["buildings"].append({
			"id": building.id,
			"building_type_name": building.building_type_name,
			"macro_x": building.macro_x,
			"macro_y": building.macro_y,
			"micro_x": building.micro_x,
			"micro_y": building.micro_y,
			"construction_started_day": building.construction_started_day,
			"is_complete": building.is_complete,
			"current_durability": building.current_durability,
			"built_year": building.built_year,
			"stored_resources": building.stored_resources,
			# enabled_categories (2026-09-09, richiesta utente) — filtro categorie PER-ISTANZA (vedi
			# Building.gd), Array[SecondaryResourceTypes.Category] serializzato come Array[int]
			# grezzo (JSON non ha un concetto di array tipizzato Godot, gli enum sono int sotto il
			# cofano) — vuoto per ogni edificio che il player non ha ancora ristretto, stesso
			# trattamento "storia reale" già usato per stored_resources sopra.
			"enabled_categories": building.enabled_categories,
			"rotation": building.rotation
		})

	# Fog of war (vedi FogOfWarMemory.gd/GameScene.fog_of_war_memories) — una entry per macrocella
	# con ALMENO una posizione vista (una macrocella entrata nel set vivo come vicino ma mai
	# davvero osservata dal player, es. avvicinamento poi allontanamento senza attraversare, ha
	# last_seen_by_position vuoto: saltata per non appesantire il salvataggio con entry inutili,
	# stesso principio già usato sopra per stone_positions). Vector2i non è mai una chiave JSON
	# diretta (JSON vuole chiavi stringa): sia le coordinate macro sia quelle micro sono array di
	# oggetti {x,y,...}, stesso stile già in uso per stone_positions/occupied_macrocells sopra,
	# mai un Dictionary con chiave Vector2i serializzato direttamente.
	data["fog_of_war"] = []
	for coords in fog_of_war_memories:
		var memory: FogOfWarMemory = fog_of_war_memories[coords]
		if memory.last_seen_by_position.is_empty():
			continue
		var last_seen_data: Array = []
		for pos in memory.last_seen_by_position:
			last_seen_data.append({
				"x": pos.x,
				"y": pos.y,
				"day": memory.last_seen_by_position[pos]
			})
		data["fog_of_war"].append({
			"macro_x": coords.x,
			"macro_y": coords.y,
			"last_seen": last_seen_data
		})

	# Popolo umano del player (Folk/HumanPopulationGroup/HumanIndividual, richiesta utente,
	# 2026-09-02) — sezione assente (nessuna chiave "human") se human_folk è null, stesso principio
	# "non appesantire/non scrivere dati inesistenti" già usato altrove in questo file. human_rules_ref
	# (Folk)/folk_ref (HumanPopulationGroup)/source_group_ref (HumanIndividual) non sono mai
	# serializzati: sono ricollegati da GameLoadService dopo la ricostruzione (un solo Folk/gruppo
	# esiste oggi, human_rules_ref si ricarica dal path fisso come fa già GameScene al seeding).
	# is_moving/target_position/path di ogni individuo NON sono persistiti (richiesta utente,
	# confermato 2026-09-02): un movimento in corso al salvataggio viene scartato, l'individuo
	# riparte fermo al caricamento — stesso principio per is_selected (mai scritto qui, derivato al
	# caricamento da game_data.player_individual_id, non serve un campo ridondante per individuo).
	if human_folk != null:
		data["human"] = {
			"folk": {
				"id": human_folk.id,
				"name": human_folk.name,
				# thoughts_count/active_idea_id/thoughts_invested/completed_ideas (2026-09-07,
				# richiesta utente — modello dati albero tecnologie) — stesso trattamento diretto di
				# id/name sopra, nessuna retrocompatibilità da questo lato (il caricamento usa .get()
				# con un default per ciascuno, per i salvataggi precedenti a questi campi, vedi
				# GameLoadService). Dictionary/Array di soli String/int, serializzabili da JSON.
				# stringify() così come sono, nessun ciclo di conversione manuale necessario (a
				# differenza di fog_of_war/individuals sopra, che contengono oggetti custom).
				"thoughts_count": human_folk.thoughts_count,
				"active_idea_id": human_folk.active_idea_id,
				"thoughts_invested": human_folk.thoughts_invested,
				"completed_ideas": human_folk.completed_ideas
			},
			"group": {
				"id": human_population_group.id,
				"home_macro_x": human_population_group.home_macro_coords.x,
				"home_macro_y": human_population_group.home_macro_coords.y,
				"total_count": human_population_group.total_count
			},
			"individuals": []
		}
		for individual in human_individuals:
			data["human"]["individuals"].append({
				"id": individual.id,
				"sex": individual.sex,
				"birth_year_virtual": individual.birth_year_virtual,
				"mother_id": individual.mother_id,
				"father_id": individual.father_id,
				"partner_id": individual.partner_id,
				"name": individual.name,
				"position_x": individual.position.x,
				"position_y": individual.position.y,
				"home_macro_x": individual.home_macro_coords.x,
				"home_macro_y": individual.home_macro_coords.y,
				# Tratti d'aspetto (2026-09-04, richiesta utente) — vedi HumanIndividual.gd per il
				# perché sono persistiti. Nessuna retrocompatibilità richiesta con i save
				# precedenti a questi campi (confermato con l'utente) — vale anche per
				# facing_direction sotto.
				"hair_color": individual.hair_color,
				"clothing_color": individual.clothing_color,
				# Carnagione (2026-09-06) — stesso trattamento di hair_color/clothing_color sopra,
				# nessuna retrocompatibilità richiesta.
				"skin_color": individual.skin_color,
				# Orientamento (2026-09-04, richiesta utente: "possibile aggiungere anche
				# l'orientamento al salvataggio?") — prima viveva solo in HumanIndividualView
				# (mai salvato), spostato su HumanIndividual apposta per questo.
				"facing_direction_x": individual.facing_direction.x,
				"facing_direction_y": individual.facing_direction.y,
				# Step 4 piano mortalità (2026-09-05) — estrazione singola non ricalcolabile,
				# vedi HumanIndividual.scheduled_death_day per il perché va persistita.
				"scheduled_death_day": individual.scheduled_death_day,
				# Step 9 piano mortalità (2026-09-05) — nessuna retrocompatibilità richiesta
				# (confermato con l'utente), stesso trattamento di hair_color/clothing_color/
				# facing_direction sopra.
				"scheduled_death_cause": individual.scheduled_death_cause,
				# Step 3 piano riproduzione (2026-09-06) — estrazione di stato non ricalcolabile al
				# volo (a differenza di età/age_band), stesso motivo di scheduled_death_day sopra:
				# va persistita o una gravidanza in corso sparirebbe silenziosamente al reload.
				"is_pregnant": individual.is_pregnant,
				# Step 2 piano riproduzione (2026-09-06) — precalcolati al concepimento, vanno
				# persistiti con la stessa urgenza di is_pregnant sopra: senza, un reload a metà
				# gravidanza perderebbe il padre/i tratti già tirati per il figlio in arrivo,
				# nessuna retrocompatibilità richiesta (stesso trattamento di is_pregnant).
				"pending_child_hair_color": individual.pending_child_hair_color,
				"pending_child_skin_color": individual.pending_child_skin_color,
				"pending_child_father_id": individual.pending_child_father_id,
				# Piano "trasporto neonati" (2026-09-06) — va persistito o un reload perderebbe il
				# legame "sto trasportando questo figlio" (nessuna retrocompatibilità richiesta,
				# stesso trattamento dei campi pending_child_* sopra).
				"dependent_child_id": individual.dependent_child_id,
				# Stamina (2026-09-08, richiesta utente) — PRIMA non persistita (max_stamina veniva
				# comunque ricalcolato ogni giorno da HumanStaminaIndividualService, current_stamina
				# non aveva ancora un consumatore reale): ora che Rest/Walk la fanno davvero
				# variare, un reload che la azzerasse/reimpostasse al fallback perderebbe stato di
				# gioco reale, stesso motivo di is_pregnant/dependent_child_id sopra.
				"current_stamina": individual.current_stamina,
				"max_stamina": individual.max_stamina,
				# Capacità di trasporto (2026-09-08, richiesta utente) — carried_resource_name/
				# carried_quantity sono l'unico stato "posseduto" da un individuo che sparirebbe
				# silenziosamente al reload senza persistenza (stesso principio di dependent_child_id
				# sopra: un possesso, non un dato ricalcolabile al volo). max_carry_capacity
				# DELIBERATAMENTE non persistito: ricalcolato ogni giorno da
				# HumanCarryCapacityIndividualService, stesso trattamento che max_stamina aveva PRIMA
				# di questo passo.
				"carried_resource_name": individual.carried_resource_name,
				"carried_quantity": individual.carried_quantity,
				# carried_decay_fraction (2026-09-09, richiesta utente, Step 3 decadimento) — stesso
				# trattamento/stesso motivo di carried_quantity sopra: un possesso che sparirebbe
				# silenziosamente al reload senza persistenza.
				"carried_decay_fraction": individual.carried_decay_fraction,
				# Task/Action in corso (2026-09-08, richiesta utente — "salva anche lo stato della
				# sua action") — null se l'individuo non ha una Task attiva (Rest implicito, vedi
				# HumanIndividualActionService.apply_action), altrimenti l'intera sequenza di step
				# con progresso (vedi TaskPersistenceService.serialize_task): senza, un reload
				# perderebbe qualunque comando Walk/Think/Deposit in corso, tornando tutti gli
				# individui a Rest.
				"current_task": (
					TaskPersistenceService.serialize_task(individual.current_task)
					if individual.current_task != null else null
				)
			})

	var json_text := JSON.stringify(data, "\t")
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(json_text)
	file.close()
	print("Game saved to JSON: ", file_path)


# Appiattisce ogni record di GameData.expired_objects in un Dictionary di soli tipi JSON-nativi —
# serve perché "position" a runtime è un Vector2 vero (vedi GameData), non serializzabile
# direttamente come death_events. Stessa convenzione già in uso per HumanIndividual.position
# (position_x/position_y separati) poco sopra, solo applicata a un Array intero invece che un
# singolo oggetto.
func _expired_objects_to_json(expired_objects: Array[Dictionary]) -> Array:
	var result: Array = []
	for record in expired_objects:
		var position: Vector2 = record["position"]
		var home_macro_coords: Vector2i = record["home_macro_coords"]
		result.append({
			"object_type": record["object_type"],
			"individual_id": record["individual_id"],
			"position_x": position.x,
			"position_y": position.y,
			# Step 6 (2026-09-05) — necessario per il hit-test di selezione, stessa convenzione di
			# home_macro_x/y già usata per HumanIndividual poco sotto.
			"home_macro_x": home_macro_coords.x,
			"home_macro_y": home_macro_coords.y,
			"appeared_at_year": record["appeared_at_year"],
			"appeared_at_day": record["appeared_at_day"],
			# Step 5 (2026-09-05) — Dictionary annidato di soli int/enum (già JSON-nativi, vedi
			# GameData.expired_objects), passato COSÌ COM'È: il suo contenuto è specifico del
			# object_type (oggi solo DEAD_BODY: sex/age_at_death/hair_color/clothing_color) e a
			# questo livello generico non deve saperlo — un futuro BUILDING_RUIN metterebbe altri
			# campi qui dentro senza mai toccare questa funzione.
			"type_specific_data": record["type_specific_data"],
		})
	return result
