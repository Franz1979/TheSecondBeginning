class_name NotificationTypes

# Single source of truth per i tipi di popup di notifica in-game — stesso ruolo di GameTypes.gd/
# HumanTypes.gd per i rispettivi domini, ma per il sistema di notifiche UI (NotificationPopup).
# Solo DEATH per ora (richiesta utente, 2026-09-05, step "sistema minimo di popup"): nessun altro
# case ipotetico aggiunto in anticipo — il sistema (enum + coda + persistenza del flag di
# visibilità) è già strutturato per accoglierne altri quando arriveranno (es. nascite, eventi
# naturali rilevanti), senza dover toccare NotificationPopup stesso.
enum NotificationPopupType {
	DEATH,
	# Effetto nato-morto (2026-09-06) — riusato SIA per una nascita riuscita SIA per un nato-morto
	# (testi diversi, stesso tipo/stile di popup): non serve un terzo valore, il tipo qui distingue
	# la CATEGORIA dell'evento (nascita, in senso lato) per un futuro uso stilistico (icona/colore
	# diverso da DEATH), non l'esito interno alla categoria.
	BIRTH,
}
