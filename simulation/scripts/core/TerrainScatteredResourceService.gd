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
			return _get_available_pebble(macro_state, position)
		"stick":
			return _get_available_stick(macro_state, position)
		"plant_fiber":
			return _get_available_plant_fiber(macro_state, position)
		"mushroom":
			return _get_available_mushroom(macro_state, position)
		"eggs":
			return get_egg_stock_available_at(macro_state, position)
		"wild_vegetables":
			return get_wild_vegetable_available_at(macro_state, position)
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
		"eggs":
			consume_egg_stock_at(macro_state, position, quantity)
		"wild_vegetables":
			consume_wild_vegetable_at(macro_state, position, quantity)
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


# Lookup diretto + moltiplicatore stagionale (2026-09-19, richiesta utente — bugfix "seasonal_
# availability_multiplier è ignorato da pebble/stick/plant_fiber": _apply_seasonal_availability_
# to_capacity esisteva già come helper generico ma solo _get_available_mushroom lo chiamava —
# per pebble.tres/stick.tres/plant_fiber.tres una curva non piatta veniva quindi ignorata in
# silenzio. NESSUN cambio di comportamento oggi: pebble.tres ha una curva piatta [1,1,1,1], quindi
# floor(capacity × 1.0) == capacity sempre — cambia solo se in futuro qualcuno valorizza una curva
# vera). A differenza di stick/plant_fiber/mushroom, pebble non ha un Dictionary {"capacity",
# "harvested"} per lotto: pebble_quantities[position] È già la quantità residua (harvested
# sottratto direttamente da _consume_pebble sopra, mai una capacity grezza separata) — qui si
# applica il moltiplicatore a QUELLA quantità residua, non a una "capacity" a parte.
static func _get_available_pebble(macro_state: MacroCellState, position: Vector2i) -> int:
	var remaining: int = int(macro_state.pebble_quantities.get(position, 0))
	if remaining <= 0:
		return 0
	return _apply_seasonal_availability_to_capacity("pebble", remaining)


# Lotto stale (mai ridisegnato dall'ultimo checkpoint growth passato — vedi
# StickPoolService.most_recent_growth_checkpoint_absolute_day) → 0: senza un refresh recente la
# capacità persistita non è affidabile, stesso confronto già usato da
# StickPoolService.refresh_macrocell per decidere se un lotto va rigenerato.
#
# Moltiplicatore stagionale (2026-09-19, richiesta utente — vedi _get_available_pebble sopra per
# il perché: STESSO bugfix, STESSO helper generico già usato da mushroom, applicato QUI PRIMA di
# sottrarre harvested — stesso ordine/stesso principio di _get_available_mushroom). Nessun cambio
# di comportamento oggi: stick.tres ha una curva piatta [1,1,1,1].
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
	var seasonal_capacity := _apply_seasonal_availability_to_capacity("stick", capacity)
	return max(seasonal_capacity - harvested, 0)


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
#
# Moltiplicatore stagionale (2026-09-19, richiesta utente — vedi _get_available_stick sopra per
# il bugfix/il perché). Nessun cambio di comportamento oggi: plant_fiber.tres ha una curva piatta
# [1,1,1,1].
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
	var seasonal_capacity := _apply_seasonal_availability_to_capacity("plant_fiber", capacity)
	return max(seasonal_capacity - harvested, 0)


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
# usato da OGNI risorsa "capacità per lotto" (pebble/stick/plant_fiber/mushroom — 2026-09-19,
# richiesta utente: PRIMA solo _get_available_mushroom lo chiamava, così pebble.tres/stick.tres/
# plant_fiber.tres avevano il campo seasonal_availability_multiplier presente ma IGNORATO in
# silenzio da qualunque curva vi fosse impostata — bugfix di coerenza, nessun cambio di
# comportamento oggi perché le loro tre curve sono piatte [1,1,1,1], floor(capacity×1.0)==capacity),
# pensato per qualunque futura risorsa di questa famiglia CON una curva stagionale non-piatta nel
# proprio .tres, e per un eventuale rendering che debba mostrare la stessa proporzione — mai un
# secondo calcolo duplicato altrove.
#
# floor(capacity × moltiplicatore), mai round/ceil (stesso principio "mai frazionario" già seguito
# ovunque nel progetto per quantità raccoglibili). resource_rules == null (nome non risolvibile) o
# GameSettings.active_game_data assente (nessuna partita attiva, impossibile risolvere la stagione
# corrente) -> capacity invariata: fail-OPEN qui (a differenza del fail-closed di is_resource_locked
# sopra), perché l'assenza di un game_data non è un segnale "nascondi tutto", è semplicemente "non
# posso applicare il moltiplicatore" — un chiamante di solito ha già un proprio guard game_data a
# monte (vedi _get_available_mushroom/_get_available_stick/_get_available_plant_fiber/
# _get_available_pebble) che intercetta questo caso comunque.
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


# "Nidi" per eggs (2026-09-18, richiesta utente — uova raccoglibili per microcella, STESSO modello
# di stock aggregato/derivazione al volo della famiglia "fruit stock" sopra, ma con una differenza
# strutturale: berry/acorn/fruit derivano il peso per lotto da un registro PERSISTITO di individui
# TREE/SHRUB (tree_individual_subtype/shrub_individual_subtype), che GRASS non ha (nessuna identità
# individuale, vedi VegetationPositionService) — quindi qui non c'è un registro da cui leggere un
# peso "vero": il peso di ogni nido è invece esso stesso deterministico da hash (vedi
# compute_egg_nest_positions sotto, aggiornato 2026-09-18 — "rendi il peso variabile per nido": PRIMA
# ogni nido pesava esattamente 1, ora un valore in SecondaryResourceRules.patch_weight_min/max). Per
# lo stesso motivo per cui il peso non può essere ricostruito da un registro, dipende dalle
# posizioni GRASS CORRENTI, che vivono solo nella cache runtime di GameScene/LiveMacroCell — è
# GameScene._refresh_resource_visuals a scrivere MacroCellState.egg_nest_positions ogni volta che
# rigenera quelle posizioni (vedi commento su quel campo), MAI questo file, che si limita a leggerlo.


# Sottoinsieme deterministico di `grass_positions` (Array[Vector2i], le posizioni GRASS CORRENTI di
# una macrocella — tipicamente cell.cached_vegetation_positions[GameTypes.WorldObjectType.GRASS]):
# Vector2i (nido) -> float (peso, vedi sotto). Membership scelta con hash(str(micro_seed) + salt)
# sulla posizione, filtrato dalla soglia SecondaryResourceRules.patch_probability di eggs.tres —
# STESSO idioma di ResourcePositionService._passes_soft_threshold/_priority_hash (hash puro di
# posizione+seed, mai randf(): stesso seed => stesso risultato sempre, indipendentemente da quando/
# quante volte viene chiamato). rules == null o patch_probability <= 0.0 (nessuna .tres valorizzata,
# vedi default in SecondaryResourceRules) -> {} (nessun nido), mai un errore.
#
# Peso per nido (2026-09-18, richiesta utente — "i nidi hanno tutti peso uniforme... rendi il peso
# variabile", altrimenti ogni macrocella distribuirebbe sempre lo stesso numero esatto di uova per
# nido): un SECONDO hash della stessa posizione, con un SALT DIVERSO da quello di membership sopra
# (mai lo stesso — altrimenti "essere un nido" e "quanto pesa" sarebbero perfettamente correlati
# invece che indipendenti, es. sempre i nidi più vicini alla soglia col peso più alto/basso),
# interpolato linearmente in [patch_weight_min, patch_weight_max]. Deterministico come la membership:
# stesso seed => stesso peso sempre, nessun randf().
#
# BUGFIX (2026-09-18, richiesta utente — "il pickup viene offerto anche dove non ci sono uova, e
# l'ispezione mostra uova=0 invece di dire solo erba"): PRIMA questa funzione ignorava del tutto
# secondary_resource_stock["eggs"] — un lotto passava il test hash ed entrava in egg_nest_positions
# anche con stock aggregato a 0 (fuori dalla stagione delle uova, o in una macrocella senza BIRDS),
# quindi risultava un "nido" geometricamente valido ma perennemente vuoto. Una posizione è un nido
# SOLO quando esistono davvero uova per la macrocella: stock <= 0.0 -> {} (nessun nido affatto),
# PRIMA di risolvere rules/hashare le posizioni — un aggregato pari a zero rende comunque zero ogni
# singola quota (stock × peso/peso_totale), quindi questo early-out non cambia MAI il risultato
# finale di get_egg_stock_available_at, si limita a farlo scattare più a monte (niente candidati/
# render per lotti che sarebbero comunque risultati a 0). Ricalcolata alla stessa cadenza di
# egg_nest_positions (GameScene._refresh_resource_visuals, invalidata ad ogni checkpoint stagionale
# su TUTTE le celle vive — vedi _on_day_advanced/checkpoint_ran), quindi resta sempre coerente con
# lo stock corrente.
static func compute_egg_nest_positions(macro_state: MacroCellState, grass_positions: Array) -> Dictionary:
	if macro_state.get_secondary_resource_stock("eggs") <= 0.0:
		return {}
	var rules := CaloricCalculator.get_caloric_source_rules("eggs")
	if rules == null or rules.patch_probability <= 0.0:
		return {}
	var nest_seed: int = hash(str(macro_state.micro_seed) + "_eggs_nest")
	var weight_seed: int = hash(str(macro_state.micro_seed) + "_eggs_nest_weight")
	var nests: Dictionary = {}
	for pos in grass_positions:
		var lot := Vector2i(pos.x, pos.y)
		var hash_value: float = float(hash(lot * 3 + Vector2i(nest_seed, 727)) % 100000) / 100000.0
		if hash_value < rules.patch_probability:
			var weight_hash: float = float(hash(lot * 5 + Vector2i(weight_seed, 419)) % 100000) / 100000.0
			nests[lot] = lerp(rules.patch_weight_min, rules.patch_weight_max, weight_hash)
	return nests


# "Lotti" per wild_vegetables (2026-09-19, richiesta utente — verdure selvatiche raccoglibili per
# microcella, modello a CAPACITÀ per lotto come stick/mushroom — NESSUNO stock aggregato di
# macrocella, NESSUN consumo animale, a differenza di eggs sopra) — STESSA tecnica di selezione
# posizione di compute_egg_nest_positions (due hash sulla stessa posizione con salt diversi: uno
# decide SE è un lotto con la soglia patch_probability, l'altro QUANTO vale con l'intervallo
# patch_capacity_min/max), ma il secondo hash produce una CAPACITÀ ASSOLUTA per lotto (non un peso
# relativo da ripartire su uno stock — wild_vegetables non ha uno stock aggregato affatto), scalata
# da un fattore [0,1] = dedicated_space(GRASS) / TOTAL_SPACE della macrocella: un prato rado (poca
# erba rispetto allo spazio totale) rende meno di uno fitto, a parità di capacità RAW estratta
# dall'hash. dedicated_space(GRASS) <= 0 -> {} (nessun lotto affatto), PRIMA di risolvere rules/
# hashare le posizioni — stesso principio del gate su stock in compute_egg_nest_positions: un
# fattore 0 renderebbe comunque capacità 0 per ogni lotto, quindi l'early-out non cambia mai il
# risultato finale, si limita a farlo scattare più a monte. Un lotto con capacità arrotondata a 0
# (raw molto basso × fattore molto basso) viene scartato qui stesso (mai un'entry a capacità 0 nel
# risultato): niente da raccogliere lì, stesso principio "un hit esiste solo se il lotto è
# realmente di quel tipo" già seguito per eggs/mushroom nel resto di questo file.
#
# NON VegetationPoolService (richiesta esplicita utente): quel motore conta individui maturi in
# tree_individual_subtype/shrub_individual_subtype/tree_virtual_birth_year/shrub_virtual_birth_
# year — nessuno di questi esiste per GRASS (nessuna identità individuale, vedi
# VegetationPositionService), quindi non è riusabile nemmeno con un parametro aggiuntivo.
static func compute_wild_vegetable_lots(macro_state: MacroCellState, grass_positions: Array) -> Dictionary:
	var grass_space: int = macro_state.get_dedicated_space(GameTypes.WorldObjectType.GRASS)
	if grass_space <= 0:
		return {}
	var rules := CaloricCalculator.get_caloric_source_rules("wild_vegetables")
	if rules == null or rules.patch_probability <= 0.0:
		return {}
	var patch_seed: int = hash(str(macro_state.micro_seed) + "_wild_vegetables_patch")
	var capacity_seed: int = hash(str(macro_state.micro_seed) + "_wild_vegetables_patch_capacity")
	var density_factor: float = float(grass_space) / float(MacroCellState.TOTAL_SPACE)
	var lots: Dictionary = {}
	for pos in grass_positions:
		var lot := Vector2i(pos.x, pos.y)
		var hash_value: float = float(hash(lot * 3 + Vector2i(patch_seed, 811)) % 100000) / 100000.0
		if hash_value >= rules.patch_probability:
			continue
		var capacity_hash: float = float(hash(lot * 5 + Vector2i(capacity_seed, 953)) % 100000) / 100000.0
		var raw_capacity: float = lerp(float(rules.patch_capacity_min), float(rules.patch_capacity_max), capacity_hash)
		var capacity: int = int(round(raw_capacity * density_factor))
		if capacity > 0:
			lots[lot] = capacity
	return lots


# Disponibilità REALE del lotto: capacità RAW (vedi compute_wild_vegetable_lots sopra, già scalata
# per densità GRASS) passata attraverso l'helper generico di scalatura stagionale già usato da
# mushroom (_apply_seasonal_availability_to_capacity — legge seasonal_availability_multiplier da
# wild_vegetables.tres, NESSUNA tabella hardcoded qui) meno quanto già raccolto DA UMANI in questo
# lotto (MacroCellState.wild_vegetables_harvested_by_lot). `position` non in wild_vegetable_lots
# (mai stato un lotto, o non lo è più dopo un rigenero — vedi commento su quel campo) -> 0, nessuna
# eccezione.
static func get_wild_vegetable_available_at(macro_state: MacroCellState, position: Vector2i) -> int:
	if not macro_state.wild_vegetable_lots.has(position):
		return 0
	var capacity: int = int(macro_state.wild_vegetable_lots[position])
	var seasonal_capacity := _apply_seasonal_availability_to_capacity("wild_vegetables", capacity)
	var harvested: int = int(macro_state.wild_vegetables_harvested_by_lot.get(position, 0))
	return max(seasonal_capacity - harvested, 0)


# Incrementa wild_vegetables_harvested_by_lot[position], clampato alla capacità GREZZA (non a
# quella scontata dalla stagione) — STESSO principio esplicito di _consume_stick: capacity/
# harvested restano quelli dell'ultima generazione nota, get_available già garantisce che questa
# funzione non venga mai chiamata con quantity superiore alla disponibilità REALE già scontata
# della stagione (PickUpAction risolve la quantità da get_available), quindi un secondo calcolo
# stagionale qui sarebbe ridondante.
static func consume_wild_vegetable_at(macro_state: MacroCellState, position: Vector2i, quantity: int) -> void:
	var capacity: int = int(macro_state.wild_vegetable_lots.get(position, 0))
	var harvested_before: int = int(macro_state.wild_vegetables_harvested_by_lot.get(position, 0))
	macro_state.wild_vegetables_harvested_by_lot[position] = min(harvested_before + quantity, capacity)


# Peso totale dei nidi di una macrocella — somma di egg_nest_positions.values(), estratta a parte
# solo perché get_egg_stock_available_at sotto la userebbe come denominatore comune per OGNI
# chiamata sulla stessa macrocella (nessuna cache: il Dictionary è già piccolo, tipicamente poche
# decine di nidi, e già ricalcolato alla cadenza di egg_nest_positions — sommarlo ad ogni query
# resta economico, stesso principio "niente cache dove non serve" già seguito per nest_count prima
# di questo passo).
static func _get_egg_nest_total_weight(macro_state: MacroCellState) -> float:
	var total: float = 0.0
	for weight in macro_state.egg_nest_positions.values():
		total += float(weight)
	return total


# Disponibilità REALE del nido: quota nominale (stock aggregato × peso_nido / peso_totale — vedi
# compute_egg_nest_positions sopra per come nasce il peso, ora variabile per nido) meno quanto già
# raccolto DA UMANI in questo nido quest'anno (MacroCellState.eggs_harvested_by_lot). Il TOTALE
# raccoglibile in una macrocella non cambia rispetto al vecchio peso uniforme (la somma di
# stock×peso/peso_totale su tutti i nidi resta sempre stock, per costruzione) — cambia solo come si
# distribuisce tra nidi ricchi (peso vicino a patch_weight_max) e poveri (vicino a patch_weight_min).
# `position` non in egg_nest_positions (mai stato un nido, o non lo è più dopo un rigenero — vedi
# commento su quel campo) -> 0, nessuna eccezione.
static func get_egg_stock_available_at(macro_state: MacroCellState, position: Vector2i) -> int:
	if not macro_state.egg_nest_positions.has(position):
		return 0
	var total_weight: float = _get_egg_nest_total_weight(macro_state)
	if total_weight <= 0.0:
		return 0
	var lot_weight: float = float(macro_state.egg_nest_positions[position])
	var stock: float = macro_state.get_secondary_resource_stock("eggs")
	var nominal: int = int(floor(stock * lot_weight / total_weight))
	var harvested: int = int(macro_state.eggs_harvested_by_lot.get(position, 0))
	return max(nominal - harvested, 0)


# Scala l'aggregato (stesso principio esplicito di consume_fruit_stock_at sopra — "è il punto in
# cui la raccolta umana toglie cibo agli animali") E incrementa eggs_harvested_by_lot[position]:
# STESSO schema di consume_fruit_stock_at, ma senza il livello aggiuntivo per resource_name (eggs è
# l'unica risorsa di questa famiglia, vedi MacroCellState.eggs_harvested_by_lot).
static func consume_egg_stock_at(macro_state: MacroCellState, position: Vector2i, quantity: int) -> void:
	var stock_before: float = macro_state.get_secondary_resource_stock("eggs")
	macro_state.set_secondary_resource_stock("eggs", stock_before - float(quantity))
	var harvested_before: int = int(macro_state.eggs_harvested_by_lot.get(position, 0))
	macro_state.eggs_harvested_by_lot[position] = harvested_before + quantity


# Azzeramento stagionale del raccolto per le risorse a CAPACITÀ PER LOTTO (2026-09-19, richiesta
# utente — bugfix "wild_vegetables_harvested_by_lot non viene mai azzerato, le verdure non
# ricrescono mai"): eggs (sopra) ha già il proprio azzeramento stagionale, ma vive dentro
# WorldTimeService._run_secondary_resource_stock_checkpoint, agganciato al loop su CaloricCalculator.
# SECONDARY_SOURCES — un percorso che presuppone uno STOCK AGGREGATO di macrocella (source[
# "primary_resource_type"]), che le risorse a capacità per lotto (mushroom, wild_vegetables) non
# hanno affatto (richiesta esplicita utente: "le verdure non stanno in SECONDARY_SOURCES, serve un
# percorso che valga per le risorse a capacità per lotto"). Questo è quel percorso — UN SOLO punto
# per ENTRAMBE le risorse (non due blocchi ad-hoc separati), chiamato da WorldTimeService allo
# STESSO momento (inizio di ogni stagione) del checkpoint eggs, ma indipendente da esso.
#
# VERIFICA mushroom (richiesta esplicita utente): mushroom.tres ha una curva NON piatta
# ([0.4, 0.0, 0.3, 1.0]) — oggi il SOLO azzeramento che mushroom_quantities riceve è quello
# INCIDENTALE di VegetationPoolService.refresh_macrocell (l'intera entry per lotto, capacity
# INCLUSA, viene rigenerata da zero una volta l'anno al checkpoint growth di fine PRIMAVERA,
# harvested=0 come effetto collaterale) — un reset legato al ciclo di maturazione degli alberi,
# NON al proprio moltiplicatore stagionale: per questa curva specifica coincide (l'unico giorno di
# reset è già a moltiplicatore 0.0, subito prima che salga in estate), ma è una coincidenza di
# calendario, non una garanzia — un'eventuale futura curva con una salita in un punto diverso
# dell'anno lascerebbe mushroom con lo stesso identico problema di wild_vegetables per il resto
# dell'anno. Da qui in avanti mushroom riceve ANCHE questo azzeramento esplicito (in aggiunta al
# reset incidentale esistente, mai in conflitto: azzerare un harvested già a 0 è un no-op).
#
# LISTA (2026-09-19, richiesta utente — bugfix "LOT_CAPACITY_HARVEST_SOURCES è scritta a mano,
# sostituiscila con un criterio derivato dai dati"): PRIMA questa lista conteneva SOLO "mushroom"/
# "wild_vegetables" perché erano le due risorse la cui curva SEMBRAVA non piatta *oggi*, guardata a
# occhio — esattamente la trappola segnalata: dare domani una curva vera a stick.tres/plant_fiber.
# tres non avrebbe fatto scattare nulla, perché quel file andava ricordato e riaggiornato a mano.
# Ora elenca invece TUTTE le risorse "capacità per lotto" con un concetto di "harvested" da poter
# azzerare (stick/plant_fiber/mushroom/wild_vegetables) — un fatto STRUTTURALE (quali campi esistono
# su MacroCellState/quali case esistono in get_available/consume sopra), non stagionale: la DECISIONE
# di azzerare o no resta 100% derivata dalla curva del .tres di ciascuna, ricalcolata sotto ad ogni
# checkpoint — nessuna curva da giudicare "piatta" a mano qui. pebble È a capacità per lotto ma
# DELIBERATAMENTE ESCLUSA: pebble_quantities[pos] è già la quantità residua (vedi _consume_pebble/
# _get_available_pebble sopra), non esiste una "capacity" separata da cui un "harvested" possa
# essere scorporato e azzerato — un sasso estratto non deve mai "ricrescere", qualunque sia la sua
# curva stagionale (quella già si applica in lettura, vedi _apply_seasonal_availability_to_capacity,
# senza bisogno di un reset qui).
const LOT_CAPACITY_RESOURCE_NAMES: Array[String] = ["stick", "plant_fiber", "mushroom", "wild_vegetables"]


# Driver chiamato una volta per checkpoint stagionale (WorldTimeService, inizio di OGNI stagione,
# stesso momento del checkpoint eggs) — per ciascuna risorsa in LOT_CAPACITY_RESOURCE_NAMES,
# decide UNA SOLA VOLTA (non per cella: nessuna dipendenza da macro_state, solo dalla curva del
# .tres) se il moltiplicatore stagionale sale rispetto alla stagione precedente; se nessuna
# risorsa sale, esce subito senza toccare world.cell_states (caso comune: la maggior parte delle
# transizioni stagionali non fa salire NULLA — oggi stick/plant_fiber non salgono MAI, curve
# piatte, quindi in pratica continuano a non ricevere alcun reset esplicito, ma per una ragione
# che si auto-corregge il giorno in cui qualcuno gli dà una curva vera, non perché sono assenti da
# un elenco). Altrimenti itera le celle SOLO per le risorse che devono davvero resettarsi.
static func reset_all_lot_harvests_on_season_rise(
	world: World, previous_season: GameTypes.Season, new_season: GameTypes.Season
) -> void:
	var resources_to_reset: Array[String] = []
	for resource_name in LOT_CAPACITY_RESOURCE_NAMES:
		var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
		if rules == null:
			continue
		var previous_multiplier: float = float(rules.seasonal_availability_multiplier[previous_season])
		var new_multiplier: float = float(rules.seasonal_availability_multiplier[new_season])
		if new_multiplier > previous_multiplier:
			resources_to_reset.append(resource_name)
	if resources_to_reset.is_empty():
		return
	for state in world.cell_states:
		for resource_name in resources_to_reset:
			_reset_lot_harvest_for_resource(state, resource_name)


# Dispatch per-risorsa: "wild_vegetables" -> registro FLAT, svuotato per intero (stesso principio
# del ramo "fruit stock" in WorldTimeService — non c'è "capacity" da preservare a parte, vedi
# get_wild_vegetable_available_at, che la ricalcola sempre al volo); stick/plant_fiber/mushroom ->
# STESSO registro combinato {"checkpoint_day","capacity","harvested"}, SOLO "harvested" azzerato
# per ogni lotto tramite l'helper condiviso sotto (capacity/checkpoint_day intatti: azzerarli
# forzerebbe una rigenerazione a vuoto prima del prossimo checkpoint growth reale, mai voluto qui).
static func _reset_lot_harvest_for_resource(macro_state: MacroCellState, resource_name: String) -> void:
	match resource_name:
		"wild_vegetables":
			if not macro_state.wild_vegetables_harvested_by_lot.is_empty():
				macro_state.wild_vegetables_harvested_by_lot.clear()
		"stick":
			_reset_harvested_in_combined_registry(macro_state.stick_quantities)
		"plant_fiber":
			_reset_harvested_in_combined_registry(macro_state.plant_fiber_quantities)
		"mushroom":
			_reset_harvested_in_combined_registry(macro_state.mushroom_quantities)


# Azzera SOLO "harvested" per ogni lotto di un registro nel formato combinato {"checkpoint_day",
# "capacity","harvested"} (stick_quantities/plant_fiber_quantities/mushroom_quantities — stesso
# Dictionary passato per riferimento, le scritture qui sono visibili al chiamante) — estratta una
# volta sola invece di tre copie identiche (mushroom ne aveva già una propria, ora condivisa anche
# da stick/plant_fiber). `if harvested == 0: continue` evita una scrittura Dictionary per il caso
# comune (lotto mai raccolto), stesso principio già in uso altrove nel file.
static func _reset_harvested_in_combined_registry(quantities: Dictionary) -> void:
	for lot in quantities.keys():
		var entry: Dictionary = quantities[lot]
		if int(entry.get("harvested", 0)) == 0:
			continue
		entry["harvested"] = 0
		quantities[lot] = entry
