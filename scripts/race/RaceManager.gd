class_name RaceManager
extends Node2D
## Runs one on-track session (test drive, time trial or 5-lap race): builds the grid,
## owns timing / positions / telemetry for every car and hands results to the next scene.

enum State { COUNTDOWN, RACING, FINISHED }

const PPM := VehiclePhysicsConfig.PPM
const RESET_PENALTY := 3.0
const PLAYER_GRID_SLOT := 3
const FINISH_DELAY := 2.2
const PLAYER_COLOR := Color("e8eef6")

var mode := GameManager.MODE_TEST
var state := State.COUNTDOWN
var track_node: Track
var track: TrackData
var line: RacingLine
var cars: Array[VehicleController] = []
var timers: Array[LapTimer] = []
var drivers: Array[AIDriver] = []
var player: VehicleController
var player_timer: LapTimer
var positions := RacePositionManager.new()
var telemetry := TelemetryRecorder.new()
var race_time := 0.0

# --- personal-best reference (delta + ghost)
var live_delta := 0.0
var has_delta := false
var reference_best := 0.0
var _reference_trace: Array = []
var _lap_trace: LapTrace
var _ghost_recorder := GhostRecorder.new()
var _ghost_data: Array = []
var _ghost: CarVisual
var _ghost_sample: Dictionary = {}

var _hud: HUDController
var _controls: MobileControls
var _camera: RaceCamera
var _line_assist: RacingLineAssist
var _skids: SkidMarks
var _prev_progress := PackedFloat32Array()
var _countdown := 0.0
var _finish_timer := 0.0
var _position_timer := 0.0
var _finish_count := 0
var _message_cooldowns: Dictionary = {}
var _condition_timers: Dictionary = {}
var _session := {"new_pb": false, "finished": false, "previous_pb_corners": [], "pb_lap_number": -1, "session_best_lap_number": -1}
var _session_best := 0.0
var _leaving := false
var _mission: Dictionary = {}
var _objective_done := false
## Seconds left in the current pit stop (0 = not in the pits).
var pit_timer := 0.0
var _pit_total := 0.0
## 0 dry, 1 light rain, 2 heavy rain.
var weather := 0
var _assist_profile := PackedFloat32Array()


func _ready() -> void:
	mode = GameManager.session_mode
	_mission = GameManager.mission()
	if not BuildValidator.is_ready(GameManager.setup):
		# Never start a session with an incomplete car.
		SceneManager.call_deferred("goto", "garage")
		set_physics_process(false)
		set_process(false)
		return
	AudioManager.play_music(false)
	track_node = get_node_or_null("Track") as Track
	if track_node == null:
		track_node = Track.new()
		track_node.name = "Track"
		add_child(track_node)
	track = track_node.data
	weather = clampi(GameManager.session_weather, 0, 2)
	track_node.set_wet(weather)
	var rain := WeatherFX.new()
	rain.level = weather
	add_child(rain)
	line = RacingLine.build(track)
	var line_path := Path2D.new()
	line_path.name = "RacingLinePath"
	line_path.curve = line.curve
	line_path.visible = false
	add_child(line_path)
	_skids = SkidMarks.new()
	add_child(_skids)
	_lap_trace = LapTrace.new(track.length)
	reference_best = float(GameManager.record()["best_lap"])
	_reference_trace = GameManager.record()["best_lap_trace"]
	_ghost_data = GameManager.record()["ghost_data"]
	_spawn_cars()
	_build_ghost()
	_line_assist = RacingLineAssist.new()
	add_child(_line_assist)
	_line_assist.setup(line, player)
	_camera = RaceCamera.new()
	add_child(_camera)
	_camera.target = player
	_camera.make_current()
	_hud = _instantiate("res://scenes/components/RaceHUD.tscn", HUDController) as HUDController
	add_child(_hud)
	_hud.setup(self)
	_controls = _instantiate("res://scenes/components/TouchControls.tscn", MobileControls) as MobileControls
	var controls_layer := CanvasLayer.new()
	controls_layer.layer = 9
	add_child(controls_layer)
	controls_layer.add_child(_controls)
	_controls.input = player.input
	var debug := DebugOverlay.new()
	debug.manager = self
	add_child(debug)
	EventBus.settings_changed.connect(_apply_settings)
	_apply_settings()
	if weather > 0:
		EventBus.driver_message.emit("%s  -  LOW GRIP" % WeatherFX.NAMES[weather], Color("7fd4ff"))
	_camera.snap_to_target()
	positions.update(cars, timers, track.length)
	_countdown = 3.6 if mode == GameManager.MODE_RACE else 1.2
	_hud.set_countdown(0 if mode == GameManager.MODE_RACE else -1)
	EventBus.race_state_changed.emit("countdown")


func _instantiate(scene_path: String, fallback: Variant) -> Node:
	if ResourceLoader.exists(scene_path):
		return (load(scene_path) as PackedScene).instantiate()
	return fallback.new()


# ---------------------------------------------------------------- setup

func _spawn_cars() -> void:
	var slot_for_player := PLAYER_GRID_SLOT if mode == GameManager.MODE_RACE else 0
	var livery := PLAYER_COLOR
	var livery2 := Color("23272e")
	if Career.active():
		# Your car wears the team's colours.
		livery = Color(str(Career.my_team()["color"]))
		livery2 = Color(str(Career.my_team()["color2"]))
	player = _make_car(GameManager.setup.duplicate_setup(), "You", livery, true, 0, "res://scenes/components/Car.tscn", livery2)
	_place_on_grid(player, slot_for_player)
	player_timer = timers[0]
	player_timer.lap_finished.connect(_on_player_lap)
	player_timer.sector_finished.connect(_on_player_sector)
	player_timer.lap_invalidated.connect(func() -> void: EventBus.driver_message.emit("LAP INVALID  ·  TRACK LIMITS", Color("ff5d5d")))
	player.collided.connect(func(strength: float) -> void: _camera.add_shake(2.0 + strength * 7.0))
	player.takes_damage = true
	player.damage_scale = Difficulty.damage_scale()
	player.wet = weather > 0
	# Conservative line speeds for the braking aid, on today's grip.
	_assist_profile = line.speed_profile(player.physics.stats, player.physics_config, (0.93 if weather == 0 else 0.86) * WeatherFX.grip(weather), 0.85 if weather == 0 else 0.75)
	player.uses_fuel = mode == GameManager.MODE_RACE
	player.damaged.connect(_on_player_damaged)
	player.destroyed.connect(_on_player_destroyed)
	if mode != GameManager.MODE_RACE:
		return
	var profiles: Array = []
	if not GameManager.career_race.is_empty():
		# Career grand prix: the seven cars around you on the real grid, in grid order.
		profiles = GameManager.career_race["rivals"]
		player.driver_name = GameManager.career_race["driver_name"]
	else:
		var data: Variant = SaveManager.load_json("res://data/progression/ai_drivers.json")
		profiles = data if data is Array else []
		profiles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["pace"]) > float(b["pace"]))
	var slot := 0
	for i in profiles.size():
		var profile: Dictionary = profiles[i]
		if slot == PLAYER_GRID_SLOT:
			slot += 1
		# Difficulty shifts every rival's pace; rain costs grip, more for poor wet-weather drivers.
		profile = profile.duplicate()
		profile["pace"] = clampf(float(profile.get("pace", 0.92)) + Difficulty.ai_pace_offset(), 0.8, 1.0)
		profile["aggression"] = clampf(float(profile.get("aggression", 0.5)) * Difficulty.ai_aggression_scale(), 0.1, 1.0)
		# In the wet everyone leaves a margin; the rain specialists leave less of one.
		profile["track_grip"] = WeatherFX.grip(weather) * (lerpf(0.84, 0.93, float(profile.get("wet", 0.75))) if weather > 0 else 1.0)
		var setup := _ai_setup(profile.get("setup", {}))
		var car := _make_car(setup, profile["name"], Color(profile.get("color", "#ffffff")), false, i + 1, "res://scenes/components/AICar.tscn", Color(str(profile.get("color2", "#23272e"))))
		_place_on_grid(car, slot)
		var driver := AIDriver.new()
		driver.name = "Driver"
		car.add_child(driver)
		car.physics.grip_scale = WeatherFX.grip(weather)
		car.wet = weather > 0
		driver.setup(car, line, profile, 1000 + i * 77 + randi() % 1000)
		driver.needs_recovery.connect(_recover_car)
		drivers.append(driver)
		var index := cars.size() - 1
		timers[index].lap_finished.connect(_on_ai_lap.bind(index))
		slot += 1
	for driver in drivers:
		driver.others = cars


func _ai_setup(overrides: Dictionary) -> CarSetup:
	var base: Dictionary = GameManager.default_profile()["car_setup"]
	for key: String in overrides:
		if CarSetup.SLOT_CATEGORY.has(key):
			base["parts"][key] = overrides[key]
		else:
			base[key] = overrides[key]
	return CarSetup.from_dict(base)


func _make_car(setup: CarSetup, driver_name: String, color: Color, is_player: bool, id: int, scene_path: String, color2: Color = Color("23272e")) -> VehicleController:
	var car := _instantiate(scene_path, VehicleController) as VehicleController
	car.setup = setup
	car.track = track
	car.driver_name = driver_name
	car.body_color = color
	car.accent_color = color2
	car.is_player = is_player
	car.car_id = id
	car.skid_marks = _skids
	add_child(car)
	cars.append(car)
	timers.append(LapTimer.new(track))
	_prev_progress.append(0.0)
	return car


func _place_on_grid(car: VehicleController, slot: int) -> void:
	var info := track.grid_slot(slot)
	car.place(info["position"], info["rotation"])
	_prev_progress[cars.find(car)] = car.progress


func _build_ghost() -> void:
	if mode != GameManager.MODE_TIME_TRIAL:
		return
	_ghost = CarVisual.new()
	_ghost.setup = player.setup
	_ghost.body_color = Color("7fd4ff")
	_ghost.accent_color = Color("7fd4ff")
	_ghost.alpha = 0.33
	_ghost.z_index = 1
	_ghost.visible = false
	add_child(_ghost)


func _apply_settings() -> void:
	if player == null:
		return
	player.physics.abs_level = int(GameManager.setting("abs"))
	player.physics.tc_level = int(GameManager.setting("traction_control"))
	player.physics.transmission.automatic = bool(GameManager.setting("automatic"))
	player.physics.stability_assist = 1.0 if bool(GameManager.setting("stability_assist")) else 0.0
	player.physics.grip_scale = WeatherFX.grip(weather) * Difficulty.player_grip()
	player.damage_scale = Difficulty.damage_scale()
	_line_assist.visible = bool(GameManager.setting("racing_line"))
	_camera.rotate_with_car = bool(GameManager.setting("camera_rotation"))


# ---------------------------------------------------------------- loop

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_pause()
	elif event.is_action_pressed("reset_car"):
		reset_player()


func _physics_process(delta: float) -> void:
	if state == State.COUNTDOWN:
		_countdown -= delta
		if mode == GameManager.MODE_RACE:
			var lights := clampi(int((3.6 - _countdown) / 1.0), 0, 3)
			if lights != _last_lights:
				_last_lights = lights
				_hud.set_countdown(lights)
				if lights > 0:
					AudioManager.play("beep", -6.0)
		if _countdown <= 0.0:
			_start()
		return
	race_time += delta
	for i in cars.size():
		var car := cars[i]
		timers[i].update(_prev_progress[i], car.progress, not car.off_track, race_time, delta)
		_prev_progress[i] = car.progress
	_update_player(delta)
	_position_timer -= delta
	if _position_timer <= 0.0:
		_position_timer = 0.2
		positions.update(cars, timers, track.length)
	if state == State.FINISHED:
		_finish_timer -= delta
		if _finish_timer <= 0.0 and not _leaving:
			_end_session("results")

var _last_lights := -1


func _start() -> void:
	state = State.RACING
	_hud.set_countdown(-1)
	_hud.flash_go()
	AudioManager.play("go", -4.0)
	for car in cars:
		car.controls_enabled = true
		car.start_audio()
	EventBus.race_state_changed.emit("racing")


func _update_player(delta: float) -> void:
	var lap_time := player_timer.current_time(race_time)
	if player_timer.started:
		_lap_trace.record(player.progress, lap_time)
		_ghost_recorder.record(lap_time, player.global_position, player.rotation)
		var ref := LapTrace.time_at(_reference_trace, player.progress)
		has_delta = ref >= 0.0 and reference_best > 0.0
		if has_delta:
			live_delta = lerpf(live_delta, lap_time - ref, minf(1.0, 8.0 * delta))
	telemetry.record(race_time, player_timer.laps_completed + 1 if player_timer.started else 0, player)
	if _ghost:
		_ghost.visible = player_timer.started and GhostRecorder.sample(_ghost_data, lap_time, _ghost_sample)
		if _ghost.visible:
			var rot: float = _ghost_sample["rotation"]
			# CarVisual's origin is the rear axle; the stored position is the centre of mass.
			_ghost.rotation = rot
			_ghost.global_position = (_ghost_sample["position"] as Vector2) - Vector2.RIGHT.rotated(rot) * player.physics.stats.cg_x * PPM
	_driver_feedback(delta)
	_update_assists()
	_update_pit_stop(delta)
	if state == State.RACING and not _objective_done and _mission.get("objective", {}).get("type", "") == "max_speed":
		if player.speed * 3.6 >= float(_mission["objective"]["target"]):
			_complete_objective()


# ---------------------------------------------------------------- driving aids

## Steering and braking help from the difficulty settings: the car is nudged toward the
## racing line and slowed when it arrives at a corner too fast. The player keeps control;
## the aids are blended in, never substituted.
func _update_assists() -> void:
	var steer_help := Difficulty.steer_assist()
	var brake_help := Difficulty.brake_assist()
	player.assist_steer_weight = 0.0
	player.assist_brake = 0.0
	if state != State.RACING or (steer_help <= 0.0 and brake_help <= 0.0) or _assist_profile.is_empty():
		return
	if track.in_pit_lane(player.progress, player.lateral) or player.physics.transmission.gear < 0:
		return
	var idx := player.track_index
	var v := player.speed
	if steer_help > 0.0 and v > 4.0:
		var look := idx + int((9.0 + v * 0.4) / track.spacing)
		var to_target := (line.point(look) - player.global_position).rotated(-player.rotation) / PPM
		var dist := maxf(to_target.length(), 1.0)
		var wheel := atan(2.0 * player.physics_config.wheelbase * to_target.y / (dist * dist))
		player.assist_steer = clampf(wheel / player.physics_config.max_steer_angle(v), -1.0, 1.0)
		player.assist_steer_weight = steer_help
	if brake_help > 0.0:
		var target := INF
		for k in range(0, int(v * 0.25 / track.spacing) + 2):
			target = minf(target, _assist_profile[posmod(idx + k, _assist_profile.size())])
		var over := v - target * 1.03
		if over > 0.0:
			player.assist_brake = clampf(over * 0.22, 0.0, 1.0) * brake_help


# ---------------------------------------------------------------- pit stops

## Stop in the red service box on the pit lane to repair damage, refuel and take new tires.
## The stop takes longer the more work there is, and less with a better pit crew.
func _update_pit_stop(delta: float) -> void:
	if state != State.RACING or player.is_destroyed:
		return
	if pit_timer > 0.0:
		pit_timer -= delta
		if pit_timer <= 0.0:
			pit_timer = 0.0
			player.damage = 0.0
			player.fuel = 100.0
			player.physics.reset_wear_and_heat()
			player.controls_enabled = true
			EventBus.driver_message.emit("GO GO GO  -  %.1f s STOP" % _pit_total, Color("5fe08a"))
			AudioManager.play("go", -6.0)
		return
	var p := player.physics
	var needs_service := player.damage > 1.0 or player.fuel < 97.0 or p.front_tire.wear < 0.97 or p.rear_tire.wear < 0.97
	if needs_service and player.speed < 2.5 and track.in_pit_box(player.progress, player.lateral):
		var crew := int(Career.state()["factory"]["pit"]) if Career.active() else 2
		_pit_total = maxf(2.0, 3.2 - 0.3 * crew) + player.damage * 0.07 + (100.0 - player.fuel) * 0.03
		pit_timer = _pit_total
		player.controls_enabled = false
		EventBus.driver_message.emit("PIT STOP  -  %.1f s" % _pit_total, Color("ffb347"))
		AudioManager.play("snap", -4.0)


# ---------------------------------------------------------------- damage and story

func _on_player_damaged(amount: float, total: float) -> void:
	_camera.add_shake(3.0 + amount * 0.4)
	if amount >= 3.0 and total < 100.0:
		EventBus.driver_message.emit("DAMAGE  %d%%" % int(total), Color("ff5d5d") if total > 60.0 else Color("ffb347"))


func _on_player_destroyed() -> void:
	player.explode()
	_camera.add_shake(16.0)
	_session["destroyed"] = true
	EventBus.driver_message.emit("CAR DESTROYED", Color("ff5d5d"))
	if state != State.FINISHED:
		state = State.FINISHED
		_finish_timer = 2.8
		EventBus.race_state_changed.emit("finished")


## Lap / speed objectives end the session as soon as they are met.
func _complete_objective() -> void:
	_objective_done = true
	_session["mission_complete"] = true
	EventBus.driver_message.emit("OBJECTIVE COMPLETE", Color("5fe08a"))
	AudioManager.play("finish", -4.0)
	if mode != GameManager.MODE_RACE and state == State.RACING:
		state = State.FINISHED
		_finish_timer = 2.6
		player.controls_enabled = false


## Short engineering messages. Each needs its condition held briefly and has a cooldown,
## so the screen never fills with chatter.
func _driver_feedback(delta: float) -> void:
	for key: String in _message_cooldowns.keys():
		_message_cooldowns[key] = float(_message_cooldowns[key]) - delta
	if state != State.RACING:
		return
	var p := player.physics
	var moving := player.speed > 8.0
	_feedback("BRAKE LOCK", moving and (p.front_tire.locked or p.rear_tire.locked), 0.12, 2.5, Color("ff5d5d"), delta)
	_feedback("REAR SLIP", moving and (p.oversteer or p.rear_tire.spinning), 0.25, 2.5, Color("ffb347"), delta)
	_feedback("UNDERSTEER", p.understeer, 0.45, 3.0, Color("ffb347"), delta)
	_feedback("TRACTION CONTROL", p.tc_active and player.speed > 5.0, 0.7, 5.0, Color("7fd4ff"), delta)
	_feedback("FRONT TIRES OVERHEATING", p.front_tire.is_overheating(), 0.5, 9.0, Color("ff5d5d"), delta)
	_feedback("REAR TIRES OVERHEATING", p.rear_tire.is_overheating(), 0.5, 9.0, Color("ff5d5d"), delta)
	_feedback("BRAKE FADE", p.brakes.is_fading(), 0.3, 9.0, Color("ff5d5d"), delta)
	_feedback("ENGINE HOT  ·  POWER REDUCED", p.engine.is_overheating(), 1.0, 12.0, Color("ff5d5d"), delta)
	_feedback("FUEL LOW  -  BOX THIS LAP", player.uses_fuel and player.fuel < 22.0 and pit_timer <= 0.0, 0.5, 25.0, Color("ffb347"), delta)
	_feedback("HEAVY DAMAGE  -  BOX FOR REPAIRS", player.damage > 60.0 and pit_timer <= 0.0, 0.5, 25.0, Color("ff5d5d"), delta)


func _feedback(text: String, condition: bool, hold: float, cooldown: float, color: Color, delta: float) -> void:
	var held: float = _condition_timers.get(text, 0.0)
	held = held + delta if condition else 0.0
	_condition_timers[text] = held
	if held >= hold and float(_message_cooldowns.get(text, 0.0)) <= 0.0:
		_message_cooldowns[text] = cooldown
		EventBus.driver_message.emit(text, color)


# ---------------------------------------------------------------- timing events

func _on_player_sector(sector: int, sector_time: float) -> void:
	var best_ever: Array = GameManager.record()["best_sectors"]
	var previous: float = float(best_ever[sector]) if sector < best_ever.size() else 0.0
	var color := Color("ffb347")
	if player_timer.current_valid or sector == 2:
		if previous <= 0.0 or sector_time < previous:
			color = Color("c77dff")
			if player_timer.lap_valid.is_empty() or player_timer.current_valid:
				best_ever[sector] = sector_time
		elif sector_time <= player_timer.best_sectors[sector] + 0.0005:
			color = Color("5fe08a")
	_hud.flash_sector(sector, color)
	if sector < 2:
		var text := "S%d  %.3f" % [sector + 1, sector_time]
		if previous > 0.0:
			text += "   %s" % LapTimer.format_time(sector_time - previous, true)
		EventBus.driver_message.emit(text, color)


func _on_player_lap(lap_time: float, valid: bool, lap_number: int) -> void:
	EventBus.lap_completed.emit(player, lap_time, valid)
	if valid and (_session_best <= 0.0 or lap_time < _session_best):
		_session_best = lap_time
		_session["session_best_lap_number"] = lap_number
	if valid and (reference_best <= 0.0 or lap_time < reference_best):
		# New personal best: store the delta trace, ghost and corner reference.
		var improvement := reference_best - lap_time
		_session["previous_pb_corners"] = (GameManager.record()["best_lap_corners"] as Array).duplicate(true)
		_session["new_pb"] = true
		_session["pb_lap_number"] = lap_number
		EventBus.driver_message.emit("PERSONAL BEST  %s%s" % [LapTimer.format_time(lap_time), ("  (-%.3f)" % improvement) if reference_best > 0.0 else ""], Color("c77dff"))
		reference_best = lap_time
		_reference_trace = _lap_trace.to_array()
		_ghost_data = _ghost_recorder.samples
		GameManager.record()["best_lap"] = lap_time
		GameManager.record()["best_lap_trace"] = _reference_trace
		GameManager.record()["ghost_data"] = _ghost_data
		GameManager.record()["best_lap_corners"] = TelemetryAnalyzer.corner_stats(telemetry, track, lap_number)
		GameManager.save()
		AudioManager.play("finish", -8.0)
	else:
		var note := "" if valid else "  (INVALID)"
		EventBus.driver_message.emit("LAP %s%s" % [LapTimer.format_time(lap_time), note], Color.WHITE if valid else Color("ff5d5d"))
	_lap_trace.clear()
	_ghost_recorder.begin_lap()
	live_delta = 0.0
	var objective: Dictionary = _mission.get("objective", {})
	if not _objective_done and valid and state == State.RACING:
		var kind: String = objective.get("type", "")
		if kind == "complete_lap" or (kind == "lap_time" and lap_time <= float(objective.get("target", 0.0))):
			_complete_objective()
	if mode == GameManager.MODE_RACE and lap_number >= GameManager.RACE_LAPS and state == State.RACING:
		_finish_count += 1
		player_timer.finish_time = race_time
		_session["finished"] = true
		state = State.FINISHED
		_finish_timer = FINISH_DELAY
		player.controls_enabled = false
		positions.update(cars, timers, track.length)
		if _mission.get("objective", {}).get("type", "") == "race_position" and positions.position_of(player) <= int(_mission["objective"]["target"]):
			_session["mission_complete"] = true
		EventBus.driver_message.emit("FINISH  ·  P%d" % positions.position_of(player), Color("7fd4ff"))
		AudioManager.play("finish", -4.0)
		EventBus.race_state_changed.emit("finished")


func _on_ai_lap(_lap_time: float, _valid: bool, lap_number: int, index: int) -> void:
	if mode == GameManager.MODE_RACE and lap_number >= GameManager.RACE_LAPS and timers[index].finish_time < 0.0:
		_finish_count += 1
		timers[index].finish_time = race_time


# ---------------------------------------------------------------- actions

func reset_player() -> void:
	if state != State.RACING or player == null or player.is_destroyed:
		return
	_recover_car(player)
	if player_timer.started:
		player_timer.add_penalty(RESET_PENALTY)
		EventBus.driver_message.emit("RESET  ·  +%d s" % int(RESET_PENALTY), Color("ff5d5d"))


## Puts a car back on the nearest piece of track, stationary and pointing the right way.
func _recover_car(car: VehicleController) -> void:
	var idx := track.nearest_index(car.global_position)
	var progress := idx * track.spacing
	# Stay off the centre line if another car is sitting there.
	var lateral := 0.0
	for other in cars:
		if other != car and absf(track.progress_delta(progress, other.progress)) < 8.0 and absf(other.lateral) < 2.5:
			lateral = 3.5 if other.lateral <= 0.0 else -3.5
	car.place(track.position_at(progress, lateral), track.heading_at(progress))
	_prev_progress[cars.find(car)] = car.progress


func toggle_pause() -> void:
	if _leaving:
		return
	var paused := not get_tree().paused
	get_tree().paused = paused
	_hud.set_paused(paused)
	_controls.release_all()


func restart() -> void:
	_leaving = true
	get_tree().paused = false
	SceneManager.goto("race")


func finish_session() -> void:
	_end_session("results")


## Leave without the results screen (quick return to the garage keeps the loop tight).
func leave_to(scene_key: String) -> void:
	_end_session(scene_key)
	GameManager.active_mission = -1


func _end_session(next_scene: String) -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().paused = false
	positions.update(cars, timers, track.length)
	var was_career := not GameManager.career_race.is_empty()
	GameManager.last_results = RaceResults.build(mode, player_timer, positions.position_of(player), cars.size(), _classification(), telemetry, track, _session)
	# A career race always goes through the results screen so the outcome is shown.
	SceneManager.goto("results" if was_career else next_scene)


func _classification() -> Array:
	var rows: Array = []
	var leader_time := -1.0
	for car: VehicleController in positions.order:
		var timer := timers[cars.find(car)]
		var finished := timer.finish_time >= 0.0
		if finished and leader_time < 0.0:
			leader_time = timer.finish_time
		rows.append({
			"name": car.driver_name,
			"is_player": car == player,
			"color": car.body_color.to_html(false),
			"laps": timer.laps_completed,
			"best_lap": timer.best_lap,
			"finished": finished,
			"gap": (timer.finish_time - leader_time) if finished and leader_time >= 0.0 else -1.0,
			"time": timer.finish_time,
		})
	return rows
