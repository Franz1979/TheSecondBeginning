class_name IdeaProgressService
extends RefCounted

# Primo consumatore reale del modello dati Idea/Folk (2026-09-07, richiesta utente — prima erano
# solo campi dichiarati, nessuna logica). *Service stateless (RefCounted, static func — stesso
# pattern di HumanStaminaIndividualService.recalculate_max_stamina, stessa cartella): opera su un
# Folk passato dal chiamante, nessuno stato proprio. Non conosce BuildBar/GameScene — segnala un
# completamento solo col valore di ritorno (bool), il chiamante decide se/come reagire (vedi
# GameScene._debug_add_thought, che richiama _refresh_building_slots_buildable SOLO quando torna
# true — lo stesso punto di aggancio predisposto nel passo precedente).


# Incrementa i pensieri investiti nell'Idea attiva di `folk` (assegnandone una automaticamente se
# nessuna è attiva, vedi _pick_next_idea_id sotto) e, se il costo viene raggiunto, la completa.
# Ritorna true SOLO nel frame/chiamata in cui un'Idea viene completata (mai per un investimento che
# non la conclude) — il chiamante lo usa per sapere quando propagare il cambiamento altrove (es.
# BuildBar), senza dover ricontrollare da sé completed_ideas prima/dopo.
static func add_thoughts(folk: Folk, amount: int) -> bool:
	if folk.active_idea_id == "":
		folk.active_idea_id = _pick_next_idea_id(folk)
	if folk.active_idea_id == "":
		# Nessuna Idea disponibile — tutte già completate, o le rimanenti hanno prerequisiti non
		# ancora soddisfatti. Nessun errore: uno stato legittimo, i pensieri vanno semplicemente
		# persi finché non si libera un'Idea (nessun accumulo "in sospeso" da nessuna parte, per
		# design — non richiesto, non introdotto).
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


# Prima Idea (per ordine di IdeaCalculator.list_idea_ids(), alfabetico per id) non ancora completata
# i cui prerequisites sono TUTTI già in folk.completed_ideas — "" se nessuna qualifica (tutte
# completate, o tutte bloccate da prerequisiti mancanti). Nessuna logica di scelta tra più opzioni
# equivalenti richiesta ora (richiesta esplicita utente): la prima trovata vince, sempre — con
# una sola Idea esistente oggi (paleolithic_constructions, prerequisites=[]) è sempre lei finché non
# viene completata.
static func _pick_next_idea_id(folk: Folk) -> String:
	for idea_id in IdeaCalculator.list_idea_ids():
		if folk.completed_ideas.has(idea_id):
			continue
		var idea := IdeaCalculator.get_idea(idea_id)
		if idea == null:
			continue
		var prerequisites_met := true
		for prerequisite_id in idea.prerequisites:
			if not folk.completed_ideas.has(prerequisite_id):
				prerequisites_met = false
				break
		if prerequisites_met:
			return idea_id
	return ""
