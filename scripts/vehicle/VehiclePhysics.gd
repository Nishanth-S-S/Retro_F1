class_name VehiclePhysics
extends RefCounted
## Custom top-down single-track ("bicycle") vehicle model.
##
## Each axle is treated as one equivalent tire. Every step we work out the load on each
## axle (static weight + longitudinal transfer + downforce), the slip angle of each axle,
## and the longitudinal force the driver is asking for. Lateral and longitudinal demand
## then share one traction circle per axle. Understeer, oversteer, wheelspin, lockups and
## trail braking are not scripted anywhere: they fall out of that force allocation.
##
## Frame convention: +x forward, +y to the driver's right, positive yaw = clockwise on screen.

const REFERENCE_MU := 1.5

var config: VehiclePhysicsConfig
var stats: CarStats
var engine := EngineModel.new()
var transmission := TransmissionModel.new()
var aero := AeroModel.new()
var brakes := BrakeModel.new()
var front_tire := TireModel.new()
var rear_tire := TireModel.new()

var tc_level := 1
var abs_level := 1
## 0 = off, 1 = on. Helps catch slides without steering the car for the driver.
var stability_assist := 0.0
## Multiplies all tire grip: wet weather lowers it, the difficulty grip aid raises it.
var grip_scale := 1.0
var _rear_slide := 0.0

# --- outputs of the latest step (read by controller, HUD, telemetry, debug overlay)
var accel_local := Vector2.ZERO
var yaw_accel := 0.0
var steer_angle := 0.0
var long_accel := 0.0
var front_load := 0.0
var rear_load := 0.0
var front_limit := 0.0
var rear_limit := 0.0
var front_force := Vector2.ZERO      # x = longitudinal, y = lateral (tire frame)
var rear_force := Vector2.ZERO
var display_rpm := 0.0
var tc_active := false
var abs_active := false
var understeer := false
var oversteer := false
var peak_slip_angle := 0.14

var _mass := 700.0
var _inertia := 1000.0
var _a := 1.7     # CG -> front axle
var _b := 1.3     # CG -> rear axle
var _rpm_flare := 0.0


func configure(setup: CarSetup, physics_config: VehiclePhysicsConfig) -> void:
	config = physics_config
	stats = CarStats.compute(setup, config)
	_mass = stats.mass
	_inertia = _mass * config.yaw_gyration_radius * config.yaw_gyration_radius
	_b = stats.cg_x
	_a = config.wheelbase - _b
	if setup.part("engine"):
		engine.configure(setup.part("engine"))
	if setup.part("gearbox"):
		transmission.configure(setup.part("gearbox"))
	if setup.part("brakes"):
		brakes.configure(setup.part("brakes"), setup.brake_bias)
	if setup.part("tires"):
		front_tire.configure(setup.part("tires"))
		rear_tire.configure(setup.part("tires"))
	aero.configure(stats, config)
	reset()


func reset() -> void:
	engine.reset()
	transmission.reset()
	steer_angle = 0.0
	long_accel = 0.0
	accel_local = Vector2.ZERO
	yaw_accel = 0.0
	_rpm_flare = 0.0
	display_rpm = engine.idle_rpm


func reset_wear_and_heat() -> void:
	front_tire.reset()
	rear_tire.reset()
	brakes.reset()
	engine.temperature = EngineModel.AMBIENT_TEMP


func mass() -> float:
	return _mass


func step(delta: float, vx: float, vy: float, yaw_rate: float, steer_input: float, throttle_input: float, brake_input: float, surface_front: int, surface_rear: int) -> void:
	var c := config
	var speed := sqrt(vx * vx + vy * vy)
	var dir := 1.0 if vx >= 0.0 else -1.0
	# Forces that oppose motion fade out near standstill so the car settles instead of jittering.
	var rest_scale := clampf(absf(vx) / 1.2, 0.0, 1.0)

	# ---- steering: input requests a front wheel angle; lock shrinks with speed
	var steer_target := steer_input * c.max_steer_angle(vx)
	steer_angle = move_toward(steer_angle, steer_target, c.steering_rate * stats.front_response * delta)

	# ---- drivetrain
	transmission.update(delta, vx, c.wheel_radius, engine.redline_rpm, throttle_input)
	var wheel_rpm := transmission.rpm_at(vx, c.wheel_radius)
	var launch_rpm := lerpf(engine.idle_rpm, engine.redline_rpm * 0.55, engine.throttle)
	var clutch_slipping := wheel_rpm < launch_rpm
	engine.rpm = maxf(wheel_rpm, launch_rpm)
	engine.update(delta, 0.0 if transmission.is_shifting() else throttle_input, speed)
	var engine_torque := engine.torque()
	if clutch_slipping:
		engine_torque = maxf(engine_torque, 0.0)
	var drive_force := engine_torque * transmission.total_ratio() * transmission.efficiency / c.wheel_radius
	if transmission.is_shifting():
		drive_force = 0.0
	# Stability assist trims power while the rear is stepping out (uses last step's slide).
	drive_force *= 1.0 - config.stability_torque_cut * stability_assist * _rear_slide

	# ---- axle loads: static + longitudinal transfer + downforce
	aero.update(vx)
	var weight := _mass * VehiclePhysicsConfig.GRAVITY
	# weight_transfer = mass * longitudinal_acceleration * cg_height / wheelbase
	var transfer := _mass * long_accel * c.cg_height / c.wheelbase * c.weight_transfer_scale
	front_load = maxf(weight * stats.front_weight - transfer + aero.front_downforce, 150.0)
	rear_load = maxf(weight * (1.0 - stats.front_weight) + transfer + aero.rear_downforce, 150.0)

	# ---- grip budget per axle
	front_limit = front_tire.grip_coefficient() * c.tire_grip_multiplier * stats.front_mech_grip * c.load_factor(front_load, c.front_reference_load) * front_load * _surface_grip(surface_front, stats.front_curb)
	rear_limit = rear_tire.grip_coefficient() * c.tire_grip_multiplier * stats.rear_mech_grip * c.rear_grip_bias * c.load_factor(rear_load, c.rear_reference_load) * rear_load * _surface_grip(surface_rear, stats.rear_curb)

	# ---- slip angles. The velocity floor keeps atan2 well-behaved at low speed, and scaling
	# the steer term by the same ratio makes the model converge on plain kinematic steering
	# (yaw rate = v * steer / wheelbase) as the car slows down.
	var v_floor := maxf(absf(vx), c.low_speed_floor)
	var steer_term := steer_angle * dir * clampf(absf(vx) / c.low_speed_floor, 0.0, 1.0)
	var alpha_f := atan2(vy + _a * yaw_rate, v_floor) - steer_term
	var alpha_r := atan2(vy - _b * yaw_rate, v_floor)
	front_tire.slip_angle = alpha_f
	rear_tire.slip_angle = alpha_r

	# ---- lateral demand: saturating tanh curve gives a progressive breakaway
	var stiff_f := c.cornering_stiffness * sqrt(stats.front_response) * c.surface_steering[surface_front] / REFERENCE_MU
	var stiff_r := c.cornering_stiffness * sqrt(stats.rear_response) / REFERENCE_MU
	peak_slip_angle = 2.0 * REFERENCE_MU / c.cornering_stiffness
	var slide_f := clampf((absf(alpha_f) - peak_slip_angle) / 0.22, 0.0, 1.0)
	var slide_r := clampf((absf(alpha_r) - peak_slip_angle) / 0.22, 0.0, 1.0)
	front_limit *= 1.0 - c.slide_grip_falloff * slide_f
	rear_limit *= 1.0 - c.slide_grip_falloff * slide_r
	var fy_f := -front_limit * tanh(stiff_f * alpha_f)
	var fy_r := -rear_limit * tanh(stiff_r * alpha_r)

	# ---- longitudinal demand
	var brake_f := brakes.front_force(brake_input) * rest_scale
	var brake_r := brakes.rear_force(brake_input) * rest_scale
	var avail_f := sqrt(maxf(front_limit * front_limit - fy_f * fy_f, front_limit * front_limit * 0.09))
	var avail_r := sqrt(maxf(rear_limit * rear_limit - fy_r * fy_r, rear_limit * rear_limit * 0.09))
	abs_active = false
	tc_active = false
	if abs_level > 0 and brake_input > 0.0:
		# ABS holds each axle slightly below the tire's limit: it cannot lock, but it also
		# never finds the last few percent a careful foot can.
		var cap_f := front_limit * c.abs_levels[abs_level]
		var cap_r := rear_limit * c.abs_levels[abs_level]
		if brake_f > cap_f:
			brake_f = cap_f
			abs_active = speed > 3.0
		if brake_r > cap_r:
			brake_r = cap_r
			abs_active = speed > 3.0
	if tc_level > 0 and absf(drive_force) > 0.0 and brake_input < 0.05:
		var cap := avail_r * c.tc_levels[tc_level]
		if absf(drive_force) > cap and drive_force * transmission.total_ratio() > 0.0:
			drive_force = signf(drive_force) * cap
			tc_active = speed > 2.0
	var fx_f_req := -dir * brake_f
	var fx_r_req := drive_force - dir * brake_r

	# ---- traction circle
	front_force = _combine(fx_f_req, fy_f, front_limit, avail_f, front_tire, false, slide_f, speed)
	rear_force = _combine(fx_r_req, fy_r, rear_limit, avail_r, rear_tire, drive_force * dir > 0.0, slide_r, speed)

	# ---- sum forces in the body frame
	var cs := cos(steer_angle)
	var sn := sin(steer_angle)
	var rolling := front_tire.rolling_resistance * (front_load * c.surface_rolling[surface_front] + rear_load * c.surface_rolling[surface_rear])
	var front_body_x := front_force.x * cs - front_force.y * sn
	var front_body_y := front_force.y * cs + front_force.x * sn
	var fx := front_body_x + rear_force.x - dir * (aero.drag + rolling) * rest_scale
	var fy := front_body_y + rear_force.y
	var yaw_torque := _a * front_body_y - _b * rear_force.y - yaw_rate * c.yaw_damping * (1.0 + c.stability_yaw_gain * stability_assist * slide_r)
	_rear_slide = slide_r
	accel_local = Vector2(fx / _mass, fy / _mass)
	yaw_accel = yaw_torque / _inertia
	var transfer_rate := c.weight_transfer_rate * (stats.front_response + stats.rear_response) * 0.5
	long_accel = lerpf(long_accel, accel_local.x, minf(1.0, transfer_rate * delta))

	# ---- thermal state, wear and driver-facing flags
	brakes.update(delta, (absf(front_force.x) + (absf(rear_force.x) if rear_force.x * dir < 0.0 else 0.0)) * absf(vx) * (1.0 if brake_input > 0.02 else 0.0), speed)
	front_tire.update(delta, speed, c.surface_grip[surface_front])
	rear_tire.update(delta, speed, c.surface_grip[surface_rear])
	understeer = speed > 12.0 and absf(steer_input) > 0.25 and absf(alpha_f) > peak_slip_angle * 1.2 and absf(alpha_f) > absf(alpha_r) + 0.04
	oversteer = speed > 9.0 and absf(alpha_r) > peak_slip_angle * 1.05 and absf(alpha_r) > absf(alpha_f) * 0.9
	_rpm_flare = lerpf(_rpm_flare, rear_tire.slip_ratio * 2600.0 if rear_tire.spinning else 0.0, minf(1.0, 10.0 * delta))
	display_rpm = lerpf(display_rpm, minf(engine.rpm + _rpm_flare, engine.redline_rpm * 1.01), minf(1.0, 16.0 * delta))


func _surface_grip(surface: int, curb_compliance: float) -> float:
	if surface == VehiclePhysicsConfig.Surface.CURB:
		# Compliant suspension rides curbs; stiff suspension skips across them.
		return lerpf(config.surface_grip[surface] - 0.09, 1.0, curb_compliance) * grip_scale
	if surface >= VehiclePhysicsConfig.Surface.GRASS:
		# Grass and gravel are already slippery; rain must not make a spin unrecoverable.
		return config.surface_grip[surface] * maxf(grip_scale, 0.9)
	return config.surface_grip[surface] * grip_scale


## Shares one grip budget between longitudinal and lateral demand.
## If the combined request exceeds the limit both are scaled back proportionally.
func _combine(fx_req: float, fy_req: float, limit: float, avail: float, tire: TireModel, driving: bool, slide: float, speed: float) -> Vector2:
	var fx := clampf(fx_req, -limit * config.max_longitudinal_overdrive, limit * config.max_longitudinal_overdrive)
	var fy := fy_req
	tire.slip_ratio = maxf(0.0, absf(fx_req) / maxf(avail, 1.0) - 1.0)
	var saturated := tire.slip_ratio > 0.04 and speed > 1.5
	tire.locked = saturated and not driving
	tire.spinning = saturated and driving
	var budget := limit
	if tire.locked:
		budget *= 1.0 - config.lock_grip_penalty      # a sliding contact patch grips less
	elif tire.spinning:
		budget *= 1.0 - config.spin_grip_penalty
	var demand := sqrt(fx * fx + fy * fy)
	tire.usage = demand / maxf(limit, 1.0)
	if demand > budget:
		var k := budget / demand
		fx *= k
		fy *= k
	tire.sliding = slide + (minf(tire.slip_ratio, 1.0) * 0.8 if saturated else 0.0)
	return Vector2(fx, fy)
