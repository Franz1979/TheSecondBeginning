class_name LODOrchestrator
extends RefCounted

# Congelamento della vegetazione: dentro una scena con celle vive (GameScene/MacroCellScene) la vegetazione cresce solo
# nelle macrocelle già scoperte almeno una volta (MacroCellState.has_ever_been_discovered); le altre restano ferme come
# all'inizio partita finché il giocatore non ci arriva. In vista mondo (World.lod_focus_active a false) nulla è congelato.
# Gli animali non c'entrano: le mandrie esistono solo attorno alle celle vive (WildFaunaService).


# Marca come scoperte le SINGOLE celle vive di live_cell_coords (Dictionary[Vector2i, bool]). `season` serve solo per il
# catch-up di secondary_resource_stock alla prima scoperta (_catch_up_secondary_resource_stock sotto): senza, lo stock
# restava a 0.0 fino al prossimo checkpoint stagionale anche con vegetazione fruttifera già presente.
static func set_focus_region(world: World, live_cell_coords: Dictionary, season: GameTypes.Season) -> void:
	for coords in live_cell_coords:
		var state := world.get_cell_state_at(coords.x, coords.y)
		if state != null:
			if not state.has_ever_been_discovered:
				_catch_up_secondary_resource_stock(world, coords, state, season)
				if DebugLogging.ENABLED:
					_print_new_discovery_secondary_stock(coords, state, season)
			state.has_ever_been_discovered = true


# Catch-up alla PRIMA scoperta di una cella (richiesta utente, 2026-09-05 — vedi set_focus_region
# sopra per il perché): calcola subito, per le 4 fonti a stock persistente (CaloricCalculator.
# SECONDARY_SOURCES), un reset pieno alla stagione CORRENTE — stesso identico calcolo che
# update_secondary_resource_stock fa una volta l'anno a cycle_start_season, isolato in
# CaloricCalculator.seed_secondary_resource_stock_now per essere richiamabile anche qui, fuori dal
# normale ciclo stagionale. Nessuna modifica alla pianta stessa (TREE/SHRUB/BIRDS, che può restare
# congelata) — solo lo stock derivato si allinea subito.
static func _catch_up_secondary_resource_stock(world: World, coords: Vector2i, state: MacroCellState, season: GameTypes.Season) -> void:
	var cell := world.get_cell_at(coords.x, coords.y)
	if cell == null:
		return
	for source in CaloricCalculator.SECONDARY_SOURCES:
		var rules := CaloricCalculator.get_caloric_source_rules(source["resource_name"])
		if rules == null:
			continue
		CaloricCalculator.seed_secondary_resource_stock_now(rules, cell, state, source["primary_resource_type"], season)


# DIAGNOSTICO TEMPORANEO (vedi set_focus_region sopra) — stampa lo stock calorico REALE
# (MacroCellState.secondary_resource_stock, quello che mangiano gli animali) delle 4 fonti a
# stock persistente per la cella appena scoperta, a fianco della composizione VISIVA dei
# sottotipi (subtype_composition, quella che pilota i puntini-frutto disegnati da
# MicroCellRenderer) — le due cose sono indipendenti: un valore di composizione > 0 NON implica
# uno stock > 0, ed è proprio questo che vogliamo distinguere prima di decidere se serve un
# catch-up dedicato al momento della scoperta.
#
# Esteso (2026-09-19, richiesta utente — verifica del seeding stagionale): in testa stagione e giorno
# correnti; per ogni fonte a stock (l'elenco e' CaloricCalculator.SECONDARY_SOURCES, non piu' una
# lista scritta a mano) lo stock e il moltiplicatore stagionale di `season` (quello che
# seed_secondary_resource_stock_now ha applicato); poi, a parte, il moltiplicatore stagionale delle
# risorse a capacita' per lotto (mushroom, stick, ecc.), che NON hanno uno stock per macrocella.
# `season` e' la stessa passata a set_focus_region; il giorno e' letto da GameSettings.
# active_game_data ("?" se assente).
static func _print_new_discovery_secondary_stock(coords: Vector2i, state: MacroCellState, season: GameTypes.Season) -> void:
	var day_text := "?"
	if GameSettings.active_game_data != null:
		day_text = str(GameSettings.active_game_data.current_day)
	var stock_parts: Array[String] = []
	for source in CaloricCalculator.SECONDARY_SOURCES:
		var source_name: String = source["resource_name"]
		var source_rules := CaloricCalculator.get_caloric_source_rules(source_name)
		var multiplier_text := "?"
		if source_rules != null:
			multiplier_text = "%.2f" % source_rules.seasonal_availability_multiplier[season]
		stock_parts.append("%s=%.2f (x%s)" % [source_name, state.get_secondary_resource_stock(source_name), multiplier_text])
	var lot_parts: Array[String] = []
	for lot_name in LotCapacityService.get_all_lot_capacity_resource_names():
		var lot_rules := CaloricCalculator.get_caloric_source_rules(lot_name)
		if lot_rules != null:
			lot_parts.append("%s x%.2f" % [lot_name, lot_rules.seasonal_availability_multiplier[season]])
	var composition_parts: Array[String] = []
	for entry in [
		{"label": "shrub.fruit_bearing", "type": GameTypes.WorldObjectType.SHRUB, "subtype": "fruit_bearing"},
		{"label": "tree.wild_fruit", "type": GameTypes.WorldObjectType.TREE, "subtype": "wild_fruit"},
		{"label": "tree.domesticable_fruit", "type": GameTypes.WorldObjectType.TREE, "subtype": "domesticable_fruit"},
	]:
		composition_parts.append("%s=%d" % [entry["label"], state.get_subtype_count(entry["type"], entry["subtype"])])
	print("[CELL DISCOVERED] %s giorno %s (%d,%d) secondary_resource_stock (REALE, quello che mangiano gli animali): %s | moltiplicatori lotti: %s | subtype_composition (COSMETICO, solo disegno): %s" % [
		GameTypes.Season.keys()[season], day_text, coords.x, coords.y,
		", ".join(stock_parts), ", ".join(lot_parts), ", ".join(composition_parts)
	])


# Vero se QUESTA macrocella va saltata dai checkpoint stagionali della vegetazione.
static func is_vegetation_frozen(world: World, state: MacroCellState) -> bool:
	if not world.lod_focus_active:
		return false
	return not state.has_ever_been_discovered
