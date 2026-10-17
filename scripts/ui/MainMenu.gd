extends Control
## Main menu: modes on the left, the game crest on the right, current save underneath.

var _settings: SettingsPanel
var _buttons: Dictionary = {}
var _popup: InfoPopup
var _free: Control
var _difficulty: DifficultyPanel
var _time := 0.0
var _crest: Art


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	AudioManager.play_music(true)
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
	root.add_child(UIKit.title_bar("MAIN MENU"))
	var outer := UIKit.panel(Color(1, 1, 1, 0.0), Color.TRANSPARENT)
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(outer)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	outer.add_child(columns)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	columns.add_child(left)
	# --- modes
	var modes := Frame.make("MODES", 10)
	modes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(modes)
	# Careers are the saves: this opens the list to continue one or start another.
	var career := UIKit.button("CAREER", 28, true)
	career.custom_minimum_size = Vector2(0, 96)
	career.pressed.connect(func() -> void: SceneManager.goto("saves"))
	modes.body.add_child(career)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	modes.body.add_child(grid)
	for info: Array in [
		["> FREE DRIVE", func() -> void: _free.visible = true],
		["# GARAGE", func() -> void: SceneManager.goto("garage")],
		["? TUTORIAL", func() -> void:
			# Replays every screen's guided tips, starting here.
			CoachMarks.reset_all()
			_start_tutorial()],
		["= SETTINGS", func() -> void: _settings.visible = true],
		["* DIFFICULTY: %s" % Difficulty.mode_name(), func() -> void: _difficulty.open()],
	]:
		var b := UIKit.button(info[0], 20)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 78)
		b.pressed.connect(info[1])
		grid.add_child(b)
		if str(info[0]).begins_with("*"):
			b.name = "DifficultyButton"
		_buttons[str(info[0]).substr(2).get_slice(":", 0)] = b
	_buttons["CAREER"] = career
	# --- crest
	var right := Frame.make("")
	right.custom_minimum_size = Vector2(470, 0)
	columns.add_child(right)
	_crest = Art.make(Vector2(0, 0), _paint_crest)
	_crest.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.body.add_child(_crest)
	_settings = SettingsPanel.new()
	add_child(_settings)
	_popup = InfoPopup.new()
	add_child(_popup)
	_build_free_drive()
	_difficulty = DifficultyPanel.new()
	add_child(_difficulty)
	_difficulty.closed.connect(func() -> void:
		(find_child("DifficultyButton", true, false) as Button).text = "* DIFFICULTY: %s" % Difficulty.mode_name()
		(find_child("FreeDifficulty", true, false) as Button).text = "DIFFICULTY: %s  /  WEATHER: %s" % [Difficulty.mode_name(), DifficultyPanel.WEATHER_CHOICES[int(GameManager.setting("free_weather"))]])
	_start_tutorial()


func _start_tutorial() -> void:
	CoachMarks.run_once(self, "menu", func() -> Array: return [
		[null, "Welcome to RETRO F1! Here's a quick tour. Tap anywhere to move on."],
		[_buttons["CAREER"], "CAREER is the main game: run an F1 team for season after season. Every career is its own save."],
		[_buttons["FREE DRIVE"], "FREE DRIVE: jump straight in. Test drive, time trial or a 3-lap race on any circuit."],
		[_buttons["GARAGE"], "The GARAGE is where you build and tune your car. Every change shows up in its ratings."],
		[_buttons["DIFFICULTY"], "Pick a DIFFICULTY from ROOKIE (lots of help) to LEGEND (none)."],
		[_buttons["SETTINGS"], "Sound, steering feel and driving assists live in SETTINGS."],
	])


func _draw() -> void:
	UIKit.draw_backdrop(self, Rect2(Vector2.ZERO, size))


func _process(delta: float) -> void:
	_time += delta
	_crest.queue_redraw()


func _paint_crest(a: Control) -> void:
	var c := a.size * 0.5
	var px := 6.0
	# Crossed chequered flags behind the title.
	PixelArt.draw_flag(a, c + Vector2(-190, -150), 9.0, Color.WHITE, UIKit.INK, Color("c9ccd1"), true)
	PixelArt.draw_flag(a, c + Vector2(100, -150), 9.0, Color.WHITE, UIKit.INK, Color("c9ccd1"))
	var plate := Rect2(c + Vector2(-200, -64), Vector2(400, 128))
	a.draw_rect(plate.grow(6.0), UIKit.INK)
	a.draw_rect(plate, UIKit.WARM)
	a.draw_rect(Rect2(plate.position, Vector2(plate.size.x, 10)), Color("ff8a80"))
	a.draw_rect(Rect2(plate.position + Vector2(0, plate.size.y - 12.0), Vector2(plate.size.x, 12)), UIKit.WARM.darkened(0.35))
	PixelFont.draw_centered(a, Rect2(plate.position + Vector2(0, 10), Vector2(plate.size.x, 54)), "RETRO", px, Color.WHITE, UIKit.INK)
	PixelFont.draw_centered(a, Rect2(plate.position + Vector2(0, 64), Vector2(plate.size.x, 54)), "F1", px, Color.WHITE, UIKit.INK)
	# A pixel car doing laps under the crest.
	var track := Rect2(c + Vector2(-190, 96), Vector2(380, 44))
	a.draw_rect(track, Color("1c1e22"))
	PixelArt.draw_checker(a, Rect2(track.position + Vector2(300, 0), Vector2(12, 44)), 6.0, Color.WHITE, UIKit.INK)
	for i in 8:
		a.draw_rect(Rect2(track.position + Vector2(fposmod(i * 50.0 - _time * 160.0, 380.0), 20), Vector2(22, 4)), Color(1, 1, 1, 0.25))
	var team := Career.my_team() if Career.active() else {"color": "#c8201e", "color2": "#f4f6f2"}
	PixelArt.draw_car(a, track.position + Vector2(120 + sin(_time * 1.3) * 60.0, 4), 3.0, Color(str(team["color"])), Color(str(team["color2"])))
	PixelFont.draw_centered(a, Rect2(c + Vector2(-200, 150), Vector2(400, 20)), "BUILD - MANAGE - RACE", 2.0, UIKit.LINE)


func _build_free_drive() -> void:
	_free = Control.new()
	_free.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_free.visible = false
	add_child(_free)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_free.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_free.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(440, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	box.add_child(UIKit.title_bar("FREE DRIVE", 52.0))
	var track := UIKit.button("", 16)
	track.custom_minimum_size = Vector2(0, 54)
	var show_track := func() -> void: track.text = "<  TRACK: %s  -  %s  >" % [GameManager.TRACK_NAMES[GameManager.track_id], TrackTheme.label(GameManager.track_id)]
	show_track.call()
	track.pressed.connect(func() -> void:
		GameManager.track_id = GameManager.TRACKS[(GameManager.TRACKS.find(GameManager.track_id) + 1) % GameManager.TRACKS.size()]
		show_track.call())
	box.add_child(track)
	for info: Array in [["> TEST DRIVE", GameManager.MODE_TEST], ["> TIME TRIAL", GameManager.MODE_TIME_TRIAL], ["> 3 LAP RACE", GameManager.MODE_RACE]]:
		var b := UIKit.button(info[0], 20)
		b.custom_minimum_size = Vector2(0, 64)
		var mode: String = info[1]
		b.pressed.connect(func() -> void: _start(mode))
		box.add_child(b)
	var diff := UIKit.button("DIFFICULTY: %s  /  WEATHER: %s" % [Difficulty.mode_name(), DifficultyPanel.WEATHER_CHOICES[int(GameManager.setting("free_weather"))]], 14)
	diff.name = "FreeDifficulty"
	diff.custom_minimum_size = Vector2(0, 50)
	diff.pressed.connect(func() -> void: _difficulty.open())
	box.add_child(diff)
	var back := UIKit.button("< BACK", 20)
	back.custom_minimum_size = Vector2(0, 64)
	back.pressed.connect(func() -> void: _free.visible = false)
	box.add_child(back)


func _start(mode: String) -> void:
	if not BuildValidator.is_ready(GameManager.setup):
		_popup.open("CAR NOT READY", BuildValidator.report(GameManager.setup).replace("CAR NOT READY\n\n", ""), "OPEN GARAGE", func() -> void: SceneManager.goto("garage"))
		return
	GameManager.start_free_session(mode)
