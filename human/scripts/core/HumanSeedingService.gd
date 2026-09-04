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

# "COUPLE"/"FAMILY"/"GROUP" — stesse tre etichette gia' esposte da NewGameOptionsMenu/
# GameSettings.selected_group_size_preference/GameData.starting_group_size_preference. Rinominato
# da FAMILY/SMALL_GROUP/BIG_GROUP (richiesta utente, 2026-09-04): BIG_GROUP (20 individui)
# eliminato, SMALL_GROUP rinominato GROUP, aggiunto COUPLE (1 coppia, nessun figlio) come nuovo
# tipo piu' difficile.
const VALID_GROUP_SIZE_PREFERENCES: Array[String] = ["COUPLE", "FAMILY", "GROUP"]
const DEFAULT_GROUP_SIZE_PREFERENCE := "GROUP" # stesso default di GameSettings.selected_group_size_preference

# Numero di figli per FAMILY — SOLO consumatore rimasto (richiesta utente, 2026-09-04: COUPLE ora
# riusa _create_coordinated_couple come FAMILY, "senza i child", quindi non legge più questo
# Dictionary — vedi seed_player_start). Struttura Dictionary mantenuta (invece di una singola
# const int) per coerenza con lo stile "un blocco dati per tipo" del resto del progetto, e perché
# resta il punto naturale per un futuro ritocco del numero di figli senza dover cercare un altro
# posto. GROUP non vi compare mai (generatore dedicato, _create_unpaired_fertile_group).
const GROUP_SIZE_COMPOSITIONS := {
	"FAMILY": {"children": 3},
}

# Anni minimi tra l'eta' di un genitore e quella del figlio al momento della nascita — soglia di
# comodo dichiaratamente arbitraria (non derivata da alcun dato biologico reale), facile da
# ritarare in seguito senza toccare l'algoritmo che la usa.
const MIN_PARENT_CHILD_AGE_GAP_YEARS := 14

# Regole migliorative per la coppia — nate SOLO per FAMILY (richiesta utente, 2026-09-02), da un
# caso reale osservato con la vecchia selezione indipendente generica: madre/padre scelti
# indipendentemente (fascia + eta' a caso ciascuno) potevano finire a 50 e 13 anni — oltre ad
# essere assurdo di per se', il genitore piu' giovane dei due rendeva impossibile anche dare
# un'eta' sensata ai figli (vincolati da MIN_PARENT_CHILD_AGE_GAP_YEARS contro il genitore PIU'
# GIOVANE), risultando SEMPRE in figli tutti a eta' 0. RIVISTE e RIUSATE da COUPLE 2026-09-04 (vedi
# _create_coordinated_couple) — GROUP resta l'unico tipo sulla selezione indipendente pura (nessuna
# coppia da coordinare, vedi _create_unpaired_fertile_group).
#
# Margine (anni) tenuto DENTRO ciascun estremo della fascia FERTILE_ADULT per entrambi i genitori
# (richiesta utente, 2026-09-04 — sostituisce la precedente "differenza massima tra le due eta'"):
# né appena entrati né vicini a uscirne, stesso principio già in uso per GROUP (vedi
# _create_unpaired_fertile_group, che riusa questa stessa costante) — età fertile "adeguata"
# all'Era corrente, non ai bordi teorici della fascia grezza.
const FERTILE_EDGE_MARGIN_YEARS: float = 3.0
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


# Semina Folk + HumanPopulationGroup + HumanIndividual per il popolo del player, in UNA cella gia'
# scelta altrove (macro_coords, tipicamente il risultato di FirstStartMacroCellSelectionService —
# mai richiamato da qui). group_size_preference sconosciuta/vuota -> fallback
# DEFAULT_GROUP_SIZE_PREFERENCE (stesso principio "default neutro" gia' in uso ovunque nel
# progetto). human_rules/folk_name sono decisi dal chiamante (oggi GameScene carica direttamente il
# .tres del player) — questo servizio resta generico, non conosce alcun path su disco. current_year
# passato esplicitamente (non letto da GameData) per restare stateless, stesso principio di
# AnimalSeedingService che non tocca GameData.
#
# effective_age_band_durations_male/female (richiesta utente, 2026-09-04 — bugfix: prima questo
# file leggeva human_rules.age_band_durations_male/female DIRETTAMENTE, ignorando gli eventuali
# moltiplicatori dell'Era corrente — vedi EraCalculator.compute_effective_age_band_durations/
# GameData.era_effective_age_band_durations_male/female, introdotti in una sessione precedente ma
# mai collegati a nessun consumatore reale finora): il CHIAMANTE risolve le durate età-per-fascia
# GIA' scalate per l'Era (tipicamente game_data.era_effective_age_band_durations_male/female, dopo
# aver chiamato GameData.set_current_era) e le passa qui — questo servizio resta stateless, non
# tocca mai GameData/EraCalculator da sé (stesso principio di current_year sopra). human_rules
# resta comunque un parametro a sé: serve ancora per Folk.human_rules_ref (altri campi come
# workforce, mai le durate età, che ora passano SOLO dagli array qui sotto). NESSUN fallback
# difensivo se il chiamante passa array vuoti/troppo corti (il chiamante DEVE aver già risolto
# l'Era, vedi GameScene) — stesso principio "non validare scenari che non possono accadere" già
# seguito nel resto del progetto: _age_band_* sotto indicizzano durations[age_band] confidando
# che l'array copra tutte le 5 fasce di HumanTypes.AgeBand.
#
# Tre modelli di generazione DIVERSI e interamente separati a seconda della preferenza risolta
# (richiesta utente, 2026-09-04): GROUP usa _create_unpaired_fertile_group (10 adulti fertili
# indipendenti, nessuna coppia/figlio); FAMILY e COUPLE condividono entrambe _create_coordinated_
# couple (padre generato per primo, poi madre <= padre — richiesta utente, 2026-09-04: "stesse
# logiche della coppia in family, senza i child") — FAMILY aggiunge poi _create_family_children (3
# figli a età distinte), COUPLE si ferma alla coppia (nessun figlio, mai chiamata _create_family_
# children). _create_adult/_create_child restano infrastruttura generica non più chiamata da nessuno dei
# tre tipi attuali — tenuta per seed_indigenous_settlement sotto, che la cita esplicitamente come
# possibile riuso futuro. source_group_ref/posizione in griglia sono condivisi da tutti e tre,
# applicati DOPO in un unico passaggio qui sotto.
func seed_player_start(
	macro_coords: Vector2i,
	group_size_preference: String,
	human_rules: HumanRules,
	folk_name: String,
	current_year: int,
	effective_age_band_durations_male: Array[float],
	effective_age_band_durations_female: Array[float]
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

	var resolved_preference := (
		group_size_preference if VALID_GROUP_SIZE_PREFERENCES.has(group_size_preference) else DEFAULT_GROUP_SIZE_PREFERENCE
	)

	var individuals: Array[HumanIndividual] = []

	if resolved_preference == "GROUP":
		individuals = _create_unpaired_fertile_group(
			effective_age_band_durations_male, effective_age_band_durations_female, current_year
		)
	elif resolved_preference == "FAMILY":
		# FAMILY è sempre esattamente 1 coppia — percorso interamente dedicato (richiesta utente,
		# 2026-09-04), non più condiviso col ramo generico sotto: _distribute_children non serve
		# (nessuna distribuzione multi-coppia da fare, mai più di 1 coppia per FAMILY),
		# _create_family_children rimpiazza il vecchio loop _create_child per-figlio.
		var total_children: int = GROUP_SIZE_COMPOSITIONS["FAMILY"]["children"]
		var used_names: Array[String] = []

		var couple := _create_coordinated_couple(effective_age_band_durations_male, effective_age_band_durations_female, current_year, 1, used_names)
		var mother: HumanIndividual = couple[0]
		var father: HumanIndividual = couple[1]
		mother.partner_id = father.id
		father.partner_id = mother.id
		individuals.append(mother)
		individuals.append(father)

		var children := _create_family_children(
			effective_age_band_durations_male, effective_age_band_durations_female, current_year,
			mother, father, 3, total_children, used_names
		)
		individuals.append_array(children)
	else:
		# COUPLE (l'unica preferenza rimasta, dato che GROUP/FAMILY sono già gestite sopra — vedi
		# VALID_GROUP_SIZE_PREFERENCES) — richiesta utente, 2026-09-04: "molto semplice, un uomo e
		# una donna, con le stesse logiche con cui crei la coppia in family (senza i child)". Stesso
		# _create_coordinated_couple di FAMILY (padre generato per primo, poi madre <= padre — vedi
		# lì), semplicemente senza mai chiamare _create_family_children: GROUP_SIZE_COMPOSITIONS
		# ["COUPLE"].children è 0 per definizione, nessun figlio da creare per questo tipo.
		var couple := _create_coordinated_couple(
			effective_age_band_durations_male, effective_age_band_durations_female, current_year, 1, ([] as Array[String])
		)
		var mother: HumanIndividual = couple[0]
		var father: HumanIndividual = couple[1]
		mother.partner_id = father.id
		father.partner_id = mother.id
		individuals.append(mother)
		individuals.append(father)

	# source_group_ref — condiviso da entrambi i modelli sopra, spostato qui (era assegnato inline
	# nel solo ramo coppie+figli prima di questo passo) per non doverlo duplicare dentro
	# _create_unpaired_fertile_group, che non conosce/non deve conoscere HumanPopulationGroup.
	for individual in individuals:
		individual.source_group_ref = result.group

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
# quadrato per qualunque totale (2/5/10 secondo COUPLE/FAMILY/GROUP).
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
# group_size come conteggio diretto invece delle etichette COUPLE/FAMILY/GROUP (quelle
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
	# "COUPLE"/"FAMILY"/"GROUP", solo numeri di coppie/figli), o se un insediamento
	# indigeno avra' una propria logica di composizione demografica diversa da quella del player.
	return null


# Ripartisce total_children tra couple_count coppie: base = total_children / couple_count a
# ciascuna, poi il resto (total_children % couple_count) distribuito UNA coppia a caso per
# unita' di resto — stessa formula per COUPLE/FAMILY (le uniche due che passano ancora di qui da
# quando GROUP ha un generatore dedicato, _create_unpaired_fertile_group, senza coppie/figli),
# nessun caso speciale per etichetta (verificato a mano: COUPLE 0/1 coppia -> [0]; FAMILY 3/1
# coppia -> [3]).
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
# _age_band_year_range — durate GIA' scalate per l'Era corrente (vedi il commento su
# effective_age_band_durations_male/female in seed_player_start).
func _create_adult(
	durations_male: Array[float], durations_female: Array[float], current_year: int, sex: HumanTypes.Sex, id: int
) -> HumanIndividual:
	var individual := HumanIndividual.new()
	individual.id = id
	individual.sex = sex

	var age_band := HumanTypes.AgeBand.FERTILE_ADULT if randf() < 0.5 else HumanTypes.AgeBand.MATURE_ADULT
	var age := _random_age_in_band(durations_male, durations_female, sex, age_band)
	individual.birth_year_virtual = current_year - int(round(age))

	individual.assign_random_name()
	# Fondatore, nessun genitore simulato — assign_hair_color() senza argomenti ripiega su random
	# puro (vedi HumanIndividual.gd).
	individual.assign_hair_color()
	individual.assign_random_clothing()
	return individual


# Generatore dedicato per GROUP (richiesta utente, 2026-09-04) — 10 adulti FERTILE_ADULT
# indipendenti, 5 donne + 5 uomini, SENZA alcun legame di coppia o genitorialità reciproca: nessun
# partner_id incrociato (resta al default -1 di HumanIndividual — "non ancora accoppiato", un
# futuro meccanismo di accoppiamento in gioco, non ancora scritto, lo valorizzerà), tutti pensati
# per poter essere accoppiati tra loro in seguito.
#
# mother_id/father_id DELIBERATAMENTE distinti per ciascun individuo, mai il sentinel -1 condiviso
# usato ovunque altrove per "genitore sconosciuto/non applicabile" (es. _create_adult sopra): qui
# ogni fondatore riceve una coppia di id-fantasma NEGATIVI tutti diversi tra loro (offset -100 per
# la madre, -200 per il padre, dal proprio id locale — mai collidenti tra individui né tra i due
# campi) — così un futuro controllo "stesso genitore = fratelli, non accoppiabili" non tratterà per
# errore due fondatori come fratelli solo perché condividono lo stesso -1 di default. Restano
# comunque "non applicabile" per qualunque lettura esistente oggi (_format_id in
# HumanIndividualInfoPanel/HumanPopulationInfoPanel mostra "—" per QUALUNQUE valore < 0, non solo
# -1).
#
# Età: uniforme tra (inizio FERTILE_ADULT + FERTILE_EDGE_MARGIN_YEARS) e (fine FERTILE_ADULT -
# FERTILE_EDGE_MARGIN_YEARS) per il sesso dato — richiesta utente: mai ai bordi esatti della fascia
# (né appena usciti da TEENAGER né vicini a MATURE_ADULT), stessa costante ora condivisa con
# _create_coordinated_couple sotto (stesso identico principio di narrowing). Fallback all'inizio fascia
# se la durata di FERTILE_ADULT fosse troppo corta (< 2×FERTILE_EDGE_MARGIN_YEARS) per lasciare un
# intervallo valido — difensivo, non un caso atteso con i dati attuali.
# Durate GIA' scalate per l'Era corrente (vedi il commento su effective_age_band_durations_male/
# female in seed_player_start) — coi moltiplicatori del Paleolitico attuali (EraRules.
# longevity_multiplier_by_age = [1,1,0.6,0.6,0.6]), FERTILE_ADULT risulta più corta della durata
# base di HumanRules, quindi anche il range scalato qui sotto è più stretto di conseguenza.
func _create_unpaired_fertile_group(
	durations_male: Array[float], durations_female: Array[float], current_year: int
) -> Array[HumanIndividual]:
	var individuals: Array[HumanIndividual] = []
	var next_id := 1
	for sex in [HumanTypes.Sex.FEMALE, HumanTypes.Sex.MALE]:
		for _i in range(5):
			var individual := HumanIndividual.new()
			individual.id = next_id
			individual.sex = sex
			individual.mother_id = -(100 + next_id)
			individual.father_id = -(200 + next_id)

			var fertile_range := _age_band_year_range(durations_male, durations_female, sex, HumanTypes.AgeBand.FERTILE_ADULT)
			var min_age: float = fertile_range.x + FERTILE_EDGE_MARGIN_YEARS
			var max_age: float = fertile_range.y - FERTILE_EDGE_MARGIN_YEARS
			var age: float = randf_range(min_age, max_age) if max_age > min_age else fertile_range.x
			individual.birth_year_virtual = current_year - int(round(age))

			individual.assign_random_name()
			# Fondatore, nessun genitore simulato — random puro (vedi assign_hair_color in HumanIndividual.gd).
			individual.assign_hair_color()
			individual.assign_random_clothing()
			individuals.append(individual)
			next_id += 1
	return individuals


# Coppia fondatrice "coordinata" — nata per FAMILY (richiesta utente, 2026-09-02, REGOLE RIVISTE
# 2026-09-04), riusata ORA anche da COUPLE (richiesta utente, 2026-09-04: "un uomo e una donna, con
# le stesse logiche con cui crei la coppia in family, senza i child") — da qui il nome generico
# senza riferimento a FAMILY. Entrambi i genitori sono FERTILE_ADULT, con età tenuta lontana da
# entrambi gli estremi della fascia (FERTILE_EDGE_MARGIN_YEARS, stessa costante/principio di
# _create_unpaired_fertile_group — "età fertile adeguata all'Era", non ai bordi teorici). Ordine di
# creazione significativo (richiesta utente): il PADRE viene generato per primo, età uniforme nel
# proprio range ristretto; la MADRE viene generata dopo e vincolata a un'età <= a quella del padre
# (oltre a restare comunque dentro il proprio range ristretto). Ritorna [mother, father] nell'ordine
# (invariato per compatibilità coi chiamanti), anche se internamente il padre è il primo a essere
# costruito. used_names: nomi tutti diversi dentro la coppia (e i suoi eventuali figli, per FAMILY)
# — passato per riferimento, aggiornato QUI subito dopo ogni assign_random_name cosi' la chiamata
# successiva (madre, poi gli eventuali figli nel chiamante) vede gia' i nomi presi finora. COUPLE
# passa un array vuoto "usa e getta" (nessun figlio dopo, nessun dedup oltre padre/madre stessi).
func _create_coordinated_couple(
	durations_male: Array[float], durations_female: Array[float], current_year: int, next_id: int, used_names: Array[String]
) -> Array[HumanIndividual]:
	var father := HumanIndividual.new()
	father.id = next_id
	father.sex = HumanTypes.Sex.MALE
	var father_range := _age_band_year_range(durations_male, durations_female, HumanTypes.Sex.MALE, HumanTypes.AgeBand.FERTILE_ADULT)
	var father_min: float = father_range.x + FERTILE_EDGE_MARGIN_YEARS
	var father_max: float = father_range.y - FERTILE_EDGE_MARGIN_YEARS
	var father_age: float = randf_range(father_min, father_max) if father_max > father_min else father_range.x
	father.birth_year_virtual = current_year - int(round(father_age))
	father.assign_random_name(used_names)
	# Fondatore, nessun genitore simulato — random puro (vedi assign_hair_color in HumanIndividual.gd).
	father.assign_hair_color()
	father.assign_random_clothing()
	used_names.append(father.name)

	var mother := HumanIndividual.new()
	mother.id = next_id + 1
	mother.sex = HumanTypes.Sex.FEMALE
	var mother_range := _age_band_year_range(durations_male, durations_female, HumanTypes.Sex.FEMALE, HumanTypes.AgeBand.FERTILE_ADULT)
	var mother_min: float = mother_range.x + FERTILE_EDGE_MARGIN_YEARS
	var mother_band_max: float = mother_range.y - FERTILE_EDGE_MARGIN_YEARS
	# Tetto = età del padre, ma MAI sotto mother_min: se il padre risultasse più giovane del minimo
	# ristretto della madre (non capita con i dati attuali, dove i due minimi coincidono a 18 anni
	# nel Paleolitico — vedi ricognizione — ma resta un limite teorico possibile con dati futuri
	# diversi), la madre ripiega sul proprio minimo invece di produrre un intervallo invertito.
	var mother_max: float = clampf(father_age, mother_min, mother_band_max)
	var mother_age: float = randf_range(mother_min, mother_max) if mother_max > mother_min else mother_min
	mother.birth_year_virtual = current_year - int(round(mother_age))
	mother.assign_random_name(used_names)
	# Fondatrice, nessun genitore simulato — random puro (vedi assign_hair_color in HumanIndividual.gd).
	mother.assign_hair_color()
	mother.assign_random_clothing()
	used_names.append(mother.name)

	return [mother, father]


# 3 figli con età INTERE e DISTINTE tra loro (richiesta utente, 2026-09-04 — "0,1,3 ok, 1,1,2 no"):
# a differenza del vecchio _create_child sotto (oggi non più chiamato da nessun tipo attivo — resta
# solo infrastruttura generica per un futuro consumatore, es. seed_indigenous_settlement), qui
# l'età di ciascun figlio è pre-assegnata da un pool di
# interi 0..max_child_age SENZA ripetizioni, invece di essere sorteggiata indipendentemente per
# ciascuno (che permetteva duplicati per puro caso — irrilevante finché l'età viene comunque
# arrotondata all'anno intero via birth_year_virtual, ma osservabile in gioco come "due fratelli
# della stessa identica età").
#
# max_child_age: stessa identica formula di _create_child (gap dinamico dal genitore più giovane +
# FAMILY_PARENT_CHILD_GAP_MARGIN_YEARS, tetto FAMILY_CHILD_MAX_AGE_YEARS), calcolata UNA sola volta
# qui invece che per ciascun figlio — è la stessa per tutti e tre (stessi genitori). A differenza
# di _create_child, qui NON si considera la fascia CHILD del figlio stesso (dipenderebbe dal suo
# sesso, non ancora deciso a questo punto): FAMILY_CHILD_MAX_AGE_YEARS (3) è sempre più stretto
# della fascia CHILD vera (10 anche nel Paleolitico attuale), quindi il tetto reale è sempre
# l'override, mai la fascia stessa — nessuna perdita di correttezza nel saltare quel controllo qui.
#
# child_count preso da GROUP_SIZE_COMPOSITIONS["FAMILY"]["children"] dal chiamante (mai hardcoded
# "3" qui dentro), così un futuro ritocco di quel numero non richiede toccare anche questa funzione.
func _create_family_children(
	durations_male: Array[float], durations_female: Array[float], current_year: int,
	mother: HumanIndividual, father: HumanIndividual, next_id: int, child_count: int, used_names: Array[String]
) -> Array[HumanIndividual]:
	var mother_age: float = float(current_year - mother.birth_year_virtual)
	var father_age: float = float(current_year - father.birth_year_virtual)
	var youngest_parent_age: float = minf(mother_age, father_age)
	var youngest_parent_sex: HumanTypes.Sex = mother.sex if mother_age <= father_age else father.sex

	var parent_child_gap: float = (
		_age_band_duration(durations_male, durations_female, youngest_parent_sex, HumanTypes.AgeBand.CHILD)
		+ FAMILY_PARENT_CHILD_GAP_MARGIN_YEARS
	)
	var max_child_age: float = maxf(0.0, minf(FAMILY_CHILD_MAX_AGE_YEARS, youngest_parent_age - parent_child_gap))

	# Pool di età intere distinte disponibili in [0, max_child_age] — quante ce ne sono dipende da
	# quanto è ampio max_child_age (coi dati attuali sempre >= FAMILY_CHILD_MAX_AGE_YEARS, vedi
	# sopra, quindi il pool copre sempre {0,1,2,3}, più che sufficiente per child_count=3).
	var available_ages: Array[int] = []
	for a in range(int(floor(max_child_age)) + 1):
		available_ages.append(a)
	available_ages.shuffle()

	var children: Array[HumanIndividual] = []
	for c in range(child_count):
		# Fallback (dati futuri con max_child_age molto più stretta di oggi): se il pool di interi
		# distinti si esaurisce prima di child_count, i figli in eccesso tornano al vecchio
		# sorteggio indipendente — duplicati possibili SOLO in questo caso limite, mai col tuning
		# attuale (pool sempre >= 4 valori contro 3 figli richiesti).
		var age: float = float(available_ages[c]) if c < available_ages.size() else randf_range(0.0, max_child_age)
		var child := HumanIndividual.new()
		child.id = next_id + c
		child.sex = HumanTypes.Sex.FEMALE if randf() < 0.5 else HumanTypes.Sex.MALE
		child.mother_id = mother.id
		child.father_id = father.id
		child.birth_year_virtual = current_year - int(round(age))
		child.assign_random_name(used_names)
		# Unico punto di creazione con genitori VERI disponibili — 40/40/20 madre/padre/random
		# (regola genetica già esistente, confermata con l'utente — vedi
		# HumanIndividual.assign_hair_color per i pesi).
		child.assign_hair_color(mother, father)
		child.assign_random_clothing()
		used_names.append(child.name)
		children.append(child)
	return children


# Figlio di una coppia gia' creata: mother_id/father_id valorizzati, partner_id resta -1 (nessuna
# logica di formazione coppie qui). Sesso libero (indipendente da quello dei genitori). Eta'
# vincolata dal genitore PIU' GIOVANE dei due (mai solo la madre: il vincolo deve valere contro
# entrambi) meno MIN_PARENT_CHILD_AGE_GAP_YEARS, clampata a >=0 e al massimo alla durata della
# fascia CHILD per il sesso del figlio — cosi' il vincolo "mai un figlio quasi coetaneo o piu'
# vecchio del genitore" e' garantito per costruzione qualunque eta' sia stata assegnata al
# genitore, invece di pescare l'eta' del figlio alla cieca e sperare che risulti compatibile.
#
# FAMILY (richiesta utente, 2026-09-04) non passa più di qui — ha un proprio generatore dedicato,
# _create_family_children sopra (età distinte tra fratelli, genitori generati con regole proprie).
# Questa funzione resta generica per COUPLE (oggi sempre chiamata con soli i parametri richiesti,
# 0 figli in pratica) e per un futuro consumatore (es. seed_indigenous_settlement) che voglia
# esattamente il vecchio comportamento indipendente: max_age_override/use_dynamic_parent_gap/
# used_names sono rimasti come parametri opzionali (default = comportamento originale, mai
# richiesti dai chiamanti attuali) proprio per questo.
func _create_child(
	durations_male: Array[float], durations_female: Array[float], current_year: int,
	mother: HumanIndividual, father: HumanIndividual, id: int,
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
			_age_band_duration(durations_male, durations_female, youngest_parent_sex, HumanTypes.AgeBand.CHILD)
			+ FAMILY_PARENT_CHILD_GAP_MARGIN_YEARS
		)

	var child_band_duration: float = _age_band_duration(durations_male, durations_female, individual.sex, HumanTypes.AgeBand.CHILD)
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
# cumulativamente durations_male/female fino alla fascia richiesta — stesso ordine di
# HumanTypes.AgeBand (0=CHILD..4=OLD), indicizzato posizionalmente come il resto dei campi "per
# fascia" di HumanRules. durations_male/female sono le durate GIA' scalate per l'Era corrente
# (vedi il commento su effective_age_band_durations_male/female in seed_player_start) — MAI
# HumanRules.age_band_durations_male/female letto direttamente da qui, a differenza di prima
# (bugfix, richiesta utente 2026-09-04).
func _age_band_year_range(durations_male: Array[float], durations_female: Array[float], sex: HumanTypes.Sex, age_band: HumanTypes.AgeBand) -> Vector2:
	var durations: Array[float] = durations_female if sex == HumanTypes.Sex.FEMALE else durations_male
	var start := 0.0
	for i in range(int(age_band)):
		start += durations[i]
	return Vector2(start, start + durations[age_band])


func _age_band_duration(durations_male: Array[float], durations_female: Array[float], sex: HumanTypes.Sex, age_band: HumanTypes.AgeBand) -> float:
	var durations: Array[float] = durations_female if sex == HumanTypes.Sex.FEMALE else durations_male
	return durations[age_band]


func _random_age_in_band(durations_male: Array[float], durations_female: Array[float], sex: HumanTypes.Sex, age_band: HumanTypes.AgeBand) -> float:
	var year_range := _age_band_year_range(durations_male, durations_female, sex, age_band)
	return randf_range(year_range.x, year_range.y)
