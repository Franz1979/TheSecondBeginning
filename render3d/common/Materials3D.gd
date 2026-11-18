class_name Materials3D
extends RefCounted

# I materiali condivisi della vista 3D, creati una volta e passati a tutte le celle: pochi materiali = pochi cambi di
# stato per la scheda video.

var vertex_color: StandardMaterial3D = FlatMeshBuilder.vertex_color_material()
var water: StandardMaterial3D = WaterMesh3D.make_material()
var grid: StandardMaterial3D = GridLines3D.make_material()
