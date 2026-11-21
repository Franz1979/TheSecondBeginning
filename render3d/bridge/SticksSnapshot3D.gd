class_name SticksSnapshot3D
extends RefCounted

# Bastoni a terra di UNA macrocella, come li riceve il 2D (MicroCellRenderer.stick_availability): lotto d'albero ->
# quantità disponibile, già netta del raccolto e filtrata dal chiamante. Quanti e dove li decide Sticks3D con la regola
# del 2D.
var quantities: Dictionary = {}
