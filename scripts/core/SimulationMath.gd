class_name SimulationMath
extends RefCounted

# Arrotondamento stocastico: converte un valore continuo atteso in un intero SENZA il bias
# sistematico di round() (che arrotonda sempre nella stessa direzione per lo stesso valore
# frazionario, es. 0.6 -> sempre 1) — floor(value) + 1 con probabilità pari alla parte
# decimale, così nel lungo periodo la MEDIA su molti cicli converge al valore continuo atteso
# invece di scostarsene sistematicamente. Equivalente a round() in valore atteso, ma senza bias
# a singolo campione — importante quando value deriva da conteggi piccoli (popolazioni animali
# ridotte), dove il bias di round() diventa proporzionalmente enorme (es. 3 vecchi su 5 anni di
# durata attesa -> 0.6 morti/anno atteso, ma round(0.6) fa morire SEMPRE esattamente 1 individuo
# ogni anno invece che nel 60% dei casi). A numeri grandi converge comunque quasi allo stesso
# risultato di round() (nessuna soglia di magnitudine: usata uniformemente ovunque serva
# convertire un conteggio atteso frazionario in un intero, indipendentemente dalla scala).
# Non seedato (randf() globale): stesso livello di non-determinismo già accettato altrove nella
# simulazione (es. InitialResourceSetupService.randf_range), nessun bisogno di riproducibilità
# qui — a differenza della generazione del mondo (ResourcePositionService), che usa invece un
# seed dedicato.
# debug_label (Step diagnostico, solo predatori — vedi chiamanti): se non vuoto E
# DebugLogging.ENABLED, stampa il tiro grezzo di randf() insieme a floor/fractional/risultato —
# usa lo STESSO randf() già chiamato per la decisione, mai un secondo tiro extra (che
# perturberebbe la sequenza per tutte le chiamate successive). Vuoto per default e per ogni
# chiamante erbivoro: nessun log aggiuntivo, nessun cambio di comportamento per loro.
static func stochastic_round(value: float, debug_label: String = "") -> int:
	# Tipizzate esplicitamente (non `:=`): floor() confonde l'inferenza di tipo di GDScript qui,
	# risultando in un errore di parsing su "fractional" nonostante value sia già float.
	var floor_value: float = floor(value)
	var fractional: float = value - floor_value
	var roll := randf()
	var result: int = int(floor_value) + (1 if roll < fractional else 0)
	if debug_label != "" and DebugLogging.ENABLED:
		print(
			"[STOCHASTIC ROUND] %s value=%.3f floor=%d fractional=%.3f roll=%.3f -> %d" % [
				debug_label, value, int(floor_value), fractional, roll, result
			]
		)
	return result
