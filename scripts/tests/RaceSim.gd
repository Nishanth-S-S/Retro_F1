extends Node
## Headless full-race simulation: 7 AI + an AI-driven "player" car over 5 laps.
##   godot --headless res://scenes/tests/RaceSim.tscn -- [player_pace]

const TIME_SCALE := 10.0

var manager: RaceManager
var _done := false
var _resets := 0
var _report_timer := 0.0


func _ready() -> void:
	SaveManager.disabled = true
	GameManager.load_profile()
	Engine.time_scale = TIME_SCALE
	Engine.physics_ticks_per_second = int(60 * TIME_SCALE)
	Engine.max_physics_steps_per_frame = 64
	AudioServer.set_bus_mute(0, true)
	GameManager.session_mode = GameManager.MODE_RACE
	for a in OS.get_cmdline_user_args():
		if a.begins_with("track:"):
			GameManager.track_id = a.substr(6)
	manager = (load("res://scenes/Race.tscn") as PackedScene).instantiate() as RaceManager
	add_child(manager)
	var args := OS.get_cmdline_user_args()
	var pace := float(args[0]) if args.size() > 0 and args[0].is_valid_float() else 0.95
	manager.player.is_player = false      # stop keyboard polling from fighting the AI
	var driver := AIDriver.new()
	manager.player.add_child(driver)
	driver.setup(manager.player, manager.line, {"pace": pace, "braking_accuracy": 0.95, "consistency": 0.97, "aggression": 0.6, "tire_management": 0.7, "error_rate": 0.0}, 5)
	driver.others = manager.cars
	driver.needs_recovery.connect(func(car: VehicleController) -> void:
		_resets += 1
		manager._recover_car(car))
	for d in manager.drivers:
		d.needs_recovery.connect(func(_car: VehicleController) -> void: _resets += 1)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_report_timer += delta
	if _report_timer > 60.0:
		_report_timer = 0.0
		var text := "t=%4.0f  " % manager.race_time
		for car: VehicleController in manager.positions.order:
			text += "%s(L%d) " % [car.driver_name.substr(0, 6), manager.timers[manager.cars.find(car)].laps_completed]
		print(text)
	if manager.state == RaceManager.State.FINISHED or manager.race_time > 900.0:
		_done = true
		manager.positions.update(manager.cars, manager.timers, manager.track.length)
		print("\n=== CLASSIFICATION (race time %.1f s, recoveries %d) ===" % [manager.race_time, _resets])
		for row: Dictionary in manager._classification():
			var idx := 0
			for i in manager.cars.size():
				if manager.cars[i].driver_name == row["name"]:
					idx = i
			var t := manager.timers[idx]
			var laps := ""
			for lt in t.lap_times:
				laps += "%.1f " % lt
			var p := manager.cars[idx].physics
			print("%-14s laps %d  best %s  gap %6.1f  [%s] tires F%.0f%% R%.0f%% %.0fC/%.0fC" % [row["name"], row["laps"], LapTimer.format_time(row["best_lap"]), row["gap"], laps, p.front_tire.wear * 100, p.rear_tire.wear * 100, p.front_tire.temperature, p.rear_tire.temperature])
		get_tree().quit()
