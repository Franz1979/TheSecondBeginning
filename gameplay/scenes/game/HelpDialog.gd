class_name HelpDialog
extends Window

# Popup di aiuto di GameScene — stesso pattern di SystemMenuDialog/SaveConfirmationDialog (Window,
# popup_centered, close_requested -> hide), trattato come dialogo bloccante da GameScene
# (visibility_changed collegato a _on_blocking_dialog_visibility_changed, stesso schema degli
# altri due): mette in pausa il clock mentre è aperto, non il movimento dell'individuo
# (indipendente dal clock per design).
#
# Struttura a indice con link ipertestuali (richiesta utente, 2026-08-30): un solo
# RichTextLabel riusato per tutte le "pagine" — l'indice (PAGE_MAIN, con un [url=...] per voce)
# e ogni pagina foglia (oggi solo PAGE_SHORTCUTS). meta_clicked cambia pagina, back_button
# (nascosto sull'indice, non c'è dove tornare) riporta a PAGE_MAIN. Aggiungere una nuova voce di
# help significa: una nuova costante PAGE_*, una riga [url=...] in _build_main_menu_text, e un
# nuovo _build_*_text/branch nel match di _show_page.

# Dimensione della finestra e margine minimo dai bordi della finestra di gioco (open_dialog).
const DIALOG_SIZE := Vector2i(700, 550)
const DIALOG_SCREEN_MARGIN: int = 20

@onready var content_label: RichTextLabel = $MarginContainer/VBoxContainer/ContentLabel
@onready var back_button: Button = $MarginContainer/VBoxContainer/BackButton
@onready var close_button: Button = $MarginContainer/VBoxContainer/CloseButton

const PAGE_MAIN := "main"
const PAGE_SHORTCUTS := "shortcuts"
const PAGE_FOG_OF_WAR := "fog_of_war"
const PAGE_ERA_ADVANCEMENT := "era_advancement"
const PAGE_BUILDING_MATERIALS := "building_materials"
# Pagina "Edifici" (2026-10-07): elenco dei tipi costruibili, e scheda di un tipo con la pagina
# BUILDING_PAGE_PREFIX + <tipo> (es. "building:hut").
const PAGE_BUILDINGS := "buildings"
const BUILDING_PAGE_PREFIX := "building:"
const INFO_ROW_INDENT := "    "
# Pagina "Risorse" (2026-10-07, prima due pagine "Attrezzi" e "Ricette"): elenco per categoria e scheda della risorsa,
# ITEM_PAGE_PREFIX + <risorsa>.
const PAGE_RESOURCES := "resources"
# Pagina "Attrezzi" (2026-10-07): le risorse della categoria degli attrezzi, che "Risorse" non elenca.
const PAGE_TOOLS := "tools"
const ITEM_PAGE_PREFIX := "item:"

# Icone nelle schede di edifici, attrezzi e risorse (2026-10-08, richiesta utente): grande accanto al nome in testa
# alla scheda, piccola davanti ai materiali dell'edificio e agli ingredienti della ricetta. Solo icone che esistono già
# (IconRegistry): immagine in assets/icons, icona disegnata (Control) o emoji, nello stesso ordine dei pannelli; senza
# icona nessun segnaposto. Il testo delle pagine resta lo stesso: nel BBCode l'icona è un segnaposto (_icon_token) che
# _set_page_text sostituisce con un'immagine inline (RichTextLabel.add_image) o con l'emoji. Le icone disegnate non sono
# texture: ognuna viene disegnata una volta in un SubViewport tenuto qui (_icon_viewports) e mostrata con la sua
# ViewportTexture.
const HEADER_ICON_SIDE: int = 48
const INLINE_ICON_SIDE: int = 18
# Lato del disegno nel SubViewport (il doppio dell'icona grande, così resta nitida anche ridotta).
const ICON_RENDER_SIDE: int = 96
const ICON_TOKEN_PATTERN := "§icon:(building|resource):([a-z0-9_]+):([0-9]+)§"
var _icon_viewports: Dictionary = {}  # "building:<tipo>" / "resource:<nome>" -> SubViewport
var _icon_token_regex: RegEx = null

var _current_page: String = PAGE_MAIN
# Pagine da cui si è arrivati (2026-10-07): Indietro torna sempre alla precedente (scheda -> elenco -> indice, scheda di
# un edificio -> scheda dell'oggetto da cui la si è aperta). Svuotata a ogni apertura e quando si torna all'indice.
var _page_history: Array[String] = []


func _ready() -> void:
	title = tr("help_dialog_title")
	close_button.text = tr("close_menu")
	close_button.pressed.connect(hide)
	# close_requested NON collegato a hide() + X nascosta (richiesta utente, 2026-09-05, stesso
	# motivo/meccanismo di SystemMenuDialog._hide_native_close_button): si chiude solo dal
	# CloseButton esplicito.
	var transparent := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	add_theme_icon_override("close", transparent)
	add_theme_icon_override("close_pressed", transparent)
	back_button.text = tr("back")
	back_button.pressed.connect(_on_back_pressed)

	content_label.bbcode_enabled = true
	content_label.meta_clicked.connect(_on_meta_clicked)
	_show_page(PAGE_MAIN)


func open_dialog() -> void:
	# Riparte sempre dall'indice quando il popup si riapre — nessuna pagina foglia resta "aperta"
	# da una sessione precedente, coerente con com'era il comportamento prima di questa modifica
	# (il contenuto era sempre lo stesso ad ogni apertura).
	_page_history.clear()
	_show_page(PAGE_MAIN)
	exclusive = true
	# 700 × 550 (2026-10-07, richiesta utente — era 420 × 400), mai più grande della finestra di gioco (con un margine):
	# così resta tutta visibile anche su schermi piccoli. Il testo va a capo sulla larghezza vera (RichTextLabel a tutta
	# larghezza).
	var screen_size := Vector2i(get_tree().root.get_visible_rect().size)
	var dialog_size := Vector2i(
		mini(DIALOG_SIZE.x, maxi(screen_size.x - DIALOG_SCREEN_MARGIN * 2, 1)),
		mini(DIALOG_SIZE.y, maxi(screen_size.y - DIALOG_SCREEN_MARGIN * 2, 1))
	)
	popup_centered(dialog_size)


# Un link alla pagina già aperta (o lo stesso clic ricevuto due volte) non entra nella cronologia (2026-10-09, richiesta
# utente: servivano due clic su Indietro).
func _on_meta_clicked(meta: Variant) -> void:
	var page := str(meta)
	if page == _current_page:
		_log_page("link alla pagina già aperta, ignorato: %s" % page)
		return
	_page_history.append(_current_page)
	_log_page("link: %s -> %s" % [_current_page, page])
	_show_page(page)


# Indietro (2026-10-07): la pagina da cui si è arrivati; senza storia, l'indice. Le voci uguali alla pagina aperta
# vengono saltate (2026-10-09): un clic torna sempre a una pagina diversa.
func _on_back_pressed() -> void:
	while not _page_history.is_empty() and _page_history.back() == _current_page:
		_page_history.pop_back()
	var previous: String = _page_history.pop_back() if not _page_history.is_empty() else PAGE_MAIN
	_log_page("Indietro: %s -> %s" % [_current_page, previous])
	_show_page(previous)


# Log [HELP] (DebugLogging.SHOW_HELP_DIALOG_LOGS): l'evento e la cronologia intera dopo l'evento.
func _log_page(event_text: String) -> void:
	if DebugLogging.ENABLED and DebugLogging.SHOW_HELP_DIALOG_LOGS:
		print("[HELP] %s — cronologia %s, aperta '%s'." % [event_text, str(_page_history), _current_page])


func _show_page(page: String) -> void:
	_current_page = page
	if page == PAGE_MAIN:
		_page_history.clear()
	back_button.visible = page != PAGE_MAIN
	# BUGFIX "Indietro due volte" (2026-10-09): le schede (risorsa, attrezzo, edificio) si scrivono con clear() +
	# append_text (_set_page_text), che NON cambiano la proprietà `text`: restava il BBCode della pagina di prima (es.
	# l'elenco "Risorse"). Tornando a quella pagina, `text = <stesso BBCode>` non faceva nulla (il setter ignora un valore
	# uguale) e restava visibile la scheda: sembrava che il primo "Indietro" non funzionasse. Ora `text` si azzera prima
	# di ogni pagina, così ogni assegnazione la ridisegna davvero.
	content_label.text = ""
	match page:
		PAGE_SHORTCUTS:
			content_label.text = _build_shortcuts_text()
		PAGE_FOG_OF_WAR:
			content_label.text = _build_fog_of_war_text()
		PAGE_ERA_ADVANCEMENT:
			content_label.text = _build_era_advancement_text()
		PAGE_BUILDING_MATERIALS:
			content_label.text = _build_building_materials_text()
		PAGE_BUILDINGS:
			content_label.text = _build_buildings_list_text()
		PAGE_RESOURCES:
			content_label.text = _build_resources_list_text()
		PAGE_TOOLS:
			content_label.text = _build_tools_list_text()
		_:
			if page.begins_with(ITEM_PAGE_PREFIX):
				_set_page_text(_build_item_page_text(page.substr(ITEM_PAGE_PREFIX.length())))
			elif page.begins_with(BUILDING_PAGE_PREFIX):
				_set_page_text(_build_building_page_text(page.substr(BUILDING_PAGE_PREFIX.length())))
			else:
				content_label.text = _build_main_menu_text()
	content_label.scroll_to_line(0)
	_log_page("pagina mostrata: %s" % page)


# --- Icone delle schede (vedi in testa al file) ---

# Segnaposto dell'icona di `name` ("building" o "resource") di lato `side`, seguito da uno spazio; "" se l'icona non
# esiste (niente spazio vuoto).
func _icon_token(kind: String, name: String, side: int) -> String:
	if not _has_icon(kind, name):
		return ""
	return "§icon:%s:%s:%d§ " % [kind, name, side]


func _has_icon(kind: String, name: String) -> bool:
	if kind == "building":
		return IconRegistry.BUILDING_ICON_NODES.has(name) or IconRegistry.get_building_icon(name) != ""
	return IconRegistry.get_icon_texture(name) != null or IconRegistry.RESOURCE_ICON_NODES.has(name) \
		or IconRegistry.get_resource_icon(name) != ""


# Testo della pagina con i segnaposto: il testo tra un'icona e l'altra entra come BBCode (append_text), l'icona come
# immagine o emoji. I segnaposto stanno sempre fuori dai tag ([b], [url]), così ogni pezzo di BBCode è completo.
func _set_page_text(bbcode: String) -> void:
	if _icon_token_regex == null:
		_icon_token_regex = RegEx.create_from_string(ICON_TOKEN_PATTERN)
	content_label.clear()
	var cursor := 0
	var rendered_new := false
	for found in _icon_token_regex.search_all(bbcode):
		content_label.append_text(bbcode.substr(cursor, found.get_start() - cursor))
		rendered_new = _append_icon(found.get_string(1), found.get_string(2), int(found.get_string(3))) or rendered_new
		cursor = found.get_end()
	content_label.append_text(bbcode.substr(cursor))
	if rendered_new:
		_redraw_after_icon_render()


# Aggiunge l'icona al testo. true se ha appena creato un disegno nuovo (visibile dal fotogramma dopo).
func _append_icon(kind: String, name: String, side: int) -> bool:
	if kind == "building":
		if IconRegistry.BUILDING_ICON_NODES.has(name):
			var created := not _icon_viewports.has("building:" + name)
			content_label.add_image(_drawn_icon_texture("building:" + name, func() -> Control: return IconRegistry.get_building_icon_node(name)), side, side)
			return created
		_append_emoji(IconRegistry.get_building_icon(name), side)
		return false
	var texture := IconRegistry.get_icon_texture(name)
	if texture != null:
		var icon_scale := float(side) / float(maxi(texture.get_width(), texture.get_height()))
		content_label.add_image(texture, int(round(texture.get_width() * icon_scale)), int(round(texture.get_height() * icon_scale)))
		return false
	if IconRegistry.RESOURCE_ICON_NODES.has(name):
		var created := not _icon_viewports.has("resource:" + name)
		content_label.add_image(_drawn_icon_texture("resource:" + name, func() -> Control: return IconRegistry.RESOURCE_ICON_NODES[name].new()), side, side)
		return created
	_append_emoji(IconRegistry.get_resource_icon(name), side)
	return false


func _append_emoji(emoji: String, side: int) -> void:
	if emoji != "":
		content_label.append_text("[font_size=%d]%s[/font_size]" % [int(side * 0.8), emoji])


# Texture dell'icona disegnata `key`: il SubViewport che la disegna una volta (creato alla prima richiesta con il nodo
# di `make_node`, poi riusato per entrambe le misure).
func _drawn_icon_texture(key: String, make_node: Callable) -> Texture2D:
	if not _icon_viewports.has(key):
		var viewport := SubViewport.new()
		viewport.size = Vector2i(ICON_RENDER_SIDE, ICON_RENDER_SIDE)
		viewport.transparent_bg = true
		viewport.disable_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		var icon_node: Control = make_node.call()
		icon_node.position = Vector2.ZERO
		icon_node.size = Vector2(ICON_RENDER_SIDE, ICON_RENDER_SIDE)
		viewport.add_child(icon_node)
		add_child(viewport)
		_icon_viewports[key] = viewport
	return (_icon_viewports[key] as SubViewport).get_texture()


# Un disegno nuovo è pronto solo dopo il fotogramma in cui il SubViewport lo disegna: allora la pagina si ridisegna.
func _redraw_after_icon_render() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(content_label):
		content_label.queue_redraw()


func _build_main_menu_text() -> String:
	var lines: Array[String] = [
		"[b]%s[/b]" % tr("help_dialog_title"),
		"",
		"[url=%s]%s[/url]" % [PAGE_SHORTCUTS, tr("help_shortcuts_menu_link")],
		"[url=%s]%s[/url]" % [PAGE_FOG_OF_WAR, tr("help_fog_of_war_menu_link")],
		"[url=%s]%s[/url]" % [PAGE_ERA_ADVANCEMENT, tr("help_era_advancement_menu_link")],
		"[url=%s]%s[/url]" % [PAGE_BUILDING_MATERIALS, tr("help_building_materials_menu_link")],
		"[url=%s]%s[/url]" % [PAGE_BUILDINGS, tr("help_buildings_menu_link")],
		"[url=%s]%s[/url]" % [PAGE_TOOLS, tr("help_tools_menu_link")],
		"[url=%s]%s[/url]" % [PAGE_RESOURCES, tr("help_resources_menu_link")],
	]
	return "\n".join(lines)


func _build_fog_of_war_text() -> String:
	# I tre livelli usano [ol]/[li] (lista numerata) invece di prefissare "1."/"2."/"3." dentro le
	# chiavi tradotte — la formattazione è responsabilità del codice, il testo tradotto resta puro
	# senza markup da dover replicare/mantenere in ogni lingua.
	var lines: Array[String] = [
		"[b]%s[/b]" % tr("help_fog_of_war_title"),
		"",
		tr("help_fog_of_war_intro"),
		"",
		tr("help_fog_of_war_memory_intro"),
		"[ol]",
		"[li]%s[/li]" % tr("help_fog_of_war_tier_detail"),
		"[li]%s[/li]" % tr("help_fog_of_war_tier_resources"),
		"[li]%s[/li]" % tr("help_fog_of_war_tier_terrain"),
		"[/ol]",
		tr("help_fog_of_war_full_forget"),
		"",
		tr("help_fog_of_war_persistence"),
		"",
		tr("help_fog_of_war_per_macrocell"),
	]
	return "\n".join(lines)


func _build_era_advancement_text() -> String:
	var lines: Array[String] = [
		"[b]%s[/b]" % tr("help_era_advancement_title"),
		"",
		tr("help_era_advancement_intro"),
		"",
		tr("help_era_advancement_longevity"),
		"",
		tr("help_era_advancement_bands_unaffected"),
		"",
		tr("help_era_advancement_not_yet_active"),
	]
	return "\n".join(lines)


# Pagina "Costruzioni e materiali" (2026-09-14, richiesta utente — spiegare al player il fabbisogno
# materiale in due fasi della Build Task, ora che la Transport automatica è stata rimossa: SOLO
# documentazione, nessuna logica). Stesso schema delle altre pagine foglia (titolo in grassetto,
# paragrafi separati da una riga vuota).
func _build_building_materials_text() -> String:
	var lines: Array[String] = [
		"[b]%s[/b]" % tr("help_building_materials_title"),
		"",
		tr("help_building_materials_setup_vs_construction"),
		"",
		tr("help_building_materials_manual"),
		"",
		tr("help_building_materials_deposit_bonus"),
		"",
		tr("help_building_materials_future"),
	]
	return "\n".join(lines)


func _build_shortcuts_text() -> String:
	# Aggiornata 2026-09-13 (richiesta utente — "ultimamente ne sono stati aggiunti un bel po' ma
	# non è stata aggiornata la lista"): mancavano B (piazzamento istantaneo), il secondo significato
	# di R (Rest Task, mutuamente esclusivo col piazzamento edificio — vedi GameScene._unhandled_
	# input), G (Wander Task) e P (Play Task, aggiunta nello stesso giro di questo aggiornamento).
	# Verificato contro OGNI KEY_* di GameScene._unhandled_input non gated da DebugLogging.ENABLED —
	# T/Y restano deliberatamente FUORI (vedi nota sotto per il perché, invariata). U AGGIUNTO
	# (2026-09-16, richiesta utente): non più il test debug temporaneo che era prima (vedi
	# GameScene._unhandled_input), ora è il modificatore vero per "Scaricare risorsa qui".
	# Doppio click sinistro AGGIUNTO (2026-09-16, richiesta utente) — unico gesto MOUSE elencato qui
	# insieme alle scorciatoie da tastiera (nessun'altra convenzione click esistente documentata in
	# help finora): ispeziona la microcella, comando introdotto nello stesso giro in cui il click
	# singolo ha smesso di poter selezionare una cella/lotto intero (solo oggetti precisi).
	var lines: Array[String] = [
		"[b]%s[/b]" % tr("help_shortcuts_title"),
		"",
		"[b]W A S D[/b] / %s — %s" % [tr("help_arrow_keys"), tr("help_pan_camera")],
		"[b]X[/b] — %s" % tr("help_center_camera"),
		"[b]+[/b] — %s" % tr("help_zoom_max"),
		"[b]-[/b] — %s" % tr("help_zoom_min"),
		"[b]B[/b] — %s" % tr("help_instant_build"),
		"[b]R[/b] — %s" % tr("help_rotate_or_rest"),
		"[b]G[/b] — %s" % tr("help_wander_task"),
		"[b]P[/b] — %s" % tr("help_play_task"),
		"[b]O[/b] — %s" % tr("help_explore_task"),
		# Tasti dei comandi già esistenti ma assenti da questa lista fino al 2026-10-04 (richiesta utente: "i comandi
		# da tastiera nel ? insieme agli altri"): E, F, L, i tasti della barra dei comandi (CommandBar.GATHER_KEY/
		# HUNT_KEY/AUTO_ZONE_KEY) ed Esc.
		"[b]E[/b] — %s" % tr("help_emergency_rest_task"),
		"[b]F[/b] — %s" % tr("help_leisure_restock_task"),
		"[b]H[/b] — %s" % tr("help_stop_task"),
		"[b]U[/b] — %s" % tr("help_unload_here_task"),
		"[b]%s[/b] — %s" % [OS.get_keycode_string(CommandBar.GATHER_KEY), tr("help_gather_command")],
		"[b]%s[/b] — %s" % [OS.get_keycode_string(CommandBar.HUNT_KEY), tr("help_hunt_command")],
		"[b]%s[/b] — %s" % [OS.get_keycode_string(CommandBar.CUT_KEY), tr("help_cut_command")],
		"[b]%s[/b] — %s" % [OS.get_keycode_string(CommandBar.QUARRY_KEY), tr("help_quarry_command")],
		"[b]%s[/b] — %s" % [OS.get_keycode_string(CommandBar.AUTO_ZONE_KEY), tr("help_auto_zone_command")],
		"[b]L[/b] — %s" % tr("help_cycle_map_layer"),
		"[b]Esc[/b] — %s" % tr("help_escape_cancel"),
		"[b]%s[/b] — %s" % [tr("help_double_click_label"), tr("help_double_click_inspect_microcell")],
	]
	# Voci DEBUG (2026-09-09, richiesta utente — "aggiungi anche z, s [H] nell'help"): mostrate
	# solo quando i debug hook stessi sono attivi (DebugLogging.ENABLED, stesso interruttore che li
	# abilita in GameScene._unhandled_input) — coerente col fatto che in una build "pulita" quei
	# tasti non fanno letteralmente nulla, elencarli comunque confonderebbe il player. T/Y (test
	# temporanei "usa e getta", da rimuovere — vedi i rispettivi commenti "TEST TEMPORANEO... DA
	# RIMUOVERE" in GameScene.gd) restano deliberatamente FUORI da questa lista anche a debug attivo:
	# non richiesti, e pensati per sparire a breve — a differenza di Z, un'utility di debug più
	# duratura. U non è più tra questi (vedi sopra): è ora un comando vero, elencato incondizionatamente.
	if DebugLogging.ENABLED:
		lines.append("[b]Z[/b] — %s" % tr("help_debug_clear_backpack"))
	return "\n".join(lines)


# --- Pagina "Edifici" (2026-10-07, richiesta utente) ---
# Elenco dei tipi che il giocatore può costruire dalla barra edifici (BuildBar.BUILDING_SLOT_INDEX_BY_TYPE, nell'ordine
# dei bottoni) o ottenere con un miglioramento (BuildingRules.upgrades_to), anche se non ancora scoperti, letti dai
# dati (BuildingCalculator). Raggruppati per catena di miglioramento: ogni edificio di partenza (uno che non è la
# destinazione di un miglioramento di un altro dell'elenco) seguito, rientrati, da quelli in cui si migliora.
func _build_buildings_list_text() -> String:
	var lines: Array[String] = ["[b]%s[/b]" % tr("help_buildings_title"), ""]
	for chain in _building_upgrade_chains():
		for index in range(chain.size()):
			var rules := BuildingCalculator.get_building_rules(chain[index])
			var link := "[url=%s%s]%s[/url]" % [BUILDING_PAGE_PREFIX, chain[index], tr(rules.building_name)]
			lines.append((INFO_ROW_INDENT.repeat(index) + "→ " + link) if index > 0 else link)
	return "\n".join(lines)


# Catene di miglioramento dei tipi elencati: [[partenza, migliorato, migliorato del migliorato, ...], ...].
func _building_upgrade_chains() -> Array:
	var known := BuildingCalculator.list_building_type_names()
	var types: Array[String] = []
	var bar_order: Array = BuildBar.BUILDING_SLOT_INDEX_BY_TYPE.keys()
	bar_order.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int(BuildBar.BUILDING_SLOT_INDEX_BY_TYPE[a]) < int(BuildBar.BUILDING_SLOT_INDEX_BY_TYPE[b])
	)
	for type_name in bar_order:
		if known.has(String(type_name)) and not types.has(String(type_name)):
			types.append(String(type_name))
	# Destinazioni dei miglioramenti, anche fuori dalla barra (seguendo le catene).
	var index := 0
	while index < types.size():
		var rules := BuildingCalculator.get_building_rules(types[index])
		if rules != null and rules.upgrades_to != "" and known.has(rules.upgrades_to) and not types.has(rules.upgrades_to):
			types.append(rules.upgrades_to)
		index += 1
	var targets: Dictionary = {}
	for type_name in types:
		var rules := BuildingCalculator.get_building_rules(type_name)
		if rules != null and rules.upgrades_to != "":
			targets[rules.upgrades_to] = true
	var chains: Array = []
	for type_name in types:
		if targets.has(type_name):
			continue
		var chain: Array[String] = [type_name]
		var rules := BuildingCalculator.get_building_rules(type_name)
		while rules != null and rules.upgrades_to != "" and known.has(rules.upgrades_to) and not chain.has(rules.upgrades_to):
			chain.append(rules.upgrades_to)
			rules = BuildingCalculator.get_building_rules(rules.upgrades_to)
		chains.append(chain)
	return chains


# Scheda di un tipo di edificio: nome e descrizione breve (se c'è, BuildingCostTooltip.get_short_description); costo
# (materiali e lavoro, gli stessi dati del tooltip di costo, BuildingCostTooltip.get_build_materials — come testo, dal
# 2026-10-08 con l'icona piccola di ogni materiale, vedi _icon_token); le righe Info del tipo
# (BuildingInfoLines.build); l'idea richiesta, se c'è; "Si migliora in: X", se c'è, che apre la scheda di X.
func _build_building_page_text(type_name: String) -> String:
	var rules := BuildingCalculator.get_building_rules(type_name)
	if rules == null:
		return _build_buildings_list_text()
	# Icona grande accanto al nome (2026-10-08): quella del bottone della barra edifici.
	var lines: Array[String] = ["%s[b]%s[/b]" % [_icon_token("building", type_name, HEADER_ICON_SIDE), tr(rules.building_name)]]
	var description := BuildingCostTooltip.get_short_description(type_name)
	if description != "":
		lines.append(description)
	lines.append("")
	var materials := BuildingCostTooltip.get_build_materials(rules)
	var material_names: Array = materials.keys()
	material_names.sort()
	var material_parts: Array[String] = []
	for material_name in material_names:
		material_parts.append("%d %s%s" % [
			int(materials[material_name]), _icon_token("resource", String(material_name), INLINE_ICON_SIDE),
			IconRegistry.get_resource_display_name(String(material_name)),
		])
	lines.append(tr("help_buildings_materials").format({
		"items": ", ".join(material_parts) if not material_parts.is_empty() else tr("building_upgrade_nothing"),
	}))
	lines.append(tr("building_upgrade_labor").format({"labor": rules.required_labor}))
	lines.append("")
	for row in BuildingInfoLines.build(rules):
		lines.append((INFO_ROW_INDENT if bool(row.get("indent", false)) else "") + String(row["text"]))
	# Ricette dell'edificio (2026-10-07): le risorse che vi si producono, ognuna apre la sua scheda.
	var recipe_links: Array[String] = []
	for resource_name in _sorted_by_display_name(CaloricCalculator.list_secondary_resource_names()):
		var resource_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
		if resource_rules != null and resource_rules.recipe_workstation_types.has(type_name):
			recipe_links.append(_item_link(resource_name))
	if not recipe_links.is_empty():
		lines.append("")
		lines.append(tr("help_buildings_recipes").format({"items": ", ".join(recipe_links)}))
	if rules.required_idea_id != "":
		var idea := IdeaCalculator.get_idea(rules.required_idea_id)
		lines.append("")
		lines.append(tr("tech_tree_requires").format({"ideas": tr(idea.display_name) if idea != null else rules.required_idea_id}))
	var upgrade_rules := BuildingCalculator.get_building_rules(rules.upgrades_to) if rules.upgrades_to != "" else null
	if upgrade_rules != null:
		lines.append("")
		lines.append(tr("help_buildings_upgrades_to").format({
			"building": "[url=%s%s]%s[/url]" % [BUILDING_PAGE_PREFIX, rules.upgrades_to, tr(upgrade_rules.building_name)],
		}))
	return "\n".join(lines)


# --- Pagina "Risorse" (2026-10-07, richiesta utente — prima "Attrezzi" e "Ricette") ---
# Tutto dai dati delle risorse (CaloricCalculator.list_secondary_resource_names / get_caloric_source_rules), niente
# scritto a mano. Nomi del gioco con IconRegistry.get_resource_display_name; righe composte in RecipeInfoLines.

# Tutte le risorse, materie prime comprese, raggruppate per categoria (SecondaryResourceTypes.Category, nell'ordine
# dell'enum) con i nomi di categoria del gioco (gli stessi della conservazione degli edifici,
# BuildingInfoLines.category_display_name); dentro ogni categoria in ordine di nome.
func _build_resources_list_text() -> String:
	var lines: Array[String] = ["[b]%s[/b]" % tr("help_resources_title")]
	var by_category: Dictionary = {}
	for resource_name in CaloricCalculator.list_secondary_resource_names():
		var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
		if rules == null:
			continue
		var category := int(rules.category)
		if not by_category.has(category):
			by_category[category] = []
		(by_category[category] as Array).append(resource_name)
	for category in SecondaryResourceTypes.Category.values():
		# Gli attrezzi hanno la loro pagina (PAGE_TOOLS).
		if int(category) == SecondaryResourceTypes.Category.TOOL or not by_category.has(int(category)):
			continue
		lines.append("")
		lines.append("[b]%s[/b]" % BuildingInfoLines.category_display_name(int(category)))
		for resource_name in _sorted_by_display_name(by_category[int(category)]):
			lines.append(INFO_ROW_INDENT + _item_link(resource_name))
	return "\n".join(lines)


# Elenco degli attrezzi (categoria TOOL, la stessa esclusa da "Risorse"), in ordine di nome; ogni nome apre la scheda
# della risorsa.
func _build_tools_list_text() -> String:
	var lines: Array[String] = ["[b]%s[/b]" % tr("help_tools_title"), ""]
	var tools: Array[String] = []
	for resource_name in CaloricCalculator.list_secondary_resource_names():
		var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
		if rules != null and rules.category == SecondaryResourceTypes.Category.TOOL:
			tools.append(resource_name)
	for resource_name in _sorted_by_display_name(tools):
		lines.append(_item_link(resource_name))
	return "
".join(lines)


func _sorted_by_display_name(names: Array) -> Array[String]:
	var sorted: Array[String] = []
	for resource_name in names:
		sorted.append(String(resource_name))
	sorted.sort_custom(func(a: String, b: String) -> bool:
		return IconRegistry.get_resource_display_name(a) < IconRegistry.get_resource_display_name(b)
	)
	return sorted


func _item_link(resource_name: String) -> String:
	return "[url=%s%s]%s[/url]" % [ITEM_PAGE_PREFIX, resource_name, IconRegistry.get_resource_display_name(resource_name)]


# Scheda di una risorsa. Solo le righe con un valore:
#   - nome (le risorse non hanno ancora una descrizione nei dati);
#   - caratteristiche (RecipeInfoLines.characteristics): spazio, deperimento, calorie e effetti se è un cibo, combustibile;
#   - attrezzo (RecipeInfoLines.tool_lines): a cosa serve, usi, potenza, portata, munizione, efficienza, capacità;
#   - ricetta (RecipeInfoLines.build): ingredienti, quantità prodotta, lavoro, combustibile, giorni se avanza da sola,
#     attrezzo richiesto;
#   - "Si produce in: X, Y", ogni edificio apre la sua scheda.
func _build_item_page_text(resource_name: String) -> String:
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	# Icona grande accanto al nome (2026-10-08): quella dei pannelli e dei tooltip.
	var lines: Array[String] = ["%s[b]%s[/b]" % [_icon_token("resource", resource_name, HEADER_ICON_SIDE), IconRegistry.get_resource_display_name(resource_name)]]
	if rules == null:
		return "\n".join(lines)
	for group in [RecipeInfoLines.characteristics(rules), RecipeInfoLines.tool_lines(rules)]:
		if not (group as Array).is_empty():
			lines.append("")
			lines.append_array(group)
	# Icona piccola davanti a ogni ingrediente (2026-10-08).
	var recipe_lines := RecipeInfoLines.build(rules, func(input_name: String) -> String: return _icon_token("resource", input_name, INLINE_ICON_SIDE))
	if not recipe_lines.is_empty():
		lines.append("")
		lines.append("[b]%s[/b]" % tr("help_recipe_title"))
		lines.append_array(recipe_lines)
	var places: Array[String] = []
	for type_name in rules.recipe_workstation_types:
		var building_rules := BuildingCalculator.get_building_rules(type_name)
		if building_rules != null:
			places.append("[url=%s%s]%s[/url]" % [BUILDING_PAGE_PREFIX, type_name, tr(building_rules.building_name)])
	if not places.is_empty():
		lines.append("")
		lines.append(tr("help_recipe_made_in").format({"buildings": ", ".join(places)}))
	return "\n".join(lines)
