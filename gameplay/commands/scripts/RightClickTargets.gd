class_name RightClickTargets
extends RefCounted

# Cosa c'è sotto un clic destro di comando (2026-10-24, refactoring GameScene 5B.7): raccolto una volta dalla scena
# (GameScene._collect_right_click_targets, hit-test del renderer 2D), letto da RightClickCommandService per scegliere i
# comandi. Una versione 3D riempie gli stessi campi con il suo hit-test.

# Corpo sotto la sagoma (DeadBodySelectorController.find_body_at_silhouette), -1 = nessuno.
var body_id: int = -1
# Animale vivo colpito e la sua specie; null = nessuno.
var prey: AnimalVisualGroup = null
var prey_species: String = ""
# Mucchio a terra con una carcassa vicino al mouse; null = nessuno.
var carcass_pile: GroundPile = null
# Pianta viva più vicina al mouse ({"macro_coords", "object_type", "individual_key"}), {} = nessuna.
var plant: Dictionary = {}
# Roccia colpita ({"macro_coords", "position", ...}), {} = nessuna.
var rock: Dictionary = {}
# Candidati della raccolta nel punto (GameScene._resolve_pickup_candidates), già filtrati dalla nebbia.
var pickup_candidates: Array[Dictionary] = []
# Edificio colpito; null = nessuno.
var building: Building = null
