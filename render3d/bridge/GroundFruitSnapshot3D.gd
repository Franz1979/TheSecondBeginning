class_name GroundFruitSnapshot3D
extends RefCounted

# Frutti caduti a terra di UNA macrocella (2026-11-21): risorsa ("acorn", in futuro "fruit") -> {lotto Vector2i: quota}.
# La quota è quanto resta sul lotto rispetto alla capacità piena dell'anno (disponibile / capacità senza stagione), quindi
# segue già la stagione della risorsa (ghiande: autunno 1, inverno 0,5, primavera 0,3, estate 0) e la raccolta.
# Solo i lotti con un albero in vista (niente frutti sotto la nebbia). Quanti mucchietti e dove lo decide GroundFruit3D.
var fractions_by_resource: Dictionary = {}
