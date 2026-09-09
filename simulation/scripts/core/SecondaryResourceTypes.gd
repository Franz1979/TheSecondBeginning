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
