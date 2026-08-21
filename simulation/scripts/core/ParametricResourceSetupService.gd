class_name ParametricResourceSetupService
extends RefCounted

# Seminatore alternativo, parametrico per eta' del mondo (GameTypes.WorldAge: YOUNG/ADULT/OLD),
# pensato per stare AFFIANCO a InitialResourceSetupService (il seminatore "giovane" di sempre),
# non sostituirlo: quest'ultimo resta il riferimento/fallback invariato, non toccato da questo
# file se non per due commenti di documentazione sui punti di dipendenza silenziosa (vedi sotto).
# Non ancora collegato al flusso di creazione partita (nessuna UI, nessuna scelta age esposta) —
# e' un service pronto all'uso, il collegamento e' un passo separato successivo.
#
# Differenze concettuali rispetto a InitialResourceSetupService:
# - STONE non scala con l'eta' (decisione di design, Opzione A): e' un giacimento geologico,
#   non un processo di crescita. Delegato invariato a InitialResourceSetupService.populate_stone
#   in ogni livello.
# - GRASS/SHRUB/TREE non sono seminati con tre chiamate indipendenti che si contendono lo spazio
#   libero in ordine (come fa InitialResourceSetupService, dove chi gira prima ha priorita' — sua
#   nota esplicita in populate_stone) ma con un UNICO step congiunto (populate_vegetation) che
#   calcola lo spazio disponibile una volta sola e lo ripartisce secondo proporzioni target
#   bioma x terreno, cosi' il risultato riflette le proporzioni volute e non l'ordine di chiamata.
# - FISH/BIRDS sono seminati come frazione della capacita' SFRUTTABILE (usable capacity, lo
#   stesso tetto verso cui la crescita converge — vedi ResourceCalculator.get_water_
#   usable_capacity_space/get_land_usable_capacity_space), non della capacita' fisica grezza
#   come in InitialResourceSetupService: per un mondo ADULT/OLD la frazione seminata deve
#   avvicinarsi al tetto che la crescita userebbe comunque, non al tetto fisico che la crescita
#   non raggiunge mai se usable_capacity_ratio < 1.0.


# --- Parametri per livello di eta' ---

const FILL_FRACTION_BY_AGE := {
	GameTypes.WorldAge.YOUNG: 0.30,
	GameTypes.WorldAge.ADULT: 0.60,
	GameTypes.WorldAge.OLD: 0.90,
}

# DESERT non punta mai al fill_fraction generale: nessuna delle sue combinazioni bioma/terreno
# converge mai al 90% (GRASS/TREE hanno densita' 0 in deserto, solo SHRUB cresce, e pochissimo —
# vedi analisi precedente). Stessa proporzione 20/90 gia' approvata per il livello OLD, derivata
# come rapporto unico invece di tre costanti scollegate: YOUNG~0.067, ADULT~0.133, OLD=0.20.
const DESERT_FILL_RATIO := 20.0 / 90.0

# Vector2(min, max) per randf_range — frazione della capacita' SFRUTTABILE (non fisica) seminata
# per FISH/BIRDS. YOUNG identico a InitialResourceSetupService (2-6%); ADULT e OLD assumono un
# mondo dove la fauna "passiva" ha gia' avuto tempo di popolarsi, senza pero' presupporre nulla
# sull'equilibrio ecologico vero (che dipenderebbe anche da predatori/erbivori, fuori scope qui).
const FAUNA_SEED_RATIO_BY_AGE := {
	GameTypes.WorldAge.YOUNG: Vector2(0.02, 0.06),
	GameTypes.WorldAge.ADULT: Vector2(0.35, 0.45),
	GameTypes.WorldAge.OLD: Vector2(0.85, 0.90),
}

const JITTER_MIN := 0.90
const JITTER_MAX := 1.10


# --- Proporzioni target GRASS/SHRUB/TREE per bioma (baseline terreno PLAIN, sommano a 1.0) ---
# DESERT deliberatamente assente: caso speciale gestito a parte in populate_vegetation (100%
# SHRUB, mai le proporzioni di questa tabella). NONE e' il fallback neutro (nessun moltiplicatore
# di bioma nei .tres, usato per celle mai dipinte — es. i corridoi fluviali di marealtodx.json).
const BIOME_PROPORTIONS := {
	GameTypes.Biome.GRASSLAND: {
		GameTypes.WorldObjectType.GRASS: 0.82,
		GameTypes.WorldObjectType.SHRUB: 0.13,
		GameTypes.WorldObjectType.TREE: 0.05,
	},
	GameTypes.Biome.FERTILE: {
		GameTypes.WorldObjectType.GRASS: 0.55,
		GameTypes.WorldObjectType.SHRUB: 0.20,
		GameTypes.WorldObjectType.TREE: 0.25,
	},
	GameTypes.Biome.FOREST: {
		GameTypes.WorldObjectType.GRASS: 0.08,
		GameTypes.WorldObjectType.SHRUB: 0.27,
		GameTypes.WorldObjectType.TREE: 0.65,
	},
	GameTypes.Biome.SWAMP: {
		GameTypes.WorldObjectType.GRASS: 0.30,
		GameTypes.WorldObjectType.SHRUB: 0.30,
		GameTypes.WorldObjectType.TREE: 0.40,
	},
	GameTypes.Biome.ROCKY: {
		GameTypes.WorldObjectType.GRASS: 0.35,
		GameTypes.WorldObjectType.SHRUB: 0.35,
		GameTypes.WorldObjectType.TREE: 0.30,
	},
	GameTypes.Biome.NONE: {
		GameTypes.WorldObjectType.GRASS: 0.75,
		GameTypes.WorldObjectType.SHRUB: 0.20,
		GameTypes.WorldObjectType.TREE: 0.05,
	},
}

# Aggiustamento terreno: il peso GRASS viene moltiplicato per questo fattore, la massa tolta
# ridistribuita a SHRUB/TREE in proporzione ai loro pesi correnti (vedi _adjust_for_terrain) —
# coerente con terrain_multiplier_mountain nei *_growth.tres, dove GRASS e' penalizzato piu' di
# SHRUB/TREE in quota (0.1 contro 0.2/0.3).
const TERRAIN_GRASS_NUDGE := {
	GameTypes.TerrainBase.PLAIN: 1.0,
	GameTypes.TerrainBase.HILL: 0.85,
	GameTypes.TerrainBase.MOUNTAIN: 0.6,
}

const VEGETATION_TYPES := [
	GameTypes.WorldObjectType.GRASS,
	GameTypes.WorldObjectType.SHRUB,
	GameTypes.WorldObjectType.TREE,
]


func populate_resources(world: World, age: GameTypes.WorldAge) -> void:
	# Delega a InitialResourceSetupService — vedi il commento speculare li' sopra
	# reserve_river_space/populate_stone. STONE non scala con l'eta' del mondo (Opzione A):
	# resta identico in YOUNG/ADULT/OLD, nessuna logica propria qui.
	var young_seeder := InitialResourceSetupService.new()
	young_seeder.reserve_river_space(world)
	young_seeder.populate_stone(world)

	populate_fish(world, age)
	populate_birds(world, age)
	populate_vegetation(world, age)


# Gemella di InitialResourceSetupService.populate_fish, ma la frazione seminata e' parametrica
# per eta' (FAUNA_SEED_RATIO_BY_AGE) e calcolata sulla capacita' SFRUTTABILE, non fisica — vedi
# nota in testa al file. Stesso ordine di controlli del riferimento (capacita' -> presenza ->
# densita' -> quantita') per facilita' di confronto.
func populate_fish(world: World, age: GameTypes.WorldAge) -> void:
	var ratio_range: Vector2 = FAUNA_SEED_RATIO_BY_AGE[age]

	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue

		var capacity := ResourceCalculator.get_water_usable_capacity_space(GameTypes.WorldObjectType.FISH, cell, state)
		if capacity <= 0:
			continue

		var chance := ResourceCalculator.get_water_presence_chance(GameTypes.WorldObjectType.FISH, cell.water_type)
		if randf() > chance:
			continue

		var max_density := ResourceCalculator.get_water_max_density(GameTypes.WorldObjectType.FISH, cell.water_type)
		if max_density <= 0.0:
			continue

		var dedicated_space: int = int(round(capacity * randf_range(ratio_range.x, ratio_range.y)))
		if dedicated_space <= 0:
			continue
		var quantity: int = int(round(max_density * dedicated_space))

		state.set_water_space(GameTypes.WorldObjectType.FISH, dedicated_space)
		state.set_resource_quantity(GameTypes.WorldObjectType.FISH, quantity)

	print("Fish popolato (mondo parametrico, age=%s)" % GameTypes.WorldAge.keys()[age])


# Gemella di InitialResourceSetupService.populate_birds — vedi populate_fish sopra per le stesse
# differenze (frazione parametrica per eta', capacita' sfruttabile invece che fisica).
func populate_birds(world: World, age: GameTypes.WorldAge) -> void:
	var ratio_range: Vector2 = FAUNA_SEED_RATIO_BY_AGE[age]

	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue

		var capacity := ResourceCalculator.get_land_usable_capacity_space(GameTypes.WorldObjectType.BIRDS, cell, state)
		if capacity <= 0:
			continue

		var chance := ResourceCalculator.get_presence_chance(
			GameTypes.WorldObjectType.BIRDS, cell.terrain_base, cell.biome, cell.coast_type
		)
		if randf() > chance:
			continue

		var max_density := ResourceCalculator.get_max_density(
			GameTypes.WorldObjectType.BIRDS, cell.terrain_base, cell.biome, cell.coast_type
		)
		if max_density <= 0.0:
			continue

		var dedicated_space: int = int(round(capacity * randf_range(ratio_range.x, ratio_range.y)))
		if dedicated_space <= 0:
			continue
		var quantity: int = int(round(max_density * dedicated_space))

		state.set_terrestrial_space(GameTypes.WorldObjectType.BIRDS, dedicated_space)
		state.set_resource_quantity(GameTypes.WorldObjectType.BIRDS, quantity)

	print("Birds popolato (mondo parametrico, age=%s)" % GameTypes.WorldAge.keys()[age])


# Step unico per GRASS+SHRUB+TREE: calcola available_space UNA VOLTA (dopo STONE e river_space,
# gia' seminati/riservati da populate_resources sopra), poi lo ripartisce secondo le proporzioni
# target bioma x terreno — a differenza di InitialResourceSetupService, che semina i tre tipi con
# chiamate indipendenti in sequenza, ognuna delle quali consuma lo spazio libero residuo al
# proprio turno (nessun controllo sulla proporzione finale risultante, solo sull'ordine).
func populate_vegetation(world: World, age: GameTypes.WorldAge) -> void:
	var fill_fraction: float = FILL_FRACTION_BY_AGE[age]
	var desert_fill_fraction: float = fill_fraction * DESERT_FILL_RATIO
	var subtype_helper := InitialResourceSetupService.new()

	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue

		var available_space: int = state.get_empty_space()
		if available_space <= 0:
			continue

		var this_fill_fraction: float
		var base_proportions: Dictionary
		if cell.biome == GameTypes.Biome.DESERT:
			this_fill_fraction = desert_fill_fraction
			base_proportions = {
				GameTypes.WorldObjectType.GRASS: 0.0,
				GameTypes.WorldObjectType.SHRUB: 1.0,
				GameTypes.WorldObjectType.TREE: 0.0,
			}
		else:
			this_fill_fraction = fill_fraction
			var biome_row: Dictionary = BIOME_PROPORTIONS.get(cell.biome, BIOME_PROPORTIONS[GameTypes.Biome.NONE])
			base_proportions = _adjust_for_terrain(biome_row, cell.terrain_base)

		# Azzera le risorse strutturalmente non idonee a questa cella (es. terreno WATER, dove
		# terrain_multiplier_water=0.0 per tutti e tre nei *_density.tres) prima di applicare la
		# variazione probabilistica, cosi' il rumore non "resuscita" una risorsa a densita' zero.
		var eligible_proportions := _apply_density_gate(base_proportions, cell.terrain_base, cell.biome, cell.coast_type)
		if eligible_proportions.is_empty():
			continue # nessuna delle tre ha densita' > 0 in questa cella (tipicamente terreno WATER)

		var jittered_proportions := _apply_jitter(eligible_proportions)

		var total_fill: int = int(round(this_fill_fraction * available_space))
		total_fill = min(total_fill, available_space)
		if total_fill <= 0:
			continue

		var space_split := _split_largest_remainder(total_fill, jittered_proportions)

		for resource_type in VEGETATION_TYPES:
			var space: int = int(space_split.get(resource_type, 0))
			if space <= 0:
				continue

			var max_density := ResourceCalculator.get_max_density(
				resource_type, cell.terrain_base, cell.biome, cell.coast_type
			)
			var quantity: int = int(round(max_density * space))

			state.set_dedicated_space(resource_type, space)
			state.set_resource_quantity(resource_type, quantity)

			# Chiamato anche qui da ParametricResourceSetupService — vedi il commento
			# speculare sopra _seed_subtype_composition/_seed_age_band_composition in
			# InitialResourceSetupService.gd.
			if resource_type == GameTypes.WorldObjectType.TREE or resource_type == GameTypes.WorldObjectType.SHRUB:
				subtype_helper._seed_subtype_composition(state, resource_type, cell.biome, space)

	print("Vegetazione (mondo parametrico, age=%s) popolata sull'intera mappa" % GameTypes.WorldAge.keys()[age])


# HILL/MOUNTAIN: il peso GRASS si riduce per TERRAIN_GRASS_NUDGE[terrain], la massa tolta si
# ridistribuisce a SHRUB/TREE in proporzione ai loro pesi CORRENTI (non un 50/50 fisso) cosi' un
# bioma gia' molto SHRUB-dominante non diventa artificialmente TREE-dominante solo per l'effetto
# del terreno. PLAIN (fattore 1.0) ritorna la riga invariata.
func _adjust_for_terrain(base: Dictionary, terrain: GameTypes.TerrainBase) -> Dictionary:
	var grass_nudge: float = TERRAIN_GRASS_NUDGE.get(terrain, 1.0)
	if grass_nudge >= 1.0:
		return base.duplicate()

	var grass: float = base[GameTypes.WorldObjectType.GRASS]
	var shrub: float = base[GameTypes.WorldObjectType.SHRUB]
	var tree: float = base[GameTypes.WorldObjectType.TREE]

	var new_grass: float = grass * grass_nudge
	var removed: float = grass - new_grass
	var shrub_tree_sum: float = shrub + tree
	var shrub_share: float = (shrub / shrub_tree_sum) if shrub_tree_sum > 0.0 else 0.5

	return {
		GameTypes.WorldObjectType.GRASS: new_grass,
		GameTypes.WorldObjectType.SHRUB: shrub + removed * shrub_share,
		GameTypes.WorldObjectType.TREE: tree + removed * (1.0 - shrub_share),
	}


# Azzera ogni risorsa con get_max_density <= 0 in questa cella specifica (terreno/bioma/costa) e
# rinormalizza le rimanenti a somma 1.0. Dizionario vuoto se nessuna risorsa e' idonea (la
# chiamante salta la cella per la vegetazione in quel caso, esattamente come farebbe
# InitialResourceSetupService per ciascun tipo singolarmente).
func _apply_density_gate(
	proportions: Dictionary, terrain: GameTypes.TerrainBase, biome: GameTypes.Biome, coast: GameTypes.CoastType
) -> Dictionary:
	var gated: Dictionary = {}
	var sum := 0.0
	for resource_type in proportions.keys():
		var max_density := ResourceCalculator.get_max_density(resource_type, terrain, biome, coast)
		if max_density <= 0.0 or proportions[resource_type] <= 0.0:
			continue
		gated[resource_type] = proportions[resource_type]
		sum += proportions[resource_type]

	if sum <= 0.0:
		return {}

	for resource_type in gated.keys():
		gated[resource_type] = gated[resource_type] / sum
	return gated


# +-10% relativo indipendente per risorsa (randf_range(0.90,1.10)), poi rinormalizzato perche' la
# somma torni a 1.0 — altrimenti il riempimento totale della cella non rispetterebbe piu'
# fill_fraction dopo il rumore.
func _apply_jitter(proportions: Dictionary) -> Dictionary:
	var jittered: Dictionary = {}
	var sum := 0.0
	for resource_type in proportions.keys():
		var p: float = proportions[resource_type]
		var factor := randf_range(JITTER_MIN, JITTER_MAX)
		var value: float = p * factor
		jittered[resource_type] = value
		sum += value

	if sum <= 0.0:
		return proportions

	for resource_type in jittered.keys():
		jittered[resource_type] = jittered[resource_type] / sum
	return jittered


# Ripartisce `total` microcelle tra le chiavi di `proportions` (gia' normalizzate a somma 1.0)
# con arrotondamento "largest remainder": ogni chiave prende il floor della propria quota esatta,
# poi le unita' residue (total - somma dei floor, sempre < numero di chiavi) vanno una a testa
# alle chiavi con il resto frazionario piu' alto — stesso principio gia' usato altrove nel motore
# (MacroCellState.apply_subtype_space_delta), cosi' la somma finale e' sempre esattamente
# `total`, mai di piu' o di meno per arrotondamento indipendente.
func _split_largest_remainder(total: int, proportions: Dictionary) -> Dictionary:
	var exact: Dictionary = {}
	var result: Dictionary = {}
	var floor_sum := 0
	for resource_type in proportions.keys():
		var value: float = float(total) * float(proportions[resource_type])
		exact[resource_type] = value
		var f: int = int(floor(value))
		result[resource_type] = f
		floor_sum += f

	var remainder: int = total - floor_sum
	if remainder <= 0:
		return result

	var keys_by_remainder: Array = proportions.keys()
	keys_by_remainder.sort_custom(
		func(a, b): return (exact[a] - result[a]) > (exact[b] - result[b])
	)
	for i in range(remainder):
		var key = keys_by_remainder[i % keys_by_remainder.size()]
		result[key] += 1

	return result
