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
static func stochastic_round(value: float) -> int:
	# Tipizzate esplicitamente (non `:=`): floor() confonde l'inferenza di tipo di GDScript qui,
	# risultando in un errore di parsing su "fractional" nonostante value sia già float.
	var floor_value: float = floor(value)
	var fractional: float = value - floor_value
	if randf() < fractional:
		return int(floor_value) + 1
	return int(floor_value)
