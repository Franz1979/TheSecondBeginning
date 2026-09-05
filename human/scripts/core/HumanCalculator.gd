class_name HumanCalculator
extends RefCounted

# Calcoli di supporto per il dominio umano, stateless — stesso ruolo/pattern di
# AnimalCalculator/BuildingCalculator lato simulazione, ma nessuna dipendenza da quelli.

# Fascia d'età corrispondente a `age` (anni) per il sesso dato, camminando cumulativamente
# durations_male/female fino a trovare quella che la contiene — stesso ordine di HumanTypes.AgeBand
# (0=CHILD..4=OLD). Età oltre l'ultima fascia (durate tutte esaurite, es. durations non ancora
# tarate/zero) ricade su OLD, l'ultima fascia esistente, invece di andare fuori range: nessun
# individuo può risultare "senza fascia".
#
# durations_male/female sono le durate GIA' scalate per l'Era corrente (bugfix, richiesta utente
# 2026-09-04 — PRIMA questo metodo prendeva HumanRules e leggeva age_band_durations_male/female
# DIRETTAMENTE, ignorando i moltiplicatori dell'Era: un individuo già MATURE_ADULT/OLD per l'Era
# corrente poteva risultare mostrato come FERTILE_ADULT). Tipicamente
# game_data.era_effective_age_band_durations_male/female — vedi EraCalculator.
# compute_effective_age_band_durations/GameData.set_current_era. Stesso principio già applicato a
# HumanSeedingService: mai HumanRules.age_band_durations_male/female letto direttamente da qui.
static func get_age_band(durations_male: Array[float], durations_female: Array[float], sex: HumanTypes.Sex, age: float) -> HumanTypes.AgeBand:
	var durations: Array[float] = durations_female if sex == HumanTypes.Sex.FEMALE else durations_male
	var cumulative := 0.0
	for i in range(durations.size()):
		cumulative += durations[i]
		if age < cumulative:
			return i
	return HumanTypes.AgeBand.OLD


# Età (anni) di inizio di age_band, sommando cumulativamente durations fino alla fascia
# precedente — stesso scan cumulativo di get_age_band sopra, letto nella direzione opposta (fascia
# -> età di inizio invece di età -> fascia). Un solo array durations (non male/female distinti come
# get_age_band): il chiamante decide quali durate passare — vedi get_annual_death_probability
# sotto, che passa la media dei due sessi per una curva di mortalità deliberatamente
# sesso-indipendente (age_band_durations_male/female restano un asse a parte, non collassato qui
# in generale — solo questa curva lo ignora).
static func get_age_band_start_age(durations: Array[float], age_band: HumanTypes.AgeBand) -> float:
	var start := 0.0
	for i in range(int(age_band)):
		start += durations[i]
	return start


# Probabilità di morte annuale in funzione dell'età, curva continua (non per age-band come i
# moltiplicatori sopra) ancorata a due estremi scalari di HumanRules
# (mortality_prob_at_mature_start/mortality_prob_at_old_end, vedi HumanRules.gd) più un tetto
# assoluto (absolute_max_age). Funzione pura, nessuno stato/individuo reale coinvolto — solo age +
# rules + durate. Sesso deliberatamente ignorato (a differenza di get_age_band, che lo richiede):
# la curva usa la MEDIA di durations_male/female per calcolare i due estremi d'età (inizio
# MATURE_ADULT, fine nominale di OLD), invece di richiedere un sesso come get_age_band — questi tre
# campi HumanRules sono scalari singoli, non per-sesso, quindi non ha senso far dipendere la curva
# da un HumanTypes.Sex che non userebbe comunque.
#
# durations_male/female AGGIUNTI come parametri espliciti (richiesta utente, 2026-09-05 — PRIMA
# leggeva rules.age_band_durations_male/female DIRETTAMENTE, ignorando qualunque scaling per Era:
# un individuo in un'Era con longevity_multiplier_by_age < 1 risultava valutato con soglie
# "troppo lunghe" rispetto a quanto i pannelli mostravano già, vedi discussione con l'utente sul
# Paleolitico — MATURE_ADULT lì inizia a 33/30 anni scalati, non 45/40 base). Stesso principio già
# seguito da get_age_band/HumanSeedingService: il chiamante decide se passare le durate BASE di
# HumanRules o quelle EFFETTIVE (game_data.era_effective_age_band_durations_male/female) — questa
# funzione non lo sa e non le legge mai da sola.
static func get_annual_death_probability(
	age: int, rules: HumanRules, durations_male: Array[float], durations_female: Array[float]
) -> float:
	var avg_durations: Array[float] = []
	for i in range(durations_male.size()):
		avg_durations.append((durations_male[i] + durations_female[i]) * 0.5)

	var mature_start := get_age_band_start_age(avg_durations, HumanTypes.AgeBand.MATURE_ADULT)
	if age < mature_start:
		return 0.0
	if age >= rules.absolute_max_age:
		return 1.0

	var old_start := get_age_band_start_age(avg_durations, HumanTypes.AgeBand.OLD)
	var old_nominal_end := old_start + avg_durations[HumanTypes.AgeBand.OLD]

	var t := 1.0
	if old_nominal_end > mature_start:
		t = clampf((age - mature_start) / (old_nominal_end - mature_start), 0.0, 1.0)
	return lerpf(rules.mortality_prob_at_mature_start, rules.mortality_prob_at_old_end, t)


# Workforce di BASE per fascia d'età + sesso — solo HumanRules.base_daily_workforce ×
# workforce_multiplier_by_age[age_band] × workforce_multiplier_by_sex[sex], nessuna stanchezza/
# wellness (quelle arriveranno in un passo successivo insieme a un vero
# available_workforce_per_day). Non chiama get_age_band: il chiamante passa già l'age_band
# risolto, stesso schema di size_multiplier_by_age/caloric_multiplier_by_age altrove nel progetto.
# TODO (quando esisterà la classe Action): alcune azioni potrebbero voler ignorare la differenza
# di sesso nella workforce (es. compiti dove la dimorfia non ha senso di modellazione) — servirà
# un campo booleano su Action per decidere se applicare workforce_multiplier_by_sex o no. Non
# implementato qui.
static func get_base_workforce(human_rules: HumanRules, age_band: HumanTypes.AgeBand, sex: HumanTypes.Sex) -> float:
	return (
		human_rules.base_daily_workforce
		* human_rules.workforce_multiplier_by_age[age_band]
		* human_rules.workforce_multiplier_by_sex[sex]
	)
