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

# Tratti d'aspetto per-individuo (2026-09-04, richiesta utente) e persistiti (HumanIndividual.
# hair_color/clothing_color, salvati/caricati come sex/birth_year_virtual). Enum apposta (non un
# Color diretto su HumanIndividual): l'utente ha chiesto esplicitamente "estensibili", così se in
# futuro si aggiungono altre tinte il pool cresce da sé (HumanIndividual.assign_hair_color/
# assign_random_clothing pescano da .values(), mai un conteggio hardcoded) — la mappatura
# enum->Color vera e propria resta in HumanIndividualView (l'aspetto, mai qui: questa classe resta
# agnostica sul COME si disegna, sa solo QUALI categorie esistono, stesso principio già seguito per
# Sex/AgeBand sopra). hair_color, a differenza di clothing_color, è GENETICO da HumanSeedingService.
# _create_child in poi (40/40/20 madre/padre/random, vedi HumanIndividual.assign_hair_color) —
# random puro solo per i fondatori senza genitori simulati.
enum HairColor {
	BLONDE,
	BROWN,
	BLACK,
}

enum ClothingColor {
	TAN,
	DARK_BROWN,
	RUST,
	OLIVE,
	# Aggiunto 2026-09-04, richiesta utente — DEVE restare visivamente distinto dal futuro grigio
	# dei capelli anziani (Step 4, non ancora implementato): vedi HumanIndividualView per il
	# colore vero, tarato apposta più scuro/freddo del grigio capelli previsto.
	GRAY,
}
