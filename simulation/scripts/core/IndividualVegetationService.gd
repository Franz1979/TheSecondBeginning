class_name IndividualVegetationService
extends RefCounted

# Persistenza "nota-prima, genera-solo-il-delta" (sostituisce il precedente "ricalcola tutto da
# zero ogni volta dai soli numeri aggregati", che non garantiva la stabilità di un individuo
# specifico: né di posizione — un cambio di resource_quantity poteva far sparire/rinumerare
# individui a caso — né di sottotipo, ritestato ad ogni render contro un rapporto corrente e quindi
# capace di "cambiare specie" se le proporzioni della cella si spostavano). Regola guida: un
# individuo già noto (sottotipo+anno di nascita congelati in MacroCellState, lotto già rivendicato
# in tree_claimed_lots/shrub_claimed_lots) viene SEMPRE ridisegnato nello stesso lotto con lo
# stesso indice, qualunque cosa succeda ai numeri aggregati altrove; solo il fabbisogno che gli
# individui noti non coprono ancora passa dal motore procedurale (ResourcePositionService), e gli
# indici assegnati a un lotto sono sempre in APPEND (mai rinumerati): rimuovere un individuo da un
# lotto affollato non sposta mai i suoi vicini di lotto.
#
# Taglio (vegetation_cut_exceptions) e morte (vegetation_death_exceptions) condividono lo stesso
# meccanismo di blocco universale sullo SLOT (vedi _is_blocked) ma hanno finestre di non-ricrescita
# di natura diversa, per decisione esplicita: il taglio è un'azione deliberata del giocatore, resta
# bloccato per REENTRY_YEARS_BY_TYPE anni (vedi _is_cut_entry_active). La morte naturale è invece
# solo un artificio grafico stagionale — nessun conteggio di anni: un'entry in
# vegetation_death_exceptions è attiva per pura presenza, azzerata in BLOCCO da WorldTimeService.
# _clear_natural_death_markers al checkpoint di growth (fine primavera), mai scaduta individualmente
# per anno. Il marker visivo che il renderer disegna sopra lo slot bloccato distingue comunque
# tronco mozzato vs pianta morta (vedi MicroCellRenderer.set_cut_positions/set_dead_positions).
# Scrive in vegetation_cut_exceptions PlayerHarvestService.cut_individual; scrive in
# vegetation_death_exceptions NaturalMortalityVisualService.kill_individual (mortalità in corso su
# una cella nota) E questo stesso file (_seed_first_sight_death_markers, prima scoperta di una
# cella mai vista: vedi sotto).
#
# Deliberatamente FUORI SCOPE per questo passo: la mortalità/lo sgretolamento del territorio noto
# (se dedicated_space o il target per-lotto scendono sotto quanto già noto, questo servizio non
# rimuove nulla — un individuo noto resta noto finché non viene esplicitamente cancellato altrove,
# accettato come inconsistenza temporanea in attesa di quel lavoro).

const REENTRY_YEARS_BY_TYPE := {
	GameTypes.WorldObjectType.TREE: 8,
	GameTypes.WorldObjectType.SHRUB: 2,
}

const TREE_AGE_SALT := Vector2i(179, 97)
const SHRUB_AGE_SALT := Vector2i(163, 71)

# Salt di sottotipo — spostati qui da MicroCellRenderer insieme alla decisione stessa: il
# sottotipo si decide ora UNA SOLA volta, alla generazione di un individuo nuovo, mai più ad ogni
# render. Stesse identiche formule hash di prima, nessun cambio di comportamento statistico.
const TREE_CONIFER_SALT := Vector2i(131, 17)
const TREE_FRUIT_BEARING_SALT := Vector2i(211, 149)
const TREE_FRUIT_DOMESTICABLE_SALT := Vector2i(83, 227)
const SHRUB_FRUIT_BEARING_SALT := Vector2i(97, 53)


# Equivalente di ResourcePositionService.generate_positions per TREE/SHRUB, con l'aggiunta della
# granularità per-individuo E della persistenza "nota-prima". Ritorna posizioni-INDIVIDUO
# (Vector3i: x, y lotto + indice locale), non posizioni-lotto.
static func generate_positions(
	macro_state: MacroCellState,
	object_type: GameTypes.WorldObjectType,
	occupied: Dictionary,
	frequency: float,
	threshold: float,
	current_year: int,
	current_day: int
) -> Array:
	# Pulizia delle eccezioni di taglio scadute: nessun costo di realismo, una volta passata la
	# finestra di rientro l'entry non serve più a nessuno — vedi _prune_expired_cut_exceptions.
	# Filtrata per origin_type == object_type: le due chiamate (una per TREE, una per SHRUB, vedi
	# VegetationPositionService.CLAIM_ORDER) coprono insieme tutte le origini possibili. La morte
	# naturale non ha una pulizia equivalente qui: è azzerata in blocco altrove (vedi
	# WorldTimeService._clear_natural_death_markers), mai scaduta entry per entry per anno.
	_prune_expired_cut_exceptions(macro_state.vegetation_cut_exceptions, object_type, current_year)

	var dedicated_space: int = macro_state.get_dedicated_space(object_type)
	if dedicated_space <= 0:
		return []

	var birth_year_store: Dictionary = _birth_year_store(macro_state, object_type)
	var subtype_store: Dictionary = _subtype_store(macro_state, object_type)
	var claimed_lots: Dictionary = _claimed_lots_store(macro_state, object_type)
	# "Mai visto prima in assoluto" = nessun lotto ancora rivendicato per questo tipo in questa
	# cella — condizione più larga del semplice birth_year_store vuoto, perché un lotto può essere
	# noto anche solo tramite un'eccezione attiva (individuo tagliato/morto, birth_year già
	# rimosso — vedi _freeze_new_individual sul perché un individuo bloccato non porta età).
	var is_first_sight: bool = claimed_lots.is_empty()

	for pos in claimed_lots.keys():
		occupied[pos] = true

	var new_lots_needed: int = max(0, dedicated_space - claimed_lots.size())
	var noise_seed: int = hash(str(macro_state.micro_seed) + "_" + str(object_type))
	var new_lots: Array = ResourcePositionService.generate_positions(
		noise_seed, new_lots_needed, occupied, frequency, threshold
	)
	for pos in new_lots:
		occupied[pos] = true
		claimed_lots[pos] = true

	var all_lots: Array = claimed_lots.keys()

	return _distribute_individuals(
		macro_state, object_type, all_lots, noise_seed, current_year, current_day,
		birth_year_store, subtype_store, is_first_sight
	)


# Secondo livello, sui lotti già scelti sopra (noti + nuovi insieme). A differenza del vecchio
# comportamento (floor_count/resto ricalcolati da zero e riapplicati a TUTTI gli indici del
# lotto), qui il target per-lotto non scende MAI sotto quanti individui sono già noti in quel
# lotto (vivi o bloccati da un'eccezione) — vedi _count_known_extent_by_lot: se il target
# aggregato implicherebbe meno di quanti già ne conosco, semplicemente non genero nulla di nuovo
# per quel lotto (nessuna rimozione, la mortalità resta fuori scope). Se invece implica di più,
# i soli indici NUOVI (mai usati prima in quel lotto) vengono generati e congelati.
static func _distribute_individuals(
	macro_state: MacroCellState,
	object_type: GameTypes.WorldObjectType,
	lot_positions: Array,
	noise_seed: int,
	current_year: int,
	current_day: int,
	birth_year_store: Dictionary,
	subtype_store: Dictionary,
	is_first_sight: bool
) -> Array:
	var dedicated_space: int = lot_positions.size()
	if dedicated_space <= 0:
		return []

	var resource_quantity: int = macro_state.get_resource_quantity(object_type)
	if resource_quantity <= 0:
		return []

	var floor_count: int = resource_quantity / dedicated_space
	var remainder: int = resource_quantity - dedicated_space * floor_count
	var ordered_lots: Array = _sorted_by_remainder_priority(lot_positions, noise_seed)
	var known_extent_by_lot: Dictionary = _count_known_extent_by_lot(macro_state, object_type, lot_positions, current_year)

	# Prima passata: solo pianificare QUALI slot (lotto+indice) esisteranno quest'anno, senza
	# ancora congelare/aggiungere nulla — serve l'elenco completo PRIMA di sapere quali di questi
	# nascono già "morti" (vedi _seed_first_sight_death_markers sotto), altrimenti la seconda
	# passata (_is_blocked) non li vedrebbe ancora bloccati.
	var planned_slots: Array = []
	for i in range(ordered_lots.size()):
		var lot_pos: Vector2i = ordered_lots[i]
		var target_count: int = floor_count + (1 if i < remainder else 0)
		var known_extent: int = int(known_extent_by_lot.get(lot_pos, 0))
		# Mai sotto quanto già noto in questo lotto (vedi commento in testa alla funzione).
		var effective_count: int = max(target_count, known_extent)
		for index in range(effective_count):
			planned_slots.append({"lot_pos": lot_pos, "index": index})

	if is_first_sight:
		_seed_first_sight_death_markers(macro_state, object_type, planned_slots, current_year, current_day)

	var individuals: Array = []
	for slot in planned_slots:
		var lot_pos: Vector2i = slot["lot_pos"]
		var index: int = slot["index"]
		if _is_blocked(macro_state, lot_pos, index, current_year):
			continue
		var key := Vector3i(lot_pos.x, lot_pos.y, index)
		# "or", non "and": i due dati sono indipendenti (un salvataggio precedente
		# all'introduzione del sottotipo congelato potrebbe avere l'anno di nascita ma non il
		# sottotipo) — ciascuno va completato per conto suo, mai saltato per intero solo perché
		# l'altro è già presente.
		if not birth_year_store.has(key) or not subtype_store.has(key):
			_freeze_new_individual(
				macro_state, object_type, key, lot_pos, index, current_year,
				birth_year_store, subtype_store, is_first_sight
			)
		individuals.append(key)
	return individuals


# Prima scoperta di una cella mai vista: invece di far nascere il 100% degli individui vivi (poco
# realistico — la mortalità aggregata gira su QUESTA cella ogni anno anche se nessuno la guarda, vedi
# ResourceMortalityService.apply_mortality che itera world.cells per intero), ne marca subito
# "morti" tanti quanti last_mortality_loss[object_type] indica essere morti nell'ultimo passaggio di
# mortalità (dato reale, già mantenuto ogni anno per OGNI cella del mondo, vista o no) — stessa
# esatta fonte/formula di NaturalMortalityVisualService.select_dying_individuals, qui con
# visible_fraction=1.0 perché una cella appena scoperta è per definizione vista al 100%. No-op se
# oggi cade fuori dalla finestra di visibilità stagionale (vedi SeasonCalculator.
# is_within_natural_death_visibility_window): fuori stagione nessuna cella del mondo, nota o nuova,
# mostra piante morte — coerenza totale, non solo un caso speciale per le celle nuove.
static func _seed_first_sight_death_markers(
	macro_state: MacroCellState, object_type: GameTypes.WorldObjectType, planned_slots: Array, current_year: int, current_day: int
) -> void:
	if not SeasonCalculator.is_within_natural_death_visibility_window(current_day):
		return
	var loss: int = int(macro_state.last_mortality_loss.get(object_type, 0))
	if loss <= 0 or planned_slots.is_empty():
		return
	macro_state.last_mortality_loss.erase(object_type)

	var marks_needed: int = min(loss, planned_slots.size())
	if marks_needed <= 0:
		return

	var shuffled: Array = planned_slots.duplicate()
	shuffled.shuffle()
	for i in range(marks_needed):
		var slot: Dictionary = shuffled[i]
		var key := Vector3i(slot["lot_pos"].x, slot["lot_pos"].y, slot["index"])
		macro_state.vegetation_death_exceptions[key] = {
			"origin_type": object_type,
			"death_year": current_year,
			"size_multiplier": 1.0,
		}


# Estensione (indice più alto mai assegnato + 1) per lotto, tra i soli lotti passati — un
# individuo conta come "noto" sia se ha un anno di nascita congelato (vivo) sia se occupa uno
# slot con un'eccezione di taglio/morte ancora attiva con origin_type == object_type (bloccato,
# ma lo slot resta comunque riservato). Un'eccezione con origin_type diverso NON allarga
# l'estensione per QUESTO tipo (il blocco è universale sullo slot, ma la proprietà del lotto/degli
# indici resta di chi lo ha originariamente occupato).
static func _count_known_extent_by_lot(
	macro_state: MacroCellState, object_type: GameTypes.WorldObjectType, lot_positions: Array, current_year: int
) -> Dictionary:
	var lot_set: Dictionary = {}
	for pos in lot_positions:
		lot_set[pos] = true

	var extent: Dictionary = {}
	var birth_year_store: Dictionary = _birth_year_store(macro_state, object_type)
	for key in birth_year_store.keys():
		var lot := Vector2i(key.x, key.y)
		if lot_set.has(lot):
			extent[lot] = max(int(extent.get(lot, 0)), key.z + 1)

	for exceptions in [macro_state.vegetation_cut_exceptions, macro_state.vegetation_death_exceptions]:
		for key in exceptions.keys():
			var entry: Dictionary = exceptions[key]
			if int(entry["origin_type"]) != object_type:
				continue
			var lot := Vector2i(key.x, key.y)
			if lot_set.has(lot):
				extent[lot] = max(int(extent.get(lot, 0)), key.z + 1)

	return extent


# Congela sottotipo ed eventualmente anno di nascita (solo per sottotipi con track_age_bands=true,
# stesso comportamento di sempre) per un individuo — i due dati sono completati INDIPENDENTEMENTE
# (vedi il chiamante): un individuo con l'anno già noto ma senza sottotipo (caso limite di
# compatibilità con salvataggi precedenti a questo campo) riceve solo il sottotipo mancante, mai
# un anno di nascita ricalcolato sopra quello già congelato. Sposta qui — dal renderer, dove
# viveva prima di questa sessione — la decisione perché ora deve avvenire una sola volta, alla
# nascita dell'individuo, non ad ogni render.
static func _freeze_new_individual(
	macro_state: MacroCellState,
	object_type: GameTypes.WorldObjectType,
	key: Vector3i,
	lot_pos: Vector2i,
	index: int,
	current_year: int,
	birth_year_store: Dictionary,
	subtype_store: Dictionary,
	is_first_sight: bool
) -> void:
	var subtype_name: String
	if subtype_store.has(key):
		subtype_name = subtype_store[key]
	else:
		subtype_name = _resolve_new_subtype(macro_state, object_type, lot_pos, index)
		subtype_store[key] = subtype_name

	if birth_year_store.has(key):
		return

	var subtype_rule := ResourceCalculator.get_subtype_rule(object_type, subtype_name)
	if subtype_rule == null or not subtype_rule.track_age_bands:
		return

	var birth_year: int
	if is_first_sight:
		var age_counts := macro_state.get_age_composition(object_type, subtype_name)
		var ratios: Array = [
			float(age_counts.get(GameTypes.AgeBand.YOUNG, 0)),
			float(age_counts.get(GameTypes.AgeBand.ADULT, 0)),
			float(age_counts.get(GameTypes.AgeBand.OLD, 0)),
		]
		var salt: Vector2i = TREE_AGE_SALT if object_type == GameTypes.WorldObjectType.TREE else SHRUB_AGE_SALT
		birth_year = AgeBandVisualService.compute_virtual_birth_year(
			lot_pos, salt, index, current_year,
			subtype_rule.youth_duration_years, subtype_rule.adult_duration_years, ratios
		)
	else:
		birth_year = current_year
	birth_year_store[key] = birth_year


static func _resolve_new_subtype(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType, lot_pos: Vector2i, index: int) -> String:
	match object_type:
		GameTypes.WorldObjectType.TREE:
			return _resolve_new_tree_subtype(macro_state, lot_pos, index)
		GameTypes.WorldObjectType.SHRUB:
			return _resolve_new_shrub_subtype(macro_state, lot_pos, index)
		_:
			return ""


# Stesse identiche soglie hash-vs-rapporto di prima (vedi ex MicroCellRenderer._is_tree_conifer/
# _is_tree_fruit_bearing/_is_tree_fruit_domesticable), solo ristrutturate come rami annidati
# invece di tre funzioni separate che ritestavano ciascuna la propria precondizione — nessun
# cambio di comportamento statistico.
static func _resolve_new_tree_subtype(macro_state: MacroCellState, pos: Vector2i, index: int) -> String:
	var conifer_ratio := ResourceCalculator.get_subtype_ratio(GameTypes.WorldObjectType.TREE, macro_state, "conifer")
	var conifer_hash: float = float(hash(pos * 11 + TREE_CONIFER_SALT + Vector2i(index * 293, index * 41)) % 100000) / 100000.0
	if conifer_hash < conifer_ratio:
		return "conifer"

	var non_conifer_share: float = 1.0 - conifer_ratio
	if non_conifer_share <= 0.0:
		return "wood_only"

	var wild_fruit_ratio := ResourceCalculator.get_subtype_ratio(GameTypes.WorldObjectType.TREE, macro_state, "wild_fruit")
	var domesticable_fruit_ratio := ResourceCalculator.get_subtype_ratio(GameTypes.WorldObjectType.TREE, macro_state, "domesticable_fruit")
	var fruit_hash: float = float(hash(pos * 3 + TREE_FRUIT_BEARING_SALT + Vector2i(index * 71, index * 197)) % 100000) / 100000.0
	if fruit_hash >= ((wild_fruit_ratio + domesticable_fruit_ratio) / non_conifer_share):
		return "wood_only"

	var total_fruit_ratio: float = wild_fruit_ratio + domesticable_fruit_ratio
	if total_fruit_ratio <= 0.0:
		return "wild_fruit"
	var domesticable_hash: float = float(hash(pos * 5 + TREE_FRUIT_DOMESTICABLE_SALT + Vector2i(index * 113, index * 29)) % 100000) / 100000.0
	return "domesticable_fruit" if domesticable_hash < (domesticable_fruit_ratio / total_fruit_ratio) else "wild_fruit"


static func _resolve_new_shrub_subtype(macro_state: MacroCellState, pos: Vector2i, index: int) -> String:
	var fruit_ratio := ResourceCalculator.get_subtype_ratio(GameTypes.WorldObjectType.SHRUB, macro_state, "fruit_bearing")
	var hash_value: float = float(hash(pos * 3 + SHRUB_FRUIT_BEARING_SALT + Vector2i(index * 181, index * 67)) % 100000) / 100000.0
	return "fruit_bearing" if hash_value < fruit_ratio else "wood_only"


static func _birth_year_store(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType) -> Dictionary:
	return macro_state.tree_virtual_birth_year if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_virtual_birth_year


static func _subtype_store(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType) -> Dictionary:
	return macro_state.tree_individual_subtype if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_individual_subtype


static func _claimed_lots_store(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType) -> Dictionary:
	return macro_state.tree_claimed_lots if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_claimed_lots


# Svuota l'identità "ordinaria" (individui vivi/mai toccati) di object_type per questa macrocella
# — usata da GameScene quando il FogOfWarMemory di una macrocella non più viva diventa
# completamente vuoto (vedi GameScene._forget_vegetation_identity), MAI da un punto della
# generazione normale. NON tocca vegetation_cut_exceptions/vegetation_death_exceptions: un
# individuo tagliato o morto è già stato rimosso da questi tre dizionari nell'istante stesso del
# taglio/morte (vedi PlayerHarvestService.cut_individual/NaturalMortalityVisualService.
# kill_individual, entrambi fanno birth_year_store.erase(key)) — le due eccezioni vivono altrove e
# hanno le proprie scadenze indipendenti (8/2 anni per il taglio, azzeramento stagionale in
# blocco per la morte naturale), mai influenzate da questa pulizia. Al prossimo ingresso in questa
# macrocella, claimed_lots vuoto fa scattare is_first_sight come per una cella mai vista prima:
# nessun codice di rigenerazione dedicato, si riusa la stessa identica macchina.
static func forget_known_individuals(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType) -> void:
	_birth_year_store(macro_state, object_type).clear()
	_subtype_store(macro_state, object_type).clear()
	_claimed_lots_store(macro_state, object_type).clear()


# Blocco UNIFICATO e universale (vedi MacroCellState.vegetation_cut_exceptions/
# vegetation_death_exceptions): indipendente da object_type, valido per qualunque tipo stia
# interrogando — "questo slot ha un blocco attivo?", non "è escluso PER IL MIO TIPO?". Le due cause
# usano però test di attività diversi (vedi commento in testa al file): il taglio scade per anni
# trascorsi, la morte naturale è attiva per pura presenza (azzerata altrove in blocco).
static func _is_blocked(macro_state: MacroCellState, lot_pos: Vector2i, index: int, current_year: int) -> bool:
	var key := Vector3i(lot_pos.x, lot_pos.y, index)
	if _is_cut_entry_active(macro_state.vegetation_cut_exceptions.get(key), current_year):
		return true
	if macro_state.vegetation_death_exceptions.has(key):
		return true
	return false


static func _is_cut_entry_active(entry, current_year: int) -> bool:
	if entry == null:
		return false
	var reentry_years: int = REENTRY_YEARS_BY_TYPE.get(int(entry["origin_type"]), 0)
	return current_year - int(entry["cut_year"]) < reentry_years


# Rimuove le entry di TAGLIO la cui finestra di rientro è passata — nessun costo di realismo
# (un'eccezione scaduta non fa già più nulla via _is_blocked), solo pulizia di dati altrimenti mai
# liberati. Filtrata per origin_type == object_type: chiamata una volta per TREE e una per SHRUB
# (vedi generate_positions), le due chiamate coprono insieme ogni origine possibile senza
# rielaborare due volte le stesse entry. Nessun equivalente per la morte naturale: quelle entry
# vengono azzerate in blocco da WorldTimeService._clear_natural_death_markers, mai scadute una per
# una qui.
static func _prune_expired_cut_exceptions(exceptions: Dictionary, object_type: GameTypes.WorldObjectType, current_year: int) -> void:
	var expired_keys: Array = []
	for key in exceptions.keys():
		var entry: Dictionary = exceptions[key]
		if int(entry["origin_type"]) != object_type:
			continue
		if not _is_cut_entry_active(entry, current_year):
			expired_keys.append(key)
	for key in expired_keys:
		exceptions.erase(key)


# Individui tagliati attualmente bloccati, filtrati per origin_type — usato da GameScene/
# MacroCellScene per alimentare MicroCellRenderer.set_cut_positions (il marker "tronco mozzato" da
# disegnare sopra lo slot bloccato). Ritorna Array[Dictionary] — {"key": Vector3i,
# "size_multiplier": float, "event_year": int} — non il solo Vector3i: il renderer deve poter
# disegnare il marker alla stessa dimensione che l'individuo aveva al momento del taglio (congelata
# lì da PlayerHarvestService.cut_individual) senza dover rileggere sottotipo/età, che a quel punto
# sono già stati dimenticati.
static func get_cut_positions(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType, current_year: int) -> Array:
	var result: Array = []
	for key in macro_state.vegetation_cut_exceptions.keys():
		var entry: Dictionary = macro_state.vegetation_cut_exceptions[key]
		if int(entry["origin_type"]) != object_type:
			continue
		if _is_cut_entry_active(entry, current_year):
			result.append({
				"key": key,
				"size_multiplier": float(entry.get("size_multiplier", 1.0)),
				"event_year": int(entry["cut_year"]),
			})
	return result


# Individui morti naturalmente attualmente marcati — stesso formato di get_cut_positions sopra, ma
# SENZA test di scadenza per anno: ogni entry qui presente È per definizione attiva (la finestra di
# visibilità è interamente calendariale, vedi SeasonCalculator.is_within_natural_death_visibility_
# window/_seed_first_sight_death_markers), azzerata in blocco al checkpoint di growth — non
# richiede più current_year, a differenza di get_cut_positions.
static func get_dead_positions(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType) -> Array:
	var result: Array = []
	for key in macro_state.vegetation_death_exceptions.keys():
		var entry: Dictionary = macro_state.vegetation_death_exceptions[key]
		if int(entry["origin_type"]) != object_type:
			continue
		result.append({
			"key": key,
			"size_multiplier": float(entry.get("size_multiplier", 1.0)),
			"event_year": int(entry["death_year"]),
		})
	return result


# Priorità di spareggio per il resto della divisione — invariata rispetto a prima di questa
# sessione, salt indipendente da ResourcePositionService._priority_hash (stessa filosofia di
# decorrelazione: quali lotti ricevono l'individuo "in più" non è correlato a quali lotti il BFS
# ha scelto per primi in ordine di priorità).
static func _remainder_priority_hash(pos: Vector2i, noise_seed: int) -> float:
	return float(hash(pos * 13 + Vector2i(noise_seed, 4243)) % 100000) / 100000.0


static func _sorted_by_remainder_priority(lot_positions: Array, noise_seed: int) -> Array:
	var decorated: Array = []
	for pos in lot_positions:
		decorated.append([_remainder_priority_hash(pos, noise_seed), pos])
	decorated.sort_custom(func(a, b): return a[0] < b[0])

	var sorted_lots: Array = []
	for pair in decorated:
		sorted_lots.append(pair[1])
	return sorted_lots
