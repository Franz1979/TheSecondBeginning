class_name AnimalVisualGroup
extends RefCounted

# Stato per-sessione (mai persistito) di un singolo individuo animale disegnato da
# AnimalGroupRenderer (individui animali step 1: un'istanza = un animale reale della quota di
# questa cella, non più un'icona che ne rappresenta visual_group_size): posizione in coordinate
# microcella (float, stesso spazio 0..100 di World) e direzione di marcia normalizzata.
#
# id: progressivo, assegnato UNA volta alla generazione (AnimalGroupRenderer._make_individual) e
# mai riassegnato — la riconciliazione con la popolazione rimuove per id, non per indice
# nell'array. 0 = nessuna identità: istanza usata come centro-cluster invisibile (vedi
# _make_random_group), mai un individuo. Non persistito: alla disattivazione della cella gli
# individui vengono scartati e alla riattivazione ne nascono di nuovi con id nuovi.
var id: int = 0
var species_name: String = ""
var position: Vector2
var direction: Vector2
# Indice nell'array _clusters di AnimalGroupRenderer verso cui questo individuo è attratto.
# Assegnato UNA volta alla nascita (AnimalGroupRenderer._make_individual) e poi fisso: cambia solo
# se quel centro viene rimosso (_reassign_orphaned_individuals). -1 = non ancora assegnato
# (individuo appena ricostruito da un salvataggio). Irrilevante quando l'istanza è usata essa
# stessa come centro-cluster, assegnato solo esternamente.
var cluster_index: int = 0
# Fascia d'età di QUESTO individuo (assegnata da AnimalGroupRenderer.
# set_population_by_age, o sempre ADULT per il fallback set_population non age-aware) — determina
# la scala visiva applicata in _write_instance_transform (AnimalRules.size_multiplier_by_age).
# Irrilevante quando l'istanza è usata come centro-cluster (mai disegnata, stesso trattamento di
# cluster_index sopra).
var age_band: GameTypes.AgeBand = GameTypes.AgeBand.ADULT

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
