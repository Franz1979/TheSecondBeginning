class_name IconButtonRow
extends HBoxContainer

signal action_pressed(action_id: StringName)

@export var slot_count: int = 4

var _slots: Array[Button] = []

func _ready() -> void:
	alignment = ALIGNMENT_CENTER
	for i in range(slot_count):
		var slot := Button.new()
		slot.custom_minimum_size = Vector2(32, 32)
		slot.disabled = true
		slot.modulate = Color(1, 1, 1, 0.4)
		add_child(slot)
		_slots.append(slot)


func configure_slot(index: int, icon_text: String, tooltip: String, action_id: StringName) -> void:
	var slot := _slots[index]
	slot.text = icon_text
	slot.tooltip_text = tooltip
	slot.disabled = false
	slot.modulate = Color(1, 1, 1, 1)
	slot.pressed.connect(func() -> void: action_pressed.emit(action_id))
