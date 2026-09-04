class_name HumanSeedingService
extends RefCounted

# Seminatore del popolo/insediamento/individui umani a inizio partita — stesso ruolo di
# AnimalSeedingService lato animale, ma NON un suo consumatore (nessuna dipendenza, solo
# ispirazione di pattern: stateless, un solo entry point per caso d'uso). find_candidate_start_
# cells/griglia con jitter di AnimalSeedingService non si applicano qui: un insediamento umano
# iniziale nasce in UNA cella gia' scelta da FirstStartMacroCellSelectionService (mai toccato da
# questa classe), non serve alcuna ricerca di celle candidate su tutta la mappa.
#
# DEBITO NOTO: nessuna persistenza reale ancora — Folk/HumanPopulationGroup/HumanIndividual
# creati qui vengono riseminati da zero ad ogni chiamata (stessa convenzione gia' in uso per
# HumanIndividual.new() in GameScene prima di questo passo). Quando arriveranno
# GameSaveService/GameLoadService per il lato umano, questo andra' rivisto.
#
# DEBITO NOTO: id locali sequenziali assegnati DENTRO la singola chiamata (Folk/
# HumanPopulationGroup fissi a 1, individui 1..N) — nessun allocatore globale ancora (equivalente
# umano di World.allocate_population_group_id()), rimandato a quando esistera' un vero "mondo
# umano" con piu' insediamenti contemporaneamente.

# "FAMILY"/"SMALL_GROUP"/"BIG_GROUP" — stesse tre etichette gia' esposte da NewGameOptionsMenu/
# GameSettings.selected_group_size_preference/GameData.starting_group_size_preference (finora
# senza alcun effetto pratico, solo difficolta' — questo e' il primo consumatore reale).
# "couples" = numero di coppie fondatrici (mother+father, genitori sconosciuti/-1), "children" =
# totale figli distribuiti tra le coppie da _distribute_children.
const GROUP_SIZE_COMPOSITIONS := {
	"FAMILY": {"couples": 1, "children": 3},
	"SMALL_GROUP": {"couples": 3, "children": 4},
	"BIG_GROUP": {"couples": 6, "children": 8},
}
const DEFAULT_GROUP_SIZE_PREFERENCE := "SMALL_GROUP" # stesso default di GameSettings.selected_group_size_preference

# Anni minimi tra l'eta' di un genitore e quella del figlio al momento della nascita — soglia di
# comodo dichiaratamente arbitraria (non derivata da alcun dato biologico reale), facile da
# ritarare in seguito senza toccare l'algoritmo che la usa.
const MIN_PARENT_CHILD_AGE_GAP_YEARS := 14

# Regole migliorative SOLO per FAMILY (richiesta utente, 2026-09-02) — SMALL_GROUP/BIG_GROUP
# restano sulla selezione indipendente generica (_create_adult) per ora, regole proprie per quei
# due tipi rimandate a un passo successivo. Nate da un caso reale osservato con la selezione
# generica: madre/padre scelti indipendentemente (fascia + eta' a caso ciascuno) potevano finire
# a 50 e 13 anni — oltre ad essere assurdo di per se', il genitore piu' giovane dei due rendeva
# impossibile anche dare un'eta' sensata ai figli (vincolati da MIN_PARENT_CHILD_AGE_GAP_YEARS
# contro il genitore PIU' GIOVANE), risultando SEMPRE in figli tutti a eta' 0.
#
# Differenza d'eta' massima tra i due genitori di una FAMILY — entrambi garantiti FERTILE_ADULT
# (mai MATURE_ADULT, vedi _create_family_couple), quindi coppie plausibili invece di abbinamenti
# a caso tra fasce diverse.
const MAX_FAMILY_PARENT_AGE_GAP_YEARS: float = 3.0
# Eta' massima dei figli di una FAMILY (invece del massimo teorico "tutta la fascia CHILD") —
# risultato voluto: una famiglia giovane con figli piccoli, eta' distribuite tra 0 e questo
# valore invece che sempre 0 (bug precedente) o sparse fino al limite della fascia CHILD.
const FAMILY_CHILD_MAX_AGE_YEARS: float = 3.0

# Margine (anni) aggiunto alla durata della fascia CHILD del genitore PIU' GIOVANE per ottenere il
# gap minimo genitore-figlio, SOLO per FAMILY (richiesta utente, 2026-09-02 — sostituisce, solo
# per questo tipo, il MIN_PARENT_CHILD_AGE_GAP_YEARS flat sopra): il ragionamento e' che il
# genitore deve aver gia' superato la propria infanzia (CHILD) da almeno questo margine di anni al
# momento del concepimento, non solo un numero fisso scollegato dalla fascia CHILD vera e propria
# del suo stesso Folk. Vedi _create_child (parametro use_dynamic_parent_gap).
const FAMILY_PARENT_CHILD_GAP_MARGIN_YEARS: float = 5.0

# Spaziatura (microcelle) tra le posizioni iniziali degli individui generati — richiesta utente,
# 2026-09-01: griglia ORDINATA invece dello sparpagliamento casuale iniziale (troppo largo/
# disordinato), più vicina. Centrata su World.WIDTH/HEIGHT/2.0 (stesso centro-griglia di default
# già usato da GameScene per il fondatore quando non c'è una posizione salvata) — GameScene
# ricentra poi l'intero gruppo sulla posizione REALE del fondatore (salvata o di default, comunque
# risolta lì) traslando tutti individui della stessa differenza, così la formazione resta coerente
# sia per una partita nuova sia per una caricata.
const SPAWN_GRID_SPACING: float = 1.2


# Semina Folk + HumanPopulationGroup + HumanIndividual (coppie fondatrici + figli) per il popolo
# del player, in UNA cella gia' scelta altrove (macro_coords, tipicamente il risultato di
# FirstStartMacroCellSelectionService — mai richiamato da qui). group_size_preference e' una
# delle chiavi di GROUP_SIZE_COMPOSITIONS (chiave sconosciuta/vuota -> fallback
# DEFAULT_GROUP_SIZE_PREFERENCE, stesso principio "default neutro" gia' in uso ovunque nel
# progetto per Dictionary.get). human_rules/folk_name sono decisi dal chiamante (oggi GameScene
# carica direttamente il .tres del player) — questo servizio resta generico, non conosce alcun
# path su disco. current_year passato esplicitamente (non letto da GameData) per restare
# stateless, stesso principio di AnimalSeedingService che non tocca GameData.
func seed_player_start(
	macro_coords: Vector2i,
	group_size_preference: String,
	human_rules: HumanRules,
	folk_name: String,
	current_year: int
) -> HumanSeedingResult:
	var result := HumanSeedingResult.new()

	result.folk = Folk.new()
	result.folk.id = 1
	result.folk.name = folk_name
	result.folk.human_rules_ref = human_rules

	result.group = HumanPopulationGroup.new()
	result.group.id = 1
	result.group.folk_ref = result.folk
	result.group.home_macro_coords = macro_coords

	var composition: Dictionary = GROUP_SIZE_COMPOSITIONS.get(
		group_size_preference, GROUP_SIZE_COMPOSITIONS[DEFAULT_GROUP_SIZE_PREFERENCE]
	)
	var couple_count: int = composition["couples"]
	var total_children: int = composition["children"]
	var children_per_couple := _distribute_children(couple_count, total_children)

	var individuals: Array[HumanIndividual] = []
	var next_id := 1
	# Regole coordinate SOLO per FAMILY — vedi MAX_FAMILY_PARENT_AGE_GAP_YEARS/
	# FAMILY_CHILD_MAX_AGE_YEARS sopra per il motivo. SMALL_GROUP/BIG_GROUP restano sulla
	# selezione indipendente generica per ora.
	var is_family := group_size_preference == "FAMILY"
	# Nomi gia' assegnati in QUESTA chiamata, SOLO per FAMILY (richiesta utente, 2026-09-02: nomi
	# tutti diversi dentro una famiglia) — passato per riferimento a _create_family_couple/
	# _create_child, che vi aggiungono il nome appena scelto subito dopo assign_random_name.
	# SMALL_GROUP/BIG_GROUP non lo popolano/consultano affatto (restano sulla vecchia selezione
	# indipendente, duplicati possibili come prima).
	var used_names: Array[String] = []

	for i in range(couple_count):
		var mother: HumanIndividual
		var father: HumanIndividual
		if is_family:
			var couple := _create_family_couple(human_rules, current_year, next_id, used_names)
			mother = couple[0]
			father = couple[1]
			next_id += 2
		else:
			# Ruoli FEMALE/MALE fissati per costruzione (mother=FEMALE, father=MALE per
			# definizione dei due campi, coerente con l'assunzione di coppie eterosessuali
			# confermata con l'utente) invece di pescare il sesso a caso e riprovare finche' non
			# risulta una coppia mista: stesso identico esito garantito (sempre esattamente una
			# FEMALE e un MALE per coppia), senza alcun ciclo di ritentativo — la casualita' vera
			# resta dov'è rilevante (fascia d'eta', eta' esatta, nome).
			mother = _create_adult(human_rules, current_year, HumanTypes.Sex.FEMALE, next_id)
			next_id += 1
			father = _create_adult(human_rules, current_year, HumanTypes.Sex.MALE, next_id)
			next_id += 1
		mother.partner_id = father.id
		father.partner_id = mother.id
		mother.source_group_ref = result.group
		father.source_group_ref = result.group
		individuals.append(mother)
		individuals.append(father)

		for _c in range(children_per_couple[i]):
			var child := _create_child(
				human_rules, current_year, mother, father, next_id,
				FAMILY_CHILD_MAX_AGE_YEARS if is_family else -1.0,
				is_family,
				used_names if is_family else []
			)
			next_id += 1
			child.source_group_ref = result.group
			individuals.append(child)

	# Posizione iniziale in griglia ORDINATA per OGNI individuo, fondatore incluso (richiesta
	# utente, 2026-09-01, Passo 2 — sostituisce il primo tentativo a sparpagliamento casuale,
	# giudicato troppo largo/disordinato) — human_individuals[0] (il fondatore scelto come
	# controllabile da GameScene) viene comunque ri-centrato lì sulla posizione reale di spawn
	# subito dopo, spostando l'intero gruppo della stessa differenza: la posizione assegnata qui
	# conta solo come punto di riferimento RELATIVO tra i membri del gruppo, non come coordinata
	# finale.
	for i in range(individuals.size()):
		individuals[i].position = _grid_spawn_position(i, individuals.size())

	result.individuals = individuals
	result.group.total_count = individuals.size()
	return result


# Griglia quadrata-ish centrata su World.WIDTH/HEIGHT/2.0, ordinata per indice riga per riga
# (nessun significato particolare nell'ordine — coincide con l'ordine di creazione: coppie poi
# figli, vedi sopra). columns = ceil(sqrt(total)) tiene la griglia il più vicina possibile a un
# quadrato per qualunque totale (5/10/20 secondo FAMILY/SMALL_GROUP/BIG_GROUP).
func _grid_spawn_position(index: int, total: int) -> Vector2:
	var columns := ceili(sqrt(float(total)))
	var rows := ceili(float(total) / float(columns))
	var col := index % columns
	var row := index / columns
	var grid_size := Vector2(float(columns - 1), float(rows - 1)) * SPAWN_GRID_SPACING
	var center := Vector2(World.WIDTH / 2.0, World.HEIGHT / 2.0)
	return center - grid_size / 2.0 + Vector2(col, row) * SPAWN_GRID_SPACING


# STUB — firma dichiarata ora per fissare la forma futura, nessuna logica di composizione/eta'/
# nomi implementata (TODO, vedi sotto). Parametri plausibili per un insediamento indigeno:
# macro_coords gia' scelte da un futuro servizio di posizionamento indigeno (fuori scope di
# QUESTA classe, non FirstStartMacroCellSelectionService — quello resta specifico del player),
# group_size come conteggio diretto invece delle etichette FAMILY/SMALL_GROUP/BIG_GROUP (quelle
# sono un'opzione di NewGameOptionsMenu specifica del player — un insediamento indigeno
# probabilmente non le usera' allo stesso modo, da decidere quando arrivera' questo passo),
# human_rules/folk_name propri di quel Folk (diversi da quelli del player), current_year.
func seed_indigenous_settlement(
	macro_coords: Vector2i,
	group_size: int,
	human_rules: HumanRules,
	folk_name: String,
	current_year: int
) -> HumanSeedingResult:
	# TODO: non ancora progettato. Aperto: se riusare _distribute_children/_create_adult/
	# _create_child cosi' come sono (probabile, sono gia' generici — nessuno dei tre conosce
	# "FAMILY"/"SMALL_GROUP"/"BIG_GROUP", solo numeri di coppie/figli), o se un insediamento
	# indigeno avra' una propria logica di composizione demografica diversa da quella del player.
	return null


# Ripartisce total_children tra couple_count coppie: base = total_children / couple_count a
# ciascuna, poi il resto (total_children % couple_count) distribuito UNA coppia a caso per
# unita' di resto — stessa formula per FAMILY/SMALL_GROUP/BIG_GROUP, nessun caso speciale per
# etichetta (verificato a mano per le tre composizioni attuali: FAMILY 3/1 coppia -> [3];
# SMALL_GROUP 4/3 coppie -> due coppie a caso [1,1] + una [2]; BIG_GROUP 8/6 coppie -> quattro
# coppie [1,1,1,1] + due a caso [2,2]).
func _distribute_children(couple_count: int, total_children: int) -> Array[int]:
	var base_count: int = total_children / couple_count
	var remainder: int = total_children % couple_count

	var per_couple: Array[int] = []
	for _i in range(couple_count):
		per_couple.append(base_count)

	var indices: Array[int] = []
	for i in range(couple_count):
		indices.append(i)
	indices.shuffle()
	for i in range(remainder):
		per_couple[indices[i]] += 1

	return per_couple


# Adulto fondatore: mother_id/father_id/partner_id restano al default -1 (valorizzati dal
# chiamante per partner_id, mai per mother_id/father_id — un fondatore non ha genitori noti in
# questa partita). Fascia FERTILE_ADULT o MATURE_ADULT scelta a caso (mai CHILD/OLD per un
# fondatore, come confermato), eta' pescata dentro l'intervallo reale di quella fascia via
# _age_band_year_range (primo consumatore vero di HumanRules.age_band_durations_male/female).
func _create_adult(human_rules: HumanRules, current_year: int, sex: HumanTypes.Sex, id: int) -> HumanIndividual:
	var individual := HumanIndividual.new()
	individual.id = id
	individual.sex = sex

	var age_band := HumanTypes.AgeBand.FERTILE_ADULT if randf() < 0.5 else HumanTypes.AgeBand.MATURE_ADULT
	var age := _random_age_in_band(human_rules, sex, age_band)
	individual.birth_year_virtual = current_year - int(round(age))

	individual.assign_random_name()
	# Fondatore, nessun genitore simulato — assign_hair_color() senza argomenti ripiega su random
	# puro (vedi HumanIndividual.gd).
	individual.assign_hair_color()
	individual.assign_random_clothing()
	return individual


# Coppia fondatrice "coordinata" per FAMILY (richiesta utente, 2026-09-02) — a differenza di due
# chiamate indipendenti a _create_adult, qui entrambi sono garantiti FERTILE_ADULT (mai
# MATURE_ADULT) e l'eta' del padre e' pescata VICINO a quella gia' assegnata alla madre (entro
# MAX_FAMILY_PARENT_AGE_GAP_YEARS), non indipendentemente — evita le coppie assurde viste con la
# selezione generica. Ritorna [mother, father] nell'ordine. used_names (richiesta utente,
# 2026-09-02): nomi tutti diversi dentro la famiglia — passato per riferimento, aggiornato QUI
# subito dopo ogni assign_random_name cosi' la chiamata successiva (padre, poi i figli nel
# chiamante) vede gia' i nomi presi finora.
func _create_family_couple(
	human_rules: HumanRules, current_year: int, next_id: int, used_names: Array[String]
) -> Array[HumanIndividual]:
	var mother := HumanIndividual.new()
	mother.id = next_id
	mother.sex = HumanTypes.Sex.FEMALE
	var mother_age := _random_age_in_band(human_rules, HumanTypes.Sex.FEMALE, HumanTypes.AgeBand.FERTILE_ADULT)
	mother.birth_year_virtual = current_year - int(round(mother_age))
	mother.assign_random_name(used_names)
	# Fondatrice, nessun genitore simulato — random puro (vedi assign_hair_color in HumanIndividual.gd).
	mother.assign_hair_color()
	mother.assign_random_clothing()
	used_names.append(mother.name)

	var father := HumanIndividual.new()
	father.id = next_id + 1
	father.sex = HumanTypes.Sex.MALE
	# Vicino all'eta' della madre, ma clampato dentro la fascia FERTILE_ADULT del padre — mai una
	# coppia dove uno dei due sia gia' fuori fertilita' pur di rispettare la vicinanza d'eta'.
	# Piccola distorsione statistica accettata quando la madre e' vicina a un bordo della fascia
	# (il padre finisce spinto verso quel bordo invece che simmetrico attorno a lei): comodo e
	# semplice, non serve altro per ora.
	var father_range := _age_band_year_range(human_rules, HumanTypes.Sex.MALE, HumanTypes.AgeBand.FERTILE_ADULT)
	var father_age := clampf(
		mother_age + randf_range(-MAX_FAMILY_PARENT_AGE_GAP_YEARS, MAX_FAMILY_PARENT_AGE_GAP_YEARS),
		father_range.x, father_range.y
	)
	father.birth_year_virtual = current_year - int(round(father_age))
	father.assign_random_name(used_names)
	# Fondatore, nessun genitore simulato — random puro (vedi assign_hair_color in HumanIndividual.gd).
	father.assign_hair_color()
	father.assign_random_clothing()
	used_names.append(father.name)

	return [mother, father]


# Figlio di una coppia gia' creata: mother_id/father_id valorizzati, partner_id resta -1 (nessuna
# logica di formazione coppie qui). Sesso libero (indipendente da quello dei genitori). Eta'
# vincolata dal genitore PIU' GIOVANE dei due (mai solo la madre: il vincolo deve valere contro
# entrambi) meno MIN_PARENT_CHILD_AGE_GAP_YEARS, clampata a >=0 e al massimo alla durata della
# fascia CHILD per il sesso del figlio — cosi' il vincolo "mai un figlio quasi coetaneo o piu'
# vecchio del genitore" e' garantito per costruzione qualunque eta' sia stata assegnata al
# genitore, invece di pescare l'eta' del figlio alla cieca e sperare che risulti compatibile.
# max_age_override (richiesta utente, 2026-09-02): -1.0 = nessun tetto oltre alla fascia CHILD
# (comportamento originale, SMALL_GROUP/BIG_GROUP), altrimenti un ulteriore tetto piu' stretto
# (FAMILY_CHILD_MAX_AGE_YEARS per FAMILY) — mai piu' largo della fascia CHILD stessa, solo piu'
# stretto.
# use_dynamic_parent_gap (richiesta utente, 2026-09-02, SOLO FAMILY): invece del gap flat
# MIN_PARENT_CHILD_AGE_GAP_YEARS, usa la durata della fascia CHILD del genitore PIU' GIOVANE +
# FAMILY_PARENT_CHILD_GAP_MARGIN_YEARS — il genitore deve aver gia' superato la propria infanzia
# da almeno quel margine, non solo rispettare un numero fisso scollegato dalla fascia CHILD vera
# del suo Folk. used_names (richiesta utente, 2026-09-02, SOLO FAMILY, default vuoto altrove):
# nomi tutti diversi dentro la famiglia — aggiornato QUI subito dopo assign_random_name, stesso
# schema di _create_family_couple.
func _create_child(
	human_rules: HumanRules, current_year: int, mother: HumanIndividual, father: HumanIndividual, id: int,
	max_age_override: float = -1.0, use_dynamic_parent_gap: bool = false, used_names: Array[String] = []
) -> HumanIndividual:
	var individual := HumanIndividual.new()
	individual.id = id
	individual.sex = HumanTypes.Sex.FEMALE if randf() < 0.5 else HumanTypes.Sex.MALE
	individual.mother_id = mother.id
	individual.father_id = father.id

	var mother_age: float = float(current_year - mother.birth_year_virtual)
	var father_age: float = float(current_year - father.birth_year_virtual)
	var youngest_parent_age: float
	var youngest_parent_sex: HumanTypes.Sex
	if mother_age <= father_age:
		youngest_parent_age = mother_age
		youngest_parent_sex = mother.sex
	else:
		youngest_parent_age = father_age
		youngest_parent_sex = father.sex

	var parent_child_gap: float = MIN_PARENT_CHILD_AGE_GAP_YEARS
	if use_dynamic_parent_gap:
		parent_child_gap = (
			_age_band_duration(human_rules, youngest_parent_sex, HumanTypes.AgeBand.CHILD)
			+ FAMILY_PARENT_CHILD_GAP_MARGIN_YEARS
		)

	var child_band_duration: float = _age_band_duration(human_rules, individual.sex, HumanTypes.AgeBand.CHILD)
	if max_age_override >= 0.0:
		child_band_duration = minf(child_band_duration, max_age_override)
	var max_child_age: float = maxf(0.0, minf(child_band_duration, youngest_parent_age - parent_child_gap))
	var age: float = randf_range(0.0, max_child_age) if max_child_age > 0.0 else 0.0
	individual.birth_year_virtual = current_year - int(round(age))

	individual.assign_random_name(used_names)
	# Unico punto di creazione con genitori VERI disponibili — 40/40/20 madre/padre/random (vedi
	# HumanIndividual.assign_hair_color per i pesi).
	individual.assign_hair_color(mother, father)
	individual.assign_random_clothing()
	used_names.append(individual.name)
	return individual


# Intervallo [inizio, fine) in anni di age_band per il sesso dato, ricavato sommando
# cumulativamente HumanRules.age_band_durations_male/female fino alla fascia richiesta — stesso
# ordine di HumanTypes.AgeBand (0=CHILD..3=OLD), indicizzato posizionalmente come il resto dei
# campi "per fascia" di HumanRules.
func _age_band_year_range(human_rules: HumanRules, sex: HumanTypes.Sex, age_band: HumanTypes.AgeBand) -> Vector2:
	var durations: Array[float] = (
		human_rules.age_band_durations_female if sex == HumanTypes.Sex.FEMALE else human_rules.age_band_durations_male
	)
	var start := 0.0
	for i in range(int(age_band)):
		start += durations[i]
	return Vector2(start, start + durations[age_band])


func _age_band_duration(human_rules: HumanRules, sex: HumanTypes.Sex, age_band: HumanTypes.AgeBand) -> float:
	var durations: Array[float] = (
		human_rules.age_band_durations_female if sex == HumanTypes.Sex.FEMALE else human_rules.age_band_durations_male
	)
	return durations[age_band]


func _random_age_in_band(human_rules: HumanRules, sex: HumanTypes.Sex, age_band: HumanTypes.AgeBand) -> float:
	var year_range := _age_band_year_range(human_rules, sex, age_band)
	return randf_range(year_range.x, year_range.y)
