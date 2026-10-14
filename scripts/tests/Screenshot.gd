extends Node
## Dev tool: open a scene in a real window, wait, save a PNG, quit.
##   godot res://scenes/tests/Screenshot.tscn -- <scene path> <seconds> <out.png> [mode] [drive]

var _wait := 1.0
var _out := ""
var _scene: Node
var _drive := false


func _ready() -> void:
	SaveManager.disabled = true
	AudioServer.set_bus_mute(0, true)
	var args := OS.get_cmdline_user_args()
	_wait = float(args[1])
	_out = args[2]
	if args.size() > 3:
		GameManager.session_mode = args[3]
	_drive = args.has("drive")
	for a in args:
		if a.begins_with("setup:"):
			var kv := a.substr(6).split("=")
			GameManager.setup.install(kv[0], kv[1])
	if args.has("fake_results"):
		GameManager.last_results = {"mode": "race", "position": 3, "total_cars": 8, "finished": true, "laps": [97.2, 95.1, 95.4, 96.0, 95.8], "lap_valid": [true, true, true, true, true], "best_lap": 95.1, "total_time": 479.5,
			"money": 3000, "reward_lines": ["Race result P3  +$3000"], "report": {"max_speed": 241.0, "avg_corner_entry": 150.0, "front_peak": 96.0, "rear_peak": 101.0, "sliding_time": 3.2}, "corners": [], "corner_note": "",
			"classification": [{"name": "M. Varga", "is_player": false, "finished": true, "time": 470.0, "gap": 0.0, "laps": 5}, {"name": "S. Okafor", "is_player": false, "finished": true, "time": 474.0, "gap": 4.0, "laps": 5}, {"name": "You", "is_player": true, "finished": true, "time": 479.5, "gap": 9.5, "laps": 5}]}
	_scene = (load(args[0]) as PackedScene).instantiate()
	add_child(_scene)
	if _drive and _scene is RaceManager:
		var m := _scene as RaceManager
		m.player.is_player = false
		var driver := AIDriver.new()
		m.player.add_child(driver)
		driver.setup(m.player, m.line, {"pace": 0.97, "error_rate": 0.0}, 3)
		driver.others = m.cars


func _process(delta: float) -> void:
	_wait -= delta
	if _wait <= 0.0 and _out != "":
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out)
		print("perf: fps %d  process %.2f ms  physics %.2f ms  draw calls %d  objects %d" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
		_out = ""
		get_tree().quit()
