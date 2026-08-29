class_name PlayerHarvestService
extends RefCounted

# Prima scrittura reale in MacroCellState.vegetation_cut_exceptions (pronto da prima di questa
# sessione, mai usato) — scope volutamente ristretto a un solo individuo alla volta, nessuna stima
# di resa/materiale (fuori scope, vedi la pausa esplicita sul lavoro Human/Harvest). Il taglio
# produce quattro effetti, in ordine:
#
# 1. Blocca lo slot specifico per la finestra di rientro (IndividualVegetationService.
#    REENTRY_YEARS_BY_TYPE) — stesso meccanismo universale già documentato altrove.
# 2. L'individuo smette di essere "vivo": anno di nascita/sottotipo congelati vengono dimenticati
#    — se/quando lo slot tornerà a ospitare un individuo vero dopo la finestra di rientro sarà uno
#    NUOVO (nuovo birth_year/sottotipo), non lo stesso "resuscitato". La sola dimensione
#    (size_multiplier, età×densità al momento del taglio) sopravvive — catturata dal chiamante
#    PRIMA di questa cancellazione e passata come parametro qui — cosicché il marker visivo possa
#    restare proporzionato all'individuo reale invece di assumere una taglia neutra di default.
# 3. Decrementa resource_quantity[object_type] di 1 — un albero/cespuglio reale in meno per il
#    resto della simulazione (calorie, crescita) — SENZA alcun rischio per la stabilità delle
#    posizioni: IndividualVegetationService non abbassa mai il numero di individui sotto quanto
#    già noto per un lotto (vedi _count_known_extent_by_lot), quindi nessun ALTRO individuo può
#    sparire per effetto di questo decremento, qualunque valore assuma.
# 4. Sposta 1 unità di SPAZIO dal sottotipo tagliato (subtype_composition, mai da altri sottotipi)
#    a "vuoto", scalando dedicated_space[object_type] della stessa quantità EFFETTIVAMENTE rimossa
#    — approssimazione dichiarata: subtype_composition è tracciato in spazio (microcelle-lotto),
#    un taglio è un evento a granularità individuo; 1 unità di spazio è la conversione più semplice
#    difendibile, non pretende una precisione che il modello a spazio non ha mai avuto. Tenere
#    dedicated_space in sincrono con la sottrazione REALE (mai un valore fisso) rispetta
#    l'invariante "subtype_composition somma sempre a dedicated_space" già in uso ovunque nel
#    progetto. Conseguenza diretta e voluta: la crescita futura pesa le nuove unità sulla
#    composizione CORRENTE (vedi ResourceGrowthService/ResourceCalculator.
#    get_biome_weighted_subtype_composition) — un sottotipo azzerato da qui non viene "resuscitato"
#    da un ricalcolo proporzionale, riparte da 0 come qualunque altro sottotipo assente.
static func cut_individual(
	macro_state: MacroCellState,
	object_type: GameTypes.WorldObjectType,
	individual_key: Vector3i,
	subtype_name: String,
	size_multiplier: float,
	current_year: int
) -> void:
	# size_multiplier: catturato dal chiamante PRIMA di dimenticare sottotipo/età (vedi sotto) —
	# è l'unico modo per il marker (tronco mozzato/rovi) di restare dimensionato come l'individuo
	# vivo che rappresentava, dato che quel dato altrimenti sparirebbe con subtype/birth_year.
	macro_state.vegetation_cut_exceptions[individual_key] = {
		"origin_type": object_type,
		"cut_year": current_year,
		"size_multiplier": size_multiplier,
	}

	var birth_year_store: Dictionary = macro_state.tree_virtual_birth_year if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_virtual_birth_year
	var subtype_store: Dictionary = macro_state.tree_individual_subtype if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_individual_subtype
	birth_year_store.erase(individual_key)
	subtype_store.erase(individual_key)

	var quantity_before: int = macro_state.get_resource_quantity(object_type)
	macro_state.add_resource_quantity(object_type, -1)

	var space_before: int = macro_state.get_dedicated_space(object_type)
	var removed_by_subtype: Dictionary = macro_state.apply_subtype_space_delta(object_type, -1, {subtype_name: 1.0})
	var space_removed: int = int(removed_by_subtype.get(subtype_name, 0))
	if space_removed > 0:
		macro_state.set_dedicated_space(object_type, space_before - space_removed)

	print("[PLAYER HARVEST] tagliato %s/%s in (%d,%d,%d): resource_quantity %d->%d, dedicated_space %d->%d (spazio rimosso dal sottotipo: %d)" % [
		GameTypes.WorldObjectType.keys()[object_type], subtype_name,
		individual_key.x, individual_key.y, individual_key.z,
		quantity_before, macro_state.get_resource_quantity(object_type),
		space_before, macro_state.get_dedicated_space(object_type),
		space_removed
	])
