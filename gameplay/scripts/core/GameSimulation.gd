class_name GameSimulation
extends RefCounted

# Driver del tempo della simulazione del villaggio (2026-10-17, refactoring GameScene blocco 3 — docs/design/
# gamescene_refactoring.md): l'ordine dei passi di logica del giro "al secondo" e del giro giornaliero, in un punto solo e
# senza nodi. La scena (oggi GameScene 2D, domani quella 3D) gli passa il contesto, il momento di gioco e un GameEffects, poi
# esegue gli effetti. Statico e senza stato: lo stato dei passi vive in GameData (e nei suoi *_runtime).
#
# Passi ancora in scena, da spostare qui con i blocchi che li estraggono: il riallineamento giornaliero degli ordini di
# produzione (dopo tick_day), il gestore delle scorte (blocco 4), il ciclo degli individui (blocco 5).


# Giro "al secondo" (prima dentro GameScene._refresh_pending_entries, stesso ordine): gira ogni secondo reale e a ogni altro
# ricalcolo di "In sospeso". `now`: momento di gioco in giorni (con la frazione del giorno in corso).
static func tick_second(ctx: GameContext, now: float, effects: GameEffects) -> void:
	if ctx.game_data == null or ctx.world == null:
		return
	# Ordini di zona del cassetto (2026-10-09): quelli presi che nessuno porta più tornano in coda (o spariscono a serie
	# finita) prima di raccogliere i lavori.
	DrawerOrderService.settle_zone_orders(ctx)
	# Edifici entrati o usciti dallo stato "Danneggiato" (2026-10-10): mappa del movimento della loro cella aggiornata.
	BuildingMaintenanceService.sync_damaged_buildings(ctx.world, ctx.game_data, effects)
	# Riparazioni richieste (2026-10-10): quelle non più valide si chiudono, poi quelle automatiche sotto soglia.
	BuildingMaintenanceService.settle_repair_requests(ctx.world)
	BuildingMaintenanceService.auto_request_repairs(ctx.world, ctx.game_data, ctx.folk, ctx.individuals)
	# Sgombero automatico delle macerie (2026-10-10): segnate come col clic su "Sgombera".
	for building in BuildingMaintenanceService.rubble_to_clear(ctx.world, ctx.game_data, ctx.folk):
		BuildingLifecycleService.mark_for_demolition(building, effects)
		if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
			print("[JOB BOARD] Sgombero richiesto in automatico per le macerie #%d (crollo di %s): in coda come demolish:%d." % [
				building.id, building.get_rubble_source_display_name(), building.id
			])
	# Attrezzi presi in deposito per un lavoro (2026-10-11): riposti da chi è libero, se la regola è accesa.
	for created in ToolFetchService.return_borrowed_tools(ctx):
		effects.wire_storage_task(created["task"], created["member"])
	# Coordinatori ai punti di assegnazione (2026-10-09, CoordinatorService). Con la sola idea, anche senza punti
	# (2026-10-10): così, quando l'ultimo punto sparisce, chi va al punto o è in fila smette e il turno del coordinatore
	# finisce.
	if JobBoardService.is_idea_completed(ctx.folk):
		CoordinatorService.tick(ctx.game_data, ctx.world, ctx.individuals, now, ctx.age_band_of)


# Giro giornaliero (prima in GameScene._on_day_advanced, stesso ordine), dopo il calo giornaliero dell'Integrità
# (WorldTimeService, già girato).
static func tick_day(ctx: GameContext, effects: GameEffects) -> void:
	# Crollo a Integrità zero (2026-10-10).
	BuildingLifecycleService.collapse_ruined_buildings(ctx, effects)
	# Case danneggiate (2026-10-10, effetti passo 5): sfratto di chi è in più, poi riassegnazione.
	BuildingLifecycleService.evict_damaged_house_overflow(ctx, effects)
