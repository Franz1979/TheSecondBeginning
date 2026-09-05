class_name MacroCellState
extends RefCounted

const TOTAL_SPACE: int = 10000

var x: int
var y: int
var micro_seed: int
var resource_quantity: Dictionary = {}
var dedicated_space: Dictionary = {}
# WorldObjectType -> bool. Fatto storico permanente, mai azzerato: true dal primo momento in cui
# dedicated_space[type] diventa > 0 in questa cella (generazione iniziale, growth, encroachment o
# migrazione — vedi set_dedicated_space sotto, unico punto di scrittura di dedicated_space).
# Usato solo dal floor di ricrescita minima (seed-rain) in ResourceGrowthService, per distinguere
# una cella temporaneamente svuotata (qui il floor si applica) da una radura mai popolata per
# quella risorsa dal world generator (il floor NON deve mai forzare crescita lì).
var has_ever_grown: Dictionary = {}
var subtype_composition: Dictionary = {} # WorldObjectType -> Dictionary[String subtype_name, int space_count]
# WorldObjectType -> Dictionary[String subtype_name, Dictionary[AgeBand, int space_count]].
# Popolato solo per i sottotipi con SubtypeRules.track_age_bands=true (oggi solo SHRUB); vuoto
# altrove, stesso idioma "vuoto = non tracciato" di subtype_composition per GRASS. Invariante:
# sum(age_composition[type][subtype].values()) == subtype_composition[type][subtype] sempre —
# ogni chiamante che tocca subtype_composition per un sottotipo age-tracked deve aggiornare
# anche age_composition nella stessa operazione (vedi add_age_band_gain/apply_age_band_loss).
var age_composition: Dictionary = {}
var river_space: int = 0
# Budget separato per risorse acquatiche (oggi solo FISH), mai sommato in
# get_total_dedicated_space()/get_empty_space(): l'acqua non compete mai con lo spazio
# terrestre, esiste solo entro la capacità restituita da
# ResourceCalculator.get_water_capacity_space() (TOTAL_SPACE per SEA/LAKE, river_space per RIVER).
var water_dedicated_space: Dictionary = {}
# Budget separato per fauna terrestre "passiva" (oggi solo BIRDS), stesso principio di
# water_dedicated_space sopra: mai sommato in get_total_dedicated_space()/get_empty_space(),
# esiste solo entro la capacità restituita da ResourceCalculator.get_land_capacity_space()
# (TOTAL_SPACE - river_space per terrain non-WATER) — non compete con TREE/GRASS/SHRUB/ROCK per
# lo stesso spazio fisico, esattamente come FISH non compete con la vegetazione.
var terrestrial_dedicated_space: Dictionary = {}
var active_growth_bonuses: Dictionary = {} # NaturalEventType -> {multiplier: float, trigger_absolute_day: int, duration_years: int}
# Surplus di crescita non piazzato dall'encroachment a fine primavera, in attesa che il
# checkpoint di inizio primavera dell'anno successivo lo trasformi in trasferimenti verso le
# celle vicine (vedi WorldTimeService). WorldObjectType -> quantità di surplus.
var pending_migration_surplus: Dictionary = {}
var stone_positions: Array = [] # Array[Vector2i], posizioni microcella occupate da stone (100x100)
var stone_positions_generated: bool = false # separato dall'array vuoto: distingue "mai aperta" da "aperta ma senza stone"
# LOD0 (2026-08-30): true dal primo momento in cui questa macrocella entra nel set di celle vive
# VERE (LODOrchestrator.set_focus_region, vedi world.lod_focus_live_cells) — MAI più rimesso a
# false, stesso principio "fatto storico permanente" di has_ever_grown sopra. È l'UNICO dato che
# guida il livello LOD di ogni PopulationGroup il cui territorio include questa cella (LEVEL_0 se
# NESSUNA cella del territorio ha mai questo flag a true, LEVEL_1 se almeno una ce l'ha ma nessuna
# è viva ORA, LEVEL_2 se almeno una è viva ORA) — DELIBERATAMENTE mai marcato da altro (vedi
# vegetation_feeding_active sotto per il perché): se bastasse "una cella qualunque del mio
# territorio è comunque diventata nota" per salire a LEVEL_1, un gruppo il cui territorio si
# sovrappone per puro caso a quello di un erbivoro attivo salirebbe a LEVEL_1 senza aver MAI
# toccato lui stesso una cella viva — un contagio scoperto in sessione (LEVEL_1 deve restare
# raggiungibile SOLO per retrocessione da LEVEL_2, mai per "prossimità" ad altri).
var has_ever_been_discovered: bool = false
# LOD0 (2026-08-30), SEPARATO da has_ever_been_discovered sopra apposta — vedi lì per il perché
# della separazione. True quando questa cella fa parte del territorio di un erbivoro (mai un
# predatore: la caccia legge population/get_population_by_cell, mai dedicated_space, non le serve
# vegetazione attiva) che diventa LEVEL_2 — marca l'INTERO territorio dell'erbivoro (fino a decine
# di celle, es. aurochs), non solo la cella viva vera, altrimenti le altre celle del suo territorio
# (dove comunque mangia ogni giorno, vedi AnimalConsumptionService._consume_group che itera tutto
# occupied_macrocells) resterebbero congelate per sempre — niente ricrescita, fame reale senza
# scampo. Consultato SOLO da LODOrchestrator.is_vegetation_frozen (mai dalla classificazione
# popolazioni sopra): governa se la vegetazione può crescere qui, non se qualcuno è "scoperto".
# MAI più rimesso a false, stesso principio "fatto storico permanente" degli altri due flag.
var vegetation_feeding_active: bool = false
# LOD0/consumo (2026-09-05, richiesta utente): "fotografia" di dedicated_space[GRASS] catturata la
# PRIMA volta che questa cella, pur congelata (is_vegetation_frozen), entra a far parte del
# territorio di una popolazione erbivora Livello 1/2 attiva — vedi WorldTimeService (checkpoint di
# inizio stagione, PRIMA del consumo aggregato: in quel momento il valore coincide sempre con
# quello di semina, perché il consumo Livello 1 è solo a checkpoint, mai giornaliero, quindi nulla
# può averlo eroso prima). -1 = mai catturato (sentinella, stesso idioma di altri campi "non ancora
# valorizzato" nel progetto). Serve a "far ricrescere" il grass una volta l'anno (checkpoint di
# crescita, fine primavera) SENZA calcolare la vera crescita nella cella (resta congelata per
# quello): il consumo stagionale continua a intaccare dedicated_space[GRASS] per davvero (fame/
# mortalità/split restano sensibili alla scarsità reale), ma ogni anno la cella torna a questo
# valore invece di restare erosa per sempre — altrimenti forage diventerebbe un pareggio
# indefinito verso zero senza mai recuperare, dato che qui la vera crescita non gira.
var grass_seed_baseline: int = -1
# Vector3i (x, y lotto + indice individuo locale) -> {"origin_type": GameTypes.WorldObjectType,
# "cut_year": int}. Fatto storico reale (non ricalcolabile), stesso principio di stone_positions:
# a differenza di GRASS/SHRUB/TREE aggregati (mai persistiti, rigenerati da zero ad ogni apertura/
# anno), una posizione tagliata deve restare esclusa dalla rigenerazione anche se l'algoritmo di
# posizionamento (deterministico, stesso seed) la sceglierebbe di nuovo — altrimenti un albero
# "tagliato" ricomparirebbe identico l'anno successivo come se nulla fosse successo. BLOCCO
# UNIFICATO (non selettivo per tipo): finché il blocco è attivo, quella posizione-individuo è
# terreno bloccato per QUALUNQUE tipo di vegetazione, non solo origin_type — decisione esplicita:
# un taglio è un disturbo del terreno (ceppo/radura), non un "posto libero per un tipo diverso".
# origin_type serve solo a scegliere la finestra di rientro giusta
# (IndividualVegetationService.REENTRY_YEARS_BY_TYPE), non limita quali tipi restano bloccati.
# Consumata da IndividualVegetationService (TREE/SHRUB, a livello di singolo indice) e da
# VegetationPositionService (GRASS, a livello di intero lotto — GRASS non ha identità
# individuale, un blocco su un solo indice esclude l'intera microcella per lei, vedi
# _exclude_blocked_lots). Scaduta viene rimossa immediatamente (nessun costo di realismo, vedi
# IndividualVegetationService._prune_expired_cut_exceptions), non solo ignorata. Scritte da
# PlayerHarvestService.cut_individual (unico chiamante che scrive qui, tramite il bottone "Cut" di
# VegetationInfoPanel in GameScene).
var vegetation_cut_exceptions: Dictionary = {}
# Vector3i (x, y lotto + indice individuo locale) -> anno di nascita virtuale. Fatto storico reale
# una volta fissato (stesso principio di vegetation_cut_exceptions sopra): il congelamento avviene
# in IndividualVegetationService._freeze_new_individual (nascita dell'individuo — stima con
# AgeBandVisualService.compute_virtual_birth_year dai ratio young/adult/old correnti se è la prima
# volta in assoluto che questa cella viene vista, altrimenti anno corrente = crescita di
# quest'anno), mai più da MicroCellRenderer (che qui si limita a leggere, vedi
# _resolve_age_band_and_size) — scrittura diretta qui perché il Dictionary passato al renderer via
# set_tree_age_params/set_shrub_age_params è lo stesso oggetto (i Dictionary in GDScript sono
# sempre per riferimento), sopravvivendo così a save/load e alla ricreazione dell'istanza renderer
# nello streaming multi-cella. NESSUNA potatura automatica in questo step (deliberato, vedi
# IndividualVegetationService): una posizione che smette di esistere (morte/migrazione) resta
# comunque nota finché non verrà gestita esplicitamente — la mortalità a granularità
# per-individuo è lavoro futuro, non ancora implementato.
var tree_virtual_birth_year: Dictionary = {}
var shrub_virtual_birth_year: Dictionary = {}
# Sottotipo congelato per individuo (TREE/SHRUB) — vedi IndividualVegetationService: deciso UNA
# SOLA volta quando l'individuo viene generato per la prima volta, mai più ricalcolato da un
# rapporto corrente (a differenza del vecchio comportamento, che lo ritestava ad ogni render e
# poteva "cambiare specie" se le proporzioni della cella si spostavano nel frattempo). Stessa
# chiave Vector3i e stesso principio "Dictionary per riferimento" di tree_virtual_birth_year sopra
# (vedi MicroCellRenderer.set_tree_subtypes/set_shrub_subtypes).
var tree_individual_subtype: Dictionary = {}
var shrub_individual_subtype: Dictionary = {}
# Lotti (Vector2i, spazio microcella 0..99) già "rivendicati per sempre" da questo tipo, una volta
# scelti dal motore procedurale — mai rimossi in questo step (la mortalità/lo sgretolamento del
# territorio noto restano fuori scope, vedi IndividualVegetationService). Garantisce che un lotto
# resti lo stesso anche quando il suo unico individuo noto perde temporaneamente identità
# (tagliato o morto: l'eccezione blocca lo SLOT, non il lotto — vedi
# IndividualVegetationService._is_blocked), evitando che il lotto torni "libero" e magari
# riassegnato altrove non appena l'eccezione scade.
var tree_claimed_lots: Dictionary = {}
var shrub_claimed_lots: Dictionary = {}
# Stesso formato di vegetation_cut_exceptions sopra (origin_type/size_multiplier), ma per la
# mortalità naturale invece del taglio del giocatore — con una finestra di non-ricrescita di natura
# DIVERSA, per decisione esplicita: il taglio è un'azione deliberata (bloccata per anni, vedi
# REENTRY_YEARS_BY_TYPE), la morte naturale è solo un artificio grafico stagionale — "morto" da fine
# autunno (checkpoint di mortalità) a fine primavera (checkpoint di growth), poi azzerata in BLOCCO
# per l'intero mondo da WorldTimeService._clear_natural_death_markers (mai scaduta entry per entry
# per anno, vedi SeasonCalculator.is_within_natural_death_visibility_window). Scritte da
# NaturalMortalityVisualService.kill_individual (mortalità su una cella già nota — vedi
# last_mortality_loss sotto per come sceglie quali individui) E da IndividualVegetationService.
# _seed_first_sight_death_markers (prima scoperta di una cella mai vista: anche lì una quota
# realistica nasce già "morta", dalla stessa fonte last_mortality_loss — la mortalità aggregata gira
# su ogni cella ogni anno indipendentemente da essere vista o meno).
var vegetation_death_exceptions: Dictionary = {}
# WorldObjectType -> int: quanti individui ResourceMortalityService ha TOLTO IN AGGREGATO
# quest'anno per quel tipo (già applicato a dedicated_space/resource_quantity, vedi
# _apply_mortality_in_cell) — un valore "da consumare", non un fatto storico. Scritto per OGNI
# cella del mondo ogni anno, vista o no (ResourceMortalityService itera world.cells per intero), non
# solo per quelle vive — proprietà sfruttata da entrambi i consumatori: NaturalMortalityVisualService
# .select_dying_individuals lo legge e lo cancella per decidere quanti (e quali, tra i noti visti dal
# fog of war) individui di una cella GIÀ NOTA ricevono un marker "morto"; IndividualVegetationService
# ._seed_first_sight_death_markers lo legge (e cancella) allo stesso modo per una cella MAI vista
# prima — stesso dato, stessa formula, letto ovunque per la prima volta la cella smette di essere
# "vuota" di individui noti. Deliberatamente NON persistito su salvataggio: se non viene consumato
# entro la sessione l'anno successivo lo sovrascrive comunque — stessa inconsistenza già accettata
# altrove per il territorio non osservato, non un dato la cui perdita comprometta la simulazione
# aggregata (quella è già applicata a prescindere da questo campo).
var last_mortality_loss: Dictionary = {}
# Stock persistente delle fonti caloriche con consuming_depletes_primary = false (es. bacche
# mature): resource_name (CaloricSourceRules.caloric_source_name) -> quantità (float). Vuoto per
# le fonti stateless come FORAGE, che non ne hanno bisogno. Vedi CaloricCalculator.update_secondary_resource_stock.
var secondary_resource_stock: Dictionary = {}
# Debito frazionario di spazio GRASS da rimuovere per consumo animale: il consumo giornaliero
# convertito in "spazio equivalente" (unità/densità) è quasi sempre < 1 unità intera — invece
# di arrotondare e perdere la frazione ogni giorno, si accumula qui finché non supera 1.0 (vedi
# AnimalConsumptionService), momento in cui dedicated_space[GRASS] viene davvero decrementato.
var pending_grass_space_debt: float = 0.0
# Stesso meccanismo di pending_grass_space_debt sopra, per le altre due fonti a consumo diretto
# (consuming_depletes_primary = true, nessuno stock proprio — vedi CaloricSourceRules):
# fish_meat decrementa water_dedicated_space[FISH], bird_meat decrementa
# terrestrial_dedicated_space[BIRDS]. Campi separati (non un Dictionary unico) per restare
# coerenti con lo schema già in uso per GRASS — nessun consumatore reale li tocca ancora (vedi
# AnimalConsumptionService._consume_fish_meat/_consume_bird_meat).
var pending_fish_space_debt: float = 0.0
var pending_bird_space_debt: float = 0.0

func _init(_x: int, _y: int) -> void:
	x = _x
	y = _y
	micro_seed = hash(str(x) + "_" + str(y))

func get_resource_quantity(object_type: GameTypes.WorldObjectType) -> int:
	return int(resource_quantity.get(object_type, 0))

func set_resource_quantity(object_type: GameTypes.WorldObjectType, amount: int) -> void:
	resource_quantity[object_type] = max(amount, 0)

func add_resource_quantity(object_type: GameTypes.WorldObjectType, amount: int) -> void:
	set_resource_quantity(object_type, get_resource_quantity(object_type) + amount)

func get_dedicated_space(object_type: GameTypes.WorldObjectType) -> int:
	return int(dedicated_space.get(object_type, 0))

func set_dedicated_space(object_type: GameTypes.WorldObjectType, amount: int) -> void:
	var clamped: int = max(amount, 0)
	dedicated_space[object_type] = clamped
	if clamped > 0:
		has_ever_grown[object_type] = true

func has_resource_ever_grown(object_type: GameTypes.WorldObjectType) -> bool:
	return bool(has_ever_grown.get(object_type, false))

func get_subtype_composition(object_type: GameTypes.WorldObjectType) -> Dictionary:
	return subtype_composition.get(object_type, {})

func get_subtype_count(object_type: GameTypes.WorldObjectType, subtype_name: String) -> int:
	return int(get_subtype_composition(object_type).get(subtype_name, 0))

func set_subtype_count(object_type: GameTypes.WorldObjectType, subtype_name: String, amount: int) -> void:
	if not subtype_composition.has(object_type):
		subtype_composition[object_type] = {}
	subtype_composition[object_type][subtype_name] = max(amount, 0)

func get_subtype_total(object_type: GameTypes.WorldObjectType) -> int:
	var total := 0
	for amount in get_subtype_composition(object_type).values():
		total += int(amount)
	return total

# Distribuisce (delta > 0) o sottrae (delta < 0) una quantità assoluta di dedicated_space
# tra i sottotipi di object_type, mantenendo sum(subtype_composition) sempre allineato a
# dedicated_space. Di default (weights vuoto) i pesi sono la composizione locale già presente
# (un sottotipo a 0 localmente resta a 0). weights esplicito è usato da:
# - migrazione, che porta con sé la composizione della cella di origine invece di quella
#   locale (già filtrata per idoneità dal chiamante prima di arrivare qui), su delta positivo;
# - growth/encroachment (guadagno) e mortality (perdita), che pesano la composizione locale
#   per il moltiplicatore di idoneità al bioma di ciascun sottotipo (diretto per i guadagni,
#   invertito per le perdite — vedi ResourceCalculator.get_biome_weighted_subtype_composition),
#   invece della sola proporzione locale grezza.
# Se object_type non ha sottotipi registrati (nessun SubtypeRules), la funzione non fa nulla:
# stesso comportamento di oggi per GRASS/TREE finché non verranno anch'essi estesi.
func apply_subtype_space_delta(object_type: GameTypes.WorldObjectType, delta: int, weights: Dictionary = {}) -> Dictionary:
	if delta == 0:
		return {}

	if delta > 0:
		var source_weights: Dictionary = weights if not weights.is_empty() else get_subtype_composition(object_type)
		if source_weights.is_empty():
			return {}
		var split := _split_by_weight(source_weights, delta)
		for subtype_name in split.keys():
			set_subtype_count(object_type, subtype_name, get_subtype_count(object_type, subtype_name) + split[subtype_name])
		return split
	else:
		var composition := get_subtype_composition(object_type)
		if composition.is_empty():
			return {}
		var loss: int = min(-delta, get_subtype_total(object_type))
		if loss <= 0:
			return {}
		# Un peso esterno (es. inverso del moltiplicatore di bioma) può "chiedere" a un
		# sottotipo più di quanto possiede davvero, soprattutto quando è già quasi esaurito:
		# _split_by_weight_capped ridistribuisce l'eccedenza sui sottotipi non ancora saturi
		# invece di sforare. Se weights è vuoto, source_weights coincide con composition e il
		# capping non scatta mai (comportamento identico a prima, self-limiting per costruzione).
		var source_weights: Dictionary = weights if not weights.is_empty() else composition
		var split := _split_by_weight_capped(source_weights, composition, loss)
		for subtype_name in split.keys():
			set_subtype_count(object_type, subtype_name, get_subtype_count(object_type, subtype_name) - split[subtype_name])
		return split

# Ripartisce amount (intero) tra le chiavi di weights in proporzione al loro peso relativo,
# con arrotondamento "largest remainder" così la somma delle parti risulta sempre esattamente
# amount (mai perso/guadagnato per arrotondamento indipendente di ogni singola quota).
static func _split_by_weight(weights: Dictionary, amount: int) -> Dictionary:
	var shares: Dictionary = {}
	if amount <= 0:
		return shares

	var weight_total := 0.0
	for value in weights.values():
		weight_total += float(value)
	if weight_total <= 0.0:
		return shares

	var assigned := 0
	var remainders: Array = []
	for key in weights.keys():
		var exact: float = float(amount) * float(weights[key]) / weight_total
		var base: int = int(floor(exact))
		shares[key] = base
		assigned += base
		remainders.append({"key": key, "remainder": exact - base})

	var missing: int = amount - assigned
	if missing > 0:
		remainders.sort_custom(func(a, b): return a["remainder"] > b["remainder"])
		for i in range(missing):
			var key = remainders[i % remainders.size()]["key"]
			shares[key] += 1

	return shares

# Come _split_by_weight, ma nessuna chiave può ricevere più del proprio tetto in caps (qui
# sempre la composizione reale del sottotipo: non si può sottrarre più di quanto esiste). Se il
# peso proporzionale di una chiave supererebbe il suo tetto, la chiave viene saturata al tetto e
# l'eccedenza si ridistribuisce (stesso criterio di peso) sulle chiavi non ancora sature —
# "water-filling" iterativo. Il chiamante garantisce amount <= somma dei tetti, quindi una
# soluzione esiste sempre e il ciclo termina. Se weights coincide già con caps (caso di oggi,
# nessun peso esterno) nessuna chiave può mai saturare prima del normale completamento: degenera
# esattamente in _split_by_weight.
static func _split_by_weight_capped(weights: Dictionary, caps: Dictionary, amount: int) -> Dictionary:
	var shares: Dictionary = {}
	for key in weights.keys():
		shares[key] = 0
	if amount <= 0:
		return shares

	var remaining_amount := amount
	var active_weights := weights.duplicate()

	while remaining_amount > 0 and not active_weights.is_empty():
		var split := _split_by_weight(active_weights, remaining_amount)
		var saturated: Array = []
		for key in split.keys():
			var cap_remaining: int = int(caps.get(key, 0)) - shares[key]
			if split[key] >= cap_remaining:
				shares[key] += cap_remaining
				remaining_amount -= cap_remaining
				saturated.append(key)

		if saturated.is_empty():
			for key in split.keys():
				shares[key] += split[key]
			remaining_amount = 0
		else:
			for key in saturated:
				active_weights.erase(key)

	return shares

func get_age_composition(object_type: GameTypes.WorldObjectType, subtype_name: String) -> Dictionary:
	if not age_composition.has(object_type):
		return {}
	return age_composition[object_type].get(subtype_name, {})

func get_age_count(object_type: GameTypes.WorldObjectType, subtype_name: String, age_band: GameTypes.AgeBand) -> int:
	return int(get_age_composition(object_type, subtype_name).get(age_band, 0))

func set_age_count(object_type: GameTypes.WorldObjectType, subtype_name: String, age_band: GameTypes.AgeBand, amount: int) -> void:
	if not age_composition.has(object_type):
		age_composition[object_type] = {}
	if not age_composition[object_type].has(subtype_name):
		age_composition[object_type][subtype_name] = {}
	age_composition[object_type][subtype_name][age_band] = max(amount, 0)

func get_age_total(object_type: GameTypes.WorldObjectType, subtype_name: String) -> int:
	var total := 0
	for amount in get_age_composition(object_type, subtype_name).values():
		total += int(amount)
	return total

# Gain sempre e solo in YOUNG: growth/encroachment (lato vincente)/migration non spostano mai
# individui già adulti, sono tutti fenomeni di nuova crescita/dispersione semi. Il chiamante
# (i service) decide SE chiamarla, in base a SubtypeRules.track_age_bands — qui nessuna verifica,
# puro meccanismo.
func add_age_band_gain(object_type: GameTypes.WorldObjectType, subtype_name: String, amount: int) -> void:
	if amount <= 0:
		return
	set_age_count(object_type, subtype_name, GameTypes.AgeBand.YOUNG,
		get_age_count(object_type, subtype_name, GameTypes.AgeBand.YOUNG) + amount)

# Usato SOLO dal seeding iniziale (InitialResourceSetupService, SubtypeRules.initial_age_ratio):
# a differenza del gain corrente in game (sempre YOUNG, sopra), un mondo nuovo può partire con
# una distribuzione già "stabilita" tra le tre fasce. Riusa lo stesso _split_by_weight generico.
func seed_age_band_composition(object_type: GameTypes.WorldObjectType, subtype_name: String, amount: int, weights: Dictionary) -> void:
	if amount <= 0 or weights.is_empty():
		return
	var split := _split_by_weight(weights, amount)
	for age_band in split.keys():
		set_age_count(object_type, subtype_name, age_band,
			get_age_count(object_type, subtype_name, age_band) + split[age_band])

# Perdita ripartita tra le fasce: se `shares` è vuoto, usa la composizione età locale come pesi
# (proporzione pura — stesso default di apply_subtype_space_delta, usato da encroachment lato
# perdente e distruzione da eventi naturali: non è un giudizio di età, solo territorio/eventi
# bruti). Se esplicito (es. SubtypeRules.mortality_share_by_age), quei pesi guidano la
# ripartizione — usato da ResourceMortalityService. _split_by_weight_capped gestisce già il caso
# in cui una fascia non abbia abbastanza unità per la propria quota, ridistribuendo l'eccedenza
# (water-filling) sulle fasce non ancora sature: nessun residuo perso, una soluzione esiste
# sempre perché il chiamante garantisce amount <= totale reale del sottotipo.
func apply_age_band_loss(object_type: GameTypes.WorldObjectType, subtype_name: String, amount: int, shares: Dictionary = {}) -> void:
	if amount <= 0:
		return
	var composition := get_age_composition(object_type, subtype_name)
	if composition.is_empty():
		return
	var loss: int = min(amount, get_age_total(object_type, subtype_name))
	if loss <= 0:
		return
	var source_weights: Dictionary = shares if not shares.is_empty() else composition
	var split := _split_by_weight_capped(source_weights, composition, loss)
	for age_band in split.keys():
		set_age_count(object_type, subtype_name, age_band,
			get_age_count(object_type, subtype_name, age_band) - split[age_band])

# Maturazione annuale: young->adult dopo youth_duration_years, adult->old dopo
# adult_duration_years — durate PROPRIE di ciascuna fascia, indipendenti tra loro (non soglie
# cumulative di età dalla nascita). Entrambe le transizioni calcolate sulla composizione di
# INIZIO checkpoint (non incatenate): un individuo avanza al massimo di una fascia per anno, mai
# due nello stesso ciclo. Frazione 1/N per anno (residenza media statistica, non un tracking di
# coorte per anno di nascita — coerente con lo stile aggregato già usato altrove, es.
# mortalità/crescita a moltiplicatore). Chiamata da ResourceAgeBandService PRIMA di
# growth/encroachment nello stesso checkpoint di fine primavera, così le nuove nascite di
# quest'anno (età 0) non vengono mai incluse nella maturazione dello stesso ciclo in cui
# compaiono.
func apply_age_band_maturation(object_type: GameTypes.WorldObjectType, subtype_name: String, youth_duration_years: int, adult_duration_years: int) -> void:
	var young_count := get_age_count(object_type, subtype_name, GameTypes.AgeBand.YOUNG)
	var adult_count := get_age_count(object_type, subtype_name, GameTypes.AgeBand.ADULT)
	if young_count <= 0 and adult_count <= 0:
		return

	var young_to_adult: int = 0
	if youth_duration_years > 0:
		young_to_adult = min(int(round(float(young_count) / float(youth_duration_years))), young_count)

	var adult_to_old: int = 0
	if adult_duration_years > 0:
		adult_to_old = min(int(round(float(adult_count) / float(adult_duration_years))), adult_count)

	if young_to_adult <= 0 and adult_to_old <= 0:
		return

	set_age_count(object_type, subtype_name, GameTypes.AgeBand.YOUNG, young_count - young_to_adult)
	set_age_count(object_type, subtype_name, GameTypes.AgeBand.ADULT, adult_count - adult_to_old + young_to_adult)
	set_age_count(object_type, subtype_name, GameTypes.AgeBand.OLD,
		get_age_count(object_type, subtype_name, GameTypes.AgeBand.OLD) + adult_to_old)

func get_secondary_resource_stock(resource_name: String) -> float:
	return float(secondary_resource_stock.get(resource_name, 0.0))

func set_secondary_resource_stock(resource_name: String, amount: float) -> void:
	secondary_resource_stock[resource_name] = max(amount, 0.0)

func get_pending_grass_space_debt() -> float:
	return pending_grass_space_debt

func set_pending_grass_space_debt(amount: float) -> void:
	pending_grass_space_debt = max(amount, 0.0)

func get_pending_fish_space_debt() -> float:
	return pending_fish_space_debt

func set_pending_fish_space_debt(amount: float) -> void:
	pending_fish_space_debt = max(amount, 0.0)

func get_pending_bird_space_debt() -> float:
	return pending_bird_space_debt

func set_pending_bird_space_debt(amount: float) -> void:
	pending_bird_space_debt = max(amount, 0.0)

func get_river_space() -> int:
	return river_space

func set_river_space(amount: int) -> void:
	river_space = max(amount, 0)

func get_water_space(object_type: GameTypes.WorldObjectType) -> int:
	return int(water_dedicated_space.get(object_type, 0))

func set_water_space(object_type: GameTypes.WorldObjectType, amount: int) -> void:
	water_dedicated_space[object_type] = max(amount, 0)

func get_total_water_dedicated_space() -> int:
	var total := 0
	for amount in water_dedicated_space.values():
		total += amount
	return total

# capacity è la capacità fisica della cella (ResourceCalculator.get_water_capacity_space),
# non una costante fissa come TOTAL_SPACE: SEA/LAKE e RIVER hanno capacità diverse, quindi va
# passata dal chiamante invece di essere ricavata qui.
func get_empty_water_space(capacity: int) -> int:
	return capacity - get_total_water_dedicated_space()

func get_terrestrial_space(object_type: GameTypes.WorldObjectType) -> int:
	return int(terrestrial_dedicated_space.get(object_type, 0))

func set_terrestrial_space(object_type: GameTypes.WorldObjectType, amount: int) -> void:
	terrestrial_dedicated_space[object_type] = max(amount, 0)

func get_total_terrestrial_dedicated_space() -> int:
	var total := 0
	for amount in terrestrial_dedicated_space.values():
		total += amount
	return total

# capacity è la capacità fisica della cella (ResourceCalculator.get_land_capacity_space), non
# una costante fissa: stesso principio di get_empty_water_space sopra.
func get_empty_terrestrial_space(capacity: int) -> int:
	return capacity - get_total_terrestrial_dedicated_space()

func get_total_dedicated_space() -> int:
	var total := river_space
	for amount in dedicated_space.values():
		total += amount
	return total

func get_empty_space() -> int:
	return TOTAL_SPACE - get_total_dedicated_space()

const DAYS_PER_YEAR_FOR_BONUSES: int = 365

func register_growth_bonus(
	event_type: GameTypes.NaturalEventType, multiplier: float, duration_years: int, trigger_absolute_day: int
) -> void:
	active_growth_bonuses[event_type] = {
		"multiplier": multiplier,
		"trigger_absolute_day": trigger_absolute_day,
		"duration_years": duration_years,
	}

func get_active_event_bonus(event_type: GameTypes.NaturalEventType) -> Dictionary:
	return active_growth_bonuses.get(event_type, {})

# Un bonus resta attivo esattamente `duration_years` anni dopo il giorno reale in cui l'evento
# è scattato (nessun arrotondamento a confine d'anno): current_absolute_day è il giorno assoluto
# di oggi (vedi GameData.get_absolute_day()).
func get_active_growth_multiplier(current_absolute_day: int) -> float:
	var multiplier := 1.0
	for bonus in active_growth_bonuses.values():
		var expiry_day: int = bonus["trigger_absolute_day"] + bonus["duration_years"] * DAYS_PER_YEAR_FOR_BONUSES
		if current_absolute_day >= expiry_day:
			continue
		multiplier *= bonus["multiplier"]
	return multiplier

# "Fresco" = entro il primo anno dal giorno reale del trigger (usato dal marker in
# WorldRenderer per distinguere l'anno dell'evento dagli anni di recupero successivi).
func is_event_bonus_fresh(event_type: GameTypes.NaturalEventType, current_absolute_day: int) -> bool:
	var bonus := get_active_event_bonus(event_type)
	if bonus.is_empty():
		return false
	return current_absolute_day - int(bonus["trigger_absolute_day"]) < DAYS_PER_YEAR_FOR_BONUSES

# Il marker resta visibile un anno oltre la scadenza effettiva dell'effetto sulla crescita
# (stesso "un ciclo in più" del vecchio schema a years_remaining), così non sparisce un anno
# prima che l'effetto sia realmente esaurito agli occhi del giocatore.
func is_event_bonus_visible(event_type: GameTypes.NaturalEventType, current_absolute_day: int) -> bool:
	var bonus := get_active_event_bonus(event_type)
	if bonus.is_empty():
		return false
	var visible_until: int = int(bonus["trigger_absolute_day"]) + (int(bonus["duration_years"]) + 1) * DAYS_PER_YEAR_FOR_BONUSES
	return current_absolute_day < visible_until
