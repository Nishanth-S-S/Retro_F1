extends Control
## Race day: the grid is set. Choose to drive the race yourself, run it from the pit wall,
## or quick-sim it.

var _sim: GPSim


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not Career.active() or Career.state()["fired"]:
		SceneManager.call_deferred("goto", "career")
		return
	_sim = Career.weekend_sim()
	var round_info := Career.next_round()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	root.add_child(UIKit.title_bar(str(round_info["name"])))
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 14)
	root.add_child(columns)
	# --- starting grid
	var grid := Frame.make("STARTING GRID")
	grid.custom_minimum_size = Vector2(470, 0)
	columns.add_child(grid)
	var tower := Art.make(Vector2(0, 0), _paint_grid)
	tower.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.body.add_child(tower)
	# --- options
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	columns.add_child(right)
	var info := Frame.make("CONDITIONS")
	right.add_child(info)
	info.body.add_child(UIKit.label("%d LAPS   ·   %s NOW   ·   RAIN CHANCE %d%%" % [_sim.laps, GPSim.WEATHER_NAMES[_sim.weather], int(float(round_info["rain"]) * 100.0)], 15))
	info.body.add_child(UIKit.label("CAR %d   ·   TEAM %d   ·   BOARD WANTS: %s" % [int(Career.car_rating(Career.state()["team"])), Career.team_rating(Career.state()["team"]), Career.board_target_text().to_upper()], 13, UIKit.TEXT_DIM))
	var track_id := Career.round_track()
	info.body.add_child(UIKit.label("%s   ·   %s CIRCUIT" % [TrackTheme.label(track_id), Career.TRACK_TYPES.get(track_id, "")], 13, UIKit.TEXT_DIM))
	for car in _sim.player_cars():
		var d := Career.driver(car["id"])
		var machine := Career.car_for(car["id"])
		var note := Career.form_note(d, track_id) if Career.scout_level(d) >= 3 else ""
		var faults := Career.car_violations(machine)
		var line := "%s: %s, FIT %d%s%s" % [str(d["name"]).get_slice(" ", 1).to_upper(), machine["name"], Career.car_fit(d, machine), ("   ·   " + note) if note != "" else "", "   ·   CAR IS ILLEGAL" if not faults.is_empty() else ""]
		info.body.add_child(UIKit.label(line, 12, UIKit.BAD if not faults.is_empty() or note.begins_with("STRUGGLES") else UIKit.GOOD))
	var options := Frame.make("RACE OPTIONS", 10)
	options.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(options)
	var ready := BuildValidator.is_ready(GameManager.setup)
	for car in _sim.player_cars():
		var id: String = car["id"]
		var b := UIKit.button(">  DRIVE IT  -  %s  (P%d)" % [str(car["name"]).to_upper(), int(car["position"])], 18, true)
		b.custom_minimum_size = Vector2(0, 66)
		b.disabled = not ready
		b.pressed.connect(func() -> void: Career.prepare_drive(id))
		options.body.add_child(b)
	if not ready:
		options.body.add_child(UIKit.label("Your garage car is missing parts - fix it to drive.", 12, UIKit.BAD))
	var wall := UIKit.button("oo  PIT WALL  -  CALL THE STRATEGY", 18)
	wall.custom_minimum_size = Vector2(0, 66)
	wall.pressed.connect(func() -> void: SceneManager.goto("pitwall"))
	options.body.add_child(wall)
	var quick := UIKit.button(">>>  QUICK SIM", 18)
	quick.custom_minimum_size = Vector2(0, 66)
	quick.pressed.connect(func() -> void: RaceReport.show(self, Career.quick_sim()))
	options.body.add_child(quick)
	var hint := UIKit.label("Driving puts you on track against the seven cars around you on the grid. Your team mate's race is simulated.", 12, UIKit.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(300, 0)
	options.body.add_child(hint)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	root.add_child(foot)
	var back := UIKit.button("<-  BACK TO HQ", 18)
	back.custom_minimum_size = Vector2(0, 60)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func() -> void: SceneManager.goto("career"))
	foot.add_child(back)
	var panel := DifficultyPanel.new()
	var diff := UIKit.button("DIFFICULTY: %s" % Difficulty.mode_name(), 16)
	diff.custom_minimum_size = Vector2(340, 60)
	diff.pressed.connect(func() -> void: panel.open())
	foot.add_child(diff)
	add_child(panel)
	# Rival pace is baked into the grid, so a change re-runs qualifying.
	var pace_before := Difficulty.sim_car_bonus()
	panel.closed.connect(func() -> void:
		diff.text = "DIFFICULTY: %s" % Difficulty.mode_name()
		if not is_equal_approx(pace_before, Difficulty.sim_car_bonus()):
			Career.clear_weekend()
			SceneManager.goto("raceday"))


func _draw() -> void:
	UIKit.draw_backdrop(self, Rect2(Vector2.ZERO, size))


func _paint_grid(a: Control) -> void:
	var f := UIKit.font()
	var row_h := minf(26.0, (a.size.y - 18.0) / 22.5)
	PixelArt.draw_checker(a, Rect2(0, 0, a.size.x, 8), 8.0, Color.WHITE, UIKit.INK)
	for i in _sim.cars.size():
		var car: Dictionary = _sim.cars[i]
		# Two-wide staggered grid, pole on the left.
		var col := i % 2
		var x := col * a.size.x * 0.5 + 4.0
		var y := 14.0 + i * row_h
		if car["is_player"]:
			a.draw_rect(Rect2(x - 2.0, y - 2.0, a.size.x * 0.5 - 8.0, row_h), Color(UIKit.WARM, 0.6))
		PixelArt.draw_car(a, Vector2(x + 30.0, y + 2.0), 1.5, Color(str(car["color"])), Color.WHITE)
		a.draw_string(f, Vector2(x, y + row_h * 0.62), "%2d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.TEXT_DIM)
		a.draw_string(f, Vector2(x + 76.0, y + row_h * 0.62), str(car["name"]).get_slice(" ", 1).to_upper().left(11), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.TEXT)
