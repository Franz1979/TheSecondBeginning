class_name TaskReassignmentService
extends RefCounted

# Servizio stateless (2026-09-12, richiesta utente — sostituzione di _pending_build_tasks con un
# percorso generico "click individuo selezionato + click destro su un target riassegnabile"):
# STESSO principio "istanzia con .new() e chiama un solo metodo" già in uso da
# SpatialSelectionService/WarehouseSelectionService/ecc — nessuno stato interno, nessun campo.
#
# `target` è duck-typed (Variant, non un tipo/interfaccia formale) — deve solo esporre i quattro
# metodi usati sotto (has_resumable_task/get_resumable_task_definition_path/
# get_resumable_task_context/get_debug_target_key), stessa convenzione già seguita da
# SpatialSelectionService.find_nearest per i suoi candidati. Oggi l'UNICO tipo che li implementa è
# Building (vedi simulation/scripts/game/Building.gd), ma nessun codice qui sotto assume quel tipo
# specifico: un futuro secondo target riassegnabile (non-Building) passerebbe da qui senza modifiche.
#
# NESSUNA distinzione tra "prima assegnazione" e "riassegnazione dopo interruzione" (richiesta
# esplicita utente, punto 2) — è lo stesso identico percorso in entrambi i casi: la Task viene
# SEMPRE ricostruita da zero via TaskFactory, e sono gli step stessi (SetupSiteAction/ClearAction/
# BuildAction, get_stamina_delta) a fare da soli l'auto-skip quando il progresso è già presente su
# target.construction_progress — nessuna soglia/percentuale letta o confrontata qui.
#
# extra_context copre i dati che il target NON può risolvere da sé perché appartengono a un layer
# che il target (se è un Building, layer di simulazione) non può conoscere — oggi "macro_state"
# (serve World, irraggiungibile da Building.gd) e "is_currently_grass" (serve il renderer live,
# layer di gameplay/rendering) — vedi Building.get_resumable_task_context per il dettaglio. Fuso
# con overwrite=true: extra_context vince in caso di chiave duplicata, ma nella pratica di oggi le
# chiavi non si sovrappongono mai (target ne fornisce due, extra_context le altre due).
#
# age_band (2026-09-12, richiesta utente — collegamento di HumanTypes.AgeBand.INFANT al gameplay) —
# semplicemente inoltrato a individual.assign_task sotto, che lo richiede (vedi il commento su
# HumanIndividual.assign_task per il perché è obbligatorio, non calcolabile da questa classe
# stateless). Il chiamante lo risolve già (GameScene._resolve_age_band).
static func reassign_task(target: Variant, individual: HumanIndividual, age_band: HumanTypes.AgeBand, extra_context: Dictionary = {}) -> Task:
	if target == null or individual == null or not target.has_resumable_task():
		return null

	var definition := load(target.get_resumable_task_definition_path()) as TaskDefinition
	if definition == null:
		return null

	var context: Dictionary = target.get_resumable_task_context()
	context.merge(extra_context, true)

	var task := TaskFactory.build_task(definition, context)
	# TaskDebugRegistry (2026-09-12, richiesta utente — fix righe duplicate/fantasma) — valorizzato
	# PRIMA di assign_task sotto, che è quanto scatena TaskDebugRegistry.on_task_assigned: quel punto
	# usa debug_target_key per chiudere un'eventuale riga "in corso" già aperta per questo STESSO
	# target (es. lasciata da un'interruzione precedente, magari di un individuo diverso da quello
	# assegnato qui) prima di aprirne una nuova. Vedi Task.debug_target_key/Building.
	# get_debug_target_key per il dettaglio.
	task.debug_target_key = target.get_debug_target_key()
	individual.assign_task(task, age_band)
	return task
