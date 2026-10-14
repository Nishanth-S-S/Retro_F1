extends Control
## Career select. Each of the six saves is one career: continue it, or start a new one in
## an empty slot. The garage and records travel with the career.

var _delete_mode := false
var _grid: GridContainer
var _options: Button


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 50)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	root.add_child(UIKit.title_bar("CAREERS"))
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	root.add_child(_grid)
	var foot := HBoxContainer.new()
	root.add_child(foot)
	var back := UIKit.button("<-", 26)
	back.custom_minimum_size = Vector2(120, 66)
	back.pressed.connect(func() -> void: SceneManager.goto("menu"))
	foot.add_child(back)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(gap)
	_options = UIKit.button("DELETE", 18)
	_options.custom_minimum_size = Vector2(240, 66)
	_options.pressed.connect(func() -> void:
		_delete_mode = not _delete_mode
		_rebuild())
	foot.add_child(_options)
	_rebuild()


func _draw() -> void:
	UIKit.draw_backdrop(self, Rect2(Vector2.ZERO, size))


func _rebuild() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_options.text = "CANCEL" if _delete_mode else "DELETE"
	for i in range(1, SaveManager.SLOT_COUNT + 1):
		var data := SaveManager.slot_data(i)
		if i == SaveManager.slot:
			data = GameManager.profile
		var career: Dictionary = data.get("career", {})
		var running: bool = not career.is_empty() and career.get("active", false)
		var frame := Frame.make("CAREER %d" % i, 8)
		frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_grid.add_child(frame)
		frame.body.alignment = BoxContainer.ALIGNMENT_CENTER
		if running:
			var team := Career.team(str(career["team"]))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			frame.body.add_child(row)
			row.add_child(Art.make(Vector2(84, 84), func(a: Control) -> void: PixelArt.draw_logo(a, Rect2(Vector2.ZERO, a.size), team)))
			var info := VBoxContainer.new()
			info.add_theme_constant_override("separation", 2)
			row.add_child(info)
			info.add_child(UIKit.label(str(team.get("name", "?")).to_upper(), 20))
			info.add_child(UIKit.label("SEASON %d  ·  ROUND %d" % [int(career["season"]), int(career["round"]) + 1], 16, UIKit.TEXT_DIM))
			info.add_child(UIKit.label(UIKit.money(float(data.get("money", 0))), 18, UIKit.GOOD))
		else:
			var empty := UIKit.label("EMPTY", 26, UIKit.TEXT_DIM)
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			frame.body.add_child(empty)
		var text := "CONTINUE" if running else "NEW CAREER"
		if _delete_mode:
			text = "DELETE"
		var b := UIKit.button(text, 22, running or _delete_mode)
		b.custom_minimum_size = Vector2(0, 70)
		b.disabled = _delete_mode and not running
		b.pressed.connect(func() -> void:
			if _delete_mode:
				if i == SaveManager.slot:
					GameManager.reset_profile()
				else:
					SaveManager.delete_slot(i)
				_delete_mode = false
				_rebuild()
			else:
				GameManager.switch_slot(i)
				SceneManager.goto("career" if Career.active() else "career_start"))
		frame.body.add_child(b)
