class_name GroundPatchSnapshot3D
extends RefCounted

# Risorse dei lotti "chiazza d'erba" (GRASS_PATCH: verdure selvatiche, erbe medicinali, granaglie, lino) di UNA
# macrocella, come le disegna il 2D (MicroCellRenderer.grass_patch_availability: lotti con disponibilità > 0, già
# filtrati dal chiamante). Il punto è quello della figurina del 2D, spostamento compreso (_lot_marker_offset), calcolato
# dal 2D stesso. Uova: dal 2026-11-21 anche loro (MicroCellRenderer.egg_nest_availability), resource = "eggs".

# Una voce per figurina: {"resource": String, "lot": Vector2i, "pos": Vector2 (microcelle, locali alla cella)}.
# Granaglie: una voce per granaglia del lotto, resource = "grains", "grain" = il suo nome (il colore), "cluster" = [posto,
# quante] (tutte nello stesso punto: GroundPlants3D le apre a ciuffetto).
var items: Array = []
