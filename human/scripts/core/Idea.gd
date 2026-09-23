class_name Idea
extends Resource

# Dati statici per un nodo dell'albero delle tecnologie (2026-09-07, richiesta utente, primo passo
# del modello dati — solo campi, nessuna logica di consumo/verifica ancora) — una .tres per idea,
# stesso schema di BuildingRules quanto a "solo la DEFINIZIONE qui, mai lo stato di avanzamento di
# un Folk verso di essa" (quello è Folk.thoughts_invested/completed_ideas, vedi Folk.gd). Resource
# (non RefCounted) perché va salvata come .tres, in human/data/ideas/.
#
# Spostata qui da simulation/scripts/core/ (2026-09-07, richiesta utente) — Idea rappresenta
# progresso tecnologico del Folk, dominio umano/player, non simulazione di mondo: stessa cartella
# di Folk.gd/IdeaProgressService.gd, non più accanto a BuildingRules (che invece resta in
# simulation/, vedi la ricognizione dedicata sul perché).

# Identificatore stabile (es. "paleolithic_constructions") — usato come chiave in Folk.
# thoughts_invested/completed_ideas e in prerequisites sotto, MAI il nome del file .tres
# (BuildingRules.required_idea_id fa lo stesso confronto per id, non per percorso file — stesso
# principio già seguito da Building.building_type_name vs BuildingRules.building_name).
@export var id: String = ""

# Nome leggibile per UI/log — DECISO (2026-09-07, primi consumatori reali: TechTreePanel, tooltip
# "Richiede: ..." in BuildBar, popup di notifica sblocco): chiave tr(), esattamente come
# BuildingRules.building_name (es. "building_hut") — MAI una stringa già tradotta qui. Ogni
# consumatore deve avvolgerla in tr(...) prima di mostrarla (vedi TechTreePanel.refresh_content,
# GameScene._refresh_building_slots_buildable/_on_idea_completed).
@export var display_name: String = ""

# Testi descrittivi (2026-09-21, richiesta utente) — anch'essi chiavi tr(), MAI testo già tradotto
# (stessa regola di display_name sopra), convenzione idea_<id>_summary / idea_<id>_description.
# summary = una riga (popup di sblocco, tooltip); description = testo più esteso (tooltip del
# TechTreePanel). Vuoto = niente da mostrare, i consumatori saltano la riga.
@export var summary: String = ""
@export var description: String = ""

# Costo in "pensieri" (Folk.thoughts_count/thoughts_invested) per completare questa idea — non
# ancora confrontato da nessuna logica in questo passo.
@export var thoughts_cost: int = 0

# Id di altre Idee (Idea.id, non percorsi file) che devono essere già in Folk.completed_ideas prima
# che questa sia raggiungibile — vuoto = nessun prerequisito, è una radice dell'albero. Untyped
# risolto come Array[String] (non un Array di Resource, quindi nessuno dei problemi di sintassi
# fragile in .tres già discussi per TaskDefinition.steps/ResourceGrowthRules.subtypes: una stringa
# in un array tipizzato scrive/legge senza sorprese in un file scritto a mano).
@export var prerequisites: Array[String] = []

# Era (GameData.current_era_name, es. "paleolithic") a cui questa idea appartiene — per un futuro
# controllo aggregato "tutte le idee di questa era sono complete -> avanza era", non ancora
# consultato da nessuna logica (stesso principio "solo il dato" di thoughts_cost sopra). Stringa
# libera per lo stesso motivo di GameData.current_era_name, non un enum chiuso.
@export var era: String = ""
