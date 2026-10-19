class_name SettingsPanel
extends Control
## Settings overlay. Every change is applied live and persisted when the panel closes.

var _confirm_reset := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.07, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UIKit.panel(UIKit.PANEL, UIKit.ACCENT)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)
	root.add_child(UIKit.label("SETTINGS", 26, UIKit.ACCENT))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 36)
	root.add_child(columns)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	columns.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	columns.add_child(right)
	left.add_child(UIKit.label("AUDIO", 13, UIKit.TEXT_DIM))
	_slider(left, "Master Volume", "master_volume", 0.0, 1.0)
	_slider(left, "Music Volume", "music_volume", 0.0, 1.0)
	_slider(left, "Effects Volume", "effects_volume", 0.0, 1.0)
	left.add_child(UIKit.spacer(6))
	left.add_child(UIKit.label("CONTROLS", 13, UIKit.TEXT_DIM))
	_slider(left, "Steering Sensitivity", "steering_sensitivity", 0.5, 1.6)
	_slider(left, "Steering Smoothing", "steering_smoothing", 0.0, 1.0)
	_slider(left, "Control Opacity", "control_opacity", 0.15, 1.0)
	# SPLIT: brake button + throttle slider. PEDAL: one pedal, up to accelerate, down to brake.
	_choice(left, "Pedals", "control_layout", ["SPLIT", "PEDAL"])
	right.add_child(UIKit.label("ASSISTS", 13, UIKit.TEXT_DIM))
	_choice(right, "ABS", "abs", ["OFF", "LOW", "HIGH"])
	_choice(right, "Traction Control", "traction_control", ["OFF", "LOW", "HIGH"])
	_toggle(right, "Stability Assist", "stability_assist")
	_toggle(right, "Automatic Transmission", "automatic")
	_toggle(right, "Racing Line", "racing_line")
	right.add_child(UIKit.spacer(6))
	right.add_child(UIKit.label("CAMERA", 13, UIKit.TEXT_DIM))
	_toggle(right, "Camera Rotation", "camera_rotation")
	_slider(right, "Cockpit Field of View", "cockpit_fov", 0.0, 1.0)
	_toggle(right, "Reduced Halo (cockpit)", "reduced_halo")
	_toggle(right, "Reduced Camera Motion", "reduced_motion")
	_choice(right, "Graphics", "graphics", ["LOW", "MED", "HIGH"])
	_choice(right, "Retro Effects", "retro_fx", ["OFF", "SUBTLE", "STRONG"])
	right.add_child(UIKit.spacer(6))
	var reset := UIKit.button("RESET ALL PROGRESS", 14)
	reset.pressed.connect(func() -> void:
		if _confirm_reset:
			GameManager.reset_profile()
			reset.text = "PROGRESS RESET"
		else:
			_confirm_reset = true
			reset.text = "TAP AGAIN TO CONFIRM")
	right.add_child(reset)
	var close := UIKit.button("DONE", 18, true)
	close.custom_minimum_size = Vector2(180, 48)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(func() -> void:
		GameManager.save()
		visible = false)
	root.add_child(close)


func _row(parent: Control, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := UIKit.label(text, 16)
	l.custom_minimum_size = Vector2(210, 36)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	parent.add_child(row)
	return row


func _slider(parent: Control, text: String, key: String, min_value: float, max_value: float) -> void:
	var row := _row(parent, text)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = 0.01
	slider.value = float(GameManager.setting(key))
	slider.custom_minimum_size = Vector2(220, 36)
	slider.focus_mode = Control.FOCUS_NONE
	var value := UIKit.label("%d%%" % int(slider.value * 100.0), 14, UIKit.TEXT_DIM)
	value.custom_minimum_size = Vector2(48, 0)
	slider.value_changed.connect(func(v: float) -> void:
		GameManager.set_setting(key, v)
		value.text = "%d%%" % int(v * 100.0))
	row.add_child(slider)
	row.add_child(value)


func _choice(parent: Control, text: String, key: String, options: Array) -> void:
	var row := _row(parent, text)
	var buttons: Array[Button] = []
	for i in options.size():
		var b := UIKit.button(options[i], 14)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(70, 38)
		b.button_pressed = int(GameManager.setting(key)) == i
		b.pressed.connect(func() -> void:
			GameManager.set_setting(key, i)
			for j in buttons.size():
				buttons[j].button_pressed = j == i)
		buttons.append(b)
		row.add_child(b)


func _toggle(parent: Control, text: String, key: String) -> void:
	var row := _row(parent, text)
	var check := CheckButton.new()
	check.focus_mode = Control.FOCUS_NONE
	check.button_pressed = bool(GameManager.setting(key))
	check.toggled.connect(func(on: bool) -> void: GameManager.set_setting(key, on))
	row.add_child(check)
