class_name PlantFiberPoolService
extends RefCounted

# Pool di plant_fiber per lotto/microcella con SHRUB (2026-09-16, richiesta utente — Step 2 del
# piano plant_fiber) — THIN WRAPPER su VegetationPoolService, mirror esatto di StickPoolService.gd
# ma per SHRUB invece di TREE: stesso checkpoint growth (confermato — TREE/SHRUB/GRASS crescono
# tutti allo STESSO checkpoint di fine SPRING, vedi WorldTimeService._run_growth_checkpoint/
# ResourceGrowthService.GROWABLE_TYPES, nessun calendario separato per SHRUB), unità per individuo
# maturo letta da plant_fiber.tres (campo units_per_mature_plant, tarabile senza toccare codice —
# vedi VegetationPoolService.resolve_units_per_mature_individual), NESSUN filtro subtype
# (allowed_subtypes vuoto: ogni arbusto ADULT/OLD conta, qualunque sottotipo wood_only/fruit_bearing
# — richiesta esplicita utente, a differenza delle future bacche che invece filtreranno per
# "fruit_bearing").


# Aggiorna macro_state.plant_fiber_quantities per ogni lotto SHRUB la cui capacità è scaduta
# rispetto all'ultimo checkpoint growth passato — STESSA identica formula/STESSO no-op-se-fresco di
# StickPoolService.refresh_macrocell, via VegetationPoolService.
static func refresh_macrocell(macro_state: MacroCellState, game_data: GameData) -> void:
	VegetationPoolService.refresh_macrocell(
		macro_state, game_data, GameTypes.WorldObjectType.SHRUB,
		VegetationPoolService.resolve_units_per_mature_individual("plant_fiber"),
		macro_state.plant_fiber_quantities, [], "plant_fiber"
	)
