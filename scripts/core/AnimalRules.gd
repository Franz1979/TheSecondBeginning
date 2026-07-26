class_name AnimalRules
extends Resource

@export var species_name: String = ""
@export var daily_caloric_requirement: float = 0.0
# resource_name (chiave di CaloricSourceRules.caloric_source_name) -> moltiplicatore di
# edibilità. Oggi conta solo la PRESENZA della chiave (il coniglio mangia solo "forage", con
# moltiplicatore 1.0 di fatto ignorato): la logica multi-risorsa con moltiplicatori diversi per
# specie non è ancora implementata, arriverà quando servirà davvero più di una fonte per specie.
@export var diet_compatibility: Dictionary = {}

@export_group("Visualization")
# Quanti individui rappresenta una singola icona/gruppo nella resa visiva animata (vedi
# AnimalGroupRenderer). Default 1 = rappresentazione 1:1, per compatibilità con specie che
# non lo impostano esplicitamente nel proprio .tres.
@export var visual_group_size: int = 1
# Quanti individui al massimo per cluster (branco visivo di gruppi vicini tra loro, vedi
# AnimalGroupRenderer). Default 1 fa collassare il numero di cluster al numero di gruppi
# (un cluster per gruppo), disattivando di fatto l'effetto per le specie che non lo impostano
# esplicitamente — stesso pattern "default = no-op" di visual_group_size sopra.
@export var max_individuals_per_cluster: int = 1
# Movimento a balzi dei gruppi (vedi AnimalGroupRenderer): un balzo (hop_duration) alterna a
# una breve pausa (hop_pause) durante la fase "movimento" (movement_phase_duration); a quella
# segue una sosta lunga (rest_phase_duration) prima del prossimo movimento. Ogni durata è
# pescata a caso nel proprio range min/max a ogni transizione, indipendentemente per gruppo.
@export var hop_duration_min: float = 0.2
@export var hop_duration_max: float = 0.4
@export var hop_pause_min: float = 0.1
@export var hop_pause_max: float = 0.3
@export var movement_phase_duration_min: float = 2.0
@export var movement_phase_duration_max: float = 5.0
@export var rest_phase_duration_min: float = 3.0
@export var rest_phase_duration_max: float = 7.0
# Velocità durante un singolo balzo (microcelle/secondo) — sostituisce move_speed per il
# movimento dei gruppi disegnati; move_speed resta usato solo per il vagare continuo dei
# centri-cluster invisibili (vedi AnimalGroupRenderer).
@export var hop_speed: float = 6.0
