class_name RaceManager
extends Node2D
## Runs one on-track session (test drive, time trial or a short race): builds the grid,
## owns timing / positions / telemetry for every car and hands results to the next scene.

enum State { COUNTDOWN, RACING, FINISHED }

const PPM := VehiclePhysicsConfig.PPM
const RESET_PENALTY := 3.0
const PLAYER_GRID_SLOT := 3
## Cars in a free race (headless tests that fast-forward use fewer).
static var free_field_size := 20
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
## "" racing, "in" driving down the lane, "service" crew at work, "out" leaving the lane.
var pit_phase := ""
var _pit_choice := ""
var _crew: PitCrewFX
var _stops := 0
var _dry_compounds := {}
var _used_wet := false
var _ai_pit_lap: Array = []
## BOX tapped: the car steers itself into the pit lane at the next pit entry.
var box_armed := false
var _pit_guide: PitGuide
var _drs_zones: Array = []
var drs_available := false
var drs_open := false
## Seconds added to the player's race time (track limits, skipped pit stop).
var race_penalty := 0.0
var _strikes := 0
var _was_off := false
var _controls_layer: CanvasLayer
var _quali_attempts := 0
const PIT_SPEED := 22.2               # 80 km/h
## 0 dry, 1 light rain, 2 heavy rain.
var weather := 0
var _assist_profile := PackedFloat32Array()
var _crowd: AudioStreamPlayer
var _gantry: StartGantry


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
	_pit_guide = PitGuide.new()
	_pit_guide.track = track_node.data
	add_child(_pit_guide)
	_gantry = StartGantry.new()
	_gantry.track = track_node.data
	add_child(_gantry)
	if GameManager.session_night:
		var dark := CanvasModulate.new()
		dark.color = Color(0.3, 0.34, 0.5)
		add_child(dark)
		var lights := NightLights.new()
		lights.lamps = track_node.lamp_positions
		lights.stands = track_node.stand_positions
		add_child(lights)
	# The crowd gets louder as you come past the grandstands.
	_crowd = AudioManager.make_loop_player("crowd", false) as AudioStreamPlayer
	add_child(_crowd)
	_crowd.play()
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
	_controls_layer = controls_layer
	_find_drs_zones()
	_plan_ai_stops()
	_note_compound()
	_controls.input = player.input
	_controls.car = player
	var debug := DebugOverlay.new()
	debug.manager = self
	add_child(debug)
	EventBus.settings_changed.connect(_apply_settings)
	_apply_settings()
	if weather > 0:
		EventBus.driver_message.emit("%s  -  LOW GRIP" % WeatherFX.NAMES[weather], Color("7fd4ff"))
	_camera.snap_to_target()
	positions.update(cars, timers, track.length)
	# On the grid: how wide this circuit is (6.32 car widths, narrower in a few places).
	EventBus.driver_message.emit("TRACK %s" % track.width_text(), Color.WHITE)
	# First race on this save: point out the controls (the countdown waits).
	CoachMarks.run_once(self, "race", func() -> Array: return [
		[_controls.steer_rect(), "STEER here with your left thumb: slide left and right."],
		[_controls.pedal_rect(), _controls.pedal_hint()],
		[_hud._map, "The MAP shows every car. Watch the weather in its corner."],
		[_hud._status, "TYRES are a budget that has to last to your pit stop. Hard acceleration and braking spend it fastest; keep the bar ahead of the white tick. FUEL and DAMAGE too - arrows point to the pits when one runs low."],
		[_hud._box, "Tap BOX: the car slides itself into the pits, the crew does the work, then YOU accelerate out."],
		[_hud._drs, "DRS lights up on straights when you're within a second of the car ahead. Tap it to open the wing; braking closes it."],
		[_hud.marks["cam"], "CAM switches between the driver's view and the overhead view."],
		[_hud.marks["reset"], "Stuck? RESET puts you back on track for a 3-second penalty."],
	], true)
	_countdown = 3.6 if mode == GameManager.MODE_RACE else 1.2
	_hud.set_countdown(0 if mode == GameManager.MODE_RACE else -1)
	EventBus.race_state_changed.emit("countdown")


func _instantiate(scene_path: String, fallback: Variant) -> Node:
	if ResourceLoader.exists(scene_path):
		return (load(scene_path) as PackedScene).instantiate()
	return fallback.new()


# ---------------------------------------------------------------- setup

func _spawn_cars() -> void:
	var slot_for_player := int(GameManager.career_race.get("grid_slot", PLAYER_GRID_SLOT)) if mode == GameManager.MODE_RACE else 0
	var livery := PLAYER_COLOR
	var livery2 := Color("23272e")
	if Career.active():
		# Your car wears the team's colours.
		livery = Color(str(Career.my_team()["color"]))
		livery2 = Color(str(Career.my_team()["color2"]))
	var livery_override: Array = GameManager.career_race.get("livery", [])
	if livery_override.size() == 2:
		livery = Color(str(livery_override[0]))
		livery2 = Color(str(livery_override[1]))
	# Road to Glory races the series car, not the garage build.
	var own_setup := CarSetup.from_dict(GameManager.career_race["setup"]) if GameManager.career_race.has("setup") else GameManager.setup.duplicate_setup()
	player = _make_car(own_setup, "You", livery, true, 0, "res://scenes/components/Car.tscn", livery2)
	_place_on_grid(player, slot_for_player)
	player_timer = timers[0]
	player_timer.lap_finished.connect(_on_player_lap)
	player_timer.sector_finished.connect(_on_player_sector)
	player_timer.lap_invalidated.connect(func() -> void: EventBus.driver_message.emit("LAP INVALID  ·  TRACK LIMITS", Color("ff5d5d")))
	# Contact with a car or the wall gives the camera a slight shake.
	player.collided.connect(func(strength: float) -> void:
		_camera.add_shake(1.5 + strength * 3.5)
		_camera.kick(strength * 0.25))
	player.takes_damage = true
	player.damage_scale = Difficulty.damage_scale()
	player.wet = weather > 0
	# Conservative line speeds for the braking aid, on today's grip.
	_assist_profile = line.speed_profile(player.physics.stats, player.physics_config, (0.93 if weather == 0 else 0.86) * WeatherFX.tire_grip(weather, player.setup), 0.85 if weather == 0 else 0.75)
	player.uses_fuel = mode == GameManager.MODE_RACE
	player.damaged.connect(_on_player_damaged)
	player.destroyed.connect(_on_player_destroyed)
	if mode != GameManager.MODE_RACE:
		return
	var profiles: Array = []
	if not GameManager.career_race.is_empty():
		# Career grand prix: the nineteen cars around you on the real grid, in grid order.
		profiles = GameManager.career_race["rivals"]
		player.driver_name = GameManager.career_race["driver_name"]
	else:
		profiles = _free_field()
	var slot := 0
	for i in profiles.size():
		var profile: Dictionary = profiles[i]
		if slot == slot_for_player:
			slot += 1
		# Difficulty shifts every rival's pace; rain costs grip, more for poor wet-weather drivers.
		profile = profile.duplicate()
		profile["pace"] = clampf(float(profile.get("pace", 0.92)) + Difficulty.ai_pace_offset(), 0.8, 1.0)
		profile["aggression"] = clampf(float(profile.get("aggression", 0.5)) * Difficulty.ai_aggression_scale(), 0.1, 1.0)
		# In the wet everyone leaves a margin; the rain specialists leave less of one.
		var setup := _ai_setup(profile.get("setup", {}))
		profile["track_grip"] = WeatherFX.tire_grip(weather, setup) * (lerpf(0.84, 0.93, float(profile.get("wet", 0.75))) if weather > 0 else 1.0)
		var car := _make_car(setup, profile["name"], Color(profile.get("color", "#ffffff")), false, i + 1, "res://scenes/components/AICar.tscn", Color(str(profile.get("color2", "#23272e"))))
		_place_on_grid(car, slot)
		var driver := AIDriver.new()
		driver.name = "Driver"
		car.add_child(driver)
		car.physics.grip_scale = WeatherFX.tire_grip(weather, setup)
		car.wet = weather > 0
		driver.setup(car, line, profile, 1000 + i * 77 + randi() % 1000)
		driver.needs_recovery.connect(_recover_car)
		drivers.append(driver)
		var index := cars.size() - 1
		timers[index].lap_finished.connect(_on_ai_lap.bind(index))
		slot += 1
	for driver in drivers:
		driver.others = cars


## A free race is a full Formula One grid: nineteen real drivers in their team colours, each
## with their card's attributes, quickest cars first. Their car setups come from ai_drivers.json.
func _free_field() -> Array:
	var setups: Variant = SaveManager.load_json("res://data/progression/ai_drivers.json")
	var base: Variant = SaveManager.load_json("res://data/career/drivers.json")
	var teams := {}
	for t: Dictionary in Career.teams:
		teams[t["id"]] = t
	var out: Array = []
	if base is Array:
		for d: Dictionary in base:
			if d.get("reserve", false) or not teams.has(d["team"]):
				continue
			var t: Dictionary = teams[d["team"]]
			var template: Dictionary = (setups as Array)[out.size() % (setups as Array).size()] if setups is Array and not (setups as Array).is_empty() else {}
			out.append({"name": d["name"], "color": t["color"], "color2": t["color2"],
				"pace": clampf(0.9 + (float(t["car"]) - 75.0) * 0.003, 0.86, 0.98), "braking_accuracy": clampf(float(d["consistency"]) / 100.0, 0.7, 0.97),
				"consistency": clampf(float(d["consistency"]) / 100.0, 0.7, 0.97), "aggression": clampf(float(d.get("ego", 50)) / 100.0, 0.3, 0.9),
				"tire_management": 0.7, "error_rate": clampf((100.0 - float(d["consistency"])) / 170.0, 0.03, 0.2), "wet": clampf(float(d.get("wet", 75)) / 100.0, 0.4, 1.0),
				"attrs": Career.driver_attributes(d), "setup": template.get("setup", {})})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["pace"]) > float(b["pace"]))
	return out.slice(0, free_field_size - 1)


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
	player.physics.grip_scale = WeatherFX.tire_grip(weather, player.setup) * Difficulty.player_grip()
	player.damage_scale = Difficulty.damage_scale()
	_line_assist.visible = bool(GameManager.setting("racing_line"))
	_camera.rotate_with_car = bool(GameManager.setting("camera_rotation"))
	_camera.driver_view = int(GameManager.setting("camera_mode")) == 1
	_hud.set_driver_view(_camera.driver_view)


# ---------------------------------------------------------------- loop

## CAM: the overhead camera or the low driver's view.
func cycle_view() -> void:
	GameManager.set_setting("camera_mode", 1 - int(GameManager.setting("camera_mode")))
	GameManager.save()
	_apply_settings()


## Where a point of the world is on screen (HUD markers use this).
func screen_point(world: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world


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
				_gantry.set_lit(lights + 2 if lights > 0 else 0)
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
	_gantry.set_lit(0)
	_hud.set_countdown(-1)
	_hud.flash_go()
	AudioManager.play("go", -4.0)
	for car in cars:
		car.controls_enabled = true
		car.start_audio()
	EventBus.race_state_changed.emit("racing")
	if _stop_still_required():
		EventBus.driver_message.emit("MANDATORY STOP  ·  USE 2 DRY COMPOUNDS  ·  BOX BY LAP %d" % GameManager.race_laps, Color("ffb347"))


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
	_update_crowd(delta)
	_update_rules(delta)
	if pit_phase == "":
		_update_assists()
	else:
		player.assist_steer_weight = 0.0
		player.assist_brake = 0.0
	_update_pit_stop(delta)
	_pit_guide.showing = state == State.RACING and pit_phase == "" and (box_armed or pit_reason() != "")
	if state == State.RACING and not _objective_done and _mission.get("objective", {}).get("type", "") == "max_speed":
		if player.speed * 3.6 >= float(_mission["objective"]["target"]):
			_complete_objective()


func _update_crowd(delta: float) -> void:
	var nearest := INF
	for p in track_node.stand_positions:
		nearest = minf(nearest, p.distance_to(player.global_position) / PPM)
	var closeness := clampf(1.0 - (nearest - 25.0) / 230.0, 0.0, 1.0)
	var want := lerpf(-38.0, -4.0, closeness * closeness)
	_crowd.volume_db = lerpf(_crowd.volume_db, want, minf(1.0, 3.0 * delta))


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

## Roll into the pit lane and the stop plays itself: the car drives down the lane at the
## 80 km/h limit, the crew swaps tyres, fixes damage and refuels, you pick the next tyre,
## and the car is released at the lane exit. A better pit crew (factory level) is faster.
func _update_pit_stop(delta: float) -> void:
	if state != State.RACING or player.is_destroyed:
		return
	var lane := -(track.half_width + TrackData.PIT_WIDTH * 0.55)
	match pit_phase:
		"":
			if track.in_pit_lane(player.progress, player.lateral) and player.lateral < -(track.half_width + 0.8) and player.progress < track.pit_box - 25.0:
				_begin_pit()
			elif box_armed and player_timer.started and (player.progress > track.length - PitGuide.RUN_IN or (player.progress < track.pit_start - 12.0 and player_timer.laps_completed >= 1)):
				# BOX: hand the wheel to the crew's autopilot for the run into the lane.
				pit_phase = "entry"
				player.autopilot = true
				_controls.release_all()
				_controls_layer.visible = false
		"entry":
			var to_entry := fposmod(track.pit_start - player.progress, track.length)
			var into := track.pit_start <= player.progress and player.progress < track.pit_end
			var edge := -(track.half_width - 1.4)
			_autodrive(lane if into else edge, minf(70.0, sqrt(PIT_SPEED * PIT_SPEED + 2.0 * 9.0 * maxf(0.0, to_entry - 15.0))) if not into else PIT_SPEED)
			if into and player.lateral < -(track.half_width + 0.8):
				_begin_pit()
			elif into and player.progress > track.pit_box - 25.0:
				# Missed it: give the car back and try again next lap.
				pit_phase = ""
				player.autopilot = false
				_controls_layer.visible = true
				EventBus.driver_message.emit("MISSED THE PIT ENTRY  -  BOX NEXT LAP", Color("ff5d5d"))
		"in":
			var to_box := track.pit_box - player.progress
			_autodrive(lane, minf(PIT_SPEED, sqrt(maxf(0.0, 2.0 * 7.0 * (to_box - 0.6)))))
			if to_box < 1.6 and player.speed < 0.8:
				_start_service()
		"service":
			player.input.throttle = 0.0
			player.input.brake = 1.0
			pit_timer = maxf(0.0, pit_timer - delta)
			_crew.progress = 1.0 - pit_timer / maxf(_pit_total, 0.01)
			if pit_timer <= 0.0:
				_finish_service()
		"out":
			# Your throttle takes you out: the crew keeps you in the lane and the limiter holds
			# 80 km/h until the pit exit.
			var past := player.progress - (track.pit_end - 70.0)
			player.input.update_player(delta)
			var throttle := player.input.throttle
			var brake := player.input.brake
			_autosteer(lerpf(lane, -2.5, clampf(past / 60.0, 0.0, 1.0)))
			player.input.throttle = throttle if player.speed < PIT_SPEED or past >= 0.0 else 0.0
			player.input.brake = brake
			if player.progress > track.pit_end - 8.0:
				pit_phase = ""
				player.autopilot = false
				_camera.focus = Vector2.INF
				_controls_layer.visible = true
				_hud.show_tyre_choice([], "", false)


## Arms or cancels BOX: the car pits itself at the next pit entry.
func toggle_box() -> void:
	if state != State.RACING or pit_phase != "":
		return
	box_armed = not box_armed
	EventBus.driver_message.emit("BOX BOX  -  PITTING THIS LAP" if box_armed else "BOX CANCELLED", Color("ffb347") if box_armed else Color.WHITE)
	AudioManager.play("click", -8.0)


## Why the car should stop now ("" = no need): low fuel, heavy damage, worn tyres, or the
## mandatory stop on its last chance.
func pit_reason() -> String:
	if player == null or state != State.RACING:
		return ""
	if player.uses_fuel and player.fuel < 25.0:
		return "LOW FUEL"
	if player.damage > 50.0:
		return "HEAVY DAMAGE"
	if tyre_life() < 0.3:
		return "TYRES SPENT"
	if _stop_still_required() and player_timer.laps_completed >= GameManager.race_laps - 2:
		return "MANDATORY STOP"
	return ""


## 1 = new tyres, 0 = worn out (the worse axle).
func tyre_life() -> float:
	return minf(player.physics.front_tire.wear, player.physics.rear_tire.wear)


## "" outside races; otherwise the two-compound rule's status for the HUD.
func tyre_rule_text() -> String:
	if mode != GameManager.MODE_RACE or not GameManager.mandatory_stop:
		return ""
	if weather > 0 or _used_wet:
		return "WET RACE  ·  NO STOP NEEDED"
	if not _stop_still_required():
		return "TYRE RULE MET"
	return "MUST PIT BY LAP %d" % GameManager.race_laps


func stop_required() -> bool:
	return _stop_still_required()


func _begin_pit() -> void:
	box_armed = false
	pit_phase = "in"
	player.autopilot = true
	_controls.release_all()
	_controls_layer.visible = false
	_camera.focus = track.position_at(track.pit_box, -(track.half_width + TrackData.PIT_WIDTH * 0.55))
	# The crew already knows which tyre goes on next: no menu, just the stop.
	_pit_choice = _default_tyre()
	var name := PartDB.get_part(_pit_choice).display_name.to_upper() if PartDB.get_part(_pit_choice) else "NEW TYRES"
	EventBus.driver_message.emit("BOX BOX  -  %s GOING ON" % name, Color("ffb347"))


func _start_service() -> void:
	pit_phase = "service"
	var crew := int(Career.state()["factory"]["pit"]) if Career.active() else 2
	_pit_total = maxf(1.9, 2.9 - 0.22 * crew) + player.damage * 0.045 + (100.0 - player.fuel) * 0.02
	# Even good crews fumble now and then; bad ones more often.
	if randf() < 0.14 - crew * 0.02:
		_pit_total += randf_range(1.2, 3.0)
		EventBus.driver_message.emit("WHEEL NUT STUCK!", Color("ff5d5d"))
	pit_timer = _pit_total
	_crew = PitCrewFX.new()
	_crew.car = player
	_crew.color = player.body_color
	_crew.color2 = player.accent_color
	_crew.wing = player.damage > 30.0
	_crew.new_tire = CarVisual.COMPOUND_COLORS.get(_pit_choice, Color.WHITE)
	add_child(_crew)
	AudioManager.play("snap", -4.0)


func _finish_service() -> void:
	var setup := player.setup
	if _pit_choice != "" and setup.parts.get("tires", "") != _pit_choice:
		setup.install("tires", _pit_choice)
		player.configure(setup, track)
		_apply_settings()
	_note_compound()
	player.damage = 0.0
	player.fuel = 100.0
	player.physics.reset_wear_and_heat()
	_stops += 1
	_crew.queue_free()
	_crew = null
	pit_phase = "out"
	_controls_layer.visible = true
	EventBus.driver_message.emit("GO GO GO  -  ACCELERATE OUT  (%.1f s STOP)" % _pit_total, Color("5fe08a"))
	AudioManager.play("go", -6.0)


func choose_tyre(part_id: String) -> void:
	_pit_choice = part_id
	if _crew:
		_crew.new_tire = CarVisual.COMPOUND_COLORS.get(part_id, Color.WHITE)
	_hud.show_tyre_choice(_tyre_options(), _pit_choice, _stop_still_required())


## Keep the choice simple: hard, medium and soft in the dry, intermediates and wets in the
## rain (whatever the team has), plus the set already on the car.
func _tyre_options() -> Array:
	var out: Array = []
	var ids := ["tires_hard", "tires_medium", "tires_soft"] if weather == 0 else ["tires_inter", "tires_wet", "tires_medium"]
	var current: String = player.setup.parts.get("tires", "")
	if current != "" and not ids.has(current):
		ids.append(current)
	for id: String in ids:
		if GameManager.is_unlocked(id):
			out.append(id)
	return out


func _default_tyre() -> String:
	var current: String = player.setup.parts.get("tires", "tires_hard")
	if weather > 0:
		return "tires_wet" if weather == 2 and GameManager.is_unlocked("tires_wet") else ("tires_inter" if GameManager.is_unlocked("tires_inter") else current)
	if not _stop_still_required():
		return current
	for id: String in ["tires_medium", "tires_hard", "tires_soft"]:
		if id != current and GameManager.is_unlocked(id):
			return id
	for id: String in _tyre_options():
		var part := PartDB.get_part(id)
		if id != current and part.stat("wet", 0.0) == 0.0:
			return id
	return current


func _note_compound() -> void:
	var part := player.setup.part("tires")
	if part and part.stat("wet", 0.0) == 0.0:
		_dry_compounds[part.id] = true
	elif part:
		_used_wet = true


## Grand Prix rule: two different dry compounds in a dry race (wet tyres excuse it).
func _stop_still_required() -> bool:
	return mode == GameManager.MODE_RACE and GameManager.mandatory_stop and weather == 0 and not _used_wet and _dry_compounds.size() < 2


## Steering only, for when the player has the pedals (leaving the pit box).
func _autosteer(lateral: float) -> void:
	var look := player.progress + 7.0 + player.speed * 0.45
	var to_target := (track.position_at(look, lateral) - player.global_position).rotated(-player.rotation) / PPM
	var dist := maxf(to_target.length(), 1.0)
	var wheel := atan(2.0 * player.physics_config.wheelbase * to_target.y / (dist * dist))
	player.input.steer = clampf(wheel / player.physics_config.max_steer_angle(player.speed), -1.0, 1.0)


func _autodrive(lateral: float, target_speed: float) -> void:
	var look := player.progress + 7.0 + player.speed * 0.45
	var to_target := (track.position_at(look, lateral) - player.global_position).rotated(-player.rotation) / PPM
	var dist := maxf(to_target.length(), 1.0)
	var wheel := atan(2.0 * player.physics_config.wheelbase * to_target.y / (dist * dist))
	player.input.steer = clampf(wheel / player.physics_config.max_steer_angle(player.speed), -1.0, 1.0)
	var error := target_speed - player.speed
	player.input.throttle = clampf(error * 0.3, 0.0, 0.7)
	player.input.brake = clampf(-error * 0.35, 0.0, 1.0)


## Rivals stop once in a Grand Prix too, before the last lap, driving through the same pit lane.
func _plan_ai_stops() -> void:
	_ai_pit_lap.clear()
	for i in cars.size():
		var lap := -1
		if mode == GameManager.MODE_RACE and GameManager.mandatory_stop and i > 0:
			lap = randi_range(1, maxi(1, GameManager.race_laps - 1))
		_ai_pit_lap.append(lap)


# ---------------------------------------------------------------- racing rules

## DRS zones: the long straights. Within one second of the car ahead at the zone, from
## lap 2, the rear flap may open until the driver brakes.
func _find_drs_zones() -> void:
	_drs_zones.clear()
	var i := 0
	var n := track.count
	while i < n:
		if absf(track.curvature[i]) < 0.0025:
			var start := i
			while i < n and absf(track.curvature[i]) < 0.0025:
				i += 1
			if (i - start) * track.spacing >= 380.0:
				_drs_zones.append(Vector2((start * track.spacing) + 60.0, (i * track.spacing) - 50.0))
		else:
			i += 1


func _in_drs_zone(progress: float) -> bool:
	for z: Vector2 in _drs_zones:
		if progress >= z.x and progress <= z.y:
			return true
	return false


## Seconds to the car directly ahead on the road (INF when nobody is close).
func _gap_ahead(car: VehicleController) -> float:
	var best := INF
	for other in cars:
		if other == car:
			continue
		var d := track.progress_delta(car.progress, other.progress)
		if d > 0.0 and d < best:
			best = d
	return best / maxf(car.speed, 10.0)


func _update_rules(_delta: float) -> void:
	if state != State.RACING or mode != GameManager.MODE_RACE:
		drs_available = false
		return
	# DRS for everyone.
	for i in cars.size():
		var car := cars[i]
		var eligible := timers[i].laps_completed >= 1 and _in_drs_zone(car.progress) and _gap_ahead(car) < 1.0
		if i == 0:
			drs_available = eligible and pit_phase == ""
			if not drs_available or car.input.brake > 0.1:
				drs_open = false
			car.physics.aero.drs = drs_open
		else:
			drivers[i - 1].drs_allowed = eligible
	# Track limits: three warnings, then five seconds each time.
	var off := player.off_track and pit_phase == "" and player.speed > 10.0
	if off and not _was_off:
		_strikes += 1
		if _strikes <= 3:
			EventBus.driver_message.emit("TRACK LIMITS  -  WARNING %d/3" % _strikes, Color("ffb347"))
		else:
			race_penalty += 5.0
			EventBus.driver_message.emit("TRACK LIMITS  -  +5 s PENALTY", Color("ff5d5d"))
	_was_off = off


func open_drs() -> void:
	if drs_available:
		drs_open = true
		AudioManager.play("click", -6.0, 0.7)


# ---------------------------------------------------------------- damage and story

func _on_player_damaged(amount: float, total: float) -> void:
	_camera.add_shake(minf(4.0, 1.0 + amount * 0.15))
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
	_feedback("FUEL LOW  -  BOX THIS LAP", player.uses_fuel and player.fuel < 22.0 and pit_phase == "", 0.5, 25.0, Color("ffb347"), delta)
	_feedback("HEAVY DAMAGE  -  BOX FOR REPAIRS", player.damage > 60.0 and pit_phase == "", 0.5, 25.0, Color("ff5d5d"), delta)
	_feedback("MANDATORY STOP  -  BOX THIS LAP OR +25 s", _stop_still_required() and player_timer.laps_completed >= GameManager.race_laps - 2 and player.progress > track.length * 0.5 and pit_phase == "", 0.5, 30.0, Color("ffb347"), delta)
	_feedback("TYRE BUDGET NEARLY SPENT  -  BOX FOR NEW ONES", tyre_life() < 0.3 and pit_phase == "", 0.5, 25.0, Color("ffb347"), delta)
	var plan := player.tyre_target()
	_feedback("SPENDING THE TYRES TOO FAST  -  EASE INTO THE THROTTLE", plan >= 0.0 and tyre_life() < plan - 0.12 and tyre_life() >= 0.3 and pit_phase == "", 1.5, 30.0, Color("ffb347"), delta)


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


## The car's ideal lap here: its own speed profile driven perfectly. Qualifying laps are
## judged against it, so a well-driven slow car still gets credit.
func ideal_lap() -> float:
	var profile := line.speed_profile(player.physics.stats, player.physics_config, WeatherFX.tire_grip(weather, player.setup), 1.0)
	var t := 0.0
	for v in profile:
		t += track.spacing / maxf(v, 5.0)
	return t


func _quali_lap(lap_time: float, valid: bool) -> void:
	var driver_id: String = GameManager.career_race["quali"]
	_quali_attempts += 1
	if valid:
		var grid := Career.apply_quali(driver_id, lap_time, lap_time / ideal_lap())
		EventBus.driver_message.emit("QUALIFIED  P%d  ·  %s" % [grid, LapTimer.format_time(lap_time)], Color("c77dff"))
	elif _quali_attempts < 3:
		EventBus.driver_message.emit("LAP DELETED  -  GO AGAIN (%d LEFT)" % (3 - _quali_attempts), Color("ff5d5d"))
		return
	else:
		EventBus.driver_message.emit("NO VALID LAP  -  GRID UNCHANGED", Color("ff5d5d"))
	state = State.FINISHED
	_finish_timer = 2.4
	player.controls_enabled = false


func _on_player_lap(lap_time: float, valid: bool, lap_number: int) -> void:
	if GameManager.career_race.has("quali"):
		_quali_lap(lap_time, valid)
		return
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
	if mode == GameManager.MODE_RACE and lap_number >= GameManager.race_laps and state == State.RACING:
		_finish_count += 1
		if _stop_still_required():
			race_penalty += 25.0
			EventBus.driver_message.emit("NO PIT STOP  -  +25 s PENALTY", Color("ff5d5d"))
		player_timer.finish_time = race_time + race_penalty
		_session["finished"] = true
		_session["stops"] = _stops
		_session["penalty"] = race_penalty
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
	if index < _ai_pit_lap.size() and lap_number == int(_ai_pit_lap[index]) and lap_number < GameManager.race_laps:
		drivers[index - 1].start_pit(randf_range(2.3, 3.4))
	if mode == GameManager.MODE_RACE and lap_number >= GameManager.race_laps and timers[index].finish_time < 0.0:
		_finish_count += 1
		timers[index].finish_time = race_time


# ---------------------------------------------------------------- actions

func reset_player() -> void:
	if state != State.RACING or player == null or player.is_destroyed or pit_phase != "":
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
	if GameManager.career_race.has("practice"):
		# Practice books the laps you did and goes back to HQ.
		Career.last_note = Career.finish_practice_drive(player_timer.laps_completed)
		GameManager.career_race = {}
		SceneManager.goto("career")
		return
	if GameManager.career_race.has("quali"):
		# Qualifying goes straight back to race day with the new grid.
		GameManager.career_race = {}
		SceneManager.goto("raceday")
		return
	var was_career := not GameManager.career_race.is_empty()
	_session["ideal_lap"] = ideal_lap()
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
