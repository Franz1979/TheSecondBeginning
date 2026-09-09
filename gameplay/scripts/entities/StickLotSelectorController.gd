class_name StickLotSelectorController
extends RefCounted

# Hit-test per il click sul "terreno" di una microcella TREE (2026-09-08, richiesta utente) — a
# differenza di StoneSelectorController/VegetationSelectorController non cerca l'oggetto puntuale
# più vicino: qui l'intera microcella (lotto) è il bersaglio, quindi basta risolvere in quale lotto
# è caduto il click e verificare che sia "rivendicato" da un albero
# (MacroCellState.tree_claimed_lots, stesso store letto da IndividualVegetationService) — nessuna
# soglia di distanza, nessuna competizione tra più candidati nella stessa cella (un click ricade
# sempre in ESATTAMENTE un lotto).
#
# Chiamato per il SINISTRO SOLO come ultima risorsa dal chiamante (GameScene._unhandled_input, dopo
# che vegetazione/edificio/corpo morto/stone/individuo umano hanno già avuto la loro occasione e
# hanno fallito) — non compete nella lista a priorità per distanza degli altri *SelectorController:
# è deliberatamente il fallback più debole, perché l'utente ha chiesto questo click "sul terreno"
# come alternativa al click preciso sulla pianta già esistente, non come sostituto.
#
# Click SINISTRO di default (selezione/ispezione), stessa convenzione di ogni altro
# *SelectorController — ma vedi required_button su try_select sotto (2026-09-09): GameScene lo
# richiama anche col DESTRO per il comando "vai e raccogli" (chiamata diretta, NON tramite la stessa
# corsia a priorità del sinistro sopra — sul destro non esiste competizione con la vegetazione, che
# non hit-testa mai eventi non-sinistri: il problema "il click seleziona l'albero invece del lotto"
# non si ripresenta affatto su questo percorso).

const CELL_SIZE: int = 10 # stesso fattore pixel/microcella di MicroCellRenderer


# Ritorna {"macro_coords": Vector2i, "lot": Vector2i} se il click è caduto dentro una microcella
# TREE di una delle celle vive, {} altrimenti. Il chiamante (GameScene) decide cosa fare col
# risultato — questo controller non tocca mai selected_stick_lot.
#
# required_button (2026-09-09, richiesta utente — split selezione/comando raccolta): default
# MOUSE_BUTTON_LEFT invariato per il chiamante di selezione esistente. GameScene lo richiama anche
# con MOUSE_BUTTON_RIGHT per il comando "vai e raccogli" (stesso hit-test, nessuna duplicazione) —
# stesso trattamento di StoneSelectorController.try_select, vedi lì per il razionale completo.
#
# `buildings` (2026-09-09, richiesta utente — bugfix: "costruisco un deposit_site su un ex bosco,
# il lotto resta cliccabile e mi dice quanti bastoni ci sono, il destro-click ci scatta pure il
# pickup invece dell'unload") — MacroCellState.tree_claimed_lots NON viene mai cancellato quando un
# edificio occupa quel lotto (BuildingSiteClearingService lo lascia apposta "noto", per un'eventuale
# demolizione futura — vedi lì), quindi il vecchio controllo su tree_claimed_lots da solo continuava
# a far scattare questo hit-test anche su un lotto ormai occupato da un edificio. Un lotto con un
# Building sopra (stessa macrocella, stesso micro_x/micro_y) non è più un lotto stick selezionabile,
# a prescindere da cosa dice tree_claimed_lots — default Array vuoto (nessun edificio) per i
# chiamanti che non ne hanno ancora accesso, comportamento invariato in quel caso.
func try_select(event: InputEvent, live_cells: Dictionary, required_button: int = MOUSE_BUTTON_LEFT, buildings: Array = []) -> Dictionary:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != required_button:
		return {}

	for coords in live_cells:
		var cell: LiveMacroCell = live_cells[coords]
		if cell.renderer == null or cell.macro_state == null:
			continue

		var local_mouse: Vector2 = cell.renderer.get_local_mouse_position()
		var click_lot := Vector2i(int(floor(local_mouse.x / CELL_SIZE)), int(floor(local_mouse.y / CELL_SIZE)))

		if not cell.macro_state.tree_claimed_lots.has(click_lot):
			continue
		if _is_occupied_by_building(buildings, coords, click_lot):
			continue
		return {"macro_coords": coords, "lot": click_lot}

	return {}


static func _is_occupied_by_building(buildings: Array, macro_coords: Vector2i, lot: Vector2i) -> bool:
	for building in buildings:
		if building.macro_x == macro_coords.x and building.macro_y == macro_coords.y \
				and building.micro_x == lot.x and building.micro_y == lot.y:
			return true
	return false
