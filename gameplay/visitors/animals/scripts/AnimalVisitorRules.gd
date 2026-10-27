class_name AnimalVisitorRules
extends Resource

# Regole di un gruppo di animali che frequenta il villaggio (2026-10-26, richiesta utente): un file per specie in
# gameplay/visitors/animals/data/{species}.tres. Fasce d'età prese dalla specie selvatica (AnimalRules di
# wild_species_name), qui solo la composizione iniziale e l'aggressività di partenza.

# Specie selvatica (simulation/data/animals/), per le fasce d'età e il nome mostrato.
@export var wild_species_name: String = ""

@export_group("Initial composition")
# Coppia adulta (un maschio e una femmina) più gli altri adulti oltre la coppia.
@export var initial_breeding_pair: bool = true
@export var initial_extra_adults: int = 0
# Giovani nati negli anni precedenti (età tra 1 anno e la fine della giovinezza).
@export var initial_young: int = 2
# Cuccioli dell'anno (età sotto 1 anno).
@export var initial_cubs: int = 2

@export_group("Initial aggression")
# Aggressività di partenza (0..100) per fascia, estratta a caso tra min e max per ogni animale.
@export var adult_aggression_min: float = 85.0
@export var adult_aggression_max: float = 100.0
@export var young_aggression_min: float = 70.0
@export var young_aggression_max: float = 90.0
@export var cub_aggression_min: float = 50.0
@export var cub_aggression_max: float = 70.0
