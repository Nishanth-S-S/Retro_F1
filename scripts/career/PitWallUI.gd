extends Control
## Race day from the pit wall. The race runs lap by lap; you call tires, pit stops, pace
## and team orders for your two cars and react to weather and safety cars.

const LAP_SECONDS: PackedFloat32Array = [1.6, 0.6]

var sim: GPSim
var _track: TrackData
var _outline := PackedVector2Array()
var _tower: Art
var _map: Art
var _status: Label
var _log: Label
var _log_lines: Array[String] = []
var _driver_boxes: Array[VBoxContainer] = []
var _order_buttons: Dictionary = {}
var _orders_button: Button
var _title: Control
var _driver_frames: Array[Frame] = []
var _run_button: Button
var _speed_button: Button
var _running := false
var _fast := 0
var _timer := 0.0
var _lap_anim := 0.0
var _started := false
var _report_shown := false


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not Career.active():
		SceneManager.call_deferred("goto", "career_start")
		set_process(false)
		return
	AudioManager.play_music(false)
	sim = Career.weekend_sim()
	_track = TrackData.load_track("res://data/tracks/%s.json" % Career.round_track())
	_build()
	_say("CHOOSE STARTING TIRES, THEN START")
	_refresh()


func _draw() -> void:
	UIKit.draw_backdrop(self, Rect2(Vector2.ZERO, size))


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	_title = UIKit.title_bar("PIT WALL", 50.0)
	root.add_child(_title)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	root.add_child(row)
	# --- running order
	var tower_frame := Frame.make("ORDER")
	tower_frame.custom_minimum_size = Vector2(280, 0)
	row.add_child(tower_frame)
	_tower = Art.make(Vector2(250, 0), _paint_tower)
	_tower.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tower_frame.body.add_child(_tower)
	# --- track map with the latest radio call underneath
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_theme_constant_override("separation", 8)
	row.add_child(centre)
	_status = UIKit.label("", 15)
	_status.visible = false
	centre.add_child(_status)
	var map_panel := UIKit.panel(UIKit.PANEL, UIKit.LINE)
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	centre.add_child(map_panel)
	_map = Art.make(Vector2(200, 200), _paint_map)
	map_panel.add_child(_map)
	_log = UIKit.label("", 14, UIKit.HOT)
	_log.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_log.clip_text = true
	centre.add_child(_log)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	centre.add_child(controls)
	_run_button = UIKit.button("START RACE", 18, true)
	_run_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_run_button.custom_minimum_size = Vector2(0, 54)
	_run_button.pressed.connect(_toggle_run)
	controls.add_child(_run_button)
	_speed_button = UIKit.button("x1", 16)
	_speed_button.custom_minimum_size = Vector2(80, 54)
	_speed_button.pressed.connect(func() -> void:
		_fast = 1 - _fast
		_speed_button.text = "x%d" % (1 + _fast * 2))
	controls.add_child(_speed_button)
	# --- one small console per car, and a single team-orders switch
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(300, 0)
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	for car in sim.player_cars():
		var frame := Frame.make("", 6)
		frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
		right.add_child(frame)
		_driver_boxes.append(frame.body)
		_driver_frames.append(frame)
	_orders_button = UIKit.button("", 13)
	_orders_button.custom_minimum_size = Vector2(0, 50)
	_orders_button.pressed.connect(func() -> void:
		var keys := ["free", "hold", "swap"]
		sim.team_order = keys[(keys.find(sim.team_order) + 1) % 3]
		_refresh())
	right.add_child(_orders_button)


func _say(text: String) -> void:
	_log.text = text


# ---------------------------------------------------------------- flow

func _toggle_run() -> void:
	if sim.finished():
		return
	_started = true
	_running = not _running
	_refresh()


func _process(delta: float) -> void:
	if _running and not sim.finished():
		_timer += delta
		_lap_anim = clampf(_timer / LAP_SECONDS[_fast], 0.0, 1.0)
		if _timer >= LAP_SECONDS[_fast]:
			_timer = 0.0
			_lap_anim = 0.0
			sim.step()
			for message in sim.messages:
				_say(message)
				if message.contains("SAFETY CAR DEPLOYED") or message.contains("FORECAST") or message.contains("CONTACT"):
					# Big moments stop the clock so you can react.
					_running = false
					AudioManager.play("beep", -8.0)
			_refresh()
	if sim.finished() and not _report_shown:
		_report_shown = true
		_running = false
		_show_report()
	_map.queue_redraw()


func _refresh() -> void:
	var extra := GPSim.WEATHER_NAMES[sim.weather]
	if sim.safety_car > 0:
		extra = "SAFETY CAR"
	elif sim.forecast_in > 0:
		extra = "%s IN %d" % [GPSim.WEATHER_NAMES[sim.forecast_to], sim.forecast_in]
	_title.set_meta("title", "LAP %d/%d - %s" % [mini(sim.lap + 1, sim.laps), sim.laps, extra])
	_title.queue_redraw()
	_run_button.text = "RACE OVER" if sim.finished() else ("PAUSE" if _running else ("RESUME" if _started else "START RACE"))
	_orders_button.text = "TEAM ORDERS: %s" % {"free": "LET THEM RACE", "hold": "HOLD POSITION", "swap": "SWAP CARS"}[sim.team_order]
	var mine := sim.player_cars()
	for i in mine.size():
		_driver_frames[i].caption = "%s  -  %s" % [str(mine[i]["name"]).get_slice(" ", 1).to_upper(), "OUT" if mine[i]["dnf"] else "P%d" % int(mine[i]["position"])]
		_driver_frames[i].queue_redraw()
		_build_console(_driver_boxes[i], mine[i])
	_tower.queue_redraw()


func _build_console(box: VBoxContainer, car: Dictionary) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	if car["dnf"]:
		box.add_child(UIKit.label("RETIRED", 16, UIKit.BAD))
		return
	var compound: Dictionary = GPSim.COMPOUNDS[car["tire"]]
	var wear := GPSim.tire_wear_fraction(car)
	box.add_child(Art.make(Vector2(0, 26), func(a: Control) -> void:
		var f := UIKit.font()
		a.draw_rect(Rect2(0, 2, 22, 22), Color(str(compound["color"])))
		a.draw_rect(Rect2(0, 2, 22, 22), UIKit.INK, false, 2.0)
		a.draw_string(f, Vector2(0, 19), str(car["tire"]), HORIZONTAL_ALIGNMENT_CENTER, 22, 13, UIKit.INK)
		var w := a.size.x - 32.0
		a.draw_rect(Rect2(32, 6, w, 14), UIKit.GRID_BOLD)
		a.draw_rect(Rect2(32, 6, w * clampf(1.0 - wear, 0.0, 1.0), 14), UIKit.GOOD if wear < 0.7 else (Color("c98a1a") if wear < 1.0 else UIKit.BAD))))
	var prompt := "START ON" if not _started else ("PIT FOR" if car["pit_request"] == "" else "BOXING THIS LAP")
	box.add_child(UIKit.label(prompt, 11, UIKit.HOT if car["pit_request"] != "" else UIKit.TEXT_DIM))
	var tires := HBoxContainer.new()
	tires.add_theme_constant_override("separation", 4)
	box.add_child(tires)
	for key: String in GPSim.COMPOUNDS:
		var b := UIKit.button(key, 14)
		b.toggle_mode = true
		b.button_pressed = (car["tire"] == key) if not _started else (car["pit_request"] == key)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 44)
		b.pressed.connect(func() -> void:
			if not _started:
				car["tire"] = key
			else:
				car["pit_request"] = "" if car["pit_request"] == key else key
			_refresh())
		tires.add_child(b)
	var pace := UIKit.button("PACE: %s" % GPSim.MODE_NAMES[car["mode"]], 13)
	pace.custom_minimum_size = Vector2(0, 44)
	pace.pressed.connect(func() -> void:
		car["mode"] = (int(car["mode"]) + 1) % 3
		_refresh())
	box.add_child(pace)


# ---------------------------------------------------------------- drawing

func _paint_tower(a: Control) -> void:
	var f := UIKit.font()
	var row_h := minf(27.0, (a.size.y - 4.0) / maxf(sim.cars.size(), 1))
	for i in sim.cars.size():
		var car: Dictionary = sim.cars[i]
		var y := 2.0 + i * row_h
		if car["is_player"]:
			a.draw_rect(Rect2(-4, y, a.size.x + 8, row_h - 2.0), Color(UIKit.WARM, 0.55))
		a.draw_rect(Rect2(28, y + 3.0, 5, row_h - 8.0), Color(str(car["color"])))
		var color := UIKit.TEXT_DIM if car["dnf"] else UIKit.TEXT
		a.draw_string(f, Vector2(0, y + row_h * 0.68), "%2d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
		a.draw_string(f, Vector2(40, y + row_h * 0.68), str(car["name"]).get_slice(" ", 1).to_upper().left(11), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
		var gap := "OUT" if car["dnf"] else ("LEADER" if i == 0 else "+%.1f" % float(car["gap"]))
		if car["status"] != "" and not car["dnf"]:
			gap = car["status"]
		a.draw_string(f, Vector2(0, y + row_h * 0.68), gap, HORIZONTAL_ALIGNMENT_RIGHT, a.size.x - 26.0, 12, color)
		if not car["dnf"]:
			var compound: Dictionary = GPSim.COMPOUNDS[car["tire"]]
			a.draw_rect(Rect2(a.size.x - 18.0, y + 3.0, 16, row_h - 8.0), Color(str(compound["color"])))
			a.draw_string(f, Vector2(a.size.x - 18.0, y + row_h * 0.68), str(car["tire"]), HORIZONTAL_ALIGNMENT_CENTER, 16, 10, UIKit.INK)


func _paint_map(a: Control) -> void:
	if _track == null:
		return
	var b := _track.bounds
	var s := minf((a.size.x - 40.0) / b.size.x, (a.size.y - 40.0) / b.size.y)
	var origin := (a.size - b.size * s) * 0.5 - b.position * s
	if _outline.is_empty() or _outline.size() != _track.count / 4 + 1:
		_outline.clear()
		for i in range(0, _track.count, 4):
			_outline.append(_track.points[i])
		_outline.append(_track.points[0])
	var pts := PackedVector2Array()
	for p in _outline:
		pts.append(p * s + origin)
	if sim.weather > 0:
		a.draw_rect(Rect2(Vector2.ZERO, a.size), Color(UIKit.ACCENT, 0.08 * sim.weather))
	a.draw_polyline(pts, UIKit.INK, 11.0)
	a.draw_polyline(pts, Color("e0a23a") if sim.safety_car > 0 else Color("4a4e57"), 7.0)
	var start := _track.points[0] * s + origin
	PixelArt.draw_checker(a, Rect2(start - Vector2(4, 12), Vector2(8, 24)), 4.0, Color.WHITE, UIKit.INK)
	# Cars: position on the lap comes from the gap to the leader.
	var f := UIKit.font()
	var labelled := 0
	for i in range(sim.cars.size() - 1, -1, -1):
		var car: Dictionary = sim.cars[i]
		if car["dnf"]:
			continue
		var frac := fposmod(_lap_anim - float(car["gap"]) / GPSim.BASE_LAP - 0.02, 1.0) if _started else fposmod(-0.004 * i - 0.01, 1.0)
		var p := _track.position_at(frac * _track.length) * s + origin
		var radius := 8.0 if car["is_player"] else 5.0
		a.draw_circle(p, radius + 2.0, UIKit.INK)
		a.draw_circle(p, radius, Color(str(car["color"])))
		if car["is_player"]:
			labelled += 1
			a.draw_string(f, p + Vector2(11, -8.0 if labelled == 1 else 16.0), str(car["name"]).get_slice(" ", 1).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.TEXT)


# ---------------------------------------------------------------- end of race

func _show_report() -> void:
	AudioManager.play("finish", -4.0)
	var report := Career.apply_race(sim.cars, sim.flags)
	Career.clear_weekend()
	RaceReport.show(self, report)
