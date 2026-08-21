class_name FireEventRules
extends NaturalEventRules

@export_group("Fire Spread")
@export var flammability_threshold: float = 0.0
@export var spread_probability_to_neighbors: float = 0.4
@export var max_spread_iterations: int = 4
