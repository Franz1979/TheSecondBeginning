class_name ResourceAgeBandService
extends RefCounted

# Stessa lista di GRASS/TREE/SHRUB usata da growth/encroachment/mortality/migration: solo i
# sottotipi con SubtypeRules.track_age_bands=true (oggi solo i due di SHRUB) fanno davvero
# qualcosa, gli altri sono no-op per costruzione (get_subtype_rules vuoto o track_age_bands=false).
const AGE_BAND_TYPES := [
	GameTypes.WorldObjectType.GRASS,
	GameTypes.WorldObjectType.TREE,
	GameTypes.WorldObjectType.SHRUB,
]


# Chiamata da WorldTimeService._run_growth_checkpoint (fine primavera) PRIMA di growth/
# encroachment nello stesso checkpoint: opera sulla composizione young/adult/old ereditata dagli
# anni precedenti, mai su nascite che stanno per avvenire in questo stesso ciclo — vedi
# MacroCellState.apply_age_band_maturation per il dettaglio del calcolo.
func mature_age_bands(world: World) -> void:
	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue
		# LOD0: macrocella mai scoperta dentro una sessione con focus attivo — congelata, nessuna
		# maturazione età finché il player non ci arriva (vedi LODOrchestrator.is_vegetation_frozen).
		if LODOrchestrator.is_vegetation_frozen(world, state):
			continue

		for resource_type in AGE_BAND_TYPES:
			var subtype_rules := ResourceCalculator.get_subtype_rules(resource_type)
			for rule in subtype_rules:
				if not rule.track_age_bands:
					continue
				state.apply_age_band_maturation(
					resource_type, rule.subtype_name, rule.youth_duration_years, rule.adult_duration_years
				)
