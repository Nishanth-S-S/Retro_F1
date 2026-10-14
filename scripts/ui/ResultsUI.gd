extends Control
## Post-session screen, kept to the essentials: the result, the best lap, what it earned,
## the running order, and where to go next. Career races show the career summary instead.

var _results: Dictionary = {}


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_results = GameManager.last_results
	AudioManager.play_music(true)
	if _results.has("career_report"):
		RaceReport.show(self, _results["career_report"])
		return
	var mode: String = _results.get("mode", GameManager.MODE_TEST)
	var racing: bool = mode == GameManager.MODE_RACE
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UIKit.panel(UIKit.PANEL, UIKit.LINE)
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(UIKit.title_bar("%s  -  %s" % [GameManager.MODE_LABELS.get(mode, ""), GameManager.TRACK_NAMES.get(GameManager.track_id, "")], 54.0))
	var headline := "DONE"
	var color := UIKit.TEXT
	if _results.get("destroyed", false):
		headline = "CAR DESTROYED"
		color = UIKit.BAD
	elif racing and _results.get("finished", false):
		headline = "P%d" % int(_results["position"])
		color = UIKit.GOOD if int(_results["position"]) <= 3 else UIKit.TEXT
	elif racing:
		headline = "RETIRED"
		color = UIKit.BAD
	elif float(_results.get("best_lap", 0.0)) > 0.0:
		headline = LapTimer.format_time(float(_results["best_lap"]))
	var top := UIKit.label(headline, 64, color)
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(top)
	var facts := PackedStringArray()
	if racing and float(_results.get("best_lap", 0.0)) > 0.0:
		facts.append("BEST LAP %s" % LapTimer.format_time(float(_results["best_lap"])))
	if _results.get("new_pb", false):
		facts.append("NEW RECORD")
	var cash := int(_results.get("money", 0)) - int(_results.get("penalty", 0))
	if cash != 0:
		facts.append("%s%s" % ["+" if cash > 0 else "", UIKit.money(cash)])
	if not facts.is_empty():
		var line := UIKit.label("   ·   ".join(facts), 22, UIKit.ACCENT)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(line)
	# Running order: cars still on track when you took the flag are simply listed in order.
	var order: Array = _results.get("classification", [])
	if racing and order.size() > 1:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 40)
		box.add_child(grid)
		for i in order.size():
			var entry: Dictionary = order[i]
			var row := UIKit.label("%d  %s" % [i + 1, str(entry["name"]).to_upper()], 18, UIKit.WARM if entry["is_player"] else UIKit.TEXT)
			row.custom_minimum_size = Vector2(340, 0)
			grid.add_child(row)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	for info: Array in [["AGAIN", false, func() -> void: GameManager.start_free_session(mode)], ["GARAGE", true, func() -> void: SceneManager.goto("garage")], ["MENU", false, func() -> void: SceneManager.goto("menu")]]:
		var b := UIKit.button(info[0], 22, info[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 66)
		b.pressed.connect(info[2])
		buttons.add_child(b)
	if cash > 0:
		AudioManager.play("cash", -6.0)


func _draw() -> void:
	UIKit.draw_backdrop(self, Rect2(Vector2.ZERO, size))
