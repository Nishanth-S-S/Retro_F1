extends Control
## New career: pick the team you will run, then build your manager.

var _team_id := ""
var _look := PixelArt.default_look()
var _name := "ALEX STONE"
var _page: Control


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	AudioManager.play_music(true)
	_show_teams()


func _draw() -> void:
	UIKit.draw_backdrop(self, Rect2(Vector2.ZERO, size))


func _fresh(title: String, back: Callable) -> VBoxContainer:
	if _page:
		_page.queue_free()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	_page = margin
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	root.add_child(head)
	var b := UIKit.button("<-", 20)
	b.custom_minimum_size = Vector2(90, 58)
	b.pressed.connect(back)
	head.add_child(b)
	head.add_child(UIKit.title_bar(title))
	return root


func _show_teams() -> void:
	var root := _fresh("CHOOSE YOUR TEAM", func() -> void: SceneManager.goto("menu"))
	root.add_child(UIKit.label("You are the new team principal. Bigger teams have more money and a faster car - and owners who expect trophies.", 13, UIKit.TEXT_DIM))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	root.add_child(grid)
	var base: Array = SaveManager.load_json("res://data/career/drivers.json")
	for team: Dictionary in Career.teams:
		var names := PackedStringArray()
		var total := 0.0
		for d: Dictionary in base:
			if d["team"] == team["id"]:
				names.append(str(d["name"]).get_slice(" ", 1))
				total += float(d["pace"])
		var card := Button.new()
		card.focus_mode = Control.FOCUS_NONE
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(0, 150)
		card.pressed.connect(func() -> void:
			AudioManager.play("click", -12.0)
			_team_id = team["id"]
			_show_manager())
		var t := team
		var art := Art.make(Vector2.ZERO, func(c: Control) -> void:
			var f := UIKit.font()
			PixelArt.draw_logo(c, Rect2(10, 10, 64, 64), t, f)
			c.draw_string(f, Vector2(84, 28), str(t["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, c.size.x - 90.0, 14, UIKit.TEXT)
			c.draw_string(f, Vector2(84, 48), " / ".join(names).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, c.size.x - 90.0, 10, UIKit.TEXT_DIM)
			c.draw_string(f, Vector2(84, 68), "BUDGET %s" % UIKit.money(float(t["budget"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.GOOD)
			for info: Array in [["CAR", float(t["car"]), 92.0], ["DRIVERS", total / 2.0, 112.0]]:
				c.draw_string(f, Vector2(10, float(info[2]) + 9.0), info[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIKit.TEXT_DIM)
				var w := c.size.x - 110.0
				c.draw_rect(Rect2(66, float(info[2]), w, 10), UIKit.GRID_BOLD)
				var bar := Color(str(t["color"]))
				c.draw_rect(Rect2(66, float(info[2]), w * (float(info[1]) - 50.0) / 50.0, 10), bar if bar.get_luminance() > 0.18 else bar.lightened(0.5))
				c.draw_string(f, Vector2(0, float(info[2]) + 10.0), "%d" % int(info[1]), HORIZONTAL_ALIGNMENT_RIGHT, c.size.x - 10.0, 12, UIKit.TEXT)
			c.draw_string(f, Vector2(10, 142), "OWNERS EXPECT P%d" % int(t["expectation"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIKit.BAD if int(t["expectation"]) <= 3 else UIKit.TEXT_DIM))
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.add_child(art)
		grid.add_child(card)


func _show_manager() -> void:
	var team := Career.team(_team_id)
	var root := _fresh("CREATE YOUR MANAGER", _show_teams)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 30)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(row)
	var portrait := Art.make(Vector2(360, 360), func(c: Control) -> void:
		PixelArt.draw_portrait(c, Rect2(Vector2.ZERO, c.size), _look, Color(str(team["color"])), Color("d8e6dc")))
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(portrait)
	var form := VBoxContainer.new()
	form.alignment = BoxContainer.ALIGNMENT_CENTER
	form.add_theme_constant_override("separation", 10)
	row.add_child(form)
	form.add_child(UIKit.label("TEAM PRINCIPAL  ·  %s" % str(team["name"]).to_upper(), 14, UIKit.ACCENT))
	var name_edit := LineEdit.new()
	name_edit.text = _name
	name_edit.max_length = 18
	name_edit.custom_minimum_size = Vector2(380, 46)
	name_edit.add_theme_font_size_override("font_size", 20)
	name_edit.text_changed.connect(func(text: String) -> void: _name = text.to_upper())
	form.add_child(name_edit)
	var options := {"skin": ["SKIN", PixelArt.SKIN.size()], "hair": ["HAIR", PixelArt.HAIR_STYLES.size()], "hair_color": ["HAIR COLOUR", PixelArt.HAIR_COLORS.size()], "accessory": ["EXTRA", PixelArt.ACCESSORIES.size()], "outfit": ["OUTFIT", PixelArt.OUTFITS.size()]}
	for key: String in options:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		form.add_child(line)
		var count: int = options[key][1]
		var value := UIKit.label("", 15)
		value.custom_minimum_size = Vector2(240, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var refresh := func() -> void:
			var idx := int(_look[key])
			var text := str(idx + 1)
			if key == "hair":
				text = PixelArt.HAIR_STYLES[idx]
			elif key == "accessory":
				text = PixelArt.ACCESSORIES[idx]
			elif key == "outfit":
				text = PixelArt.OUTFITS[idx]
			value.text = "%s: %s" % [options[key][0], text]
			portrait.queue_redraw()
		for step: int in [-1, 1]:
			var b := UIKit.button("<" if step < 0 else ">", 18)
			b.custom_minimum_size = Vector2(56, 44)
			b.pressed.connect(func() -> void:
				_look[key] = posmod(int(_look[key]) + step, count)
				refresh.call())
			line.add_child(b)
			if step < 0:
				line.add_child(value)
		refresh.call()
	form.add_child(UIKit.spacer(8))
	var start := UIKit.button("START CAREER", 22, true)
	start.custom_minimum_size = Vector2(380, 60)
	start.pressed.connect(func() -> void:
		Career.new_career(_team_id, {"name": _name if _name.strip_edges() != "" else "THE BOSS", "look": _look})
		SceneManager.goto("career"))
	form.add_child(start)
