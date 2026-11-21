class_name InstanceBuffer3D
extends RefCounted

# Copie di una MultiMesh che cambiano a ogni fotogramma (persone, animali), scritte tutte in un blocco di dati e
# consegnate al motore in una volta sola (2026-11-21, misura [3D TIME]: una chiamata per posizione e una per colore di
# ogni copia costavano circa 0,1 ms per corpo). Uso: begin(), add() per ogni copia, commit().
# Formato del blocco di Godot per TRANSFORM_3D: 12 numeri per copia (righe della base con l'origine in fondo), più 4 del
# colore se la MultiMesh usa i colori. Il blocco cresce raddoppiando (mai a ogni fotogramma); le copie in più restano
# nascoste (visible_instance_count).

var multimesh: MultiMesh
var _stride: int
var _data := PackedFloat32Array()
var _count := 0


func _init(target: MultiMesh) -> void:
	multimesh = target
	_stride = 16 if multimesh.use_colors else 12


func begin() -> void:
	_count = 0


func add(t: Transform3D, color: Color = Color.WHITE) -> void:
	var i := _count * _stride
	if i + _stride > _data.size():
		_data.resize(maxi(_data.size() * 2, _stride * 16))
	var b := t.basis
	var o := t.origin
	_data[i] = b.x.x
	_data[i + 1] = b.y.x
	_data[i + 2] = b.z.x
	_data[i + 3] = o.x
	_data[i + 4] = b.x.y
	_data[i + 5] = b.y.y
	_data[i + 6] = b.z.y
	_data[i + 7] = o.y
	_data[i + 8] = b.x.z
	_data[i + 9] = b.y.z
	_data[i + 10] = b.z.z
	_data[i + 11] = o.z
	if _stride == 16:
		_data[i + 12] = color.r
		_data[i + 13] = color.g
		_data[i + 14] = color.b
		_data[i + 15] = color.a
	_count += 1


func commit() -> void:
	var capacity := _data.size() / _stride
	if capacity == 0:
		multimesh.visible_instance_count = 0
		return
	if multimesh.instance_count != capacity:
		multimesh.instance_count = capacity
	multimesh.buffer = _data
	multimesh.visible_instance_count = _count
