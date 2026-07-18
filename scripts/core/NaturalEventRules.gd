class_name NaturalEventRules
extends Resource

@export var event_name: String = ""

@export_group("Trigger")
@export var base_probability_per_year: float = 0.1
# Se true, il centro dell'evento viene scelto solo tra celle con coast_type != NONE
# (adiacenti al mare) invece che a caso su tutta la mappa. Generico e riusabile da
# qualunque evento vincolato geograficamente, non solo dalle inondazioni marine.
@export var requires_coastal_center: bool = false

@export_group("Intensity")
@export var intensity_probability_weights: Array[float] = []
@export var radius_by_intensity: Array[int] = []
@export var cells_destroyed_by_intensity: Array[int] = []

@export_group("Succession Fragility")
@export var fragility_weight_by_succession_level: Array[float] = []

@export_group("Post-Event Recovery")
@export var post_event_growth_multiplier: float = 1.5
@export var post_event_growth_duration_years: int = 3

@export_group("Subtype Overrides")
# Predisposizione futura: split esplicito dei sottotipi da distruggere per questo evento,
# al posto della proporzione locale attuale usata di default. Vuoto = non usato (default di
# oggi); nessun servizio lo legge ancora.
@export var subtype_destruction_override: Dictionary = {}
