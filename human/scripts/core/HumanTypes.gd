class_name HumanTypes

# Single source of truth per gli enum del dominio umano — stesso ruolo di GameTypes.gd per il
# mondo simulato, ma deliberatamente separato: nessuna delle due classi referenzia l'altra.

enum Sex {
	MALE,
	FEMALE,
}

# Quattro fasce (non tre come GameTypes.AgeBand, tarato sugli animali): CHILD (infanzia,
# pre-riproduttiva), FERTILE_ADULT (età riproduttiva), MATURE_ADULT (adulto ma tipicamente non
# più fertile, soprattutto per le donne — da qui la necessità di durate differenziate per sesso,
# vedi HumanRules.age_band_durations_male/female), OLD. Nomi di membro deliberatamente diversi da
# GameTypes.AgeBand (YOUNG/ADULT/OLD): qui la fascia adulta è divisa in due per riflettere la
# fertilità, un asse che l'animale non modella a questo livello di dettaglio.
enum AgeBand {
	CHILD,
	FERTILE_ADULT,
	MATURE_ADULT,
	OLD,
}

# Occupazione corrente di un HumanIndividual materializzato — solo NONE per ora (nessuna AI/
# assegnazione compiti implementata), valori futuri (es. FORAGING, BUILDING, GUARDING) aggiunti
# qui quando quella logica arriverà, stesso pattern di GameTypes.WorldObjectType/ResourceType
# ("in futuro: ...").
enum Task {
	NONE,
}
