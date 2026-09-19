class_name SecondaryResourceTypes

# Single source of truth per gli enum del dominio risorse secondarie (2026-09-08, richiesta
# utente) — stesso ruolo/stile di GameTypes.gd/BuildingTypes.gd/ExpiredObjectTypes.gd per i
# rispettivi domini, ma per ciò che serve a classificare una risorsa secondaria (SecondaryResource
# Rules). Vive separato da SecondaryResourceRules per lo stesso motivo per cui BuildingTypes vive
# separato da BuildingRules — enum condivisi tenuti fuori dalle classi Resource che li usano.
# Nessun `extends` (stesso stile di BuildingTypes/ExpiredObjectTypes) — puro contenitore di enum,
# mai istanziato.

# FOOD copre le risorse alimentari, RAW_MATERIAL le risorse non alimentari (es. pebble/stick) —
# nessun caso ipotetico anticipato oltre questi due, stesso principio già seguito da
# BuildingTypes.Category/ExpiredObjectType. Compresso da FOOD_FAST/FOOD_MEDIUM/FOOD_SLOW+
# RAW_MATERIAL a FOOD+RAW_MATERIAL (2026-09-09, richiesta utente) — la distinzione di velocità di
# deperibilità non era consultata da nessuna logica; se servirà in futuro un vero sistema di
# conservazione/scorte, si riaggiungerà come campo dedicato, non rimettendo sottocategorie qui.
# Non ancora consultato da nessuna logica — solo il dato.
enum Category {
	FOOD,
	RAW_MATERIAL,
}

# Provenienza dello stock (2026-09-08, richiesta utente) — PURAMENTE descrittivo, nessuna logica
# lo consulta: documenta se la quantità disponibile deriva da una pianta/animale (PLANT_DERIVED —
# frutti/uova/carne/forage, tutte oggi legate a resource_quantity/subtype_composition di una
# risorsa primaria vegetale/animale via CaloricCalculator) o è sparsa sul terreno stesso
# (TERRAIN_SCATTERED — es. pebble, generato da StonePositionService a partire dalle posizioni di
# ROCK, mai attraverso il pipeline CaloricCalculator.SECONDARY_SOURCES). Solo due valori: nessun
# caso ipotetico anticipato oltre questi, stesso principio già seguito per Category sopra.
enum GenerationSource {
	PLANT_DERIVED,
	TERRAIN_SCATTERED,
}

# Formula di derivazione lotti+capacità per il modello "capacità per lotto" (2026-09-19, richiesta
# utente — refactor pebble/stick/plant_fiber/mushroom/wild_vegetables: prima ogni risorsa aveva un
# proprio wrapper/case scelto per NOME nel codice — StickPoolService, un case "stick" in
# TerrainScatteredResourceService.get_available/consume, un blocco dedicato in GameScene.
# _resolve_pickup_candidates — ora la stessa scelta vive qui, sul dato, letta da un unico servizio
# generico, LotCapacityService). NONE = questa risorsa non usa il modello "capacità per lotto"
# affatto (berry/acorn/fruit/eggs/forage/fish_meat/bird_meat — altri modelli, stock aggregato o
# stateless, non toccati da questo enum). Gli altri quattro valori sono le uniche quattro formule
# oggi implementate da LotCapacityService, ciascuna risolve "quali microcelle sono un lotto" e
# "quanto vale la capacità di ciascuno":
#   - TREE_INDIVIDUAL: un lotto per ogni microcella in MacroCellState.tree_claimed_lots, capacità =
#     units_per_mature_plant × individui TREE adulti/vecchi nel lotto (stick, mushroom).
#   - SHRUB_INDIVIDUAL: STESSA formula di TREE_INDIVIDUAL, ma su shrub_claimed_lots (plant_fiber).
#   - GRASS_PATCH: lotti sparsi tra le posizioni GRASS correnti (hash su micro_seed+patch_probability),
#     capacità da un hash indipendente in [patch_capacity_min, patch_capacity_max], scalata per
#     dedicated_space(GRASS)/TOTAL_SPACE (wild_vegetables).
#   - STONE_POSITION: un lotto per ogni posizione di MacroCellState.stone_positions (generate UNA
#     SOLA volta, mai rideterminate — la capacità stessa è il valore persistito, non una cache
#     runtime, perché la generazione non è deterministica — randf_range, non hash — vedi
#     LotCapacityService.seed_stone_lot_capacity) (pebble).
enum LotSource {
	NONE,
	TREE_INDIVIDUAL,
	SHRUB_INDIVIDUAL,
	GRASS_PATCH,
	STONE_POSITION,
}
