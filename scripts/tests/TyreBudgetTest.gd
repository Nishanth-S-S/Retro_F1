extends Node
## The tyre budget:  godot --headless res://scenes/tests/TyreBudgetTest.tscn
## Laps a car flat out and gently (same car, same driver) and checks that pushing spends the
## budget faster. Prints the metres a set lasts flat out at stint_scale 1, which is
## TireModel.REFERENCE_LIFE_M, and what a race stint would spend.

const TRACK := "silverstone"

var _failures := 0
var _track: Track
var _line: RacingLine
var _car: VehicleController
var _timer: LapTimer
var _time := 0.0
var _prev := 0.0
var _start_wear := 1.0


func _check(ok: bool, text: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", text])
	if not ok:
		_failures += 1


func _ready() -> void:
	SaveManager.disabled = true
	GameManager.load_profile()
	GameManager.profile["career"] = {}
	AudioServer.set_bus_mute(0, true)
	Engine.time_scale = 12.0
	Engine.physics_ticks_per_second = 720
	Engine.max_physics_steps_per_frame = 64
	GameManager.track_id = TRACK
	GameManager.session_weather = 0
	GameManager.session_mode = GameManager.MODE_TIME_TRIAL
	_track = Track.new()
	add_child(_track)
	_line = RacingLine.build(_track.data)
	var spent := {}
	for pace: float in [1.0, 0.86]:     # 0.86 = gentle: slower corners and the throttle fed in
		_start_run(pace)
		while _car != null:
			await get_tree().physics_frame
	spent = _results
	var push: float = spent[1.0]
	var gentle: float = spent[0.86]
	var life := _track.data.length / maxf(push, 0.0001)
	print("     flat out: $%.1f a lap   gently: $%.1f a lap   (lap %.0f m)" % [push * 100.0, gentle * 100.0, _track.data.length])
	print("     a set lasts %.0f m flat out at stint_scale 1 (TireModel.REFERENCE_LIFE_M = %.0f)" % [life, TireModel.REFERENCE_LIFE_M])
	_check(push > gentle * 1.15, "pushing spends the tyres faster than driving gently")
	# What a 3-lap Grand Prix stint (1.5 laps) would cost with the race scale applied.
	var scale := TireModel.REFERENCE_LIFE_M * 0.9 / (1.5 * _track.data.length)
	print("     3-lap GP, one stop: flat out spends $%.0f of $100 by the stop, gently $%.0f" % [push * scale * 150.0, gentle * scale * 150.0])
	print("TYRE BUDGET TEST PASSED" if _failures == 0 else "TYRE BUDGET TEST FAILED")
	get_tree().quit(0 if _failures == 0 else 1)


var _results := {}
var _pace := 1.0


func _start_run(pace: float) -> void:
	_pace = pace
	_car = VehicleController.new()
	_car.setup = CarSetup.from_dict(GameManager.default_profile()["car_setup"])
	_car.track = _track.data
	add_child(_car)
	var slot := _track.data.grid_slot(0)
	_car.place(slot["position"], slot["rotation"])
	_car.controls_enabled = true
	var driver := AIDriver.new()
	_car.add_child(driver)
	driver.setup(_car, _line, {"pace": pace, "braking_accuracy": pace, "consistency": 1.0, "error_rate": 0.0}, 1)
	driver.others = [_car]
	driver.throttle_cap = 1.0 if pace >= 1.0 else 0.55
	_timer = LapTimer.new(_track.data)
	_time = 0.0
	_prev = _car.progress


func _physics_process(delta: float) -> void:
	if _car == null or _timer == null:
		return
	_time += delta
	_timer.update(_prev, _car.progress, not _car.off_track, _time, delta)
	_prev = _car.progress
	if _timer.laps_completed == 1 and _start_wear >= 1.0:
		_start_wear = minf(_car.physics.front_tire.wear, _car.physics.rear_tire.wear)
	if _timer.laps_completed >= 2 or _time > 400.0:
		var now := minf(_car.physics.front_tire.wear, _car.physics.rear_tire.wear)
		_results[_pace] = _start_wear - now
		_start_wear = 1.0
		_car.queue_free()
		_car = null
