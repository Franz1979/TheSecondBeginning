class_name HumanMortalityIndividualService
extends RefCounted

# Determinazione annuale di chi muore per età (MATURE_ADULT/OLD) — Step 3/4 del piano mortalità
# (vedi HumanRules.mortality_prob_at_mature_start/mortality_prob_at_old_end/absolute_max_age e
# HumanCalculator.get_annual_death_probability, Step 1/2). Un file a parte da HumanCalculator
# (calcoli scalari per-individuo, mai una lista) perché questa è invece un'operazione di gruppo su
# un intero Array[HumanIndividual] — stesso principio già seguito lato mondo/animali per la
# separazione tra un *Calculator (scalare, stateless) e un *Service (che opera su collezioni),
# es. ResourceCalculator vs ResourceMortalityService.
#
# Rinominato da HumanMortalityService (Step 4, richiesta utente) — "Individual" nel nome per
# distinguerlo fin da ora da un futuro HumanMortalityAggregateService (calcolo per popolazioni
# lontane/rappresentate solo in forma aggregata, non ancora scritto), sullo stesso principio già
# in uso lato animale (AnimalMortalityAggregateService accanto al calcolo individuale esistente).
# Questo file resta quello "individuale" — un HumanIndividual reale per volta, mai un aggregato.
#
# Step 3: solo query, nessuna scrittura su HumanIndividual, nessuna rimozione dagli array del
# chiamante (Step 6). Step 4 (questo): check_mortality scrive scheduled_death_day SUGLI individui
# marcati (unico campo toccato in questo step) — ancora nessuna rimozione reale, nessun aggancio
# al tick giornaliero (Step 6).


# Determina quali individui di `individuals` moriranno quest'anno, assegnando loro
# HumanIndividual.scheduled_death_day (un giorno 0-365 estratto una volta sola). Skip diretto
# (nessun tiro di dado) per CHILD/TEENAGER/FERTILE_ADULT: solo MATURE_ADULT/OLD hanno una
# probabilità di morte per età (vedi HumanCalculator.get_annual_death_probability, 0.0 sotto
# l'inizio di MATURE_ADULT per costruzione — il controllo qui evita comunque di tirare un dado
# inutile per età sotto quella soglia). age_band risolto con HumanCalculator.get_age_band, stesso
# sesso dell'individuo e le durate passate dal chiamante (vedi durations_male/female sotto).
#
# current_year (aggiunto rispetto alla firma proposta, che aveva solo individuals/rules):
# HumanIndividual non salva l'età come campo — solo birth_year_virtual (vedi HumanIndividual.gd,
# "l'età si ricava sempre al volo... mai salvata come campo separato") — serve quindi l'anno
# corrente per calcolare age = current_year - birth_year_virtual, esattamente come fa il resto del
# progetto (es. i pannelli info umani).
#
# durations_male/female AGGIUNTI (richiesta utente, 2026-09-05 — bugfix: PRIMA questo metodo
# leggeva rules.age_band_durations_male/female DIRETTAMENTE per il gate age_band, ignorando lo
# scaling per Era — un individuo poteva risultare ancora FERTILE_ADULT/MATURE_ADULT qui mentre il
# pannello (che usa game_data.era_effective_age_band_durations_male/female) lo mostrava già OLD).
# Il chiamante decide quali durate passare — tipicamente quelle effettive scalate per Era, stesso
# principio già seguito da HumanCalculator.get_age_band/HumanSeedingService — e sono le STESSE
# passate a HumanCalculator.get_annual_death_probability sotto, mai due fonti diverse per lo
# stesso individuo nella stessa chiamata.
#
# scheduled_death_day è l'UNICO campo scritto qui (a differenza di età/age_band, mai persistiti,
# questo va persistito: è un'estrazione singola non ricalcolabile — ritirare il dado una seconda
# volta darebbe un giorno diverso). Nessun individuo NON marcato viene toccato — resta al proprio
# valore precedente di scheduled_death_day (-1 di default, "nessuna morte programmata quest'anno").
#
# Ritorna comunque la lista dei marcati (nessun cambio di scopo rispetto allo Step 3), solo ora con
# scheduled_death_day già valorizzato su ciascuno.
static func check_mortality(
	individuals: Array[HumanIndividual],
	rules: HumanRules,
	current_year: int,
	durations_male: Array[float],
	durations_female: Array[float]
) -> Array[HumanIndividual]:
	var marked_for_death: Array[HumanIndividual] = []
	for individual in individuals:
		var age := current_year - individual.birth_year_virtual
		var age_band := HumanCalculator.get_age_band(durations_male, durations_female, individual.sex, float(age))
		if age_band != HumanTypes.AgeBand.MATURE_ADULT and age_band != HumanTypes.AgeBand.OLD:
			continue
		if randf() < HumanCalculator.get_annual_death_probability(age, rules, durations_male, durations_female):
			# 0..DAYS_PER_YEAR-1 (0..364), non 0..365: stesso range di GameData.current_day — 365
			# non è mai un giorno valido (GameData.advance_day avvolge a 0 prima di raggiungerlo).
			individual.scheduled_death_day = randi() % GameData.DAYS_PER_YEAR
			marked_for_death.append(individual)
	return marked_for_death
