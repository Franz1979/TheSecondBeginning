class_name DebugLogging

# Interruttore unico per tutti i print di debug temporanei aggiunti per validare growth/
# surplus/migration/mortality (terra e FISH). Metti a true per riattivarli tutti insieme
# senza scommentare riga per riga nei singoli servizi.
const ENABLED := true

# Filtro aggiuntivo per i log di ciclo vita (ANIMAL BIRTHS, ANIMAL AGING, ANIMAL OLD AGE DEATHS,
# BIRTH MITIGATION/TERRITORY DYNAMICS, ANIMAL HUNGER SUMMARY/ANIMAL HUNGER dettaglio,
# POPULATION SPLIT): con ENABLED sopra a true stampano sia erbivori che predatori, troppo rumoroso
# mentre si valida la sola natalità/mortalità/territorio dei lupi. A false: quei log restano
# visibili solo per le specie PredatorRules (ANIMAL HUNGER non stampa mai nulla in questo caso,
# visto che quel service processa solo erbivori per costruzione); gli erbivori continuano ad
# essere processati normalmente (nessun comportamento di simulazione cambia, solo il print viene
# soppresso). Rimetti a true per riavere subito tutti i log come prima, senza toccare i singoli
# servizi.
const SHOW_HERBIVORE_LIFECYCLE_LOGS := false
