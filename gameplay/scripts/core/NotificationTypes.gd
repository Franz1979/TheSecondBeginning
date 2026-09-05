class_name NotificationTypes

# Single source of truth per i tipi di popup di notifica in-game — stesso ruolo di GameTypes.gd/
# HumanTypes.gd per i rispettivi domini, ma per il sistema di notifiche UI (NotificationPopup).
# Solo DEATH per ora (richiesta utente, 2026-09-05, step "sistema minimo di popup"): nessun altro
# case ipotetico aggiunto in anticipo — il sistema (enum + coda + persistenza del flag di
# visibilità) è già strutturato per accoglierne altri quando arriveranno (es. nascite, eventi
# naturali rilevanti), senza dover toccare NotificationPopup stesso.
enum NotificationPopupType {
	DEATH,
}
