class_name StoryScene
extends Control
## Road to Glory dialogue: short lines with the speaker's portrait, one at a time. Tap to move
## on. A scene can end with choices; `done` is called with the chosen key ("" without choices).
## A line is [speaker, text] where speaker is a Glory.CAST key, "you", "title" (a full-width
## caption card) or "objective".

var _lines: Array = []
var _choices: Array = []
var _done: Callable
var _index := -1
var _box: VBoxContainer
var _portrait: Art
var _name: Label
var _text: Label
var _choice_row: HFlowContainer
var _title: Label
var _hint: Label
var _look: Dictionary = {}
var _accent := UIKit.WARM


## `choices` is [[key, label], ...].
static func play(parent: Node, lines: Array, choices: Array = [], done: Callable = Callable()) -> StoryScene:
	var scene := StoryScene.new()
	scene._lines = lines
	scene._choices = choices
	scene._done = done
	parent.add_child(scene)
	return scene


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UIKit.theme()
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.04, 0.05, 0.86)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_title = UIKit.label("", 46, Color.WHITE)
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title.grow_vertical = Control.GROW_DIRECTION_BOTH
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	var panel := UIKit.panel(UIKit.PANEL, UIKit.LINE)
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 40
	panel.offset_right = -40
	panel.offset_top = -270
	panel.offset_bottom = -30
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	_portrait = Art.make(Vector2(200, 200), func(a: Control) -> void:
		if not _look.is_empty():
			PixelArt.draw_portrait(a, Rect2(Vector2.ZERO, a.size), _look, _accent, Color("d8e6dc")))
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_portrait)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_box)
	_name = UIKit.label("", 18, UIKit.HOT)
	_box.add_child(_name)
	_text = UIKit.label("", 28)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(400, 0)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_box.add_child(_text)
	_choice_row = HFlowContainer.new()
	_choice_row.add_theme_constant_override("h_separation", 10)
	_choice_row.add_theme_constant_override("v_separation", 8)
	_box.add_child(_choice_row)
	_hint = UIKit.label("TAP TO CONTINUE", 12, UIKit.TEXT_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_box.add_child(_hint)
	_next()


func _gui_input(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed)
	if tapped and _choice_row.get_child_count() == 0:
		accept_event()
		_next()


func _next() -> void:
	if _choice_row.get_child_count() > 0:
		return
	_index += 1
	if _index >= _lines.size():
		if _choices.is_empty():
			_finish("")
		else:
			_show_choices()
		return
	var line: Array = _lines[_index]
	var who: String = line[0]
	var text: String = line[1]
	_title.visible = who == "title"
	_box.get_parent().get_parent().visible = who != "title"
	if who == "title":
		_title.text = text
		AudioManager.play("go", -10.0)
		return
	AudioManager.play("click", -16.0, 1.2)
	_text.text = text
	if who == "objective":
		_name.text = "OBJECTIVE UPDATED"
		_name.add_theme_color_override("font_color", Color("ffb347"))
		_look = {}
	elif who == "you":
		var me := Glory.me()
		_name.text = str(me["name"]).to_upper()
		_name.add_theme_color_override("font_color", UIKit.GOOD)
		_look = me["look"]
		_accent = Color(str(Glory.my_team().get("color", "#c8201e")))
	else:
		var info: Dictionary = Glory.CAST.get(who, {"name": who.to_upper(), "role": "", "look": PixelArt.default_look()})
		_name.text = "%s  ·  %s" % [_speaker_name(who, info), info["role"]]
		_name.add_theme_color_override("font_color", UIKit.HOT)
		_look = info["look"]
		_accent = Color("3a3f48")
	_portrait.visible = not _look.is_empty()
	_portrait.queue_redraw()
	_hint.visible = _index < _lines.size() - 1 or _choices.is_empty()


func _speaker_name(who: String, info: Dictionary) -> String:
	if who == "principal":
		return Glory.principal_name()
	return str(info["name"])


func _show_choices() -> void:
	_hint.visible = false
	for choice: Array in _choices:
		var key: String = choice[0]
		var b := UIKit.button(str(choice[1]), 16, choice == _choices[0])
		b.custom_minimum_size = Vector2(0, 54)
		b.pressed.connect(func() -> void: _finish(key))
		_choice_row.add_child(b)


func _finish(key: String) -> void:
	queue_free()
	if _done.is_valid():
		_done.call(key)
