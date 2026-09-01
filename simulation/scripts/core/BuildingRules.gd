class_name BuildingRules
extends Resource

# Dati statici per un TIPO di edificio (una .tres per tipo, es. "hut.tres", "granary.tres") —
# stesso schema di AnimalRules per le specie animali: qui vive solo la DEFINIZIONE, mai lo stato
# di una singola istanza piazzata sulla mappa (quello è Building.gd). Caricata per convenzione da
# BuildingCalculator, stesso principio di AnimalCalculator/ResourceCalculator.

@export var building_name: String = "" # chiave tr(), es. "building_hut" — mai una stringa già tradotta qui

# Livello tecnologico minimo per poter costruire questo edificio — 0 = sempre disponibile. Il
# confronto vero ("la popolazione al livello N può costruire tutto fino a N") vive altrove, quando
# esisterà un tracciamento reale del progresso tecnologico: qui è solo il dato, non ancora
# consultato da nessuna logica.
@export var tech_level_required: int = 0

# Tempo minimo di processo, indipendente dalla forza lavoro sotto — anche con manodopera
# sufficiente a completare il lavoro in un solo giorno, la costruzione non può comunque finire
# prima di questi giorni (fasi che non si parallelizzano: es. una parete deve asciugare). Non
# ancora consultato da nessuna logica (vedi required_labor sotto per lo stesso discorso) — in
# futuro il completamento richiederà ENTRAMBE le soglie soddisfatte, non solo questa.
@export var min_construction_days: int = 5

# Quantità totale di lavoro necessaria per completare la costruzione, nella stessa unità del
# "daily" che verrà aggiunto alla futura classe Uomo (es. capanna=500, un uomo con daily=50 ci
# mette 10 giorni da solo, dieci uomini un giorno solo — ma vedi min_construction_days sopra per
# il floor che comunque si applica). Presuppone una popolazione di lavoratori assegnabile che oggi
# non esiste ancora (solo l'Individual del player, nessuna popolazione NPC umana) — per ora è solo
# il dato, non consultato da nessuna logica, stesso principio degli altri campi "futuri" qui sotto.
@export var required_labor: int = 0

# -1 = non degrada mai (nessuna scadenza per età) — mai 0, che si leggerebbe come "degrada subito".
@export var lifespan_years: int = -1

@export var storage_capacity: int = 0

# Nome risorsa (stringa libera per ora, es. "wood"/"stick"/"stone"/"iron" — nessun enum dedicato
# finché non esiste un vero inventario/economia) -> quantità richiesta per completare la
# costruzione.
@export var required_materials: Dictionary = {}

@export var max_durability: int = 50

# Spazio occupato in microcelle (stessa unità di MacroCellState.TOTAL_SPACE/dedicated_space per la
# vegetazione) — quanto della macrocella ospitante viene sottratto al budget condiviso quando
# l'edificio è completo. Non ancora sottratto da nessuna logica reale (nessuna integrazione con
# MacroCellState scritta qui): solo il dato, per ora.
@export var required_space: int = 0

# Flag per BuildingVerificationService (2026-08-30) — i criteri "questa cella è di un terreno
# proibito" NON sono universali come "non sconosciuta"/"non già occupata": variano da tipo a
# tipo (una capanna non può stare in acqua, un futuro molo sì; una futura cava sì sulla roccia).
# Default = comportamento restrittivo di oggi (solo terreno "normale"), così i tipi esistenti non
# cambiano finché non li si abilita esplicitamente.
@export var buildable_on_water: bool = false
@export var buildable_on_river: bool = false
@export var buildable_on_stone: bool = false

# Controlla SOLO il Criterio 7 di BuildingVerificationService (la porta non può affacciarsi su
# terreno ostacolato/ignoto) — un edificio senza porta (es. una futura fontana) semplicemente non
# ha quel vincolo. Il Criterio 8 (non bloccare la porta di un edificio ESISTENTE già piazzato)
# resta invece SEMPRE attivo indipendentemente da questo flag, anche costruendo un edificio senza
# porta propria: è un vincolo sull'edificio ESISTENTE vicino, non su quello che si sta piazzando.
@export var has_door: bool = true

# Raggio in MACROCELLE (non microcelle — un edificio proietta il proprio effetto su macrocelle
# intere attorno a sé, unità diversa da FogOfWarRenderer.visibility_radius, che invece è in
# microcelle dentro una singola macrocella). 0 = solo la propria macrocella, 1 = anche le 8
# adiacenti, 2 = un altro anello oltre quello, ecc. — anelli concentrici (distanza di Chebyshev),
# confermato con l'utente. Il collegamento vero col fog of war (FogOfWarMemory) è rimandato: per
# ora questi quattro campi sono solo il dato che lo definirà in futuro.
@export var visibility_radius: int = 0
@export var political_radius: int = 0
@export var cultural_radius: int = 0
@export var religious_radius: int = 0
