class_name NaturalEventRules
extends Resource

@export var event_name: String = ""

@export_group("Trigger")
@export var base_probability_per_year: float = 0.1

@export_group("Intensity")
@export var intensity_probability_weights: Array[float] = []
@export var radius_by_intensity: Array[int] = []
@export var cells_destroyed_by_intensity: Array[int] = []

@export_group("Succession Fragility")
@export var fragility_weight_by_succession_level: Array[float] = []

@export_group("Post-Event Recovery")
@export var post_event_growth_multiplier: float = 1.5
@export var post_event_growth_duration_years: int = 3
