class_name Action
extends RefCounted

# Classe base per il futuro sistema di azioni (Walk/Rest/Cut/Build/...) del refactor Stamina
# (2026-09-06, richiesta utente) — RefCounted come ogni altra classe di stato/servizio del
# progetto (mai Node, vedi CLAUDE.md), pura interfaccia/scheletro. Sottoclassi concrete oggi:
# WalkAction/RestAction (vedi file omonimi, stessa cartella) — Cut/Build restano ancora da
# scrivere. HumanIndividual.current_task (Task, 2026-09-07 — SOSTITUISCE il precedente
# current_action: Action, un solo campo) referenzia una sequenza ordinata di istanze di questa
# classe (vedi Task.gd) — HumanIndividualActionService.apply_action legge/avanza quella sequenza,
# questa classe resta ignara di Task/HumanIndividual, la conosce solo per dispatch dinamico sui
# parametri Variant sotto.
#
# Deliberatamente NESSUN collegamento a HumanIndividual/HumanIndividualMovementService/GameScene:
# `individual` sotto è tipizzato Variant, non HumanIndividual, per non introdurre una dipendenza da
# quella classe qui — il futuro service esterno che orchestrerà le azioni deciderà lui il tipo
# concreto da passare.


# Bersaglio opzionale dell'azione (una cella, una risorsa, un altro individuo, ...) — tipo
# generico (Variant, non ancora un tipo concreto) perché nessuna sottoclasse esiste ancora per
# decidere cosa un target debba essere; Cut/Build lo popoleranno quando arriveranno. null = azione
# senza bersaglio (es. un futuro Rest, che agisce solo sull'individuo stesso).
var target: Variant = null


# Variazione di stamina per questo istante/frame — negativa per un drain (es. Walk/Cut consumano),
# positiva per un recharge (es. Rest recupera). `individual`/`delta` generici (Variant/float) così
# un futuro service esterno può chiamarlo senza che questa classe dipenda da HumanIndividual.
# Implementazione di base neutra (nessun effetto): ogni sottoclasse concreta la sovrascriverà con
# la propria formula di costo/recupero.
func get_stamina_delta(individual: Variant, delta: float) -> float:
	return 0.0


# Vero se l'azione è da considerarsi conclusa — `individual` generico (Variant), stesso principio
# di get_stamina_delta sopra: nessuna dipendenza da HumanIndividual in questa classe base (corretta
# 2026-09-06, richiesta utente — l'asimmetria precedente, nessun parametro qui contro uno su
# get_stamina_delta, impediva a una sottoclassa di verificare il completamento in base allo stato
# dell'individuo). Implementazione di base neutra: l'azione base non termina mai da sola (nessuno
# stato interno di progresso esiste qui) — ogni sottoclassa concreta la sovrascrive con il proprio
# criterio.
func is_complete(individual: Variant) -> bool:
	return false


# Invocata UNA VOLTA quando questo step diventa quello ATTIVO di una Task (2026-09-07, richiesta
# utente, introdotta insieme a Task) — sia all'assegnazione del primissimo step (chi crea la Task
# la chiama subito dopo, vedi HumanIndividual.set_target) sia all'avanzamento automatico a uno step
# successivo (vedi HumanIndividualActionService.apply_action). Punto in cui una sottoclasse
# concreta può inizializzare lo stato dell'individuo necessario per ESEGUIRE questo step — es.
# WalkAction imposta qui individual.target_position/is_moving dal proprio `target` (vedi
# WalkAction.gd). `individual` generico (Variant), stesso principio di get_stamina_delta/
# is_complete sopra.
#
# is_moving = false DI DEFAULT (bugfix, richiesta utente 2026-09-07 — "il pipottino quando pensa
# continua a muovere gambe e braccia come stesse camminando"): is_moving restava true per l'intera
# durata di una Task multi-step, azzerato solo da stop() — un WalkAction lo mette a true nel proprio
# activate(), ma nessuno step successivo (Think/Deposit/Rest) lo rimetteva a false quando diventava
# lo step attivo, quindi HumanIndividualView continuava ad animare le gambe (gated su is_moving,
# vedi lì) anche durante uno step immobile. Messo qui nella classe BASE, non ripetuto in ogni
# sottoclasse stazionaria, cosi' ogni futura azione immobile (Cut/Build/...) lo ottiene gratis
# semplicemente non sovrascrivendo activate(); WalkAction resta l'UNICA sottoclasse che lo
# riporta a true, subito dopo aver chiamato questa implementazione base (vedi WalkAction.activate).
func activate(individual: Variant) -> void:
	individual.is_moving = false


# Invocata UNA VOLTA quando is_complete(individual) diventa vero, PRIMA che la Task avanzi allo step
# successivo (2026-09-07, richiesta utente, introdotta con ThinkAction) — simmetrica ad activate()
# sopra: se activate() è "come preparo l'individuo a ESEGUIRE questo step", questa è "cosa lascio
# sull'individuo quando questo step FINISCE" (es. ThinkAction imposta qui individual.pending_thought
# = true, vedi ThinkAction.gd). Deliberatamente un metodo a parte, non un effetto collaterale dentro
# is_complete() stessa: is_complete() resta una query pura in ogni sottoclasse esistente (WalkAction
# confronta solo position/target, senza scrivere nulla) — un chiamante potrebbe in teoria valutarla
# più volte per lo stesso stato senza aspettarsi effetti collaterali, mentre on_complete() ha una
# semantica esplicita di "chiamami esattamente una volta, ora". Richiamata da
# HumanIndividualActionService.apply_action subito dopo aver verificato is_complete(), prima di
# avanzare l'indice della Task. `individual` generico (Variant), stesso principio di get_stamina_
# delta/is_complete/activate sopra. Implementazione di base neutra: un'azione senza nulla da
# lasciare sull'individuo al termine (es. WalkAction/RestAction) non la sovrascrive.
func on_complete(individual: Variant) -> void:
	pass
