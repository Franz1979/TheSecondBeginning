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
	# Sblocco Idea (2026-09-07, richiesta utente) — riusa lo STESSO NotificationPopup/gate
	# UserOptions.show_notification_popups di morte/nascita (vedi GameScene._on_idea_completed),
	# non un sistema di avvisi separato: si disattiva insieme agli altri da Opzioni.
	IDEA_COMPLETED,
	# Decadimento risorsa (2026-09-09, richiesta utente, Step 3 decadimento) — una risorsa
	# trasportata/stoccata ha raggiunto decay_fraction >= 1.0 ed è stata rimossa (zaino individuo o
	# storage edificio, vedi ResourceDecayService) — stesso gate/stesso meccanismo di morte/nascita/
	# idea, riusato per il quarto caso d'uso invece di un sistema di avvisi a parte.
	RESOURCE_DECAYED,
	# Cantiere bloccato per mancanza di materiale da costruzione (2026-09-14, richiesta utente) —
	# PRIMO tipo con uno STILE VISIVO DIVERSO dagli altri (sfondo giallo/triangolo invece del
	# pannello scuro di default — vedi NotificationPopup._show_next), non solo una categoria per un
	# futuro uso stilistico mai arrivato come per BIRTH sopra: un avviso di blocco deve leggersi
	# come "attenzione", non come un evento normale della simulazione.
	MATERIAL_NEEDED,
	# Un individuo ha finito le provviste e comincia a consumare la riserva corporea (2026-09-19, richiesta
	# utente) - stesso stile "alert" giallo di MATERIAL_NEEDED (vedi NotificationPopup._show_next).
	BODY_RESERVE_IN_USE,
	# Task non partita per mancanza di attrezzi (2026-09-25, richiesta utente — ToolGateService):
	# attrezzo assente, oppure cintura piena. Stesso stile "alert" giallo di MATERIAL_NEEDED.
	TOOL_REQUIRED,
	# Comando rifiutato perché l'individuo non è idoneo (2026-09-26, richiesta utente): troppo giovane,
	# fascia d'età non ammessa, stamina insufficiente — vedi HumanIndividual.get_assign_rejection_reason.
	# Aggiunto IN CODA. Stesso stile "alert" giallo di TOOL_REQUIRED.
	TASK_REJECTED,
}
