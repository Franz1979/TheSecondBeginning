class_name IconRegistry
extends RefCounted

# Registro centrale di icone-emoji per dominio (2026-09-09, richiesta utente — "fai una cosa
# generica... in cui potremo mettere tutte le icone che ci servono"). Nessuno stato (RefCounted,
# solo costanti/funzioni statiche, mai istanziato) — stesso principio "fabbrica statica" già usato
# da TaskFactory/CaloricCalculator. Vive in simulation/scripts/ui/ insieme a IconButtonRow/
# PebbleCircleIcon/AnimalSilhouetteIcon: stessa cartella già stabilita per componenti/dati di
# presentazione puramente visivi, indipendentemente dal fatto che il game state che rappresentano
# viva in simulation/ o gameplay/ (vedi CLAUDE.md, confine Building/simulation — qui non si applica:
# non c'è stato, solo lookup).
#
# Un Dictionary SEPARATO per dominio (non uno solo con chiavi tipo "resource:pebble"): un dominio
# nuovo (es. tool, quando arriverà un vero sistema di equip) si aggiunge come una nuova costante +
# un nuovo getter accanto a questi, senza inventare uno schema di namespacing dentro le chiavi
# stringa esistenti.

# Icone-EMOJI per SecondaryResourceRules.secondary_resource_name (2026-09-09, primo consumatore:
# HumanIndividualInfoPanel._update_carried_resource_box, il riquadro risorsa trasportata — vedi lì
# per il fallback all'iniziale maiuscola quando una risorsa non ha ancora una voce né qui né in
# RESOURCE_ICON_NODES sotto). VUOTO oggi apposta: "pebble"/"stick" (i primi due popolati) sono
# passati entrambi a icone DISEGNATE (vedi RESOURCE_ICON_NODES sotto, get_resource_icon_node) dopo
# due giri di feedback sulle emoji disponibili — 🪨 legge come UN macigno singolo, non "tanti
# sassolini sparsi"; 🥢 legge come bacchette da tavola, 🪵 è più adatto a un futuro "wood"
# (materiale da costruzione DISTINTO, vedi hut.tres.required_materials, ancora senza .tres/icona
# propria — 🪵/🪨 restano liberi per quando "wood"/"stone" diventeranno vere risorse). Nessun emoji
# Unicode rende bene "rametti sparsi"/"ghiaia", stesso identico problema già risolto a mano per
# PebbleCircleIcon (vedi sotto). Questo Dictionary resta comunque il punto d'ingresso per una futura
# risorsa che un emoji SEMPLICE rappresenta già bene (es. un domani "egg" -> 🥚).
#
# "eggs" (2026-09-18, richiesta utente - uova raccoglibili per microcella): l'emoji uovo rende
# già bene da sé il concetto - esattamente il caso "emoji semplice" anticipato nel commento sopra,
# nessuna icona disegnata a mano necessaria a differenza di pebble/stick/berry/ecc. sotto.
#
# "wild_vegetables" (2026-09-19, richiesta utente - verdure selvatiche raccoglibili per
# microcella): l'emoji verdura a foglia rende già bene il concetto, stesso principio di eggs sopra.
#
# "medicinal_herbs" (2026-09-19, richiesta utente - erbe medicinali): 🌿 rende già bene una pianta
# officinale, stesso principio di wild_vegetables sopra. Consultato dal pannello dell'individuo
# (HumanIndividualInfoPanel), da BuildingInfoPanel e da OptionChoiceDialog.
const RESOURCE_ICONS := {
	"eggs": "🥚",
	"wild_vegetables": "🥬",
	"medicinal_herbs": "🌿",
	# "fiber_rope" (2026-09-23, richiesta utente - corda di fibre, primo prodotto del sistema di produzione): emoji
	# nodo provvisorio.
	"fiber_rope": "🪢",
}


# Icone DISEGNATE A MANO (Control, non emoji) per SecondaryResourceRules.secondary_resource_name
# (2026-09-09, richiesta utente) — stesso principio già in uso per BuildingRules "pebble_circle"
# (PebbleCircleIcon sotto): quando nessun emoji Unicode rende bene il concetto, un piccolo Control
# con solo _draw() lo sostituisce. "pebble" -> PebbleIcon (sassolini piccoli sparsi, non un macigno
# singolo), "stick" -> StickIcon (rametti spezzati, non bacchette/tronco). Ogni chiamata a
# get_resource_icon_node ritorna una ISTANZA NUOVA (.new(), mai condivisa): un Control non può
# avere più di un parent contemporaneamente, stesso principio già seguito da BuildBar per
# PebbleCircleIcon.new(). Il chiamante (HumanIndividualInfoPanel) decide dove/come inserirla.
#
# preload(), non il nome classe nudo (bugfix: "Assigned value for constant... isn't a constant
# expression" — un riferimento diretto a class_name dentro un Dictionary letterale non è una
# constant expression valida per GDScript, preload() sì, stesso identico valore risolto).
const RESOURCE_ICON_NODES := {
	"pebble": preload("res://simulation/scripts/ui/PebbleIcon.gd"),
	"stick": preload("res://simulation/scripts/ui/StickIcon.gd"),
	# "plant_fiber" (2026-09-16, richiesta utente — proposta mostrata in artifact e approvata):
	# fascio di fibre curve legate da un nodo, stesso principio "nessun emoji rende bene il
	# concetto" già documentato sopra per pebble/stick — vedi PlantFiberIcon.gd.
	"plant_fiber": preload("res://simulation/scripts/ui/PlantFiberIcon.gd"),
	# "berry" (2026-09-17, richiesta utente — proposta mostrata in artifact e approvata: "ok
	# bello"): grappolo di 3 bacche con riflesso e stelo/fogliolina, stesso principio "nessun emoji
	# rende bene il concetto" già documentato sopra — vedi BerryIcon.gd.
	"berry": preload("res://simulation/scripts/ui/BerryIcon.gd"),
	# "acorn" (2026-09-17, richiesta utente — seconda risorsa della catena "fruit stock" generica
	# dopo berry, stesso schema icona): due ghiande, corpo+cappuccio ellittici — vedi AcornIcon.gd.
	"acorn": preload("res://simulation/scripts/ui/AcornIcon.gd"),
	# "fruit" (2026-09-17, richiesta utente — terza risorsa della catena "fruit stock" generica,
	# TREE/domesticable_fruit, stesso schema icona): due mele, corpo circolare+stelo+fogliolina —
	# vedi FruitIcon.gd.
	"fruit": preload("res://simulation/scripts/ui/FruitIcon.gd"),
	# "mushroom" (2026-09-17, richiesta utente — quarta risorsa TERRAIN_SCATTERED a capacità
	# propria per lotto dopo pebble/stick/plant_fiber, modello stick): due funghi, cappello+gambo —
	# vedi MushroomIcon.gd.
	"mushroom": preload("res://simulation/scripts/ui/MushroomIcon.gd"),
	# Primi attrezzi (2026-09-24, richiesta utente — gli emoji 🔱/🔪 leggevano come forcone e coltello
	# moderno): bastone appuntito con punta indurita al fuoco, e scheggia di selce senza manico — vedi
	# WoodenSpearIcon.gd/StoneKnifeIcon.gd.
	"wooden_spear": preload("res://simulation/scripts/ui/WoodenSpearIcon.gd"),
	"stone_knife": preload("res://simulation/scripts/ui/StoneKnifeIcon.gd"),
}


# Icone per BuildingRules.building_name/Building.building_type_name (2026-09-09, richiesta utente
# — MIGRATE qui da BuildBar._ready, che prima le teneva come stringhe inline: "l'icona capanna
# potrei usarla sia nel button che magari in un'altra view", stesso motivo per cui esiste questo
# intero file invece di un fix locale a BuildBar). Chiavi = building_type_name, STESSA convenzione
# di BuildBar.BUILDING_SLOT_INDEX_BY_TYPE, non un enum chiuso: coerente col resto del progetto,
# dove building_type_name è sempre la chiave di confronto (mai il nome del file .tres).
#
# "pebble_circle" ASSENTE apposta da QUESTO Dictionary (emoji): non ha un'icona emoji, nessun emoji
# Unicode rende bene "cerchio di sassolini" (due giri di feedback: 🗿 leggeva come una testa dell'Isola
# di Pasqua, 🪨 come un mucchio di sassi). Ha invece un Control disegnato a mano — vedi
# BUILDING_ICON_NODES/get_building_icon_node sotto, STESSO principio già in uso per "pebble"/"stick"
# in RESOURCE_ICON_NODES sopra (BUGFIX 2026-09-09: prima PebbleCircleIcon.new() era istanziata
# direttamente e solo in BuildBar.gd, l'unica icona disegnata rimasta fuori da questo registro
# centrale — commento qui obsoleto di conseguenza, corretto).
#
# "🔨" (martello, azione "apri il menu costruzione" in BuildBar.main_row) NON è qui: non
# rappresenta un tipo di edificio, è un glifo di azione UI — dominio diverso, nessun bisogno di
# generalizzarlo finché non serve altrove.
#
# "deposit_site" e "dirt_ground" ASSENTI da questo Dictionary (2026-09-19, richiesta utente): erano
# emoji (🟫/🟤), ora hanno un'icona DISEGNATA (DepositSiteIcon/DirtGroundIcon, vedi
# BUILDING_ICON_NODES sotto) che riproduce sagoma, colori e bordo del rendering sulla mappa — un
# emoji non poteva farlo. get_building_icon ritorna quindi "" per entrambi: il chiamante usa
# get_building_icon_node (vedi BuildBar._ready).
const BUILDING_ICONS := {
	"hut": "🛖",
	# Stick Tent (2026-09-12, richiesta utente — collegamento UI/rendering) — "⛺" rende già bene da
	# sé "tenda", nessun problema di leggibilità come per pebble_circle sopra: non serve un'icona
	# disegnata a mano.
	"stick_tent": "⛺",
	# Focolare (2026-09-23, richiesta utente) — emoji provvisorio, già leggibile da sé.
	"campfire": "🔥",
	# Capanna dell'attrezzista (2026-09-24, richiesta utente) — emoji provvisorio.
	"toolmaker_hut": "🛠️",
}


# Icone DISEGNATE A MANO per BuildingRules.building_name/Building.building_type_name (2026-09-09,
# richiesta utente — "quel commento è obsoleto... farei come facciamo sia per sticks icon che per
# pebble icon, che passano nell'icon registry"): stesso identico principio/stessa struttura di
# RESOURCE_ICON_NODES sopra, dominio edifici invece che risorse. "pebble_circle" è l'unica entry per
# ora (vedi commento su BUILDING_ICONS sopra per il perché non ha un'icona emoji).
const BUILDING_ICON_NODES := {
	"pebble_circle": preload("res://simulation/scripts/ui/PebbleCircleIcon.gd"),
	# "deposit_site" (2026-09-19, richiesta utente): stessa sagoma, riempimento e bordo dell'edificio
	# piazzato (DepositSiteShape) + un mucchio di tre sacchi di iuta che la distingue dalla terra
	# battuta — vedi DepositSiteIcon.
	"deposit_site": preload("res://simulation/scripts/ui/DepositSiteIcon.gd"),
	# "dirt_ground" (2026-09-19, richiesta utente): quadrato a tutto slot, senza bordo, del colore base
	# del rendering con le stesse macchie — vedi DirtGroundIcon/DirtGroundPattern.
	"dirt_ground": preload("res://simulation/scripts/ui/DirtGroundIcon.gd"),
}


# Icone-EMOJI per l'effetto "lampeggio comando" (2026-09-11, richiesta utente — generalizzazione di
# GameScene._spawn_pickup_command_effect, prima solo per PickUpAction/"✋" hardcoded: "fai comparire
# un'icona lampeggiante quando parte l'azione... dovremmo avere un file dove indichiamo tutte le
# icone e le pesca da lì" — questo file esiste già per risorse/edifici, stesso principio esteso qui
# a un terzo dominio). Chiave = stringa libera scelta DAL CHIAMANTE che spawna l'effetto (oggi
# sempre GameScene, al momento in cui un comando viene impartito — vedi sotto), NON da un campo su
# Action: un primo tentativo (stesso giorno) legava l'icona ad Action.command_icon_key/un segnale
# `activated` emesso quando lo STEP DI LAVORO diventava attivo (cioè dopo il Walk, quando l'individuo
# arrivava) — SCARTATO su feedback utente: "il martello deve comparire quando parte la task, non
# quando arriva il pipottino dopo il walk... anche per haul service la manina appare subito... credo
# serva coerenza". Rimossi Action.command_icon_key/activated (Action.gd, SetupSiteAction.gd/
# ClearAction.gd/BuildAction.gd tornati al comportamento base) — il lampeggio ora scatta SEMPRE nello
# STESSO istante per ogni comando, "pickup" e "build" incluso: subito quando il comando viene dato
# (right-click di assegnazione), mai quando l'individuo arriva a destinazione.
#
# "🔨" per "build" — STESSO glifo già in uso in BuildBar.main_row per l'azione UI "apri il menu
# costruzione" (vedi la nota su BUILDING_ICONS sopra: quello è un dominio diverso, un glifo di
# azione UI non un tipo di edificio — qui invece è proprio il dominio giusto, nessuna duplicazione
# concettuale). UNA sola chiave per l'intera Build Task (non una per step, come nel tentativo
# scartato): il lampeggio spara una volta sola all'assegnazione, non differenzia più i quattro step
# interni (Walk/SetupSite/Clear/Build) — coerente con "pickup" sotto, che lampeggia una volta sola
# per l'intera haul_resource.

# "transport" (2026-09-12, richiesta utente — lampeggio sulla destinazione della Transport Task,
# "come accade per la build, e per la pick up task... metti un altro simbolo di scarico, non so se
# una carriola sia possibile") — nessuna carriola in Unicode standard (🛒/🧺 leggono come
# spesa/bucato, non trasporto merci; 🚚 è un veicolo, sproporzionato per un individuo a piedi): "📦"
# (pacco) scelto perché legge chiaramente come "consegna/scarico merce" restando coerente in scala
# con ✋/🔨 sopra, senza somigliare a nessuno dei due.
# "task_rejected" (2026-09-13, richiesta utente — bugfix: l'icona di comando compariva comunque
# anche quando HumanIndividual.assign_task rifiutava l'assegnazione, es. INFANT/vincolo di Task —
# il player vedeva "manina"/"martelletto" per una Task che non sarebbe mai partita) — "❌" ha già un
# colore nativo rosso nella maggior parte dei font emoji, nessun modulate custom necessario, stesso
# principio "colori nativi dell'emoji" già dichiarato per pickup/build/transport in
# GameScene._spawn_command_blink_effect.
const COMMAND_ICONS := {
	"pickup": "✋",
	"build": "🔨",
	"transport": "📦",
	# "produce" (2026-09-23, richiesta utente — Produce Task): icona provvisoria.
	"produce": "⚒️",
	"task_rejected": "❌",
}


# "" se resource_name non ha ancora un'icona registrata — il chiamante decide il fallback (es.
# l'iniziale maiuscola del nome, vedi HumanIndividualInfoPanel), questa funzione non lo impone.
static func get_resource_icon(resource_name: String) -> String:
	return RESOURCE_ICONS.get(resource_name, "")


# null se resource_name non ha un'icona disegnata registrata — il chiamante prova prima questa
# (icona vera), poi get_resource_icon sopra (emoji), poi il proprio fallback testuale, in
# quest'ordine (vedi HumanIndividualInfoPanel._update_carried_resource_box e
# BuildingInfoPanel._build_storage_slot, gli stessi tre livelli in entrambi). Istanza NUOVA ad ogni
# chiamata (vedi commento su RESOURCE_ICON_NODES sopra) — mai cachata qui.
static func get_resource_icon_node(resource_name: String) -> Control:
	if not RESOURCE_ICON_NODES.has(resource_name):
		return null
	return RESOURCE_ICON_NODES[resource_name].new()


# "" se building_type_name non ha ancora un'icona emoji qui (es. "pebble_circle", che ne ha una
# DISEGNATA invece — vedi get_building_icon_node sotto, chiamante che deve provare entrambe segue
# lo stesso ordine "icona vera poi emoji" già descritto sopra per get_resource_icon_node/
# get_resource_icon) — il chiamante decide il fallback, questa funzione non lo impone.
static func get_building_icon(building_type_name: String) -> String:
	return BUILDING_ICONS.get(building_type_name, "")


# null se building_type_name non ha un'icona disegnata registrata — stesso identico comportamento/
# stesso principio "istanza NUOVA ad ogni chiamata, mai cachata" di get_resource_icon_node sopra.
static func get_building_icon_node(building_type_name: String) -> Control:
	if not BUILDING_ICON_NODES.has(building_type_name):
		return null
	return BUILDING_ICON_NODES[building_type_name].new()


# "" se command_icon_key non ha un'icona registrata — il chiamante (GameScene._spawn_command_blink_
# effect) tratta "" come "nessun effetto", mai un fallback testuale come per le altre due famiglie
# sopra.
static func get_command_icon(command_icon_key: String) -> String:
	return COMMAND_ICONS.get(command_icon_key, "")


# Nome leggibile per resource_name — chiave tr() "carried_resource_tooltip_<resource_name>" (2026-
# 09-09, promossa qui da HumanIndividualInfoPanel._display_name_for_resource, che la duplicava:
# ORA anche BuildingInfoPanel/griglia slot magazzino la consulta per il proprio tooltip, un solo
# posto invece di due copie identiche — coerente col principio "registro centrale" di questo file).
# Stesso principio "chiave grezza, mai testo già tradotto" di BuildingRules.building_name/Idea.
# display_name, con fallback all'iniziale maiuscola di resource_name se la chiave non esiste ancora
# (nessuna traduzione trovata -> stesso idioma già usato altrove nel progetto per rilevarlo, es.
# Idea.gd) — così una risorsa futura senza voce qui mostra comunque qualcosa di leggibile invece
# della chiave grezza.
#
# TranslationServer.translate(), non tr() (bugfix: "Cannot call non-static function tr() from the
# static function" — tr() è un metodo di Object/Node, richiede un'istanza; TranslationServer è il
# singleton globale che tr() stesso richiama sotto il cofano, chiamabile ovunque senza self,
# stesso identico risultato/stesso identico fallback "ritorna la chiave se non trovata").
static func get_resource_display_name(resource_name: String) -> String:
	var key := "carried_resource_tooltip_%s" % resource_name
	var translated := TranslationServer.translate(key)
	if translated != key:
		return translated
	return resource_name.capitalize()


# Tinta stabile per lo stesso resource_name ad ogni chiamata (mai randf() puro, stesso principio
# "hash della stringa -> risultato stabile" già in uso altrove nel progetto, es. MicroCellRenderer.
# _is_shrub_fruit_bearing) — promossa qui (2026-09-09) da HumanIndividualInfoPanel.
# _placeholder_color_for_resource, che la duplicava: ORA anche BuildingInfoPanel/griglia slot
# magazzino la consulta, un solo posto invece di due copie identiche. Saturazione/valore fissi,
# solo l'hue varia per distinguere una risorsa dall'altra a colpo d'occhio — stessa risorsa =
# stesso colore ovunque nella UI (zaino individuo, slot magazzino, ...).
static func get_resource_color(resource_name: String) -> Color:
	var hue: float = float(resource_name.hash() % 360) / 360.0
	return Color.from_hsv(hue, 0.55, 0.8)


# Icone-IMMAGINE fornite dall'utente (2026-09-09, richiesta utente — "vorrei provare a metterlo
# come icona... se funziona provo poi con altre, senza fartele rifare ogni volta da codice"):
# convenzione per nome file, NESSUN Dictionary da aggiornare per ogni nuova icona. Un file
# res://simulation/assets/icons/<nome>.<estensione> — dove <nome> è la stessa chiave già in uso
# altrove in questo file (building_type_name per gli edifici, secondary_resource_name per le
# risorse: i due domini non si sovrappongono mai nei nomi usati oggi) — viene rilevato e preferito
# automaticamente al posto dell'icona disegnata a mano/emoji esistente. get_icon_texture_node
# ritorna null se il file non esiste ANCORA per quel nome: il chiamante allora ricade sulla propria
# icona esistente (stesso pattern a cascata di get_resource_icon_node/get_resource_icon sopra), MAI
# un errore/crash per un nome senza immagine.
const ICON_TEXTURE_DIR := "res://simulation/assets/icons/"
const ICON_TEXTURE_EXTENSIONS := ["png", "jpg", "jpeg", "webp"]


static func _find_icon_texture_path(name: String) -> String:
	for extension in ICON_TEXTURE_EXTENSIONS:
		var path := "%s%s.%s" % [ICON_TEXTURE_DIR, name, extension]
		if ResourceLoader.exists(path):
			return path
	return ""


# load(), non preload(): il path è costruito da <nome> a runtime (non una stringa letterale), e
# soprattutto il file potrebbe non esistere affatto per la maggior parte dei nomi — preload()
# richiederebbe che OGNI possibile nome avesse già un file al momento della compilazione dello
# script, l'opposto della convenzione "aggiungi un file quando vuoi" voluta qui. Istanza NUOVA ad
# ogni chiamata (stesso principio di get_resource_icon_node), STRETCH_MODE keep_aspect_centered
# per non deformare l'immagine qualunque sia la sua proporzione originale, mouse_filter=IGNORE
# stesso motivo di PebbleCircleIcon/PebbleIcon/StickIcon (i click devono raggiungere il Button sotto).
static func get_icon_texture_node(name: String) -> Control:
	var path := _find_icon_texture_path(name)
	if path == "":
		return null
	var texture: Texture2D = load(path)
	if texture == null:
		return null
	var texture_rect := TextureRect.new()
	texture_rect.texture = texture
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return texture_rect
