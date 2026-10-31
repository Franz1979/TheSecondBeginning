class_name SimulationSettings

# Fauna selvatica "ad hoc" (2026-10-31, richiesta utente — piano fauna, passo 0): a true gli animali selvatici non sono
# più PopulationGroup simulati in tutto il mondo, ma esistono solo nelle macrocelle dove gioca il giocatore. Per ora
# salta soltanto la semina mondiale (WorldScene._populate_new_world) e le prede garantite alla partenza (GameScene);
# i passi successivi del piano aggiungono qui sotto gli altri punti. A false il gioco torna esattamente com'era.
const WILD_FAUNA_AD_HOC := true
