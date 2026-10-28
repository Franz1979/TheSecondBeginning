class_name WildAnimalGroupRules
extends Resource

# Regole di un gruppo di animali selvatici seguiti uno per uno (2026-10-26, richiesta utente): un file per specie in
# gameplay/wild_animals/data/groups/{species}_group.tres. Fasce d'età e stagione delle nascite prese dalla specie
# selvatica (AnimalRules di wild_species_name), qui composizione iniziale, aggressività e crescita del gruppo.

# Specie selvatica (simulation/data/animals/), per le fasce d'età, la stagione delle nascite e il nome mostrato.
@export var wild_species_name: String = ""

@export_group("Initial composition")
# Coppia adulta (un maschio e una femmina) più gli altri adulti oltre la coppia.
@export var initial_breeding_pair: bool = true
@export var initial_extra_adults: int = 0
# Giovani nati negli anni precedenti (età tra 1 anno e la fine della giovinezza).
@export var initial_young: int = 2
# Cuccioli dell'anno (età sotto 1 anno).
@export var initial_cubs: int = 2

@export_group("Aggression")
# Aggressività (0..100) dei membri iniziali e degli adulti che arrivano da fuori. I nati nel gruppo partono invece
# dalla media dei due riproduttori (2026-10-27, richiesta utente).
@export var initial_aggression: float = 100.0

@export_group("Growth")
# Cuccioli per anno, il primo giorno della stagione delle nascite della specie, se la coppia è adulta o vecchia.
@export var litter_min: int = 1
@export var litter_max: int = 3
# Oltre questo numero se ne vanno i giovani più grandi (dispersione semplificata).
@export var max_group_size: int = 12
