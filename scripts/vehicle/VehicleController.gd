class_name VehicleController
extends RigidBody2D
## The physical car. Owns a VehiclePhysics model and feeds its accelerations into the
## RigidBody2D, which keeps real inertia and handles collisions. Player and AI cars are
## the same class - only where VehicleInput gets its numbers from differs.

signal collided(strength: float)
signal gear_shifted(gear: int)
signal damaged(amount: float, total: float)
signal destroyed

const PPM := VehiclePhysicsConfig.PPM
const SUBSTEPS := 2
const REVERSE_HOLD_TIME := 0.35
## Impacts below this change in speed (m/s) are just rubbing and do no damage.
const DAMAGE_THRESHOLD := 1.6
const DAMAGE_PER_MS := 1.9
## Percent of the tank burned per metre at full throttle with a 100 %-efficiency engine
## (about six laps of Falcon Ridge). Thirsty engines will need a stop in a five-lap race.
const FUEL_PER_METRE := 0.0061

@export var physics_config: VehiclePhysicsConfig = preload("res://data/physics/default_physics.tres")

var setup: CarSetup
var physics := VehiclePhysics.new()
var input := VehicleInput.new()
var track: TrackData
var visual: CarVisual
var skid_marks: SkidMarks
var car_id := 0
var driver_name := "Player"
var body_color := Color("e8eef6")
var accent_color := Color("23272e")
var is_player := false
var controls_enabled := false

# --- state other systems read
var speed := 0.0                       # m/s
var local_velocity := Vector2.ZERO     # m/s, x forward / y right
var track_index := 0
var lateral := 0.0
var progress := 0.0
var surface_front := 0
var surface_rear := 0
var on_curb := false
var off_track := false
## 0 = pristine, 100 = destroyed. Only tracked when `takes_damage` is set.
var damage := 0.0
var takes_damage := false
var is_destroyed := false
## 100 = full tank. Only burns when `uses_fuel` is set (race sessions).
var fuel := 100.0
var uses_fuel := false
## Difficulty scales how much an impact hurts.
var damage_scale := 1.0
## Driving aids (set by RaceManager for the player): target steering, how strongly to blend
## it in, and an automatic brake request.
var assist_steer := 0.0
var assist_steer_weight := 0.0
var assist_brake := 0.0
## Wet track: rear tires throw up spray.
var wet := false

var _teleport_pending := false
var _teleport_transform := Transform2D()
var _reverse_timer := 0.0
var _smoke_front: CPUParticles2D
var _smoke_rear: CPUParticles2D
var _dust: CPUParticles2D
var _engine_audio: Node
var _squeal_audio: AudioStreamPlayer
var _collision_cooldown := 0.0
var _last_velocity := Vector2.ZERO
var _velocity_valid := false
var _damage_smoke: CPUParticles2D
var _spray: CPUParticles2D


func configure(car_setup: CarSetup, track_data: TrackData) -> void:
	setup = car_setup
	track = track_data
	physics.configure(setup, physics_config)
	mass = physics.mass()
	if visual:
		visual.setup = setup
		visual.body_color = body_color
		visual.accent_color = accent_color
		visual.position = Vector2(-physics.stats.cg_x * PPM, 0.0)
		visual.refresh()
	# The body origin is the centre of mass, so the collision shape shifts with the build.
	var collider := get_node_or_null("Collider") as CollisionShape2D
	if collider:
		collider.position = Vector2((1.75 - physics.stats.cg_x) * PPM, 0.0)


func _ready() -> void:
	gravity_scale = 0.0
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	collision_layer = 1
	collision_mask = 3
	var material := PhysicsMaterial.new()
	material.friction = 0.15
	material.bounce = physics_config.collision_bounce
	physics_material_override = material
	if get_node_or_null("Collider") == null:
		var collider := CollisionShape2D.new()
		collider.name = "Collider"
		var capsule := CapsuleShape2D.new()
		capsule.radius = 0.92 * PPM
		capsule.height = 4.7 * PPM
		collider.shape = capsule
		collider.rotation = PI / 2.0
		add_child(collider)
	_build_visuals()
	body_entered.connect(_on_body_entered)
	physics.transmission.gear_changed.connect(_on_gear_changed)
	if setup:
		configure(setup, track)


func _build_visuals() -> void:
	var shadow := Polygon2D.new()
	shadow.name = "Shadow"
	shadow.color = Color(0, 0, 0, 0.28)
	shadow.polygon = PackedVector2Array([Vector2(-22, -9), Vector2(24, -8), Vector2(27, 0), Vector2(24, 8), Vector2(-22, 9)])
	shadow.z_index = -1
	add_child(shadow)
	visual = CarVisual.new()
	visual.name = "Visual"
	add_child(visual)
	_smoke_front = _make_particles(Color(0.92, 0.92, 0.92, 0.5), 18)
	_smoke_rear = _make_particles(Color(0.92, 0.92, 0.92, 0.5), 22)
	_dust = _make_particles(Color(0.62, 0.55, 0.4, 0.55), 16)
	_damage_smoke = _make_particles(Color(0.2, 0.2, 0.22, 0.6), 14)
	_damage_smoke.lifetime = 1.1
	_spray = _make_particles(Color(0.86, 0.9, 0.96, 0.4), 26)
	_spray.lifetime = 0.9
	_engine_audio = AudioManager.make_loop_player("engine", not is_player)
	add_child(_engine_audio)
	if is_player:
		_squeal_audio = AudioManager.make_loop_player("squeal", false) as AudioStreamPlayer
		add_child(_squeal_audio)


func _make_particles(color: Color, amount: int) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = 0.7
	p.local_coords = false
	p.direction = Vector2.LEFT
	p.spread = 40.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 30.0
	p.damping_min = 20.0
	p.damping_max = 40.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.5
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.6))
	p.scale_amount_curve = grow
	p.z_index = 2
	add_child(p)
	return p


func start_audio() -> void:
	if _engine_audio and not _engine_audio.get("playing"):
		_engine_audio.call("play")
	if _squeal_audio and not _squeal_audio.playing:
		_squeal_audio.play()


## Teleports the car (grid placement, reset to track). Applied inside the physics callback.
func place(pos: Vector2, heading: float) -> void:
	_teleport_transform = Transform2D(heading, pos)
	_teleport_pending = true
	global_position = pos
	rotation = heading
	physics.reset()
	input.clear()
	if track:
		track_index = track.nearest_index(pos)
		_update_track_state()


func _physics_process(delta: float) -> void:
	_collision_cooldown = maxf(0.0, _collision_cooldown - delta)
	if is_player and controls_enabled:
		input.update_player(delta)
	if track:
		track_index = track.nearest_index(global_position, track_index)
		_update_track_state()
	_update_effects(delta)


func _update_track_state() -> void:
	lateral = track.lateral_offset(global_position, track_index)
	progress = track.progress_at(global_position, track_index)
	var forward := Vector2.RIGHT.rotated(rotation)
	var stats := physics.stats
	if stats == null:
		return
	var front_pos := global_position + forward * (physics_config.wheelbase - stats.cg_x) * PPM
	var rear_pos := global_position - forward * stats.cg_x * PPM
	surface_front = track.surface_at(track.lateral_offset(front_pos, track_index), track_index)
	surface_rear = track.surface_at(track.lateral_offset(rear_pos, track_index), track_index)
	on_curb = surface_front == VehiclePhysicsConfig.Surface.CURB or surface_rear == VehiclePhysicsConfig.Surface.CURB
	off_track = not track.is_legal(lateral) and not track.in_pit_lane(progress, lateral)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _teleport_pending:
		state.transform = _teleport_transform
		state.linear_velocity = Vector2.ZERO
		state.angular_velocity = 0.0
		_teleport_pending = false
		_velocity_valid = false
		return
	if setup == null or physics.stats == null:
		return
	var steer := input.steer if controls_enabled else 0.0
	var throttle := input.throttle if controls_enabled else 0.0
	var brake := input.brake if controls_enabled else 1.0
	if is_player and controls_enabled:
		if assist_steer_weight > 0.0:
			steer = lerpf(steer, assist_steer, assist_steer_weight)
		if assist_brake > 0.0:
			brake = maxf(brake, assist_brake)
			throttle *= 1.0 - assist_brake
	var velocity := state.linear_velocity / PPM
	# Whatever changed our velocity since the last step was a collision impulse.
	if takes_damage and _velocity_valid and not is_destroyed:
		var impact := (velocity - _last_velocity).length()
		if impact > DAMAGE_THRESHOLD:
			_apply_damage((impact - DAMAGE_THRESHOLD) * DAMAGE_PER_MS)
	var yaw_rate := clampf(state.angular_velocity, -physics_config.max_yaw_rate, physics_config.max_yaw_rate)
	var heading := state.transform.get_rotation()
	var local := velocity.rotated(-heading)

	# --- gearbox requests and automatic reverse selection
	var gearbox := physics.transmission
	if controls_enabled:
		if input.shift_up:
			gearbox.shift_up()
		if input.shift_down:
			gearbox.shift_down(local.x, physics_config.wheel_radius, physics.engine.redline_rpm)
		if gearbox.automatic:
			if gearbox.gear >= 1 and absf(local.x) < 0.6 and brake > 0.3 and throttle < 0.05:
				_reverse_timer += state.step
				if _reverse_timer > REVERSE_HOLD_TIME:
					gearbox.shift_to(-1)
			else:
				_reverse_timer = 0.0
			if gearbox.gear == -1 and throttle > 0.1 and absf(local.x) < 1.5:
				gearbox.shift_to(1)
	input.shift_up = false
	input.shift_down = false
	if gearbox.gear == -1 and gearbox.automatic:
		# In automatic reverse the pedals swap: "brake" backs the car up, "throttle" stops it.
		var swap := throttle
		throttle = brake * 0.6
		brake = swap

	if uses_fuel and controls_enabled:
		var efficiency := setup.part("engine").stat("fuel_efficiency", 1.0) if setup.part("engine") else 1.0
		fuel = maxf(0.0, fuel - FUEL_PER_METRE * throttle * speed * state.step / efficiency)
		if fuel <= 0.0:
			throttle *= 0.15              # fumes: just enough to crawl to the pits
	var h := state.step / SUBSTEPS
	for i in SUBSTEPS:
		local = velocity.rotated(-heading)
		physics.step(h, local.x, local.y, yaw_rate, steer, throttle, brake, surface_front, surface_rear)
		velocity += physics.accel_local.rotated(heading) * h
		yaw_rate += physics.yaw_accel * h
		heading += yaw_rate * h
	yaw_rate = clampf(yaw_rate, -physics_config.max_yaw_rate, physics_config.max_yaw_rate)
	state.linear_velocity = velocity * PPM
	state.angular_velocity = yaw_rate
	local_velocity = velocity.rotated(-heading)
	speed = velocity.length()
	_last_velocity = velocity
	_velocity_valid = true


func _apply_damage(amount: float) -> void:
	damage = minf(100.0, damage + amount)
	damaged.emit(amount, damage)
	if damage >= 100.0:
		is_destroyed = true
		controls_enabled = false
		destroyed.emit()


## Visual + audio for a destroyed car. The session logic lives in RaceManager.
func explode() -> void:
	if visual:
		visual.modulate = Color(0.12, 0.1, 0.1)
	for i in 2:
		var burst := CPUParticles2D.new()
		burst.one_shot = true
		burst.explosiveness = 0.95
		burst.amount = 46 if i == 0 else 28
		burst.lifetime = 1.1 if i == 0 else 1.8
		burst.local_coords = false
		burst.spread = 180.0
		burst.gravity = Vector2.ZERO
		burst.initial_velocity_min = 40.0 if i == 0 else 10.0
		burst.initial_velocity_max = 190.0 if i == 0 else 60.0
		burst.damping_min = 60.0
		burst.damping_max = 120.0
		burst.scale_amount_min = 5.0
		burst.scale_amount_max = 13.0 if i == 0 else 20.0
		var ramp := Gradient.new()
		if i == 0:
			ramp.set_color(0, Color(1.0, 0.9, 0.5))
			ramp.add_point(0.4, Color(1.0, 0.45, 0.1, 0.9))
			ramp.set_color(ramp.get_point_count() - 1, Color(0.3, 0.05, 0.0, 0.0))
		else:
			ramp.set_color(0, Color(0.15, 0.15, 0.15, 0.8))
			ramp.set_color(1, Color(0.1, 0.1, 0.1, 0.0))
		burst.color_ramp = ramp
		burst.z_index = 3
		add_child(burst)
		burst.emitting = true
	if _engine_audio:
		_engine_audio.call("stop")
	if _squeal_audio:
		_squeal_audio.stop()
	AudioManager.play("collision", 4.0, 0.45)
	AudioManager.play("collision", 0.0, 0.8)


func speed_kmh() -> float:
	return speed * 3.6


func _on_gear_changed(gear: int) -> void:
	gear_shifted.emit(gear)
	if is_player:
		AudioManager.play("shift", -8.0, randf_range(0.9, 1.1))


func _on_body_entered(_body: Node) -> void:
	if _collision_cooldown > 0.0:
		return
	_collision_cooldown = 0.25
	var strength := clampf(speed / 40.0, 0.15, 1.0)
	collided.emit(strength)
	if is_player:
		AudioManager.play("collision", lerpf(-16.0, -2.0, strength), randf_range(0.85, 1.15))


func _update_effects(_delta: float) -> void:
	if physics.stats == null:
		return
	var front := physics.front_tire
	var rear := physics.rear_tire
	var threshold := 0.35
	var front_slide := front.sliding if speed > 6.0 else 0.0
	var rear_slide := rear.sliding if speed > 3.0 else 0.0
	var rough := surface_rear >= VehiclePhysicsConfig.Surface.GRASS
	var front_x := (physics_config.wheelbase - physics.stats.cg_x) * PPM
	var rear_x := -physics.stats.cg_x * PPM
	_smoke_front.position = Vector2(front_x, 0)
	_smoke_rear.position = Vector2(rear_x, 0)
	_dust.position = Vector2(rear_x, 0)
	_smoke_front.emitting = front_slide > threshold + 0.25 and surface_front < VehiclePhysicsConfig.Surface.GRASS
	_smoke_rear.emitting = rear_slide > threshold + 0.25 and not rough
	_dust.emitting = rough and speed > 5.0
	_spray.position = Vector2(rear_x, 0)
	_spray.emitting = wet and not rough and speed > 14.0
	if skid_marks:
		var half := 0.8 * PPM
		if front_slide > threshold and surface_front < VehiclePhysicsConfig.Surface.GRASS:
			skid_marks.mark(car_id * 4, to_global(Vector2(front_x, -half)))
			skid_marks.mark(car_id * 4 + 1, to_global(Vector2(front_x, half)))
		if rear_slide > threshold and not rough:
			skid_marks.mark(car_id * 4 + 2, to_global(Vector2(rear_x, -half)))
			skid_marks.mark(car_id * 4 + 3, to_global(Vector2(rear_x, half)))
	# A badly hurt car trails dark smoke from the engine bay.
	_damage_smoke.emitting = damage > 55.0 and not is_destroyed
	_damage_smoke.position = Vector2((0.8 - physics.stats.cg_x) * PPM, 0)
	if visual:
		visual.front_steer = physics.steer_angle
	var shadow := get_node_or_null("Shadow") as Node2D
	if shadow:
		# Keep the shadow offset fixed in world space regardless of the car's heading.
		shadow.position = Vector2(2.5, 3.5).rotated(-rotation) + Vector2((1.6 - physics.stats.cg_x) * PPM, 0)
	# --- audio: pitch follows rpm, volume follows throttle and rpm
	if _engine_audio:
		var rpm_frac := physics.display_rpm / physics.engine.redline_rpm
		_engine_audio.set("pitch_scale", 0.45 + rpm_frac * 1.75)
		var loudness := 0.25 + 0.45 * rpm_frac + 0.3 * physics.engine.throttle
		_engine_audio.set("volume_db", linear_to_db(loudness * (0.55 if is_player else 0.4)))
	if _squeal_audio:
		var slide := clampf(maxf(front_slide, rear_slide) - 0.15, 0.0, 1.0)
		if rough:
			slide = 0.0
		_squeal_audio.volume_db = linear_to_db(maxf(slide * 0.5, 0.0001))
		_squeal_audio.pitch_scale = 0.8 + clampf(speed / 80.0, 0.0, 0.5)
