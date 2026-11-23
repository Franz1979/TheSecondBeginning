class_name GrassSnapshot3D
extends RefCounted

# Erba-risorsa di UNA macrocella, come la disegna il 2D (MicroCellRenderer.vegetation_positions GRASS, già filtrata come
# nel 2D) e la stagione corrente del 2D (per il colore dei ciuffi, come GRASS_PALETTE_BY_SEASON). Per GrassTufts3D.

# Microcelle con l'erba (Vector2i).
var positions: Array = []
var season: GameTypes.Season = GameTypes.Season.SUMMER
