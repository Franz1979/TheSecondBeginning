class_name AnimalGroupRenderer
extends Node2D

# Nodo generico e riusabile: un'istanza per specie animale. Non contiene alcuna logica
# specifica di una specie nel movimento — tutti i parametri comportamentali arrivano via
# configure(), chiamato una volta dal nodo che lo istanzia (oggi MacroCellScene, per "rabbit" e
# "deer"). La FORMA di ogni specie invece non è parametrica dentro questa classe: il chiamante
# costruisce la ArrayMesh con la funzione statica dedicata alla specie (build_rabbit_mesh,
# build_deer_mesh, ...) e la passa già pronta in configure() — vedi commento lì. Disegna i
# gruppi tramite un singolo MultiMeshInstance2D che si aggiorna e ridisegna da solo ogni frame
# quando cambiano le trasformazioni istanza — a differenza di MicroCellRenderer, qui NON si usa
# _draw()/queue_redraw(): un redraw manuale a ogni frame rifarebbe inutilmente anche i buffer
# statici (erba, pietre, alberi) di tutta la cella.
const CELL_SIZE: int = 10 # stesso fattore pixel/microcella di MicroCellRenderer
const BODY_SEGMENTS: int = 16 # risoluzione del ventaglio del corpo, condivisa da tutte le specie
const TAIL_SEGMENTS: int = 8  # risoluzione del cerchietto della coda, condivisa da tutte le specie

# --- Sagoma RABBIT (build_rabbit_mesh) ---
# Il corpo non è un'ellisse simmetrica: il raggio Y viene scalato da un fattore che assottiglia
# il muso (+X, direzione di marcia) e allarga i fianchi (-X, posteriore) — per leggersi come un
# coniglio affusolato invece di un maialino.
const RABBIT_BODY_FRONT_WIDTH_RATIO: float = 0.55
const RABBIT_BODY_REAR_WIDTH_RATIO: float = 1.25
# Ancorate vicino al muso (+X, direzione di marcia): puntando in avanti-e-leggermente-fuori,
# le orecchie si estendono oltre la punta del muso in spazio libero (nessuna sagoma del corpo
# lì), quindi restano nettamente visibili senza bisogno di un ancoraggio laterale estremo —
# a differenza dei tentativi all'indietro (135°/150°/160° dall'asse di marcia), che finivano
# per leggersi come alette/ali ai lati o restare sepolti nel fianco largo del corpo.
const RABBIT_EAR_ANCHOR_RATIO: float = 0.75 # frazione di body_length a cui ancorare le orecchie
const RABBIT_EAR_ANCHOR_LATERAL_RATIO: float = 0.3 # frazione di body_width per lo scarto laterale: vicine tra loro, non allargate
# Angolo dall'asse di marcia locale +X, mirrorato ±side: piccolo (10°, era 20°: più dritte,
# meno divaricate — a 20° con orecchie sottili si leggevano come antenne) così le due orecchie
# restano quasi parallele all'asse di marcia invece di aprirsi a V.
const RABBIT_EAR_ANGLE_FROM_HEADING: float = 10.0 * PI / 180.0
# Coda: piccolo cerchio sul retro (-X), stesso colore uniforme del resto (vedi color in configure).
const RABBIT_TAIL_RADIUS: float = 0.85
const RABBIT_TAIL_ANCHOR_RATIO: float = 0.9 # frazione di body_length: leggermente arretrata rispetto alla punta posteriore, così risulta "attaccata"

# --- Sagoma DEER (build_deer_mesh) ---
# A differenza del coniglio, il corpo del cervo è quasi uniforme (poco affusolato: un animale
# allungato, non a goccia) — front/rear ratio vicini a 1 invece del forte contrasto 0.55/1.25
# del coniglio.
const DEER_BODY_FRONT_WIDTH_RATIO: float = 0.8
const DEER_BODY_REAR_WIDTH_RATIO: float = 1.05
# Orecchie piccole "all'erta" sopra la testa, angolate verso l'esterno/alto (~60° dall'asse di
# marcia) invece che protese in avanti come quelle del coniglio — più larghe tra loro
# (lateral_ratio maggiore) per leggersi come orecchie ritte, non come corna.
const DEER_EAR_ANCHOR_RATIO: float = 0.85
const DEER_EAR_ANCHOR_LATERAL_RATIO: float = 0.6
const DEER_EAR_ANGLE_FROM_HEADING: float = 60.0 * PI / 180.0
# Coda più piccola del coniglio (i cervi hanno una coda corta, non un batuffolo prominente).
const DEER_TAIL_RADIUS: float = 0.6
const DEER_TAIL_ANCHOR_RATIO: float = 0.92

# --- Sagoma BOAR (build_boar_mesh) ---
# Rapporto INVERTITO rispetto al coniglio: il cinghiale ha testa/spalle massicce che si
# assottigliano verso il posteriore (front_width > rear_width), non un corpo a goccia
# rear-heavy come rabbit — legge come un animale tozzo e squadrato davanti.
const BOAR_BODY_FRONT_WIDTH_RATIO: float = 1.3
const BOAR_BODY_REAR_WIDTH_RATIO: float = 0.7
# Orecchie piccole, ancorate vicino al muso come il coniglio ma molto più corte, angolate a
# metà strada tra le orecchie protese di rabbit e quelle ritte di deer.
const BOAR_EAR_ANCHOR_RATIO: float = 0.85
const BOAR_EAR_ANCHOR_LATERAL_RATIO: float = 0.5
const BOAR_EAR_ANGLE_FROM_HEADING: float = 45.0 * PI / 180.0
# Coda corta (più del cervo): un moncherino, non un batuffolo né una coda lunga.
const BOAR_TAIL_RADIUS: float = 0.45
const BOAR_TAIL_ANCHOR_RATIO: float = 0.95

# --- Sagoma TARPAN (build_tarpan_mesh) ---
# Corpo quasi uniforme come deer, leggermente più affusolato verso il muso (collo/testa più
# stretti del garrese) — front/rear ratio intermedio tra deer (0.8/1.05) e rabbit.
const TARPAN_BODY_FRONT_WIDTH_RATIO: float = 0.75
const TARPAN_BODY_REAR_WIDTH_RATIO: float = 1.0
# Orecchie piccole e ritte, più verticali di quelle "all'erta" di deer (angolo maggiore
# dall'asse di marcia) — lettura da equide, non da cervide.
const TARPAN_EAR_ANCHOR_RATIO: float = 0.88
const TARPAN_EAR_ANCHOR_LATERAL_RATIO: float = 0.55
const TARPAN_EAR_ANGLE_FROM_HEADING: float = 70.0 * PI / 180.0
# Coda ellittica allungata lungo l'asse del corpo (X) e stretta sull'asse trasversale (Y) —
# _get_silhouette_geometry/_build_mesh_from_geometry ora supportano due raggi distinti invece di
# un cerchio perfetto, usati per la prima volta qui.
const TARPAN_TAIL_RADIUS_X: float = 1.3
const TARPAN_TAIL_RADIUS_Y: float = 0.4
const TARPAN_TAIL_ANCHOR_RATIO: float = 1.0

# --- Sagoma WILD_DONKEY (build_wild_donkey_mesh) ---
# Stesso schema generale di tarpan (equide, corpo quasi uniforme) ma front/rear più vicini
# (0.8/1.0 contro 0.75/1.0 di tarpan) per leggersi "leggermente più tozzo" invece che filiforme.
const WILD_DONKEY_BODY_FRONT_WIDTH_RATIO: float = 0.8
const WILD_DONKEY_BODY_REAR_WIDTH_RATIO: float = 1.0
# Tratto distintivo reale dell'asino: orecchie molto più lunghe in proporzione al corpo di
# quelle di tarpan (vedi WILD_DONKEY_EAR_LENGTH sotto, ~0.35x body_length contro ~0.18x di
# tarpan) — anchor/lateral simili a tarpan (stessa lettura "equide ritto"), angolo leggermente
# meno verticale per lasciare più spazio visivo alla lunghezza extra senza leggersi come corna.
const WILD_DONKEY_EAR_ANCHOR_RATIO: float = 0.85
const WILD_DONKEY_EAR_ANCHOR_LATERAL_RATIO: float = 0.5
const WILD_DONKEY_EAR_ANGLE_FROM_HEADING: float = 65.0 * PI / 180.0
# Coda ellittica come tarpan (stesso meccanismo a due raggi indipendenti), scalata in giù per il
# corpo più piccolo.
const WILD_DONKEY_TAIL_RADIUS_X: float = 1.0
const WILD_DONKEY_TAIL_RADIUS_Y: float = 0.35
const WILD_DONKEY_TAIL_ANCHOR_RATIO: float = 1.0

# --- Sagoma AUROCHS (build_aurochs_mesh) ---
# A differenza di boar (front_width > rear_width, spalle larghe/anche strette a goccia), un
# bovino deve leggersi con larghezza uniforme testa-coda: front/rear ratio UGUALI collassano
# _get_silhouette_geometry's width_scale (normalmente un lerp tra i due) a un valore costante per
# ogni angolo, quindi il corpo diventa un'ellisse simmetrica invece che una goccia asimmetrica —
# il massimo di "squadrato/uniforme" ottenibile in questa pipeline senza una nuova primitiva.
# Nota strutturale: i vertici a muso (angle=0) e coda (angle=PI) restano comunque punte
# geometriche vere in QUALUNQUE combinazione di ratio (lì sin(angle)=0 a prescindere) — un corpo
# davvero tronco a entrambe le estremità richiederebbe una formula diversa (es. capsula/
# superellisse), non solo questi due parametri.
const AUROCHS_BODY_FRONT_WIDTH_RATIO: float = 1.0
const AUROCHS_BODY_REAR_WIDTH_RATIO: float = 1.0
# Lo slot "orecchie" condiviso da tutte le specie viene qui riusato per le CORNA (nessun nuovo
# elemento geometrico nella pipeline generica _get_silhouette_geometry/_build_mesh_from_geometry
# — vedi commento in cima al file): ancorate vicino alla testa (anchor_ratio alto, come tarpan/
# boar) ma con base molto più ravvicinata (lateral_ratio basso, come rabbit) perché le corna
# nascono vicine sulla sommità del cranio, non ai lati della testa come vere orecchie. Angolo
# intermedio tra rabbit (protese in avanti) e boar (aperte a ventaglio) per leggersi come corna
# che puntano in avanti e leggermente verso l'esterno.
const AUROCHS_EAR_ANCHOR_RATIO: float = 0.92
const AUROCHS_EAR_ANCHOR_LATERAL_RATIO: float = 0.35
const AUROCHS_EAR_ANGLE_FROM_HEADING: float = 35.0 * PI / 180.0
# Coda corta come boar/deer (non il batuffolo di rabbit né l'ellisse allungata di tarpan).
const AUROCHS_TAIL_RADIUS: float = 0.55
const AUROCHS_TAIL_ANCHOR_RATIO: float = 0.95

# --- Sagoma MOUFLON (build_mouflon_mesh) ---
# Corpo compatto, taper mite (front/rear vicini, come deer, ma leggermente più massiccio in
# spalla per una lettura da ovino robusto invece che filiforme).
const MOUFLON_BODY_FRONT_WIDTH_RATIO: float = 0.9
const MOUFLON_BODY_REAR_WIDTH_RATIO: float = 1.0
# Come aurochs, lo slot "orecchie" è riusato per le CORNA (nessuna nuova geometria) — ma con
# angolo MOLTO più ampio dall'asse di marcia (140° contro i 35° di aurochs): un triangolo dritto
# non può disegnare la spirale reale del corno di muflone, ma angolandolo all'indietro e verso
# l'esterno invece che in avanti si ottiene una lettura "corno che curva indietro" nettamente
# distinguibile dalle corna dritte-in-avanti di aurochs, il compromesso più semplice compatibile
# con la pipeline esistente. Lunghezza proporzionalmente grande rispetto al corpo (vedi
# MOUFLON_EAR_LENGTH sotto, ~0.37x body_length) perché nel muflone reale le corna sono vistose
# rispetto alla taglia corporea ridotta. Base ravvicinata (lateral_ratio basso) come aurochs,
# stesso motivo: nascono vicine sulla sommità del cranio.
const MOUFLON_EAR_ANCHOR_RATIO: float = 0.9
const MOUFLON_EAR_ANCHOR_LATERAL_RATIO: float = 0.4
const MOUFLON_EAR_ANGLE_FROM_HEADING: float = 140.0 * PI / 180.0
# Coda corta e circolare come deer/boar (nessun bisogno dell'ellisse a due raggi di tarpan/
# wild_donkey, riservata agli equidi).
const MOUFLON_TAIL_RADIUS: float = 0.5
const MOUFLON_TAIL_ANCHOR_RATIO: float = 0.95

# --- Sagoma BEZOAR (build_bezoar_mesh) ---
# Stesso archetipo corporeo di mouflon (compatto, taper mite front/rear) — le due specie
# condividono la stessa nicchia ecologica (ungulati montani di taglia simile), quindi la stessa
# forma di base ha senso; a differenziarle sono soprattutto dimensioni assolute (vedi
# BEZOAR_BODY_LENGTH/WIDTH sotto) e corna.
const BEZOAR_BODY_FRONT_WIDTH_RATIO: float = 0.9
const BEZOAR_BODY_REAR_WIDTH_RATIO: float = 1.0
# Corna riusando lo slot "orecchie" come già per aurochs/mouflon, ma qui l'angolo è vicino ai 90°
# (quasi perpendicolare all'asse di marcia) invece che nettamente in avanti (aurochs, 35°) o
# all'indietro (mouflon, 140°) — la lettura più vicina a "dritto/verticale" ottenibile in una
# vista dall'alto puramente 2D, dove non esiste un vero asse verticale da inclinare: qui "dritte"
# si traduce nell'assenza di uno sweep marcato in una direzione o nell'altra, a differenza dello
# sweep pronunciato delle altre due specie. Più lunghe e più sottili di quelle di mouflon (vedi
# BEZOAR_EAR_LENGTH/WIDTH sotto) per leggersi come lame a sciabola invece che corna ricurve tozze.
const BEZOAR_EAR_ANCHOR_RATIO: float = 0.88
const BEZOAR_EAR_ANCHOR_LATERAL_RATIO: float = 0.38
const BEZOAR_EAR_ANGLE_FROM_HEADING: float = 95.0 * PI / 180.0
# Coda corta e circolare come mouflon, leggermente più piccola (corpo leggermente più piccolo).
const BEZOAR_TAIL_RADIUS: float = 0.45
const BEZOAR_TAIL_ANCHOR_RATIO: float = 0.95

# --- Sagoma WOLF (build_wolf_mesh) ---
# Prima specie PREDATRICE (PredatorRules, non AnimalRules) a ricevere una sagoma dedicata — la
# pipeline di forma (_get_silhouette_geometry/_build_mesh_from_geometry) è comunque generica
# rispetto a prede/predatori, nessun adattamento richiesto. Corpo da canide: taper testa/coda più
# marcato di deer (0.8/1.05) ma meno estremo del muso a goccia di rabbit (0.55/1.25) — un lupo si
# legge con un muso distintamente più stretto delle spalle/anche, non uniforme come un cervide né
# a goccia come un leporide.
const WOLF_BODY_FRONT_WIDTH_RATIO: float = 0.65
const WOLF_BODY_REAR_WIDTH_RATIO: float = 1.1
# Orecchie piccole, dritte, "a punta" e leggermente in avanti — più vicine all'assetto "all'erta"
# di deer (60°) che a quello quasi orizzontale di boar (45°), ma con angolo intermedio (42°) per
# leggersi più aguzze/dritte-in-avanti di quelle "aperte lateralmente" del cervo.
const WOLF_EAR_ANCHOR_RATIO: float = 0.87
const WOLF_EAR_ANCHOR_LATERAL_RATIO: float = 0.45
const WOLF_EAR_ANGLE_FROM_HEADING: float = 42.0 * PI / 180.0
# Coda ellittica allungata lungo l'asse del corpo (stesso meccanismo a due raggi di tarpan/
# wild_donkey), qui per rendere la coda folta e distesa tipica del lupo — non un batuffolo/
# moncherino come le prede erbivore di taglia comparabile (deer/boar), l'unico tratto di sagoma
# condiviso con gli equidi pur non essendone uno.
const WOLF_TAIL_RADIUS_X: float = 0.9
const WOLF_TAIL_RADIUS_Y: float = 0.35
const WOLF_TAIL_ANCHOR_RATIO: float = 1.0

# --- Sagoma PARTRIDGE (build_partridge_mesh) ---
# Prima specie non-mammifero a ricevere una sagoma: nessuna nuova geometria nella pipeline
# generica, lo slot "orecchie" viene qui riusato come ALI RIPIEGATE invece che orecchie/corna.
# Corpo quasi uniforme come deer (front/rear vicini) — un uccello non ha un muso da assottigliare
# come rabbit, si legge meglio tondeggiante che a goccia.
const PARTRIDGE_BODY_FRONT_WIDTH_RATIO: float = 0.8
const PARTRIDGE_BODY_REAR_WIDTH_RATIO: float = 1.05
# Ali ripiegate: ancorate a META' corpo (anchor_ratio basso, non vicino alla testa come le
# orecchie di rabbit/deer) e angolate NETTAMENTE all'indietro (155°, il valore più arretrato di
# tutto il roster, oltre i 140° delle corna di mouflon) così si leggono come ali chiuse contro il
# fianco puntate verso la coda, non come orecchie/corna dritte o laterali.
const PARTRIDGE_EAR_ANCHOR_RATIO: float = 0.3
const PARTRIDGE_EAR_ANCHOR_LATERAL_RATIO: float = 0.95
const PARTRIDGE_EAR_ANGLE_FROM_HEADING: float = 155.0 * PI / 180.0
# Coda piccola e compatta (ventaglio di penne), la più piccola del roster insieme a boar.
const PARTRIDGE_TAIL_RADIUS: float = 0.35
const PARTRIDGE_TAIL_ANCHOR_RATIO: float = 0.85

# Dimensioni/colore di riferimento per specie, usati da MacroCellScene per costruire la mesh sul
# campo (build_rabbit_mesh/build_deer_mesh) E da AnimalSilhouetteIcon per l'icona del filtro Fauna
# (WorldInfoPanel) — un'unica fonte di verità, non due valori duplicati che potrebbero
# disallinearsi se uno dei due punti venisse tarato di nuovo senza ricordarsi dell'altro.
const RABBIT_BODY_LENGTH: float = 3.0
const RABBIT_BODY_WIDTH: float = 1.3
const RABBIT_EAR_LENGTH: float = 2.7
const RABBIT_EAR_WIDTH: float = 0.9
const RABBIT_COLOR: Color = Color(0.93, 0.91, 0.87, 0.95)

const DEER_BODY_LENGTH: float = 5.5
const DEER_BODY_WIDTH: float = 2.2
const DEER_EAR_LENGTH: float = 1.4
const DEER_EAR_WIDTH: float = 0.6
const DEER_COLOR: Color = Color(0.55, 0.4, 0.25, 0.95)

const BOAR_BODY_LENGTH: float = 4.5
const BOAR_BODY_WIDTH: float = 2.4
const BOAR_EAR_LENGTH: float = 1.0
const BOAR_EAR_WIDTH: float = 0.5
const BOAR_COLOR: Color = Color(0.25, 0.18, 0.12, 0.95)

# Corpo più allungato/snello di tutte le altre specie (rapporto lunghezza:larghezza ~3.25:1,
# contro il ~2.5:1 di deer) per leggersi come un animale più "rangy"/filiforme — non esiste un
# concetto di zampe in questa sagoma generica (corpo+2 orecchie+coda, condivisa da ogni specie),
# quindi "gambe lunghe" è approssimato solo con la snellezza del corpo, non con arti disegnati.
const TARPAN_BODY_LENGTH: float = 6.5
const TARPAN_BODY_WIDTH: float = 2.0
const TARPAN_EAR_LENGTH: float = 1.2
const TARPAN_EAR_WIDTH: float = 0.5
# Tonalità "grullo"/topo, richiamo storico al mantello del tarpan — desaturata verso il grigio
# (a differenza del bruno caldo e saturo di DEER_COLOR) così le due specie restano distinguibili
# a colpo d'occhio anche a icona piccola.
const TARPAN_COLOR: Color = Color(0.5, 0.5, 0.47, 0.95)

# Più piccolo di tarpan su entrambi gli assi (5.8x2.1 contro 6.5x2.0) ma rapporto L:W più basso
# (~2.76:1 contro ~3.25:1) — leggermente più tozzo come da design, non solo "un tarpan rimpicciolito".
# Orecchie lunghe (vedi WILD_DONKEY_EAR_* sopra) sono il tratto distintivo principale rispetto a
# tarpan/deer. Colore grigio-brunastro, intermedio tra il grigio neutro di TARPAN_COLOR e il
# bruno caldo di DEER_COLOR — distinguibile da entrambi a colpo d'occhio.
const WILD_DONKEY_BODY_LENGTH: float = 5.8
const WILD_DONKEY_BODY_WIDTH: float = 2.1
const WILD_DONKEY_EAR_LENGTH: float = 2.0
const WILD_DONKEY_EAR_WIDTH: float = 0.55
const WILD_DONKEY_COLOR: Color = Color(0.55, 0.48, 0.4, 0.95)

# La specie più grande finora (corpo massiccio come boar ma di dimensioni maggiori, corna incluse
# nello slot "orecchie" — vedi costanti AUROCHS_EAR_* sopra). Colore bruno-nerastro pieno, fedele
# al mantello scuro dell'aurochs storico (i maschi erano quasi neri, le femmine bruno-rossicce) —
# NON il bianco a macchie nere tipico delle mucche domestiche moderne: il sistema di rendering
# assegna un unico colore uniforme per specie (vedi _build_mesh_from_geometry, un solo
# st.set_color() per l'intera sessione SurfaceTool, condiviso da tutte le istanze via MultiMesh),
# quindi un pattern a macchie sarebbe identico su ogni singolo individuo e illeggibile alla scala
# di rendering effettiva (icone/gruppi di poche decine di px) — riservato come idea per una futura
# mucca domestica, non implementato qui.
const AUROCHS_BODY_LENGTH: float = 7.5
const AUROCHS_BODY_WIDTH: float = 3.4
const AUROCHS_EAR_LENGTH: float = 2.5
const AUROCHS_EAR_WIDTH: float = 0.35
const AUROCHS_COLOR: Color = Color(0.14, 0.1, 0.08, 0.95)

# Il più piccolo tra i grandi erbivori "veri" (sopra rabbit, sotto boar — vedi confronto body
# LENGTH×WIDTH nel report di implementazione): 3.8x1.7, contro il 4.5x2.4 di boar e il 3.0x1.3 di
# rabbit. Rapporto L:W basso (~2.24:1) per leggersi come "compatto" invece che filiforme. Corna
# nello slot "orecchie" (vedi MOUFLON_EAR_* sopra) proporzionalmente vistose rispetto al corpo
# ridotto. Colore bruno-grigiastro, intermedio tra il grigio neutro di TARPAN_COLOR e il bruno
# scuro di BOAR_COLOR — distinguibile da entrambi.
const MOUFLON_BODY_LENGTH: float = 3.8
const MOUFLON_BODY_WIDTH: float = 1.7
const MOUFLON_EAR_LENGTH: float = 1.4
const MOUFLON_EAR_WIDTH: float = 0.4
const MOUFLON_COLOR: Color = Color(0.42, 0.35, 0.3, 0.95)

# Taglia comparabile a mouflon (3.7x1.65 contro 3.8x1.7, vedi confronto nel report di
# implementazione) — leggermente più piccola/snella, stesso rapporto L:W (~2.24:1, stesso
# archetipo "compatto" di mouflon). Corna (vedi BEZOAR_EAR_* sopra) sensibilmente più lunghe di
# quelle di mouflon (~0.57x body_length contro ~0.37x) per leggersi come il tratto dominante
# della sagoma, a lama invece che a corno spesso ricurvo — larghezza aumentata di pari passo
# (non solo la lunghezza) così restano leggibili come lama anche alla lunghezza maggiore, invece
# di assottigliarsi fino a somigliare ad antenne. Colore grigio chiaro, nettamente più chiaro del
# bruno-grigiastro di MOUFLON_COLOR e anche più grigio/meno bruno del WILD_DONKEY_COLOR —
# distinguibile da entrambi a colpo d'occhio.
const BEZOAR_BODY_LENGTH: float = 3.7
const BEZOAR_BODY_WIDTH: float = 1.65
const BEZOAR_EAR_LENGTH: float = 2.1
const BEZOAR_EAR_WIDTH: float = 0.35
const BEZOAR_COLOR: Color = Color(0.58, 0.56, 0.52, 0.95)

# Prima specie predatrice: taglia media, tra boar (4.5x2.4, tozzo) e aurochs (7.5x3.4, massiccio)
# ma con rapporto L:W più snello di entrambi (~2.63:1 contro ~1.88:1 di boar) — legge come un
# animale magro e agile, non massiccio. Orecchie compatte (vicine a deer/boar in valore assoluto),
# coerenti con la sagoma "a punta" definita da WOLF_EAR_* sopra. Colore grigio-brunastro freddo e
# desaturato: distinto dal grigio quasi neutro/caldo di TARPAN_COLOR (0.5, 0.5, 0.47) per una
# tonalità più scura e leggermente più fredda, e dal bruno-grigiastro più caldo di MOUFLON_COLOR
# (0.42, 0.35, 0.3) per essere meno saturo/più grigio — la lettura "mantello da lupo" richiesta,
# distinguibile da entrambi a colpo d'occhio.
const WOLF_BODY_LENGTH: float = 5.0
const WOLF_BODY_WIDTH: float = 1.9
const WOLF_EAR_LENGTH: float = 1.1
const WOLF_EAR_WIDTH: float = 0.45
const WOLF_COLOR: Color = Color(0.38, 0.37, 0.35, 0.95)

# La sagoma più piccola del roster (1.8x1.1, contro 3.0x1.3 di rabbit, finora la più piccola) —
# rapporto L:W basso (~1.6:1) per leggersi tondeggiante come un uccello tozzo, non allungato come
# un mammifero. Colore bruno-rossiccio caldo, richiamo al piumaggio fulvo della starna reale —
# distinto dal grigio-brunastro freddo di TARPAN_COLOR/WILD_DONKEY_COLOR e dal bruno più
# scuro/saturo di DEER_COLOR.
const PARTRIDGE_BODY_LENGTH: float = 1.8
const PARTRIDGE_BODY_WIDTH: float = 1.1
const PARTRIDGE_EAR_LENGTH: float = 0.5
const PARTRIDGE_EAR_WIDTH: float = 0.35
const PARTRIDGE_COLOR: Color = Color(0.68, 0.5, 0.32, 0.95)

# Individui animali step 1: un'istanza disegnata = un animale reale della quota di questa cella
# (AnimalRules.visual_group_size non è più letto — un individuo non rappresenta più N animali).
# species_name arriva da configure(params["species_name"]) ed è copiato su ogni individuo generato.
var species_name: String = ""
var move_speed: float = 0.0 # microcelle/giorno di gioco
var turn_rate: float = 0.0 # radianti/giorno di gioco massimi di deriva casuale della direzione

# Cluster: stessa popolazione -> quanti gruppi disegnare, arriva da AnimalRules.max_individuals_per_cluster
# (letto dal chiamante, mai hardcoded qui). Un cluster è un punto che vaga con la STESSA logica
# di un gruppo (deriva + rimbalzo, vedi _clusters sotto) ma non viene disegnato: serve solo da
# centro verso cui i gruppi che gli appartengono vengono debolmente attratti (vedi
# _apply_cluster_attraction), niente vero flocking (no separazione/allineamento tra gruppi, no
# attrazione tra cluster diversi).
var max_individuals_per_cluster: int = 1
var cluster_comfort_radius: float = 5.0 # microcelle: entro questo raggio dal centro-cluster nessuna trazione
var cluster_attraction_strength: float = 12.0 # tasso per giorno di gioco della trazione oltre il raggio comfort

# Movimento a balzi dei gruppi (vedi AnimalVisualGroup.MacroPhase/MicroPhase e _update_group_phase),
# arrivano da AnimalRules (letti dal chiamante, mai hardcoded qui). move_speed sopra resta usato
# solo per il vagare continuo dei centri-cluster invisibili. TEMPO DI GIOCO: hop_speed in
# microcelle/giorno di gioco, tutte le durate in giorni di gioco (vedi AnimalRules e _process).
var hop_speed: float = 0.0
var movement_phase_duration_min: float = 0.25
var movement_phase_duration_max: float = 0.625
var rest_phase_duration_min: float = 0.375
var rest_phase_duration_max: float = 0.875
var hop_duration_min: float = 0.025
var hop_duration_max: float = 0.05
var hop_pause_min: float = 0.0125
var hop_pause_max: float = 0.0375

# Scala visiva (young, adult, old) applicata per-istanza in _write_instance_transform, arriva da
# AnimalRules.size_multiplier_by_age (letto dal chiamante, mai hardcoded qui) — indicizzato da
# GameTypes.AgeBand. Default [1,1,1]: nessuna scala per specie che non lo passano esplicitamente
# (compatibilità con set_population, il fallback non age-aware, che tagga tutto ADULT).
var size_multiplier_by_age: Array = [1.0, 1.0, 1.0]

# Se assegnato (vedi MacroCellScene._ready), i gruppi si muovono solo quando clock.is_playing
# è true — stesso orologio che governa l'avanzamento giorno/anno, così i conigli si fermano
# in pausa e durante le finestre di dialogo bloccanti (che già mettono in pausa il clock, vedi
# _on_blocking_dialog_visibility_changed). Dà anche il delta in giorni di gioco usato da tutto il
# movimento (vedi _game_day_delta). Se null (nessun clock assegnato), il movimento resta sempre
# attivo, al ritmo della velocità 1x.
var clock: GameClockController = null

# Test di visibilità fog of war per microcella (Vector2i -> bool), assegnato come il clock da chi
# istanzia il renderer — GameScene._activate_live_cell lo lega a FogOfWarRenderer.
# is_animal_visible_at della stessa cella (in raggio o dettaglio fresco). Callable invece di un
# riferimento a FogOfWarRenderer, così questo renderer (layer simulation) non dipende da una classe
# di gameplay. Applicato in _write_instance_transform a OGNI frame: un'istanza in una microcella
# non visibile non si disegna (scala zero), senza toccare posizione né movimento — gli animali
# restano su tutta la macrocella e possono entrare nella zona visibile da fuori. Non valida
# (default, es. MacroCellScene senza fog): tutti visibili, comportamento di sempre.
var visibility_test: Callable = Callable()

# Contatore id individui, condiviso da TUTTI i renderer (static) per l'intera sessione: un id non
# viene mai riassegnato, nemmeno a un individuo di un'altra cella/specie o a uno rigenerato dopo
# la riattivazione di una cella. Non persistito (nessun salvataggio degli individui in questo step).
static var _next_individual_id: int = 1

var _groups: Array = [] # Array[AnimalVisualGroup], un elemento per individuo (id > 0)
var _clusters: Array = [] # Array[AnimalVisualGroup], riusata come "centro mobile", mai disegnata
var _multimesh: MultiMesh
var _multimesh_instance: MultiMeshInstance2D
var _configured: bool = false


# "mesh" è una ArrayMesh già costruita dal chiamante tramite la funzione statica dedicata alla
# specie (build_rabbit_mesh/build_deer_mesh/...) — questa classe non sa e non deve sapere come è
# fatta la sagoma di una specie, riceve solo il risultato finito. Nessun default: un chiamante
# che non la passa è un bug reale (specie senza sagoma configurata), meglio un errore rumoroso
# che un coniglio-fallback silenzioso per una specie che non lo è.
func configure(params: Dictionary) -> void:
	species_name = String(params.get("species_name", ""))
	move_speed = float(params.get("move_speed", 24.0))
	turn_rate = float(params.get("turn_rate", 12.0))
	max_individuals_per_cluster = max(int(params.get("max_individuals_per_cluster", 1)), 1)
	cluster_comfort_radius = float(params.get("cluster_comfort_radius", 5.0))
	cluster_attraction_strength = float(params.get("cluster_attraction_strength", 12.0))
	hop_speed = float(params.get("hop_speed", 48.0))
	movement_phase_duration_min = float(params.get("movement_phase_duration_min", 0.25))
	movement_phase_duration_max = float(params.get("movement_phase_duration_max", 0.625))
	rest_phase_duration_min = float(params.get("rest_phase_duration_min", 0.375))
	rest_phase_duration_max = float(params.get("rest_phase_duration_max", 0.875))
	hop_duration_min = float(params.get("hop_duration_min", 0.025))
	hop_duration_max = float(params.get("hop_duration_max", 0.05))
	hop_pause_min = float(params.get("hop_pause_min", 0.0125))
	hop_pause_max = float(params.get("hop_pause_max", 0.0375))
	size_multiplier_by_age = params.get("size_multiplier_by_age", [1.0, 1.0, 1.0])

	var mesh: ArrayMesh = params["mesh"]

	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_multimesh.mesh = mesh
	_multimesh.instance_count = 0

	_multimesh_instance = MultiMeshInstance2D.new()
	_multimesh_instance.multimesh = _multimesh
	add_child(_multimesh_instance)

	_configured = true


# Puro toggle di visibilità: il movimento resta governato solo da clock.is_playing (play/pausa
# del tempo), nessun concetto separato di "freeze" — se il giocatore vuole fermarli mette in
# pausa il gioco, questo bottone serve solo a non vederli (es. mentre costruisce).
func set_animals_visible(v: bool) -> void:
	if _multimesh_instance != null:
		_multimesh_instance.visible = v


# Fallback per specie che non tracciano age band (track_age_bands false): stessa riconciliazione
# per id di set_population_by_age sotto, con l'intera quota della cella taggata ADULT (scala fissa
# size_multiplier_by_age[ADULT], 1.0 se non impostato). Un individuo per animale.
func set_population(total_population: int) -> void:
	if not _configured:
		return

	_apply_band_targets({
		GameTypes.AgeBand.YOUNG: 0,
		GameTypes.AgeBand.ADULT: max(total_population, 0),
		GameTypes.AgeBand.OLD: 0,
	})


# Specie con track_age_bands=true: la quota della cella arriva già ripartita per fascia
# (chiamante: GameScene/MacroCellScene, via PopulationGroup.get_age_composition_in_cell). Ogni
# fascia è riconciliata INDIPENDENTEMENTE dalle altre — _groups resta un unico array misto: il
# movimento/cluster restano indifferenti alla fascia, solo l'aspetto (scala per age_band in
# _write_instance_transform) cambia. Alla prima chiamata dopo l'attivazione della cella (_groups
# vuoto) genera un individuo per ogni animale della quota.
func set_population_by_age(young: int, adult: int, old: int) -> void:
	if not _configured:
		return

	_apply_band_targets({
		GameTypes.AgeBand.YOUNG: max(young, 0),
		GameTypes.AgeBand.ADULT: max(adult, 0),
		GameTypes.AgeBand.OLD: max(old, 0),
	})


# Riconciliazione per id in tre fasi, in quest'ordine:
# 1. rimozioni: per ogni fascia in eccesso, individui scelti a caso e tolti per id;
# 2. centri-cluster: numero ricalcolato sulla popolazione FINALE (_sync_cluster_count); chi
#    apparteneva a un centro rimosso viene riassegnato (_reassign_orphaned_individuals), tutti gli
#    altri tengono il proprio centro — l'appartenenza non dipende mai dalla posizione nell'array;
# 3. nascite: ogni nuovo individuo riceve alla nascita il centro meno popolato e nasce già
#    dentro il suo raggio di comfort (_make_individual), invece che in un punto qualunque della
#    macrocella.
# Gli individui sopravvissuti mantengono id, posizione, centro e ordine relativo.
func _apply_band_targets(targets: Dictionary) -> void:
	var total_population: int = 0
	for age_band in targets:
		_remove_excess_in_band(age_band, int(targets[age_band]))
		total_population += int(targets[age_band])

	_sync_cluster_count(total_population)
	_reassign_orphaned_individuals()

	for age_band in targets:
		_add_missing_in_band(age_band, int(targets[age_band]))

	_refresh_instances()


# Se la fascia ha più individui di `target`, sceglie a caso quali rimuovere (non "l'ultimo della
# fascia", così a sparire non sono sempre i più recenti) e li toglie per id.
func _remove_excess_in_band(age_band: GameTypes.AgeBand, target: int) -> void:
	var band_ids: Array[int] = []
	for individual in _groups:
		if individual.age_band == age_band:
			band_ids.append(individual.id)
	if band_ids.size() <= target:
		return

	band_ids.shuffle()
	var ids_to_remove: Dictionary = {}
	for i in range(band_ids.size() - target):
		ids_to_remove[band_ids[i]] = true
	_remove_individuals_by_id(ids_to_remove)


# Se la fascia ha meno individui di `target`, ne genera di nuovi IN CODA a _groups, ciascuno
# assegnato al centro meno popolato in quel momento (i nuovi si distribuiscono tra i centri
# invece di accumularsi tutti sullo stesso).
func _add_missing_in_band(age_band: GameTypes.AgeBand, target: int) -> void:
	var current: int = 0
	for individual in _groups:
		if individual.age_band == age_band:
			current += 1
	if current >= target or _clusters.is_empty():
		return

	var counts := _cluster_member_counts()
	for i in range(target - current):
		var cluster_index := _least_filled_cluster(counts)
		counts[cluster_index] += 1
		_groups.append(_make_individual(age_band, cluster_index))


# Rimuove da _groups gli individui il cui id è in `ids` (Dictionary id -> true), preservando
# l'ordine dei rimanenti. Unico punto di rimozione degli individui.
func _remove_individuals_by_id(ids: Dictionary) -> void:
	if ids.is_empty():
		return
	var kept: Array = []
	for individual in _groups:
		if not ids.has(individual.id):
			kept.append(individual)
	_groups = kept


# Numero di individui attualmente istanziati (uno per animale) — letto dal riepilogo debug di
# GameScene per confrontarlo con la quota della cella.
func get_individual_count() -> int:
	return _groups.size()


# --- Selezione (AnimalSelectorController / GameScene) ---
# Gli individui restano posseduti da questo renderer: chi li legge da fuori non li modifica mai.

const SELECTION_RING_COLOR := Color(1.0, 1.0, 1.0, 0.9) # stesso bianco dell'anello umano (HumanIndividualView)
const SELECTION_RING_WIDTH: float = 0.55 # stesso spessore a schermo dell'anello umano (~0.55 px)
# L'anello sta sempre un po' fuori dalla sagoma (margine) e mai sotto un raggio minimo, così resta
# leggibile anche attorno a un cucciolo di coniglio (~1 px).
const SELECTION_RING_MARGIN_PX: float = 1.5
const SELECTION_RING_MIN_RADIUS_PX: float = 2.5
const SELECTION_RING_SEGMENTS: int = 24

# Id dell'individuo selezionato in QUESTO renderer (0 = nessuno) — l'anello è disegnato da _draw.
var _selected_individual_id: int = 0


# Array[AnimalVisualGroup] degli individui (per riferimento, sola lettura per chi lo riceve).
func get_individuals() -> Array:
	return _groups


func get_individual_by_id(individual_id: int) -> AnimalVisualGroup:
	if individual_id <= 0:
		return null
	for individual in _groups:
		if individual.id == individual_id:
			return individual
	return null


# Animali di questo renderer mostrati (toggle "animali" della barra di debug, set_animals_visible).
func are_animals_shown() -> bool:
	return _multimesh_instance != null and _multimesh_instance.visible


# Stesso test del disegno (visibility_test sulla microcella dell'individuo, vedi
# _write_instance_transform), più il toggle di visibilità: un animale che non si vede non è
# selezionabile né evidenziato.
func is_individual_visible(individual: AnimalVisualGroup) -> bool:
	return individual != null and are_animals_shown() and _is_visible_now(individual.position)


func set_selected_individual(individual_id: int) -> void:
	_selected_individual_id = individual_id
	queue_redraw()


func clear_selected_individual() -> void:
	if _selected_individual_id == 0:
		return
	_selected_individual_id = 0
	queue_redraw()


# Anello attorno all'individuo selezionato, nello stesso spazio pixel delle istanze MultiMesh
# (posizione × CELL_SIZE). Raggio dal bounding box della mesh della specie (quindi proporzionato
# alla taglia) × scala d'età, più un margine. Il nodo disegna PRIMA dei figli (il MultiMesh), quindi
# l'anello resta sotto la sagoma, che ci sta dentro.
func _draw() -> void:
	if _selected_individual_id <= 0:
		return
	var individual := get_individual_by_id(_selected_individual_id)
	if not is_individual_visible(individual):
		return
	draw_arc(
		individual.position * CELL_SIZE, _selection_ring_radius(individual), 0.0, TAU,
		SELECTION_RING_SEGMENTS, SELECTION_RING_COLOR, SELECTION_RING_WIDTH
	)


func _selection_ring_radius(individual: AnimalVisualGroup) -> float:
	var base_radius: float = 0.0
	if _multimesh != null and _multimesh.mesh != null:
		var aabb: AABB = _multimesh.mesh.get_aabb()
		base_radius = maxf(
			maxf(absf(aabb.position.x), absf(aabb.end.x)),
			maxf(absf(aabb.position.y), absf(aabb.end.y))
		)
	var age_scale: float = 1.0
	if individual.age_band >= 0 and individual.age_band < size_multiplier_by_age.size():
		age_scale = float(size_multiplier_by_age[individual.age_band])
	return maxf(base_radius * age_scale + SELECTION_RING_MARGIN_PX, SELECTION_RING_MIN_RADIUS_PX)


# --- Salvataggio (individui animali step 2) ---
# Solo per rendere identico "salva e ricarica": GameScene legge gli individui delle celle vive con
# get_individuals_snapshot prima di salvare e li ricostruisce con restore_individuals subito dopo
# la costruzione del renderer, PRIMA della prima riconciliazione con la popolazione. Direzione e
# fase del movimento a balzi non sono salvate (ripartono casuali), né i centri-cluster: questi
# vengono ricostruiti dalle posizioni salvate (vedi _cluster_restored_individuals).

static func get_next_individual_id() -> int:
	return _next_individual_id


# Mai all'indietro: un id già assegnato in questa sessione non viene riusato nemmeno dopo aver
# caricato un salvataggio con un contatore più basso.
static func set_next_individual_id(value: int) -> void:
	_next_individual_id = max(_next_individual_id, value)


# Soli tipi JSON-nativi, nell'ordine di _groups.
func get_individuals_snapshot() -> Array:
	var result: Array = []
	for individual in _groups:
		result.append({
			"id": individual.id,
			"species": individual.species_name,
			"age_band": int(individual.age_band),
			"x": individual.position.x,
			"y": individual.position.y,
		})
	return result


# Ricostruisce gli individui così come salvati (id, fascia d'età, posizione), sostituendo quelli
# presenti. `entries`: stesso formato di get_individuals_snapshot (numeri JSON anche come float).
# Il contatore degli id viene portato oltre l'id più alto ricostruito, per non riusarlo mai.
func restore_individuals(entries: Array) -> void:
	if not _configured:
		return

	_groups.clear()
	for entry in entries:
		var age_band := int(entry.get("age_band", GameTypes.AgeBand.ADULT)) as GameTypes.AgeBand
		var individual := _make_random_group(age_band)
		individual.id = int(entry.get("id", 0))
		individual.species_name = String(entry.get("species", species_name))
		individual.position = Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)))
		individual.cluster_index = -1
		if individual.id <= 0:
			# Difensivo: un individuo senza id valido ne riceve uno nuovo invece di restare id 0
			# (riservato ai centri-cluster).
			individual.id = _next_individual_id
		_next_individual_id = max(_next_individual_id, individual.id + 1)
		_groups.append(individual)

	_sync_cluster_count(_groups.size())
	_cluster_restored_individuals()
	_refresh_instances()


# Centri per individui ricostruiti da un salvataggio (i centri non sono salvati): ogni centro parte
# dalla posizione di un individuo scelto a intervalli regolari, ogni individuo va al centro più
# vicino, poi ogni centro si sposta sul baricentro dei propri membri. Così i gruppetti ripartono
# da dove gli individui si trovano già, invece di essere attratti verso centri casuali lontani.
func _cluster_restored_individuals() -> void:
	if _clusters.is_empty() or _groups.is_empty():
		return

	var group_count: int = _groups.size()
	var cluster_count: int = _clusters.size()
	for c in range(cluster_count):
		_clusters[c].position = _groups[(c * group_count) / cluster_count].position

	var sums: Array[Vector2] = []
	sums.resize(cluster_count)
	sums.fill(Vector2.ZERO)
	var counts: Array[int] = []
	counts.resize(cluster_count)
	counts.fill(0)
	for individual in _groups:
		var best: int = 0
		var best_distance: float = INF
		for c in range(cluster_count):
			var distance: float = individual.position.distance_squared_to(_clusters[c].position)
			if distance < best_distance:
				best_distance = distance
				best = c
		individual.cluster_index = best
		sums[best] += individual.position
		counts[best] += 1

	for c in range(cluster_count):
		if counts[c] > 0:
			_clusters[c].position = sums[c] / float(counts[c])


func _refresh_instances() -> void:
	_multimesh.instance_count = _groups.size()
	for i in range(_groups.size()):
		_write_instance_transform(i, _groups[i])


# Numero di centri per la popolazione (formula: ceil(popolazione/max_individuals_per_cluster), mai
# più degli individui). Nuovi centri in coda in posizione casuale; i centri in eccesso vengono tolti
# dalla coda — i loro membri restano "orfani" (cluster_index fuori range) finché
# _reassign_orphaned_individuals non li riassegna. Nessun altro individuo cambia centro.
func _sync_cluster_count(total_population: int) -> void:
	if total_population <= 0:
		_clusters.clear()
		return

	var num_clusters: int = clampi(ceili(float(total_population) / max_individuals_per_cluster), 1, total_population)
	while _clusters.size() < num_clusters:
		_clusters.append(_make_random_group())
	if _clusters.size() > num_clusters:
		_clusters.resize(num_clusters)


# Riassegna SOLO gli individui senza un centro valido (il loro centro è stato rimosso), ciascuno al
# centro meno popolato. Chi ha già un centro valido non viene mai toccato.
func _reassign_orphaned_individuals() -> void:
	if _clusters.is_empty():
		return
	var counts := _cluster_member_counts()
	for individual in _groups:
		if individual.cluster_index >= 0 and individual.cluster_index < _clusters.size():
			continue
		var cluster_index := _least_filled_cluster(counts)
		counts[cluster_index] += 1
		individual.cluster_index = cluster_index


func _cluster_member_counts() -> Array[int]:
	var counts: Array[int] = []
	counts.resize(_clusters.size())
	counts.fill(0)
	for individual in _groups:
		if individual.cluster_index >= 0 and individual.cluster_index < counts.size():
			counts[individual.cluster_index] += 1
	return counts


# A parità di membri vince l'indice più basso.
func _least_filled_cluster(counts: Array[int]) -> int:
	var best: int = 0
	for i in range(1, counts.size()):
		if counts[i] < counts[best]:
			best = i
	return best


# Nuovo individuo: id progressivo mai riassegnato (vedi _next_individual_id), specie di questo
# renderer, centro assegnato UNA volta qui e poi fisso (cambia solo se quel centro viene rimosso),
# posizione casuale DENTRO il raggio di comfort del proprio centro (distribuzione uniforme sul
# disco, limitata ai bordi della macrocella) — nasce già nel suo gruppetto.
func _make_individual(age_band: GameTypes.AgeBand, cluster_index: int) -> AnimalVisualGroup:
	var individual := _make_random_group(age_band)
	individual.id = _next_individual_id
	_next_individual_id += 1
	individual.species_name = species_name
	individual.cluster_index = cluster_index
	individual.position = _random_point_near_cluster(cluster_index)
	return individual


func _random_point_near_cluster(cluster_index: int) -> Vector2:
	var center: Vector2 = _clusters[cluster_index].position
	var offset := Vector2.RIGHT.rotated(randf_range(0.0, TAU)) * cluster_comfort_radius * sqrt(randf())
	var point := center + offset
	return Vector2(clampf(point.x, 0.0, World.WIDTH), clampf(point.y, 0.0, World.HEIGHT))


# Istanza con posizione/direzione/fase casuali e NESSUNA identità (id 0) — usata così com'è per i
# centri-cluster invisibili, e come base da _make_individual per gli individui veri.
func _make_random_group(age_band: GameTypes.AgeBand = GameTypes.AgeBand.ADULT) -> AnimalVisualGroup:
	var position := Vector2(randf_range(0.0, World.WIDTH), randf_range(0.0, World.HEIGHT))
	var direction := Vector2.RIGHT.rotated(randf_range(0.0, TAU))
	var group := AnimalVisualGroup.new(position, direction)
	group.age_band = age_band
	_randomize_group_phase(group)
	return group


# Stato/timer iniziale scelto a caso (non "tutti freschi in MOVING") così un gruppo appena
# creato — sia all'apertura della scena, sia aggiunto a metà sessione da una popolazione che
# cresce — non risulta sincronizzato con quelli già esistenti. Irrilevante per i centri-cluster
# (che ignorano questi campi), ma innocuo lasciarlo girare anche per loro.
func _randomize_group_phase(group: AnimalVisualGroup) -> void:
	if randf() < 0.5:
		group.macro_phase = AnimalVisualGroup.MacroPhase.MOVING
		group.macro_phase_timer = randf_range(movement_phase_duration_min, movement_phase_duration_max)
		if randf() < 0.5:
			group.micro_phase = AnimalVisualGroup.MicroPhase.HOPPING
			group.micro_phase_timer = randf_range(hop_duration_min, hop_duration_max)
		else:
			group.micro_phase = AnimalVisualGroup.MicroPhase.HOP_PAUSE
			group.micro_phase_timer = randf_range(hop_pause_min, hop_pause_max)
	else:
		group.macro_phase = AnimalVisualGroup.MacroPhase.RESTING
		group.macro_phase_timer = randf_range(rest_phase_duration_min, rest_phase_duration_max)


# Avanza la macchina a stati a due livelli di un gruppo di un frame. Chiamata sempre (anche
# quando il gruppo non si muove), così i timer procedono indipendentemente dal fatto che questo
# frame produca o meno uno spostamento — vedi _process per la regola che decide il movimento.
func _update_group_phase(group: AnimalVisualGroup, delta: float) -> void:
	group.macro_phase_timer -= delta
	if group.macro_phase == AnimalVisualGroup.MacroPhase.MOVING:
		group.micro_phase_timer -= delta
		if group.micro_phase_timer <= 0.0:
			if group.micro_phase == AnimalVisualGroup.MicroPhase.HOPPING:
				group.micro_phase = AnimalVisualGroup.MicroPhase.HOP_PAUSE
				group.micro_phase_timer = randf_range(hop_pause_min, hop_pause_max)
			else:
				group.micro_phase = AnimalVisualGroup.MicroPhase.HOPPING
				group.micro_phase_timer = randf_range(hop_duration_min, hop_duration_max)
		if group.macro_phase_timer <= 0.0:
			group.macro_phase = AnimalVisualGroup.MacroPhase.RESTING
			group.macro_phase_timer = randf_range(rest_phase_duration_min, rest_phase_duration_max)
	else:
		if group.macro_phase_timer <= 0.0:
			group.macro_phase = AnimalVisualGroup.MacroPhase.MOVING
			group.macro_phase_timer = randf_range(movement_phase_duration_min, movement_phase_duration_max)
			group.micro_phase = AnimalVisualGroup.MicroPhase.HOPPING
			group.micro_phase_timer = randf_range(hop_duration_min, hop_duration_max)


# Livello 1: movimento casuale semplice, non un vero sistema di IA. I cluster (centri invisibili)
# vagano in modo continuo (deriva + rimbalzo, come sempre); i gruppi disegnati invece si
# muovono a balzi (vedi _update_group_phase) — deriva della direzione e attrazione verso il
# cluster restano sempre attive anche da fermi, solo l'avanzamento è gated dalla fase HOPPING.
func _process(real_delta: float) -> void:
	# Anello di selezione (vedi _draw): ridisegnato a ogni frame finché c'è una selezione, così segue
	# l'individuo che si muove e sparisce da solo se l'individuo non esiste più o non è più visibile.
	if _selected_individual_id > 0:
		queue_redraw()
	if not _configured or _groups.is_empty():
		return
	if clock != null and not clock.is_playing:
		# In pausa nessuno si muove, ma la visibilità fog of war può cambiare comunque (es. un
		# edificio piazzato a gioco fermo): le trasformazioni si riscrivono lo stesso, così il
		# filtro di visibilità resta per-frame anche qui.
		if visibility_test.is_valid():
			for i in range(_groups.size()):
				_write_instance_transform(i, _groups[i])
		return

	# Tempo di gioco (2026-09-25): tutto il movimento sotto — spostamenti, deriva della direzione,
	# guinzaglio e timer delle fasi (_update_group_phase) — usa la frazione di giorno di gioco
	# trascorsa in questo frame, come HumanIndividualMovementService per gli umani: la velocità degli
	# animali rispetto a un umano non cambia con la velocità di gioco (1x/2x/4x/8x).
	var delta := _game_day_delta(real_delta)

	# I cluster avanzano per primi (stessa logica di sempre) così i gruppi, elaborati subito
	# dopo, tirano verso il centro già aggiornato di questo frame invece che verso quello vecchio.
	for cluster in _clusters:
		cluster.direction = cluster.direction.rotated(randf_range(-turn_rate, turn_rate) * delta)
		cluster.position += cluster.direction * move_speed * delta
		_bounce_at_bounds(cluster)

	for i in range(_groups.size()):
		var group: AnimalVisualGroup = _groups[i]
		group.direction = group.direction.rotated(randf_range(-turn_rate, turn_rate) * delta)
		_apply_cluster_attraction(group, delta)
		_update_group_phase(group, delta)
		if group.macro_phase == AnimalVisualGroup.MacroPhase.MOVING and group.micro_phase == AnimalVisualGroup.MicroPhase.HOPPING:
			group.position += group.direction * hop_speed * delta
			_bounce_at_bounds(group)
		_write_instance_transform(i, group)


# Frazione di giorno di gioco corrispondente a `real_delta` secondi reali: dal clock se assegnato
# (0 in pausa, scala con la velocità di gioco), altrimenti come a velocità 1x — contesti senza
# GameClockController si muovono come prima di questa conversione.
func _game_day_delta(real_delta: float) -> float:
	if clock != null:
		return clock.get_game_day_delta(real_delta)
	return real_delta / GameClockController.SECONDS_PER_DAY_BY_SPEED[GameClockController.Speed.X1]


# Guinzaglio elastico verso il centro del proprio cluster: nessuna trazione entro
# cluster_comfort_radius (i gruppi possono vagare liberamente vicino al centro), oltre quella
# soglia la direzione viene reindirizzata gradualmente (slerp, pesato dallo sforamento) verso il
# centro — non un vero steering behavior, solo un bias sulla stessa deriva casuale di sempre.
func _apply_cluster_attraction(group: AnimalVisualGroup, delta: float) -> void:
	if _clusters.is_empty():
		return
	var cluster: AnimalVisualGroup = _clusters[group.cluster_index]
	var offset: Vector2 = group.position - cluster.position
	var distance: float = offset.length()
	if distance <= cluster_comfort_radius:
		return
	var pull_direction: Vector2 = -offset / distance
	var pull_strength: float = clamp((distance - cluster_comfort_radius) / cluster_comfort_radius, 0.0, 1.0)
	var pull_weight: float = clamp(pull_strength * cluster_attraction_strength * delta, 0.0, 1.0)
	group.direction = group.direction.slerp(pull_direction, pull_weight)


func _bounce_at_bounds(group: AnimalVisualGroup) -> void:
	if group.position.x < 0.0:
		group.position.x = 0.0
		group.direction.x = abs(group.direction.x)
	elif group.position.x > World.WIDTH:
		group.position.x = World.WIDTH
		group.direction.x = -abs(group.direction.x)

	if group.position.y < 0.0:
		group.position.y = 0.0
		group.direction.y = abs(group.direction.y)
	elif group.position.y > World.HEIGHT:
		group.position.y = World.HEIGHT
		group.direction.y = -abs(group.direction.y)


# La scala per age_band (size_multiplier_by_age) è applicata moltiplicando direttamente i
# vettori di base x/y del transform (assi locali del mesh), MAI tramite Transform2D.scaled() —
# quel metodo storicamente in Godot ha una semantica ambigua su cosa tocca esattamente
# (basis e/o origin a seconda della versione); moltiplicare x/y a mano è inequivocabile: scala
# solo gli assi locali, mai la posizione già scritta in origin.
func _write_instance_transform(index: int, group: AnimalVisualGroup) -> void:
	if not _is_visible_now(group.position):
		# Istanza nascosta: basi a zero (nessun triangolo visibile), origine alla posizione vera.
		_multimesh.set_instance_transform_2d(index, Transform2D(Vector2.ZERO, Vector2.ZERO, group.position * CELL_SIZE))
		return
	var transform := Transform2D(group.direction.angle(), group.position * CELL_SIZE)
	var scale: float = 1.0
	if group.age_band >= 0 and group.age_band < size_multiplier_by_age.size():
		scale = float(size_multiplier_by_age[group.age_band])
	transform.x *= scale
	transform.y *= scale
	_multimesh.set_instance_transform_2d(index, transform)


# Microcella dell'animale (posizione float 0..100, il bordo 100.0 ricade nell'ultima microcella)
# interrogata con visibility_test — vedi il campo.
func _is_visible_now(position: Vector2) -> bool:
	if not visibility_test.is_valid():
		return true
	var cell := Vector2i(
		clampi(int(floor(position.x)), 0, World.WIDTH - 1),
		clampi(int(floor(position.y)), 0, World.HEIGHT - 1)
	)
	return bool(visibility_test.call(cell))


# Corpo a goccia (ventaglio con raggio Y assottigliato verso il muso e allargato verso i
# fianchi) + due orecchie lunghe protese in avanti oltre il muso + coda (piccolo cerchio)
# accumulati in un'unica sessione SurfaceTool con un UNICO colore uniforme, cosicché ogni
# specie resti un solo MultiMesh/una sola draw call indipendentemente dal numero di gruppi.
# Asse locale +X = direzione di marcia (stessa convenzione di FISH in MicroCellRenderer).
# Chiamata dal nodo che istanzia AnimalGroupRenderer (oggi MacroCellScene), mai da questa
# classe: il risultato va passato in configure() tramite params["mesh"]. I punti geometrici
# (get_rabbit_silhouette_geometry sotto) sono condivisi con AnimalSilhouetteIcon (icona del
# filtro Fauna in WorldInfoPanel) — un solo posto definisce "che forma ha un coniglio", non
# due copie della stessa formula che potrebbero disallinearsi in futuro.
static func build_rabbit_mesh(
	body_length: float, body_width: float, ear_length: float, ear_width: float, color: Color
) -> ArrayMesh:
	return _build_mesh_from_geometry(
		get_rabbit_silhouette_geometry(body_length, body_width, ear_length, ear_width), color,
		_field_scale(RABBIT_FIELD_BODY_LENGTH_PX, body_length)
	)


# Sagoma DEER: stesso schema costruttivo di build_rabbit_mesh sopra (corpo a ventaglio + 2
# orecchie + coda, unico colore, unica SurfaceTool) ma con proporzioni/angoli propri (vedi
# costanti DEER_* in cima al file) — corpo quasi uniforme invece che a goccia, orecchie corte
# "all'erta" invece che lunghe e protese in avanti, coda più piccola. Stessa convenzione di
# asse locale +X = direzione di marcia.
static func build_deer_mesh(
	body_length: float, body_width: float, ear_length: float, ear_width: float, color: Color
) -> ArrayMesh:
	return _build_mesh_from_geometry(
		get_deer_silhouette_geometry(body_length, body_width, ear_length, ear_width), color,
		_field_scale(DEER_FIELD_BODY_LENGTH_PX, body_length)
	)


# Sagoma BOAR: stesso schema costruttivo di build_rabbit_mesh/build_deer_mesh sopra, ma con
# body_front_width_ratio > body_rear_width_ratio (vedi costanti BOAR_* in cima al file) — l'unica
# specie oggi con la spalla più larga del muso invece che il contrario.
static func build_boar_mesh(
	body_length: float, body_width: float, ear_length: float, ear_width: float, color: Color
) -> ArrayMesh:
	return _build_mesh_from_geometry(
		get_boar_silhouette_geometry(body_length, body_width, ear_length, ear_width), color,
		_field_scale(BOAR_FIELD_BODY_LENGTH_PX, body_length)
	)


# Sagoma TARPAN: stesso schema costruttivo delle altre, corpo più snello/allungato (vedi
# costanti TARPAN_* in cima al file) — la prima specie erbivora "vera" oltre a deer, distinta da
# quest'ultima per proporzioni più filiformi e orecchie più verticali.
static func build_tarpan_mesh(
	body_length: float, body_width: float, ear_length: float, ear_width: float, color: Color
) -> ArrayMesh:
	return _build_mesh_from_geometry(
		get_tarpan_silhouette_geometry(body_length, body_width, ear_length, ear_width), color,
		_field_scale(TARPAN_FIELD_BODY_LENGTH_PX, body_length)
	)


# Sagoma WILD_DONKEY: stesso schema costruttivo di tarpan (equide, coda ellittica a due raggi),
# proporzioni proprie (vedi costanti WILD_DONKEY_* in cima al file) — corpo più piccolo e tozzo,
# orecchie molto più lunghe in proporzione.
static func build_wild_donkey_mesh(
	body_length: float, body_width: float, ear_length: float, ear_width: float, color: Color
) -> ArrayMesh:
	return _build_mesh_from_geometry(
		get_wild_donkey_silhouette_geometry(body_length, body_width, ear_length, ear_width), color,
		_field_scale(WILD_DONKEY_FIELD_BODY_LENGTH_PX, body_length)
	)


# Sagoma AUROCHS: stesso schema costruttivo delle altre. Lo slot "orecchie" della pipeline
# generica è qui riusato per le corna (vedi costanti AUROCHS_EAR_* in cima al file) — nessuna
# nuova geometria introdotta, solo proporzioni/angoli diversi passati agli stessi parametri.
static func build_aurochs_mesh(
	body_length: float, body_width: float, ear_length: float, ear_width: float, color: Color
) -> ArrayMesh:
	return _build_mesh_from_geometry(
		get_aurochs_silhouette_geometry(body_length, body_width, ear_length, ear_width), color,
		_field_scale(AUROCHS_FIELD_BODY_LENGTH_PX, body_length)
	)


# Sagoma MOUFLON: stesso schema costruttivo delle altre. Lo slot "orecchie" della pipeline
# generica è qui riusato per le corna, come per aurochs, ma angolate diversamente (vedi
# costanti MOUFLON_EAR_* in cima al file) per leggersi come corna che curvano all'indietro
# invece che protese in avanti.
static func build_mouflon_mesh(
	body_length: float, body_width: float, ear_length: float, ear_width: float, color: Color
) -> ArrayMesh:
	return _build_mesh_from_geometry(
		get_mouflon_silhouette_geometry(body_length, body_width, ear_length, ear_width), color,
		_field_scale(MOUFLON_FIELD_BODY_LENGTH_PX, body_length)
	)


# Sagoma BEZOAR: stesso schema costruttivo delle altre. Lo slot "orecchie" della pipeline
# generica è qui riusato per le corna, come per aurochs/mouflon, ma con angolo vicino ai 90°
# (vedi costanti BEZOAR_EAR_* in cima al file) per leggersi come corna dritte invece che
# nettamente sweep in avanti o all'indietro.
static func build_bezoar_mesh(
	body_length: float, body_width: float, ear_length: float, ear_width: float, color: Color
) -> ArrayMesh:
	return _build_mesh_from_geometry(
		get_bezoar_silhouette_geometry(body_length, body_width, ear_length, ear_width), color,
		_field_scale(BEZOAR_FIELD_BODY_LENGTH_PX, body_length)
	)


# Sagoma WOLF: stesso schema costruttivo delle altre (la pipeline non distingue predatori da
# prede) — corpo da canide con taper marcato (vedi costanti WOLF_* in cima al file), orecchie
# corte a punta, coda ellittica allungata (unica specie non-equide a riusare quel meccanismo a
# due raggi, vedi commento su WOLF_TAIL_RADIUS_X/Y).
static func build_wolf_mesh(
	body_length: float, body_width: float, ear_length: float, ear_width: float, color: Color
) -> ArrayMesh:
	return _build_mesh_from_geometry(
		get_wolf_silhouette_geometry(body_length, body_width, ear_length, ear_width), color,
		_field_scale(WOLF_FIELD_BODY_LENGTH_PX, body_length)
	)


# Sagoma PARTRIDGE: stesso schema costruttivo delle altre. Lo slot "orecchie" della pipeline
# generica è qui riusato per le ALI RIPIEGATE (vedi costanti PARTRIDGE_* in cima al file), prima
# specie non-mammifero della pipeline — nessuna nuova geometria introdotta, solo proporzioni/
# angoli diversi passati agli stessi parametri, come già per corna/orecchie delle altre specie.
static func build_partridge_mesh(
	body_length: float, body_width: float, ear_length: float, ear_width: float, color: Color
) -> ArrayMesh:
	return _build_mesh_from_geometry(
		get_partridge_silhouette_geometry(body_length, body_width, ear_length, ear_width), color,
		_field_scale(PARTRIDGE_FIELD_BODY_LENGTH_PX, body_length)
	)


# Pubbliche (non prefissate _, a differenza delle altre helper statiche sotto): consumate anche
# da AnimalSilhouetteIcon, fuori da questa classe. Ritornano i punti 2D grezzi (corpo, le due
# orecchie come triangoli [base_a, base_b, tip], centro/raggio della coda) SENZA passare per una
# SurfaceTool — chi li consuma decide come disegnarli (build_*_mesh sotto li accumula in una
# ArrayMesh per il MultiMesh sul campo; AnimalSilhouetteIcon li disegna direttamente con _draw()).
static func get_rabbit_silhouette_geometry(
	body_length: float, body_width: float, ear_length: float, ear_width: float
) -> Dictionary:
	return _get_silhouette_geometry(
		body_length, body_width, ear_length, ear_width,
		RABBIT_BODY_REAR_WIDTH_RATIO, RABBIT_BODY_FRONT_WIDTH_RATIO,
		RABBIT_EAR_ANCHOR_RATIO, RABBIT_EAR_ANCHOR_LATERAL_RATIO, RABBIT_EAR_ANGLE_FROM_HEADING,
		RABBIT_TAIL_ANCHOR_RATIO, RABBIT_TAIL_RADIUS, RABBIT_TAIL_RADIUS
	)


static func get_deer_silhouette_geometry(
	body_length: float, body_width: float, ear_length: float, ear_width: float
) -> Dictionary:
	return _get_silhouette_geometry(
		body_length, body_width, ear_length, ear_width,
		DEER_BODY_REAR_WIDTH_RATIO, DEER_BODY_FRONT_WIDTH_RATIO,
		DEER_EAR_ANCHOR_RATIO, DEER_EAR_ANCHOR_LATERAL_RATIO, DEER_EAR_ANGLE_FROM_HEADING,
		DEER_TAIL_ANCHOR_RATIO, DEER_TAIL_RADIUS, DEER_TAIL_RADIUS
	)


static func get_boar_silhouette_geometry(
	body_length: float, body_width: float, ear_length: float, ear_width: float
) -> Dictionary:
	return _get_silhouette_geometry(
		body_length, body_width, ear_length, ear_width,
		BOAR_BODY_REAR_WIDTH_RATIO, BOAR_BODY_FRONT_WIDTH_RATIO,
		BOAR_EAR_ANCHOR_RATIO, BOAR_EAR_ANCHOR_LATERAL_RATIO, BOAR_EAR_ANGLE_FROM_HEADING,
		BOAR_TAIL_ANCHOR_RATIO, BOAR_TAIL_RADIUS, BOAR_TAIL_RADIUS
	)


static func get_tarpan_silhouette_geometry(
	body_length: float, body_width: float, ear_length: float, ear_width: float
) -> Dictionary:
	return _get_silhouette_geometry(
		body_length, body_width, ear_length, ear_width,
		TARPAN_BODY_REAR_WIDTH_RATIO, TARPAN_BODY_FRONT_WIDTH_RATIO,
		TARPAN_EAR_ANCHOR_RATIO, TARPAN_EAR_ANCHOR_LATERAL_RATIO, TARPAN_EAR_ANGLE_FROM_HEADING,
		TARPAN_TAIL_ANCHOR_RATIO, TARPAN_TAIL_RADIUS_X, TARPAN_TAIL_RADIUS_Y
	)


static func get_wild_donkey_silhouette_geometry(
	body_length: float, body_width: float, ear_length: float, ear_width: float
) -> Dictionary:
	return _get_silhouette_geometry(
		body_length, body_width, ear_length, ear_width,
		WILD_DONKEY_BODY_REAR_WIDTH_RATIO, WILD_DONKEY_BODY_FRONT_WIDTH_RATIO,
		WILD_DONKEY_EAR_ANCHOR_RATIO, WILD_DONKEY_EAR_ANCHOR_LATERAL_RATIO, WILD_DONKEY_EAR_ANGLE_FROM_HEADING,
		WILD_DONKEY_TAIL_ANCHOR_RATIO, WILD_DONKEY_TAIL_RADIUS_X, WILD_DONKEY_TAIL_RADIUS_Y
	)


static func get_aurochs_silhouette_geometry(
	body_length: float, body_width: float, ear_length: float, ear_width: float
) -> Dictionary:
	return _get_silhouette_geometry(
		body_length, body_width, ear_length, ear_width,
		AUROCHS_BODY_REAR_WIDTH_RATIO, AUROCHS_BODY_FRONT_WIDTH_RATIO,
		AUROCHS_EAR_ANCHOR_RATIO, AUROCHS_EAR_ANCHOR_LATERAL_RATIO, AUROCHS_EAR_ANGLE_FROM_HEADING,
		AUROCHS_TAIL_ANCHOR_RATIO, AUROCHS_TAIL_RADIUS, AUROCHS_TAIL_RADIUS
	)


static func get_mouflon_silhouette_geometry(
	body_length: float, body_width: float, ear_length: float, ear_width: float
) -> Dictionary:
	return _get_silhouette_geometry(
		body_length, body_width, ear_length, ear_width,
		MOUFLON_BODY_REAR_WIDTH_RATIO, MOUFLON_BODY_FRONT_WIDTH_RATIO,
		MOUFLON_EAR_ANCHOR_RATIO, MOUFLON_EAR_ANCHOR_LATERAL_RATIO, MOUFLON_EAR_ANGLE_FROM_HEADING,
		MOUFLON_TAIL_ANCHOR_RATIO, MOUFLON_TAIL_RADIUS, MOUFLON_TAIL_RADIUS
	)


static func get_bezoar_silhouette_geometry(
	body_length: float, body_width: float, ear_length: float, ear_width: float
) -> Dictionary:
	return _get_silhouette_geometry(
		body_length, body_width, ear_length, ear_width,
		BEZOAR_BODY_REAR_WIDTH_RATIO, BEZOAR_BODY_FRONT_WIDTH_RATIO,
		BEZOAR_EAR_ANCHOR_RATIO, BEZOAR_EAR_ANCHOR_LATERAL_RATIO, BEZOAR_EAR_ANGLE_FROM_HEADING,
		BEZOAR_TAIL_ANCHOR_RATIO, BEZOAR_TAIL_RADIUS, BEZOAR_TAIL_RADIUS
	)


static func get_wolf_silhouette_geometry(
	body_length: float, body_width: float, ear_length: float, ear_width: float
) -> Dictionary:
	return _get_silhouette_geometry(
		body_length, body_width, ear_length, ear_width,
		WOLF_BODY_REAR_WIDTH_RATIO, WOLF_BODY_FRONT_WIDTH_RATIO,
		WOLF_EAR_ANCHOR_RATIO, WOLF_EAR_ANCHOR_LATERAL_RATIO, WOLF_EAR_ANGLE_FROM_HEADING,
		WOLF_TAIL_ANCHOR_RATIO, WOLF_TAIL_RADIUS_X, WOLF_TAIL_RADIUS_Y
	)


static func get_partridge_silhouette_geometry(
	body_length: float, body_width: float, ear_length: float, ear_width: float
) -> Dictionary:
	return _get_silhouette_geometry(
		body_length, body_width, ear_length, ear_width,
		PARTRIDGE_BODY_REAR_WIDTH_RATIO, PARTRIDGE_BODY_FRONT_WIDTH_RATIO,
		PARTRIDGE_EAR_ANCHOR_RATIO, PARTRIDGE_EAR_ANCHOR_LATERAL_RATIO, PARTRIDGE_EAR_ANGLE_FROM_HEADING,
		PARTRIDGE_TAIL_ANCHOR_RATIO, PARTRIDGE_TAIL_RADIUS, PARTRIDGE_TAIL_RADIUS
	)


static func _get_silhouette_geometry(
	body_length: float, body_width: float, ear_length: float, ear_width: float,
	body_rear_width_ratio: float, body_front_width_ratio: float,
	ear_anchor_ratio: float, ear_anchor_lateral_ratio: float, ear_angle_from_heading: float,
	tail_anchor_ratio: float, tail_radius_x: float, tail_radius_y: float
) -> Dictionary:
	var body_points := PackedVector2Array()
	for i in range(BODY_SEGMENTS):
		var angle: float = (float(i) / float(BODY_SEGMENTS)) * TAU
		# t: 0 sul punto più posteriore (-X), 1 sul punto più anteriore/muso (+X) — modula il
		# raggio Y così il corpo si legge come una goccia affusolata invece di un'ellisse.
		var t: float = (cos(angle) + 1.0) / 2.0
		var width_scale: float = lerp(body_rear_width_ratio, body_front_width_ratio, t)
		body_points.append(Vector2(cos(angle) * body_length, sin(angle) * body_width * width_scale))

	var anchor_x: float = body_length * ear_anchor_ratio
	var ears: Array = []
	for side in [-1.0, 1.0]:
		var ear_dir: Vector2 = Vector2.RIGHT.rotated(side * ear_angle_from_heading)
		var anchor := Vector2(anchor_x, side * body_width * ear_anchor_lateral_ratio)
		var perpendicular := ear_dir.rotated(PI / 2.0)
		var base_a := anchor - perpendicular * (ear_width / 2.0)
		var base_b := anchor + perpendicular * (ear_width / 2.0)
		var tip := anchor + ear_dir * ear_length
		ears.append([base_a, base_b, tip])

	return {
		"body_points": body_points,
		"ears": ears,
		"tail_center": Vector2(-body_length * tail_anchor_ratio, 0.0),
		# Due raggi invece di uno: X lungo l'asse del corpo (avanti/indietro), Y trasversale —
		# stesso principio già usato dal corpo sopra (body_length su X, body_width*width_scale su
		# Y). Un cerchio perfetto (rabbit/deer/boar) è semplicemente il caso radius_x==radius_y;
		# solo tarpan oggi li differenzia per una coda allungata invece che un batuffolo tondo.
		"tail_radius_x": tail_radius_x,
		"tail_radius_y": tail_radius_y,
	}


# Dimensione sul campo (2026-09-25, richiesta utente — scala grafica umani/animali): lunghezza TOTALE
# del corpo di un adulto, in pixel a schermo (10 px = 1 microcella; un umano adulto misura ~2.2 px
# nella direzione di marcia, vedi HumanIndividualView.BASE_DRAW_SCALE). Sostituisce la vecchia scala
# unica WORLD_MESH_SCALE (0.6): ogni build_*_mesh ricava la propria scala come
# lunghezza_px / (2 × <SPECIE>_BODY_LENGTH) — le costanti BODY_LENGTH sono SEMIASSI — e la applica a
# TUTTA la geometria (corpo, larghezza, orecchie/corna/ali, coda), quindi la sagoma non si deforma.
# Le costanti di forma per specie restano invariate: sono condivise con AnimalSilhouetteIcon (icona
# del filtro Fauna), che adatta la sagoma al proprio riquadro e quindi non cambia dimensione.
# La scala per fascia d'età (size_multiplier_by_age) si applica sopra, per istanza.
const PARTRIDGE_FIELD_BODY_LENGTH_PX: float = 1.8
const RABBIT_FIELD_BODY_LENGTH_PX: float = 2.0
const BEZOAR_FIELD_BODY_LENGTH_PX: float = 3.5
const MOUFLON_FIELD_BODY_LENGTH_PX: float = 3.5
const BOAR_FIELD_BODY_LENGTH_PX: float = 4.5
const WOLF_FIELD_BODY_LENGTH_PX: float = 4.5
const DEER_FIELD_BODY_LENGTH_PX: float = 5.0
const WILD_DONKEY_FIELD_BODY_LENGTH_PX: float = 6.0
const TARPAN_FIELD_BODY_LENGTH_PX: float = 6.0
const AUROCHS_FIELD_BODY_LENGTH_PX: float = 7.0


# Scala che porta un corpo di semiasse `body_length` (unità di forma) a `field_body_length_px` pixel.
static func _field_scale(field_body_length_px: float, body_length: float) -> float:
	if body_length <= 0.0:
		return 1.0
	return field_body_length_px / (2.0 * body_length)


static func _build_mesh_from_geometry(geometry: Dictionary, color: Color, scale: float) -> ArrayMesh:
	var scaled := _scale_geometry(geometry, scale)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(color)

	_append_fan_triangles(st, scaled["body_points"])
	for ear in scaled["ears"]:
		_append_triangle(st, ear[0], ear[1], ear[2])

	var tail_center: Vector2 = scaled["tail_center"]
	var tail_radius_x: float = scaled["tail_radius_x"]
	var tail_radius_y: float = scaled["tail_radius_y"]
	var tail_points := PackedVector2Array()
	for i in range(TAIL_SEGMENTS):
		var angle: float = (float(i) / float(TAIL_SEGMENTS)) * TAU
		tail_points.append(tail_center + Vector2(cos(angle) * tail_radius_x, sin(angle) * tail_radius_y))
	_append_fan_triangles(st, tail_points, tail_center)

	return st.commit()


# Scala uniforme di tutta la geometria (corpo, orecchie/corna/ali, coda) di uno stesso fattore,
# così le proporzioni relative tra le parti di una specie — e tra specie diverse (un aurochs
# resta più grande di un coniglio) — restano invariate, cambia solo la scala assoluta.
static func _scale_geometry(geometry: Dictionary, scale: float) -> Dictionary:
	var scaled_body := PackedVector2Array()
	for point in geometry["body_points"]:
		scaled_body.append(point * scale)

	var scaled_ears: Array = []
	for ear in geometry["ears"]:
		scaled_ears.append([ear[0] * scale, ear[1] * scale, ear[2] * scale])

	return {
		"body_points": scaled_body,
		"ears": scaled_ears,
		"tail_center": geometry["tail_center"] * scale,
		"tail_radius_x": geometry["tail_radius_x"] * scale,
		"tail_radius_y": geometry["tail_radius_y"] * scale,
	}


static func _append_fan_triangles(st: SurfaceTool, points: PackedVector2Array, center: Vector2 = Vector2.ZERO) -> void:
	var center_v3 := Vector3(center.x, center.y, 0.0)
	var count := points.size()
	for i in range(count):
		var a := Vector3(points[i].x, points[i].y, 0.0)
		var b := Vector3(points[(i + 1) % count].x, points[(i + 1) % count].y, 0.0)
		st.add_vertex(center_v3)
		st.add_vertex(a)
		st.add_vertex(b)


static func _append_triangle(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2) -> void:
	st.add_vertex(Vector3(a.x, a.y, 0.0))
	st.add_vertex(Vector3(b.x, b.y, 0.0))
	st.add_vertex(Vector3(c.x, c.y, 0.0))
