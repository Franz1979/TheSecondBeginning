class_name BuildingTypes

# Single source of truth per gli enum del dominio edifici (2026-09-07, richiesta utente) — stesso
# ruolo/stile di GameTypes.gd/HumanTypes.gd/ExpiredObjectTypes.gd/NotificationTypes.gd per i
# rispettivi domini, ma per ciò che serve a classificare un TIPO di edificio (BuildingRules). Vive
# separato da BuildingRules per lo stesso motivo per cui ExpiredObjectTypes vive separato da
# ExpiredObjectRules — enum condivisi tenuti fuori dalle classi Resource che li usano. Nessun
# `extends` (stesso stile di HumanTypes.gd/ExpiredObjectTypes.gd) — puro contenitore di enum, mai
# istanziato.

# RESIDENTIAL (hut), POLITICAL (pebble_circle), STORAGE (deposit_site, 2026-09-08) — nessun caso
# ipotetico anticipato, stesso principio già seguito da ExpiredObjectType/NotificationPopupType:
# altre categorie si aggiungono qui quando serviranno davvero. Non ancora consultato da BuildBar/
# altra UI in questo passo — solo il dato, pronto per i futuri sottomenu per categoria (quando i
# tipi di edificio saranno troppi per una sola riga, confermato con l'utente).
enum Category {
	RESIDENTIAL,
	POLITICAL,
	STORAGE,
}
