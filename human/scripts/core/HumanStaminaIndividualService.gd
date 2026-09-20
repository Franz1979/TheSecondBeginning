class_name HumanStaminaIndividualService
extends RefCounted

# Ricalcolo di HumanIndividual.max_stamina per un SINGOLO individuo (2026-09-06, richiesta utente)
# — stesso principio di separazione di HumanMortalityIndividualService/HumanCouplingIndividualService
# (un *Service RefCounted stateless), ma qui il metodo opera su UN individuo alla volta: il
# chiamante (GameTimeService._on_day_advanced) è quello che itera l'intera popolazione e misura il
# costo aggregato, non questo file.
#
# SOLUZIONE TEMPORANEA (richiesta utente, 2026-09-06) — ricalcolo PERIODICO (una volta al giorno,
# incondizionato, per OGNI individuo) invece che EVENT-DRIVEN (solo quando qualcosa che influenza
# max_stamina cambia davvero: inizio/fine gravidanza, assegnazione/rimozione di un figlio a carico,
# cambio age_band). Il motivo è strutturale, non di comodità: il progetto non ha oggi NESSUN
# meccanismo per rilevare questi cambi di stato (vedi ricognizione 2026-09-06) — l'unico confronto
# "fascia precedente vs attuale" esistente vive dentro HumanIndividualView._process(), per decidere
# se ridisegnare (early-out queue_redraw()), non è un evento generico riusabile altrove. Finché non
# esisterà un simile meccanismo generale, il ricalcolo periodico è l'unica opzione disponibile senza
# costruire prima quell'infrastruttura — da rivedere quando servirà un sistema più granulare.
#
# age_band risolto con le durate EFFETTIVE per l'Era corrente (game_data.era_effective_age_band_
# durations_male/female), MAI human_rules.age_band_durations_male/female direttamente — stesso
# principio già fissato altrove nel progetto (HumanMortalityIndividualService/
# HumanCouplingIndividualService/HumanConceptionIndividualService, tutte con lo stesso identico
# bugfix storico: ignorare l'Era classificava erroneamente un individuo già invecchiato). era_rules
# risolto UNA VOLTA dal chiamante (stesso principio "il chiamante risolve età/era una volta, il
# servizio resta puro rispetto alla provenienza" già seguito da _run_annual_human_conception/
# _run_annual_human_births) — serve solo per il ramo "figlio a carico" di HumanCalculator.
# get_max_stamina.
#
# Fallback HumanIndividual.FALLBACK_MAX_STAMINA quando la catena source_group_ref->folk_ref->
# human_rules_ref non è risolvibile — stesso criterio già usato da
# HumanIndividual._resolve_initial_max_stamina alla creazione (mai un secondo fallback diverso).
#
# Clamp SOLO verso il basso su current_stamina (2026-09-06, richiesta utente) — se il nuovo
# max_stamina scende sotto l'attuale current_stamina, quest'ultima viene tagliata al nuovo tetto;
# MAI il contrario (un max_stamina che sale non "rabbocca" mai current_stamina, che resta quella
# che era). Copre sia il caso odierno (fallback 5000.0 corretto al primo ricalcolo reale, appena
# la catena source_group_ref diventa risolvibile) sia casi futuri in cui max_stamina scenda per
# altri motivi (gravidanza, quando arriverà un vero consumo). Verificato che nessun altro punto del
# codebase scrive/clampa current_stamina — solo HumanIndividual._init() (assegnazione iniziale) e
# HumanIndividualActionService.apply_action (drain/recharge, deliberatamente SENZA clamp, task
# separato) lo toccano; questo resta l'UNICO punto che applica il tetto massimo.
static func recalculate_max_stamina(individual: HumanIndividual, game_data: GameData, era_rules: EraRules, world: World = null) -> void:
	var human_rules: HumanRules = null
	var changed_to_band: int = -1
	if individual.source_group_ref != null and individual.source_group_ref.folk_ref != null:
		human_rules = individual.source_group_ref.folk_ref.human_rules_ref
	var max_before: float = individual.max_stamina
	if human_rules == null:
		individual.max_stamina = HumanIndividual.FALLBACK_MAX_STAMINA
	else:
		var age := float(game_data.year - individual.birth_year_virtual)
		var age_band := HumanCalculator.get_age_band(
			game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female,
			individual.sex, age
		)
		individual.max_stamina = HumanCalculator.get_max_stamina(
			human_rules, age_band, individual.sex, individual.is_pregnant, individual.dependent_child_id != -1, era_rules
		)
		# Cambio di fascia d'eta' (2026-09-19, richiesta utente): se la fascia e' cambiata rispetto all'ultimo
		# ricalcolo (stamina_age_band noto) e il massimo SALE, current_stamina sale in proporzione,
		# mantenendo la stessa percentuale di prima. Se prima era 0 su 0 (es. INFANT, moltiplicatore 0.0) si
		# tratta come pieno: chi comincia a camminare non parte esausto. Un massimo che sale per altri
		# motivi (gravidanza, figlio a carico) NON alza current_stamina, come prima.
		if individual.stamina_age_band != -1 and individual.stamina_age_band != age_band and individual.max_stamina > max_before:
			var ratio: float = (individual.current_stamina / max_before) if max_before > 0.0 else 1.0
			var raised: float = clampf(ratio, 0.0, 1.0) * individual.max_stamina
			if DebugLogging.ENABLED and DebugLogging.SHOW_STAMINA_RECALC_LOGS:
				print("[HUMAN STAMINA RECALC] #%d %s: cambio fascia (%s -> %s), max %.1f -> %.1f, current_stamina %.1f -> %.1f (stessa percentuale, 0 su 0 = pieno)" % [
					individual.id, individual.name, HumanTypes.AgeBand.keys()[individual.stamina_age_band],
					HumanTypes.AgeBand.keys()[age_band], max_before, individual.max_stamina, individual.current_stamina, raised
				])
			individual.current_stamina = raised
		if individual.stamina_age_band != -1 and individual.stamina_age_band != age_band:
			changed_to_band = age_band
		individual.stamina_age_band = age_band
	if individual.current_stamina > individual.max_stamina:
		# Log SOLO quando il clamp scatta davvero (evento reale, non ogni ricalcolo — stesso
		# principio di [HUMAN BIRTH]/[HUMAN DEATH]: un log ad ogni passata "senza effetto" sarebbe
		# rumore) — riusa lo stesso flag di [HUMAN STAMINA RECALC] (concetto strettamente correlato,
		# nessun flag dedicato nuovo).
		if DebugLogging.ENABLED and DebugLogging.SHOW_STAMINA_RECALC_LOGS:
			print("[HUMAN STAMINA RECALC] #%d %s: current_stamina %.1f > nuovo max_stamina %.1f -> tagliata a %.1f" % [
				individual.id, individual.name, individual.current_stamina, individual.max_stamina, individual.max_stamina
			])
		individual.current_stamina = individual.max_stamina
	# Cambio di fascia con individuo libero (2026-09-19, richiesta utente): resolve_idle_individual e' chiamata
	# solo a eventi, quindi chi cambia fascia senza generarne (es. INFANT -> CHILD, mai avuto una task)
	# resterebbe fermo. Solo su cambio fascia + current_task == null: nessuna verifica giornaliera degli
	# inattivi, chi il giocatore ha lasciato fermo di proposito non viene toccato. Ultimo passo, cosi' vede
	# la stamina gia' aggiornata/tagliata. Serve `world` dal chiamante; senza (null) non fa nulla.
	if changed_to_band != -1 and changed_to_band != HumanTypes.AgeBand.INFANT \
			and world != null and individual.current_task == null:
		HumanIndividualActionService.resolve_idle_individual(individual, changed_to_band as HumanTypes.AgeBand, world)
