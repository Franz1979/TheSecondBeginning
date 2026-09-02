class_name Folk
extends RefCounted

# Cultura/etnia condivisa — nessun governo (quello sarà PoliticalEntity, non ancora costruita).
# RefCounted, non Resource: a differenza di HumanRules/EraRules (regole statiche, dati di
# bilanciamento caricati da .tres), un Folk è un'entità di PARTITA — esiste dal momento in cui
# viene creato in una sessione di gioco, ha un id progressivo, e andrà salvato/caricato come dato
# di partita quando arriverà la persistenza (mai come .tres) — stesso principio già seguito da
# PopulationGroup/Building lato animale/edifici.
#
# Solo il minimo per ora: nessun era_rules_ref/name_rules ancora, non collegati a nulla in questo
# passo.

var id: int = 0
var name: String = ""
var human_rules_ref: HumanRules = null
