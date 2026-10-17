class_name PendingEntryService
extends RefCounted

# Voci della campanella ("In sospeso", PendingPanel) fuori da GameScene (2026-10-16, richiesta utente — primo passo del
# refactoring della campanella): qui la costruzione comune di una voce e le voci che non dipendono dallo stato della
# scena. Le altre raccolte (_collect_*_entries di GameScene) si spostano con i blocchi del refactoring della loro
# meccanica (docs/design/gamescene_refactoring.md). Senza stato.
#
# Una voce: {"key", "text", "kind", "id", "macro", "sort", "name", "detail"?, "enabled", "disabled_reason"}; `kind`
# decide cosa fa il clic (GameScene._on_pending_entry_activated): "building", "body", … oppure "idea" (apre l'albero).

const KIND_IDEA := "idea"


# Voce con i campi comuni: `centerable` = il suo posto si può centrare (cella viva), altrimenti spenta col motivo.
static func make_entry(key: String, text: String, data: Dictionary, centerable: bool) -> Dictionary:
	var entry := data.duplicate()
	entry["key"] = key
	entry["text"] = text
	entry["enabled"] = centerable
	entry["disabled_reason"] = "" if centerable else TranslationServer.translate("pending_not_centerable")
	return entry


# "Nessuna idea in sviluppo" (2026-10-16, richiesta utente): senza un'idea attiva i pensieri depositati vanno persi
# (IdeaProgressService.add_thoughts). Solo con l'albero delle idee disponibile (`tech_tree_available`: un edificio che
# accoglie i pensieri) e almeno un'idea che si potrebbe scegliere. Il clic apre l'albero.
static func collect_idea_entries(folk: Folk, tech_tree_available: bool) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if folk == null or not tech_tree_available or folk.active_idea_id != "":
		return entries
	var any_available := false
	for idea_id in IdeaCalculator.list_idea_ids():
		var idea := IdeaCalculator.get_idea(idea_id)
		if idea != null and IdeaProgressService.is_available(folk, idea) and not IdeaProgressService.is_hidden(folk, idea):
			any_available = true
			break
	if not any_available:
		return entries
	var name := TranslationServer.translate("pending_no_active_idea")
	var detail := TranslationServer.translate("pending_no_active_idea_detail")
	entries.append(make_entry("no_active_idea", "%s\n%s" % [name, detail], {
		"kind": KIND_IDEA, "id": -1, "macro": Vector2i(-1, -1), "sort": 0.0, "name": name, "detail": detail,
	}, true))
	return entries


# Voci "<villaggio>: senza centro" (2026-10-12, passo 2 Folk/Village; spostata da GameScene il 2026-10-16): una per
# villaggio con center_building_id -1 (centro demolito o crollato). Nessun posto da centrare: spenta con il
# suggerimento. Sparisce quando un nuovo centro completato ricollega il villaggio.
static func collect_village_without_center_entries(folk: Folk) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if folk == null:
		return entries
	for village in folk.villages:
		if village.center_building_id != -1:
			continue
		var text := TranslationServer.translate("pending_village_without_center").format({"village": village.get_display_name()})
		var entry := make_entry("village_without_center:%d" % village.id, text, {
			"kind": "none", "id": -1, "macro": Vector2i(-1, -1), "sort": float(village.id), "name": text,
		}, false)
		entry["disabled_reason"] = TranslationServer.translate("pending_village_without_center_detail")
		entries.append(entry)
	return entries
