class_name Race3DEffects
extends Node3D
## Tyre effects for the 3D race, driven by the simulation's tyre state:
##   skid marks  dark rubber laid where a tyre locks, spins or slides (one instanced mesh,
##               a ring buffer of marks, so they stay cheap and fade by being overwritten)
##   tyre smoke  pale puffs from a locked, spinning or sliding tyre
##   rain spray  a mist trail behind every car on a wet track
## Purely visual: nothing here feeds back into physics.

const MAX_MARKS := 3600
const MARK_STEP := 0.45            # metres between marks from one tyre
const SPRAY_SPEED := 14.0          # m/s before a wet car throws spray

var race3d: Race3D
var race: RaceManager
var _marks: MultiMesh
var _next := 0
var _last := {}                     # "car:wheel" -> Vector3 of the last mark
var _smoke := {}                    # Car3D -> CPUParticles3D
var _spray := {}                    # Car3D -> CPUParticles3D


func setup(owner_3d: Race3D, manager: RaceManager) -> void:
	race3d = owner_3d
	race = manager


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.62, 0.26)
	quad.orientation = PlaneMesh.FACE_Y
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.06, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	_marks = MultiMesh.new()
	_marks.transform_format = MultiMesh.TRANSFORM_3D
	_marks.mesh = quad
	_marks.instance_count = MAX_MARKS
	_marks.visible_instance_count = 0
	var holder := MultiMeshInstance3D.new()
	holder.multimesh = _marks
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(holder)


func _process(_delta: float) -> void:
	if race3d == null:
		return
	var cam := race3d.camera()
	for c: Car3D in race3d._cars:
		if c.car == null or not is_instance_valid(c.car):
			continue
		var car := c.car
		var near := cam.global_position.distance_to(c.global_position) < 140.0
		var ph := car.physics
		var points := c.contact_points()
		# Wheel order from Car3D: front-left, front-right, rear-left, rear-right.
		var tyres := [ph.front_tire, ph.front_tire, ph.rear_tire, ph.rear_tire]
		var smoking := false
		for w in points.size():
			var tire: TireModel = tyres[w]
			var skidding: bool = car.speed > 3.0 and (tire.locked or tire.spinning or tire.sliding > 0.45) and car.surface_rear < VehiclePhysicsConfig.Surface.GRASS
			var key := "%d:%d" % [c.get_instance_id(), w]
			if skidding:
				smoking = smoking or tire.locked or tire.spinning or tire.sliding > 0.8
				var p: Vector3 = points[w]
				var last: Vector3 = _last.get(key, Vector3.INF)
				if last == Vector3.INF or last.distance_to(p) > MARK_STEP:
					if last != Vector3.INF and last.distance_to(p) < 3.0:
						_add_mark(last, p)
					_last[key] = p
			else:
				_last.erase(key)
		_puff(c, smoking and near)
		_mist(c, car.wet and car.speed > SPRAY_SPEED and near)


func _add_mark(a: Vector3, b: Vector3) -> void:
	var dir := b - a
	dir.y = 0.0
	var length := dir.length()
	if length < 0.05:
		return
	var yaw := atan2(-dir.z, dir.x)
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3(length / 0.62 + 0.15, 1.0, 1.0))
	var at := (a + b) * 0.5
	at.y += 0.015
	_marks.set_instance_transform(_next, Transform3D(basis, at))
	_next = (_next + 1) % MAX_MARKS
	_marks.visible_instance_count = mini(_marks.visible_instance_count + 1, MAX_MARKS)


func _puff(c: Car3D, on: bool) -> void:
	var p: CPUParticles3D = _smoke.get(c)
	if p == null:
		if not on:
			return
		p = _emitter(Color(0.86, 0.87, 0.89, 0.55), 26, 1.3, 0.7, Vector3(0, 1.4, 0), 1.6)
		p.position = c._origin + Vector3(0.0, 0.25, 0.0)
		c.add_child(p)
		_smoke[c] = p
	p.emitting = on


func _mist(c: Car3D, on: bool) -> void:
	var p: CPUParticles3D = _spray.get(c)
	if p == null:
		if not on:
			return
		p = _emitter(Color(0.9, 0.93, 0.97, 0.35), 44, 0.7, 1.0, Vector3(0, 0.5, 0), 2.4)
		p.position = c._origin + Vector3(-0.6, 0.35, 0.0)
		p.direction = Vector3(-1, 0.3, 0)
		p.spread = 25.0
		p.initial_velocity_min = 3.0
		p.initial_velocity_max = 6.0
		c.add_child(p)
		_spray[c] = p
	p.emitting = on


func _emitter(color: Color, amount: int, lifetime: float, size: float, gravity: Vector3, grow: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.emitting = false
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	p.mesh = quad
	p.gravity = gravity
	p.spread = 40.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, grow))
	p.scale_amount_curve = curve
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = fade
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
