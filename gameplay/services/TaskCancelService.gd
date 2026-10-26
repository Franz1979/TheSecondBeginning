class_name TaskCancelService
extends RefCounted

# Chiusura della task in corso di un pipottino (2026-10-25, richiesta utente — estratta da GameScene._stop_member_task, il
# tasto H): la task non va in coda come per un bisogno, si chiude e il lavoro torna alla lista. Usata da H / X del
# pannello / X delle righe "Diretto" (GameScene._stop_member_task) e da chi va a letto (SicknessService.on_bedridden).
# Stateless, stesso pattern degli altri *Service; gli effetti di presentazione tornano in `effects`.


# Effetto di H su `member`: stessa chiusura della task corrente, regola del carico, "salta la lista una volta" e ripresa.
# `reason`: testo dei log (caccia, coordinatore).
static func stop_current_task(ctx: GameContext, member: HumanIndividual, effects: GameEffects, reason: String = "annullata a mano (X o tasto H)") -> void:
	if member == null:
		return
	# Ordine di zona del cassetto (2026-10-09, richiesta utente): H su chi lo porta fa come "Rimetti in coda" — carico
	# riportato con la regola di sempre, ma l'ordine non resta nella coda personale (ripetizioni dei viaggi, consegne,
	# tagli successivi): torna subito in "In coda" con quello che resta, la stessa scelta e la stessa zona.
	var zone_order := DrawerOrderService.find(ctx.game_data, DrawerOrderService.order_of_task(member.current_task))
	if DrawerOrderService.is_zone_order_type(String(zone_order.get("type", ""))) and bool(zone_order.get("taken", false)):
		ZoneOrderCommandService.release_drawer_zone_order(ctx, zone_order, effects)
		return
	if HuntService.is_hunt_task(member.current_task):
		HuntService.log_event(member, "caccia chiusa: %s." % reason)
	# Coordinatore fermato con H (2026-10-09): il posto si libera, con il motivo nel log.
	CoordinatorService.end_shift_by_player(ctx.game_data, member, reason)
	# Annullo del giocatore con l'assegnazione attiva (2026-10-07): al prossimo momento libero il pipottino salta una
	# volta la lista dei lavori, altrimenti riprenderebbe subito il lavoro appena annullato.
	if member.current_task != null and JobBoardService.is_enabled(ctx.folk):
		member.skip_job_board_once = true
	var stopped_produce_building: Building = null
	if member.current_task != null and member.current_task.task_name == "task_produce_name":
		for step in member.current_task.steps:
			if step is ProduceAction:
				stopped_produce_building = (step as ProduceAction).target_building
				break
	# Regola unica del carico (2026-09-29, CargoReturnService.release_cargo): se la Task annullata possiede il carico,
	# il pipottino lo riporta al magazzino più vicino (a terra solo se nessun magazzino lo accetta); H su una Task di
	# ritorno la ferma davvero, con il carico a terra. Con un carico di un'altra Task lo zaino resta com'è.
	# Ritiro di un mucchio della coda (2026-10-09): il ritorno del carico che lo sostituisce non è una riga "Diretto".
	var stopped_board_pile := member.current_task != null and PileJobProvider.is_board_pile_task(member.current_task)
	var cargo_outcome := CargoReturnService.release_cargo(member, member.current_task, ctx.world)
	if cargo_outcome != CargoReturnService.Outcome.RETURNING:
		member.stop(false)
	elif stopped_board_pile and member.current_task != null and CargoReturnService.is_cargo_return_task(member.current_task):
		member.current_task.context[DrawerOrderService.CARGO_KEY] = true
	# Ordine intero (2026-09-26): la produzione annullata non conta più nel fabbisogno dell'edificio.
	if stopped_produce_building != null:
		JobWorkScanService.reconcile_production_units(ctx.individuals, stopped_produce_building)
	# Ritorno al magazzino già attivo come Task corrente: niente da risolvere.
	if cargo_outcome == CargoReturnService.Outcome.RETURNING:
		return
	# Bugfix (2026-09-14, richiesta utente) — member.stop() da solo azzera SOLO current_task, senza mai toccare task_queue
	# né richiamare resolve_idle_individual: un individuo con Task sospese in coda restava bloccato per sempre con
	# current_task null e la coda intatta. STESSA chiamata del completamento naturale/seeding/nascita/load.
	HumanIndividualActionService.resolve_idle_individual(member, ctx.age_band_of(member), ctx.world)
