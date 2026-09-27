class_name VisitorTypes
extends RefCounted

# Enum dei gruppi di visitatori (2026-09-27, richiesta utente — infrastruttura dei visitatori). Vedi
# VisitorParty/VisitorService.

# Tipo del gruppo. MIGRANTS (2026-09-27, ex TEST, stesso valore 0: i salvataggi con il vecchio gruppo di prova
# si ricaricano come migranti) è chi chiede di unirsi al villaggio, es. l'evento family_arrival; mercanti e
# predoni arriveranno come valori nuovi, con lo stesso meccanismo.
enum PartyType {
	MIGRANTS,
}

# Fase dell'episodio: in arrivo (cammina dal bordo verso il centro del villaggio), in attesa di decisione
# (fermo vicino al centro), in partenza (cammina verso il bordo e sparisce).
enum Phase {
	ARRIVING,
	AWAITING_DECISION,
	LEAVING,
}

# Ruolo del membro nel gruppo (solo descrittivo per ora).
enum MemberRole {
	ADULT,
	CHILD,
}
