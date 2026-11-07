class_name BirdPresenceRules
extends Resource

# Numeri della presenza degli uccelli (2026-11-07, BirdPresenceService). Gli uccelli non sono una popolazione salvata:
# la presenza si calcola sul posto dalle piante attorno, dal bioma e dalla stagione.

@export_group("Woody Cover")
# Raggio (in microcelle, quadrato) in cui si contano alberi e arbusti attorno alla microcella.
@export var cover_radius: int = 3
# Quota di microcelle con alberi/arbusti oltre la quale la copertura vale già il massimo.
@export var full_cover_ratio: float = 0.4

@export_group("Multipliers")
# Chiavi GameTypes.Biome; un bioma assente vale 1.
@export var multiplier_by_biome: Dictionary = {}
# Chiavi GameTypes.Season; una stagione assente vale 1.
@export var multiplier_by_season: Dictionary = {}

@export_group("Levels")
# Sotto few_threshold: nessuno; poi pochi; da some_threshold: parecchi; da many_threshold: molti.
@export var few_threshold: float = 0.10
@export var some_threshold: float = 0.35
@export var many_threshold: float = 0.65
