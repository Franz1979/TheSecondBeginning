class_name IdeaProgressService
extends RefCounted

# Primo consumatore reale del modello dati Idea/Folk (2026-09-07, richiesta utente — prima erano
# solo campi dichiarati, nessuna logica). *Service stateless (RefCounted, static func — stesso
# pattern di HumanStaminaIndividualService.recalculate_max_stamina, stessa cartella): opera su un
# Folk passato dal chiamante, nessuno stato proprio. Non conosce BuildBar/GameScene — segnala un
# completamento solo col valore di ritorno (bool), il chiamante decide se/come reagire (vedi
# GameScene._debug_add_thought, che richiama _refresh_building_slots_buildable SOLO quando torna
# true — lo stesso punto di aggancio predisposto nel passo precedente).


# Incrementa i pensieri investiti nell'Idea attiva di `folk` (scelta dal giocatore, vedi
# select_idea sotto — se nessuna è attiva il pensiero non finisce in nessuna idea) e, se il costo
# viene raggiunto, la completa.
# Ritorna true SOLO nel frame/chiamata in cui un'Idea viene completata (mai per un investimento che
# non la conclude) — il chiamante lo usa per sapere quando propagare il cambiamento altrove (es.
# BuildBar), senza dover ricontrollare da sé completed_ideas prima/dopo.
static func add_thoughts(folk: Folk, amount: int) -> bool:
	# Contatore aggregato (2026-09-10, richiesta utente — "toglilo [il limite], fai che il counter
	# ne accumula ancora anche se non fa scattare nulla": col vecchio comportamento, una volta
	# esaurite tutte le Idee disponibili, ogni pensiero depositato dopo quel punto veniva perso
	# silenziosamente, "return false" sotto usciva PRIMA di scrivere qualunque cosa — un Folk che
	# aveva già completato tutte le idee raggiungibili smetteva di fatto di accumulare qualunque
	# progresso visibile, anche se il giocatore continuava a far pensare i propri individui).
	# folk.thoughts_count è ESATTAMENTE il campo lasciato pronto per questo (vedi Folk.gd: "Nessuna
	# logica lo incrementa ancora in questo passo: solo il campo dichiarato, pronto per essere
	# scritto da un futuro DepositThoughtAction") — incrementato qui SEMPRE, incondizionatamente,
	# prima di qualunque `return false` sotto: un pensiero depositato conta sempre per il totale
	# aggregato, che ci sia o meno un'Idea attiva pronta a consumarlo. Già persistito in save/load
	# (GameSaveService/GameLoadService, invariati — il campo esisteva già), nessuna modifica lì
	# necessaria.
	folk.thoughts_count += amount
	if folk.active_idea_id == "":
		# Nessuna Idea attiva (2026-09-21, richiesta utente — la scelta è del giocatore, vedi
		# select_idea sotto, non più automatica): il pensiero depositato è PERSO ai fini della
		# ricerca. Nessun errore, thoughts_invested/completed_ideas restano invariati; conta solo
		# nel totale aggregato folk.thoughts_count, già incrementato sopra.
		return false

	var active_idea := IdeaCalculator.get_idea(folk.active_idea_id)
	if active_idea == null:
		# Difensivo: active_idea_id valorizzato ma il .tres non è risolvibile — non dovrebbe
		# succedere con dati coerenti (non fallisce silenziosamente sull'incremento, ma nemmeno
		# tenta un cast su null).
		return false

	folk.thoughts_invested[folk.active_idea_id] = folk.thoughts_invested.get(folk.active_idea_id, 0) + amount
	if folk.thoughts_invested[folk.active_idea_id] < active_idea.thoughts_cost:
		return false

	folk.completed_ideas.append(folk.active_idea_id)
	folk.thoughts_invested.erase(folk.active_idea_id)
	folk.active_idea_id = ""
	return true


# "Disponibile" = non ancora completata e con TUTTI i prerequisites già in folk.completed_ideas
# (l'idea attiva stessa resta disponibile: chi distingue "in ricerca" è il chiamante, vedi
# TechTreePanel._state_of).
static func is_available(folk: Folk, idea: Idea) -> bool:
	if folk.completed_ideas.has(idea.id):
		return false
	for prerequisite_id in idea.prerequisites:
		if not folk.completed_ideas.has(prerequisite_id):
			return false
	return true


# Scelta del giocatore (2026-09-21, richiesta utente — sostituisce la vecchia scelta automatica per
# ordine alfabetico): rende `idea_id` l'idea attiva di `folk`. Ritorna false (nessuna modifica) se
# l'id non si risolve o l'idea non è disponibile (già completata, prerequisiti mancanti). Cambiare
# idea attiva NON tocca thoughts_invested: il progresso resta per-idea e riprende da dove era se il
# giocatore ci torna.
#
# current_day/era_rules servono al decadimento dei pensieri (vedi IdeaDecayService): l'idea che
# smette di essere attiva parte con la sua scadenza di grazia, quella che torna attiva la perde.
static func select_idea(folk: Folk, idea_id: String, current_day: int, era_rules: EraRules) -> bool:
	var idea := IdeaCalculator.get_idea(idea_id)
	if idea == null or not is_available(folk, idea):
		return false
	if folk.active_idea_id == idea_id:
		return true
	IdeaDecayService.on_idea_deactivated(folk, folk.active_idea_id, current_day, era_rules)
	folk.active_idea_id = idea_id
	IdeaDecayService.on_idea_activated(folk, idea_id)
	return true


# Idea "coperta" (2026-09-21, richiesta utente — TechTreePanel e popup di sblocco): almeno un
# prerequisito non è né completato né disponibile (o non esiste). Idee senza prerequisiti sono
# sempre visibili.
static func is_hidden(folk: Folk, idea: Idea) -> bool:
	for prerequisite_id in idea.prerequisites:
		if folk.completed_ideas.has(prerequisite_id):
			continue
		var prerequisite := IdeaCalculator.get_idea(prerequisite_id)
		if prerequisite == null or not is_available(folk, prerequisite):
			return true
	return false


# Filtro per IdeaUnlocksService.format_lines (parametro is_hidden): uno sblocco che è un'idea ancora
# coperta va mostrato come "???", altrimenti ne rivelerebbe il nome. Edifici/risorse mai nascosti.
static func is_unlock_hidden(folk: Folk, kind: StringName, unlock_id: String) -> bool:
	if kind != &"idea":
		return false
	var unlocked := IdeaCalculator.get_idea(unlock_id)
	return unlocked != null and is_hidden(folk, unlocked)
