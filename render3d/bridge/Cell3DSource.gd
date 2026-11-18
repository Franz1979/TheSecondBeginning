class_name Cell3DSource
extends RefCounted

# Dati di UNA macrocella accesa, già estratti dal gioco da GameStateReader: è tutto ciò che gli oggetti 3D ricevono.
# Nessun oggetto 3D legge GameScene o LiveMacroCell direttamente.

var coords: Vector2i
# Angolo in alto a sinistra della macrocella, in microcelle, rispetto alla macrocella centrale (come i container 2D).
var origin: Vector2
# Micro-mondo 100x100 della cella (terreno e acqua per microcella).
var world: World
# Acqua della macrocella intera (SEA/LAKE = tutta acqua; RIVER = fascia di fiume sopra il terreno).
var water_type: GameTypes.WaterType = GameTypes.WaterType.NONE
# Microcelle del fiume (Array di Vector2i) e del ruscello (Vector2i -> true).
var river_positions: Array = []
var stream_positions: Dictionary = {}
# Tracciato morbido del ruscello, lo stesso che disegna il 2D (StreamMicrocellService.get_layout): "paths" (linee
# centrali in microcelle), "widenings", "pond_center".
var stream_layout: Dictionary = {}
# Microcelle del giacimento d'argilla (Vector2i -> true), le stesse del 2D.
var clay_positions: Dictionary = {}
