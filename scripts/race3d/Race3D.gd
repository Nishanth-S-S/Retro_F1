class_name Race3D
extends CanvasLayer
## The race in 3D. The simulation stays the 2D one underneath (same physics, AI and rules);
## this layer mirrors it every frame into a lit 3D scene and films it from one of four views:
##   CHASE    behind and above your car, like a console racer
##   HIGH     a raised camera that reads the track ahead
##   COCKPIT  from your helmet, with the halo and steering wheel in view
##   TOP      the classic top-down 2D view (this layer hides itself)
## CAM on the HUD cycles them; the choice is saved in settings ("camera_view").

const VIEWS: PackedStringArray = ["CHASE", "HIGH", "COCKPIT", "TOP"]
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
	_env.fog_enabled = true
	world.environment = _env
	_viewport.add_child(world)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-52, 35, 0)
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
	_apply_weather()
	set_view(int(GameManager.setting("camera_view")))
	_snap()


func _apply_weather() -> void:
	var wet := race.weather
	var night := GameManager.session_night
	var sky := Color("8fc8ea")
	var ambient := Color("b9c7d6")
	var sun := 1.15
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
	_env.ambient_light_energy = 0.75 if not night else 0.9
	_env.fog_light_color = sky
	_env.fog_density = 0.0016 if wet == 0 else 0.006
	_sun.light_energy = sun
	_sun.light_color = Color("fff1d6") if not night else Color("aab8ff")


## 0 CHASE, 1 HIGH, 2 COCKPIT, 3 TOP (2D).
func set_view(index: int) -> void:
	view = posmod(index, VIEWS.size())
	var in_3d := view != 3
	visible = in_3d
	# The 2D world stays simulated underneath but is not drawn while the 3D view is up.
	race.track_node.visible = not in_3d
	for car in race.cars:
		car.visible = not in_3d
	for child in race.get_children():
		if child is NightLights or child is PitGuide or child is RacingLineAssist:
			child.visible = not in_3d
	if _player3d:
		_player3d.hide_helmet(view == 2)
	_camera.fov = [68.0, 55.0, 82.0, 60.0][view]
	_snap()


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
		c.sync(delta)
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
	var shake := race._camera._shake * 0.02 if race._camera else 0.0
	var jitter := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * shake
	match view:
		0:
			var want := pos - fwd * (7.5 + car.speed * 0.03) + Vector3(0, 2.9, 0)
			_camera.global_position = _camera.global_position.lerp(want, 1.0 - exp(-7.0 * delta)) + jitter
			_camera.look_at(pos + fwd * 5.0 + Vector3(0, 0.9, 0), Vector3.UP)
			_camera.fov = 66.0 + clampf(car.speed * 0.12, 0.0, 12.0)
		1:
			var want := pos - fwd * 13.0 + Vector3(0, 17.0, 0)
			_camera.global_position = _camera.global_position.lerp(want, 1.0 - exp(-5.0 * delta)) + jitter
			_camera.look_at(pos + fwd * 11.0, Vector3.UP)
		2:
			var t := _player3d.global_transform
			var eye := t * _player3d.cockpit_point
			_camera.global_position = eye + jitter * 0.4
			var look_dir := t.basis * Vector3(1, -0.07, 0)
			_camera.look_at(eye + look_dir, Vector3.UP)


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
