class_name HumanCouplingIndividualService
extends RefCounted

# Formazione annuale di coppie tra FERTILE_ADULT senza partner, per HumanPopulationGroup — stesso
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
# HumanPopulationGroup rappresentato in `individuals` (raggruppamento via source_group_ref — vedi
# HumanIndividual — non un Array pre-diviso dal chiamante: oggi esiste un solo gruppo/Folk nel
# progetto, ma questo resta corretto anche quando ce ne sarà più di uno, senza che il chiamante
# debba occuparsene). "Stesso Folk" è quindi implicito: due individui di gruppi diversi non
# vengono mai confrontati tra loro.
#
# current_year/durations_male/durations_female: stessa necessità e stessa convenzione di
# HumanMortalityIndividualService.check_mortality — age_band non è un campo salvato su
# HumanIndividual, va ricavato da birth_year_virtual con le durate EFFETTIVE (scalate per Era),
# stessa fonte già passata a check_mortality dal chiamante.
#
# Ritorna le coppie formate come {a, b} (entrambi HumanIndividual), stesso principio del ritorno di
# check_mortality: nessuna scrittura di log qui, solo dati per il chiamante che vorrà loggare.
static func form_couples(
	individuals: Array[HumanIndividual],
	current_year: int,
	durations_male: Array[float],
	durations_female: Array[float]
) -> Array[Dictionary]:
	var groups: Dictionary = {}
	for individual in individuals:
		var group_key: HumanPopulationGroup = individual.source_group_ref
		if not groups.has(group_key):
			groups[group_key] = [] as Array[HumanIndividual]
		groups[group_key].append(individual)
	var formed: Array[Dictionary] = []
	for group_individuals in groups.values():
		formed.append_array(
			_form_couples_in_group(group_individuals, current_year, durations_male, durations_female)
		)
	return formed


# Pool/matching per un SINGOLO gruppo (già filtrato da form_couples sopra) — candidati: age_band
# FERTILE_ADULT e partner_id == -1 (include sia neo-fertili sia vedovi/e accumulati durante
# l'anno, nessuna distinzione qui). Split per sesso, shuffle di ENTRAMBE le liste (Array.shuffle()
# di Godot — un vero rimescolamento, non un ordinamento pseudo-casuale che introdurrebbe bias),
# poi si scorre la lista più corta cercando il primo compatibile nella più lunga: chi resta senza
# match (squilibrio di sesso, o pool troppo piccolo) resta con partner_id invariato (-1),
# riconsiderato l'anno prossimo — nessuno stato aggiuntivo da tenere per questo.
static func _form_couples_in_group(
	individuals: Array[HumanIndividual],
	current_year: int,
	durations_male: Array[float],
	durations_female: Array[float]
) -> Array[Dictionary]:
	var males: Array[HumanIndividual] = []
	var females: Array[HumanIndividual] = []
	for individual in individuals:
		if individual.partner_id != -1:
			continue
		var age := current_year - individual.birth_year_virtual
		var age_band := HumanCalculator.get_age_band(durations_male, durations_female, individual.sex, float(age))
		if age_band != HumanTypes.AgeBand.FERTILE_ADULT:
			continue
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
		for other in longer:
			if other.partner_id != -1:
				continue
			if is_incestuous_pair(candidate, other):
				continue
			candidate.partner_id = other.id
			other.partner_id = candidate.id
			formed.append({"a": candidate, "b": other})
			break
	return formed
