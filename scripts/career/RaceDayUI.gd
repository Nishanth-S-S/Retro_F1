extends Control
## Race day, kept simple: where and in what weather, then drive one of your cars or let
## the race simulate. The garage is one tap away for last-minute changes.

var _sim: GPSim


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not Career.active() or Career.state()["fired"] or not (str(Career.day_event()["type"]) in ["quali", "race"]):
		SceneManager.call_deferred("goto", "career")
		return
	var quali_day := str(Career.day_event()["type"]) == "quali"
	_sim = Career.weekend_sim()
	var round_info := Career.next_round()
	var track_id := Career.round_track()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	root.add_child(UIKit.title_bar("%s  -  %s" % [str(round_info["name"]), "QUALIFYING" if quali_day else "RACE"]))
	# --- where and when
	var where := HBoxContainer.new()
	where.add_theme_constant_override("separation", 20)
	root.add_child(where)
	var weather := _sim.weather
	where.add_child(Art.make(Vector2(96, 96), func(a: Control) -> void:
		a.draw_rect(Rect2(Vector2.ZERO, a.size), Color("23262e"))
		PixelArt.draw_weather(a, Vector2(18, 24), 6.0, weather)))
	var facts := VBoxContainer.new()
	facts.add_theme_constant_override("separation", 2)
	where.add_child(facts)
	facts.add_child(UIKit.label(str(GameManager.TRACK_NAMES.get(track_id, "")), 34))
	facts.add_child(UIKit.label("%s   ·   %s   ·   %s" % [Career.format_label(round_info), GPSim.WEATHER_NAMES[weather], TrackTheme.label(track_id)], 18, UIKit.TEXT_DIM))
	facts.add_child(UIKit.label("TRACK %s" % TrackData.load_track("res://data/tracks/%s.json" % track_id).width_text(), 14, UIKit.TEXT_DIM))
	for car in _sim.player_cars():
		var faults := Career.car_violations(Career.car_for(car["id"]))
		if not faults.is_empty():
			facts.add_child(UIKit.label("%s'S CAR IS ILLEGAL: %s" % [str(car["name"]).get_slice(" ", 1).to_upper(), faults[0]], 16, UIKit.BAD))
	# --- drive
	var drive := HBoxContainer.new()
	drive.add_theme_constant_override("separation", 14)
	drive.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(drive)
	var ready := BuildValidator.is_ready(GameManager.setup)
	for car in _sim.player_cars():
		var id: String = car["id"]
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 8)
		drive.add_child(col)
		if quali_day:
			# Saturday: one flying lap decides the grid slot.
			var done: bool = Career.quali_results.has(id)
			var q := UIKit.button(("QUALIFIED\n%s\nP%d" % [str(car["name"]).to_upper(), int(car["position"])]) if done else "QUALIFY\n%s\nONE FLYING LAP" % str(car["name"]).to_upper(), 24, not done)
			q.size_flags_vertical = Control.SIZE_EXPAND_FILL
			q.disabled = done or not ready
			q.pressed.connect(func() -> void: Career.prepare_quali(id))
			col.add_child(q)
			_effects(col, id)
			continue
		var b := UIKit.button("DRIVE\n%s\nSTARTS P%d" % [str(car["name"]).to_upper(), int(car["position"])], 26, true)
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.disabled = not ready
		b.pressed.connect(func() -> void: Career.prepare_drive(id))
		col.add_child(b)
		_effects(col, id)
	var quick := UIKit.button("DONE\nWITH QUALIFYING" if quali_day else "SIMULATE\nTHE RACE", 26)
	quick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quick.size_flags_vertical = Control.SIZE_EXPAND_FILL
	quick.pressed.connect(func() -> void:
		if quali_day:
			Career.finish_qualifying_day()
			SceneManager.goto("career")
		else:
			RaceReport.show(self, Career.quick_sim()))
	drive.add_child(quick)
	# --- footer
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	root.add_child(foot)
	var back := UIKit.button("<-  HQ", 18)
	back.custom_minimum_size = Vector2(200, 60)
	back.pressed.connect(func() -> void: SceneManager.goto("career"))
	foot.add_child(back)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(gap)
	var garage := UIKit.button("GARAGE", 16)
	garage.custom_minimum_size = Vector2(160, 60)
	garage.pressed.connect(func() -> void: SceneManager.goto("garage"))
	foot.add_child(garage)
	var panel := DifficultyPanel.new()
	var diff := UIKit.button(Difficulty.mode_name(), 16)
	diff.custom_minimum_size = Vector2(200, 60)
	diff.pressed.connect(func() -> void: panel.open())
	foot.add_child(diff)
	add_child(panel)
	# Rival pace is baked into the grid, so a change of difficulty re-runs qualifying.
	var pace_before := Difficulty.sim_car_bonus()
	panel.closed.connect(func() -> void:
		diff.text = Difficulty.mode_name()
		if not is_equal_approx(pace_before, Difficulty.sim_car_bonus()):
			Career.clear_weekend()
			SceneManager.goto("raceday"))
	if not ready:
		root.add_child(UIKit.label("THE CAR IS MISSING PARTS  -  FIX IT IN THE GARAGE", 16, UIKit.BAD))
	var first_choice: Control = drive.get_child(0)
	CoachMarks.run_once(self, "raceday", func() -> Array: return [
		[first_choice, "QUALIFY on Saturday: one flying lap sets your grid slot. RACE on Sunday: drive it yourself..."],
		[quick, "...or let it simulate. You can't skip a race weekend."],
		[garage, "Last-minute changes? The GARAGE is here."],
	])


func _draw() -> void:
	UIKit.draw_backdrop(self, Rect2(Vector2.ZERO, size))


## How this driver handles the car, compared with the other one you could drive.
func _effects(col: Control, id: String) -> void:
	var other := {}
	for car in _sim.player_cars():
		if car["id"] != id:
			other = Career.driver(car["id"])
	col.add_child(UIKit.label("AT THE WHEEL", 12, UIKit.HOT))
	HubPanels.driver_effects(col, Career.driver(id), other, 12)
