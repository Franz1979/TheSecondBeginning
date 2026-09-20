class_name DeathTypes

# Single source of truth per le cause di morte umana — stesso ruolo/stile di NotificationTypes.gd,
# ma per il log eventi grezzo (vedi GameData.death_events, Step 8 del piano mortalità, 2026-09-05).
# OLD_AGE (vedi HumanMortalityIndividualService, mortalità età-dipendente reale) e MURDER (Step 9,
# 2026-09-05: morte immediata forzata da un bottone di debug "Kill" su un individuo selezionato —
# non un vero sistema di omicidio/conflitto, solo il nome di causa più onesto per una morte
# non-naturale forzata a scopo di test) — pensato per crescere ulteriormente quando arriveranno
# starvation/malattie/predazione.
enum DeathCause {
	OLD_AGE,
	MURDER,
	# Effetto morte materna (2026-09-06) — tiro "sopravvivenza madre" fallito al parto (vedi
	# HumanBirthIndividualService._roll_childbirth_survival), completamente slegato dall'esito del
	# tiro sopravvivenza figlio (i due restano indipendenti, come già impostato).
	CHILDBIRTH,
	# STARVATION (morte per fame) e ILLNESS (malattia) (2026-09-19, richiesta utente) - AGGIUNTE IN CODA:
	# il valore numerico e' persistito (death_events[].cause, HumanIndividual.scheduled_death_cause), mai
	# riordinare/inserire in mezzo. STARVATION e' generata da GameTimeService._apply_daily_starvation
	# (body_calories a 0 per STARVATION_DAYS giorni, o INFANT orfano per lo stesso numero di giorni);
	# ILLNESS non e' ancora generata da nessun sistema. Le statistiche (StatisticsPanel itera l'enum) e i
	# popup di morte (chiave tr "death_cause_<nome minuscolo>") le registrano.
	STARVATION,
	ILLNESS,
}
