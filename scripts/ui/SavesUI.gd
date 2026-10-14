extends Control
## Save slot select. Each slot is a separate profile: its own career, garage and records.

var _delete_mode := false
var _grid: GridContainer
var _options: Button


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 70)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	root.add_child(UIKit.title_bar("SELECT SAVE SLOT"))
	var outer := UIKit.panel(Color(1, 1, 1, 0.0), Color.TRANSPARENT)
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(outer)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	outer.add_child(_grid)
	var foot := HBoxContainer.new()
	root.add_child(foot)
	var back := UIKit.button("<-", 26)
	back.custom_minimum_size = Vector2(110, 60)
	back.pressed.connect(func() -> void: SceneManager.goto("menu"))
	foot.add_child(back)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(gap)
	_options = UIKit.button("DELETE A SAVE", 16)
	_options.custom_minimum_size = Vector2(240, 60)
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
	_options.text = "CANCEL DELETE" if _delete_mode else "DELETE A SAVE"
	for i in range(1, SaveManager.SLOT_COUNT + 1):
		var data := SaveManager.slot_data(i)
		if i == SaveManager.slot:
			data = GameManager.profile
		var current := i == SaveManager.slot
		var frame := Frame.make("SAVE %d%s" % [i, "  (IN USE)" if current else ""])
		frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_grid.add_child(frame)
		var career: Dictionary = data.get("career", {})
		var text := "New Game"
		var team: Dictionary = {}
		if not data.is_empty():
			text = "FREE DRIVE  %s" % UIKit.money(float(data.get("money", 0)))
			if not career.is_empty() and career.get("active", false):
				team = Career.team(str(career["team"]))
				text = "[%s] S%d R%d  %s" % [team.get("short", "?"), int(career["season"]), int(career["round"]) + 1, UIKit.money(float(data.get("money", 0)))]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		frame.body.add_child(row)
		if not team.is_empty():
			var t := team
			row.add_child(Art.make(Vector2(52, 52), func(a: Control) -> void: PixelArt.draw_logo(a, Rect2(Vector2.ZERO, a.size), t)))
		var b := UIKit.button(("DELETE: " + text) if _delete_mode and not data.is_empty() else text, 15, _delete_mode and not data.is_empty())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 60)
		b.disabled = _delete_mode and (data.is_empty() or current)
		b.pressed.connect(func() -> void:
			if _delete_mode:
				SaveManager.delete_slot(i)
				_delete_mode = false
				_rebuild()
			else:
				GameManager.switch_slot(i)
				SceneManager.goto("menu"))
		row.add_child(b)
