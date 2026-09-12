class_name IconButtonRow
extends HBoxContainer

signal action_pressed(action_id: StringName)

@export var slot_count: int = 4

var _slots: Array[TooltipButton] = []

# Tooltip "normale" di ogni slot, quello passato a configure_slot (2026-09-07, BUGFIX: mancava un
# modo di ripristinarlo dopo un set_slot_disabled(false), vedi lì) — array parallelo a _slots,
# indicizzato allo stesso modo.
var _slot_enabled_tooltips: Array[String] = []

func _ready() -> void:
	alignment = ALIGNMENT_CENTER
	for i in range(slot_count):
		var slot := TooltipButton.new()
		slot.custom_minimum_size = Vector2(32, 32)
		slot.disabled = true
		slot.modulate = Color(1, 1, 1, 0.4)
		add_child(slot)
		_slots.append(slot)
		_slot_enabled_tooltips.append("")


# description (opzionale) è la seconda riga, più piccola, del tooltip — vedi TooltipButton.
# enabled=false (richiesta utente, 2026-09-04 — placeholder "statistiche" in PrimaryActionsBar):
# mostra icona/tooltip come un slot normale ma resta disabled/dim (stesso aspetto "vuoto" di uno
# slot mai configurato, vedi _ready sopra) e NON collega pressed/action_id — un futuro passo che
# implementa davvero l'azione richiamerà questo stesso metodo con enabled=true (default, comporta-
# mento invariato per tutti i chiamanti esistenti).
#
# icon_node (opzionale, 2026-09-07, richiesta utente — Pebble Circle: nessun emoji Unicode rendeva
# bene "cerchio di sassolini", vedi PebbleCircleIcon) — un Control disegnato a mano al posto del testo-
# emoji, per gli slot dove nessun singolo carattere basta. Se fornito, sostituisce icon_text
# (svuotato) ed è aggiunto come figlio dello slot, con ancore+offset impostati DIRETTAMENTE (non
# via set_anchors_preset — BUGFIX 2026-09-07, richiesta utente: "il bottone sembra vuoto" — il
# preset di default usa resize_mode=PRESET_MODE_MINSIZE, che dimensiona il figlio sulla sua PROPRIA
# minimum size, zero per un Control senza testo/figli come PebbleCircleIcon, invece di farlo
# combaciare col rect del bottone) così riempie sempre l'intero bottone qualunque sia la sua
# dimensione, senza ambiguità di resize_mode. Default null: comportamento invariato (testo/emoji)
# per tutti i chiamanti esistenti.
func configure_slot(
	index: int, icon_text: String, tooltip: String, action_id: StringName, description: String = "",
	enabled: bool = true, icon_node: Control = null
) -> void:
	var slot := _slots[index]
	slot.text = "" if icon_node != null else icon_text
	slot.tooltip_text = tooltip
	_slot_enabled_tooltips[index] = tooltip
	slot.tooltip_description = description
	slot.disabled = not enabled
	slot.modulate = Color(1, 1, 1, 1) if enabled else Color(1, 1, 1, 0.4)
	if enabled:
		slot.pressed.connect(func() -> void: action_pressed.emit(action_id))
	if icon_node != null:
		slot.add_child(icon_node)
		icon_node.anchor_left = 0.0
		icon_node.anchor_top = 0.0
		icon_node.anchor_right = 1.0
		icon_node.anchor_bottom = 1.0
		icon_node.offset_left = 0.0
		icon_node.offset_top = 0.0
		icon_node.offset_right = 0.0
		icon_node.offset_bottom = 0.0


const ACTIVE_MODULATE := Color(1, 1, 1, 1)
const INACTIVE_MODULATE := Color(0.55, 0.55, 0.55, 0.75)

# Feedback visivo per bottoni-toggle (es. mostra/nascondi un layer): non tutti gli slot
# configurati sono toggle, quindi questo va chiamato esplicitamente dal chiamante quando lo
# stato cambia — configure_slot da sola resta neutra rispetto a questo concetto.
func set_slot_toggled(index: int, is_active: bool) -> void:
	_slots[index].modulate = ACTIVE_MODULATE if is_active else INACTIVE_MODULATE


# Disabilita/riabilita uno slot GIÀ configurato, sostituendone anche il tooltip (2026-09-07,
# richiesta utente — Pebble Circle: un tipo di edificio disponibile solo finché non ne esiste già
# uno nel mondo). A differenza di set_slot_toggled sopra (che cambia SOLO la tinta, per bottoni
# ancora cliccabili — es. i toggle mostra/nascondi), questo rende il bottone davvero non
# cliccabile: `pressed` non scatta più su un Button con disabled=true, nessuna disconnessione del
# segnale da fare. disabled_tooltip sostituisce tooltip_text SOLO quando disabled è true; alla
# riabilitazione (disabled=false) il tooltip torna a quello "normale" passato a configure_slot
# (BUGFIX 2026-09-07: la prima versione non lo ripristinava mai, un edificio che tornava
# disponibile restava con la spiegazione del blocco precedente scritta sopra).
func set_slot_disabled(index: int, disabled: bool, disabled_tooltip: String = "") -> void:
	var slot := _slots[index]
	slot.disabled = disabled
	slot.modulate = Color(1, 1, 1, 0.4) if disabled else Color(1, 1, 1, 1)
	if disabled and disabled_tooltip != "":
		slot.tooltip_text = disabled_tooltip
	elif not disabled:
		slot.tooltip_text = _slot_enabled_tooltips[index]
