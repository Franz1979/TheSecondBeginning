class_name DemolishConfirmationDialog
extends ConfirmationDialog

# Conferma prima di demolire (2026-09-12, richiesta utente — "attiva il bottone Demolisci: ...
# mostra una conferma, stesso meccanismo già usato altrove nel progetto se esiste, altrimenti una
# semplice richiesta si/no") — STESSO schema minimale di ExitConfirmationDialog.gd (estende
# direttamente il ConfirmationDialog nativo di Godot invece di un Window custom come
# SaveConfirmationDialog, che serve tre opzioni invece di due — qui bastano OK/Annulla). A
# differenza di ExitConfirmationDialog (nessun parametro, testo sempre uguale), questo deve
# ricordare QUALE building demolire tra l'apertura e la conferma — `_pending_building` (Variant,
# stesso principio "duck-typed, no import ciclico" di TaskReassignmentService: questa scena vive in
# gameplay/, Building in simulation/, nessun problema di dipendenza in questa direzione ma la firma
# resta comunque generica per coerenza con l'altro punto di introduzione recente dello stesso
# pattern).
#
# display_name/building_id passati già RISOLTI da GameScene.open_dialog (mai letti da rules/tr()
# qui dentro) — stesso principio "pannello muto, riceve solo dati già pronti" già seguito da
# BuildBar/GameInfoPanel per lo stesso genere di componente UI.
signal demolish_confirmed(building: Variant)

var _pending_building: Variant = null


func _ready() -> void:
	cancel_button_text = tr("demolish_confirmation_cancel")
	confirmed.connect(_on_confirmed)
	canceled.connect(_on_canceled)


# is_site (2026-09-27, richiesta utente): true per un cantiere non completo — testo, titolo e pulsante di
# conferma diversi ("Annulla cantiere"), perché lì la conferma annulla subito invece di segnare "da demolire".
# Una sola riga, senza a capo: size azzerata prima di popup_centered, così il dialog prende la larghezza minima
# del testo corrente invece di restare della misura dell'apertura precedente.
func open_dialog(building: Variant, display_name: String, building_id: int, is_site: bool = false) -> void:
	_pending_building = building
	var prefix := "demolish_confirmation_site_" if is_site else "demolish_confirmation_"
	title = tr(prefix + "title")
	dialog_text = tr(prefix + "text").format({"building": display_name, "id": building_id})
	ok_button_text = tr(prefix + "confirm")
	dialog_autowrap = false
	exclusive = true
	size = Vector2i.ZERO
	popup_centered()


func _on_confirmed() -> void:
	if _pending_building != null:
		demolish_confirmed.emit(_pending_building)
	_pending_building = null


func _on_canceled() -> void:
	_pending_building = null
