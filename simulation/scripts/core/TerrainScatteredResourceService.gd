class_name TerrainScatteredResourceService
extends RefCounted

# Interfaccia uniforme per le risorse secondarie raccoglibili a terra (2026-09-09, richiesta
# utente; RISCRITTA 2026-09-19, richiesta utente — refactor lot_source) — nata per togliere a
# PickUpAction l'accesso diretto ai Dictionary di MacroCellState: il chiamante passa solo
# resource_name, questo service smista internamente. Dispatch ora su TRE famiglie invece di un
# case per nome risorsa:
#   - SecondaryResourceRules.lot_source != NONE (pebble/stick/plant_fiber/mushroom/
#     wild_vegetables) -> LotCapacityService, il servizio generico per l'intera famiglia "capacità
#     per lotto" — aggiungerne una nuova costa solo un .tres, nessuna riga qui.
#   - "eggs" -> stock aggregato ripartito per nido (get_egg_stock_available_at/
#     consume_egg_stock_at sotto), modello indipendente da lot_source (GRASS non ha un registro
#     per-individuo da cui derivare un peso "vero", vedi quei due file).
#   - FRUIT_STOCK_SOURCES (berry/acorn/fruit) -> stock aggregato ripartito per peso di individui
#     TREE/SHRUB (get_fruit_stock_available_at/consume_fruit_stock_at sotto).
#
# game_data per il confronto di freschezza lotto (LotCapacityService) è risolto da GameSettings.
# active_game_data — non un parametro esplicito, per lasciare invariata la firma richiesta
# (get_available/consume prendono solo macro_state/resource_name/position, stessa firma con cui
# PickUpAction già li chiama oggi) e per non allungare la catena di parametri di PickUpAction
# (che oggi non riceve/non tiene game_data — vedi PickUpAction._init) solo per questo.


# `rules` risolta UNA SOLA VOLTA qui (2026-09-19, richiesta utente — correzione prestazioni: prima
# la stessa risorsa veniva risolta indipendentemente 3-4 volte lungo la catena — is_resource_locked,
# il controllo lot_source qui, LotCapacityService.get_available, _apply_seasonal_availability_
# to_capacity — ognuno chiamando di nuovo CaloricCalculator.get_caloric_source_rules. Ora cacheata
# lì (vedi CaloricCalculator._rules_cache), quindi non è più un vero I/O ripetuto, ma resta un
# lookup Dictionary + dispatch ripetuto senza motivo: risolta qui una volta, passata esplicitamente
# a is_resource_locked/LotCapacityService.get_available invece di lasciarla ri-risolvere) —
# nessun'altra riga di questo file richiama più get_caloric_source_rules per lo stesso resource_name.
static func get_available(macro_state: MacroCellState, resource_name: String, position: Vector2i) -> int:
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if is_resource_locked(resource_name, rules):
		return 0
	return _get_available_unlocked(macro_state, resource_name, position, rules)


# Disponibilità SENZA il gate required_idea_id (2026-09-19, richiesta utente — erbe medicinali:
# "il marker non dipende dal lock, solo dalla disponibilità") — per il RENDERING a terra
# (GameScene/MacroCellScene._build_lot_availability_map), MAI per pickup/ispezione, che passano
# sempre da get_available. Prima di questo metodo il rendering chiamava get_available, quindi
# avrebbe nascosto anche i marker di una risorsa bloccata: contrario a quanto già dichiarato su
# required_idea_id ("MAI dal rendering"), mai emerso solo perché nessuna .tres lo valorizzava.
static func get_available_ignoring_lock(macro_state: MacroCellState, resource_name: String, position: Vector2i) -> int:
	return _get_available_unlocked(macro_state, resource_name, position, CaloricCalculator.get_caloric_source_rules(resource_name))


static func _get_available_unlocked(macro_state: MacroCellState, resource_name: String, position: Vector2i, rules: SecondaryResourceRules) -> int:
	if rules != null and rules.lot_source != SecondaryResourceTypes.LotSource.NONE:
		return LotCapacityService.get_available(macro_state, resource_name, position, rules)
	if resource_name == "eggs":
		return get_egg_stock_available_at(macro_state, position)
	if FRUIT_STOCK_SOURCES.has(resource_name):
		return get_fruit_stock_available_at(resource_name, macro_state, position)
	return 0


# STESSO principio di get_available sopra — `rules` risolta una sola volta, passata a
# LotCapacityService.consume invece di lasciarglielo ri-risolvere.
static func consume(macro_state: MacroCellState, resource_name: String, position: Vector2i, quantity: int) -> void:
	if quantity <= 0:
		return
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if rules != null and rules.lot_source != SecondaryResourceTypes.LotSource.NONE:
		LotCapacityService.consume(macro_state, resource_name, position, quantity, rules)
		return
	if resource_name == "eggs":
		consume_egg_stock_at(macro_state, position, quantity)
		return
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
#
# `rules` opzionale (2026-09-19, richiesta utente — correzione prestazioni) — default null =
# risolvila da sé (comportamento invariato per GameScene._append_unlocked_pickup_candidate, il
# solo altro chiamante, che non ha ancora le rules in mano); get_available sopra la passa già
# risolta, evitando una seconda chiamata a CaloricCalculator.get_caloric_source_rules.
static func is_resource_locked(resource_name: String, rules: SecondaryResourceRules = null) -> bool:
	var resource_rules: SecondaryResourceRules = rules if rules != null else CaloricCalculator.get_caloric_source_rules(resource_name)
	if resource_rules == null or resource_rules.required_idea_id == "":
		return false
	var folk := GameSettings.active_human_folk
	return folk == null or not folk.completed_ideas.has(resource_rules.required_idea_id)


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
