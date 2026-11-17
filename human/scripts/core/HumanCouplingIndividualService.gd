class_name HumanCouplingIndividualService
extends RefCounted

# Formazione annuale di coppie tra FERTILE_ADULT senza partner, per Folk — stesso
# principio di separazione già seguito da HumanMortalityIndividualService (un *Service RefCounted
# stateless, un metodo statico che opera su un Array[HumanIndividual]). Step 1: la funzione di
# esclusione incesto, isolata perché testabile a sé. Step 2 (questo): pool/matching veri e propri
# in form_couples, agganciati al trigger annuale da un chiamante esterno (Step 3, non ancora fatto
# qui).


# Vero se `a` e `b` non possono formare coppia per parentela diretta o piena fratellanza — check
# bidirezionale (nessuna assunzione su chi dei due sia il genitore), sulle 4 condizioni della spec:
# stessa madre, stesso padre, uno è madre dell'altro, uno è padre dell'altro. Nessun vincolo di età
# qui (fuori scope, deciso). mother_id/father_id usano la sentinella -1 = sconosciuto (vedi
# HumanIndividual) — un -1 non deve MAI far scattare un match, in nessuna delle 4 condizioni:
# esplicitamente guardato anche nei casi 3/4 (mother_id/father_id == id dell'altro), non solo in
# 1/2 (stesso genitore), anche se lì il rischio resta teorico — id non è mai -1 in pratica (sempre
# assegnato alla creazione), ma la funzione non deve fare affidamento su quell'invariante esterna.
static func is_incestuous_pair(a: HumanIndividual, b: HumanIndividual) -> bool:
	if a.mother_id != -1 and a.mother_id == b.mother_id:
		return true
	if a.father_id != -1 and a.father_id == b.father_id:
		return true
	if (a.mother_id != -1 and a.mother_id == b.id) or (b.mother_id != -1 and b.mother_id == a.id):
		return true
	if (a.father_id != -1 and a.father_id == b.id) or (b.father_id != -1 and b.father_id == a.id):
		return true
	return false


# Entry point annuale: forma coppie tra FERTILE_ADULT senza partner, separatamente per ciascun
# Folk rappresentato in `individuals` (raggruppamento via folk_ref — vedi
# HumanIndividual — non un Array pre-diviso dal chiamante: oggi esiste un solo gruppo/Folk nel
# progetto, ma questo resta corretto anche quando ce ne sarà più di uno, senza che il chiamante
# debba occuparsene). "Stesso Folk" è quindi implicito: due individui di gruppi diversi non
# vengono mai confrontati tra loro.
#
# today/durations_male/durations_female: stessa necessità e stessa convenzione di
# HumanMortalityIndividualService.check_mortality — age_band non è un campo salvato su
# HumanIndividual, va ricavato da birth_year_virtual con le durate EFFETTIVE (scalate per Era),
# stessa fonte già passata a check_mortality dal chiamante.
#
# Ritorna le coppie formate come {a, b} (entrambi HumanIndividual), stesso principio del ritorno di
# check_mortality: nessuna scrittura di log qui, solo dati per il chiamante che vorrà loggare.
static func form_couples(
	individuals: Array[HumanIndividual],
	today: int,
	durations_male: Array[float],
	durations_female: Array[float]
) -> Array[Dictionary]:
	var groups: Dictionary = {}
	for individual in individuals:
		var group_key: Folk = individual.folk_ref
		if not groups.has(group_key):
			groups[group_key] = [] as Array[HumanIndividual]
		groups[group_key].append(individual)
	var formed: Array[Dictionary] = []
	for group_individuals in groups.values():
		formed.append_array(
			_form_couples_in_group(group_individuals, today, durations_male, durations_female)
		)
	return formed


# Pool/matching per un SINGOLO gruppo (già filtrato da form_couples sopra) — candidati: age_band
# FERTILE_ADULT e partner_id == -1 (include sia neo-fertili sia vedovi/e accumulati durante
# l'anno, nessuna distinzione qui). Split per sesso, shuffle di ENTRAMBE le liste (Array.shuffle()
# di Godot — un vero rimescolamento, non un ordinamento pseudo-casuale che introdurrebbe bias),
# poi si scorre la lista più corta scegliendo nella più lunga con _pick_partner (età e anni fertili in comune): chi resta senza
# match (squilibrio di sesso, o pool troppo piccolo) resta con partner_id invariato (-1),
# riconsiderato l'anno prossimo — nessuno stato aggiuntivo da tenere per questo.
static func _form_couples_in_group(
	individuals: Array[HumanIndividual],
	today: int,
	durations_male: Array[float],
	durations_female: Array[float]
) -> Array[Dictionary]:
	var males: Array[HumanIndividual] = []
	var females: Array[HumanIndividual] = []
	# Per ogni candidato (id): età, anni già passati nella fascia fertile, anni fertili che gli restano.
	var info: Dictionary = {}
	for individual in individuals:
		if individual.partner_id != -1:
			continue
		var age := individual.get_age(today)
		var age_band := HumanCalculator.get_age_band(durations_male, durations_female, individual.sex, age)
		if age_band != HumanTypes.AgeBand.FERTILE_ADULT:
			continue
		var durations: Array[float] = durations_female if individual.sex == HumanTypes.Sex.FEMALE else durations_male
		var fertile_start := HumanCalculator.get_age_band_start_age(durations, HumanTypes.AgeBand.FERTILE_ADULT)
		var fertile_end := HumanCalculator.get_age_band_start_age(durations, HumanTypes.AgeBand.MATURE_ADULT)
		info[individual.id] = {
			"age": age,
			"waited": maxf(0.0, age - fertile_start),
			"remaining": maxf(0.0, fertile_end - age),
		}
		if individual.sex == HumanTypes.Sex.MALE:
			males.append(individual)
		else:
			females.append(individual)
	males.shuffle()
	females.shuffle()
	# males/females sono per costruzione due pool disgiunti (split per sesso): un individuo scelto
	# come `candidate` dalla lista più corta non può mai ricomparire già accoppiato nella lista più
	# lunga, quindi qui non serve ricontrollare candidate.partner_id — solo quello di `other`, che
	# può essere stato assegnato da un'iterazione precedente di questo stesso ciclo.
	var shorter := males if males.size() <= females.size() else females
	var longer := females if males.size() <= females.size() else males
	var formed: Array[Dictionary] = []
	for candidate in shorter:
		var other := _pick_partner(candidate, longer, info)
		if other == null:
			continue
		candidate.partner_id = other.id
		other.partner_id = candidate.id
		formed.append({"a": candidate, "b": other})
	return formed


# Scelta del partner (2026-11-17, richiesta utente — prima era il primo compatibile, senza guardare l'età, e nascevano
# coppie in cui uno usciva presto dall'età fertile lasciando l'altro legato senza figli):
#   - ammessi solo i liberi, non parenti, con differenza d'età entro la tolleranza di ENTRAMBI: MAX_AGE_GAP_BASE anni più
#     MAX_AGE_GAP_PER_WAITED_YEAR per ogni anno già passato nella fascia fertile (chi aspetta da tempo, compresi
#     vedovi/e, si adatta di più; un appena fertile solo se l'altro è vicino d'età). Nessuno ammesso: resta single e
#     riprova l'anno dopo, con la tolleranza cresciuta;
#   - tra gli ammessi vince chi ha più anni fertili in comune (il minimo tra gli anni fertili rimasti ai due), pescando a
#     caso tra i primi PICK_AMONG_BEST per non rendere le coppie meccaniche.
const MAX_AGE_GAP_BASE := 5.0
const MAX_AGE_GAP_PER_WAITED_YEAR := 2.0
const PICK_AMONG_BEST := 3


static func _pick_partner(candidate: HumanIndividual, pool: Array[HumanIndividual], info: Dictionary) -> HumanIndividual:
	var mine: Dictionary = info[candidate.id]
	var my_tolerance := MAX_AGE_GAP_BASE + MAX_AGE_GAP_PER_WAITED_YEAR * float(mine["waited"])
	var options: Array[Dictionary] = []
	for other in pool:
		if other.partner_id != -1 or is_incestuous_pair(candidate, other):
			continue
		var theirs: Dictionary = info[other.id]
		var tolerance := minf(my_tolerance, MAX_AGE_GAP_BASE + MAX_AGE_GAP_PER_WAITED_YEAR * float(theirs["waited"]))
		if absf(float(mine["age"]) - float(theirs["age"])) > tolerance:
			continue
		options.append({"other": other, "shared": minf(float(mine["remaining"]), float(theirs["remaining"]))})
	if options.is_empty():
		return null
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["shared"]) > float(b["shared"]))
	return options[randi() % mini(PICK_AMONG_BEST, options.size())]["other"]
