class_name DeadBodyView
extends HumanIndividualView

# View minima e PASSIVA per un corpo morto (Step 5 del sistema oggetti-scaduti, 2026-09-05) —
# stesso principio "usa e getta" della classe base (nessuna mesh/texture, solo _draw()
# immediate-mode). EXTENDS HumanIndividualView per riusare DIRETTAMENTE le sue costanti di forma/
# colore (TORSO_RADIUS_*/HEAD_RADIUS/SKIN_COLOR/HAIR_COLOR_BY_TRAIT/CLOTHING_COLOR_BY_TRAIT/
# CELL_SIZE/ecc.) e i suoi helper di disegno puramente geometrici (_draw_ellipse/_draw_circle_lens
# — nessuno dei due legge mai `individual`, solo argomenti passati, quindi ereditarli è sicuro
# anche senza un vero HumanIndividual dietro) — "riusa la stessa logica di forma/scala, non
# inventarne una nuova" (richiesta utente).
#
# _process()/_draw() sono COMPLETAMENTE RISCRITTI qui, mai richiamati via super(): quelli della
# classe base leggono `individual`/`game_data.year - individual.birth_year_virtual`/is_moving/
# is_selected/facing_direction — nessuno dei quali ha senso per un cadavere (l'HumanIndividual
# originale è già stato rimosso da _human_individuals allo Step 6 del piano mortalità quando
# questa view viene creata). Il campo ereditato `individual` resta sempre null qui, innocuo
# (mai letto dai nostri _process/_draw).
#
# Postura "a faccia in giù" (richiesta utente): rotation assegnata UNA VOLTA a caso in setup()
# (varietà visiva tra cadaveri diversi, richiesta utente — "a tua scelta" tra fisso e casuale) e
# mai più toccata (a differenza della classe base che segue facing_direction ogni frame), nessuna
# animazione di passo (gambe/braccia sempre alla posizione di riposo, fase 0 — stessa geometria di
# una HumanIndividualView ferma), e NIENTE lente faccia/naso: in HumanIndividualView quel
# dettaglio è solo un indicatore di direzione di marcia, senza senso per un corpo immobile e
# rivolto verso il basso.
#
# Disposizione DISTESA (fix, 2026-09-05): testa/busto/gambe allineati lungo l'asse locale X
# (l'asse su cui `rotation` sopra applica poi l'orientamento casuale) invece che sovrapposti al
# centro come nella postura eretta della classe base — vedi le costanti SUPINE_*/_draw() sotto.
# Nessuna forma/colore/scala cambiati, solo le coordinate dei centri.
#
# Scala per età: calcolata UNA VOLTA in setup() da age_at_death (congelato — a differenza di un
# individuo vivo, la cui età e quindi la scala cambiano ogni anno, un cadavere non invecchia più),
# stessa identica formula della classe base (human_rules.size_multiplier_by_age/by_sex), nessun
# nuovo calcolo. queue_redraw() chiamato una sola volta: nulla di ciò che _draw() disegna cambia
# mai più dopo setup().

var _sex: HumanTypes.Sex
var _hair_color: HumanTypes.HairColor
var _clothing_color: HumanTypes.ClothingColor

# Layout disteso lungo l'asse locale X (fix, 2026-09-05) — testa a un'estremità, busto subito
# dopo, gambe che proseguono l'asse verso l'estremità opposta. Valori scelti per un lieve
# "aggancio"/sovrapposizione tra parti adiacenti, non un calcolo geometrico esatto — nessuna
# richiesta di realismo, solo continuità visiva.
const SUPINE_HEAD_AXIS_OFFSET: float = -1.2

# Busto DEDICATO alla postura distesa (fix 2, 2026-09-05, richiesta utente: "più stretto da morto
# e un po' più alto") — a differenza del resto (gambe/spalle/testa, dove riusiamo i raggi della
# classe base invariati), qui i raggi standing (FORWARD=0.9 più corto dell'asse, SIDE=1.15 più
# largo lateralmente — pensati per un busto largo di spalle visto dall'alto) erano proprio
# sbagliati per un corpo disteso: invertita l'enfasi, più lungo lungo l'asse (SIDE più stretto).
const SUPINE_TORSO_RADIUS_FORWARD: float = 1.2
const SUPINE_TORSO_RADIUS_SIDE: float = 0.7

# Avvicinate al busto (fix 2, richiesta utente: "le gambe sembrano leggermente staccate dal
# busto") — ridotto da 1.3, e il busto stesso ora più lungo (SUPINE_TORSO_RADIUS_FORWARD sopra),
# quindi il margine di sovrapposizione con le gambe è doppiamente maggiore di prima.
const SUPINE_LEG_AXIS_OFFSET: float = 1.15

# Braccia RIDISEGNATE come ellissi "a gamba" invece che cerchi (fix 2, richiesta utente: "non
# vanno disegnate come pallini dello stesso colore del vestito, ma come fossero due gambe attaccate
# al busto alla posizione delle braccia") — stessa forma/colore SKIN_COLOR delle gambe, solo un
# po' più piccole (richiesta utente) e posizionate sul bordo del busto ORA più stretto
# (SUPINE_ARM_SIDE_OFFSET = SUPINE_TORSO_RADIUS_SIDE, stessa relazione "spalla sul bordo busto"
# della classe base, qui applicata al nuovo bordo distesso invece che a quello eretto).
const SUPINE_ARM_RADIUS_FORWARD: float = 0.48 # allungate (fix 4, 2026-09-05, richiesta utente)
const SUPINE_ARM_RADIUS_SIDE: float = 0.18
const SUPINE_ARM_SIDE_OFFSET: float = SUPINE_TORSO_RADIUS_SIDE
# Offset assiale delle braccia, verso il lato testa — STESSO valore per entrambe (fix 3,
# 2026-09-05: prima sfalsato asimmetricamente, una verso testa una verso gambe, tolto su
# richiesta esplicita dell'utente, "perché non partono alla stessa altezza?").
const SUPINE_ARM_AXIS_OFFSET: float = 0.3

# Raggio del cerchiolino di selezione (bugfix, 2026-09-05, richiesta utente: mancava rispetto a
# individui/edifici) — la classe base lo calcola dalla propria geometria eretta (centrata
# all'origine su ogni asse), qui il corpo è disteso e allungato lungo X: un singolo valore fisso
# che copre l'estremità più lontana (la testa, SUPINE_HEAD_AXIS_OFFSET + HEAD_RADIUS = 1.8) invece
# di un calcolo geometrico esatto — stesso principio "indicatore puramente cosmetico" già
# dichiarato dalla classe base per il proprio anello.
const SUPINE_SELECTION_RADIUS: float = 1.8

# Selezione (bugfix, 2026-09-05) — NON il campo `individual.is_selected` della classe base
# (individual resta sempre null qui, vedi sopra): un proprio campo, impostato/pulito da GameScene
# (_select_dead_body/_clear_dead_body_selection) tramite GameScene.dead_body_views (individual_id
# -> DeadBodyView), stesso principio "GameScene decide, la view si limita a disegnare" del resto
# del progetto. GameScene chiama queue_redraw() esplicitamente dopo aver cambiato questo campo
# (qui non esiste il meccanismo di early-out per-frame della classe base, quindi nessun altro
# punto lo farebbe scattare da solo).
var is_selected: bool = false

# Solo appeared_at_year/appeared_at_day servono a ExpiredObjectCalculator.is_expired — stesso
# Dictionary "record" minimo richiesto dalla sua firma, costruito una volta qui invece che ad ogni
# frame in _process().
var _expiry_record: Dictionary
var _rules: ExpiredObjectRules


# individual_position/sex/age_at_death/hair_color/clothing_color/appeared_at_year/appeared_at_day
# arrivano già risolti dal chiamante (GameScene, stesso principio "componente muto" di
# HumanIndividualInfoPanel/VegetationInfoPanel) — questa view non conosce HumanIndividual/
# GameTimeService/expired_objects, solo i dati necessari a disegnarsi e a sapere quando sparire.
# game_data passato per riferimento (letto ogni frame in _process per year/current_day correnti,
# mai copiato) — stesso principio già usato dalla classe base per lo stesso campo.
func setup_dead_body(
	individual_position: Vector2, sex: HumanTypes.Sex, age_at_death: int,
	hair_color: HumanTypes.HairColor, clothing_color: HumanTypes.ClothingColor,
	appeared_at_year: int, appeared_at_day: int, p_human_rules: HumanRules, p_game_data: GameData
) -> void:
	position = individual_position * CELL_SIZE
	rotation = randf() * TAU
	_sex = sex
	_hair_color = hair_color
	_clothing_color = clothing_color
	_expiry_record = {"appeared_at_year": appeared_at_year, "appeared_at_day": appeared_at_day}
	game_data = p_game_data
	human_rules = p_human_rules
	_rules = ExpiredObjectCalculator.get_object_rules(ExpiredObjectTypes.ExpiredObjectType.DEAD_BODY)

	if human_rules != null and game_data != null:
		var age_band := HumanCalculator.get_age_band(
			game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female,
			sex, float(age_at_death)
		)
		var age_multiplier: float = human_rules.size_multiplier_by_age[age_band]
		var sex_multiplier: float = human_rules.size_multiplier_by_sex[sex]
		scale = Vector2.ONE * BASE_DRAW_SCALE * age_multiplier * sex_multiplier
	else:
		scale = Vector2.ONE * BASE_DRAW_SCALE
	queue_redraw()


# Unico lavoro per frame: sapere quando sparire (richiesta utente — "la view deve smettere di
# disegnarsi da sola quando il corpo è scaduto... indipendentemente dal fatto che il record sia
# già stato fisicamente rimosso da game_data.expired_objects dalla pulizia annuale", Step 4:
# rendering e pulizia dati sono controlli indipendenti, questa view non legge mai
# game_data.expired_objects). queue_free() (non solo visible=false): niente resta da processare
# per un corpo scaduto, stessa economia di qualunque nodo "usa e getta" rimosso in questo progetto.
func _process(_delta: float) -> void:
	if _rules == null or game_data == null:
		return
	if ExpiredObjectCalculator.is_expired(_expiry_record, _rules, game_data.year, game_data.current_day):
		queue_free()


func _draw() -> void:
	var hair_color: Color = HAIR_COLOR_BY_TRAIT.get(_hair_color, HAIR_COLOR_BY_TRAIT[HumanTypes.HairColor.BROWN])
	var clothing_color: Color = CLOTHING_COLOR_BY_TRAIT.get(_clothing_color, CLOTHING_COLOR_BY_TRAIT[HumanTypes.ClothingColor.TAN])
	# Gambe: proseguono l'asse oltre il busto, verso l'estremità opposta alla testa
	# (SUPINE_LEG_AXIS_OFFSET) — stesso LEG_SIDE_OFFSET laterale della classe base (già "leggermente
	# divaricate" lì), mai sovrapposte (2*LEG_RADIUS_SIDE < 2*LEG_SIDE_OFFSET). Nessuna oscillazione:
	# un corpo non cammina.
	_draw_ellipse(Vector2(SUPINE_LEG_AXIS_OFFSET, -LEG_SIDE_OFFSET), LEG_RADIUS_FORWARD, LEG_RADIUS_SIDE, SKIN_COLOR)
	_draw_ellipse(Vector2(SUPINE_LEG_AXIS_OFFSET, LEG_SIDE_OFFSET), LEG_RADIUS_FORWARD, LEG_RADIUS_SIDE, SKIN_COLOR)
	# Busto: subito dopo la testa lungo lo stesso asse (la testa vive a SUPINE_HEAD_AXIS_OFFSET,
	# vedi sotto) — raggi DEDICATI alla postura distesa (SUPINE_TORSO_RADIUS_*), non quelli della
	# classe base (pensati per un busto eretto largo di spalle, sbagliati qui).
	_draw_ellipse(Vector2.ZERO, SUPINE_TORSO_RADIUS_FORWARD, SUPINE_TORSO_RADIUS_SIDE, clothing_color)
	if _sex == HumanTypes.Sex.FEMALE:
		# Capelli dietro la testa, lato opposto al busto — stessa relazione HAIR_LONG_OFFSET_FORWARD
		# della classe base (dietro rispetto al busto), solo traslata sulla nuova posizione testa.
		_draw_ellipse(
			Vector2(SUPINE_HEAD_AXIS_OFFSET + HAIR_LONG_OFFSET_FORWARD, 0.0),
			HAIR_LONG_RADIUS_FORWARD, HAIR_LONG_RADIUS_SIDE, hair_color
		)
	# Braccia: ellissi "a gamba" (stessa forma/colore SKIN_COLOR delle gambe, un po' più piccole —
	# vedi SUPINE_ARM_RADIUS_*), attaccate al bordo del busto ristretto (SUPINE_ARM_SIDE_OFFSET).
	# STESSO offset assiale per entrambe, verso il lato testa (fix 3, 2026-09-05, richiesta utente:
	# "non capisco perché non partano alla stessa altezza" — lo sfalsamento asimmetrico di prima,
	# una verso testa una verso gambe, era un dettaglio cosmetico non richiesto, tolto).
	_draw_ellipse(
		Vector2(-SUPINE_ARM_AXIS_OFFSET, -SUPINE_ARM_SIDE_OFFSET), SUPINE_ARM_RADIUS_FORWARD, SUPINE_ARM_RADIUS_SIDE, SKIN_COLOR
	)
	_draw_ellipse(
		Vector2(-SUPINE_ARM_AXIS_OFFSET, SUPINE_ARM_SIDE_OFFSET), SUPINE_ARM_RADIUS_FORWARD, SUPINE_ARM_RADIUS_SIDE, SKIN_COLOR
	)
	# Testa: a un'estremità dell'asse (SUPINE_HEAD_AXIS_OFFSET) — SENZA faccia/naso (a faccia in
	# giù — nessun indicatore di direzione di marcia da mostrare, il corpo è immobile).
	draw_circle(Vector2(SUPINE_HEAD_AXIS_OFFSET, 0.0), HEAD_RADIUS, hair_color)
	if is_selected:
		draw_arc(Vector2.ZERO, SUPINE_SELECTION_RADIUS, 0, TAU, 24, SELECTION_COLOR, SELECTION_WIDTH)
