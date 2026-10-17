extends Node
## Corner skill checks:  godot --headless res://scenes/tests/CornerSkillTest.tscn
##  1. steering, braking and throttle share one grip budget
##  2. PRESERVE spins the tyres less, PUSH is quicker but spends energy, braking recharges it
##  3. the Apex Lab track: a hairpin and a sweeper on a wide road
##  4. the style read follows the driving: the same car braking late vs early into the hairpin
##     (the AI steers; this test owns the brake pedal on the approach)

var _failures := 0
## Scripted braking into the hairpin: metres before the apex where full braking starts.
var _brake_point := 0.0
var _race: RaceManager
var _hairpin := 0.0


func _check(ok: bool, text: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", text])
	if not ok:
		_failures += 1


func _ready() -> void:
	SaveManager.disabled = true
	GameManager.load_profile()
	GameManager.profile["career"] = {}
	AudioServer.set_bus_mute(0, true)
	_grip_budget()
	_pace()
	var track := TrackData.load_track("res://data/tracks/apex_lab.json")
	_check(track.corners.size() == 2 and track.half_width >= 10.0, "Apex Lab: %d corners (%s), %.0f m wide, %.0f m lap" % [track.corners.size(), ", ".join(track.corners.map(func(c: Dictionary) -> String: return "r %.0f m" % float(c["radius"]))), track.half_width * 2.0, track.length])
	process_physics_priority = 100        # after the AI has written its pedals
	var late := await _drive(105.0)
	var early := await _drive(150.0)
	_check(float(late["scores"]["LATE BRAKER"]) > float(early["scores"]["LATE BRAKER"]), "braking later reads as a later braker (%d vs %d)" % [int(late["scores"]["LATE BRAKER"]), int(early["scores"]["LATE BRAKER"])])
	print("     hairpin + straight: late braker %.2f s, early braker %.2f s" % [late["sector"], early["sector"]])
	print("CORNER SKILL TEST PASSED" if _failures == 0 else "CORNER SKILL TEST FAILED (%d)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _physics() -> VehiclePhysics:
	var phys := VehiclePhysics.new()
	phys.configure(GameManager.setup, load("res://data/physics/default_physics.tres"))
	return phys


## The same steering at 30 m/s with and without full brake: braking eats the cornering force.
func _grip_budget() -> void:
	var lateral := []
	for brake: float in [0.0, 1.0]:
		var phys := _physics()
		for i in 120:
			phys.step(1.0 / 240.0, 30.0, 0.0, 0.0, 0.6, 0.0, brake, 0, 0)
		lateral.append(absf(phys.accel_local.y))
	_check(lateral[1] < lateral[0] * 0.9, "full brake while turning costs cornering grip (%.1f -> %.1f m/s2)" % [lateral[0], lateral[1]])


## Full throttle out of a slow corner (25 km/h, no traction control) for 4 s in each pace mode.
func _pace() -> void:
	var out := {}
	for mode in 3:
		var phys := _physics()
		phys.pace_mode = mode
		phys.tc_level = 0
		var v := 7.0
		var spin := 0.0
		var dist := 0.0
		for i in 960:
			phys.step(1.0 / 240.0, v, 0.0, 0.0, 0.0, 1.0, 0.0, 0, 0)
			v += phys.accel_local.x / 240.0
			dist += v / 240.0
			if phys.rear_tire.spinning:
				spin += 1.0 / 240.0
		out[mode] = [dist, spin, phys.energy]
		print("     %-9s  %.1f m in 4 s  wheelspin %.2f s  energy %.0f%%" % [VehiclePhysics.PACE_NAMES[mode], dist, spin, phys.energy])
	_check(out[2][0] > out[1][0] and out[1][0] > out[0][0], "PUSH is quickest, PRESERVE slowest off a corner")
	_check(out[0][1] <= out[1][1] and out[1][1] <= out[2][1], "PRESERVE spins the rears least, PUSH most")
	_check(out[2][2] < 90.0 and out[1][2] >= 99.9, "PUSH spends energy, BALANCED does not")
	var phys := _physics()
	phys.energy = 40.0
	for i in 480:
		phys.step(1.0 / 240.0, 60.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0, 0)
	_check(phys.energy > 50.0, "braking recharges energy (40%% -> %.0f%%)" % phys.energy)


## Two laps of Apex Lab with the AI at the wheel and the style tracker reading it.
func _physics_process(_delta: float) -> void:
	if _race == null or _brake_point <= 0.0:
		return
	var car := _race.player
	var to_apex := _race.track.progress_delta(car.progress, _hairpin)
	if to_apex > 0.0 and to_apex < 300.0 and car.speed > 17.0:
		if to_apex > _brake_point:
			car.input.throttle = 1.0
			car.input.brake = 0.0
		else:
			car.input.throttle = 0.0
			car.input.brake = 1.0


func _drive(brake_point: float) -> Dictionary:
	Engine.time_scale = 8.0
	Engine.physics_ticks_per_second = 480
	Engine.max_physics_steps_per_frame = 64
	GameManager.track_id = "apex_lab"
	GameManager.session_weather = 0
	GameManager.session_mode = GameManager.MODE_TIME_TRIAL
	var race := (load("res://scenes/Race.tscn") as PackedScene).instantiate() as RaceManager
	add_child(race)
	race.player.is_player = false
	var driver := AIDriver.new()
	race.player.add_child(driver)
	driver.setup(race.player, race.line, {"pace": 1.0, "error_rate": 0.0, "consistency": 1.0, "braking_accuracy": 1.0}, 3)
	_race = race
	_brake_point = brake_point
	_hairpin = float(race.track.corners[0]["apex"])
	var style := DrivingStyle.new(race.track)
	var waited := 0.0
	# Time from 300 m before the hairpin to the end of the straight after it.
	var sector_start := -1.0
	var sector := 0.0
	var straight_end := float(race.track.corners[1]["start"])
	while race.player_timer.laps_completed < 2 and waited < 400.0:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		style.update(race.player, dt)
		waited += dt
		var to_apex := race.track.progress_delta(race.player.progress, _hairpin)
		if race.player_timer.laps_completed == 1:
			if sector_start < 0.0 and to_apex > 0.0 and to_apex < 300.0:
				sector_start = waited
			elif sector_start >= 0.0 and sector == 0.0 and race.track.progress_delta(race.player.progress, straight_end) < 0.0 and to_apex < 0.0:
				sector = waited - sector_start
	_brake_point = 0.0
	_race = null
	var summary := style.summary()
	var lines := PackedStringArray()
	for r: Dictionary in style.reports:
		lines.append("%s in %d apex %d out %d: %s  (braked over %.0f m, needed %.0f m, lateness %.2f)" % [r["name"], r["entry"], r["apex"], r["exit"], r["verdict"], r["braking_m"], r["needed_m"], r["lateness"]])
	summary["sector"] = sector
	print("     brakes at %.0f m, laps %s\n       %s\n       style %s %s" % [brake_point, race.player_timer.lap_times.map(func(t: float) -> String: return "%.2f" % t), "\n       ".join(lines), summary["top"], summary["scores"]])
	_check(style.reports.size() >= 3, "corner reports recorded (%d)" % style.reports.size())
	race.queue_free()
	await get_tree().process_frame
	Engine.time_scale = 1.0
	return summary
