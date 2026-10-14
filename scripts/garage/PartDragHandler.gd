class_name PartDragHandler
extends Control
## Carries a part from the shelf to the car: a floating chip follows the pointer, the
## workspace highlights valid hardpoints, and a successful drop snaps into place.

signal dropped(part: VehiclePart, slot: String)

var workspace: BlueprintWorkspace
var _chip: PanelContainer
var _chip_label: Label
var _part: VehiclePart
var _target := ""
var _tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 40
	_chip = UIKit.panel(Color(UIKit.PANEL_LIGHT, 0.96), UIKit.ACCENT)
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.visible = false
	add_child(_chip)
	_chip_label = UIKit.label("", 15)
	_chip.add_child(_chip_label)


func is_dragging() -> bool:
	return _part != null


func begin(part: VehiclePart, global_pos: Vector2) -> void:
	if _tween:
		_tween.kill()
	_part = part
	_chip_label.text = "%s\n%s" % [PartDB.CATEGORY_LABELS[part.category], part.display_name]
	_chip.visible = true
	_chip.modulate.a = 1.0
	_chip.scale = Vector2.ONE
	_chip.reset_size()
	move(global_pos)
	AudioManager.play("click", -10.0, 1.3)


func move(global_pos: Vector2) -> void:
	if _part == null:
		return
	_chip.global_position = global_pos - _chip.size * 0.5 - Vector2(0, 34)
	_target = workspace.update_drag(_part, global_pos - workspace.global_position)
	var ok := _target != ""
	_chip.add_theme_stylebox_override("panel", UIKit.box(Color(UIKit.PANEL_LIGHT, 0.96), UIKit.GOOD if ok else UIKit.ACCENT, 8, 2 if ok else 1, 12))


func release(global_pos: Vector2) -> void:
	if _part == null:
		return
	move(global_pos)
	var part := _part
	var slot := _target
	_part = null
	workspace.end_drag()
	_tween = create_tween()
	_chip.pivot_offset = _chip.size * 0.5
	if slot != "":
		# Snap: the chip shrinks into the hardpoint.
		var dest := workspace.global_position + workspace.slot_position(slot) - _chip.size * 0.5
		_tween.set_parallel(true)
		_tween.tween_property(_chip, "global_position", dest, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_tween.tween_property(_chip, "scale", Vector2(0.25, 0.25), 0.12)
		_tween.chain().tween_callback(func() -> void:
			_chip.visible = false
			dropped.emit(part, slot))
	else:
		AudioManager.play("deny", -10.0)
		_tween.tween_property(_chip, "modulate:a", 0.0, 0.18)
		_tween.tween_callback(func() -> void: _chip.visible = false)
