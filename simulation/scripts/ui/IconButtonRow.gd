class_name IconButtonRow
extends HBoxContainer

signal action_pressed(action_id: StringName)

@export var slot_count: int = 4

var _slots: Array[TooltipButton] = []

func _ready() -> void:
	alignment = ALIGNMENT_CENTER
	for i in range(slot_count):
		var slot := TooltipButton.new()
		slot.custom_minimum_size = Vector2(32, 32)
		slot.disabled = true
		slot.modulate = Color(1, 1, 1, 0.4)
		add_child(slot)
		_slots.append(slot)


# description (opzionale) è la seconda riga, più piccola, del tooltip — vedi TooltipButton.
func configure_slot(index: int, icon_text: String, tooltip: String, action_id: StringName, description: String = "") -> void:
	var slot := _slots[index]
	slot.text = icon_text
	slot.tooltip_text = tooltip
	slot.tooltip_description = description
	slot.disabled = false
	slot.modulate = Color(1, 1, 1, 1)
	slot.pressed.connect(func() -> void: action_pressed.emit(action_id))


const ACTIVE_MODULATE := Color(1, 1, 1, 1)
const INACTIVE_MODULATE := Color(0.55, 0.55, 0.55, 0.75)

# Feedback visivo per bottoni-toggle (es. mostra/nascondi un layer): non tutti gli slot
# configurati sono toggle, quindi questo va chiamato esplicitamente dal chiamante quando lo
# stato cambia — configure_slot da sola resta neutra rispetto a questo concetto.
func set_slot_toggled(index: int, is_active: bool) -> void:
	_slots[index].modulate = ACTIVE_MODULATE if is_active else INACTIVE_MODULATE
