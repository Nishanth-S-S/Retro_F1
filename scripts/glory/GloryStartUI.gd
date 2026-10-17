extends Control
## New Road to Glory: build your driver - name, race number, face and the talent you start with.

var _look := {"skin": 1, "hair": 1, "hair_color": 0, "accessory": 0, "outfit": 2, "face": 1}
var _name := "ALEX STONE"
var _number := 27
var _talent := "speed"
var _portrait: Art
var _talent_note: Label
var _talent_buttons: Dictionary = {}
var _number_label: Label
var _helmet: Art


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	AudioManager.play_music(true)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	root.add_child(head)
	var back := UIKit.button("<-", 20)
	back.custom_minimum_size = Vector2(90, 58)
	back.pressed.connect(func() -> void: SceneManager.goto("saves"))
	head.add_child(back)
	head.add_child(UIKit.title_bar("CREATE YOUR DRIVER"))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 30)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(row)
	var left := VBoxContainer.new()
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 10)
	row.add_child(left)
	_portrait = Art.make(Vector2(300, 300), func(c: Control) -> void:
		PixelArt.draw_portrait(c, Rect2(Vector2.ZERO, c.size), _look, UIKit.WARM, Color("d8e6dc")))
	left.add_child(_portrait)
	_helmet = Art.make(Vector2(300, 90), func(c: Control) -> void:
		PixelArt.draw_helmet(c, Rect2(Vector2(80, 0), Vector2(140, 90)), UIKit.WARM, Color("f4f6f2"), _number))
	left.add_child(_helmet)
	var form := VBoxContainer.new()
	form.alignment = BoxContainer.ALIGNMENT_CENTER
	form.add_theme_constant_override("separation", 7)
	row.add_child(form)
	form.add_child(UIKit.label("AN UNKNOWN F3 ROOKIE. NO ACADEMY. NO GUARANTEES.", 14, UIKit.ACCENT))
	var name_edit := LineEdit.new()
	name_edit.text = _name
	name_edit.max_length = 18
	name_edit.custom_minimum_size = Vector2(420, 46)
	name_edit.add_theme_font_size_override("font_size", 20)
	name_edit.text_changed.connect(func(text: String) -> void: _name = text.to_upper())
	form.add_child(name_edit)
	# Race number.
	var num := HBoxContainer.new()
	num.add_theme_constant_override("separation", 8)
	form.add_child(num)
	_number_label = UIKit.label("", 15)
	_number_label.custom_minimum_size = Vector2(240, 0)
	_number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for step: int in [-1, 1]:
		var b := UIKit.button("<" if step < 0 else ">", 18)
		b.custom_minimum_size = Vector2(56, 40)
		b.pressed.connect(func() -> void:
			_number = posmod(_number - 2 + step, 98) + 2
			_refresh())
		num.add_child(b)
		if step < 0:
			num.add_child(_number_label)
	# Face, skin, hair... the same features a career manager has.
	var options := {"face": ["FACE", PixelArt.FACES], "skin": ["SKIN", PixelArt.SKIN.size()], "hair": ["HAIR", PixelArt.HAIR_STYLES], "hair_color": ["HAIR COLOUR", PixelArt.HAIR_COLORS.size()],
		"accessory": ["EXTRA", PixelArt.ACCESSORIES], "outfit": ["OUTFIT", PixelArt.OUTFITS]}
	for key: String in options:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		form.add_child(line)
		var names: Variant = options[key][1]
		var count: int = (names as PackedStringArray).size() if names is PackedStringArray else int(names)
		var value := UIKit.label("", 15)
		value.custom_minimum_size = Vector2(240, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var show := func() -> void:
			var idx := int(_look[key])
			value.text = "%s: %s" % [options[key][0], (names as PackedStringArray)[idx] if names is PackedStringArray else str(idx + 1)]
			_portrait.queue_redraw()
		for step: int in [-1, 1]:
			var b := UIKit.button("<" if step < 0 else ">", 18)
			b.custom_minimum_size = Vector2(56, 40)
			b.pressed.connect(func() -> void:
				_look[key] = posmod(int(_look[key]) + step, count)
				show.call())
			line.add_child(b)
			if step < 0:
				line.add_child(value)
		show.call()
	# Talent.
	form.add_child(UIKit.label("YOUR TALENT", 13, UIKit.HOT))
	var talents := HBoxContainer.new()
	talents.add_theme_constant_override("separation", 6)
	form.add_child(talents)
	for key: String in Glory.TALENTS:
		var b := UIKit.button(str(Glory.TALENTS[key]["name"]), 14)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(136, 44)
		b.pressed.connect(func() -> void:
			_talent = key
			_refresh())
		talents.add_child(b)
		_talent_buttons[key] = b
	_talent_note = UIKit.label("", 13, UIKit.TEXT_DIM)
	_talent_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_talent_note.custom_minimum_size = Vector2(420, 0)
	form.add_child(_talent_note)
	var start := UIKit.button("START ROAD TO GLORY", 22, true)
	start.custom_minimum_size = Vector2(420, 60)
	start.pressed.connect(func() -> void:
		Glory.new_game(_name if _name.strip_edges() != "" else "THE ROOKIE", _number, _look.duplicate(), _talent)
		SceneManager.goto("glory"))
	form.add_child(start)
	_refresh()


func _draw() -> void:
	UIKit.draw_backdrop(self, Rect2(Vector2.ZERO, size))


func _refresh() -> void:
	_number_label.text = "RACE NUMBER: %d" % _number
	_talent_note.text = str(Glory.TALENTS[_talent]["note"])
	for key: String in _talent_buttons:
		(_talent_buttons[key] as Button).button_pressed = key == _talent
	_portrait.queue_redraw()
	_helmet.queue_redraw()
