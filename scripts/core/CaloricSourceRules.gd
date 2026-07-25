class_name CaloricSourceRules
extends Resource

@export var caloric_source_name: String = ""

@export_group("Origin")
# Sottotipo di origine (es. "domesticable_fruit"). Vuoto = la fonte non deriva da un
# sottotipo ma dalla risorsa primaria stessa (caso FORAGE: deriva da GRASS, non da un
# suo sottotipo — GRASS non ne ha).
@export var source_subtype: String = ""
# Frutti/unità per pianta. Non si applica a FORAGE (yield 1:1 con GRASS); resta al
# default finché non serve per una fonte con la propria resa distinta dalla pianta madre.
@export var yield_ratio: float = 1.0

@export_group("Calories")
@export var calories_per_unit: float = 1.0

@export_group("Seasonality")
# Frazione delle unità della risorsa primaria/sottotipo collegata EFFETTIVAMENTE raggiungibile/
# consumabile in quella stagione (indice = GameTypes.Season: WINTER, SPRING, SUMMER, AUTUMN).
# Non è un moltiplicatore del valore calorico per unità (quello resta fisso in
# calories_per_unit) — rappresenta quanto è marcito/sepolto/non raggiungibile. Per FORAGE: 0.6
# in inverno significa che il 40% dell'erba residua non è più foraggiabile, il resto sì.
@export var seasonal_availability_multiplier: Array[float] = [1.0, 1.0, 1.0, 1.0]

@export_group("Consumption")
# true = consumare calorie da questa fonte decrementa DIRETTAMENTE la risorsa primaria
# (dedicated_space/resource_quantity) — caso FORAGE. false (futuro) = la fonte ha un proprio
# stock indipendente (frutti maturi) che il consumo intacca senza toccare la pianta madre.
@export var consuming_depletes_primary: bool = true
# NOTA per quando implementeremo il consumo (non ancora fatto): seasonal_availability_multiplier
# sopra è un TETTO MASSIMO di unità raggiungibili, applicato UNA sola volta per calcolare il
# disponibile (vedi CaloricCalculator.get_available_units) — un consumo di X unità da questa
# fonte deve scalare 1:1 la risorsa fisica collegata (resource_quantity[GRASS] per FORAGE, lo
# stock derivato per i frutti), MAI moltiplicando/dividendo di nuovo per questo multiplier.
