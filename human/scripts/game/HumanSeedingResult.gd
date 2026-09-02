class_name HumanSeedingResult
extends RefCounted

# Contenitore di ritorno per HumanSeedingService — tre campi tipizzati invece di un Dictionary a
# chiavi stringa, per un call site leggibile (result.individuals invece di
# result["individuals"]), coerente con la preferenza generale del progetto per oggetti tipizzati
# quando la forma e' fissa e nota in anticipo.

var folk: Folk = null
var group: HumanPopulationGroup = null
var individuals: Array[HumanIndividual] = []
