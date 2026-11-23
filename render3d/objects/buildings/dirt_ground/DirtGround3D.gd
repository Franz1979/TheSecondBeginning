class_name DirtGround3D
extends RefCounted

# Oggetto 3D: le mattonelle dell'edificio "Terra battuta" di UNA macrocella (DirtGroundSnapshot3D), come maschera letta
# dallo shader del terreno (terrain.gdshader, beaten_mask): un pixel per microcella, 255 dove c'è terra battuta. Lo
# shader ci mette la terra marrone scura (2026-11-21; la terra chiara e più liscia resta sotto gli altri edifici), col bordo sfumato e mosso come gli
# altri suoli (richiesta utente: deve sembrare terra, non un tappeto né una strada). Le mattonelle vicine si fondono da
# sole in una macchia unica. In cantiere il valore segue il lavoro fatto: la terra battuta compare a chiazze che si
# allargano (lo shader taglia la maschera col rumore del bordo), piena a lavoro finito.

static func build_image(snapshot: DirtGroundSnapshot3D) -> Image:
	var size := World.WIDTH
	# Tre canali: R = quanto è battuta, G = quanto è più scura (sito di deposito), B = mattonella dell'edificio "Terra
	# battuta" (marrone scuro; senza = terra chiara sotto un altro edificio).
	var bytes := PackedByteArray()
	bytes.resize(size * size * 3)
	for i in range(snapshot.size()):
		var pos := snapshot.positions[i]
		if pos.x < 0 or pos.y < 0 or pos.x >= size or pos.y >= size:
			continue
		var index := (pos.y * size + pos.x) * 3
		bytes[index] = maxi(bytes[index], int(round(255.0 * clampf(snapshot.strengths[i], 0.0, 1.0))))
		var shade: float = snapshot.shades[i] if i < snapshot.shades.size() else 0.0
		bytes[index + 1] = maxi(bytes[index + 1], int(round(255.0 * clampf(shade, 0.0, 1.0))))
		if i < snapshot.tiles.size() and snapshot.tiles[i] > 0:
			bytes[index + 2] = 255
	return Image.create_from_data(size, size, false, Image.FORMAT_RGB8, bytes)
