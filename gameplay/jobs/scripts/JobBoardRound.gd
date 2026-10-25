class_name JobBoardRound
extends RefCounted

# Giro della lista dei lavori a tappe (2026-10-25, richiesta utente — picco del giro al secondo del cassetto): invece di
# chiedere tutti i fornitori nello stesso fotogramma (4–12 ms), un fornitore per fotogramma (step). Ogni fornitore è
# chiesto una sola volta per giro e le assegnazioni (`assigned`) si contano una volta all'inizio: il lavoro totale è
# quello di prima, solo distribuito.
# La firma della lista (assegnazioni, ordini del cassetto, prese) è presa all'INIZIO del giro: se qualcosa cambia durante
# il giro, la lista finita non combacia con la firma di adesso e la prima domanda la rifà, come oggi dopo un cambiamento.
# Un'istanza per scena (tenuta da GameScene): le Callable dei fornitori non sopravvivono alla scena.

var _providers: Array = []
var _index: int = 0
var _jobs: Array[Dictionary] = []
var _assigned: Dictionary = {}
var _signature: int = 0
var _running: bool = false


func is_running() -> bool:
	return _running


# Nuovo giro sui fornitori `providers` (voci con "collect" e "name"), con le assegnazioni e la firma di adesso.
func start(providers: Array, assigned: Dictionary, signature: int) -> void:
	_providers = providers
	_index = 0
	_jobs = []
	_assigned = assigned
	_signature = signature
	_running = true


# Un fornitore. true quando il giro è finito (risultato in take_result).
# Tempi (JobBoardTimingService): "fornitore:<nome>" come nel giro in un colpo, contati nel fotogramma.
func step() -> bool:
	if not _running:
		return false
	if _index < _providers.size():
		var provider: Dictionary = _providers[_index]
		var timing := JobBoardTimingService.is_enabled()
		var started := JobBoardTimingService.now() if timing else 0
		_jobs.append_array(provider["collect"].call(provider, _assigned))
		if timing:
			JobBoardTimingService.add("fornitore:%s" % String(provider.get("name", "?")), started)
		_index += 1
	return _index >= _providers.size()


# Risultato del giro finito: {"jobs", "assigned", "signature"}. Il giro si chiude.
func take_result() -> Dictionary:
	var result := {"jobs": _jobs, "assigned": _assigned, "signature": _signature}
	cancel()
	return result


# Giro buttato (una lista fatta in un colpo l'ha già sostituito).
func cancel() -> void:
	_providers = []
	_index = 0
	_jobs = []
	_assigned = {}
	_running = false
