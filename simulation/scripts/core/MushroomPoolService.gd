class_name MushroomPoolService
extends RefCounted

# Pool di mushroom per lotto/microcella con TREE (2026-09-17, richiesta utente) — THIN WRAPPER su
# VegetationPoolService, mirror esatto di StickPoolService.gd: stesso checkpoint growth (fine
# SPRING, comune a TREE/SHRUB/GRASS), unità per individuo maturo letta da mushroom.tres (campo
# units_per_mature_plant), NESSUN filtro subtype (allowed_subtypes vuoto: ogni albero ADULT/OLD
# conta, qualunque sottotipo wood_only/wild_fruit/domesticable_fruit/conifer — richiesta esplicita
# utente, "come stick"). VegetationPoolService NON è stato toccato: l'esclusione degli alberi YOUNG
# che applica già (_compute_capacity_for_lot) va bene così com'è per mushroom.
#
# Nessuna stagionalità qui dentro (richiesta esplicita utente): la capacità GREZZA si ricalcola
# allo STESSO checkpoint growth di stick, tutto l'anno — la curva stagionale (mushroom.tres,
# seasonal_availability_multiplier) viene applicata esclusivamente in lettura
# (TerrainScatteredResourceService._get_available_mushroom, tramite l'helper generico
# _apply_seasonal_availability_to_capacity), mai qui.


# Aggiorna macro_state.mushroom_quantities per ogni lotto TREE la cui capacità è scaduta rispetto
# all'ultimo checkpoint growth passato — STESSA identica formula/STESSO no-op-se-fresco di
# StickPoolService.refresh_macrocell, via VegetationPoolService.
static func refresh_macrocell(macro_state: MacroCellState, game_data: GameData) -> void:
	VegetationPoolService.refresh_macrocell(
		macro_state, game_data, GameTypes.WorldObjectType.TREE,
		VegetationPoolService.resolve_units_per_mature_individual("mushroom"),
		macro_state.mushroom_quantities, [], "mushroom"
	)
