class_name DemolishConfirmationDialog
extends ConfirmationDialog

# Conferma prima di demolire (2026-09-12, richiesta utente — "attiva il bottone Demolisci: ...
# mostra una conferma, stesso meccanismo già usato altrove nel progetto se esiste, altrimenti una
# semplice richiesta si/no") — STESSO schema minimale di ExitConfirmationDialog.gd (estende
# direttamente il ConfirmationDialog nativo di Godot invece di un Window custom come
# SaveConfirmationDialog, che serve tre opzioni invece di due — qui bastano OK/Annulla). A
# differenza di ExitConfirmationDialog (nessun parametro, testo sempre uguale), questo deve
# ricordare QUALE building demolire tra l'apertura e la conferma — oggi catturato nella callback
# `_pending_on_confirm` (building Variant, stesso principio "duck-typed, no import ciclico" di TaskReassignmentService: questa scena vive in
# gameplay/, Building in simulation/, nessun problema di dipendenza in questa direzione ma la firma
# resta comunque generica per coerenza con l'altro punto di introduzione recente dello stesso
# pattern).
#
# display_name/building_id passati già RISOLTI da GameScene.open_dialog (mai letti da rules/tr()
# qui dentro) — stesso principio "pannello muto, riceve solo dati già pronti" già seguito da
# BuildBar/GameInfoPanel per lo stesso genere di componente UI.
#
# GENERICO (2026-10-03, richiesta utente — conferma di "Svuota tutto"): open_confirmation apre lo stesso dialog con
# titolo, testo e pulsante di conferma dati dal chiamante e chiama `on_confirm` alla conferma. open_dialog (demolizione)
# è ora un suo caso particolare e continua a emettere demolish_confirmed.
signal demolish_confirmed(building: Variant)

var _pending_on_confirm: Callable = Callable()


func _ready() -> void:
	cancel_button_text = tr("demolish_confirmation_cancel")
	confirmed.connect(_on_confirmed)
	canceled.connect(_on_canceled)


# is_site (2026-09-27, richiesta utente): true per un cantiere non completo — testo, titolo e pulsante di
# conferma diversi ("Annulla cantiere"), perché lì la conferma annulla subito invece di segnare "da demolire".
# Una sola riga, senza a capo: size azzerata prima di popup_centered, così il dialog prende la larghezza minima
# del testo corrente invece di restare della misura dell'apertura precedente.
func open_dialog(building: Variant, display_name: String, building_id: int, is_site: bool = false) -> void:
	var prefix := "demolish_confirmation_site_" if is_site else "demolish_confirmation_"
	open_confirmation(
		tr(prefix + "title"),
		tr(prefix + "text").format({"building": display_name, "id": building_id}),
		tr(prefix + "confirm"),
		func(): demolish_confirmed.emit(building)
	)


# Conferma generica: testi già tradotti; righe separate da "\n" (nessun a capo automatico).
func open_confirmation(title_text: String, body_text: String, confirm_text: String, on_confirm: Callable) -> void:
	_pending_on_confirm = on_confirm
	title = title_text
	dialog_text = body_text
	ok_button_text = confirm_text
	dialog_autowrap = false
	exclusive = true
	size = Vector2i.ZERO
	popup_centered()


func _on_confirmed() -> void:
	var on_confirm := _pending_on_confirm
	_pending_on_confirm = Callable()
	if on_confirm.is_valid():
		on_confirm.call()


func _on_canceled() -> void:
	_pending_on_confirm = Callable()
