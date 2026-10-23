class_name FamilyNucleusService
extends RefCounted

# Nuclei famigliari (2026-10-22, richiesta utente — assegnazione delle Hut e bonus del nucleo unito). Stateless, come gli
# altri *Service. Il nucleo NON si salva: si ricalcola ogni volta dai legami (partner_id, mother_id, father_id), così
# resta sempre coerente con coppie, nascite e morti senza dover essere aggiornato in ogni punto che li cambia.
#
# Un nucleo è:
#   - una COPPIA (partner reciproci, entrambi vivi), con o senza figli — chiave "c:<id minore>";
#   - oppure un GENITORE senza partner con almeno un figlio non accoppiato — chiave "p:<id del genitore>".
# Membri: la coppia o il genitore più i figli vivi di entrambi o di uno dei due, finché non formano una coppia propria.
# Chi è genitore senza partner con un figlio non accoppiato è capo del proprio nucleo, non membro di quello dei suoi
# genitori. Un figlio appartiene al nucleo della madre se viva e capo di un nucleo, altrimenti a quello del padre. Senza
# genitori vivi i figli sono singoli; vedovi senza figli e anziani soli sono singoli (nessun nucleo).
#
# Usato da AssignHouseService (passata delle Hut) e da GameTimeService (bonus giornaliero del nucleo unito): una sola
# definizione, così assegnazione ed effetti non possono divergere.

const COUPLE_PREFIX := "c:"
const PARENT_PREFIX := "p:"


# {"by_member": {id -> chiave}, "members": {chiave -> Array[HumanIndividual]}, "heads": {chiave -> Array[HumanIndividual]}}.
# I singoli non compaiono in by_member. Un giro per l'indice, uno per le coppie, uno per i figli.
static func compute_nuclei(individuals: Array[HumanIndividual]) -> Dictionary:
	var by_id: Dictionary = {}
	for individual in individuals:
		by_id[individual.id] = individual
	var by_member: Dictionary = {}
	var members: Dictionary = {}
	var heads: Dictionary = {}
	# Coppie: partner reciproco e vivo.
	for individual in individuals:
		var partner: HumanIndividual = by_id.get(individual.partner_id)
		if partner == null or partner.partner_id != individual.id or individual.id > partner.id:
			continue
		var key := COUPLE_PREFIX + str(individual.id)
		by_member[individual.id] = key
		by_member[partner.id] = key
		var couple_members: Array[HumanIndividual] = [individual, partner]
		var couple_heads: Array[HumanIndividual] = [individual, partner]
		members[key] = couple_members
		heads[key] = couple_heads
	# Figli non accoppiati con almeno un genitore vivo, raggruppati per genitore.
	var children_by_parent: Dictionary = {}
	for individual in individuals:
		if individual.partner_id != -1 and by_id.has(individual.partner_id):
			continue
		for parent_id in [individual.mother_id, individual.father_id]:
			if by_id.has(parent_id):
				if not children_by_parent.has(parent_id):
					children_by_parent[parent_id] = []
				(children_by_parent[parent_id] as Array).append(individual)
	# Genitori senza partner con figli non accoppiati: capi di un proprio nucleo.
	for parent_id in children_by_parent.keys():
		if by_member.has(parent_id):
			continue
		var parent: HumanIndividual = by_id[parent_id]
		var key := PARENT_PREFIX + str(parent_id)
		by_member[parent_id] = key
		var parent_members: Array[HumanIndividual] = [parent]
		var parent_heads: Array[HumanIndividual] = [parent]
		members[key] = parent_members
		heads[key] = parent_heads
	# Figli: al nucleo della madre se ne è capo, altrimenti a quello del padre. Un capo resta nel proprio nucleo.
	for parent_id in children_by_parent.keys():
		for child in children_by_parent[parent_id]:
			var member: HumanIndividual = child
			if by_member.has(member.id):
				continue
			var nucleus_key := ""
			if by_member.has(member.mother_id):
				nucleus_key = String(by_member[member.mother_id])
			elif by_member.has(member.father_id):
				nucleus_key = String(by_member[member.father_id])
			if nucleus_key == "":
				continue
			by_member[member.id] = nucleus_key
			(members[nucleus_key] as Array).append(member)
	return {"by_member": by_member, "members": members, "heads": heads}


# Il membro è un capo del nucleo (uno della coppia o il genitore solo).
static func is_head(nuclei: Dictionary, nucleus_key: String, member: HumanIndividual) -> bool:
	return (nuclei["heads"].get(nucleus_key, []) as Array).has(member)


# Figlio adulto: dalla fascia FERTILE_ADULT in su (durate dell'era della partita). Senza partita: mai adulto (nessuna uscita).
static func is_adult(member: HumanIndividual, current_year: int) -> bool:
	var game_data: GameData = GameSettings.active_game_data
	if game_data == null:
		return false
	var band := HumanCalculator.get_age_band(
		game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female, member.sex,
		float(current_year - member.birth_year_virtual)
	)
	return int(band) >= int(HumanTypes.AgeBand.FERTILE_ADULT)


# Anno di nascita del membro più anziano (spareggio: il nucleo con il membro più anziano vince).
static func oldest_birth_year(members: Array) -> int:
	var oldest := 1 << 30
	for member in members:
		oldest = mini(oldest, (member as HumanIndividual).birth_year_virtual)
	return oldest


# Id dei membri di nuclei che vivono tutti nella stessa casa (qualsiasi casa, anche una tenda): {id -> true}.
static func united_member_ids(nuclei: Dictionary) -> Dictionary:
	var united: Dictionary = {}
	for nucleus_key in nuclei["members"].keys():
		var nucleus_members: Array = nuclei["members"][nucleus_key]
		var house_id: int = (nucleus_members[0] as HumanIndividual).house_id
		if house_id == -1:
			continue
		var together := true
		for member in nucleus_members:
			if (member as HumanIndividual).house_id != house_id:
				together = false
				break
		if together:
			for member in nucleus_members:
				united[(member as HumanIndividual).id] = true
	return united
