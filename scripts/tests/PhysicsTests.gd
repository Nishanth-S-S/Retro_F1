extends Node
## Headless physics regression / tuning scenarios (spec section 92).
##   godot --headless res://scenes/tests/PhysicsTests.tscn -- <scenario> [laps]
## Each scenario drives a car with the AI driver (same inputs a player has) and prints
## lap times, so setup changes can be compared objectively.

const TIME_SCALE := 12.0

var track_node: Track
var line: RacingLine
var _runs: Array = []
var _results: Array = []
var _car: VehicleController
var _driver: AIDriver
var _timer: LapTimer
var _time := 0.0
var _prev_progress := 0.0
var _max_speed := 0.0
var _laps_wanted := 2
var _label := ""
var _off_time := 0.0
var _binary := false
var _trace := false
var _frame := 0
var _ring: Array[String] = []
var _was_off := false
var _resets := 0


func _ready() -> void:
	SaveManager.disabled = true
	# time_scale stretches the physics delta, so raise the tick rate by the same factor
	# to keep a true 1/60 s step while running faster than real time.
	Engine.time_scale = TIME_SCALE
	Engine.physics_ticks_per_second = int(60 * TIME_SCALE)
	Engine.max_physics_steps_per_frame = 64
	AudioServer.set_bus_mute(0, true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("track:"):
			GameManager.track_id = a.substr(6)
	track_node = Track.new()
	add_child(track_node)
	line = RacingLine.build(track_node.data)
	var args := OS.get_cmdline_user_args()
	var scenario: String = args[0] if args.size() > 0 else "baseline"
	_laps_wanted = int(args[1]) if args.size() > 1 else 2
	_trace = args.has("trace")
	_build_runs(scenario)
	_next_run()


func _base() -> Dictionary:
	return GameManager.default_profile()["car_setup"].duplicate(true)


func _variant(label: String, changes: Dictionary, driver: Dictionary = {}) -> void:
	var d := _base()
	for key: String in changes:
		if d["parts"].has(key) or CarSetup.SLOT_CATEGORY.has(key):
			d["parts"][key] = changes[key]
		else:
			d[key] = changes[key]
	_runs.append({"label": label, "setup": d, "driver": driver})


func _build_runs(scenario: String) -> void:
	match scenario:
		"baseline":
			_variant("starter car", {})
		"engines":
			_variant("compact 4", {})
			_variant("balanced 6", {"engine": "engine_balanced_6"})
			_variant("turbo 6", {"engine": "engine_turbo_6"})
			_variant("high output 8", {"engine": "engine_high_output_8"})
		"wings":
			_variant("low drag", {"front_wing": "front_wing_low_drag", "rear_wing": "rear_wing_low_drag"})
			_variant("balanced", {})
			_variant("high downforce", {"front_wing": "front_wing_high_df", "rear_wing": "rear_wing_high_df"})
		"balance":
			_variant("ballast 30 front", {"ballast": "ballast_30", "ballast_position": 0.0})
			_variant("no ballast", {})
			_variant("ballast 30 rear", {"ballast": "ballast_30", "ballast_position": 1.0})
			_variant("front-heavy aero", {"front_wing": "front_wing_high_df", "rear_wing": "rear_wing_low_drag"})
			_variant("rear-heavy aero", {"front_wing": "front_wing_low_drag", "rear_wing": "rear_wing_high_df"})
		"tires":
			_variant("hard", {})
			_variant("medium", {"tires": "tires_medium"})
			_variant("soft", {"tires": "tires_soft"})
		"skill":
			_variant("smooth analog driver", {})
			_variant("binary pedals + ABS/TC", {}, {"binary": true})
			_variant("smooth, no assists", {}, {"no_assists": true})
			_variant("binary, no assists", {}, {"binary": true, "no_assists": true})
		"field":
			var drivers: Array = SaveManager.load_json("res://data/progression/ai_drivers.json")
			for d: Dictionary in drivers:
				_variant(d["name"], d["setup"], d)
		_:
			_variant("starter car", {})


func _next_run() -> void:
	if _car:
		_car.queue_free()
		_driver = null
	if _runs.is_empty():
		_report()
		get_tree().quit()
		return
	var run: Dictionary = _runs.pop_front()
	_label = run["label"]
	var setup := CarSetup.from_dict(run["setup"])
	_car = VehicleController.new()
	_car.setup = setup
	_car.track = track_node.data
	add_child(_car)
	var slot := track_node.data.grid_slot(0)
	_car.place(slot["position"], slot["rotation"])
	_car.controls_enabled = true
	var profile: Dictionary = {"pace": 1.0, "braking_accuracy": 1.0, "consistency": 1.0, "aggression": 0.5, "tire_management": 0.63, "error_rate": 0.0}
	var overrides: Dictionary = run["driver"]
	for key: String in overrides:
		profile[key] = overrides[key]
	_binary = overrides.get("binary", false)
	_driver = AIDriver.new()
	add_child(_driver)
	_driver.setup(_car, line, profile, 1)
	_driver.others = [_car]
	_driver.binary_pedals = _binary
	_driver.needs_recovery.connect(_on_recovery)
	_resets = 0
	if overrides.has("no_assists"):
		_car.physics.tc_level = 0
		_car.physics.abs_level = 0
	_timer = LapTimer.new(track_node.data)
	_time = 0.0
	_max_speed = 0.0
	_off_time = 0.0
	_prev_progress = _car.progress
	var s := _car.physics.stats
	print("\n== %s ==  mass %.0f kg  F/R %.1f/%.1f  power %.0f kW  top %.0f km/h (%s)  0-100 %.2fs  mech %.2fg  DF@200 %.0f N  aeroF %.0f%%  brake %.2fg  balance low %+.3f high %+.3f -> %s" % [
		_label, s.mass, s.front_weight * 100, (1 - s.front_weight) * 100, s.power_kw, s.top_speed * 3.6, s.top_speed_limited_by, s.accel_0_100, s.mech_grip_g, s.downforce_200, s.front_aero * 100, s.braking_g, s.balance_low, s.balance_high, s.balance_label()])


func _physics_process(delta: float) -> void:
	if _car == null or _driver == null:
		return
	_time += delta
	_frame += 1
	if _trace and _frame % 10 == 0:
		var ph := _car.physics
		_ring.append("t%5.1f s=%6.0f v=%5.1f tgt=%5.1f lat=%5.1f st=%+.2f th=%.2f br=%.2f g%d af=%+.3f ar=%+.3f Ff=%5.0f/%5.0f Fr=%5.0f/%5.0f T %3.0f/%3.0f surf %d%d %s" % [_time, _car.progress, _car.speed, _driver.target_speed_at(_car.track_index), _car.lateral, _car.input.steer, _car.input.throttle, _car.input.brake, ph.transmission.gear, ph.front_tire.slip_angle, ph.rear_tire.slip_angle, ph.front_force.length(), ph.front_limit, ph.rear_force.length(), ph.rear_limit, ph.front_tire.temperature, ph.rear_tire.temperature, _car.surface_front, _car.surface_rear, _driver.state])
		if _ring.size() > 28:
			_ring.pop_front()
	if _trace and _car.off_track and not _was_off:
		print("--- incident")
		for line_text: String in _ring:
			print(line_text)
	_was_off = _car.off_track
	_max_speed = maxf(_max_speed, _car.speed)
	if _car.off_track:
		_off_time += delta
	_timer.update(_prev_progress, _car.progress, not _car.off_track, _time, delta)
	_prev_progress = _car.progress
	if _timer.laps_completed >= _laps_wanted or _time > 150.0 * (_laps_wanted + 1):
		var p := _car.physics
		var laps := ""
		for i in _timer.lap_times.size():
			laps += "%s%s " % [LapTimer.format_time(_timer.lap_times[i]), "" if _timer.lap_valid[i] else "*"]
		laps += "| S %.1f %.1f %.1f " % [_timer.best_sectors[0], _timer.best_sectors[1], _timer.best_sectors[2]]
		var line_text := "%-22s laps: %s| vmax %.0f km/h | off %.1fs resets %d | tires F %.0fC %.0f%%  R %.0fC %.0f%% | brakes %.0fC | engine %.0fC" % [
			_label, laps, _max_speed * 3.6, _off_time, _resets, p.front_tire.temperature, p.front_tire.wear * 100, p.rear_tire.temperature, p.rear_tire.wear * 100, p.brakes.temperature, p.engine.temperature]
		print(line_text)
		_results.append(line_text)
		_next_run()


func _on_recovery(car: VehicleController) -> void:
	_resets += 1
	car.place(track_node.data.position_at(car.progress + 10.0), track_node.data.heading_at(car.progress + 10.0))


func _report() -> void:
	print("\n================ SUMMARY ================")
	for r: String in _results:
		print(r)
