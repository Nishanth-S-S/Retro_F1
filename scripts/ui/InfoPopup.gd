class_name InfoPopup
extends Control
## Modal card used for engineering tooltips and "car not ready" style notices.

signal closed

var _title: Label
var _body: Label
var _action: Button
var _action_callback: Callable


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	z_index = 50
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.07, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			close())
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := UIKit.panel(UIKit.PANEL, UIKit.ACCENT)
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	_title = UIKit.label("", 22, UIKit.ACCENT)
	box.add_child(_title)
	_body = UIKit.label("", 16)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(430, 0)
	box.add_child(_body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_action = UIKit.button("", 16, true)
	_action.custom_minimum_size = Vector2(150, 44)
	_action.pressed.connect(func() -> void:
		close()
		if _action_callback.is_valid():
			_action_callback.call())
	row.add_child(_action)
	var ok := UIKit.button("CLOSE", 16)
	ok.custom_minimum_size = Vector2(110, 44)
	ok.pressed.connect(close)
	row.add_child(ok)


func open(title: String, body: String, action_text: String = "", action: Callable = Callable()) -> void:
	_title.text = title
	_body.text = body
	_action.visible = action_text != ""
	_action.text = action_text
	_action_callback = action
	visible = true


func open_term(term: String) -> void:
	open(term, str(GameManager.tooltips.get(term, "No notes for this yet.")))


func close() -> void:
	visible = false
	closed.emit()
