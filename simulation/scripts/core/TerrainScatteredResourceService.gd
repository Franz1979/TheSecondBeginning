class_name TerrainScatteredResourceService
extends RefCounted

# Interfaccia uniforme per i pool di risorse GenerationSource.TERRAIN_SCATTERED (vedi
# SecondaryResourceTypes — sparse sul terreno stesso, non derivate da una risorsa primaria via
# CaloricCalculator.SECONDARY_SOURCES) — 2026-09-09, richiesta utente. Nata per togliere a
# PickUpAction l'accesso diretto a MacroCellState.pebble_quantities/stick_quantities: il chiamante
# passa solo resource_name, questo service smista internamente sul Dictionary/formato giusto.
# Aggiungere una terza risorsa scattered (es. un futuro "clay") richiede solo un nuovo case in
# get_available/consume qui, nessuna modifica a PickUpAction.
#
# game_data per il confronto di freschezza lotto stick (sotto) è risolto da GameSettings.
# active_game_data — non un parametro esplicito, per lasciare invariata la firma richiesta
# (get_available/consume prendono solo macro_state/resource_name/position, stessa firma con cui
# PickUpAction già li chiama oggi) e per non allungare la catena di parametri di PickUpAction
# (che oggi non riceve/non tiene game_data — vedi PickUpAction._init) solo per questo. Stessa
# fonte già letta da WorldScene/GameScene/MacroCellScene per lo stato "attivo" di sessione — qui è
# il solo consumatore che la legge da dentro un service invece che da uno script di scena.


static func get_available(macro_state: MacroCellState, resource_name: String, position: Vector2i) -> int:
	if is_resource_locked(resource_name):
		return 0
	match resource_name:
		"pebble":
			return int(macro_state.pebble_quantities.get(position, 0))
		"stick":
			return _get_available_stick(macro_state, position)
		"plant_fiber":
			return _get_available_plant_fiber(macro_state, position)
		"mushroom":
			return _get_available_mushroom(macro_state, position)
		_:
			if FRUIT_STOCK_SOURCES.has(resource_name):
				return get_fruit_stock_available_at(resource_name, macro_state, position)
			return 0


static func consume(macro_state: MacroCellState, resource_name: String, position: Vector2i, quantity: int) -> void:
	if quantity <= 0:
		return
	match resource_name:
		"pebble":
			_consume_pebble(macro_state, position, quantity)
		"stick":
			_consume_stick(macro_state, position, quantity)
		"plant_fiber":
			_consume_plant_fiber(macro_state, position, quantity)
		"mushroom":
			_consume_mushroom(macro_state, position, quantity)
		_:
			if FRUIT_STOCK_SOURCES.has(resource_name):
				consume_fruit_stock_at(resource_name, macro_state, position, quantity)


# Gate unico "questa risorsa è raccoglibile dagli umani ORA?" (2026-09-17, richiesta utente —
# SecondaryResourceRules.required_idea_id, stesso significato di BuildingRules.required_idea_id).
# Consultato da get_available sopra (che copre TUTTI i percorsi di raccolta, incluso il tasto di
# debug _debug_test_haul_resource_task) e da GameScene._resolve_pickup_candidates (popup di scelta
# al tasto destro + ispezione microcella al doppio click sinistro, stessa fonte condivisa). MAI
# consultato da consume/dal rendering (MicroCellRenderer continua a disegnare i puntini come sempre,
# richiesta esplicita utente) né da AnimalConsumptionService (percorso separato, mai toccato).
# resource_rules == null (nome non risolvibile) o required_idea_id == "" (nessun requisito) ->
# false, mai bloccata per un motivo diverso da un'idea mancante. GameSettings.active_human_folk
# assente (nessuna partita/folk attiva) -> true (bloccata): un requisito impostato non può mai
# risultare "soddisfatto" senza un Folk reale da interrogare.
static func is_resource_locked(resource_name: String) -> bool:
	var resource_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if resource_rules == null or resource_rules.required_idea_id == "":
		return false
	var folk := GameSettings.active_human_folk
	return folk == null or not folk.completed_ideas.has(resource_rules.required_idea_id)


# Lookup diretto, clamp a 0 — entry lasciata a 0 senza rimuoverla (stesso comportamento già in uso
# in PickUpAction.on_complete prima di questo refactor).
static func _consume_pebble(macro_state: MacroCellState, position: Vector2i, quantity: int) -> void:
	var remaining: int = int(macro_state.pebble_quantities.get(position, 0)) - quantity
	macro_state.pebble_quantities[position] = max(remaining, 0)


# Lotto stale (mai ridisegnato dall'ultimo checkpoint growth passato — vedi
# StickPoolService.most_recent_growth_checkpoint_absolute_day) → 0: senza un refresh recente la
# capacità persistita non è affidabile, stesso confronto già usato da
# StickPoolService.refresh_macrocell per decidere se un lotto va rigenerato.
static func _get_available_stick(macro_state: MacroCellState, position: Vector2i) -> int:
	var entry: Dictionary = macro_state.stick_quantities.get(position, {})
	if entry.is_empty():
		return 0
	if GameSettings.active_game_data == null:
		return 0 # GameScene può girare con un game_data locale di riserva senza mai valorizzare
		# GameSettings.active_game_data (vedi GameScene._ready) — fail-closed invece di un crash null.
	var checkpoint_absolute_day := StickPoolService.most_recent_growth_checkpoint_absolute_day(GameSettings.active_game_data)
	if int(entry.get("checkpoint_day", -1)) != checkpoint_absolute_day:
		return 0
	var capacity := int(entry.get("capacity", 0))
	var harvested := int(entry.get("harvested", 0))
	return max(capacity - harvested, 0)


# Incrementa harvested, clampato a non superare capacity — nessun controllo di freschezza qui
# (a differenza di get_available sopra): se il lotto è nel frattempo diventato stale, capacity/
# harvested persistiti sono comunque quelli dell'ultima generazione nota, e limitare consume a
# quell'ultima capacity nota resta corretto (mai un harvested > capacity, qualunque sia l'epoch).
static func _consume_stick(macro_state: MacroCellState, position: Vector2i, quantity: int) -> void:
	var entry: Dictionary = macro_state.stick_quantities.get(position, {})
	if entry.is_empty():
		return
	var capacity := int(entry.get("capacity", 0))
	var harvested := int(entry.get("harvested", 0))
	entry["harvested"] = min(harvested + quantity, capacity)
	macro_state.stick_quantities[position] = entry


# Mirror esatto di _get_available_stick/_consume_stick sopra, per plant_fiber (2026-09-16,
# richiesta utente) — STESSO checkpoint growth (VegetationPoolService.most_recent_growth_
# checkpoint_absolute_day, comune a TREE/SHRUB, verificato), STESSA formula di freschezza/clamp.
static func _get_available_plant_fiber(macro_state: MacroCellState, position: Vector2i) -> int:
	var entry: Dictionary = macro_state.plant_fiber_quantities.get(position, {})
	if entry.is_empty():
		return 0
	if GameSettings.active_game_data == null:
		return 0
	var checkpoint_absolute_day := VegetationPoolService.most_recent_growth_checkpoint_absolute_day(GameSettings.active_game_data)
	if int(entry.get("checkpoint_day", -1)) != checkpoint_absolute_day:
		return 0
	var capacity := int(entry.get("capacity", 0))
	var harvested := int(entry.get("harvested", 0))
	return max(capacity - harvested, 0)


static func _consume_plant_fiber(macro_state: MacroCellState, position: Vector2i, quantity: int) -> void:
	var entry: Dictionary = macro_state.plant_fiber_quantities.get(position, {})
	if entry.is_empty():
		return
	var capacity := int(entry.get("capacity", 0))
	var harvested := int(entry.get("harvested", 0))
	entry["harvested"] = min(harvested + quantity, capacity)
	macro_state.plant_fiber_quantities[position] = entry


# Applica SecondaryResourceRules.seasonal_availability_multiplier (indicizzato per GameTypes.
# Season — WINTER/SPRING/SUMMER/AUTUMN, STESSO indice già usato dalla famiglia "fruit stock" sotto
# per lo stock aggregato) alla capacità GREZZA di un lotto — GENERICO per resource_name (2026-09-17,
# richiesta utente, BUGFIX: la prima versione aveva una tabella SEASONAL_TERRAIN_SCATTERED_SOURCES
# hardcoded qui nel codice, che duplicava/contraddiceva la curva già dichiarata nel .tres — il .tres
# resta l'UNICA fonte di verità per la stagionalità, qui la si legge soltanto). Un solo helper,
# usato oggi da _get_available_mushroom sotto, pensato per qualunque futura risorsa di questa
# famiglia (capacità propria per lotto, nessuno stock aggregato) CON una curva stagionale non-piatta
# nel proprio .tres, e per un eventuale rendering che debba mostrare la stessa proporzione — mai un
# secondo calcolo duplicato altrove.
#
# floor(capacity × moltiplicatore), mai round/ceil (stesso principio "mai frazionario" già seguito
# ovunque nel progetto per quantità raccoglibili). resource_rules == null (nome non risolvibile) o
# GameSettings.active_game_data assente (nessuna partita attiva, impossibile risolvere la stagione
# corrente) -> capacity invariata: fail-OPEN qui (a differenza del fail-closed di is_resource_locked
# sopra), perché l'assenza di un game_data non è un segnale "nascondi tutto", è semplicemente "non
# posso applicare il moltiplicatore" — un chiamante di solito ha già un proprio guard game_data a
# monte (vedi _get_available_mushroom sotto) che intercetta questo caso comunque.
static func _apply_seasonal_availability_to_capacity(resource_name: String, capacity: int) -> int:
	var resource_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if resource_rules == null or GameSettings.active_game_data == null:
		return capacity
	var current_season := SeasonCalculator.get_season_for_day(GameSettings.active_game_data.current_day)
	var multiplier: float = resource_rules.seasonal_availability_multiplier[current_season]
	return int(floor(float(capacity) * multiplier))


# Mirror esatto di _get_available_stick/_consume_stick sopra, per mushroom (2026-09-17, richiesta
# utente) — STESSO checkpoint growth (VegetationPoolService.most_recent_growth_checkpoint_
# absolute_day, comune a TREE/SHRUB), STESSA formula di freschezza/clamp, PIÙ il moltiplicatore
# stagionale (_apply_seasonal_availability_to_capacity sopra, letto da mushroom.tres —
# [0.4, 0.0, 0.3, 1.0]: quasi nullo in primavera, pieno in autunno) applicato alla capacità PRIMA
# di sottrarre harvested — un lotto con capacity=10 e harvested=0 mostra quindi disponibilità reale
# 0 in primavera, 3 in estate, 10 in autunno, 4 in inverno.
static func _get_available_mushroom(macro_state: MacroCellState, position: Vector2i) -> int:
	var entry: Dictionary = macro_state.mushroom_quantities.get(position, {})
	if entry.is_empty():
		return 0
	if GameSettings.active_game_data == null:
		return 0
	var checkpoint_absolute_day := VegetationPoolService.most_recent_growth_checkpoint_absolute_day(GameSettings.active_game_data)
	if int(entry.get("checkpoint_day", -1)) != checkpoint_absolute_day:
		return 0
	var capacity := int(entry.get("capacity", 0))
	var harvested := int(entry.get("harvested", 0))
	var seasonal_capacity := _apply_seasonal_availability_to_capacity("mushroom", capacity)
	return max(seasonal_capacity - harvested, 0)


# Nessun moltiplicatore stagionale qui (a differenza di _get_available_mushroom sopra) — STESSO
# principio di _consume_stick/_consume_plant_fiber: capacity/harvested persistiti restano quelli
# GREZZI (pre-moltiplicatore) dell'ultima generazione nota, get_available già garantisce che questa
# funzione non venga mai chiamata con quantity superiore alla disponibilità REALE già scontata
# della stagione (PickUpAction risolve _quantity_to_collect da get_available), quindi un secondo
# calcolo qui sarebbe ridondante — clampare harvested alla capacity grezza (non a quella scontata)
# resta corretto: capacity grezza è il tetto vero anche quando il moltiplicatore stagionale nasconde
# temporaneamente parte del raccolto.
static func _consume_mushroom(macro_state: MacroCellState, position: Vector2i, quantity: int) -> void:
	var entry: Dictionary = macro_state.mushroom_quantities.get(position, {})
	if entry.is_empty():
		return
	var capacity := int(entry.get("capacity", 0))
	var harvested := int(entry.get("harvested", 0))
	entry["harvested"] = min(harvested + quantity, capacity)
	macro_state.mushroom_quantities[position] = entry


# "Fruit stock" (2026-09-17, richiesta utente — GENERALIZZATO dal precedente codice specifico di
# berry, in preparazione di fruit/acorn: NESSUN cambio di comportamento per berry) — famiglia di
# risorse secondarie a stock aggregato (consuming_depletes_primary = false) ripartite tra i lotti
# TREE/SHRUB di un dato sottotipo a frutto, DELIBERATAMENTE senza un pool per-lotto persistente
# come stick/plant_fiber sopra: secondary_resource_stock[resource_name] (MacroCellState,
# alimentato/consumato ogni stagione da CaloricCalculator.update_secondary_resource_stock e ogni
# giorno dal consumo animale, vedi AnimalConsumptionService) resta l'UNICA fonte di verità,
# condivisa tra umani e fauna — è esattamente il punto: se esistesse un secondo contatore per lotto
# (tipo *_quantities), andrebbe tenuto sincrono a mano con lo stock ogni volta che l'uno o l'altro
# consumatore agisce, rischiando un drift silenzioso tra "quanto pensa di avere il lotto" e "quanto
# ne resta davvero in cella" — a differenza di stick/plant_fiber che non hanno un consumatore
# concorrente. La disponibilità per lotto è quindi sempre: floor(stock_cella × peso_lotto /
# peso_totale_cella), dove il peso è la somma degli individui (object_type, subtype_name) del
# lotto pesati per fascia d'età con gli stessi coefficienti di CaloricCalculator
# (SubtypeRules.production_coefficient_young/adult/old — mai un letterale hardcoded, per restare
# sempre coerente con la stessa formula che alimenta lo stock).
#
# TABELLA UNICA resource_name -> (object_type, subtype_name): aggiungere una risorsa a questa
# catena significa aggiungere UNA riga qui, nessun altro codice in questo file cambia. "acorn"
# (2026-09-17, richiesta utente — TREE/wild_fruit, seconda voce dopo berry, prova della
# generalizzazione) aggiunta qui; "fruit" (2026-09-17, richiesta utente — TREE/domesticable_fruit,
# terza voce, stessa catena) aggiunta subito dopo, stessa identica meccanica delle prime due.
const FRUIT_STOCK_SOURCES := {
	"berry": {"object_type": GameTypes.WorldObjectType.SHRUB, "subtype_name": "fruit_bearing"},
	"acorn": {"object_type": GameTypes.WorldObjectType.TREE, "subtype_name": "wild_fruit"},
	"fruit": {"object_type": GameTypes.WorldObjectType.TREE, "subtype_name": "domesticable_fruit"},
}


# Dispatch TREE/SHRUB sui registri per-individuo di MacroCellState — STESSO identico pattern
# (duplicato deliberatamente, non riusato) di VegetationPoolService._subtype_store/_birth_year_
# store e di IndividualVegetationService._subtype_store/_birth_year_store: quei due sono proprietà
# delle rispettive classi, non un'utility condivisa — stesso principio "nessuna classe condivisa
# tra usi diversi" già seguito ovunque nel progetto.
static func _individual_subtype_store(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType) -> Dictionary:
	return macro_state.tree_individual_subtype if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_individual_subtype


static func _individual_birth_year_store(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType) -> Dictionary:
	return macro_state.tree_virtual_birth_year if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_virtual_birth_year


# Dettaglio completo del calcolo NOMINALE (prima di sottrarre il raccolto) per il lotto —
# {"stock": float, "total_weight": float, "lot_weight": float, "nominal": int}, condiviso da
# get_fruit_stock_available_at/get_fruit_stock_visual_ratio_at (così le due query restano sempre
# coerenti sulla stessa base di calcolo) E dal log diagnostico di get_fruit_stock_available_at
# sotto, che altrimenti dovrebbe duplicare la stessa formula solo per poterla loggare.
static func _get_fruit_stock_nominal_breakdown(resource_name: String, macro_state: MacroCellState, position: Vector2i) -> Dictionary:
	var stock: float = macro_state.get_secondary_resource_stock(resource_name)
	var weights := _get_fruit_stock_weights(resource_name, macro_state)
	var total_weight: float = float(weights["total"])
	var lot_weight: float = float(weights["by_lot"].get(position, 0.0))
	var nominal: int = 0
	if stock > 0.0 and total_weight > 0.0 and lot_weight > 0.0:
		nominal = int(floor(stock * lot_weight / total_weight))
	return {"stock": stock, "total_weight": total_weight, "lot_weight": lot_weight, "nominal": nominal}


# Disponibilità REALE del lotto: quota nominale meno quanto già raccolto DA UMANI in questo lotto
# quest'anno per QUESTA risorsa (2026-09-17, richiesta utente — bugfix: prima non sottraeva nulla,
# quindi svuotare un lotto per intero non lo svuotava mai davvero, vedi MacroCellState.
# berry_harvested_by_lot).
#
# [FRUIT STOCK AVAILABLE] (2026-09-17, richiesta utente) — diagnostica TEMPORANEA dietro
# DebugLogging.SHOW_BERRY_HARVEST_LOGS (default false): resource_name/stock aggregato/peso lotto/
# peso totale/nominale/raccolto/disponibile per il lotto interrogato, per verificare a mano la
# ripartizione durante il bugfix di coerenza raccolta-microcella.
static func get_fruit_stock_available_at(resource_name: String, macro_state: MacroCellState, position: Vector2i) -> int:
	var breakdown := _get_fruit_stock_nominal_breakdown(resource_name, macro_state, position)
	var nominal: int = int(breakdown["nominal"])
	var harvested: int = int(macro_state.berry_harvested_by_lot.get(resource_name, {}).get(position, 0))
	var available: int = max(nominal - harvested, 0)
	if DebugLogging.ENABLED and DebugLogging.SHOW_BERRY_HARVEST_LOGS:
		print("[FRUIT STOCK AVAILABLE] risorsa=%s lotto=%s stock=%.2f peso_lotto=%.3f peso_totale=%.3f nominale=%d raccolto=%d disponibile=%d" % [
			resource_name, position, float(breakdown["stock"]), float(breakdown["lot_weight"]), float(breakdown["total_weight"]),
			nominal, harvested, available
		])
	return available


# Frazione [0.0, 1.0] di quanto RESTA del lotto rispetto alla sua quota nominale piena — usata SOLO
# dal rendering (MicroCellRenderer, vedi GameScene._refresh_resource_visuals) per decidere su quanti
# individui di questo lotto ancora mostrare il frutto, MAI dalla simulazione/raccolta (quelle usano
# sempre get_fruit_stock_available_at, l'unità intera reale). nominal <= 0 -> 0.0 (nessuna base su
# cui calcolare una frazione, coincide comunque con "niente da mostrare").
static func get_fruit_stock_visual_ratio_at(resource_name: String, macro_state: MacroCellState, position: Vector2i) -> float:
	var nominal: int = int(_get_fruit_stock_nominal_breakdown(resource_name, macro_state, position)["nominal"])
	if nominal <= 0:
		return 0.0
	var harvested: int = int(macro_state.berry_harvested_by_lot.get(resource_name, {}).get(position, 0))
	return float(max(nominal - harvested, 0)) / float(nominal)


# Scala l'aggregato (richiesta esplicita utente — "è il punto in cui la raccolta umana toglie cibo
# agli animali") E incrementa berry_harvested_by_lot[resource_name][position] (2026-09-17 —
# bugfix, vedi il commento su quel campo in MacroCellState): a differenza di _consume_stick/
# _consume_plant_fiber sopra, qui SERVONO entrambe le scritture — l'aggregato per la competizione
# con la fauna, il contatore per lotto per la coerenza locale (raccogliere tutto qui deve svuotare
# qui).
#
# [FRUIT STOCK CONSUME] (2026-09-17, richiesta utente) — stessa diagnostica temporanea di
# get_fruit_stock_available_at sopra, stesso flag: resource_name/stock prima-dopo/nuovo
# berry_harvested_by_lot per il lotto. Letto DOPO set_secondary_resource_stock (non prima-quantity
# a mano) per mostrare il valore EFFETTIVO già clampato a 0 da MacroCellState.
# set_secondary_resource_stock, mai un valore teorico che potrebbe differire se quantity superasse
# lo stock residuo.
static func consume_fruit_stock_at(resource_name: String, macro_state: MacroCellState, position: Vector2i, quantity: int) -> void:
	var stock_before: float = macro_state.get_secondary_resource_stock(resource_name)
	macro_state.set_secondary_resource_stock(resource_name, stock_before - float(quantity))
	var stock_after: float = macro_state.get_secondary_resource_stock(resource_name)

	var per_lot: Dictionary = macro_state.berry_harvested_by_lot.get(resource_name, {})
	var harvested_before: int = int(per_lot.get(position, 0))
	var harvested_after: int = harvested_before + quantity
	per_lot[position] = harvested_after
	macro_state.berry_harvested_by_lot[resource_name] = per_lot

	# Vedi MacroCellState.berry_harvested_revision: incrementato ad OGNI mutazione reale del
	# berry_harvested_by_lot DI QUESTA RISORSA (qui e nell'azzeramento stagionale in
	# WorldTimeService), così GameScene._refresh_resource_visuals può accorgersi che questo lotto è
	# cambiato senza confrontare l'intero Dictionary — vedi get_fruit_stock_recompute_signature
	# sotto.
	var revision: int = int(macro_state.berry_harvested_revision.get(resource_name, 0))
	macro_state.berry_harvested_revision[resource_name] = revision + 1

	if DebugLogging.ENABLED and DebugLogging.SHOW_BERRY_HARVEST_LOGS:
		print("[FRUIT STOCK CONSUME] risorsa=%s lotto=%s quantita=%d stock %.2f->%.2f berry_harvested_by_lot=%d" % [
			resource_name, position, quantity, stock_before, stock_after, harvested_after
		])


# Peso totale/per-lotto degli individui (object_type, subtype_name) di questa risorsa in questa
# cella, in cache (MacroCellState.berry_weight_cache[resource_name]) finché checkpoint vegetativo e
# resource_quantity[object_type] non cambiano — vedi il commento su quel campo per il perché di
# questa firma di validità in due parti (checkpoint per la crescita annuale, resource_quantity per
# qualunque cambio di composizione FUORI da un checkpoint, es. un taglio). GameSettings.
# active_game_data assente (GameScene può girare con un game_data locale di riserva, vedi
# _get_available_stick sopra) -> {} fail-closed, mai un ricalcolo/una cache basata su un anno
# inventato.
static func _get_fruit_stock_weights(resource_name: String, macro_state: MacroCellState) -> Dictionary:
	if GameSettings.active_game_data == null:
		return {"total": 0.0, "by_lot": {}}

	var source: Dictionary = FRUIT_STOCK_SOURCES[resource_name]
	var object_type: GameTypes.WorldObjectType = source["object_type"]

	var checkpoint_absolute_day := VegetationPoolService.most_recent_growth_checkpoint_absolute_day(GameSettings.active_game_data)
	var primary_resource_quantity: int = macro_state.get_resource_quantity(object_type)

	var cache: Dictionary = macro_state.berry_weight_cache.get(resource_name, {})
	if not cache.is_empty() \
			and int(cache.get("checkpoint_day", -1)) == checkpoint_absolute_day \
			and int(cache.get("primary_resource_quantity", -1)) == primary_resource_quantity:
		return cache

	var weights := _compute_fruit_stock_weights(resource_name, macro_state, GameSettings.active_game_data.year)
	weights["checkpoint_day"] = checkpoint_absolute_day
	weights["primary_resource_quantity"] = primary_resource_quantity
	macro_state.berry_weight_cache[resource_name] = weights
	return weights


# Lotti con peso > 0 per questa risorsa (2026-09-17, richiesta utente — ottimizzazione: GameScene.
# _refresh_resource_visuals iterava TUTTI gli shrub_claimed_lots della macrocella, mai svuotato e
# quindi crescente per l'intera sessione, per calcolare un ratio che vale comunque 0 su ogni lotto
# senza il sottotipo giusto). Espone _get_fruit_stock_weights (cache-aware) SOLO nella parte
# "by_lot", già filtrata a peso > 0 da _compute_fruit_stock_weights (vedi sotto, `if weight <= 0.0:
# continue`) — il chiamante non deve ri-filtrare nulla, itera direttamente le chiavi di questo
# Dictionary.
static func get_fruit_stock_weight_lots(resource_name: String, macro_state: MacroCellState) -> Dictionary:
	return _get_fruit_stock_weights(resource_name, macro_state)["by_lot"]


# Firma leggera "è cambiato qualcosa che potrebbe aver alterato get_fruit_stock_visual_ratio_at per
# QUALUNQUE lotto di questa cella, per questa risorsa" (2026-09-17, richiesta utente) — i tre
# ingredienti richiesti: stock aggregato (cambia ogni consumo animale/umano, anche senza toccare la
# composizione TREE/SHRUB), checkpoint_day/primary_resource_quantity della cache pesi (cambia a
# ogni checkpoint vegetativo o taglio — vedi _get_fruit_stock_weights) e berry_harvested_revision
# (cambia a ogni raccolta/azzeramento stagionale — vedi MacroCellState). Confrontare questo Array a
# un valore salvato dal chiamante (GameScene.LiveMacroCell) costa 4 confronti scalari, contro il
# costo di ricostruire l'intero ratio_by_lot ad ogni singolo refresh anche quando nulla è cambiato.
static func get_fruit_stock_recompute_signature(resource_name: String, macro_state: MacroCellState) -> Array:
	var weights := _get_fruit_stock_weights(resource_name, macro_state)
	return [
		macro_state.get_secondary_resource_stock(resource_name),
		int(weights.get("checkpoint_day", -1)),
		int(weights.get("primary_resource_quantity", -1)),
		int(macro_state.berry_harvested_revision.get(resource_name, 0)),
	]


# Ricalcolo vero e proprio (mai chiamato direttamente da fuori questo file — passa sempre dalla
# cache sopra): itera il registro individui (TREE o SHRUB, secondo FRUIT_STOCK_SOURCES) — individui
# VIVI, gli stessi già usati da VegetationPoolService per stick/plant_fiber — un individuo tagliato/
# morto è già stato cancellato da lì, quindi un lotto occupato da un edificio, che
# BuildingSiteClearingService svuota già di tutti i suoi individui, non contribuisce mai un peso:
# nessun controllo edifici separato qui, a differenza di Stick/PlantFiberLotSelectorController, che
# invece devono escluderli esplicitamente perché lì la rivendicazione del lotto — tree/shrub_
# claimed_lots — SOPRAVVIVE alla rimozione degli individui. Coefficiente per fascia d'età letto da
# SubtypeRules (mai un valore letterale), fallback al coefficiente ADULT per un individuo senza
# track_age_bands o senza anno di nascita congelato (nessun caso reale oggi per berry: fruit_bearing
# ha sempre track_age_bands=true e ogni individuo riceve sempre un anno di nascita insieme al
# sottotipo, vedi IndividualVegetationService._freeze_new_individual — puro difensivo).
static func _compute_fruit_stock_weights(resource_name: String, macro_state: MacroCellState, current_year: int) -> Dictionary:
	var by_lot: Dictionary = {}
	var total := 0.0

	var source: Dictionary = FRUIT_STOCK_SOURCES[resource_name]
	var object_type: GameTypes.WorldObjectType = source["object_type"]
	var subtype_name: String = source["subtype_name"]

	var subtype_rule := ResourceCalculator.get_subtype_rule(object_type, subtype_name)
	if subtype_rule == null:
		return {"total": 0.0, "by_lot": by_lot}

	var subtype_store: Dictionary = _individual_subtype_store(macro_state, object_type)
	var birth_year_store: Dictionary = _individual_birth_year_store(macro_state, object_type)

	for key in subtype_store.keys():
		if subtype_store[key] != subtype_name:
			continue

		var weight: float = subtype_rule.production_coefficient_adult
		if subtype_rule.track_age_bands and birth_year_store.has(key):
			var years_lived: int = current_year - int(birth_year_store[key])
			var age_band: GameTypes.AgeBand = AgeBandVisualService.band_for_age(
				years_lived, subtype_rule.youth_duration_years, subtype_rule.adult_duration_years
			)
			match age_band:
				GameTypes.AgeBand.YOUNG:
					weight = subtype_rule.production_coefficient_young
				GameTypes.AgeBand.OLD:
					weight = subtype_rule.production_coefficient_old
				_:
					weight = subtype_rule.production_coefficient_adult

		if weight <= 0.0:
			continue

		var lot := Vector2i(key.x, key.y)
		by_lot[lot] = float(by_lot.get(lot, 0.0)) + weight
		total += weight

	return {"total": total, "by_lot": by_lot}
