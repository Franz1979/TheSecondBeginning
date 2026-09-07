class_name DepositAction
extends Action

# Quarta sottoclasse concreta di Action — azione GENERICA di deposito, non specifica a "pensiero":
# in questo passo (2026-09-07, richiesta utente) implementa SOLO il ramo pensiero (Folk.
# thoughts_invested via IdeaProgressService), il ramo oggetto fisico resta un punto da estendere
# per un futuro Harvest/PickUp (vedi on_complete sotto per dove agganciarlo). Nessun target di
# posizione (stesso pattern di RestAction/ThinkAction — vedi _init sotto): il posizionamento è già
# garantito dal WalkAction precedente nella stessa Task, l'individuo è già dove deve essere quando
# Deposit parte, questa classe non verifica/richiede nulla sulla posizione.
#
# ISTANTANEA — a differenza di WalkAction (bersaglio spaziale) e ThinkAction (bersaglio temporale,
# un accumulatore confrontato con duration), questa non ha alcuno stato di progresso interno:
# is_complete() è SEMPRE true, quindi si completa nello stesso frame/chiamata in cui diventa lo step
# attivo di una Task (stesso "deposito istantaneo" già ipotizzato in passato per un'azione di questo
# tipo). get_stamina_delta ritorna sempre 0.0 (nessun costo — depositare non è uno sforzo fisico
# come camminare né mentale come pensare).

# idea_id dell'Idea completata DA QUESTO deposito, se ne ha completata una (2026-09-07) — segnale
# d'ISTANZA, non un evento globale: chi costruisce la Task con questo step (quando esisterà una
# vera TaskDefinition "Daydream", non ancora in questo passo) lo collega UNA VOLTA alla creazione,
# esattamente come GameScene collega TechTreePanel.idea_completed una volta in _ready() — stesso
# identico principio di disaccoppiamento: DepositAction non conosce GameScene/BuildBar, si limita a
# segnalare "un'Idea è stata completata da questo deposito", chi ascolta decide se/come reagire
# (es. _refresh_building_slots_buildable). Un segnale per-istanza invece di un bus/autoload globale
# perché non esiste già un bus di eventi nel progetto (GameSettings è per stato di sessione, non
# eventi) e introdurne uno solo per questo sarebbe sproporzionato rispetto al bisogno reale.
signal idea_completed(idea_id: String)

# Emesso OGNI VOLTA che questo deposito esegue davvero il ramo pensiero (2026-09-07, richiesta
# utente — effetto visivo "una lampadina sale e sfuma") — a differenza di idea_completed sopra, che
# scatta SOLO quando quel pensiero fa scattare il completamento dell'Idea attiva, questo scatta ad
# OGNI deposito riuscito (pending_thought era true, Folk risolvibile), completi o meno l'Idea.
# Nessun payload: chi ascolta ha già l'individuo (lo cattura al momento del collegamento, vedi
# GameScene._debug_test_daydream_task), questa classe non lo conosce come tipo concreto (Variant).
signal thought_deposited()


func _init() -> void:
	target = null


func get_stamina_delta(individual: Variant, delta: float) -> float:
	return 0.0


func is_complete(individual: Variant) -> bool:
	return true


# Ramo "pensiero" (unico implementato in questo passo) — risolve Folk dalla stessa catena già in
# uso altrove (individual.source_group_ref.folk_ref, vedi HumanStaminaIndividualService per il
# precedente), poi IdeaProgressService.add_thoughts(folk, 1). Guardie difensive su source_group_ref/
# folk_ref null (stesso trattamento già visto altrove per questa catena, es.
# HumanStaminaIndividualService.recalculate_max_stamina) — non dovrebbero mai essere null con dati
# coerenti, ma questa azione non deve fallire rumorosamente se lo sono.
#
# TODO ramo "oggetto fisico" (futuro Harvest/PickUp, richiesta esplicita di non implementarlo ora):
# qui andrà un secondo ramo (es. `elif target != null: ...` o un campo dedicato tipo `deposit_kind`)
# che deposita una risorsa raccolta invece di un pensiero — DepositAction resta l'azione GENERICA di
# deposito, il ramo pensiero e il futuro ramo oggetto convivranno nello stesso on_complete().
func on_complete(individual: Variant) -> void:
	if not individual.pending_thought:
		return
	if individual.source_group_ref == null or individual.source_group_ref.folk_ref == null:
		return
	var folk: Folk = individual.source_group_ref.folk_ref
	individual.pending_thought = false
	thought_deposited.emit()
	if IdeaProgressService.add_thoughts(folk, 1):
		idea_completed.emit(folk.completed_ideas[-1])
