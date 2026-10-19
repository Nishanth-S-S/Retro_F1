class_name CameraCalibration
extends CanvasLayer
## Developer panel for the cockpit camera (F6 in a race). Edits the DriverEye offset, pitch,
## roll, FOV, near plane, head-motion strength, horizon stabilisation, cockpit-mesh and halo
## treatment live, shows the car's local axes and the camera values, and saves per car model.
## While it is open the eye position and the camera frustum are drawn in the 3D scene, so they
## can be checked from the chase view.

var race3d: Race3D
var _panel: PanelContainer
var _info: Label
var _marker: MeshInstance3D
var _lines: ImmediateMesh


static func make(owner_3d: Race3D) -> CameraCalibration:
	var c := CameraCalibration.new()
	c.race3d = owner_3d
	return c


func _ready() -> void:
	layer = 30
	visible = false
	_panel = UIKit.panel(Color(0, 0, 0, 0.82), UIKit.LINE)
	_panel.position = Vector2(12, 90)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_panel.add_child(box)
	box.add_child(UIKit.label("COCKPIT CAMERA CALIBRATION  (F6)", 13, UIKit.WARM))
	var cal := race3d.cal
	var eye: Array = cal["eye"]
	_slider(box, "EYE FORWARD", -0.3, 0.3, float(eye[0]), func(v: float) -> void: race3d.cal["eye"][0] = v)
	_slider(box, "EYE HEIGHT", -0.2, 0.25, float(eye[1]), func(v: float) -> void: race3d.cal["eye"][1] = v)
	_slider(box, "EYE SIDE", -0.2, 0.2, float(eye[2]), func(v: float) -> void: race3d.cal["eye"][2] = v)
	_slider(box, "PITCH DEG", -15.0, 10.0, float(cal["pitch"]), func(v: float) -> void: race3d.cal["pitch"] = v)
	_slider(box, "ROLL DEG", -5.0, 5.0, float(cal["roll"]), func(v: float) -> void: race3d.cal["roll"] = v)
	_slider(box, "FOV (VERTICAL)", 55.0, 75.0, race3d.cockpit_fov(), func(v: float) -> void: GameManager.set_setting("cockpit_fov", inverse_lerp(55.0, 75.0, v)))
	_slider(box, "NEAR PLANE M", 0.02, 0.2, float(cal["near"]), func(v: float) -> void:
		race3d.cal["near"] = v
		race3d.camera().near = v)
	_slider(box, "HEAD MOTION", 0.0, 2.0, float(cal["head"]), func(v: float) -> void: race3d.cal["head"] = v)
	_slider(box, "HORIZON STABILISE", 0.0, 1.0, float(cal["horizon"]), func(v: float) -> void: race3d.cal["horizon"] = v)
	_toggle(box, "COCKPIT MESH", bool(cal["cockpit_mesh"]), func(on: bool) -> void:
		race3d.cal["cockpit_mesh"] = on
		race3d.set_view(race3d.view))
	_toggle(box, "REDUCED HALO", bool(GameManager.setting("reduced_halo")), func(on: bool) -> void:
		GameManager.set_setting("reduced_halo", on)
		race3d.set_view(race3d.view))
	_info = UIKit.label("", 11, Color("5fe08a"))
	box.add_child(_info)
	var row := HBoxContainer.new()
	box.add_child(row)
	var save := UIKit.button("SAVE FOR THIS CAR", 12, true)
	save.pressed.connect(func() -> void: race3d.save_cal())
	row.add_child(save)
	var cockpit := UIKit.button("COCKPIT VIEW", 12)
	cockpit.pressed.connect(func() -> void: race3d.set_view(Race3D.COCKPIT))
	row.add_child(cockpit)
	var chase := UIKit.button("CHASE VIEW", 12)
	chase.pressed.connect(func() -> void: race3d.set_view(0))
	row.add_child(chase)
	# Eye marker and frustum preview in the 3D scene.
	var sphere := SphereMesh.new()
	sphere.radius = 0.03
	sphere.height = 0.06
	_marker = MeshInstance3D.new()
	_marker.mesh = sphere
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("ff3bd5")
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	_marker.material_override = m
	_lines = ImmediateMesh.new()
	var frustum := MeshInstance3D.new()
	frustum.mesh = _lines
	frustum.material_override = m
	_marker.add_child(frustum)
	race3d._viewport.add_child(_marker)
	_marker.visible = false


func _slider(parent: Control, text: String, lo: float, hi: float, value: float, apply: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := UIKit.label(text, 11, Color.WHITE)
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 200.0
	s.value = value
	s.custom_minimum_size = Vector2(200, 22)
	s.focus_mode = Control.FOCUS_NONE
	var v := UIKit.label("%.3f" % value, 11, UIKit.TEXT_DIM)
	v.custom_minimum_size = Vector2(56, 0)
	s.value_changed.connect(func(x: float) -> void:
		apply.call(x)
		v.text = "%.3f" % x)
	row.add_child(s)
	row.add_child(v)


func _toggle(parent: Control, text: String, on: bool, apply: Callable) -> void:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 11)
	c.toggled.connect(apply)
	parent.add_child(c)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F6:
		visible = not visible
		_marker.visible = visible


func _process(_delta: float) -> void:
	if not visible:
		return
	var car := race3d.player_car()
	if car == null:
		return
	var eye: Array = race3d.cal["eye"]
	var local := car.driver_eye.position + Vector3(float(eye[0]), float(eye[1]), float(eye[2]))
	var world := car.chassis.global_transform * local
	_marker.global_position = world
	_marker.visible = race3d.view != Race3D.COCKPIT
	# Frustum preview: four rays along the cockpit camera's corners.
	_lines.clear_surfaces()
	_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	var half_v := deg_to_rad(race3d.cockpit_fov() * 0.5)
	var aspect := race3d._container.size.x / maxf(race3d._container.size.y, 1.0)
	var half_h := atan(tan(half_v) * aspect)
	var pitch := deg_to_rad(float(race3d.cal["pitch"]))
	var basis := car.chassis.global_transform.basis
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var dir := Vector3(1.0, tan(half_v) * sy + tan(pitch), tan(half_h) * sx).normalized()
			_lines.surface_add_vertex(Vector3.ZERO)
			_lines.surface_add_vertex(_marker.global_transform.basis.inverse() * (basis * dir) * 3.0)
	_lines.surface_end()
	var cam := race3d.camera()
	_info.text = "LOCAL AXES: +X FORWARD  +Y UP  +Z RIGHT\\nEYE (CHASSIS) %.2f, %.2f, %.2f\\nVIEW %s  FOV %.1f  NEAR %.3f" % [local.x, local.y, local.z, Race3D.VIEWS[race3d.view], cam.fov, cam.near]
