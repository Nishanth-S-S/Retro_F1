extends Node
## Driver performance checks:  godot --headless res://scenes/tests/DriverPerfTest.tscn
##  1. a higher rating never makes its own capability worse
##  2. drivers do not change engine output or top speed, but do change braking
##  3. lap times of 70, 85 and 95-rated drivers in the same car on a representative track
##     (the AI drives with the same driver model the player gets; pace and errors fixed)

const TRACK := "silverstone"
const LAPS := 3

var _failures := 0


func _check(ok: bool, text: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", text])
	if not ok:
		_failures += 1


func _ready() -> void:
	SaveManager.disabled = true
	GameManager.load_profile()
	GameManager.profile["career"] = {}
	AudioServer.set_bus_mute(0, true)
	_monotonic()
	_straight_line()
	await _laps()
	print("DRIVER PERF TEST PASSED" if _failures == 0 else "DRIVER PERF TEST FAILED (%d)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _monotonic() -> void:
	var outputs := {"pace": ["grip_extraction", "traction_extraction"], "consistency": ["braking_extraction", "brake_window", "traction_forgiveness"],
		"starts": ["launch_efficiency", "launch_tolerance"], "wet": ["wet_extraction"], "tyres": ["-wear_multiplier"], "fitness": ["-fatigue_rate"]}
	for key: String in outputs:
		for field: String in outputs[key]:
			var sign := -1.0 if field.begins_with("-") else 1.0
			var name := field.trim_prefix("-")
			var last := -INF
			var ok := true
			for rating in range(1, 100):
				var attrs := DriverPerformance.preset(80)
				attrs[key] = rating
				var perf := DriverPerformance.new()
				perf.configure(attrs)
				var value := float(perf.get(name)) * sign
				ok = ok and value >= last - 1e-6 and is_finite(value)
				last = value
			_check(ok, "%s never worsens %s as it rises" % [key, name])
	# Traffic and fatigue only ever take away, and never push past the car.
	var weak := DriverPerformance.new()
	weak.configure(DriverPerformance.preset(70))
	var alone := weak.spin_sensitivity
	weak.update(0.016, -1.0, 0.5, 40.0, 1.0, 1.0, 0.0)
	_check(weak.spin_sensitivity > alone, "close racing costs a weak racer forgiveness (x%.2f -> x%.2f)" % [alone, weak.spin_sensitivity])
	var elite := DriverPerformance.new()
	var top := DriverPerformance.preset(99)
	top["morale"] = 100
	elite.configure(top)
	elite.update(0.016, 1.0, 1.0, 40.0, 0.0, 0.0, 0.0)
	_check(elite.lateral <= 1.0 and elite.braking <= 1.0 and elite.traction <= 1.0, "elite driver at full morale stays within the car (grip %.3f)" % elite.lateral)
	var tired := DriverPerformance.new()
	tired.configure(DriverPerformance.preset(70))
	var fresh_grip := tired.lateral
	for i in 600:
		tired.update(0.1, i / 600.0, 1.0, 50.0, 0.0, 0.0, 0.0)
	_check(tired.fatigue > 0.5 and tired.lateral < fresh_grip, "70 fitness at the flag: fatigue %.2f, grip %.3f -> %.3f" % [tired.fatigue, fresh_grip, tired.lateral])


## Flat out from rest on a straight, then a stop from 250 km/h: same top speed, different braking.
func _straight_line() -> void:
	var config: VehiclePhysicsConfig = load("res://data/physics/default_physics.tres")
	var results := {}
	for rating: int in [0, 70, 95]:
		var phys := VehiclePhysics.new()
		phys.configure(GameManager.setup, config)
		if rating > 0:
			var perf := DriverPerformance.new()
			perf.configure(DriverPerformance.preset(rating))
			phys.driver = perf
		var v := 0.0
		var t := 0.0
		var t100 := 0.0
		var dt := 1.0 / 240.0
		var peak_power := 0.0
		while t < 90.0:
			phys.step(dt, v, 0.0, 0.0, 0.0, 1.0, 0.0, 0, 0)
			v = maxf(0.0, v + phys.accel_local.x * dt)
			peak_power = maxf(peak_power, phys.engine.torque() * phys.engine.rpm)
			t += dt
			if t100 == 0.0 and v >= 27.78:
				t100 = t
		var top := v
		v = 250.0 / 3.6
		var dist := 0.0
		while v > 1.0:
			phys.step(dt, v, 0.0, 0.0, 0.0, 0.0, 1.0, 0, 0)
			v = maxf(0.0, v + phys.accel_local.x * dt)
			dist += v * dt
		results[rating] = [top * 3.6, t100, dist, peak_power]
		print("     %s  top %.1f km/h  0-100 %.2f s  250-0 %.1f m" % ["no driver" if rating == 0 else "driver %d" % rating, top * 3.6, t100, dist])
	_check(absf(results[70][0] - results[95][0]) < 0.5 and absf(results[95][0] - results[0][0]) < 0.5, "top speed is the car's, not the driver's")
	_check(is_equal_approx(results[70][3], results[95][3]), "engine output is the car's, not the driver's")
	_check(results[70][2] > results[95][2] and results[95][2] >= results[0][2] - 0.1, "a weaker driver needs longer to stop (%.1f m vs %.1f m)" % [results[70][2], results[95][2]])


func _laps() -> void:
	# A bare track, as PhysicsTests uses: time_scale stretches the physics delta, so the tick
	# rate rises by the same factor to keep a true 1/60 s step.
	Engine.time_scale = 12.0
	Engine.physics_ticks_per_second = 720
	Engine.max_physics_steps_per_frame = 64
	GameManager.track_id = TRACK
	GameManager.session_weather = 0
	GameManager.session_mode = GameManager.MODE_TIME_TRIAL
	_track = Track.new()
	add_child(_track)
	_line = RacingLine.build(_track.data)
	var best := {}
	for rating: int in DriverPerformance.PRESETS:
		_start_run(rating)
		while _car != null:
			await get_tree().physics_frame
		var laps: Array = _timer.lap_times.slice(1)
		var lap := INF
		for t: float in laps:
			lap = minf(lap, t)
		best[rating] = lap
		print("     driver %d: laps %s  best %.3f s" % [rating, ", ".join(laps.map(func(t: float) -> String: return "%.3f" % t)), lap])
	Engine.time_scale = 1.0
	var gap: float = (best[70] - best[95]) / best[70] * 100.0
	print("     95 vs 70: %.2f%% faster  (target 4-6%%)   85 vs 70: %.2f%%" % [gap, (best[70] - best[85]) / best[70] * 100.0])
	_check(best[95] < best[85] and best[85] < best[70], "lap time improves with the driver")


var _track: Track
var _line: RacingLine
var _car: VehicleController
var _timer: LapTimer
var _time := 0.0
var _prev := 0.0


func _start_run(rating: int) -> void:
	_car = VehicleController.new()
	_car.setup = CarSetup.from_dict(GameManager.default_profile()["car_setup"])
	_car.track = _track.data
	add_child(_car)
	var slot := _track.data.grid_slot(0)
	_car.place(slot["position"], slot["rotation"])
	_car.controls_enabled = true
	var driver := AIDriver.new()
	_car.add_child(driver)
	driver.setup(_car, _line, {"pace": 1.0, "braking_accuracy": 1.0, "consistency": 1.0, "aggression": 0.5, "error_rate": 0.0, "attrs": DriverPerformance.preset(rating)}, 1)
	driver.others = [_car]
	_timer = LapTimer.new(_track.data)
	_time = 0.0
	_prev = _car.progress


func _physics_process(delta: float) -> void:
	if _car == null or _timer == null:
		return
	_time += delta
	_timer.update(_prev, _car.progress, not _car.off_track, _time, delta)
	_prev = _car.progress
	if _timer.laps_completed >= LAPS or _time > 200.0 * LAPS:
		_car.queue_free()
		_car = null
