class_name ThinkAction
extends Action

# Terza sottoclasse concreta di Action, seconda con una vera DURATA (dopo Rest, che invece non
# completa mai da sola) — primo passo del futuro Daydream (2026-09-07, richiesta utente). A
# differenza di WalkAction (un bersaglio SPAZIALE, individual.position vs target) e di RestAction
# (nessun completamento, stato implicito), ThinkAction ha un bersaglio TEMPORALE: un accumulatore
# di tempo trascorso (_elapsed sotto, stesso principio di _last_position in WalkAction — stato
# privato dell'istanza, mai su HumanIndividual) confrontato con `duration`.
#
# `duration` arriva GIÀ RISOLTA dal chiamante (base × EraRules.think_duration_multiplier) — questa
# classe non conosce EraRules né Folk, stesso principio "nessuna Action conosce il dominio che la
# orchestra" già seguito da WalkAction/RestAction (che non conoscono HumanIndividualMovementService/
# HumanStaminaIndividualService). Unità = FRAZIONE DI GIORNO DI GIOCO, stessa di `delta` in
# get_stamina_delta (vedi la ricognizione game-clock: delta non è più tempo reale) — quindi
# duration=1.0 significa "un giorno pieno di riflessione continua", coerente con STAMINA_REGEN_PER_
# DAY/STAMINA_DRAIN_PER_MICROCELL già calibrate sulla stessa unità.
#
# Nessun target spaziale (stesso pattern di RestAction — vedi _init sotto): ThinkAction agisce solo
# sull'individuo stesso, in loco.

# Drain di stamina al GIORNO — valore di partenza ARBITRARIO (10.0, richiesta utente) da ricalibrare
# in seguito, come tutti gli altri drain/regen di questo sistema. Scelto in proporzione a Walk/Rest
# già calibrati: camminare drena 50.0 stamina/giorno a pieno ritmo (WalkAction.STAMINA_DRAIN_PER_
# MICROCELL=5.0 × HumanIndividual.move_speed=10.0 microcelle/giorno) e riposare recupera altrettanto
# (RestAction.STAMINA_REGEN_PER_DAY=50.0) — pensare è uno sforzo mentale, non fisico: un quinto del
# drain di una camminata piena (10.0 = 50.0/5) rende il costo reale ma nettamente più leggero di uno
# sforzo fisico, senza azzerare comunque il recupero passivo di un'eventuale Task successiva di Rest.
const STAMINA_DRAIN_PER_DAY: float = 10.0

var duration: float = 0.0

# Tempo trascorso in QUESTO step, in frazioni di giorno di gioco — parte da 0.0 (a differenza di
# WalkAction._last_position, che parte a null perché la primissima chiamata non ha ancora un punto
# di confronto: qui non serve, "quanto tempo è passato" è correttamente 0.0 prima di qualunque
# chiamata, nessun caso speciale per il primo frame).
var _elapsed: float = 0.0


func _init(p_duration: float) -> void:
	duration = p_duration
	target = null


func get_stamina_delta(individual: Variant, delta: float) -> float:
	_elapsed += delta
	return -STAMINA_DRAIN_PER_DAY * delta


func is_complete(individual: Variant) -> bool:
	return _elapsed >= duration


# Lascia un pensiero "in sospeso" sull'individuo quando il ciclo di riflessione si conclude
# (2026-09-07) — vedi Action.on_complete per il contratto generale/perché non è dentro is_complete()
# stessa, e HumanIndividual.pending_thought per cosa succede dopo (nulla, ancora: nessuna
# DepositThoughtAction esiste in questo passo).
func on_complete(individual: Variant) -> void:
	individual.pending_thought = true
