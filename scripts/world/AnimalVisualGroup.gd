class_name AnimalVisualGroup
extends RefCounted

# Stato per-sessione (mai persistito) di un singolo gruppo animale disegnato da
# AnimalGroupRenderer: posizione in coordinate microcella (float, stesso spazio 0..100 di
# World) e direzione di marcia normalizzata.
var position: Vector2
var direction: Vector2
# Indice nell'array _clusters di AnimalGroupRenderer verso cui questa istanza è attratta.
# Irrilevante quando l'istanza è usata essa stessa come centro-cluster invece che come gruppo
# disegnato (vedi AnimalGroupRenderer._resync_clusters), assegnato solo esternamente.
var cluster_index: int = 0

# Macchina a stati a due livelli per il movimento a balzi (vedi AnimalGroupRenderer). Rilevante
# solo per i gruppi disegnati, ignorata quando l'istanza è usata come centro-cluster (stesso
# trattamento di cluster_index sopra) — i centri-cluster vagano in modo continuo, non a balzi.
enum MacroPhase { MOVING, RESTING }
enum MicroPhase { HOPPING, HOP_PAUSE }
var macro_phase: MacroPhase = MacroPhase.MOVING
var macro_phase_timer: float = 0.0
var micro_phase: MicroPhase = MicroPhase.HOPPING
var micro_phase_timer: float = 0.0

func _init(_position: Vector2, _direction: Vector2) -> void:
	position = _position
	direction = _direction
