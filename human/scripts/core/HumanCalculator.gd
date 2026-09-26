class_name HumanCalculator
extends RefCounted

# Calcoli di supporto per il dominio umano, stateless — stesso ruolo/pattern di
# AnimalCalculator/BuildingCalculator lato simulazione, ma nessuna dipendenza da quelli.

# Fascia d'età corrispondente a `age` (anni) per il sesso dato, camminando cumulativamente
# durations_male/female fino a trovare quella che la contiene — stesso ordine di HumanTypes.AgeBand
# (0=INFANT..5=OLD, ESTESO 2026-09-12 per INFANT). Età oltre l'ultima fascia (durate tutte esaurite, es. durations non ancora
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


# Moltiplicatore gravidanza (2026-09-06) — HARDCODED, deliberatamente NON in HumanRules/EraRules:
# scelta esplicita dell'utente, non un dato di configurazione (a differenza di
# EraRules.dependent_child_stamina_multiplier sotto, che invece vive in un .tres). SOLO display,
# nessun sistema di consumo stamina reale esiste ancora.
#
# Rinominata da PREGNANCY_WORKFORCE_MULTIPLIER (2026-09-06, richiesta utente) — solo rename,
# nessuna modifica di valore/logica.
const PREGNANCY_STAMINA_MULTIPLIER: float = 0.5


# Stamina MASSIMA per fascia d'età + sesso — solo HumanRules.base_max_stamina ×
# stamina_multiplier_by_age[age_band] × stamina_multiplier_by_sex[sex], nessuna stanchezza/
# wellness (quelle arriveranno in un passo successivo insieme a un vero current_stamina). Non
# chiama get_age_band: il chiamante passa già l'age_band risolto, stesso schema di
# size_multiplier_by_age/caloric_multiplier_by_age altrove nel progetto.
# TODO (quando esisterà la classe Action): alcune azioni potrebbero voler ignorare la differenza
# di sesso nella stamina (es. compiti dove la dimorfia non ha senso di modellazione) — servirà
# un campo booleano su Action per decidere se applicare stamina_multiplier_by_sex o no. Non
# implementato qui.
#
# is_pregnant/has_dependent_child (2026-09-06, entrambi default false — SOLO display, migliora
# l'accuratezza del numero mostrato nel pannello individuo, nessun sistema di consumo stamina
# reale esiste ancora): mutuamente esclusivi per costruzione — una donna incinta non può avere
# contemporaneamente un figlio a carico (lo stesso vincolo min_birth_spacing_years che blocca il
# concepimento copre l'intera finestra di dipendenza del figlio, verificato in ricognizione), quindi
# un semplice if/elif basta — nessuna gestione del caso "entrambi true" (richiesta esplicita
# dell'utente: non può accadere, non va inventata una regola di combinazione per un caso che il
# sistema riproduzione già esclude strutturalmente).
#
# Rinominata da get_base_workforce (2026-09-06, richiesta utente, rename completo Workforce->
# Stamina) — corpo/comportamento invariati, solo nomi (funzione + campi HumanRules/EraRules letti).
static func get_max_stamina(
	human_rules: HumanRules, age_band: HumanTypes.AgeBand, sex: HumanTypes.Sex,
	is_pregnant: bool = false, has_dependent_child: bool = false, era_rules: EraRules = null
) -> float:
	var stamina := (
		human_rules.base_max_stamina
		* human_rules.stamina_multiplier_by_age[age_band]
		* human_rules.stamina_multiplier_by_sex[sex]
	)
	if is_pregnant:
		stamina *= PREGNANCY_STAMINA_MULTIPLIER
	elif has_dependent_child and era_rules != null:
		stamina *= era_rules.dependent_child_stamina_multiplier
	return stamina


# Termine di taglia condiviso (2026-09-19): `base_amount` x size_multiplier_by_age[age_band] x
# size_multiplier_by_sex[sex]. Usato da get_max_carry_capacity (che poi applica equipment_multiplier e
# il bonus slot tool) e da get_max_food_space - un solo punto per la formula di taglia.
static func _size_scaled_amount(
	base_amount: float, human_rules: HumanRules, age_band: HumanTypes.AgeBand, sex: HumanTypes.Sex
) -> float:
	return base_amount * human_rules.size_multiplier_by_age[age_band] * human_rules.size_multiplier_by_sex[sex]


# Capacità di trasporto MASSIMA per fascia d'età + sesso (2026-09-08, richiesta utente) — stesso
# identico schema di get_max_stamina sopra: HumanRules.base_carry_capacity ×
# size_multiplier_by_age[age_band] × size_multiplier_by_sex[sex], NESSUN nuovo array dedicato
# (riusa gli stessi due già usati per la taglia fisica, verificato che siano leggibili da qui
# esattamente come stamina_multiplier_by_age/by_sex). Non chiama get_age_band: stesso principio di
# get_max_stamina, il chiamante passa già l'age_band risolto.
#
# equipment_multiplier: HOOK per una futura capacità aggiuntiva da strumenti/contenitori (es. un
# cesto di vimini) — richiesta esplicita dell'utente di lasciare la struttura aperta SENZA
# costruire quella feature ora. Default 1.0 (nessun effetto): nessun chiamante oggi passa un
# valore diverso, nessuna Rules/logica di equipaggiamento esiste ancora. Applicato SOLO al termine
# scalato per taglia (age/sex), MAI al bonus slot tool sotto — quel bonus è deliberatamente FLAT,
# fuori da qualunque moltiplicatore (vedi il campo su HumanRules per il perché).
#
# equipped_tool_count (2026-09-08, richiesta utente; dal 2026-09-25 ricavato dalla cintura
# HumanIndividual.equipped_tools): bonus FLAT di HumanRules.carry_bonus_per_empty_tool_slot per ogni slot
# VUOTO, aggiunto DOPO il termine scalato per taglia, non dentro (richiesta esplicita — un
# individuo piccolo e uno grande con lo stesso zaino vuoto ottengono lo stesso bonus assoluto, non
# uno scalato con la taglia). max(..., 0) difensivo: la cintura ha sempre tool_slot_count posti, ma
# se equipped_tool_count superasse tool_slot_count per qualche motivo il bonus non deve diventare
# negativo.
static func get_max_carry_capacity(
	human_rules: HumanRules, age_band: HumanTypes.AgeBand, sex: HumanTypes.Sex,
	equipped_tool_count: int = 0, equipment_multiplier: float = 1.0
) -> float:
	var size_scaled_capacity := _size_scaled_amount(human_rules.base_carry_capacity, human_rules, age_band, sex) * equipment_multiplier
	var empty_tool_slots: int = max(human_rules.tool_slot_count - equipped_tool_count, 0)
	var tool_slot_bonus: float = float(empty_tool_slots) * human_rules.carry_bonus_per_empty_tool_slot
	return size_scaled_capacity + tool_slot_bonus


# Consumo calorico giornaliero (2026-09-19, richiesta utente): base_daily_calorie_consumption x
# caloric_multiplier_by_age[age_band] x caloric_multiplier_by_sex[sex]. NON usa i size_multiplier
# (restano per saccoccia e trasporto). Il chiamante passa gia' l'age_band risolto. Con moltiplicatore
# 0 (INFANT) il consumo e' zero.
static func get_daily_calorie_consumption(
	human_rules: HumanRules, age_band: HumanTypes.AgeBand, sex: HumanTypes.Sex,
	has_dependent_child: bool = false, era_rules: EraRules = null
) -> float:
	var consumption: float = (
		human_rules.base_daily_calorie_consumption
		* human_rules.caloric_multiplier_by_age[age_band]
		* human_rules.caloric_multiplier_by_sex[sex]
	)
	# Costo dell'allattamento (2026-09-19, richiesta utente): chi ha un figlio a carico consuma di piu'
	# (EraRules.dependent_child_calorie_multiplier). Il neonato non consuma nulla di suo (INFANT a 0.0).
	if has_dependent_child and era_rules != null:
		consumption *= era_rules.dependent_child_calorie_multiplier
	return consumption


# Spazio MASSIMO della saccoccia del cibo (2026-09-19, richiesta utente) - SOSTITUISCE get_max_hunger:
# base_food_space x size_multiplier_by_age[age_band] x size_multiplier_by_sex[sex] (stessi
# moltiplicatori di taglia del trasporto, via _size_scaled_amount), SENZA bonus slot tool liberi e
# senza equipment_multiplier. Il chiamante passa gia' l'age_band risolto.
static func get_max_food_space(human_rules: HumanRules, age_band: HumanTypes.AgeBand, sex: HumanTypes.Sex) -> float:
	return _size_scaled_amount(human_rules.base_food_space, human_rules, age_band, sex)


# Riserva calorica MASSIMA del corpo (2026-09-19, richiesta utente): base_body_calories x
# size_multiplier_by_age[age_band] x size_multiplier_by_sex[sex], con lo stesso helper di taglia di
# get_max_food_space (i size_multiplier, NON i caloric_multiplier). Il chiamante passa gia' l'age_band
# risolto. Nessun consumatore ancora.
static func get_max_body_calories(human_rules: HumanRules, age_band: HumanTypes.AgeBand, sex: HumanTypes.Sex) -> float:
	return _size_scaled_amount(human_rules.base_body_calories, human_rules, age_band, sex)


# 5 nuovi parametri vitali (2026-09-13, richiesta utente) — thirst/health/happiness/
# loyalty, STESSO identico schema di get_max_stamina sopra (base × multiplier_by_age[age_band] ×
# multiplier_by_sex[sex]), ma firma SEMPLIFICATA a soli 3 parametri (human_rules, age_band, sex):
# i due modificatori aggiuntivi di get_max_stamina (is_pregnant/has_dependent_child, con
# PREGNANCY_STAMINA_MULTIPLIER/era_rules.dependent_child_stamina_multiplier) sono specifici del
# dominio riproduttivo/capacità lavorativa, non generalizzati qui — richiesta esplicita, nessun
# consumatore reale ancora per questi 5 parametri (arriverà in un giro successivo, insieme alla
# decisione se/quali di questi modificatori li riguardino anche loro). Nessuna chiamata a
# get_age_band qui, stesso principio di get_max_stamina/get_max_carry_capacity: il chiamante passa
# già l'age_band risolto.
static func get_max_thirst(human_rules: HumanRules, age_band: HumanTypes.AgeBand, sex: HumanTypes.Sex) -> float:
	return (
		human_rules.base_max_thirst
		* human_rules.thirst_multiplier_by_age[age_band]
		* human_rules.thirst_multiplier_by_sex[sex]
	)


static func get_max_health(human_rules: HumanRules, age_band: HumanTypes.AgeBand, sex: HumanTypes.Sex) -> float:
	return (
		human_rules.base_max_health
		* human_rules.health_multiplier_by_age[age_band]
		* human_rules.health_multiplier_by_sex[sex]
	)


static func get_max_happiness(human_rules: HumanRules, age_band: HumanTypes.AgeBand, sex: HumanTypes.Sex) -> float:
	return (
		human_rules.base_max_happiness
		* human_rules.happiness_multiplier_by_age[age_band]
		* human_rules.happiness_multiplier_by_sex[sex]
	)


# Loyalty verso chi/cosa non è ancora definito concettualmente — vedi HumanRules.base_max_loyalty
# per lo stesso avvertimento.
static func get_max_loyalty(human_rules: HumanRules, age_band: HumanTypes.AgeBand, sex: HumanTypes.Sex) -> float:
	return (
		human_rules.base_max_loyalty
		* human_rules.loyalty_multiplier_by_age[age_band]
		* human_rules.loyalty_multiplier_by_sex[sex]
	)
