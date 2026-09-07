class_name RestAction
extends Action

# Seconda sottoclasse concreta di Action (2026-09-07, richiesta utente) — a differenza di
# WalkAction (comandata esplicitamente dal player), Rest è lo stato IMPLICITO di un individuo
# quando non ha nessun'altra azione assegnata: nessun comando manuale, nessun target (vedi _init
# sotto, stesso pattern di WalkAction). `individual` resta tipizzato Variant in get_stamina_delta
# (deve combaciare esattamente col parametro della classe base Action, vedi Action.gd/WalkAction.gd
# per il perché) — nessuna perdita di correttezza, solo niente controllo statico a compile-time su
# questo singolo parametro.
#
# is_complete() resta il default ereditato da Action (sempre false): non serve determinare un
# completamento per Rest in questo step — è lo stato di riempimento (HumanIndividualActionService,
# vedi lì) a decidere quando applicarlo, non un criterio di fine-azione proprio.
#
# TODO futuro: Rest richiederà che l'individuo sia tornato a un luogo specifico (casa), concetto
# non ancora esistente nel progetto — per ora recupera stamina ovunque si trovi.

# Recupero di stamina al GIORNO (rinominata da STAMINA_REGEN_PER_SECOND, richiesta utente,
# 2026-09-07 — in coppia con l'aggancio al game clock: `delta` qui è ora una frazione di giorno di
# gioco, non più secondi reali, quindi il nome precedente descriveva un'unità che questa costante
# non moltiplica più). Valore numerico invariato (50.0, resta il punto di partenza ARBITRARIO già
# scelto, richiesta utente) — solo il significato cambia, da "al secondo" a "al giorno intero".
const STAMINA_REGEN_PER_DAY: float = 50.0


func _init() -> void:
	target = null


# Nessun calcolo superfluo una volta pieno: ritorna 0.0 immediatamente se la stamina è già al
# tetto massimo. Altrimenti il recupero è clampato in uscita (min(regen_calcolato, spazio
# rimanente)) così il chiamante può sempre sommarlo direttamente a current_stamina senza bisogno
# di un clamp separato lì.
func get_stamina_delta(individual: Variant, delta: float) -> float:
	if individual.current_stamina >= individual.max_stamina:
		return 0.0
	var regen: float = STAMINA_REGEN_PER_DAY * delta
	return min(regen, individual.max_stamina - individual.current_stamina)
