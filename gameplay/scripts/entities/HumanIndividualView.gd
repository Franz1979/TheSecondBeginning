class_name HumanIndividualView
extends Node2D

# Resa visiva PLACEHOLDER dell'individuo controllabile — sarà sostituita in blocco al passaggio
# al 3D senza toccare HumanIndividual (legge solo il suo stato via setup(), non lo modifica mai).
# Forme semplici disegnate immediate-mode, stesso approccio minimale già usato altrove per i
# placeholder di questo modulo — deliberatamente "usa e getta": niente mesh/texture/AnimationPlayer,
# solo geometria via _draw() e una variabile di fase (vedi walk_phase sotto).

const CELL_SIZE: int = 10 # stesso fattore pixel/microcella di MicroCellRenderer/AnimalGroupRenderer
const SELECTION_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const SELECTION_WIDTH: float = 0.6

# Step 2 (2026-09-04) — forma base statica, sostituisce il cerchio unico dello Step 0/1: un'ellisse
# per il busto (più larga lungo le "spalle", asse Y locale, che in profondità, asse X locale —
# coerente con una sagoma umana vista dall'alto) più un cerchio più piccolo per la testa, spostato
# in avanti lungo +X locale (la direzione di marcia — vedi `individual.facing_direction`/`rotation` in _process,
# confermato "rivolto in avanti" con l'utente). Entrambe disegnate nello spazio LOCALE non ruotato
# di questo nodo: `rotation` (Step 1) applica l'orientamento in compositing, queste forme non
# calcolano mai un angolo proprio.
#
# Due colori distinti (richiesta utente, 2026-09-04 — prima un unico giallo, la testa non si
# leggeva come tale) anticipano qui la sostanza del vecchio "Step 6 — palette pelle" (rimasto solo
# per l'eventuale ritocco fine, non più per il cambio di colore in sé): SKIN_COLOR sul busto,
# HAIR_COLOR sulla testa — nessun terzo colore per vestiti/dettagli, resta comunque un placeholder
# a due tinte piatte.
const SKIN_COLOR := Color(0.82, 0.62, 0.45, 1.0)

# Step 3 (2026-09-04, richiesta utente) — hair_color/clothing_color non sono più un unico colore
# fisso: HumanIndividual porta un tratto casuale persistito (enum, vedi HumanTypes.HairColor/
# ClothingColor), QUESTA classe resta l'unica responsabile della mappatura enum->Color vera e
# propria (l'aspetto — HumanTypes resta agnostico su come si disegna). Dictionary invece di un
# match/if-elif: si estende da sola se in futuro l'enum guadagna altre voci, basta aggiungere una
# riga qui E in HumanTypes, mai toccare _draw().
#
# RIVISTI (2026-09-04, dopo il primo giro di test): BLONDE più saturo/dorato (era troppo simile a
# un biondo spento); HairColor.BROWN e ClothingColor.DARK_BROWN erano quasi identici — differenziati
# spostando i capelli verso un castano più caldo/rossiccio e i vestiti verso un marrone più freddo/
# grigiastro (pelle conciata vs capello, tonalità diverse per costruzione, non solo per caso).
const HAIR_COLOR_BY_TRAIT := {
	HumanTypes.HairColor.BLONDE: Color(0.88, 0.72, 0.24, 1.0),
	HumanTypes.HairColor.BROWN: Color(0.4, 0.19, 0.1, 1.0),
	HumanTypes.HairColor.BLACK: Color(0.08, 0.07, 0.06, 1.0),
}

# Step 4 (2026-09-04) — capelli grigi per gli anziani: override SOLO in fase di disegno (vedi
# _draw()), NON scrive mai individual.hair_color — il tratto vero resta quello pescato/ereditato
# alla nascita (vedi HumanIndividual.assign_hair_color), semplicemente "coperto" visivamente da
# vecchio, esattamente come i vestiti non diventano mai il vero colore dei capelli di qualcuno.
# DELIBERATAMENTE più chiaro/neutro del grigio dei vestiti (ClothingColor.GRAY sotto, più scuro/
# freddo) — richiesta esplicita dell'utente quando ha aggiunto quel colore: i due grigi non
# devono confondersi.
const GRAY_HAIR_COLOR := Color(0.78, 0.77, 0.74, 1.0)

# GRAY (2026-09-04, richiesta utente) — DELIBERATAMENTE più scuro/freddo del GRAY_HAIR_COLOR sopra
# (Step 4, capelli anziani): i due grigi non devono confondersi.
const CLOTHING_COLOR_BY_TRAIT := {
	HumanTypes.ClothingColor.TAN: Color(0.55, 0.36, 0.2, 1.0),
	HumanTypes.ClothingColor.DARK_BROWN: Color(0.28, 0.23, 0.19, 1.0),
	HumanTypes.ClothingColor.RUST: Color(0.56, 0.26, 0.13, 1.0),
	HumanTypes.ClothingColor.OLIVE: Color(0.42, 0.4, 0.23, 1.0),
	HumanTypes.ClothingColor.GRAY: Color(0.4, 0.41, 0.44, 1.0),
}

# Capelli lunghi (2026-09-04, richiesta utente) — SOLO per individual.sex == FEMALE (vedi
# _draw()): stesso HAIR_COLOR della testa. Disegnata DOPO il busto ma PRIMA delle spalle in
# _draw(): sopra il colore del busto (visibile), ma sotto ai cerchi-spalle/braccia (che restano
# sempre in vista, non coperti dai capelli) e sotto la testa (che li "ancora" visivamente).
#
# RIVISTO (2026-09-04, dopo il primo giro di test): i vecchi valori (0.7/0.9, più larga che
# profonda) si leggevano come una "cofana" attaccata alla testa, non come capelli lisci — richiesta
# esplicita: una striscia LARGA QUANTO LA TESTA (HAIR_LONG_RADIUS_SIDE = HEAD_RADIUS, non più
# arbitraria) che nella parte dietro copre il busto, quindi ELONGATA lungo X (profondità) invece
# che lungo Y (lati) — rapporto invertito rispetto a prima.
#
# Provato anche un taglio netto sulla punta (semicerchio + lato piatto invece di un'ellisse
# piena) — richiesta utente 2026-09-04, poi SCARTATA ("così non vanno bene", tornato a
# _draw_ellipse) — non ripetere quel tentativo senza una richiesta esplicita.
const HAIR_LONG_RADIUS_FORWARD: float = 0.85
const HAIR_LONG_RADIUS_SIDE: float = HEAD_RADIUS
const HAIR_LONG_OFFSET_FORWARD: float = -0.55

# Ridotti da 1.0/1.3 (richiesta utente, 2026-09-04: busto troppo grande, "stringere appena appena"
# per sembrare più sottile) — stesso rapporto forward/side di prima (~1:1.3), solo scalato un po'
# più in basso.
const TORSO_RADIUS_FORWARD: float = 0.9 # lungo X locale (profondità, verso la direzione di marcia)
const TORSO_RADIUS_SIDE: float = 1.15 # lungo Y locale (spalle)
# Centrata sul busto, nessun offset (richiesta utente, 2026-09-04 — dopo aver ridotto lo sporgere
# in avanti a 0.3, correzione finale: vista dall'alto la testa sta sopra il busto, non davanti —
# rimosso il campo HEAD_OFFSET_FORWARD, non più un offset da tarare). Essendo HEAD_RADIUS < sia
# TORSO_RADIUS_FORWARD che TORSO_RADIUS_SIDE, la testa ricade sempre per intero dentro la sagoma
# del busto, mai a sporgere.
const HEAD_RADIUS: float = 0.6

# Faccia + naso (2026-09-04, richiesta utente): unico segnale di direzione visibile ANCHE da fermo
# — a differenza di gambe/spalle, che a riposo restano rispettivamente nascoste o centrate, un
# piccolo cerchio color pelle spostato in avanti sulla testa (la parte "non coperta dai capelli",
# vedi HAIR_COLOR sopra) più uno anche più piccolo ancora più avanti (il naso) restano SEMPRE
# visibili nella stessa posizione relativa, ruotando col resto del corpo (rotation, Step 1) — così
# capisci dove sta il davanti anche quando il personaggio è completamente fermo. Disegnati DOPO la
# testa (vedi _draw()), stesso SKIN_COLOR del busto (è pelle, non capelli).
# FACE_RADIUS tornata a 0.3 (0.22 la faceva leggere come un cerchiolino a sé invece che come una
# porzione di faccia sulla testa, richiesta utente 2026-09-04).
#
# FACE_OFFSET_FORWARD (2026-09-04): non più un cerchio libero che poteva sporgere dalla testa —
# richiesta utente, "disegnalo come una fettina del cerchio testa, come se intersecassi due O":
# vedi _draw_circle_lens sotto, disegna SOLO l'area di sovrapposizione tra il cerchio testa e
# questo cerchio faccia, mai oltre il bordo della testa per costruzione geometrica (risolve anche
# "sporge troppo" della richiesta precedente, non serve più tarare l'offset per quello).
# FACE_RADIUS ridotto da 0.3 a 0.24 (richiesta utente, 2026-09-04: lente un po' troppo larga) —
# il cerchio faccia usato per l'intersezione (vedi sopra), non un raggio disegnato direttamente:
# più piccolo qui restringe la lente risultante.
const FACE_RADIUS: float = 0.24
const FACE_OFFSET_FORWARD: float = 0.42
const NOSE_RADIUS: float = 0.09 # ridotto da 0.12 (richiesta utente, 2026-09-04: naso un po' troppo grande)
# Ridotto insieme a FACE_OFFSET_FORWARD sopra (da 0.8 a 0.68): col nuovo bordo faccia a 0.72
# (0.42+0.3), deve restare oltre quel bordo per non finire interamente dentro la faccia (stesso
# colore, invisibile) — 0.68+NOSE_RADIUS=0.8 sporge di ~0.08 oltre 0.72, ancora un accenno visibile.
const NOSE_OFFSET_FORWARD: float = 0.68

# Step 3 (2026-09-04) — gambe, due ellissi strette (riuso di _draw_ellipse, mai un rettangolo:
# coerente con testa/busto, nessuna forma ad angoli retti in questo file).
#
# RIVISTO allo Step 4 (2026-09-04, dopo il primo giro di test con l'utente): LEG_BASE_FORWARD ora
# a 0 — CENTRATA sul busto, non più spostata verso il "dietro". Col vecchio -0.4 l'intero raggio
# di oscillazione restava sul lato posteriore (mai oltre X=-0.1), quindi UNA sola gamba per volta
# poteva mai sporgere (sempre quella indietro, mai quella avanti) e a riposo (fase congelata a un
# valore qualunque) c'era sempre una gamba visibile dietro — nessuno dei due comportamenti voluti.
# Con base 0: a riposo (offset 0) entrambe le gambe ricadono per intero dentro il busto (0±
# LEG_RADIUS_FORWARD=0.5, ben dentro TORSO_RADIUS_FORWARD=0.9) — invisibili, come richiesto — e
# l'oscillazione (vedi LEG_SWING_*_AMPLITUDE sotto) può sporgere sia in avanti che indietro dal
# centro, non solo verso un lato.
const LEG_RADIUS_FORWARD: float = 0.5 # lunghezza gamba, lungo X locale
const LEG_RADIUS_SIDE: float = 0.22 # spessore gamba, lungo Y locale
const LEG_SIDE_OFFSET: float = 0.5 # distanza laterale dal centro, lungo Y locale (una per lato)
const LEG_BASE_FORWARD: float = 0.0 # posizione di riposo lungo X locale — centrata, nascosta sotto il busto

# Step 4 (2026-09-04) — animazione delle gambe: un singolo accumulatore di fase (walk_phase sotto)
# invece di un vero walk-cycle con interpolazioni (deliberatamente escluso, richiesta utente in
# apertura di questo lavoro — "usa e getta", sarà buttato via col passaggio al 3D). WALK_PHASE_
# SPEED è radianti/secondo di avanzamento fase SOLO quando is_moving (vedi _process) — indipendente
# da HumanIndividual.move_speed (nessun accoppiamento, richiesta esplicita di conferma
# dell'utente): 6.0 iniziale, sceso a 2.5 (troppo veloce per leggere il movimento), risalito a 4.0
# poi a 8.0 (richiesta utente, 2026-09-04 — dopo aver rallentato anche move_speed separatamente,
# il ritmo delle gambe poteva permettersi di essere più vivace).
const WALK_PHASE_SPEED: float = 8.0

# Ampiezza ASIMMETRICA avanti/indietro (richiesta utente, 2026-09-04: "quella davanti ha anche un
# po' più di offset di quella dietro", coerente con un passo umano reale — il piede che avanza si
# stacca più lontano dal centro di quanto quello che resta indietro si trascini). Con
# LEG_RADIUS_FORWARD=0.5 e TORSO_RADIUS_FORWARD=0.9, un'ampiezza deve superare 0.4 per far
# sporgere la punta della gamba oltre il bordo del busto da quel lato — FORWARD=0.65 (sporge
# ~0.25) e BACKWARD=0.5 (sporge ~0.1) soddisfano entrambe questa soglia, con la prima
# visibilmente più marcata della seconda.
const LEG_SWING_FORWARD_AMPLITUDE: float = 0.65
const LEG_SWING_BACKWARD_AMPLITUDE: float = 0.5

# Step 5, RIVISTO (2026-09-04, dopo il primo giro di test) — NON più due ellissi nascoste come le
# gambe (col vecchio ARM_SIDE_OFFSET=0.8 restavano completamente dentro il busto a riposo, mai
# viste: richiesta esplicita dell'utente, "alle estremità dell'ellisse dovrei vedere due cerchi,
# le spalle"). Ora un CERCHIO per spalla (niente da orientare come un'ellisse — SHOULDER_RADIUS,
# non due assi separati), piazzato esattamente sul bordo spalle del busto (SHOULDER_SIDE_OFFSET =
# TORSO_RADIUS_SIDE) e disegnato DOPO il busto in _draw() (come la testa, non prima come le
# gambe) — SEMPRE visibile come rigonfiamento sul bordo, mai nascosto. L'oscillazione
# (ARM_SWING_*_AMPLITUDE, invariate nel valore) sposta solo la posizione X del cerchio durante il
# passo — CONTROFASE rispetto alla gamba dello stesso lato (spalla sinistra con -phase, come la
# gamba DESTRA; spalla destra con +phase, come la gamba SINISTRA — vedi _draw()), per imitare
# l'oscillazione incrociata braccio/gamba di un passo umano reale — ma il cerchio stesso non
# sparisce mai, solo scivola avanti/indietro.
const SHOULDER_RADIUS: float = 0.28 # ridotto da 0.35 (richiesta utente, 2026-09-04: un po' troppo grandi)
const SHOULDER_SIDE_OFFSET: float = TORSO_RADIUS_SIDE
const ARM_SWING_FORWARD_AMPLITUDE: float = 0.4
const ARM_SWING_BACKWARD_AMPLITUDE: float = 0.3

var individual: HumanIndividual

# Riferimenti per il ridimensionamento per età/sesso (richiesta utente, 2026-09-04) — passati da
# GameScene a setup() sotto, mai risolti da questa classe (stesso principio già seguito per
# fog_of_war_memory in FogOfWarRenderer: le dipendenze arrivano dal chiamante, mai cercate/
# istanziate qui dentro). human_rules è HumanRules.size_multiplier_by_age/by_sex (già esistenti
# nel .tres, "Nessuna logica li legge ancora" — questo è il primo consumatore reale), game_data
# serve solo per l'anno corrente (per calcolare l'età via HumanCalculator.get_age_band, che cambia
# nel tempo — non un valore congelabile a setup() come fog_of_war_memory). Questi sono dati
# FISIOLOGICI reali (HumanRules li classifica "Physical", non rendering), a differenza di
# walk_phase sotto — l'unico motivo per cui il ricalcolo vive comunque qui in _process()
# e non su HumanIndividual è evitare di dover gestire un secondo meccanismo di invalidazione/
# cache per un valore che cambia solo su base annuale: a ≤20 individui contemporanei (vedi
# ricognizione), ricalcolarlo ogni frame è un costo trascurabile, non vale la complessità di una
# cache dedicata.
var human_rules: HumanRules
var game_data: GameData

# Fascia d'età corrente (2026-09-04) — calcolata in _process() insieme alla scala (stesso
# HumanCalculator.get_age_band, stesso costo trascurabile già discusso lì), ma tenuta anche come
# campo perché _draw() (Step 4, capelli grigi per gli anziani) ne ha bisogno per decidere il
# colore, e perché l'early-out sotto deve sapere quando cambia (un individuo che diventa OLD deve
# ridisegnare i capelli, anche se walk_phase/is_selected non sono cambiati in quel frame).
var _current_age_band: HumanTypes.AgeBand = HumanTypes.AgeBand.FERTILE_ADULT

# Step 4 (2026-09-04): fase del ciclo passo — resta qui (mai su HumanIndividual), è pura
# animazione senza significato di simulazione, a differenza di HumanIndividual.facing_direction
# (vedi lì, spostato da questo file il 2026-09-04 per poterlo salvare). Incrementata SOLO quando
# is_moving (vedi _process).
#
# RIVISTO (2026-09-04, dopo il primo giro di test): AZZERATA quando l'individuo si ferma, non più
# congelata — il principio originale ("congelare per evitare scatti") partiva da un'assunzione mai
# verificata; il test reale ha mostrato l'effetto opposto a quello voluto (una gamba restava
# visibile dietro anche da fermo, richiesta esplicita dell'utente: "nessuna gamba si vede" a
# riposo). Con LEG_BASE_FORWARD ora a 0 (vedi sopra), fase 0 = entrambe le gambe perfettamente
# nascoste sotto il busto, quindi l'azzeramento produce esattamente il risultato voluto.
var walk_phase: float = 0.0

# Early-out (richiesta utente, 2026-09-04, trovato misurando ~50ms/sec PERMANENTI con
# SHOW_HUMAN_VIEW_TIMING_LOGS, anche da fermo): questo nodo chiamava queue_redraw() SENZA
# CONDIZIONI ad ogni _process(), a differenza di FogOfWarRenderer (che l'early-out ce l'aveva fin
# dall'inizio). walk_phase/is_selected/age_band sono le cose che cambiano il CONTENUTO di _draw()
# (posizione delle gambe, presenza dell'anello, colore capelli da vecchio — Step 4) — vedi
# _process() sotto per perché position/rotation/scale non vanno tracciate qui. _has_drawn_once
# sentinel per forzare il primissimo _draw() (stesso principio già usato altrove nel progetto, es.
# FogOfWarRenderer._last_drawn_positions).
var _has_drawn_once: bool = false
var _last_drawn_walk_phase: float = 0.0
var _last_drawn_is_selected: bool = false
var _last_drawn_age_band: HumanTypes.AgeBand = HumanTypes.AgeBand.FERTILE_ADULT

# Diagnostica timing (richiesta utente, 2026-09-04 — vedi DebugLogging.SHOW_HUMAN_VIEW_TIMING_LOGS
# per il perché) — `static var` (Godot 4, condivisa da TUTTE le istanze di questa classe, stesso
# principio già usato da FogOfWarCalculator._rules_cache): fino a 20 HumanIndividualView vive
# contemporaneamente (vedi ricognizione), ciascuna col proprio _process()/_draw() ogni frame — un
# accumulatore per-istanza produrrebbe fino a 20 righe di log al secondo, troppo rumoroso; questi
# sommano il costo di TUTTE le istanze in una finestra di un secondo, poi un'unica riga
# riepilogativa (stesso principio già in uso per [FOW REDRAW COUNT]). _window_start_msec=0 come
# sentinel "finestra non ancora iniziata" (il primo giro la apre soltanto, non stampa nulla di
# parziale).
static var _process_usec_accum: int = 0
static var _draw_usec_accum: int = 0
static var _window_start_msec: int = 0
static var _window_view_count: int = 0


func setup(p_individual: HumanIndividual, p_game_data: GameData, p_human_rules: HumanRules) -> void:
	individual = p_individual
	game_data = p_game_data
	human_rules = p_human_rules


func _process(delta: float) -> void:
	if individual == null:
		return
	var _process_start_usec := Time.get_ticks_usec()
	position = individual.position * CELL_SIZE
	# Ridimensionamento per età/sesso (vedi campi human_rules/game_data sopra) — età/sesso combinati
	# per MOLTIPLICAZIONE (stesso principio dichiarato in HumanRules.size_multiplier_by_age),
	# applicato uniformemente su entrambi gli assi via `scale` del nodo: nessuna forma in _draw()
	# deve sapere di questo, esattamente come nessuna sa di `rotation`. size_variance (spread
	# casuale per-individuo, in HumanRules) deliberatamente NON applicato qui — richiederebbe un
	# valore stabile per individuo (mai ricalcolato a caso ogni frame, altrimenti tremola), quindi
	# uno stato persistito che oggi non esiste; fuori scope per questa richiesta (solo "bambini più
	# piccoli", non varianza individuale).
	if human_rules != null and game_data != null:
		var age := float(game_data.year - individual.birth_year_virtual)
		_current_age_band = HumanCalculator.get_age_band(human_rules, individual.sex, age)
		var age_multiplier: float = human_rules.size_multiplier_by_age[_current_age_band]
		var sex_multiplier: float = human_rules.size_multiplier_by_sex[individual.sex]
		scale = Vector2.ONE * age_multiplier * sex_multiplier
	if individual.is_moving:
		walk_phase += delta * WALK_PHASE_SPEED
	else:
		walk_phase = 0.0
	# facing_direction (2026-09-04): non più calcolata/congelata qui — HumanIndividualMovementService.
	# advance_movement è ora l'unico scrittore (stesso principio "chi muove position possiede anche
	# la direzione", vedi HumanIndividual.gd), questa view si limita a leggerla.
	rotation = individual.facing_direction.angle()
	# position/rotation/scale appena aggiornate sopra sono proprietà di TRASFORMAZIONE del nodo:
	# Godot le riapplica da sé ogni frame ricompositando le istruzioni di disegno già cachate
	# dall'ultimo _draw() reale — muovere/ruotare/scalare non richiede mai queue_redraw(), solo
	# cambiare COSA viene disegnato lo richiede (vedi campi _last_drawn_*/_has_drawn_once sopra per
	# il perché di questo confronto e il costo ~50ms/sec permanente che risolve).
	var needs_redraw := not _has_drawn_once \
		or walk_phase != _last_drawn_walk_phase \
		or individual.is_selected != _last_drawn_is_selected \
		or _current_age_band != _last_drawn_age_band
	_process_usec_accum += Time.get_ticks_usec() - _process_start_usec
	if needs_redraw:
		_last_drawn_walk_phase = walk_phase
		_last_drawn_is_selected = individual.is_selected
		_last_drawn_age_band = _current_age_band
		_has_drawn_once = true
		queue_redraw()
	_maybe_print_timing_window()


# Stampa+reset UNA VOLTA per finestra di un secondo (vedi accumulatori static sopra) — chiamata da
# ogni istanza a fine _process(), ma solo la PRIMA a osservare la finestra scaduta stampa davvero
# (le altre trovano _window_start_msec già riportato al valore corrente e fanno subito ritorno):
# stesso principio del contatore [FOW REDRAW COUNT], qui esteso a N istanze condivise invece di
# una sola. _draw_usec_accum di QUESTO stesso frame potrebbe non essere ancora incluso quando la
# finestra scade a metà frame (il _draw() del motore di rendering arriva dopo tutti i _process()) —
# errore di al più un frame su una finestra di un secondo, irrilevante per una diagnostica.
static func _maybe_print_timing_window() -> void:
	if not DebugLogging.SHOW_HUMAN_VIEW_TIMING_LOGS:
		return
	var now_msec := Time.get_ticks_msec()
	if _window_start_msec == 0:
		_window_start_msec = now_msec
		return
	if now_msec - _window_start_msec < 1000:
		return
	print("[HUMAN VIEW TIMING] process=%.2fms draw=%.2fms totale=%.2fms su %d redraw/sec" % [
		_process_usec_accum / 1000.0, _draw_usec_accum / 1000.0,
		(_process_usec_accum + _draw_usec_accum) / 1000.0, _window_view_count
	])
	_process_usec_accum = 0
	_draw_usec_accum = 0
	_window_view_count = 0
	_window_start_msec = now_msec


func _draw() -> void:
	if individual == null:
		return
	var _draw_start_usec := Time.get_ticks_usec()
	# Contatore redraw REALI (vedi _window_view_count sopra) — incrementato qui, non più in
	# _process() (che gira sempre, con o senza redraw): da quando esiste l'early-out sopra, questo
	# è il numero che riflette davvero il lavoro fatto, non i tick passati.
	_window_view_count += 1
	# Risolti UNA volta per redraw (non per ogni chiamata di disegno) — hair_color/clothing_color
	# sono fissi per tutta la vita dell'individuo (vedi HumanIndividual.assign_hair_color/
	# assign_random_clothing), quindi il tratto vero non serve tracciarlo nell'early-out di
	# _process(): il primissimo redraw forzato lo legge già giusto e non cambia mai più. .get() con
	# fallback a BROWN/TAN solo per robustezza (un valore fuori enum non dovrebbe mai capitare, ma
	# non deve rompere il disegno).
	var hair_color: Color = HAIR_COLOR_BY_TRAIT.get(individual.hair_color, HAIR_COLOR_BY_TRAIT[HumanTypes.HairColor.BROWN])
	var clothing_color: Color = CLOTHING_COLOR_BY_TRAIT.get(individual.clothing_color, CLOTHING_COLOR_BY_TRAIT[HumanTypes.ClothingColor.TAN])
	# Step 4 — capelli grigi per gli anziani: override SOLO qui (il colore disegnato), MAI
	# individual.hair_color (vedi GRAY_HAIR_COLOR sopra per il perché). _current_age_band È
	# tracciato nell'early-out (vedi _last_drawn_age_band), quindi il cambio a OLD forza comunque
	# un redraw anche se nient'altro è cambiato in quel frame.
	if _current_age_band == HumanTypes.AgeBand.OLD:
		hair_color = GRAY_HAIR_COLOR
	# Gambe PRIMA del busto nell'ordine di disegno ("sotto", richiesta utente) — a riposo
	# (walk_phase=0) restano per intero coperte dal busto disegnato subito dopo; durante il passo
	# la punta di volta in volta "in avanti" sporge di più di quella "indietro" (vedi
	# LEG_SWING_*_AMPLITUDE sopra), sempre in controfase tra loro (sinistra +phase, destra -phase).
	var phase := sin(walk_phase)
	_draw_ellipse(Vector2(LEG_BASE_FORWARD + _limb_swing_offset(phase, LEG_SWING_FORWARD_AMPLITUDE, LEG_SWING_BACKWARD_AMPLITUDE), -LEG_SIDE_OFFSET), LEG_RADIUS_FORWARD, LEG_RADIUS_SIDE, SKIN_COLOR)
	_draw_ellipse(Vector2(LEG_BASE_FORWARD + _limb_swing_offset(-phase, LEG_SWING_FORWARD_AMPLITUDE, LEG_SWING_BACKWARD_AMPLITUDE), LEG_SIDE_OFFSET), LEG_RADIUS_FORWARD, LEG_RADIUS_SIDE, SKIN_COLOR)
	_draw_ellipse(Vector2.ZERO, TORSO_RADIUS_FORWARD, TORSO_RADIUS_SIDE, clothing_color)
	# Capelli lunghi DOPO il busto ma PRIMA delle spalle/testa (vedi HAIR_LONG_* sopra) — SOLO
	# femmine, gli uomini restano coperti solo dalla testa come prima.
	if individual.sex == HumanTypes.Sex.FEMALE:
		_draw_ellipse(Vector2(HAIR_LONG_OFFSET_FORWARD, 0.0), HAIR_LONG_RADIUS_FORWARD, HAIR_LONG_RADIUS_SIDE, hair_color)
	# Spalle DOPO il busto (come la testa sotto) — SEMPRE visibili come rigonfiamento sul bordo,
	# mai nascoste (vedi SHOULDER_RADIUS/SHOULDER_SIDE_OFFSET sopra): solo la posizione X scivola
	# avanti/indietro durante il passo, il cerchio stesso non sparisce mai. Controfase rispetto
	# alla gamba dello STESSO lato (sinistra -phase come la gamba destra, destra +phase come la
	# gamba sinistra) — vedi il commento sopra per il perché.
	#
	# clothing_color (2026-09-04, richiesta utente: "prova a colorare anche le braccia") — non più
	# SKIN_COLOR: a differenza delle gambe (sempre nude), qui proviamo la manica lunga anche sulle
	# braccia, non solo sul busto.
	draw_circle(Vector2(_limb_swing_offset(-phase, ARM_SWING_FORWARD_AMPLITUDE, ARM_SWING_BACKWARD_AMPLITUDE), -SHOULDER_SIDE_OFFSET), SHOULDER_RADIUS, clothing_color)
	draw_circle(Vector2(_limb_swing_offset(phase, ARM_SWING_FORWARD_AMPLITUDE, ARM_SWING_BACKWARD_AMPLITUDE), SHOULDER_SIDE_OFFSET), SHOULDER_RADIUS, clothing_color)
	# Testa DOPO tutto il resto nell'ordine di disegno — centrata (vedi HEAD_RADIUS sopra), quindi
	# sempre in cima, mai coperta.
	draw_circle(Vector2.ZERO, HEAD_RADIUS, hair_color)
	# Faccia + naso DOPO la testa (vedi FACE_*/NOSE_* sopra) — unico segnale di direzione visibile
	# anche da fermo, sempre nella stessa posizione locale (+X), ruota col resto via `rotation`.
	# Faccia = lente (intersezione dei due cerchi, vedi _draw_circle_lens sotto), mai un cerchio
	# libero: resta sempre dentro il bordo della testa per costruzione. Naso invece resta un
	# cerchio libero (deve sporgere un poco, è una protuberanza vera, non una porzione di viso).
	_draw_circle_lens(Vector2.ZERO, HEAD_RADIUS, Vector2(FACE_OFFSET_FORWARD, 0.0), FACE_RADIUS, SKIN_COLOR)
	draw_circle(Vector2(NOSE_OFFSET_FORWARD, 0.0), NOSE_RADIUS, SKIN_COLOR)
	if individual.is_selected:
		# Testa centrata e più piccola di entrambi i raggi del busto (vedi HEAD_RADIUS sopra): non
		# sporge mai. Gambe e braccia invece sì, e ora oscillano — margine generoso (usa la maggiore
		# tra le ampiezze in avanti di gambe/braccia, aggiunta al vecchio TORSO_RADIUS_SIDE + 0.3)
		# invece di un calcolo geometrico esatto sulla punta più lontana, coerente con la natura
		# "usa e getta" di questo indicatore puramente cosmetico (l'hit-test vero,
		# HumanIndividualSelectorController.SELECT_RADIUS_MICROCELLS, non dipende in alcun modo da
		# questo raggio). LEG_SWING_FORWARD_AMPLITUDE resta la maggiore delle due (0.65 > 0.4 di
		# ARM_SWING_FORWARD_AMPLITUDE) coi valori attuali — se in futuro le braccia diventassero più
		# ampie delle gambe, va ricontrollato.
		var selection_radius := TORSO_RADIUS_SIDE + 0.3 + LEG_SWING_FORWARD_AMPLITUDE
		draw_arc(Vector2.ZERO, selection_radius, 0, TAU, 24, SELECTION_COLOR, SELECTION_WIDTH)
	_draw_usec_accum += Time.get_ticks_usec() - _draw_start_usec


# Ampiezza di oscillazione di UN arto (gamba O braccio, vedi _draw()) dato il suo valore di fase
# con segno — ASIMMETRICA: verso l'avanti (fase >= 0) usa `forward_amplitude`, verso il dietro
# (fase < 0) usa `backward_amplitude` (minore) — vedi i commenti su LEG_SWING_*/ARM_SWING_* per il
# perché. Generica (non più gamba-specifica, vedi Step 5) proprio per essere condivisa da entrambe
# le coppie di arti con le rispettive ampiezze. Piccola discontinuità di derivata nello
# zero-crossing (non un vero seno, due seni scalati diversi cuciti insieme): impercettibile a
# queste ampiezze/velocità, non vale la complessità di una transizione morbida per un placeholder
# "usa e getta".
func _limb_swing_offset(signed_phase: float, forward_amplitude: float, backward_amplitude: float) -> float:
	if signed_phase >= 0.0:
		return signed_phase * forward_amplitude
	return signed_phase * backward_amplitude


# Ellisse piena come poligono a ventaglio (draw_circle non supporta assi diversi) — segments basso
# apposta (12): a raggi ~1px non serve più risoluzione, e sono fino a 20 individui × 5 forme
# (busto + 2 gambe + 2 braccia) a frame (vedi ricognizione: SMALL_GROUP=10 di default, BIG_GROUP=20
# il caso peggiore oggi). Riutilizzata per busto/gambe/braccia, non solo per il busto.
const ELLIPSE_SEGMENTS: int = 12

func _draw_ellipse(center: Vector2, radius_x: float, radius_y: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(ELLIPSE_SEGMENTS):
		var angle := (float(i) / float(ELLIPSE_SEGMENTS)) * TAU
		points.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	draw_colored_polygon(points, color)


# Lente (intersezione geometrica vera di due cerchi, richiesta utente 2026-09-04 per la faccia:
# "come se intersecassi due O, la O di sx tutta color testa, la O di destra colorata pelle SOLO
# per la parte intersecata") — non un'approssimazione: calcola i due punti di intersezione reali
# (formula standard cerchio-cerchio: a = distanza dal centro1 lungo l'asse centro1->centro2 fino
# alla "corda" comune, h = metà lunghezza della corda) poi costruisce il poligono percorrendo
# l'arco di circle1 rivolto verso circle2, seguito dall'arco di circle2 rivolto verso circle1 —
# _sweep_containing sotto sceglie esplicitamente il verso corto/lungo di ciascun arco invece di
# assumerlo, quindi resta corretto per qualunque combinazione di raggi/offset (non solo i valori
# attuali di FACE_RADIUS/FACE_OFFSET_FORWARD). Nessun disegno se i due cerchi non si intersecano
# davvero (uno dentro l'altro, o troppo distanti) — caso che non dovrebbe capitare con le costanti
# di questo file, ma resta comunque innocuo se succedesse (nessuna divisione per zero: d==0 è
# escluso esplicitamente).
const LENS_ARC_SEGMENTS: int = 8

func _draw_circle_lens(center1: Vector2, radius1: float, center2: Vector2, radius2: float, color: Color) -> void:
	var offset := center2 - center1
	var d := offset.length()
	if d <= 0.0 or d >= radius1 + radius2 or d <= absf(radius1 - radius2):
		return
	var a := (radius1 * radius1 - radius2 * radius2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(radius1 * radius1 - a * a, 0.0))
	var axis := offset / d
	var perp := axis.orthogonal()
	var mid := center1 + axis * a
	var p1 := mid + perp * h
	var p2 := mid - perp * h

	var points := PackedVector2Array()
	# Arco di circle1 (es. la testa) da p1 a p2, dal lato rivolto verso circle2.
	var a1_from := (p1 - center1).angle()
	var a1_to := (p2 - center1).angle()
	var sweep1 := _sweep_containing(a1_from, a1_to, axis.angle())
	for i in range(LENS_ARC_SEGMENTS + 1):
		var t1 := float(i) / float(LENS_ARC_SEGMENTS)
		var ang1 := a1_from + sweep1 * t1
		points.append(center1 + Vector2(cos(ang1), sin(ang1)) * radius1)
	# Arco di circle2 (es. la faccia) da p2 a p1, dal lato rivolto verso circle1 — chiude il poligono.
	var a2_from := (p2 - center2).angle()
	var a2_to := (p1 - center2).angle()
	var sweep2 := _sweep_containing(a2_from, a2_to, (-axis).angle())
	for i in range(LENS_ARC_SEGMENTS + 1):
		var t2 := float(i) / float(LENS_ARC_SEGMENTS)
		var ang2 := a2_from + sweep2 * t2
		points.append(center2 + Vector2(cos(ang2), sin(ang2)) * radius2)
	draw_colored_polygon(points, color)


# Sweep (radianti, con segno) da `from` a `to` che passa per l'angolo `through` — sceglie
# ESPLICITAMENTE il verso (senso orario/antiorario, arco corto/lungo) invece di assumerlo: due
# angoli hanno sempre DUE archi possibili tra loro, solo uno dei due passa per `through`.
static func _sweep_containing(from: float, to: float, through: float) -> float:
	var diff := wrapf(to - from, 0.0, TAU)
	var through_diff := wrapf(through - from, 0.0, TAU)
	if through_diff <= diff:
		return diff
	return diff - TAU
