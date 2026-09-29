class_name DiscoveryTypes

# Enum del sistema "Scoperte" (2026-09-28, richiesta utente) — stesso ruolo di NotificationTypes/GameTypes per il
# proprio dominio. Valori usati come interi nei .tres di gameplay/discoveries/data/: aggiungere SOLO IN CODA.

# Milestone che può far scattare una scoperta (un momento che sblocca qualcosa: idea completata, primo edificio di un
# tipo, in futuro soglie di popolazione...). I random event NON sono mai trigger di scoperte. Dati passati a
# DiscoveryHintService.find_unseen per tipo:
#   IDEA_COMPLETED     -> {"idea_id": String}
#   BUILDING_COMPLETED -> {"building": Building}
enum TriggerType {
	IDEA_COMPLETED,
	BUILDING_COMPLETED,
}

# Azione eseguita da GameScene dopo l'OK del DiscoveryPopup (o subito, se non c'è nulla da mostrare).
enum CloseAction {
	NONE,
	OPEN_TECH_TREE,
}
