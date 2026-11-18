class_name GroundCoverSnapshot3D
extends RefCounted

# Cosa copre il suolo di una cella, come lo disegna il 2D (elenchi filtrati dalla nebbia come nel 2D), per GroundCover3D.

# Microcelle con la risorsa erba (Vector2i).
var grass: Array = []
# Lotti con alberi (Vector3i: x, y del lotto + indice dell'individuo).
var trees: Array = []
# Lotti con cespugli (Vector3i, come sopra).
var shrubs: Array = []
# Microcelle con una roccia non esaurita (Vector2i).
var rocks: Array = []
