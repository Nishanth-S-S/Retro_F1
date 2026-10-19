class_name Race3D
extends CanvasLayer
## The race in 3D. The simulation stays the 2D one underneath (same physics, AI and rules);
## this layer mirrors it every frame into a lit 3D scene and films it from one of six views,
## each with its own anchor on the car (Car3D) and its own settings:
##   CHASE    behind and above your car, like a console racer
##   HIGH     a raised camera that reads the track ahead
##   TV POD   the camera on top of the airbox, above the driver
##   COCKPIT  the driver's eyes (DriverEye anchor): wheel, display, halo, nose ahead
##   NOSE     low on the nose
##   TOP      the classic top-down 2D view (this layer hides itself)
## CAM on the HUD cycles them; the choice is saved in settings ("camera_view").
## Camera3D.fov is vertical (keep_aspect = KEEP_HEIGHT), so every FOV here is vertical.

const VIEWS: PackedStringArray = ["CHASE", "HIGH", "TV POD", "COCKPIT", "NOSE", "TOP"]
const TOP := 5
const COCKPIT := 3
## Per-car cockpit calibration, saved in settings["cockpit_cal"][model]. All cars share one
## model today; a different chassis would get its own key.
const MODEL := "f1"
const CAL_DEFAULTS := {"eye": [0.0, 0.0, 0.0], "pitch": -4.0, "roll": 0.0, "near": 0.04, "head": 1.0, "horizon": 0.35, "cockpit_mesh": true}
const PPM := VehiclePhysicsConfig.PPM

var race: RaceManager
var view := 0
var _container: SubViewportContainer
var _viewport: SubViewport
var _camera: Camera3D
var _track: Track3D
var _cars: Array[Car3D] = []
var _player3d: Car3D
var _ghost3d: Car3D
var _crew: Node3D
var _env: Environment
var _sun: DirectionalLight3D
var _rng := RandomNumberGenerator.new()
var _head := Vector3.ZERO
var _buzz := 0.0
## Cockpit calibration in use (see CAL_DEFAULTS); edited live by CameraCalibration (F6).
var cal: Dictionary = {}
var fx: Race3DEffects


static func make(manager: RaceManager) -> Race3D:
	var r := Race3D.new()
	r.race = manager
	return r


func _ready() -> void:
	layer = 1
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.handle_input_locally = false
	_container.add_child(_viewport)
	var world := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.15
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.08
	_env.fog_enabled = true
	world.environment = _env
	_viewport.add_child(world)
	_sun = DirectionalLight3D.new()
	# High and slightly to the side, so cars and the road are lit from above, not from behind.
	_sun.rotation_degrees = Vector3(-62, -28, 0)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 110.0
	_viewport.add_child(_sun)
	_track = Track3D.make(race.track, TrackTheme.of(GameManager.track_id))
	_viewport.add_child(_track)
	for car in race.cars:
		var c := Car3D.make(car)
		_viewport.add_child(c)
		_cars.append(c)
		if car == race.player:
			_player3d = c
	_camera = Camera3D.new()
	_camera.near = 0.05
	_camera.far = 1800.0
	_viewport.add_child(_camera)
	_camera.current = true
	_crew = _make_crew()
	_viewport.add_child(_crew)
	fx = Race3DEffects.new()
	fx.setup(self, race)
	_viewport.add_child(fx)
	_load_cal()
	add_child(CameraCalibration.make(self))
	_apply_weather()
	set_view(int(GameManager.setting("camera_view")))
	_snap()


func _apply_weather() -> void:
	var wet := race.weather
	var night := GameManager.session_night
	var sky := Color("8fc8ea")
	var ambient := Color("b9c7d6")
	var sun := 1.3
	if wet > 0:
		sky = Color("8d99a6") if wet == 1 else Color("6b7581")
		ambient = Color("9aa4ae")
		sun = 0.65 if wet == 1 else 0.45
	if night:
		sky = Color("0d1426")
		ambient = Color("3c4a6e")
		sun = 0.35
	_env.background_color = sky
	_env.ambient_light_color = ambient
	_env.ambient_light_energy = 1.1 if not night else 1.0
	_env.fog_light_color = sky
	_env.fog_density = 0.0016 if wet == 0 else 0.006
	_sun.light_energy = sun
	_sun.light_color = Color("fff1d6") if not night else Color("aab8ff")


## See VIEWS: 0 CHASE ... 5 TOP (2D).
func set_view(index: int) -> void:
	view = posmod(index, VIEWS.size())
	var in_3d := view != TOP
	visible = in_3d
	# The 2D world stays simulated underneath but is not drawn while the 3D view is up.
	race.track_node.visible = not in_3d
	for car in race.cars:
		car.visible = not in_3d
	for child in race.get_children():
		if child is NightLights or child is PitGuide or child is RacingLineAssist:
			child.visible = not in_3d
	if _player3d:
		# Only the cockpit camera swaps the exterior for the interior; no offsets carry over.
		_player3d.set_cockpit(view == COCKPIT and bool(cal.get("cockpit_mesh", true)), bool(GameManager.setting("reduced_halo")))
	_camera.fov = [66.0, 55.0, 64.0, cockpit_fov(), 62.0, 60.0][view]
	_camera.near = float(cal.get("near", 0.04)) if view == COCKPIT else 0.1
	_head = Vector3.ZERO
	_snap()


## Vertical FOV for the cockpit: the player's setting (55-75 degrees).
func cockpit_fov() -> float:
	return lerpf(55.0, 75.0, clampf(float(GameManager.setting("cockpit_fov")), 0.0, 1.0))


func _load_cal() -> void:
	var saved: Dictionary = (GameManager.setting("cockpit_cal") as Dictionary).get(MODEL, {}) if GameManager.setting("cockpit_cal") is Dictionary else {}
	cal = CAL_DEFAULTS.duplicate(true)
	for key: String in saved:
		cal[key] = saved[key]


## Saves the calibration for this car model so it survives a restart.
func save_cal() -> void:
	var all: Dictionary = GameManager.setting("cockpit_cal") if GameManager.setting("cockpit_cal") is Dictionary else {}
	all = all.duplicate(true)
	all[MODEL] = cal.duplicate(true)
	GameManager.set_setting("cockpit_cal", all)
	GameManager.save()


func camera() -> Camera3D:
	return _camera


func player_car() -> Car3D:
	return _player3d


func cycle_view() -> void:
	set_view(view + 1)
	GameManager.set_setting("camera_view", view)
	GameManager.save()


func active() -> bool:
	return visible


func _process(delta: float) -> void:
	if race == null or race.player == null:
		return
	for c in _cars:
		c.sync(delta, _track.height_at_car(c.car) if _track else 0.0)
	_sync_ghost()
	_track.set_lights(race._gantry.lit if race._gantry else 0)
	_sync_crew()
	if visible:
		_update_camera(delta)


func _snap() -> void:
	_update_camera(1.0)


func _update_camera(delta: float) -> void:
	var car := race.player
	var p := car.global_position / PPM
	var pos := Vector3(p.x, 0, p.y)
	var fwd := Vector3(cos(car.rotation), 0, sin(car.rotation))
	var calm := bool(GameManager.setting("reduced_motion"))
	var shake := (race._camera._shake * 0.02 if race._camera else 0.0) * (0.0 if calm else 1.0)
	var jitter := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * minf(shake, 0.12)
	pos.y = _player3d.position.y
	match view:
		0:
			# Smooth position, responsive aim; a touch further back under acceleration.
			var back := 7.5 + car.speed * 0.03 + (0.0 if calm else clampf(car.physics.long_accel * 0.04, -0.4, 0.6))
			var want := _keep_on_track(pos - fwd * back + Vector3(0, 2.9, 0))
			_camera.global_position = _camera.global_position.lerp(want, 1.0 - exp(-7.0 * delta)) + jitter
			_camera.look_at(pos + fwd * 5.0 + Vector3(0, 0.9, 0), Vector3.UP)
			_camera.fov = 66.0 + (0.0 if calm else clampf(car.speed * 0.1, 0.0, 9.0))
		1:
			var want := pos - fwd * 13.0 + Vector3(0, 17.0, 0)
			_camera.global_position = _camera.global_position.lerp(want, 1.0 - exp(-5.0 * delta)) + jitter
			_camera.look_at(pos + fwd * 11.0, Vector3.UP)
		2:
			_film_from(_player3d.tv_pod, -3.0, jitter * 0.5)
		3:
			_cockpit_camera(delta, calm)
		4:
			_film_from(_player3d.nose_cam, -2.0, jitter * 0.3)


## A camera fixed to an anchor on the car, looking along the chassis.
func _film_from(anchor: Marker3D, pitch_deg: float, jitter: Vector3) -> void:
	var t := anchor.global_transform
	var basis := t.basis * Basis(Vector3.UP, -PI / 2.0) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg))
	_camera.global_transform = Transform3D(basis, t.origin + jitter)


## The driver's view: DriverEye plus calibration, a small filtered head offset (braking pushes
## the head forward, corners lean it, kerbs buzz it) and partial horizon stabilisation. The
## camera is set from the chassis every frame - no extra smoothing that would lag the cockpit.
func _cockpit_camera(delta: float, calm: bool) -> void:
	var car := race.player
	var strength := float(cal.get("head", 1.0)) * (0.25 if calm else 1.0)
	var want := Vector3(clampf(car.physics.long_accel * -0.0035, -0.03, 0.03), 0.0, clampf(car.physics.accel_local.y * 0.0025, -0.025, 0.025)) * strength
	_buzz = lerpf(_buzz, 1.0 if car.on_curb and car.speed > 8.0 else 0.0, minf(1.0, 10.0 * delta))
	want.y += sin(Time.get_ticks_msec() * 0.09) * 0.004 * _buzz * strength
	_head = _head.lerp(want, minf(1.0, 12.0 * delta))
	var eye_offset: Array = cal.get("eye", [0.0, 0.0, 0.0])
	var anchor := _player3d.driver_eye
	var local := anchor.position + Vector3(float(eye_offset[0]), float(eye_offset[1]), float(eye_offset[2])) + _head
	var chassis_t := _player3d.chassis.global_transform
	var origin := chassis_t * local
	var basis := chassis_t.basis
	# Partial horizon stabilisation: take out some of the chassis roll, never all of it.
	var keep := 1.0 - clampf(float(cal.get("horizon", 0.35)), 0.0, 1.0)
	var flat := _player3d.global_transform.basis
	basis = flat.slerp(basis, keep) if keep < 1.0 else basis
	basis = basis * Basis(Vector3.UP, -PI / 2.0) * Basis(Vector3.RIGHT, deg_to_rad(float(cal.get("pitch", -4.0)))) * Basis(Vector3.FORWARD, deg_to_rad(float(cal.get("roll", 0.0))))
	_camera.global_transform = Transform3D(basis.orthonormalized(), origin)
	_camera.fov = cockpit_fov()


## Keeps the chase camera inside the barriers so it never films through a wall.
func _keep_on_track(p: Vector3) -> Vector3:
	var t := race.track
	var p2 := Vector2(p.x, p.z) * PPM
	var i := t.nearest_index(p2, race.player.track_index)
	var lateral := t.lateral_offset(p2, i)
	var limit := (t.barrier_right[i] if lateral > 0.0 else t.barrier_left[i]) - 0.8
	if absf(lateral) > limit:
		var fixed := t.points[i] + t.normals[i] * signf(lateral) * limit * PPM + t.tangents[i] * (p2 - t.points[i]).dot(t.tangents[i])
		return Vector3(fixed.x / PPM, p.y, fixed.y / PPM)
	return p


func _sync_ghost() -> void:
	var ghost: Node2D = race.get("_ghost")
	if ghost == null:
		return
	if _ghost3d == null:
		var dummy := race.player
		_ghost3d = Car3D.make(dummy, 0.35)
		_ghost3d.car = null
		_viewport.add_child(_ghost3d)
	_ghost3d.visible = ghost.visible
	if ghost.visible:
		# The 2D ghost is drawn from the rear axle; move to the centre of mass like the cars.
		var rear := ghost.global_position / PPM
		var cg := race.player.physics.stats.cg_x
		var fwd := Vector2(cos(ghost.rotation), sin(ghost.rotation))
		var p := rear + fwd * cg
		_ghost3d.position = Vector3(p.x, 0, p.y)
		_ghost3d.rotation = Vector3(0, -ghost.rotation, 0)


## Six crew members around the car while it is being serviced.
func _make_crew() -> Node3D:
	var kit := MeshKit.new()
	var suit := Color(race.player.body_color)
	var spots := [Vector3(2.9, 0, 1.1), Vector3(2.9, 0, -1.1), Vector3(-0.1, 0, 1.2), Vector3(-0.1, 0, -1.2), Vector3(4.6, 0, 0), Vector3(-1.0, 0, 0)]
	for s: Vector3 in spots:
		kit.box(s + Vector3(0, 0.45, 0), Vector3(0.35, 0.9, 0.45), suit)
		kit.box(s + Vector3(0, 1.05, 0), Vector3(0.3, 0.3, 0.3), Color("f4f6f2"))
		kit.box(s + Vector3(0.12, 1.05, 0), Vector3(0.08, 0.12, 0.26), Color("101418"))
	var crew := MeshInstance3D.new()
	crew.mesh = kit.commit()
	crew.material_override = MeshKit.material()
	var holder := Node3D.new()
	holder.add_child(crew)
	holder.visible = false
	return holder


func _sync_crew() -> void:
	_crew.visible = race.pit_phase == "service"
	if _crew.visible and _player3d:
		var cg := race.player.physics.stats.cg_x
		_crew.global_transform = _player3d.global_transform * Transform3D(Basis.IDENTITY, Vector3(-cg, 0, 0))


## Where a point of the 2D world appears on screen in the current view (for HUD markers).
func to_screen(world: Vector2) -> Vector2:
	var p := world / PPM
	var point := Vector3(p.x, 0.5, p.y)
	if _camera.is_position_behind(point):
		var v := _camera.unproject_position(point)
		return _container.size - v
	return _camera.unproject_position(point)
