class_name Car3D
extends Node3D
## A Formula car in the 3D race: chunky blocks, toy-like colours, but every part an F1 fan
## looks for - wings with endplates, halo, airbox, sidepods, mirrors, suspension arms, number
## boards, a helmet in the cockpit and wheels that spin and steer. Built once per car from its
## livery and mirrored from the 2D simulation every frame. Local +X is forward, +Z is the
## car's right, the origin is the centre of mass (like the 2D body).

const WHEELBASE := 3.0
const FRONT_TRACK := 0.8
const REAR_TRACK := 0.79
const WHEEL_RADIUS := 0.35
const COCKPIT_X := 1.65            # metres ahead of the rear axle
const CARBON := Color("1d2026")
const TYRE := Color("17191d")
const RIM := Color("8d96a3")

var car: VehicleController
var cockpit_point := Vector3.ZERO
var _wheels: Array[Node3D] = []
var _steer: Array[Node3D] = []
var _pivots: Array[Node3D] = []
var _helmet: MeshInstance3D
var _brake_light: MeshInstance3D
var _spin := 0.0
var _compound := ""
var _wheel_material: StandardMaterial3D


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
	var kit := MeshKit.new()
	var floor_y := 0.1
	# Floor and plank.
	kit.box(o + Vector3(1.4, floor_y, 0), Vector3(3.0, 0.05, 1.5), CARBON)
	kit.box(o + Vector3(1.4, floor_y - 0.04, 0), Vector3(2.6, 0.04, 0.3), Color("c79a4a"))
	# Monocoque: a tapering tub from the nose to the gearbox.
	kit.box(o + Vector3(1.6, 0.34, 0), Vector3(2.2, 0.42, 0.62), main)
	kit.box(o + Vector3(2.95, 0.3, 0), Vector3(0.7, 0.3, 0.44), main)
	kit.box(o + Vector3(3.55, 0.25, 0), Vector3(0.6, 0.2, 0.28), main)
	kit.box(o + Vector3(3.92, 0.22, 0), Vector3(0.25, 0.14, 0.2), second)       # nose tip
	kit.box(o + Vector3(0.25, 0.32, 0), Vector3(0.6, 0.34, 0.42), CARBON)       # gearbox
	# Sidepods with their inlets.
	for side: float in [-1.0, 1.0]:
		kit.box(o + Vector3(1.45, 0.28, side * 0.58), Vector3(1.3, 0.34, 0.42), main)
		kit.box(o + Vector3(2.12, 0.32, side * 0.58), Vector3(0.06, 0.2, 0.3), CARBON)
		kit.box(o + Vector3(1.0, 0.22, side * 0.62), Vector3(0.5, 0.18, 0.34), second)  # undercut stripe
		kit.box(o + Vector3(1.55, 0.47, side * 0.62), Vector3(0.7, 0.03, 0.06), second)
		# Mirrors.
		kit.box(o + Vector3(2.15, 0.62, side * 0.42), Vector3(0.08, 0.06, 0.16), main)
		kit.box(o + Vector3(2.2, 0.55, side * 0.38), Vector3(0.03, 0.12, 0.03), CARBON)
	# Engine cover, airbox and shark fin.
	kit.box(o + Vector3(0.95, 0.56, 0), Vector3(1.2, 0.2, 0.36), main)
	kit.box(o + Vector3(1.45, 0.78, 0), Vector3(0.36, 0.3, 0.3), main)
	kit.box(o + Vector3(1.6, 0.8, 0), Vector3(0.04, 0.18, 0.2), CARBON)          # airbox mouth
	kit.box(o + Vector3(0.7, 0.75, 0), Vector3(0.8, 0.2, 0.03), second)
	# Cockpit opening, steering wheel and the halo.
	kit.box(o + Vector3(COCKPIT_X + 0.05, 0.55, 0), Vector3(0.62, 0.06, 0.4), CARBON)
	kit.box(o + Vector3(COCKPIT_X + 0.38, 0.62, 0), Vector3(0.05, 0.12, 0.26), CARBON)
	kit.box(o + Vector3(COCKPIT_X + 0.36, 0.64, 0), Vector3(0.03, 0.05, 0.12), Color("5fe08a"))
	kit.box(o + Vector3(COCKPIT_X + 0.45, 0.82, 0), Vector3(0.04, 0.3, 0.035), CARBON)       # halo pillar
	for side: float in [-1.0, 1.0]:
		kit.box(o + Vector3(COCKPIT_X + 0.05, 0.96, side * 0.22), Vector3(0.8, 0.03, 0.03), CARBON)  # halo hoop
	kit.box(o + Vector3(COCKPIT_X - 0.35, 0.96, 0), Vector3(0.03, 0.03, 0.47), CARBON)
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
	# Rear wing: endplates, main plane, DRS flap, beam wing, pylon.
	for side: float in [-1.0, 1.0]:
		kit.box(o + Vector3(-0.35, 0.72, side * 0.45), Vector3(0.55, 0.62, 0.05), main)
	kit.box(o + Vector3(-0.38, 0.92, 0), Vector3(0.36, 0.05, 0.9), CARBON)
	kit.box(o + Vector3(-0.28, 1.0, 0), Vector3(0.2, 0.04, 0.9), second)
	kit.box(o + Vector3(-0.3, 0.5, 0), Vector3(0.28, 0.04, 0.8), CARBON)
	kit.box(o + Vector3(-0.15, 0.7, 0), Vector3(0.12, 0.4, 0.06), CARBON)
	# Diffuser and the rain light housing.
	kit.box(o + Vector3(-0.25, 0.16, 0), Vector3(0.4, 0.14, 1.2), CARBON)
	# Suspension arms from the tub out to every wheel.
	for wheel: Array in [[WHEELBASE, FRONT_TRACK], [0.0, REAR_TRACK]]:
		var wx: float = wheel[0]
		var wz: float = wheel[1]
		for side: float in [-1.0, 1.0]:
			for dy: float in [0.22, 0.36]:
				var from := o + Vector3(wx, dy, side * 0.28)
				var to := o + Vector3(wx, dy, side * (wz - 0.2))
				kit.box((from + to) * 0.5, Vector3(0.05, 0.03, absf(to.z - from.z)), CARBON)
	var body := MeshInstance3D.new()
	body.mesh = kit.commit()
	body.material_override = MeshKit.material(alpha)
	add_child(body)
	# Helmet (hidden from the cockpit camera).
	var hk := MeshKit.new()
	hk.box(Vector3.ZERO, Vector3(0.3, 0.28, 0.27), second)
	hk.box(Vector3(0.1, 0.02, 0), Vector3(0.12, 0.09, 0.24), Color("101418"))   # visor
	hk.box(Vector3(-0.02, 0.1, 0), Vector3(0.2, 0.06, 0.24), main)
	_helmet = MeshInstance3D.new()
	_helmet.mesh = hk.commit()
	_helmet.material_override = MeshKit.material(alpha)
	_helmet.position = o + Vector3(COCKPIT_X - 0.08, 0.78, 0)
	add_child(_helmet)
	cockpit_point = o + Vector3(COCKPIT_X - 0.15, 0.95, 0)
	# Rain / brake light.
	var lk := MeshKit.new()
	lk.box(Vector3.ZERO, Vector3(0.04, 0.08, 0.14), Color("ff2a2a"))
	_brake_light = MeshInstance3D.new()
	_brake_light.mesh = lk.commit()
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("ff2a2a")
	glow.emission_enabled = true
	glow.emission = Color("ff2a2a")
	glow.emission_energy_multiplier = 2.5
	_brake_light.material_override = glow
	_brake_light.position = o + Vector3(-0.47, 0.28, 0)
	add_child(_brake_light)
	_wheel_material = MeshKit.material(alpha)
	_build_wheels(o)


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


func hide_helmet(hidden: bool) -> void:
	_helmet.visible = not hidden


## Mirrors the 2D car: position, heading, wheel spin, steering, brake light, new tyres.
func sync(delta: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	var p := car.global_position / VehiclePhysicsConfig.PPM
	position = Vector3(p.x, 0.0, p.y)
	rotation = Vector3(0, -car.rotation, 0)
	visible = not car.is_destroyed
	_spin -= car.local_velocity.x * delta / WHEEL_RADIUS
	for w in _wheels:
		w.rotation = Vector3(0, 0, _spin)
	for s in _steer:
		s.rotation = Vector3(0, -car.physics.steer_angle, 0)
	_brake_light.visible = car.input.brake > 0.1 or car.wet
	if car.setup and car.setup.parts.get("tires", "") != _compound:
		var cg := car.physics.stats.cg_x if car.physics.stats else 1.3
		_build_wheels(Vector3(-cg, 0, 0))
