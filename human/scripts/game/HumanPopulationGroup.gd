class_name HumanPopulationGroup
extends RefCounted

# Un insediamento umano aggregato — un oggetto per villaggio, stesso principio di Folk:
# RefCounted, stato di partita, non regole statiche. Solo il minimo per collegare un gruppo a un
# Folk e sapere dove si trova — nessun age_distribution/hunger_debt/is_materialized ancora (vedi
# la memoria di progetto per il design completo, non ancora costruito qui).

var id: int = 0
var folk_ref: Folk = null
# Coordinate macro ASSOLUTE dell'insediamento — nessuna classe Territory dedicata ancora (un
# insediamento umano oggi occupa sempre e solo questa singola macrocella): stesso principio di
# rimando già seguito dal Territory animale, introdotto solo quando è servito davvero il
# multi-cella. Sentinella (-1, -1) = non ancora valorizzato, stessa convenzione di
# GameData.player_macro_cell_x/y.
var home_macro_coords: Vector2i = Vector2i(-1, -1)
var total_count: int = 0
