extends Control
## Post-session screen: result, rewards, driving report, corner comparison and telemetry.

var _results: Dictionary = {}
var _analysis: Control
var _telemetry: Control


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_results = GameManager.last_results
	AudioManager.play_music(true)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	root.add_child(UIKit.title_bar("RESULTS", 50.0))
	root.add_child(_header())
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 10)
	root.add_child(columns)
	columns.add_child(_summary_panel())
	# Analysis and telemetry are one tap away instead of always on screen.
	_analysis = _analysis_panel()
	_telemetry = _telemetry_panel()
	_analysis.visible = false
	_telemetry.visible = false
	columns.add_child(_analysis)
	columns.add_child(_telemetry)
	root.add_child(_buttons())
	if int(_results.get("money", 0)) > 0 or int(_results.get("research", 0)) > 0:
		AudioManager.play("cash", -6.0)


func _draw() -> void:
	UIKit.draw_backdrop(self, Rect2(Vector2.ZERO, size))


func _header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var mode: String = _results.get("mode", GameManager.MODE_TEST)
	var headline := "SESSION COMPLETE"
	var color := UIKit.TEXT
	if mode == GameManager.MODE_RACE and _results.get("finished", false):
		headline = "P%d / %d" % [int(_results["position"]), int(_results["total_cars"])]
		color = UIKit.WARM if int(_results["position"]) <= 3 else UIKit.TEXT
	elif float(_results.get("best_lap", 0.0)) > 0.0:
		headline = LapTimer.format_time(float(_results["best_lap"]))
	var mission: Dictionary = _results.get("mission", {})
	if _results.get("destroyed", false):
		headline = "CAR DESTROYED"
		color = UIKit.BAD
	elif not mission.is_empty():
		headline = "MISSION COMPLETE" if mission["complete"] else "MISSION FAILED"
		color = UIKit.GOOD if mission["complete"] else UIKit.BAD
	row.add_child(UIKit.label(headline, 44, color))
	var sub := VBoxContainer.new()
	sub.alignment = BoxContainer.ALIGNMENT_CENTER
	sub.add_theme_constant_override("separation", -2)
	var top_line := "%s  ·  %s" % [GameManager.MODE_LABELS.get(mode, ""), GameManager.TRACK_NAMES.get(GameManager.track_id, "")]
	if not mission.is_empty():
		top_line = "STORY %d: %s  ·  %s" % [int(mission["index"]) + 1, str(mission["title"]).to_upper(), mission["objective"]]
	sub.add_child(UIKit.label(top_line, 14, UIKit.ACCENT))
	var note := "Race not finished" if mode == GameManager.MODE_RACE and not _results.get("finished", false) else ("NEW PERSONAL BEST" if _results.get("new_pb", false) else "Results and telemetry")
	sub.add_child(UIKit.label(note, 13, UIKit.PURPLE if _results.get("new_pb", false) else UIKit.TEXT_DIM))
	row.add_child(sub)
	return row


func _panel(title: String, min_width: float, expand: bool) -> Array:
	var panel := UIKit.panel()
	panel.custom_minimum_size = Vector2(min_width, 0)
	if expand:
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 3)
	scroll.add_child(box)
	box.add_child(UIKit.label(title, 13, UIKit.ACCENT))
	return [panel, box]


func _row(parent: Control, name: String, value: String, color: Color = UIKit.TEXT) -> void:
	var row := HBoxContainer.new()
	var l := UIKit.label(name, 12, UIKit.TEXT_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(UIKit.label(value, 15, color))
	parent.add_child(row)


func _summary_panel() -> Control:
	var made := _panel("RESULT", 420, true)
	var box: VBoxContainer = made[1]
	var mode: String = _results.get("mode", GameManager.MODE_TEST)
	var laps: Array = _results.get("laps", [])
	var mission: Dictionary = _results.get("mission", {})
	if not mission.is_empty() and mission["complete"]:
		if int(mission["reward"]) > 0:
			_row(box, "STORY REWARD", "$%d" % int(mission["reward"]), UIKit.GOOD)
		var unlocked: Array = mission["unlocked"]
		if not unlocked.is_empty():
			var l := UIKit.label("NEW PARTS UNLOCKED\n" + "\n".join(unlocked), 13, UIKit.PURPLE)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(l)
		box.add_child(UIKit.spacer(4))
	if mode == GameManager.MODE_RACE:
		_row(box, "POSITION", "P%d / %d" % [int(_results.get("position", 0)), int(_results.get("total_cars", 1))])
	_row(box, "TOTAL TIME", LapTimer.format_time(float(_results.get("total_time", 0.0))))
	_row(box, "BEST LAP", LapTimer.format_time(float(_results.get("best_lap", 0.0))), UIKit.PURPLE if _results.get("new_pb", false) else UIKit.TEXT)
	_row(box, "MONEY EARNED", UIKit.money(int(_results.get("money", 0))), UIKit.GOOD)
	if _results.get("destroyed", false):
		_row(box, "REBUILD COST", UIKit.money(-int(_results.get("penalty", 0))), UIKit.BAD)
	for line: String in _results.get("reward_lines", []):
		var l := UIKit.label("+ " + line, 11, UIKit.HOT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)
	box.add_child(UIKit.spacer(4))
	var classification: Array = _results.get("classification", [])
	if mode == GameManager.MODE_RACE and classification.size() > 1:
		box.add_child(UIKit.label("CLASSIFICATION", 13, UIKit.ACCENT))
		for i in classification.size():
			var entry: Dictionary = classification[i]
			var gap := "—"
			if entry["finished"]:
				gap = LapTimer.format_time(float(entry["time"])) if i == 0 else "+%.1f" % float(entry["gap"])
			elif int(entry["laps"]) < GameManager.RACE_LAPS:
				gap = "lap %d" % (int(entry["laps"]) + 1)
			_row(box, "%d  %s" % [i + 1, entry["name"]], gap, UIKit.WARM if entry["is_player"] else UIKit.TEXT)
	else:
		box.add_child(UIKit.label("LAPS", 13, UIKit.ACCENT))
		var valid: Array = _results.get("lap_valid", [])
		if laps.is_empty():
			box.add_child(UIKit.label("No completed laps.", 12, UIKit.TEXT_DIM))
		for i in laps.size():
			var ok: bool = valid[i] if i < valid.size() else true
			var is_best := ok and absf(float(laps[i]) - float(_results.get("best_lap", 0.0))) < 0.0005
			_row(box, "LAP %d%s" % [i + 1, "" if ok else "  (invalid)"], LapTimer.format_time(float(laps[i])), UIKit.PURPLE if is_best else (UIKit.TEXT if ok else UIKit.BAD))
	return made[0]


func _analysis_panel() -> Control:
	var made := _panel("DRIVING ANALYSIS", 330, false)
	var box: VBoxContainer = made[1]
	var report: Dictionary = _results.get("report", {})
	_row(box, "Best Lap", LapTimer.format_time(float(_results.get("best_lap", 0.0))))
	_row(box, "Average Corner Entry", "%d km/h" % int(report.get("avg_corner_entry", 0.0)))
	_row(box, "Maximum Speed", "%d km/h" % int(report.get("max_speed", 0.0)))
	_row(box, "Front Tire Peak", "%d°C" % int(report.get("front_peak", 0.0)), _temp_color(float(report.get("front_peak", 0.0))))
	_row(box, "Rear Tire Peak", "%d°C" % int(report.get("rear_peak", 0.0)), _temp_color(float(report.get("rear_peak", 0.0))))
	_row(box, "Time Spent Sliding", "%.1f sec" % float(report.get("sliding_time", 0.0)))
	var sectors: Array = _results.get("best_sectors", [])
	if sectors.size() == 3 and float(sectors[0]) > 0.0:
		_row(box, "Best Sectors", "%.2f  ·  %.2f  ·  %.2f" % [float(sectors[0]), float(sectors[1]), float(sectors[2])])
	box.add_child(UIKit.spacer(6))
	box.add_child(UIKit.label("CORNER ANALYSIS  ·  biggest losses vs your best", 13, UIKit.ACCENT))
	var corners: Array = _results.get("corners", [])
	if corners.is_empty():
		var note := UIKit.label(str(_results.get("corner_note", "")), 12, UIKit.TEXT_DIM)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(note)
	for corner: Dictionary in corners:
		var card := UIKit.panel(Color(UIKit.PANEL_LIGHT, 0.9), UIKit.LINE)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 0)
		card.add_child(inner)
		var loss := float(corner["loss"])
		var head := HBoxContainer.new()
		var title := UIKit.label(str(corner["name"]), 15, UIKit.TEXT)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		head.add_child(UIKit.label("%s s" % LapTimer.format_time(loss, true), 15, UIKit.BAD if loss > 0.0 else UIKit.GOOD))
		inner.add_child(head)
		inner.add_child(UIKit.label("This lap  %d km/h minimum    Best  %d km/h" % [int(corner["min"]), int(corner["best_min"])], 11, UIKit.TEXT_DIM))
		inner.add_child(UIKit.label("Entry %d → %d    Exit %d → %d   (best → this lap)" % [int(corner["best_entry"]), int(corner["entry"]), int(corner["best_exit"]), int(corner["exit"])], 11, UIKit.TEXT_DIM))
		box.add_child(card)
	return made[0]


func _temp_color(temp: float) -> Color:
	if temp > 112.0:
		return UIKit.BAD
	return UIKit.WARM if temp > 104.0 else UIKit.TEXT


func _telemetry_panel() -> Control:
	var panel := UIKit.panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(UIKit.label("TELEMETRY", 13, UIKit.ACCENT))
	var graph := (load("res://scenes/components/TelemetryGraph.tscn") as PackedScene).instantiate() as TelemetryGraph
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph.custom_minimum_size = Vector2(300, 240)
	graph.lap_label = "LAP %d" % int(_results.get("graph_lap_number", 1))
	graph.reference_label = "BEST (LAP %d)" % int(_results.get("graph_reference_number", 1))
	graph.set_data(_results.get("graph_lap", {}), _results.get("graph_reference", {}), float(_results.get("track_length", 1.0)))
	box.add_child(graph)
	return panel


func _buttons() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	var details := UIKit.button("SHOW TELEMETRY", 16)
	details.custom_minimum_size = Vector2(230, 56)
	details.pressed.connect(func() -> void:
		_analysis.visible = not _analysis.visible
		_telemetry.visible = _analysis.visible
		details.text = "HIDE TELEMETRY" if _analysis.visible else "SHOW TELEMETRY")
	row.add_child(details)
	if _results.has("career_report"):
		var hq := UIKit.button("BACK TO HQ", 20, true)
		hq.custom_minimum_size = Vector2(300, 56)
		hq.pressed.connect(func() -> void: SceneManager.goto("career"))
		row.add_child(hq)
		return row
	var retry := UIKit.button("RETRY", 20)
	retry.custom_minimum_size = Vector2(190, 54)
	retry.pressed.connect(func() -> void: GameManager.start_free_session(str(_results.get("mode", GameManager.MODE_TEST))))
	row.add_child(retry)
	var garage := UIKit.button("GARAGE", 20, true)
	garage.custom_minimum_size = Vector2(230, 54)
	garage.pressed.connect(func() -> void:
		GameManager.active_mission = -1
		SceneManager.goto("garage"))
	row.add_child(garage)
	var menu := UIKit.button("MAIN MENU", 20)
	menu.custom_minimum_size = Vector2(190, 54)
	menu.pressed.connect(func() -> void:
		GameManager.active_mission = -1
		SceneManager.goto("menu"))
	row.add_child(menu)
	return row
