class_name PopulationGroup
extends RefCounted

# Stato runtime di una popolazione animale "vera" (oggi solo rabbit) — non serializzato come
# .tres (i parametri di specie restano su AnimalRules), solo salvato/caricato come dato di
# partita (vedi GameSaveService/GameLoadService). Step 1 del refactoring fauna: sposta la
# ownership da MacroCellState (dizionari per-specie dentro la cella) a World (array di gruppi).
# Step 4: la cella occupata è ora un Territory (vedi Territory.gd) invece di una coppia di
# coordinate semplice — oggi un territorio ha sempre esattamente una macrocella
# (Territory.occupied_macrocells.size() == 1), nessun cambiamento di comportamento osservabile.
var species_name: String = ""
# ID progressivo assegnato UNA volta alla creazione (vedi World.allocate_population_group_id),
# mai ricalcolato — a differenza dell'indice mostrato da WorldInfoPanel prima di questo campo,
# resta stabile per tutta la vita del gruppo indipendentemente da quanti altri gruppi esistono o
# si estinguono nel frattempo. Permette a più gruppi della stessa specie (es. due popolazioni
# rabbit in celle diverse) di restare distinguibili nei log e nel pannello Fauna. Persistito nei
# save; 0 = mai assegnato (solo gruppi creati prima dell'introduzione di questo campo).
var id: int = 0
var population: int = 0
var age_composition: Dictionary = {} # AgeBand -> int
var territory: Territory = null
# Moltiplicatore di mitigazione della natalità (calorico × densità, vedi
# AnimalBirthMitigationService/TerritoryDynamicsService), applicato in AnimalBirthService IN
# AGGIUNTA a fertility_multiplier_by_age/base_birth_rate — non li sostituisce. Default 1.0
# (nessuna penalità): finché non è mai stato calcolato (es. gruppo appena creato prima del primo
# checkpoint a inizio birth_season), il comportamento resta quello di sempre. PERSISTITO nei save
# (bug corretto: era dichiarato "non vale la pena salvarlo perché si ricalcola al prossimo
# checkpoint annuale", ma viene CALCOLATO a inizio birth_season e CONSUMATO solo a fine — un
# salvataggio/caricamento nel mezzo perdeva il valore calcolato, tornando al default 1.0 e
# applicando nascite senza alcuna mitigazione, osservato in test).
var birth_mitigation_multiplier: float = 1.0

# Ratio calorico GREZZO (non ancora clampato/moltiplicato per densità o post-scissione) che ha
# prodotto birth_mitigation_multiplier sopra al checkpoint di birth_season — non serve alla
# simulazione (birth_mitigation_multiplier è già il valore finale usato da AnimalBirthService),
# esiste solo per il log: senza questo, per capire "quel moltiplicatore da dove viene" bisognava
# risalire al checkpoint TERRITORY DYNAMICS di inizio stagione (fino a ~90 giorni prima di quando
# la nascita viene effettivamente applicata a fine stagione, checkpoint diverso). Persistito per lo
# stesso motivo di birth_mitigation_multiplier sopra (calcolato a inizio birth_season, consumato/
# loggato solo a fine — un salvataggio/caricamento nel mezzo non deve perderlo).
var birth_mitigation_caloric_ratio: float = 1.0
# Countdown di recovery post-scissione (Step 10 del refactoring fauna, vedi
# AnimalRules.post_split_recovery_years/PopulationSplitService/TerritoryDynamicsService
# _get_post_split_multiplier): anni trascorsi dall'ultimo split che QUESTO gruppo ha generato
# come origine (mai da uno subito — il nuovo gruppo scisso non eredita questo stato). Sentinella
# -1 = mai scisso (default, incluso ogni gruppo appena creato da uno split): nessuna mitigazione
# aggiuntiva da calcolare, stesso principio del sentinella "0 = mai assegnato" già usato da id
# sopra. >= 0 = azzerato a 0 dal gruppo di origine al momento dello split, poi incrementato di 1
# ogni anno da TerritoryDynamicsService finché non ne scinde uno nuovo (che lo riazzera). PERSISTITO
# nei save (storia reale, non ricalcolabile da un checkpoint, stesso motivo di
# birth_mitigation_multiplier sopra).
var years_since_last_split: int = -1
# Cooldown (giorni) sul trigger di scissione da FAME QUOTIDIANA (Step 11 del refactoring fauna,
# vedi AnimalHungerService/PopulationSplitService) — indipendente da years_since_last_split sopra
# (quello rallenta la natalità dopo QUALUNQUE split, questo blocca esplicitamente solo i tentativi
# RIPETUTI della via fame, non tocca il trigger stagionale di TerritoryDynamicsService). Motivato
# da un rischio osservato: un territorio a 1 sola cella (rabbit) può tentare lo split ogni singolo
# giorno di fame consecutiva, senza freno rischiava di generare decine di micro-gruppi satellite in
# pochi giorni. 0 = nessun cooldown attivo (default, incluso ogni gruppo appena creato da uno
# split — nessuno stato ereditato). >0 = giorni ancora da aspettare prima di poter ritentare;
# decrementato di 1 ogni giorno da AnimalHungerService, impostato a rules.max_days_without_food
# SOLO quando uno split per fame riesce davvero (un tentativo fallito per mancanza di cella libera
# non fa scattare il cooldown). Deliberatamente NON sincronizzato con hunger_buckets/la mortalità
# da fame — quest'ultima non viene mai azzerata dallo split, i due orologi restano indipendenti
# per design (confermato: nessun collegamento voluto tra i due). PERSISTITO nei save, stesso
# motivo di birth_mitigation_multiplier/years_since_last_split sopra.
var hunger_split_cooldown_days: int = 0
# Cache di "ero bloccato l'ultima volta che ho cercato spazio" (AnimalHungerService.
# _attempt_expansion/TerritoryDynamicsService._update_group_territory), per evitare di rifare ogni
# giorno una BFS costosa (TerritoryBuilderService.expand_by_one_cell/find_nearest_free_cell, più
# uno scan O(gruppi) su _collect_species_occupied_cells) quando l'esito sarebbe comunque lo stesso
# di ieri. Sentinella -1 = "non risulta bloccato" (default, incluso ogni gruppo appena creato):
# vale sempre la pena tentare. Un valore >= 0 memorizza invece
# World.species_territory_release_version[species_name] nel momento esatto dell'ultimo fallimento
# — finché quel contatore per la specie non cambia (un territorio della stessa specie si libera
# per estinzione o contrazione altrove sulla mappa, vedi World.release_species_territory), il
# gruppo salta il tentativo, perché nulla può essere cambiato nel frattempo che renderebbe la
# ricerca diversa da ieri. Non persistito nei save, stesso principio di
# territory_distribution_weights sotto: puro dato di cache/ottimizzazione, mai storia reale —
# perderlo al caricamento costa al più un tentativo completo in più al primo checkpoint dopo il
# load per i gruppi già bloccati, poi il meccanismo si riallinea da solo.
var blocked_territory_search_version: int = -1
# Pesi (Vector2i -> float, non normalizzati) usati da get_population_by_cell() per ripartire
# population tra le celle del territorio — Step 6 del refactoring fauna: sostituisce la
# ripartizione uniforme fissa con una variazione casuale ricalcolata periodicamente (vedi
# PopulationTerritoryShuffleService), per dare l'impressione visiva di un branco che si sposta
# nel proprio areale nel tempo invece di un contatore diviso meccanicamente in parti sempre
# uguali. Default vuoto: get_population_by_cell() tratta una chiave assente come peso 1.0, quindi
# un gruppo mai rimescolato (o con territorio a 1 sola cella, mai scritto qui) degrada esattamente
# alla vecchia ripartizione uniforme, nessun ramo speciale altrove. Non persistito nei save
# (a differenza di birth_mitigation_multiplier sopra, corretto dopo un bug: questi pesi sono
# puramente estetici/di rendering — get_population_by_cell li usa solo per ripartire la
# visualizzazione tra celle, mai per calcoli che restano "in sospeso" tra un checkpoint e
# l'altro — quindi perderli al caricamento non altera l'esito del gioco): si ricalcola al
# prossimo checkpoint stagionale, non vale la pena salvarlo.
var territory_distribution_weights: Dictionary = {}
# Istogramma di fame (AnimalHungerService): chiave = giorni CONSECUTIVI in cui un individuo non
# ha ricevuto fabbisogno calorico sufficiente (0 = sazio), valore = quanti individui in quel
# bucket. La somma di tutti i valori deve sempre restare coerente con population — mantenuta
# tale dagli stessi punti che già mutano population (set_age_composition/apply_births/
# apply_old_age_mortality sotto) più lo shift giornaliero interno ad AnimalHungerService, mai
# ricalcolata da zero altrove. Storia accumulata reale (quanti giorni di fame ha già alle spalle
# un individuo), va persistita nei save (vedi GameSaveService/GameLoadService), non semplicemente
# ricalcolata al prossimo checkpoint — stesso principio di birth_mitigation_multiplier sopra.
var hunger_buckets: Dictionary = {}
# Ratio calorico GIORNALIERO del gruppo (consumo di oggi / fabbisogno di oggi, aggregato su
# TUTTO il territorio — vedi AnimalConsumptionService._consume_group), riusato da
# AnimalHungerService per decidere quanti individui non sono stati nutriti oggi e se tentare
# un'espansione territoriale. Non persistito nei save: ricalcolato ogni giorno da
# AnimalConsumptionService prima che AnimalHungerService giri, stesso trattamento di
# birth_mitigation_multiplier. Default 1.0 = nessuna penalità finché non è mai stato calcolato.
var daily_caloric_ratio: float = 1.0
# Numeri grezzi dietro daily_caloric_ratio sopra (calorie consumate oggi / calorie di fabbisogno
# oggi, stessa aggregazione su tutto il territorio) — esposti separatamente così il log di
# AnimalHungerService può mostrare i calcoli invece del solo rapporto già arrotondato: un ratio
# stampato "1.000" a 3 decimali può nascondere un vero piccolo deficit (es. 0.997, dovuto a un
# calo stagionale reale di seasonal_availability_multiplier su FORAGE, non rumore in virgola
# mobile) indistinguibile senza i numeri grezzi. Non persistiti, stesso trattamento del ratio.
var daily_calories_consumed: float = 0.0
var daily_calories_required: float = 0.0

# Pattugliamento giornaliero dei branchi predatori (PredatorPatrolService) — sequenza di anchor
# (vertice top-left di una finestra di caccia quadrata) che copre l'intero territorio seguendone
# la forma reale. Vuoto per ogni specie non predatrice (mai popolato, mai letto). Ricalcolato per
# intero da PredatorPatrolService.recompute_route SOLO quando la forma di territory cambia (mai
# ogni giorno) — puramente derivato da territory + PredatorRules.hunting_window_size, quindi non
# persistito nei save: dopo un caricamento va semplicemente ricalcolato una volta, stesso principio
# già usato per territory_distribution_weights sopra (dato ricostruibile, non storia reale).
var patrol_route: Array[Vector2i] = []
# Puntatore corrente su patrol_route e verso di avanzamento (+1/-1) — vedi
# PredatorPatrolService.advance_patrol, che li fa rimbalzare agli estremi dell'array invece di
# ripartire da 0 una volta raggiunta la fine ("avanti e indietro", non un loop). Riazzerati a 0/+1
# SOLO quando patrol_route viene ricalcolato (un indice/verso relativi al percorso VECCHIO non
# avrebbero corrispondenza garantita su un percorso nuovo) — a differenza di patrol_route sopra,
# questi due NON sono dato ricostruibile dalla sola forma del territorio: rappresentano il
# progresso del branco nel percorso (quanti giorni ha già camminato, in che verso), storia reale
# esattamente come hunger_buckets/years_since_last_split/hunger_split_cooldown_days più sotto in
# questo file — non equivalenti a territory_distribution_weights (quello sì puramente estetico).
# Persistiti in GameSaveService/GameLoadService (stesso blocco di hunger_buckets/
# years_since_last_split/hunger_split_cooldown_days) — un caricamento ricostruisce patrol_route da
# zero (dato derivato, vedi sopra) ma applica questi due dal save SENZA lasciarli riazzerare dal
# ricalcolo (PredatorPatrolService.recompute_route chiamato con reset_progress=false in
# GameLoadService), cosicché il branco riprenda esattamente da dove il pattugliamento era rimasto.
var patrol_index: int = 0
var patrol_direction: int = 1

# Bookkeeping calorico della caccia (PredationService) — debito accumulato (fabbisogno non
# coperto dei giorni scorsi, riportato in avanti) e surplus riportato da ieri (metà di un'eventuale
# eccedenza di ieri, l'altra metà persa — vedi PredationService._apply_calorie_bookkeeping). Stesso
# principio concettuale di hunger_buckets per gli erbivori, ma un ledger scalare invece di un
# istogramma per giorni: qui non serve sapere DA QUANTO TEMPO manca cibo, solo QUANTO manca oggi.
# Vuoti/a 0.0 per ogni specie non predatrice (mai popolati, mai letti). Storia reale accumulata,
# non ricalcolabile da un checkpoint — stessa categoria di patrol_index/patrol_direction sopra, non
# di territory_distribution_weights. Persistiti in GameSaveService/GameLoadService, stesso blocco.
var predation_calorie_debt: float = 0.0
var predation_surplus_carryover: float = 0.0

# Consuntivo calorico "da un checkpoint di birth_season al successivo" (non l'anno di calendario,
# vedi yearly_prey_totals sotto per quella distinzione) — somma grezza, senza il decadimento/
# azzeramento del ledger sopra (predation_calorie_debt/predation_surplus_carryover: quello risponde
# a "il branco può permettersi di non cacciare oggi?", volutamente scontato nel tempo; questo
# risponde a "com'è andata la stagione riproduttiva nel complesso?", ogni giorno pesato allo stesso
# modo). Alimenta AnimalBirthMitigationService.compute_predator_caloric_ratio (mitigazione della
# natalità dei predatori, equivalente al ratio stock/fabbisogno degli erbivori ma su dati di caccia
# reali) — TerritoryDynamicsService li azzera subito dopo averli letti al checkpoint. Vuoti/a 0.0
# per ogni specie non predatrice (mai popolati, mai letti). Persistiti in GameSaveService/
# GameLoadService, stesso blocco di predation_calorie_debt/predation_surplus_carryover sopra.
var predation_season_calories_obtained: float = 0.0
var predation_season_calories_required: float = 0.0

# Cronologia di caccia per la tab Fauna 3 (UI, PredationService la popola) — una entry per OGNI
# giorno processato dal branco (anche i giorni senza catture, "— nessuna cattura —"), non solo i
# giorni fortunati: così "gli ultimi 5 giorni" è sempre una vera finestra temporale di 5 giorni
# consecutivi, non 5 giorni sparsi nel tempo. Capped a RECENT_HUNT_LOG_MAX_DAYS entry, FIFO (la più
# vecchia esce quando arriva una nuova). Ogni entry: {"year": int, "day": int, "captures":
# Dictionary[String, Dictionary]} dove captures mappa species_name -> {"quantity": int,
# "calories": float}, dizionario vuoto se nessuna cattura quel giorno. Vuoto per ogni specie non
# predatrice (mai popolato, mai letto). Storia reale (non ricalcolabile da un checkpoint) — a
# differenza di patrol_route/blocked_territory_search_version sopra, PERSISTITA nei save: è
# contenuto informativo mostrato al giocatore, perderlo al caricamento sarebbe una regressione
# visibile (lista vuota subito dopo un load, anche con anni di caccia alle spalle).
const RECENT_HUNT_LOG_MAX_DAYS := 5
var recent_hunt_log: Array[Dictionary] = []

# Totali di caccia dell'ANNO DI CALENDARIO corrente (si azzera al cambio anno, non una finestra
# rolling — più semplice e coerente col resto del gioco, che già ragiona per anni interi tramite
# GameData.year) — species_name -> {"quantity": int, "calories": float}. yearly_prey_totals_year
# tiene traccia di QUALE anno si riferiscono questi totali: PredationService confronta con
# GameData.year corrente e azzera entrambi i campi al primo giorno di caccia di un anno nuovo,
# invece di richiedere un hook dedicato al cambio anno altrove. Stessa categoria di
# recent_hunt_log sopra (storia reale, PERSISTITA nei save), vuoti per ogni specie non predatrice.
var yearly_prey_totals: Dictionary = {}
var yearly_prey_totals_year: int = -1

func _init(_species_name: String = "", _territory: Territory = null, _id: int = 0) -> void:
	species_name = _species_name
	territory = _territory
	id = _id


func set_population(count: int) -> void:
	population = max(count, 0)


func set_birth_mitigation_multiplier(value: float) -> void:
	# Tetto = AnimalBirthMitigationService.MULTIPLIER_ABUNDANCE_CAP (1.2), non più 1.0 fisso: il
	# moltiplicatore calorico può ora superare 1.0 in caso di abbondanza reale (vedi
	# AnimalBirthMitigationService._get_multiplier) — un tetto hardcoded a 1.0 qui troncherebbe
	# silenziosamente quel bonus ogni volta che il fattore densità non lo comprime già da solo
	# (bug osservato in test: bonus abbondanza mai visibile finché la densità non era già alta).
	birth_mitigation_multiplier = clamp(value, 0.0, AnimalBirthMitigationService.MULTIPLIER_ABUNDANCE_CAP)


func set_territory_distribution_weights(weights: Dictionary) -> void:
	territory_distribution_weights = weights


func set_daily_caloric_ratio(value: float) -> void:
	daily_caloric_ratio = clamp(value, 0.0, 1.0)


# Punto unico di scrittura per daily_caloric_ratio E i numeri grezzi che lo spiegano (vedi campi
# sopra) — il chiamante (AnimalConsumptionService._consume_group) passa sempre consumo/fabbisogno
# grezzi, mai il ratio già calcolato, così l'edge case "nessun fabbisogno" (required <= 0, gruppo
# senza age_composition pesata o senza celle valide) è gestito in un solo posto: ratio neutro 1.0,
# stessa semantica di "nessuna penalità" usata altrove, invece di un 0/0 indefinito.
func set_daily_caloric_consumption(consumed: float, required: float) -> void:
	daily_calories_consumed = max(consumed, 0.0)
	daily_calories_required = max(required, 0.0)
	if daily_calories_required <= 0.0:
		set_daily_caloric_ratio(1.0)
	else:
		set_daily_caloric_ratio(daily_calories_consumed / daily_calories_required)


func get_hunger_bucket_count(days: int) -> int:
	return int(hunger_buckets.get(days, 0))

func set_hunger_bucket_count(days: int, amount: int) -> void:
	hunger_buckets[days] = max(amount, 0)

func get_hunger_bucket_total() -> int:
	var total := 0
	for amount in hunger_buckets.values():
		total += int(amount)
	return total


func get_age_count(age_band: GameTypes.AgeBand) -> int:
	return int(age_composition.get(age_band, 0))

func set_age_count(age_band: GameTypes.AgeBand, amount: int) -> void:
	age_composition[age_band] = max(amount, 0)

func get_age_total() -> int:
	var total := 0
	for amount in age_composition.values():
		total += int(amount)
	return total


# Sovrascrive interamente la composizione età ripartendo `total` individui secondo `weights`
# (in genere AnimalRules.initial_age_ratio) — pensata per un chiamante che può risettare il
# totale più volte sullo stesso gruppo (oggi solo il pulsante debug "set rabbit population"),
# quindi resetta prima di ridistribuire invece di sommarsi a quanto già presente. weights
# vuoto/tutto a 0 => pesi uguali tra le tre fasce, stesso fallback di initial_age_ratio altrove.
# Riusa MacroCellState._split_by_weight (stesso algoritmo "largest remainder" già condiviso da
# subtype/age-band vegetali, non duplicato qui).
func set_age_composition(total: int, weights: Dictionary) -> void:
	age_composition = {}
	# Reset totale della composizione (chiamato solo dal seeding/reseeding manuale, vedi
	# AnimalRules.initial_age_ratio sopra): un gruppo appena (ri)creato non ha alle spalle
	# nessuno storico di digiuno, quindi hunger_buckets riparte da zero individui tutti sazi —
	# stessa filosofia di reset completo di age_composition qui sopra, non un incremento.
	hunger_buckets = {}
	if total <= 0:
		return
	set_hunger_bucket_count(0, total)
	var source_weights := weights
	if source_weights.is_empty():
		source_weights = {
			GameTypes.AgeBand.YOUNG: 1.0,
			GameTypes.AgeBand.ADULT: 1.0,
			GameTypes.AgeBand.OLD: 1.0,
		}
	var split := MacroCellState._split_by_weight(source_weights, total)
	for age_band in split.keys():
		set_age_count(age_band, get_age_count(age_band) + split[age_band])


# Maturazione annuale: young->adult dopo youth_duration_years, adult->old dopo
# adult_duration_years — durate PROPRIE di ciascuna fascia, indipendenti tra loro (non soglie
# cumulative di età dalla nascita), stessa logica frazionaria già usata per la vegetazione. Un
# individuo avanza al massimo di una fascia per anno, mai due nello stesso ciclo. Nessuna
# modifica al totale: population non va toccato qui (il chiamante, AnimalAgeBandService, gira
# PRIMA delle nascite nello stesso checkpoint stagionale).
func apply_age_band_maturation(youth_duration_years: int, adult_duration_years: int) -> void:
	var young_count := get_age_count(GameTypes.AgeBand.YOUNG)
	var adult_count := get_age_count(GameTypes.AgeBand.ADULT)
	if young_count <= 0 and adult_count <= 0:
		return

	# stochastic_round (non round()): stesso bias sistematico di AnimalBirthService/
	# AnimalOldAgeMortalityService a conteggi piccoli — vedi SimulationMath.
	var young_to_adult: int = 0
	if youth_duration_years > 0:
		young_to_adult = min(SimulationMath.stochastic_round(float(young_count) / float(youth_duration_years)), young_count)

	var adult_to_old: int = 0
	if adult_duration_years > 0:
		adult_to_old = min(SimulationMath.stochastic_round(float(adult_count) / float(adult_duration_years)), adult_count)

	if young_to_adult <= 0 and adult_to_old <= 0:
		return

	set_age_count(GameTypes.AgeBand.YOUNG, young_count - young_to_adult)
	set_age_count(GameTypes.AgeBand.ADULT, adult_count - adult_to_old + young_to_adult)
	set_age_count(GameTypes.AgeBand.OLD, get_age_count(GameTypes.AgeBand.OLD) + adult_to_old)


# Aggiunge `amount` nuovi nati alla fascia YOUNG, incrementando anche population della stessa
# quantità — le due scritture avvengono insieme così l'invariante "somma delle fasce ==
# population" resta valida sia prima che dopo. Il chiamante (AnimalBirthService) garantisce che
# questo giri sempre DOPO la maturazione dello stesso checkpoint, così i nuovi nati non maturano
# mai nello stesso ciclo in cui compaiono.
func apply_births(amount: int) -> void:
	if amount <= 0:
		return
	set_age_count(GameTypes.AgeBand.YOUNG, get_age_count(GameTypes.AgeBand.YOUNG) + amount)
	set_population(population + amount)
	# I nuovi nati non hanno mai digiunato: entrano nel bucket 0 (sazi), mantenendo l'invariante
	# somma(hunger_buckets) == population anche dopo una nascita (vedi hunger_buckets sopra).
	set_hunger_bucket_count(0, get_hunger_bucket_count(0) + amount)


# Sottrae `amount` morti per vecchiaia dalla fascia OLD, decrementando anche population della
# stessa quantità — gemella di apply_births ma in sottrazione. set_age_count/set_population
# clampano già a 0, quindi nessun rischio di andare in negativo anche in caso di arrotondamenti
# al limite.
func apply_old_age_mortality(amount: int) -> void:
	if amount <= 0:
		return
	set_age_count(GameTypes.AgeBand.OLD, get_age_count(GameTypes.AgeBand.OLD) - amount)
	set_population(population - amount)
	# hunger_buckets non è stratificato per età: non sappiamo a quale bucket appartenessero gli
	# individui morti per vecchiaia, quindi la perdita si ripartisce PROPORZIONALMENTE tra i
	# bucket esistenti (stesso "water-filling" capped già usato per subtype/age-band vegetali),
	# invece che tutta dal bucket 0 o da uno scelto arbitrariamente — mantiene comunque l'invariante
	# somma(hunger_buckets) == population.
	var loss: int = min(amount, get_hunger_bucket_total())
	if loss > 0:
		var split := MacroCellState._split_by_weight_capped(hunger_buckets, hunger_buckets, loss)
		for days in split.keys():
			set_hunger_bucket_count(days, get_hunger_bucket_count(days) - split[days])


# Applica `amount` morti per fame prolungata (AnimalHungerService, individui la cui permanenza
# in un bucket di hunger_buckets ha superato AnimalRules.max_days_without_food), distribuite tra
# le fasce d'età in proporzione a AnimalRules.mortality_share_by_age (mai uniformemente) —
# analogo ad apply_old_age_mortality ma pesato per fascia invece che concentrato su OLD, e senza
# toccare hunger_buckets: il chiamante ha già rimosso gli individui interessati dai bucket PRIMA
# di invocare questo metodo (fanno parte dello shift giornaliero, non di un ricalcolo separato),
# quindi qui si aggiorna solo il lato age_composition/population. Se la specie non traccia le
# fasce d'età (o la composizione è vuota), population viene comunque decrementata senza toccare
# age_composition — stesso fallback "population come contatore piatto" usato prima che
# track_age_bands esistesse. Ritorna il numero di morti effettivamente applicati (mai più di
# population).
func apply_hunger_mortality(amount: int, rules: AnimalRules) -> int:
	if amount <= 0:
		return 0
	var loss: int = min(amount, population)
	if loss <= 0:
		return 0

	if rules.track_age_bands and get_age_total() > 0:
		var weights: Dictionary = {
			GameTypes.AgeBand.YOUNG: rules.mortality_share_by_age[GameTypes.AgeBand.YOUNG],
			GameTypes.AgeBand.ADULT: rules.mortality_share_by_age[GameTypes.AgeBand.ADULT],
			GameTypes.AgeBand.OLD: rules.mortality_share_by_age[GameTypes.AgeBand.OLD],
		}
		var caps: Dictionary = {
			GameTypes.AgeBand.YOUNG: get_age_count(GameTypes.AgeBand.YOUNG),
			GameTypes.AgeBand.ADULT: get_age_count(GameTypes.AgeBand.ADULT),
			GameTypes.AgeBand.OLD: get_age_count(GameTypes.AgeBand.OLD),
		}
		var split := MacroCellState._split_by_weight_capped(weights, caps, loss)
		for age_band in split.keys():
			set_age_count(age_band, get_age_count(age_band) - split[age_band])

	set_population(population - loss)
	return loss


# Applica `amount` catture di predazione (PredationService) a UNA fascia d'età specifica (quella
# della vittima già scelta dal chiamante — a differenza di apply_hunger_mortality, qui non c'è una
# ripartizione pesata tra fasce da fare qui dentro, il chiamante ha già deciso quale). Clampato alla
# disponibilità reale della fascia, stesso schema di apply_old_age_mortality/apply_hunger_mortality.
# Non tocca hunger_buckets di QUESTO gruppo (la preda): a differenza della fame, che ha sempre già
# rimosso gli individui interessati dai bucket PRIMA di chiamare l'equivalente qui, una cattura di
# predazione arriva dall'ESTERNO senza alcuna nozione di bucket coinvolta — l'eventuale
# disallineamento tra population e somma(hunger_buckets) che ne risulta è esattamente il caso per
# cui esiste AnimalHungerService._reconcile_bucket_total (rete di sicurezza già pensata per un
# "punto di mutazione futuro che dimenticasse di aggiornare hunger_buckets"), che lo risolve la
# prossima volta che quel service gira sul gruppo preda, stesso giorno se PredationService gira
# prima di AnimalHungerService nel ciclo giornaliero. Ritorna il numero di catture effettivamente
# applicate (mai più della disponibilità reale).
func apply_predation_loss(age_band: GameTypes.AgeBand, amount: int) -> int:
	if amount <= 0:
		return 0
	var available := get_age_count(age_band)
	var loss: int = min(amount, available)
	if loss <= 0:
		return 0
	set_age_count(age_band, available - loss)
	set_population(population - loss)
	return loss


# Ripartisce `population` tra le celle del territorio secondo territory_distribution_weights
# (Step 6: variazione casuale ricalcolata a ogni checkpoint stagionale da
# PopulationTerritoryShuffleService — vedi il campo sopra) — una chiave assente in quel
# dizionario vale peso 1.0, quindi un territorio a 1 sola cella (mai scritto lì, rabbit) o un
# gruppo appena creato prima del primo rimescolamento degradano automaticamente alla vecchia
# ripartizione uniforme, senza bisogno di un ramo a parte qui. Split ricalcolato da zero a ogni
# chiamata (non solo i pesi cambiano raramente, anche `population` stesso può cambiare in
# qualunque momento — es. i pulsanti debug — quindi il risultato resta sempre coerente col
# valore CORRENTE di population, mai una quantità congelata al momento del rimescolamento). Riusa
# lo stesso "largest remainder" (MacroCellState._split_by_weight) già condiviso da subtype/age-band
# vegetali e dalla composizione età sopra. Unica fonte condivisa da AnimalConsumptionService
# (ripartizione del fabbisogno) e dai pannelli UI/renderer (quota animali per cella), così non
# possono mai disallinearsi.
func get_population_by_cell() -> Dictionary:
	var result: Dictionary = {}
	if territory == null or population <= 0:
		return result
	var weights: Dictionary = {}
	for coords in territory.occupied_macrocells:
		weights[coords] = float(territory_distribution_weights.get(coords, 1.0))
	return MacroCellState._split_by_weight(weights, population)


# Composizione età SOLO per la quota di `coords` (vedi get_population_by_cell) — non stato reale,
# derivata a scopo di visualizzazione (nessuna age band è tracciata per cella nel modello, solo a
# livello di gruppo). Ripartisce la quota della cella tra le tre fasce in proporzione alla
# composizione età corrente del gruppo intero (stesso fallback a pesi uguali se age_composition è
# vuota, coerente con set_age_composition), così la somma Y+A+O di questa cella torna sempre
# esattamente uguale alla quota mostrata per la cella.
func get_age_composition_in_cell(coords: Vector2i) -> Dictionary:
	var population_by_cell := get_population_by_cell()
	var cell_population: int = int(population_by_cell.get(coords, 0))
	if cell_population <= 0:
		return {}

	var weights: Dictionary = {}
	for age_band in age_composition.keys():
		var count: float = float(age_composition[age_band])
		if count > 0.0:
			weights[age_band] = count
	if weights.is_empty():
		weights = {
			GameTypes.AgeBand.YOUNG: 1.0,
			GameTypes.AgeBand.ADULT: 1.0,
			GameTypes.AgeBand.OLD: 1.0,
		}

	return MacroCellState._split_by_weight(weights, cell_population)
