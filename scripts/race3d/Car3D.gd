class_name Car3D
extends Node3D
## A Formula car in the 3D race: chunky blocks, toy-like colours, but every part an F1 fan
## looks for - wings with endplates, halo, airbox, sidepods, mirrors, suspension arms, number
## boards, a helmet and wheels that spin and steer. Built once per car from its livery and
## mirrored from the 2D simulation every frame.
##
## Axes: local +X forward, +Y up, +Z the car's right; the origin is the centre of mass (like the
## 2D body). Hierarchy: Car3D (position, yaw) -> Chassis (visual pitch / roll from the car's
## accelerations) -> exterior mesh, helmet, cockpit mesh, DriverEye / TvPod / Nose anchors.
## The cockpit mesh is a separate interior shown only to the cockpit camera, with the exterior
## body hidden for that camera only - every other camera always sees the full car.

const WHEELBASE := 3.0
const FRONT_TRACK := 0.8
const REAR_TRACK := 0.79
const WHEEL_RADIUS := 0.35
const COCKPIT_X := 1.65            # cockpit centre, metres ahead of the rear axle
const RIM_Y := 0.64                # height of the cockpit rim
const CARBON := Color("1d2026")
const CHARCOAL := Color("2a2d33")
const PADDING := Color("3a3e46")
const TYRE := Color("17191d")
const RIM := Color("8d96a3")
## Where the driver's eyes sit, in rear-axle coordinates: inside the cockpit opening, behind
## the wheel, just above the rim - a seated F1 driver looks over the top of the cowl.
const DEFAULT_EYE := Vector3(COCKPIT_X - 0.16, 0.86, 0.0)
const SHIFT_COLORS := [Color("5fe08a"), Color("ff3b30"), Color("4f7bff")]

var car: VehicleController
var chassis: Node3D
## Camera anchors (children of the chassis so they pitch and roll with it).
var driver_eye: Marker3D
var tv_pod: Marker3D
var nose_cam: Marker3D
var _exterior: MeshInstance3D
var _cockpit: Node3D
var _halo_full: MeshInstance3D
var _halo_reduced: MeshInstance3D
var _wheel_pivot: Node3D
var _display: Label3D
var _shift_lights: Array[MeshInstance3D] = []
var _shift_on: Array[StandardMaterial3D] = []
var _light_off: StandardMaterial3D
var _wheels: Array[Node3D] = []
var _steer: Array[Node3D] = []
var _pivots: Array[Node3D] = []
var _helmet: MeshInstance3D
var _brake_light: MeshInstance3D
var _spin := 0.0
var _compound := ""
var _wheel_material: StandardMaterial3D
var _origin := Vector3.ZERO
var _roll := 0.0
var _pitch := 0.0


static func make(vehicle: VehicleController, alpha: float = 1.0) -> Car3D:
	var c := Car3D.new()
	c.car = vehicle
	c._build(alpha)
	return c


func _build(alpha: float) -> void:
	var main := car.body_color
	var second := car.accent_color
	var cg := car.physics.stats.cg_x if car.physics.stats else 1.3
	var o := Vector3(-cg, 0, 0)          # rear-axle coordinates -> centre of mass
	_origin = o
	chassis = Node3D.new()
	chassis.name = "Chassis"
	add_child(chassis)
	var kit := MeshKit.new()
	# Floor and plank.
	kit.box(o + Vector3(1.4, 0.1, 0), Vector3(3.0, 0.05, 1.5), CARBON)
	kit.box(o + Vector3(1.4, 0.06, 0), Vector3(2.6, 0.04, 0.3), Color("c79a4a"))
	# Monocoque: a tapering tub from the nose to the gearbox, open at the cockpit.
	kit.box(o + Vector3(1.0, 0.34, 0), Vector3(1.0, 0.42, 0.62), main)
	kit.box(o + Vector3(COCKPIT_X, 0.28, 0), Vector3(0.7, 0.3, 0.62), main)
	for side: float in [-1.0, 1.0]:
		kit.box(o + Vector3(COCKPIT_X, 0.52, side * 0.28), Vector3(0.7, 0.24, 0.06), main)
	kit.box(o + Vector3(2.35, 0.36, 0), Vector3(0.7, 0.4, 0.56), main)
	kit.box(o + Vector3(2.95, 0.3, 0), Vector3(0.7, 0.3, 0.44), main)
	kit.box(o + Vector3(3.55, 0.25, 0), Vector3(0.6, 0.2, 0.28), main)
	kit.box(o + Vector3(3.92, 0.22, 0), Vector3(0.25, 0.14, 0.2), second)       # nose tip
	kit.box(o + Vector3(0.25, 0.32, 0), Vector3(0.6, 0.34, 0.42), CARBON)       # gearbox
	# Sidepods with their inlets, undercut stripe and mirrors.
	for side: float in [-1.0, 1.0]:
		kit.box(o + Vector3(1.45, 0.28, side * 0.58), Vector3(1.3, 0.34, 0.42), main)
		kit.box(o + Vector3(2.12, 0.32, side * 0.58), Vector3(0.06, 0.2, 0.3), CARBON)
		kit.box(o + Vector3(1.0, 0.22, side * 0.62), Vector3(0.5, 0.18, 0.34), second)
		kit.box(o + Vector3(1.55, 0.47, side * 0.62), Vector3(0.7, 0.03, 0.06), second)
		kit.box(o + Vector3(2.15, 0.62, side * 0.42), Vector3(0.08, 0.06, 0.16), main)
		kit.box(o + Vector3(2.2, 0.55, side * 0.38), Vector3(0.03, 0.12, 0.03), CARBON)
	# Engine cover, airbox and shark fin.
	kit.box(o + Vector3(0.75, 0.56, 0), Vector3(0.9, 0.2, 0.36), main)
	kit.box(o + Vector3(1.2, 0.76, 0), Vector3(0.34, 0.28, 0.3), main)
	kit.box(o + Vector3(1.37, 0.78, 0), Vector3(0.04, 0.16, 0.2), CARBON)
	kit.box(o + Vector3(0.6, 0.75, 0), Vector3(0.7, 0.2, 0.03), second)
	# Halo seen from outside.
	kit.box(o + Vector3(COCKPIT_X + 0.42, 0.78, 0), Vector3(0.04, 0.26, 0.04), CARBON)
	for side: float in [-1.0, 1.0]:
		kit.box(o + Vector3(COCKPIT_X + 0.02, 0.92, side * 0.22), Vector3(0.8, 0.03, 0.03), CARBON)
	kit.box(o + Vector3(COCKPIT_X - 0.38, 0.92, 0), Vector3(0.03, 0.03, 0.47), CARBON)
	# Race number boards.
	for side: float in [-1.0, 1.0]:
		kit.box(o + Vector3(0.9, 0.62, side * 0.19), Vector3(0.34, 0.16, 0.02), Color.WHITE)
	kit.box(o + Vector3(3.2, 0.46, 0), Vector3(0.3, 0.02, 0.2), Color.WHITE)
	# Front wing: main plane, flaps, endplates.
	kit.box(o + Vector3(4.0, 0.12, 0), Vector3(0.45, 0.04, 1.86), CARBON)
	kit.box(o + Vector3(3.9, 0.17, 0), Vector3(0.24, 0.04, 1.7), main)
	kit.box(o + Vector3(3.82, 0.22, 0), Vector3(0.16, 0.03, 1.5), second)
	for side: float in [-1.0, 1.0]:
		kit.box(o + Vector3(4.0, 0.2, side * 0.94), Vector3(0.5, 0.2, 0.04), main)
	# Rear wing: endplates, main plane, DRS flap, beam wing, pylon; diffuser.
	for side: float in [-1.0, 1.0]:
		kit.box(o + Vector3(-0.35, 0.72, side * 0.45), Vector3(0.55, 0.62, 0.05), main)
	kit.box(o + Vector3(-0.38, 0.92, 0), Vector3(0.36, 0.05, 0.9), CARBON)
	kit.box(o + Vector3(-0.28, 1.0, 0), Vector3(0.2, 0.04, 0.9), second)
	kit.box(o + Vector3(-0.3, 0.5, 0), Vector3(0.28, 0.04, 0.8), CARBON)
	kit.box(o + Vector3(-0.15, 0.7, 0), Vector3(0.12, 0.4, 0.06), CARBON)
	kit.box(o + Vector3(-0.25, 0.16, 0), Vector3(0.4, 0.14, 1.2), CARBON)
	_suspension(kit, o)
	_exterior = MeshInstance3D.new()
	_exterior.name = "Exterior"
	_exterior.mesh = kit.commit()
	_exterior.material_override = MeshKit.material(alpha)
	chassis.add_child(_exterior)
	# Helmet (the cockpit camera never sees it).
	var hk := MeshKit.new()
	hk.box(Vector3.ZERO, Vector3(0.3, 0.28, 0.27), second)
	hk.box(Vector3(0.1, 0.02, 0), Vector3(0.12, 0.09, 0.24), Color("101418"))
	hk.box(Vector3(-0.02, 0.1, 0), Vector3(0.2, 0.06, 0.24), main)
	_helmet = MeshInstance3D.new()
	_helmet.mesh = hk.commit()
	_helmet.material_override = MeshKit.material(alpha)
	_helmet.position = o + Vector3(COCKPIT_X - 0.1, 0.76, 0)
	chassis.add_child(_helmet)
	# Camera anchors.
	driver_eye = _anchor("DriverEye", o + DEFAULT_EYE)
	tv_pod = _anchor("TvPod", o + Vector3(1.25, 1.12, 0))
	nose_cam = _anchor("Nose", o + Vector3(3.6, 0.42, 0))
	# Rain / brake light.
	var lk := MeshKit.new()
	lk.box(Vector3.ZERO, Vector3(0.04, 0.08, 0.14), Color("ff2a2a"))
	_brake_light = MeshInstance3D.new()
	_brake_light.mesh = lk.commit()
	_brake_light.material_override = _glow(Color("ff2a2a"), 2.5)
	_brake_light.position = o + Vector3(-0.47, 0.28, 0)
	chassis.add_child(_brake_light)
	_wheel_material = MeshKit.material(alpha)
	_build_wheels(o)


static func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _anchor(anchor_name: String, at: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = anchor_name
	m.position = at
	chassis.add_child(m)
	return m


func _suspension(kit: MeshKit, o: Vector3) -> void:
	for wheel: Array in [[WHEELBASE, FRONT_TRACK], [0.0, REAR_TRACK]]:
		var wx: float = wheel[0]
		var wz: float = wheel[1]
		for side: float in [-1.0, 1.0]:
			for dy: float in [0.22, 0.36]:
				var from := o + Vector3(wx, dy, side * 0.28)
				var to := o + Vector3(wx, dy, side * (wz - 0.2))
				kit.box((from + to) * 0.5, Vector3(0.05, 0.03, absf(to.z - from.z)), CARBON)


## The interior only the cockpit camera sees: rim and padding, a slim cowl and nose running
## away from the driver, the steering wheel with its display and shift lights, gloves on the
## wheel, mirror housings, front suspension and a slender halo (full or reduced).
func _build_cockpit() -> void:
	var o := _origin
	var main := car.body_color
	var cx := COCKPIT_X
	_cockpit = Node3D.new()
	_cockpit.name = "Cockpit"
	_cockpit.visible = false
	chassis.add_child(_cockpit)
	var kit := MeshKit.new()
	for side: float in [-1.0, 1.0]:
		# Cockpit rim and side padding frame the view without walling it off.
		kit.box(o + Vector3(cx - 0.05, RIM_Y, side * 0.3), Vector3(0.75, 0.05, 0.08), CHARCOAL)
		kit.box(o + Vector3(cx - 0.1, RIM_Y - 0.06, side * 0.25), Vector3(0.55, 0.1, 0.05), PADDING)
		# Sidepod shoulders beyond the rim, in the livery.
		kit.box(o + Vector3(cx + 0.1, 0.5, side * 0.58), Vector3(1.0, 0.1, 0.4), main.darkened(0.15))
		# Mirror housings, glass and stalks.
		kit.box(o + Vector3(cx + 0.55, 0.64, side * 0.42), Vector3(0.06, 0.07, 0.17), main)
		kit.box(o + Vector3(cx + 0.52, 0.64, side * 0.42), Vector3(0.01, 0.055, 0.14), Color("9fb7c9"))
		kit.box(o + Vector3(cx + 0.58, 0.57, side * 0.38), Vector3(0.025, 0.12, 0.025), CARBON)
	# Front cowl ahead of the wheel, falling away to a slim nose.
	kit.box(o + Vector3(cx + 0.5, 0.6, 0), Vector3(0.3, 0.06, 0.46), CHARCOAL)
	kit.box(o + Vector3(cx + 0.85, 0.53, 0), Vector3(0.45, 0.06, 0.4), main)
	kit.box(o + Vector3(2.75, 0.44, 0), Vector3(0.7, 0.06, 0.32), main)
	kit.box(o + Vector3(3.35, 0.34, 0), Vector3(0.6, 0.05, 0.24), main)
	kit.box(o + Vector3(3.85, 0.26, 0), Vector3(0.35, 0.05, 0.16), car.accent_color)
	kit.box(o + Vector3(4.0, 0.14, 0), Vector3(0.4, 0.03, 1.8), CARBON)
	for side: float in [-1.0, 1.0]:
		kit.box(o + Vector3(4.0, 0.2, side * 0.92), Vector3(0.45, 0.16, 0.03), main)
	_suspension(kit, o)
	var mat := MeshKit.material()
	mat.metallic_specular = 0.2
	var shell := MeshInstance3D.new()
	shell.name = "CockpitShell"
	shell.mesh = kit.commit()
	shell.material_override = mat
	_cockpit.add_child(shell)
	# Steering wheel on its column, turning with the real steering.
	_wheel_pivot = Node3D.new()
	_wheel_pivot.name = "SteeringWheel"
	_wheel_pivot.position = o + Vector3(cx + 0.36, 0.62, 0)
	_wheel_pivot.scale = Vector3(0.8, 0.8, 0.8)
	_cockpit.add_child(_wheel_pivot)
	var wk := MeshKit.new()
	wk.box(Vector3.ZERO, Vector3(0.04, 0.12, 0.2), CHARCOAL)
	for side: float in [-1.0, 1.0]:
		wk.box(Vector3(0, -0.01, side * 0.13), Vector3(0.05, 0.13, 0.05), CARBON)                # grips
		wk.box(Vector3(-0.025, -0.01, side * 0.135), Vector3(0.045, 0.06, 0.045), Color("b0221d"))  # gloves
		wk.box(Vector3(-0.2, -0.07, side * 0.17), Vector3(0.3, 0.05, 0.055), Color("23262e"))   # forearms
	wk.box(Vector3(-0.022, 0.015, 0), Vector3(0.004, 0.055, 0.1), Color("101418"))
	wk.box(Vector3(0.12, -0.06, 0), Vector3(0.22, 0.04, 0.04), CARBON)                         # column
	var wheel := MeshInstance3D.new()
	wheel.mesh = wk.commit()
	wheel.material_override = mat
	_wheel_pivot.add_child(wheel)
	# Display: gear and speed from the same values the HUD shows.
	_display = Label3D.new()
	_display.pixel_size = 0.0009
	_display.font_size = 40
	_display.outline_size = 0
	_display.modulate = Color("5fe08a")
	_display.position = Vector3(-0.026, 0.015, 0)
	_display.rotation = Vector3(0, -PI / 2.0, 0)
	_wheel_pivot.add_child(_display)
	# Shift lights across the top of the wheel.
	_light_off = StandardMaterial3D.new()
	_light_off.albedo_color = Color("202328")
	for c: Color in SHIFT_COLORS:
		_shift_on.append(_glow(c, 2.0))
	var lk := MeshKit.new()
	lk.box(Vector3.ZERO, Vector3(0.006, 0.01, 0.012), Color.WHITE)
	var lmesh := lk.commit()
	for k in 9:
		var l := MeshInstance3D.new()
		l.mesh = lmesh
		l.material_override = _light_off
		l.position = Vector3(-0.022, 0.05, -0.064 + k * 0.016)
		_wheel_pivot.add_child(l)
		_shift_lights.append(l)
	# Halo: a slim centre pillar leaning back from the cowl and the hoop over the head.
	_halo_full = _halo_mesh(0.035, 1.0)
	_halo_reduced = _halo_mesh(0.016, 0.35)
	_cockpit.add_child(_halo_full)
	_cockpit.add_child(_halo_reduced)


func _halo_mesh(thickness: float, alpha: float) -> MeshInstance3D:
	var o := _origin
	var cx := COCKPIT_X
	var k := MeshKit.new()
	# Centre pillar from the cowl up to the front of the hoop, leaning back like the real one.
	var apex := o + Vector3(cx + 0.42, 0.99, 0)
	k.rod(o + Vector3(cx + 0.56, 0.6, 0), apex, thickness, CARBON)
	# The hoop curves round the driver's head to the mounts behind the cockpit.
	for side: float in [-1.0, 1.0]:
		var path := [apex, o + Vector3(cx + 0.3, 1.01, side * 0.16), o + Vector3(cx + 0.05, 1.01, side * 0.25),
			o + Vector3(cx - 0.2, 0.97, side * 0.28), o + Vector3(cx - 0.38, 0.9, side * 0.26), o + Vector3(cx - 0.42, 0.62, side * 0.26)]
		for n in path.size() - 1:
			k.rod(path[n], path[n + 1], thickness, CARBON)
	var m := MeshInstance3D.new()
	m.name = "Halo"
	m.mesh = k.commit()
	m.material_override = MeshKit.material(alpha)
	return m


func _build_wheels(o: Vector3) -> void:
	for pivot in _pivots:
		pivot.queue_free()
	_pivots.clear()
	_wheels.clear()
	_steer.clear()
	_compound = car.setup.parts.get("tires", "") if car.setup else ""
	var stripe: Color = CarVisual.COMPOUND_COLORS.get(_compound, Color.WHITE)
	var wk := MeshKit.new()
	wk.cylinder_x(Vector3.ZERO, WHEEL_RADIUS, 0.38, TYRE, 10)
	wk.box(Vector3.ZERO, Vector3(0.4, 0.34, 0.34), RIM)
	for side: float in [-0.21, 0.21]:
		wk.box(Vector3(side, 0, 0), Vector3(0.02, 0.5, 0.5), stripe)
	var mesh := wk.commit()
	for info: Array in [[WHEELBASE, FRONT_TRACK, true], [0.0, REAR_TRACK, false]]:
		for side: float in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = o + Vector3(info[0], WHEEL_RADIUS, side * float(info[1]))
			add_child(pivot)
			_pivots.append(pivot)
			var wheel := MeshInstance3D.new()
			wheel.mesh = mesh
			wheel.material_override = _wheel_material
			# The kit builds the cylinder along X; turn it so it rolls about Z (the axle).
			wheel.rotation = Vector3(0, PI / 2.0, 0)
			var spinner := Node3D.new()
			spinner.add_child(wheel)
			pivot.add_child(spinner)
			_wheels.append(spinner)
			if info[2]:
				_steer.append(pivot)


## Where the four tyres touch the road, in world space (skid marks and smoke start here).
func contact_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for pivot in _pivots:
		var p := pivot.global_position
		out.append(Vector3(p.x, position.y, p.z))
	return out


## Cockpit view for this car: the interior instead of the exterior body, no helmet.
func set_cockpit(on: bool, reduced_halo: bool = false) -> void:
	if on and _cockpit == null:
		_build_cockpit()
	_exterior.visible = not on
	_helmet.visible = not on
	if _cockpit:
		_cockpit.visible = on
		_halo_full.visible = not reduced_halo
		_halo_reduced.visible = reduced_halo


## Mirrors the 2D car: position, heading, chassis attitude, wheel spin and steering, brake
## light, new tyres, and the wheel display while the cockpit is in use.
func sync(delta: float, ground_y: float = 0.0) -> void:
	if car == null or not is_instance_valid(car):
		return
	var p := car.global_position / VehiclePhysicsConfig.PPM
	position = Vector3(p.x, ground_y, p.y)
	rotation = Vector3(0, -car.rotation, 0)
	visible = not car.is_destroyed
	# A little roll in corners and pitch under braking / acceleration, filtered.
	var ph := car.physics
	var k := minf(1.0, 8.0 * delta)
	_roll = lerpf(_roll, clampf(ph.accel_local.y * 0.0055, -0.05, 0.05), k)
	_pitch = lerpf(_pitch, clampf(ph.long_accel * 0.0035, -0.035, 0.035), k)
	chassis.rotation = Vector3(-_roll, 0, _pitch)
	_spin -= car.local_velocity.x * delta / WHEEL_RADIUS
	for w in _wheels:
		w.rotation = Vector3(0, 0, _spin)
	for s in _steer:
		s.rotation = Vector3(0, -ph.steer_angle, 0)
	_brake_light.visible = car.input.brake > 0.1 or car.wet
	if car.setup and car.setup.parts.get("tires", "") != _compound:
		_build_wheels(_origin)
	if _cockpit and _cockpit.visible:
		# The wheel turns several times the road-wheel angle, as on the real car.
		_wheel_pivot.rotation = Vector3(ph.steer_angle * 5.0, 0, 0)
		_display.text = "%s  %d" % ["N" if ph.transmission.gear == 0 else str(ph.transmission.gear), int(car.speed_kmh())]
		var rpm := clampf(inverse_lerp(ph.engine.redline_rpm * 0.6, ph.engine.redline_rpm, ph.display_rpm), 0.0, 1.0)
		for i in _shift_lights.size():
			_shift_lights[i].material_override = _shift_on[mini(i / 3, 2)] if rpm * _shift_lights.size() > i else _light_off
