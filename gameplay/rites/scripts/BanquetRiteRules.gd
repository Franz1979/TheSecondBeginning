class_name BanquetRiteRules
extends SocialRiteRules

# Banchetto (2026-10-14, richiesta utente — primo rito sociale; dal 2026-10-17 sullo Spiazzo delle feste, docs/design/
# feast_ground.md): ai campi comuni dei riti sociali (SocialRiteRules) aggiunge il falò e il cibo. In preparazione
# l'organizzatore porta nel deposito dello spiazzo prima il combustibile del falò, poi cibo di qualunque tipo (prima il più
# deperibile) fino alla soglia di calorie dello spiazzo; all'inizio della festa il falò brucia e tutto il cibo va nel
# piatto comune, le cui calorie si dividono tra i presenti. SocialRiteService la usa solo per i riti di questo tipo.

# Combustibile del falò (in unità di fuel_value, come le ricette): portato per primo, bruciato all'inizio della festa.
@export var bonfire_fuel: float = 20.0
# Soglia di calorie del cibo da radunare: valore di partenza e minimo (si cambia per spiazzo nel pannello,
# Building.feast_calorie_threshold).
@export var default_calorie_threshold: int = 1500
@export var min_calorie_threshold: int = 500
# Coesione in più per ogni 1000 calorie servite nel piatto comune (2026-10-17, richiesta utente — più si festeggia, più il
# villaggio si unisce; prima 0.01 per pezzo di carne da 100 calorie, stesso valore), oltre alla quota fissa
# SocialRiteRules.cohesion_gain.
@export var cohesion_gain_per_1000_calories: float = 0.1
# Banchetto spontaneo (2026-10-17, attività idle): freno sulle scorte — parte solo se il cibo nei magazzini del villaggio
# vale almeno idle_min_stock_ratio × la soglia dello spiazzo (3 = la festa consuma al più un terzo). Letto da
# SocialRiteService._has_idle_food_stock. La soglia è quella dello spiazzo (2026-10-18, get_calorie_threshold).
@export var idle_min_stock_ratio: float = 3.0
