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

var _current_page: String = PAGE_MAIN


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


func _on_meta_clicked(meta: Variant) -> void:
	_show_page(str(meta))


# Indietro (2026-10-07): dalla scheda di un edificio all'elenco degli edifici, da ogni altra pagina all'indice.
func _on_back_pressed() -> void:
	_show_page(PAGE_BUILDINGS if _current_page.begins_with(BUILDING_PAGE_PREFIX) else PAGE_MAIN)


func _show_page(page: String) -> void:
	_current_page = page
	back_button.visible = page != PAGE_MAIN
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
		_:
			if page.begins_with(BUILDING_PAGE_PREFIX):
				content_label.text = _build_building_page_text(page.substr(BUILDING_PAGE_PREFIX.length()))
			else:
				content_label.text = _build_main_menu_text()
	content_label.scroll_to_line(0)


func _build_main_menu_text() -> String:
	var lines: Array[String] = [
		"[b]%s[/b]" % tr("help_dialog_title"),
		"",
		"[url=%s]%s[/url]" % [PAGE_SHORTCUTS, tr("help_shortcuts_menu_link")],
		"[url=%s]%s[/url]" % [PAGE_FOG_OF_WAR, tr("help_fog_of_war_menu_link")],
		"[url=%s]%s[/url]" % [PAGE_ERA_ADVANCEMENT, tr("help_era_advancement_menu_link")],
		"[url=%s]%s[/url]" % [PAGE_BUILDING_MATERIALS, tr("help_building_materials_menu_link")],
		"[url=%s]%s[/url]" % [PAGE_BUILDINGS, tr("help_buildings_menu_link")],
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
# (materiali e lavoro, gli stessi dati del tooltip di costo, BuildingCostTooltip.get_build_materials — come testo: le
# icone del tooltip sono nodi disegnati che il testo dell'aiuto non può contenere); le righe Info del tipo
# (BuildingInfoLines.build); l'idea richiesta, se c'è; "Si migliora in: X", se c'è, che apre la scheda di X.
func _build_building_page_text(type_name: String) -> String:
	var rules := BuildingCalculator.get_building_rules(type_name)
	if rules == null:
		return _build_buildings_list_text()
	var lines: Array[String] = ["[b]%s[/b]" % tr(rules.building_name)]
	var description := BuildingCostTooltip.get_short_description(type_name)
	if description != "":
		lines.append(description)
	lines.append("")
	var materials := BuildingCostTooltip.get_build_materials(rules)
	var material_names: Array = materials.keys()
	material_names.sort()
	var material_parts: Array[String] = []
	for material_name in material_names:
		material_parts.append("%d %s" % [int(materials[material_name]), IconRegistry.get_resource_display_name(String(material_name))])
	lines.append(tr("help_buildings_materials").format({
		"items": ", ".join(material_parts) if not material_parts.is_empty() else tr("building_upgrade_nothing"),
	}))
	lines.append(tr("building_upgrade_labor").format({"labor": rules.required_labor}))
	lines.append("")
	for row in BuildingInfoLines.build(rules):
		lines.append((INFO_ROW_INDENT if bool(row.get("indent", false)) else "") + String(row["text"]))
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
