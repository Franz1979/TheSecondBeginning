class_name SpaceReconciliationService
extends RefCounted

# Rete di sicurezza annuale, non un meccanismo primario: la mortalità (self-thinning, appena
# applicata dal chiamante) già riduce dedicated_space[TREE/SHRUB/GRASS] in base a chi è morto
# davvero, ed è più aggressiva proprio nelle celle piene — le stesse condizioni che possono
# produrre l'overshoot (vedi sotto) — quindi nella maggior parte dei casi la somma è già tornata
# a ≤ TOTAL_SPACE da sola prima ancora di arrivare qui. Questo servizio interviene SOLO sul
# residuo raro in cui non basta.
#
# Overshoot possibile SOLO tramite BuildingSiteClearingService: un edificio piazzato su una
# microcella fisicamente vuota ma non riconosciuta come tale nella contabilità aggregata (per via
# della sovrapposizione TREE/SHRUB permessa da VegetationPositionService.MIX_TREE_AND_SHRUB, che fa
# "pesare doppio" alcune microcelle) aggiunge dedicated_space[BUILDING] senza liberare nulla. Senza
# edifici, dedicated_space totale resta già sempre ≤ TOTAL_SPACE per costruzione (ResourceGrowthService
# usa get_empty_space() come tetto della crescita).
#
# Taglia SOLO da GRASS/SHRUB/TREE, mai da BUILDING (un edificio piazzato non deve restringersi o
# sparire da un ricalcolo automatico) né da ROCK (posizioni fisiche persistite, stabili). Sicuro
# anche per SHRUB/TREE: ridurre dedicated_space non cancella alcun individuo già noto (vedi
# IndividualVegetationService — un lotto già rivendicato resta noto indipendentemente dal valore
# corrente di dedicated_space, che regola solo quanti NUOVI lotti potranno essere rivendicati in
# futuro), quindi il taglio è invisibile finché la crescita non lo riassorbe naturalmente.
const TRIM_ORDER := [
	GameTypes.WorldObjectType.GRASS,
	GameTypes.WorldObjectType.SHRUB,
	GameTypes.WorldObjectType.TREE,
]

# ATTENZIONE — drift noto, non auditato: dedicated_space/subtype_composition/resource_quantity
# sono un libro contabile astratto, mai derivato da un conteggio reale delle posizioni disegnate
# (che anzi dipendono DA questo libro contabile — un audit "conta cosa c'è a schermo" sarebbe
# circolare). Ogni intervento del giocatore/degli edifici che si discosta dalla granularità
# "1 unità di spazio per LOTTO" (taglio, costruzione — vedi PlayerHarvestService/
# BuildingSiteClearingService) è un punto dove piccoli errori di arrotondamento/approssimazione
# possono accumularsi nel tempo, senza che nulla li corregga se non questa valvola (che agisce solo
# sulla soglia TOTAL_SPACE, non sulla coerenza fine dei numeri). Deciso con l'utente il 2026-08-29:
# nessun audit diagnostico per ora (costo/complessità non giustificati finché il drift resta
# invisibile) — ma se in futuro si osservano disallineamenti vistosi tra vegetazione visibile e
# dedicated_space/resource_quantity, questo è il punto da cui ripartire.


static func reconcile(macro_state: MacroCellState) -> void:
	var overshoot: int = macro_state.get_total_dedicated_space() - MacroCellState.TOTAL_SPACE
	if overshoot <= 0:
		return

	for object_type in TRIM_ORDER:
		if overshoot <= 0:
			break
		var current: int = macro_state.get_dedicated_space(object_type)
		if current <= 0:
			continue
		var trim: int = min(current, overshoot)
		_trim_space(macro_state, object_type, current, trim)
		overshoot -= trim

	if overshoot > 0:
		push_warning("[SPACE RECONCILIATION] cella (%d,%d): overshoot residuo %d dopo il taglio di GRASS/SHRUB/TREE (probabile ROCK/BUILDING/river oltre TOTAL_SPACE)" % [
			macro_state.x, macro_state.y, overshoot
		])


# apply_subtype_space_delta (non set_dedicated_space diretto) per mantenere l'invariante
# "subtype_composition somma sempre a dedicated_space" (vedi MacroCellState) anche in questo
# taglio d'emergenza — per GRASS (nessun SubtypeRules registrato, quindi nessuna composizione da
# tenere sincronizzata) la chiamata è un no-op sicuro, il fallback sotto applica in quel caso il
# taglio diretto.
static func _trim_space(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType, current: int, trim: int) -> void:
	var removed_by_subtype: Dictionary = macro_state.apply_subtype_space_delta(object_type, -trim)
	var space_removed: int = 0
	for amount in removed_by_subtype.values():
		space_removed += int(amount)
	if space_removed > 0:
		macro_state.set_dedicated_space(object_type, current - space_removed)
	else:
		macro_state.set_dedicated_space(object_type, current - trim)
