class_name DifficultyPanel
extends Control
## Difficulty overlay: five modes, ROOKIE to LEGEND, and the Free Drive weather.
## Shared by the main menu, the pause menu and race day.

signal closed

const WEATHER_CHOICES: PackedStringArray = ["BY TRACK", "DRY", "LIGHT RAIN", "HEAVY RAIN"]

var _mode_buttons: Array[Button] = []
var _weather_buttons: Array[Button] = []
var _note: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.07, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UIKit.panel(UIKit.PANEL, UIKit.LINE)
	panel.theme = UIKit.theme()
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(960, 0)
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)
	root.add_child(UIKit.title_bar("DIFFICULTY", 50.0))
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 8)
	root.add_child(modes)
	for i in Difficulty.NAMES.size():
		var b := UIKit.button(Difficulty.NAMES[i], 18)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 84)
		b.pressed.connect(func() -> void:
			Difficulty.apply_preset(i)
			_refresh())
		modes.add_child(b)
		_mode_buttons.append(b)
	_note = UIKit.label("", 18, UIKit.ACCENT)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_note)
	root.add_child(UIKit.label("FREE DRIVE WEATHER", 14, UIKit.HOT))
	var weather_row := HBoxContainer.new()
	weather_row.add_theme_constant_override("separation", 8)
	root.add_child(weather_row)
	for i in WEATHER_CHOICES.size():
		var b := UIKit.button(WEATHER_CHOICES[i], 16)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 60)
		b.pressed.connect(func() -> void:
			GameManager.set_setting("free_weather", i)
			_refresh())
		weather_row.add_child(b)
		_weather_buttons.append(b)
	var done := UIKit.button("DONE", 20, true)
	done.custom_minimum_size = Vector2(0, 62)
	done.pressed.connect(func() -> void:
		GameManager.save()
		visible = false
		closed.emit())
	root.add_child(done)


func open() -> void:
	_refresh()
	visible = true


func _refresh() -> void:
	var mode := Difficulty.mode()
	for i in _mode_buttons.size():
		_mode_buttons[i].button_pressed = i == mode
	_note.text = Difficulty.NOTES[mode]
	for i in _weather_buttons.size():
		_weather_buttons[i].button_pressed = i == int(GameManager.setting("free_weather"))
