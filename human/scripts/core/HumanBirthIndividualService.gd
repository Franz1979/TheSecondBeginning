class_name HumanBirthIndividualService
extends RefCounted

# Risoluzione annuale delle gravidanze in corso (day 20, ~9 mesi dopo il concepimento di
# HumanConceptionIndividualService al day 110 dell'anno precedente), per HumanPopulationGroup —
# stesso principio di HumanCouplingIndividualService/HumanConceptionIndividualService: un
# *Service RefCounted stateless, un metodo statico che opera su un Array[HumanIndividual],
# raggruppando internamente per source_group_ref (stesso schema di raggruppamento di
# HumanCouplingIndividualService.form_couples/HumanConceptionIndividualService.run_conception).
#
# STEP 3 (2026-09-06): il tiro sopravvivenza FIGLIO ha ora un effetto reale — se fallisce, nessun
# HumanIndividual viene creato (nato-morto, vedi _record_stillbirth_event). Il tiro sopravvivenza
# MADRE resta SOLO osservato/loggato, nessun effetto (task futuro separato). Nessun tiro sesso
# PESATO (50/50 puro, come confermato) per i nati vivi; nessun tiro sesso affatto per i nati morti
# (vedi _record_stillbirth_event).
#
# SEMPLIFICAZIONE NOTA (day 20 fisso, non ancora un vero calendario nascite): oggi TUTTE le
# nascite dell'anno cadono nello stesso identico giorno, indipendentemente da quando è avvenuto il
# concepimento — un artefatto del trigger fisso in GameTimeService._on_day_advanced (giorno 20),
# non un modello di gestazione reale. In futuro andrebbe distribuita sull'anno (es. ~9 mesi dopo
# il giorno VERO di concepimento di ciascuna donna, non un giorno fisso uguale per tutte) — non
# implementato qui, richiede prima di persistere il giorno di concepimento per donna (oggi non
# tracciato, solo l'anno tramite birth_year_virtual del futuro neonato).
#
# hair_color/skin_color/father_id del neonato vengono SOLO letti da pending_child_* sulla madre
# (precalcolati al concepimento da HumanConceptionIndividualService) — MAI da woman.partner_id né
# da un nuovo tiro qui: il padre potrebbe essere morto tra concepimento e nascita, ma il tiro
# genetico è già cristallizzato e non va rifatto (vedi HumanIndividual.pending_child_father_id).
# name/clothing_color, al contrario, NON sono precalcolati (non ereditari) — tirati qui, al
# momento della nascita, con le stesse funzioni random già usate dal seeding per i fondatori
# (HumanIndividual.assign_random_name/assign_random_clothing).
#
# game_data (SOLO per game_data.allocate_human_id(), stesso principio già stabilito per
# HumanSeedingService.seed_player_start — un canale di id condiviso, mai un contatore locale).
#
# Piano "trasporto neonati" (2026-09-06): il neonato nasce leggermente SPOSTATO rispetto alla
# madre (mai più esattamente sovrapposto, altrimenti impossibile da cliccare separatamente) — vedi
# DEPENDENT_CHILD_SIDE_OFFSET sotto, stessa formula (perpendicolare a facing_direction, "sempre a
# lato") riusata da GameScene._sync_dependent_child_position ad ogni movimento della madre finché
# il figlio resta a carico: sono lo stesso identico calcolo, non due concetti distinti — l'offset
# di nascita è solo la prima valutazione di quella stessa formula. mother.dependent_child_id
# valorizzato qui, unico punto di scrittura per tutta la vita del figlio a parte il consumatore
# stesso (vedi HumanIndividual.dependent_child_id per l'auto-manutenzione della query).
#
# RIDOTTO (richiesta utente, 2026-09-06: "l'offset è enorme, li vorrei praticamente attaccati",
# poi ulteriormente a 0.2) — da 0.9 a 0.35 a 0.2: 0.9 lasciava un distacco visivo netto tra i due
# corpi (il figlio, scalato più piccolo per età — HumanRules.size_multiplier_by_age[CHILD] —
# finiva ben oltre il bordo del busto della madre). Resta comunque > 0, quindi i due restano due
# bersagli di click separati e distinguibili (mai esattamente sovrapposti, il problema originale
# che questo offset risolveva).
const DEPENDENT_CHILD_SIDE_OFFSET: float = 0.2


# Entry point annuale (day 20): per ciascun HumanPopulationGroup rappresentato in `individuals`,
# risolve ogni gravidanza in corso creando il neonato (o registrando un nato-morto, vedi sotto) e
# resettando lo stato della madre. Il neonato viene aggiunto DIRETTAMENTE a `individuals` (Array
# passato per riferimento in GDScript — stesso oggetto di GameTimeService._human_individuals/
# GameScene.human_individuals, mai una copia), così il chiamante non deve fare un secondo append.
# Ritorna {"birth_results": Array[Dictionary]}, un elemento per OGNI gravidanza risolta (successo
# O nato-morto), ciascuno {"mother": HumanIndividual, "newborn": HumanIndividual (null se
# nato-morto), "survived": bool, "survival_roll": Dictionary} — UN'UNICA lista invece di tre array
# paralleli (processed_women/newborns/survival_rolls, versione precedente): con un nato-morto
# "newborns" sarebbe più corto degli altri due, disallineandoli per indice — stesso tipo di bug
# fragile già capitato con l'aggregatore di HumanConceptionIndividualService (return dimenticato di
# aggiornare). Un'unica lista di risultati elimina il rischio strutturalmente. Nessuna scrittura di
# log/segnale qui, solo dati per il chiamante, che dovrà emettere individual_born per ogni neonato
# vivo e (Step 2 successivo) un segnale dedicato per ogni nato-morto.
#
# human_rules/era_rules (dal 2026-09-06): calcolano le due probabilità di sopravvivenza parto
# (figlio/madre) e i due tiri indipendenti corrispondenti. STEP 3 (2026-09-06, richiesta utente):
# il tiro FIGLIO ora ha un effetto reale — vedi _run_births_in_group sotto. Il tiro MADRE resta
# SOLO osservato/loggato dal chiamante (nessun effetto ancora, task futuro separato).
static func run_births(
	individuals: Array[HumanIndividual], game_data: GameData, human_rules: HumanRules, era_rules: EraRules
) -> Dictionary:
	var groups: Dictionary = {}
	for individual in individuals:
		var group_key: HumanPopulationGroup = individual.source_group_ref
		if not groups.has(group_key):
			groups[group_key] = [] as Array[HumanIndividual]
		groups[group_key].append(individual)
	var birth_results: Array[Dictionary] = []
	for group_individuals in groups.values():
		var result := _run_births_in_group(group_individuals, individuals, game_data, human_rules, era_rules)
		birth_results.append_array(result["birth_results"])
	return {"birth_results": birth_results}


# Resa per un SINGOLO gruppo (già filtrato da run_births sopra) — ogni donna con is_pregnant==true
# viene processata, incondizionatamente. `all_individuals` (l'array COMPLETO, non solo quelli di
# questo gruppo) è dove il neonato viene fisicamente aggiunto — group_individuals sopra è solo la
# fetta usata per il raggruppamento a monte, non l'array condiviso col chiamante.
static func _run_births_in_group(
	individuals: Array[HumanIndividual], all_individuals: Array[HumanIndividual], game_data: GameData,
	human_rules: HumanRules, era_rules: EraRules
) -> Dictionary:
	var birth_results: Array[Dictionary] = []
	var newborns: Array[HumanIndividual] = []
	for woman in individuals:
		if woman.sex != HumanTypes.Sex.FEMALE:
			continue
		if not woman.is_pregnant:
			continue
		# STEP 3 (2026-09-06): il tiro va fatto PRIMA di creare l'individuo — se fallisce, nessun
		# HumanIndividual viene mai istanziato (non solo scartato dopo). Il tiro MADRE resta SOLO
		# osservato (roll["mother_survived_roll"]), nessun ramo che ne consuma l'esito qui: la
		# madre prosegue esattamente come se quel tiro non esistesse.
		var roll := _roll_childbirth_survival(human_rules, era_rules)
		var newborn: HumanIndividual = null
		if roll["child_survived_roll"]:
			newborn = _create_newborn(woman, game_data, all_individuals)
			newborns.append(newborn)
		else:
			_record_stillbirth_event(woman, game_data)
		woman.is_pregnant = false
		# Reset ai default di riposo (stessa convenzione "mai letto finché is_pregnant è false" già
		# dichiarata sui campi in HumanIndividual) — non strettamente necessario per la correttezza
		# (verranno sovrascritti dal prossimo concepimento prima di essere riletti), ma evita che
		# valori di una gravidanza già risolta restino visibili/fuorvianti in eventuali ispezioni
		# di debug. Applicato SEMPRE (successo o nato-morto): la gravidanza è comunque risolta.
		woman.pending_child_hair_color = HumanTypes.HairColor.BLONDE
		woman.pending_child_skin_color = HumanTypes.SkinColor.LIGHT
		woman.pending_child_father_id = -1
		birth_results.append({
			"mother": woman, "newborn": newborn, "survived": roll["child_survived_roll"], "survival_roll": roll
		})
	all_individuals.append_array(newborns)
	return {"birth_results": birth_results}


# Probabilità aggregate di sopravvivenza al parto (base di HumanRules × moltiplicatore di
# EraRules, stesso schema già in uso per conception_probability in
# HumanConceptionIndividualService) + i due tiri indipendenti corrispondenti. STEP 3 (2026-09-06,
# richiesta utente): "child_survived_roll" ha ora un effetto reale (vedi _run_births_in_group —
# fallimento = nato-morto). "mother_survived_roll" resta SOLO per il logging del chiamante, nessun
# effetto ancora (task futuro separato). Ritorna {"child_survival_probability": float,
# "child_survived_roll": bool, "mother_survival_probability": float, "mother_survived_roll": bool}.
static func _roll_childbirth_survival(human_rules: HumanRules, era_rules: EraRules) -> Dictionary:
	var child_survival_probability := human_rules.childbirth_survival_child_base_probability * era_rules.childbirth_survival_child_multiplier
	var mother_survival_probability := human_rules.childbirth_survival_mother_base_probability * era_rules.childbirth_survival_mother_multiplier
	return {
		"child_survival_probability": child_survival_probability,
		"child_survived_roll": randf() < child_survival_probability,
		"mother_survival_probability": mother_survival_probability,
		"mother_survived_roll": randf() < mother_survival_probability,
	}


# Costruisce il nuovo HumanIndividual per `mother` — id/mother_id/father_id/partner_id/sex/
# birth_year_virtual/name/hair_color/skin_color/clothing_color/source_group_ref/position/
# home_macro_coords, in quest'ordine (sex PRIMA di assign_random_name: quella funzione legge
# self.sex per scegliere la lista nomi maschile/femminile, stesso ordine già usato da
# HumanSeedingService._create_family_children/_create_child).
#
# all_individuals (2026-09-13, richiesta utente — eredità skill) — necessario SOLO per risolvere
# il padre per OGGETTO (mother.pending_child_father_id è solo un id): scansione lineare per id,
# stesso identico costo/stesso identico idioma già accettato altrove nel progetto per array
# analoghi (es. GameTimeService._transfer_or_orphan_dependent_child/_free_partner_if_any). Se il
# padre non è (più) nel roster — può essere morto tra concepimento e nascita, vedi doc di testa al
# file — le sue skill sono trattate come 0.0 per tutte (fallback onesto, stesso principio già in
# uso per FALLBACK_MAX_VITAL/FALLBACK_MAX_STAMINA: nessun crash, nessuna skill "inventata").
static func _create_newborn(mother: HumanIndividual, game_data: GameData, all_individuals: Array[HumanIndividual]) -> HumanIndividual:
	var newborn := HumanIndividual.new()
	newborn.id = game_data.allocate_human_id()
	newborn.mother_id = mother.id
	newborn.father_id = mother.pending_child_father_id
	newborn.partner_id = -1
	newborn.sex = HumanTypes.Sex.FEMALE if randf() < 0.5 else HumanTypes.Sex.MALE
	newborn.birth_year_virtual = game_data.year
	newborn.assign_random_name()
	# hair_color/skin_color: SOLO dai valori precalcolati al concepimento (vedi doc di testa al
	# file) — mai un nuovo tiro qui.
	newborn.hair_color = mother.pending_child_hair_color
	newborn.skin_color = mother.pending_child_skin_color
	newborn.assign_random_clothing()
	newborn.source_group_ref = mother.source_group_ref
	# Nasce ACCANTO alla madre (mai esattamente sovrapposto, vedi DEPENDENT_CHILD_SIDE_OFFSET sopra
	# per il perché), non dove si trova lei in senso stretto — dato di simulazione, non di
	# rendering: GameScene legge questi due campi già valorizzati per parentare/posizionare la
	# HumanIndividualView, stesso principio già in uso per ogni altro individuo (vedi
	# HumanIndividualView._process, che segue individual.position ad ogni frame da sé).
	newborn.position = mother.position + mother.facing_direction.orthogonal() * DEPENDENT_CHILD_SIDE_OFFSET
	newborn.home_macro_coords = mother.home_macro_coords
	# Piano "trasporto neonati" — la madre inizia subito a "portare" questo figlio, vedi
	# HumanIndividual.dependent_child_id per il ciclo di vita completo del campo.
	mother.dependent_child_id = newborn.id
	# Log grezzo per il pannello statistiche (Step 2 piano statistiche, 2026-09-06) — stesso
	# principio/schema di GameTimeService._kill_individual per death_events: l'evento è registrato
	# QUI, nell'unico punto che crea davvero il neonato, non dal chiamante. day = game_data.
	# current_day (oggi sempre 20, giorno fisso — vedi nota di testa al file sulla futura
	# distribuzione delle nascite sull'anno). mother_survived SEMPRE true: il tiro madre non ha
	# ancora nessun effetto (task futuro separato) — lo stato vero della madre in questo momento è
	# "viva", quindi il log riflette la realtà, non l'esito (ignorato) del tiro.
	game_data.birth_events.append({
		"individual_id": newborn.id,
		"mother_id": mother.id,
		"father_id": newborn.father_id,
		"sex": newborn.sex,
		"year": game_data.year,
		"day": game_data.current_day,
		"child_survived": true,
		"mother_survived": true,
	})

	# Eredità skill (2026-09-13, richiesta utente) — per OGNI skill esistente (HumanIndividual.
	# get_skill_property_names(), MAI un conteggio scritto a mano — un'ottava skill futura viene
	# ereditata automaticamente senza toccare questo codice): (skill_madre + skill_padre) / 10.0,
	# STESSA formula per tutte. father risolto per oggetto (vedi doc sopra), 0.0 su tutte le skill
	# se non trovato/morto.
	var father: HumanIndividual = null
	for candidate in all_individuals:
		if candidate.id == newborn.father_id:
			father = candidate
			break
	for skill_name in newborn.get_skill_property_names():
		var mother_skill: float = mother.get(skill_name)
		var father_skill: float = father.get(skill_name) if father != null else 0.0
		newborn.set(skill_name, (mother_skill + father_skill) / 10.0)

	# Bugfix (2026-09-13, richiesta utente) — STESSA causa/STESSO principio del fix gemello in
	# GameScene._ready() (seeding/caricamento): un neonato nasce con current_task == null (mai
	# valorizzato sopra) e, senza questa chiamata, non riceverebbe MAI il controllo bisogno/coda/
	# fallback perditempo finché qualcosa non gli assegnasse manualmente una prima Task — restando
	# fermo indefinitamente anche a stamina piena. age_band hardcoded a INFANT (non risolto via
	# HumanCalculator.get_age_band): un neonato ha per costruzione età 0 in questo stesso istante,
	# sempre e comunque INFANT — nessuna ambiguità da risolvere, nessun bisogno delle durate
	# effettive per età qui. `world` null: nessuna Task-bisogno/perditempo di oggi ne ha davvero
	# bisogno per un neonato (house_id resta -1 di default, mai assegnato a un neonato — vedi
	# NeedTaskAssignmentService.resolve_rest_target, ramo "nessuna casa"). In pratica, oggi, questa
	# chiamata è un no-op silenzioso: OGNI Task-bisogno/perditempo/Action coinvolta disallowed
	# INFANT (vedi Action.disallowed_age_bands su WalkAction/RestAction/LookAroundAction/ecc.),
	# quindi resolve_idle_individual ricade sul suo ultimo fallback (individual.stop(), no-op su
	# current_task già null) — resta comunque corretto collegarla ORA: il giorno in cui un futuro
	# bisogno/Task perditempo ammetterà INFANT, funzionerà da sé, senza dover ricordarsi di
	# aggiungere questa chiamata a posteriori.
	HumanIndividualActionService.resolve_idle_individual(newborn, HumanTypes.AgeBand.INFANT, null)

	return newborn


# Evento nato-morto (STEP 3, 2026-09-06) — stesso schema di _create_newborn sopra ma SENZA
# HumanIndividual: nessun figlio esiste mai, quindi "individual_id" usa il sentinel -1 (mai un id
# reale allocato per un individuo mai creato) e "sex" è deliberatamente ASSENTE dal dict (nessuna
# chiave, non un valore-sentinel come -1: nessuna statistica oggi legge event["sex"] sui
# birth_events — verificato in StatisticsPanel.gd — quindi non c'è bisogno di tirare un sesso per
# un individuo che non esisterà mai). father_id letto da pending_child_father_id PRIMA che il
# chiamante lo resetti a -1 subito dopo (stesso identico dato che sarebbe finito sul neonato, se
# fosse nato). mother_survived SEMPRE true, stesso motivo di _create_newborn sopra.
static func _record_stillbirth_event(mother: HumanIndividual, game_data: GameData) -> void:
	game_data.birth_events.append({
		"individual_id": -1,
		"mother_id": mother.id,
		"father_id": mother.pending_child_father_id,
		"year": game_data.year,
		"day": game_data.current_day,
		"child_survived": false,
		"mother_survived": true,
	})
