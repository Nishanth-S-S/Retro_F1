class_name WindTunnelUI
extends Control
## Wind tunnel overlay for the garage, and the one place the car is seen in 3D: a blocky
## model built from the setup turns slowly on the tunnel floor while streamlines blow over
## it. Three numbers (drag, downforce, top speed) and one button.
## In career mode runs are rationed by the FIA and each one improves the car's model
## correlation, which is worth car rating (see Career.run_tunnel).

const RUN_TIME := 3.2
const VIEW_SIZE := Vector2(820, 380)

var _config: VehiclePhysicsConfig = preload("res://data/physics/default_physics.tres")
var _stats: CarStats
var _time := 0.0
var _run := -1.0                     # seconds into the current run, -1 = fan idle
var _wind := 0.0                     # 0-1 fan speed
var _viewport: SubViewport
var _camera: Camera3D
var _car: Node3D
var _streams: Array[MeshInstance3D] = []         # moving pulses, one per lane
var _hot: Node3D                                  # tinted segments over the weak areas
var _weakest := ""
var _numbers: Dictionary = {}        # title -> Label
var _status: Label
var _run_button: Button
var _title: Control


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UIKit.panel(UIKit.PANEL, UIKit.LINE)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)
	_title = UIKit.title_bar("WIND TUNNEL", 50.0)
	root.add_child(_title)
	# The 3D view is rendered small and scaled up without smoothing, so it stays chunky.
	var holder := SubViewportContainer.new()
	holder.custom_minimum_size = VIEW_SIZE
	holder.stretch = true
	holder.stretch_shrink = 2
	holder.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(holder)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	holder.add_child(_viewport)
	_build_world()
	var numbers := HBoxContainer.new()
	numbers.add_theme_constant_override("separation", 10)
	root.add_child(numbers)
	for title: String in ["DRAG", "DOWNFORCE", "TOP SPEED"]:
		var cell := UIKit.panel(UIKit.BG_DEEP, UIKit.LINE)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		numbers.add_child(cell)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", -2)
		cell.add_child(box)
		var head := UIKit.label(title, 13, UIKit.HOT)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(head)
		var value := UIKit.label("-", 28)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(value)
		_numbers[title] = value
	_status = UIKit.label("", 16, UIKit.ACCENT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_status)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	root.add_child(buttons)
	_run_button = UIKit.button("RUN TEST", 22, true)
	_run_button.custom_minimum_size = Vector2(0, 62)
	_run_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_run_button.pressed.connect(_start_run)
	buttons.add_child(_run_button)
	var close := UIKit.button("DONE", 22)
	close.custom_minimum_size = Vector2(240, 62)
	close.pressed.connect(func() -> void:
		visible = false
		EventBus.setup_changed.emit())
	buttons.add_child(close)


# ---------------------------------------------------------------- the 3D scene

func _material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, tilt_deg: float = 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = _material(color)
	node.position = pos
	node.rotation_degrees.z = tilt_deg
	parent.add_child(node)
	return node


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("1c2026")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("9aa6b8")
	env.ambient_light_energy = 0.7
	var world := WorldEnvironment.new()
	world.environment = env
	_viewport.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.3
	_viewport.add_child(sun)
	_camera = Camera3D.new()
	_camera.fov = 38.0
	_viewport.add_child(_camera)
	# Tunnel floor with a measuring grid, and the fan ring at the far end.
	var room := Node3D.new()
	_viewport.add_child(room)
	_box(room, Vector3(16, 0.1, 9), Vector3(1.5, -0.05, 0), Color("2b3038"))
	for i in range(-7, 9):
		_box(room, Vector3(0.04, 0.02, 9), Vector3(1.5 + i, 0.01, 0), Color("3d4450"))
	for i in range(-4, 5):
		_box(room, Vector3(16, 0.02, 0.04), Vector3(1.5, 0.01, i), Color("3d4450"))
	for k in 12:
		var angle := TAU * k / 12.0
		_box(room, Vector3(0.3, 0.5, 0.5), Vector3(-6.2, 1.8 + sin(angle) * 1.7, cos(angle) * 1.7), Color("8b95a3"))
	_car = Node3D.new()
	_viewport.add_child(_car)
	# Streamlines: straight lines from nose to tail, each with a bright pulse riding it.
	for y: float in [0.2, 0.45, 0.75, 1.05, 1.4]:
		for z: float in [-1.3, -0.8, -0.4, 0.0, 0.4, 0.8, 1.3]:
			var line := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(12.0, 0.018, 0.018)
			line.mesh = mesh
			line.material_override = _material(Color("2c5f7a"), true)
			line.position = Vector3(1.5, y, z)
			_viewport.add_child(line)
			var pulse := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.6, 0.03, 0.03)
			pulse.mesh = pm
			pulse.material_override = _material(Color("8fe3ff"), true)
			pulse.set_meta("lane", Vector3(randf(), y, z))
			_viewport.add_child(pulse)
			_streams.append(pulse)
	_hot = Node3D.new()
	_viewport.add_child(_hot)


## Where the car is weakest: the aero areas that rate worst get their streamlines tinted
## orange to red. Zones: [name, x from, x to, y max, |z| from, |z| to, severity].
func _weak_zones() -> Array:
	var card := CarRatings.compute(GameManager.setup, _stats)
	var r := {}
	for row: Array in card["ratings"]:
		r[row[0]] = int(row[1])
	var sev := func(rating: int) -> float: return clampf((78.0 - rating) / 38.0, 0.0, 1.0)
	var balance := _stats.balance_index
	var body: Dictionary = CarSetup.BODY_SETS[GameManager.setup.body]
	return [
		["FRONT WING (GRIP)", 3.4, 4.4, 0.55, 0.0, 1.0, sev.call(r["DOWNFORCE"]) * 0.7 + (0.5 if balance < -0.03 else 0.0)],
		["REAR WING (DRAG)", -1.0, 0.1, 1.5, 0.0, 0.8, sev.call(r["DRAG EFFICIENCY"]) + (0.4 if balance > 0.03 else 0.0)],
		["WHEELS (DRAG)", -0.5, 3.5, 0.75, 0.6, 1.1, sev.call(r["DRAG EFFICIENCY"]) * 0.8],
		["FLOOR (DOWNFORCE)", 0.3, 3.2, 0.3, 0.0, 0.7, sev.call(r["DOWNFORCE"]) + sev.call(r["AERODYNAMICS"]) * 0.5 + (GameManager.setup.ride_height - 5) * 0.06],
		["SIDEPODS (DRAG)", 0.7, 2.3, 0.75, 0.35, 0.75, clampf((float(body["drag"]) - 0.95) * 6.0, 0.0, 1.0)],
	]


func _paint_weak_zones() -> void:
	for child in _hot.get_children():
		child.queue_free()
	_weakest = ""
	var worst := 0.15
	for zone: Array in _weak_zones():
		var severity := float(zone[6])
		if severity <= 0.15:
			continue
		if severity > worst:
			worst = severity
			_weakest = str(zone[0])
		var color := Color("ffb347").lerp(Color("ff3b30"), clampf(severity, 0.0, 1.0))
		for y: float in [0.2, 0.45, 0.75, 1.05, 1.4]:
			for z: float in [-1.3, -0.8, -0.4, 0.0, 0.4, 0.8, 1.3]:
				if y > float(zone[3]) or absf(z) < float(zone[4]) or absf(z) > float(zone[5]):
					continue
				var seg := MeshInstance3D.new()
				var mesh := BoxMesh.new()
				mesh.size = Vector3(float(zone[2]) - float(zone[1]), 0.03, 0.03)
				seg.mesh = mesh
				seg.material_override = _material(color, true)
				seg.position = Vector3((float(zone[1]) + float(zone[2])) * 0.5, y, z)
				_hot.add_child(seg)


## Rebuilds the blocky car from the setup: wing angles, wing size, engine size and team
## colours all show. x is forward, y is up, the rear axle sits at the origin.
func _build_car() -> void:
	for child in _car.get_children():
		_car.remove_child(child)
		child.queue_free()
	var setup := GameManager.setup
	var team := Career.my_team() if Career.active() else {"color": "#c8201e", "color2": "#f4f6f2"}
	var body := Color(str(team["color"]))
	var accent := Color(str(team["color2"]))
	var dark := Color("17191d")
	_box(_car, Vector3(3.5, 0.06, 1.3), Vector3(1.45, 0.1, 0), dark)                    # floor
	_box(_car, Vector3(1.9, 0.3, 0.5), Vector3(2.55, 0.32, 0), body)                    # monocoque
	_box(_car, Vector3(0.8, 0.16, 0.3), Vector3(3.75, 0.24, 0), body)                   # nose
	_box(_car, Vector3(0.8, 0.02, 0.1), Vector3(3.75, 0.33, 0), accent)                 # nose stripe
	var pod := {"classic70": 0.24, "turbo80": 0.6}.get(setup.body, 0.42) as float
	for side: float in [-1.0, 1.0]:
		_box(_car, Vector3(1.4, 0.36, pod), Vector3(1.45, 0.3, side * (0.27 + pod * 0.55)), body)      # sidepods
		_box(_car, Vector3(0.5, 0.1, pod), Vector3(1.9, 0.5, side * (0.27 + pod * 0.55)), accent)
		if setup.body == "winglet00":
			_box(_car, Vector3(0.3, 0.25, 0.05), Vector3(1.0, 0.6, side * (0.3 + pod)), accent)
	if setup.body == "classic70":
		_box(_car, Vector3(0.35, 0.55, 0.35), Vector3(1.3, 1.0, 0), accent)               # periscope airbox
	elif setup.body == "streamliner":
		_box(_car, Vector3(0.9, 0.3, 0.4), Vector3(-0.4, 0.4, 0), body)                   # long tail
	elif setup.body == "ground22":
		_box(_car, Vector3(2.4, 0.05, 1.6), Vector3(1.4, 0.08, 0), dark)                   # wide floor
	var engine := setup.part("engine")
	var bulk := clampf((engine.mass if engine else 90.0) / 120.0, 0.7, 1.3)
	_box(_car, Vector3(1.5, 0.42 * bulk, 0.44), Vector3(0.65, 0.34 + 0.21 * bulk, 0), body)     # engine cover
	_box(_car, Vector3(0.45, 0.28, 0.3), Vector3(1.25, 0.82, 0), dark)                  # airbox
	_box(_car, Vector3(0.9, 0.04, 0.06), Vector3(0.6, 0.6 + 0.21 * bulk, 0), accent)    # fin
	_box(_car, Vector3(0.5, 0.12, 0.36), Vector3(1.85, 0.5, 0), dark)                   # cockpit
	_box(_car, Vector3(0.24, 0.24, 0.24), Vector3(1.72, 0.62, 0), accent)               # helmet
	# Wheels: chunky blocks with a coloured compound band.
	var band: Color = CarVisual.COMPOUND_COLORS.get(setup.parts.get("tires", ""), Color.WHITE)
	for axle: Array in [[3.0, 0.34, 0.78], [0.0, 0.44, 0.76]]:
		for side: float in [-1.0, 1.0]:
			var centre := Vector3(axle[0], 0.33, side * (float(axle[2]) + float(axle[1]) * 0.5 - 0.17))
			_box(_car, Vector3(0.66, 0.66, axle[1]), centre, dark)
			_box(_car, Vector3(0.5, 0.5, float(axle[1]) + 0.02), centre, Color("2b2e34"))
			_box(_car, Vector3(0.3, 0.3, float(axle[1]) + 0.04), centre, band)
			_box(_car, Vector3(0.06, 0.06, 0.6), Vector3(axle[0], 0.33, side * 0.45), Color("596270"))   # suspension arm
	# Wings: one plane per element, tilted by the wing angle.
	for info: Array in [["front_wing", 3.95, 0.14, 1.9, setup.front_wing_angle, 0.2], ["rear_wing", -0.5, 0.95, 1.4, setup.rear_wing_angle, 0.55]]:
		var wing := setup.part(info[0])
		if wing == null:
			continue
		var elements := clampi(int(round(wing.stat("downforce_coefficient", 0.8) / 0.42)), 1, 4)
		var tilt := -(4.0 + float(info[4]) * 3.0)
		for e in elements:
			_box(_car, Vector3(0.3, 0.035, info[3]), Vector3(float(info[1]) - e * 0.16, float(info[2]) + e * 0.09, 0), accent if e % 2 == 0 else dark, tilt)
		for side: float in [-1.0, 1.0]:
			_box(_car, Vector3(0.65, float(info[5]) + elements * 0.08, 0.04), Vector3(float(info[1]) - 0.1, float(info[2]) + elements * 0.04, side * float(info[3]) * 0.5), body)
		if info[0] == "rear_wing":
			for side: float in [-1.0, 1.0]:
				_box(_car, Vector3(0.08, 0.5, 0.05), Vector3(-0.4, 0.7, side * 0.18), dark)


func open() -> void:
	_stats = CarStats.compute(GameManager.setup, _config)
	_run = -1.0
	_wind = 0.0
	_build_car()
	_paint_weak_zones()
	_title.set_meta("title", "WIND TUNNEL  -  %s" % (str(Career.active_car()["name"]) if Career.active() else "TEST CAR"))
	_title.queue_redraw()
	_refresh("")
	visible = true


func _force(area: float) -> float:
	return 0.5 * _config.air_density * 55.56 * 55.56 * area


func _refresh(note: String) -> void:
	(_numbers["DRAG"] as Label).text = "%d N" % int(_force(_stats.drag_area))
	(_numbers["DOWNFORCE"] as Label).text = "%d N" % int(_force(_stats.front_downforce_area + _stats.rear_downforce_area))
	(_numbers["TOP SPEED"] as Label).text = "%d KM/H" % int(_stats.top_speed * 3.6)
	_run_button.text = "RUN TEST"
	_run_button.disabled = _run >= 0.0
	if Career.active():
		var car := Career.active_car()
		_status.text = "CAR KNOWLEDGE %d%%   ·   %d OF %d RUNS LEFT THIS WEEK" % [int(float(car["tunnel"]) * 100.0), Career.tunnel_runs_left(), Career.tunnel_allowance()]
		if float(car["tunnel"]) >= 1.0:
			_run_button.text = "NOTHING LEFT TO LEARN"
			_run_button.disabled = true
		elif Career.tunnel_runs_left() <= 0:
			_run_button.text = "NO RUNS LEFT THIS WEEK"
			_run_button.disabled = true
	else:
		_status.text = "MEASURED AT 200 KM/H"
	if _weakest != "":
		_status.text += "   ·   WEAKEST: %s" % _weakest
	if note != "":
		_status.text = note


func _start_run() -> void:
	if not BuildValidator.is_ready(GameManager.setup):
		_status.text = "THE CAR IS MISSING PARTS"
		return
	_run = 0.0
	_run_button.disabled = true
	AudioManager.play("go", -10.0, 0.6)


func _finish_run() -> void:
	_run = -1.0
	var note := ""
	if Career.active():
		var outcome := Career.run_tunnel(str(Career.active_car()["id"]))
		note = str(outcome["error"]).to_upper() if outcome.has("error") else "TEST DONE   ·   CAR RATING +%.2f" % (float(outcome["gain"]) * Career.TUNNEL_BONUS)
	_refresh(note)
	AudioManager.play("finish", -10.0)


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	if _run >= 0.0:
		_run += delta
		_wind = clampf(minf(_run / 1.0, (RUN_TIME - _run) / 0.7), 0.0, 1.0)      # spin up, hold, spin down
		if _run >= RUN_TIME:
			_finish_run()
	else:
		_wind = lerpf(_wind, 0.15, minf(1.0, 2.0 * delta))
	# The camera circles the car.
	var angle := _time * 0.35
	_camera.position = Vector3(1.6 + cos(angle) * 5.9, 2.2, sin(angle) * 5.9)
	_camera.look_at(Vector3(1.6, 0.45, 0))
	# Pulses run straight from the nose (+x) past the tail; faster with the fan.
	for pulse in _streams:
		var lane: Vector3 = pulse.get_meta("lane")
		var t := fposmod(lane.x - _time * (0.05 + 0.6 * _wind), 1.0)
		pulse.position = Vector3(lerpf(-4.5, 7.5, t), lane.y, lane.z)
		pulse.scale.x = 0.6 + 2.0 * _wind
