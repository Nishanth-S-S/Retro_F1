class_name SimPicker
extends Control
## The NEXT popup: scroll between NEXT DAY, NEXT WEEK, NEXT RACE and NEXT MONTH with the
## arrows (or a swipe) and SIM. Every option stops at the next race weekend - you can
## never sim past a race.

signal chosen(span: String)

const OPTIONS: Array = [["NEXT DAY", "day"], ["NEXT WEEK", "week"], ["NEXT RACE", "race"], ["NEXT MONTH", "month"]]

var _index := 0
var _title: Label
var _target: Label
var _press_x := 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			queue_free())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := UIKit.panel(UIKit.PANEL, UIKit.LINE)
	panel.custom_minimum_size = Vector2(720, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(UIKit.title_bar("SIM TO", 50.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var left := UIKit.button("<", 34)
	left.custom_minimum_size = Vector2(96, 120)
	left.pressed.connect(func() -> void: _step(-1))
	row.add_child(left)
	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.alignment = BoxContainer.ALIGNMENT_CENTER
	middle.mouse_filter = Control.MOUSE_FILTER_STOP
	middle.gui_input.connect(_swipe)
	row.add_child(middle)
	_title = UIKit.label("", 40, UIKit.WARM)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(_title)
	_target = UIKit.label("", 18, UIKit.TEXT_DIM)
	_target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(_target)
	var right := UIKit.button(">", 34)
	right.custom_minimum_size = Vector2(96, 120)
	right.pressed.connect(func() -> void: _step(1))
	row.add_child(right)
	var go := UIKit.button("SIM", 26, true)
	go.custom_minimum_size = Vector2(0, 72)
	go.pressed.connect(func() -> void:
		chosen.emit(str(OPTIONS[_index][1]))
		queue_free())
	box.add_child(go)
	_refresh()


func _step(direction: int) -> void:
	_index = posmod(_index + direction, OPTIONS.size())
	AudioManager.play("click", -12.0)
	_title.pivot_offset = _title.size * 0.5
	_title.scale = Vector2(0.85, 0.85)
	_title.create_tween().tween_property(_title, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK)
	_refresh()


func _swipe(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_x = event.position.x
		elif absf(event.position.x - _press_x) > 40.0:
			_step(-1 if event.position.x > _press_x else 1)


func _refresh() -> void:
	var span: String = OPTIONS[_index][1]
	_title.text = OPTIONS[_index][0]
	var days := Career.sim_days(span)
	var landing := Career.day_event(Career.today() + days)
	var stop := ""
	if str(landing["type"]) in ["quali", "race"]:
		stop = "  ·  STOPS FOR THE RACE WEEKEND"
	_target.text = "%s  ·  %d DAY%s%s" % [Career.date_text(Career.today() + days), days, "" if days == 1 else "S", stop]
