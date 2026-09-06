class_name HumanConceptionIndividualService
extends RefCounted

# Concepimento annuale (SOLO concepimento — il parto/nascita è un task separato, non ancora
# scritto), per HumanPopulationGroup — stesso principio di HumanCouplingIndividualService/
# HumanMortalityIndividualService: un *Service RefCounted stateless, un metodo statico che opera su
# un Array[HumanIndividual], raggruppando internamente per source_group_ref (vedi
# HumanCouplingIndividualService.form_couples per lo stesso schema di raggruppamento, riusato identico qui).
#
# durations_male/durations_female/human_rules/era_rules sono tutti GIA' RISOLTI dal chiamante
# (GameTimeService), mai letti/ricalcolati da questo file — stesso principio di
# HumanMortalityIndividualService.check_mortality: il chiamante decide quali durate/regole passare
# (tipicamente quelle effettive per l'Era corrente), questo service resta puro rispetto alla loro
# provenienza.
#
# era_rules.conception_probability_multiplier è letto QUI direttamente al momento del calcolo
# (moltiplicazione scalare singola, una volta l'anno, per il solo gruppo in esame) — NON esiste (e
# non va creato) un canale di cache "probabilità effettiva" in EraCalculator: quello esiste solo
# per le durate delle age band (lette ad ogni giorno da più punti, da cui il bisogno di una cache),
# caso diverso da questo (verificato con l'utente, 2026-09-06).


# Vero se `woman` ha almeno un figlio (mother_id == woman.id, cercato in `individuals` — lo stesso
# gruppo passato dal chiamante) con età in anni interi <= min_birth_spacing_years. Confronto diretto
# su birth_year_virtual (NON tramite HumanCalculator.get_age_band — richiesta esplicita: qui serve
# l'età anagrafica vera, non la fascia). <= e non < (richiesta esplicita, 2026-09-06): con soglia=1,
# un figlio di ESATTAMENTE 1 anno blocca ancora la madre, solo un figlio di 2+ anni la libera.
static func _has_child_below_spacing_threshold(
	woman: HumanIndividual, individuals: Array[HumanIndividual], current_year: int, min_birth_spacing_years: int
) -> bool:
	for child in individuals:
		if child.mother_id != woman.id:
			continue
		var child_age := current_year - child.birth_year_virtual
		if child_age <= min_birth_spacing_years:
			return true
	return false


static func _find_by_id(individuals: Array[HumanIndividual], id: int) -> HumanIndividual:
	for individual in individuals:
		if individual.id == id:
			return individual
	return null


# Entry point annuale (day 110): concepimento per ciascun HumanPopulationGroup rappresentato in
# `individuals`, separatamente — stesso raggruppamento via source_group_ref di
# HumanCouplingIndividualService.form_couples. Ritorna un Dictionary con, oltre a
# "newly_pregnant"/"query_time_usec" di prima:
#   "eligible_women": Array[HumanIndividual] — passate il filtro (A) (sesso/gravidanza/partner/
#     età_band), su TUTTI i gruppi
#   "excluded_already_pregnant"/"excluded_self_not_fertile"/"excluded_partner_not_fertile"/
#     "excluded_partner_missing": Array[HumanIndividual] — coppie (donna con partner) escluse in
#     (A), suddivise per motivo (richiesta utente, 2026-09-06: distinguere "lei non più fertile" da
#     "il partner non più fertile" da "già incinta", non solo un conteggio idonee generico)
#   "discarded_for_spacing": Array[HumanIndividual] — idonee ma scartate dal filtro (B) (figlio
#     troppo giovane)
#   "candidates": Array[HumanIndividual] — sopravvissute anche a (B), quelle su cui gira il tiro (C)
#   "conception_probability": float — la stessa per tutti i gruppi in questa chiamata (dipende solo
#     da human_rules/era_rules, mai dai dati del gruppo), calcolata una sola volta qui
#   "min_birth_spacing_years": int — la soglia usata dal filtro (B), da era_rules
# (richiesta utente, 2026-09-06 — log esplicativo di scarti/tiro, non solo il conteggio finale).
static func run_conception(
	individuals: Array[HumanIndividual],
	current_year: int,
	durations_male: Array[float],
	durations_female: Array[float],
	human_rules: HumanRules,
	era_rules: EraRules
) -> Dictionary:
	var groups: Dictionary = {}
	for individual in individuals:
		var group_key: HumanPopulationGroup = individual.source_group_ref
		if not groups.has(group_key):
			groups[group_key] = [] as Array[HumanIndividual]
		groups[group_key].append(individual)
	var eligible_women: Array[HumanIndividual] = []
	var excluded_already_pregnant: Array[HumanIndividual] = []
	var excluded_self_not_fertile: Array[HumanIndividual] = []
	var excluded_partner_not_fertile: Array[HumanIndividual] = []
	var excluded_partner_missing: Array[HumanIndividual] = []
	var discarded_for_spacing: Array[HumanIndividual] = []
	var candidates: Array[HumanIndividual] = []
	var newly_pregnant: Array[HumanIndividual] = []
	var query_time_usec := 0
	for group_individuals in groups.values():
		var result := _run_conception_in_group(
			group_individuals, current_year, durations_male, durations_female, human_rules, era_rules
		)
		eligible_women.append_array(result["eligible_women"])
		excluded_already_pregnant.append_array(result["excluded_already_pregnant"])
		excluded_self_not_fertile.append_array(result["excluded_self_not_fertile"])
		excluded_partner_not_fertile.append_array(result["excluded_partner_not_fertile"])
		excluded_partner_missing.append_array(result["excluded_partner_missing"])
		discarded_for_spacing.append_array(result["discarded_for_spacing"])
		candidates.append_array(result["candidates"])
		newly_pregnant.append_array(result["newly_pregnant"])
		query_time_usec += result["query_time_usec"]
	return {
		"eligible_women": eligible_women,
		"excluded_already_pregnant": excluded_already_pregnant,
		"excluded_self_not_fertile": excluded_self_not_fertile,
		"excluded_partner_not_fertile": excluded_partner_not_fertile,
		"excluded_partner_missing": excluded_partner_missing,
		"discarded_for_spacing": discarded_for_spacing,
		"candidates": candidates,
		"newly_pregnant": newly_pregnant,
		"query_time_usec": query_time_usec,
		# Costanti rispetto ai dati del gruppo (solo human_rules/era_rules) — calcolate una volta
		# sola qui invece che ripetute identiche in ogni risultato per-gruppo.
		"conception_probability": human_rules.conception_base_probability * era_rules.conception_probability_multiplier,
		"min_birth_spacing_years": era_rules.min_birth_spacing_years,
	}


# Concepimento per un SINGOLO gruppo (già filtrato da run_conception sopra). Tre fasi distinte:
# (A) filtri economici età/partner/gravidanza — MAI cronometrati, solo la query genealogica in (B)
# lo è, come richiesto; (B) query "figli sotto soglia" per le sole donne sopravvissute al filtro
# (A) — fase esplicitamente cronometrata; (C) tiro di concepimento per le sole candidate
# sopravvissute anche a (B).
static func _run_conception_in_group(
	individuals: Array[HumanIndividual],
	current_year: int,
	durations_male: Array[float],
	durations_female: Array[float],
	human_rules: HumanRules,
	era_rules: EraRules
) -> Dictionary:
	# (A) Filtri economici: sesso, non già incinta, partner presente e FERTILE_ADULT quanto lei.
	# Bucket di esclusione per tipo (richiesta utente, 2026-09-06 — log esplicativo fin da questa
	# prima fase, non solo dalla soglia di spaziamento): "coppia" qui = donna con partner_id != -1
	# (contata dal solo lato femminile — HumanCouplingIndividualService.form_couples imposta
	# partner_id simmetricamente sui due lati, contare da entrambi conterebbe ogni coppia due
	# volte). Donne SENZA partner non sono "una coppia" per definizione, quindi non entrano in
	# nessun bucket qui sotto — restano escluse in silenzio come sempre, non sono l'oggetto di
	# questo log (che parla di COPPIE, non di ogni singola donna del gruppo).
	var eligible_women: Array[HumanIndividual] = []
	var excluded_already_pregnant: Array[HumanIndividual] = []
	var excluded_self_not_fertile: Array[HumanIndividual] = []
	var excluded_partner_not_fertile: Array[HumanIndividual] = []
	var excluded_partner_missing: Array[HumanIndividual] = []
	for woman in individuals:
		if woman.sex != HumanTypes.Sex.FEMALE:
			continue
		if woman.partner_id == -1:
			continue
		if woman.is_pregnant:
			excluded_already_pregnant.append(woman)
			continue
		var woman_age := current_year - woman.birth_year_virtual
		var woman_age_band := HumanCalculator.get_age_band(durations_male, durations_female, woman.sex, float(woman_age))
		if woman_age_band != HumanTypes.AgeBand.FERTILE_ADULT:
			excluded_self_not_fertile.append(woman)
			continue
		var partner := _find_by_id(individuals, woman.partner_id)
		if partner == null:
			# Difensivo (non dovrebbe capitare: partner_id di un vivo dovrebbe sempre risolversi
			# dentro lo stesso gruppo) — bucket a sé per non confonderlo con "partner non fertile"
			# se mai succedesse.
			excluded_partner_missing.append(woman)
			continue
		var partner_age := current_year - partner.birth_year_virtual
		var partner_age_band := HumanCalculator.get_age_band(durations_male, durations_female, partner.sex, float(partner_age))
		if partner_age_band != HumanTypes.AgeBand.FERTILE_ADULT:
			excluded_partner_not_fertile.append(woman)
			continue
		eligible_women.append(woman)

	# (B) Query "figli sotto soglia" — SOLO questo blocco cronometrato (richiesta utente).
	# discarded_for_spacing (2026-09-06, richiesta utente: log esplicativo) — le idonee che
	# NON diventano candidate, per poterle mostrare separatamente nel log invece di sparire nel
	# nulla tra "idonee" e "candidate al tiro".
	var query_start_usec := Time.get_ticks_usec()
	var candidates: Array[HumanIndividual] = []
	var discarded_for_spacing: Array[HumanIndividual] = []
	for woman in eligible_women:
		if _has_child_below_spacing_threshold(woman, individuals, current_year, era_rules.min_birth_spacing_years):
			discarded_for_spacing.append(woman)
		else:
			candidates.append(woman)
	var query_time_usec := Time.get_ticks_usec() - query_start_usec

	# (C) Tiro di concepimento: base di HumanRules × moltiplicatore di EraRules, letto qui al
	# momento del calcolo (nessuna cache — vedi commento di testa al file).
	var conception_probability := human_rules.conception_base_probability * era_rules.conception_probability_multiplier
	var newly_pregnant: Array[HumanIndividual] = []
	for woman in candidates:
		if randf() < conception_probability:
			woman.is_pregnant = true
			# Step 2 del piano riproduzione (2026-09-06): tratti/padre del figlio in arrivo
			# CRISTALLIZZATI qui, una volta sola — padre = partner ATTUALE di `woman` (già risolto
			# e verificato FERTILE_ADULT in (A) sopra, ri-cercato qui perché quella variabile locale
			# non sopravvive oltre il ciclo di (A) — sicuramente vivo in questo istante, zero
			# ambiguità). HumanBirthIndividualService (day 20) userà SOLO questi tre campi, mai
			# woman.partner_id: se il padre muore tra concepimento e nascita, il tiro è comunque già
			# fatto e non va rifatto (vedi HumanIndividual.pending_child_father_id).
			var father := _find_by_id(individuals, woman.partner_id)
			woman.pending_child_hair_color = HumanIndividual.roll_inherited_hair_color(woman, father)
			woman.pending_child_skin_color = HumanIndividual.roll_inherited_skin_color(woman, father)
			woman.pending_child_father_id = father.id
			newly_pregnant.append(woman)

	return {
		"eligible_women": eligible_women,
		"excluded_already_pregnant": excluded_already_pregnant,
		"excluded_self_not_fertile": excluded_self_not_fertile,
		"excluded_partner_not_fertile": excluded_partner_not_fertile,
		"excluded_partner_missing": excluded_partner_missing,
		"discarded_for_spacing": discarded_for_spacing,
		"candidates": candidates,
		"newly_pregnant": newly_pregnant,
		"query_time_usec": query_time_usec,
	}
