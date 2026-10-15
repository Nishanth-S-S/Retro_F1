class_name CarStats
extends RefCounted
## Everything derived from a CarSetup. The garage shows these numbers and the physics
## consumes the very same object, so what the player reads is what the car does.

const BALANCE_LABELS: PackedStringArray = ["Strong Understeer", "Understeer", "Neutral", "Oversteer", "Strong Oversteer"]
const BALANCE_MILD := 0.02
const BALANCE_STRONG := 0.06
const LOW_SPEED_REF := 20.0     # m/s, where wings barely matter
const HIGH_SPEED_REF := 61.0    # m/s (~220 km/h)

var valid := false
var mass := 700.0
var cg_x := 1.3                 # metres ahead of the rear axle
var front_weight := 0.44        # fraction of static weight on the front axle
var fuel_mass := 46.0
var mass_items: Array[Dictionary] = []

var power_kw := 0.0
var peak_torque := 0.0
var power_to_weight := 0.0      # kW per tonne
var top_speed := 0.0            # m/s
var top_speed_limited_by := ""
var accel_0_100 := 0.0          # seconds
var mech_grip_g := 0.0
var downforce_200 := 0.0        # N at 200 km/h
var braking_g := 0.0

var front_downforce_area := 0.0
var rear_downforce_area := 0.0
var drag_area := 0.0
var front_aero := 0.45          # fraction of downforce on the front axle

var front_mech_grip := 1.0
var rear_mech_grip := 1.0
var front_response := 1.0
var rear_response := 1.0
var front_curb := 0.5
var rear_curb := 0.5
var rigidity := 1.0
var tire_grip := 1.45

var balance_low := 0.0
var balance_high := 0.0
var balance_index := 0.0


static func compute(setup: CarSetup, config: VehiclePhysicsConfig) -> CarStats:
	var s := CarStats.new()
	s._mass_and_balance(setup, config)
	s._aero(setup, config)
	s._chassis_and_grip(setup, config)
	s.valid = setup.missing_slots().is_empty()
	s._performance(setup, config)
	return s


func _mass_and_balance(setup: CarSetup, config: VehiclePhysicsConfig) -> void:
	mass_items.clear()
	for slot in CarSetup.SLOTS:
		var part := setup.part(slot)
		if part == null or part.mass <= 0.0:
			continue
		var x: float = setup.ballast_x() if slot == "ballast" else float(CarSetup.SLOT_POSITION[slot])
		var m := part.mass - (5.0 * setup.level("chassis") if slot == "chassis" else 0.0)
		mass_items.append({"slot": slot, "name": CarSetup.SLOT_LABELS[slot], "mass": m, "x": x})
	var engine := setup.part("engine")
	# Thirsty engines must carry more fuel for the same distance.
	fuel_mass = config.base_fuel_mass / (engine.stat("fuel_efficiency", 1.0) if engine else 1.0)
	mass_items.append({"slot": "driver", "name": "Driver", "mass": config.driver_mass, "x": config.driver_position})
	mass_items.append({"slot": "fuel", "name": "Fuel", "mass": fuel_mass, "x": config.fuel_position})
	mass = 0.0
	var moment := 0.0
	for item in mass_items:
		mass += float(item["mass"])
		moment += float(item["mass"]) * float(item["x"])
	# Longitudinal centre of mass = sum(m * x) / sum(m)
	cg_x = moment / maxf(mass, 1.0)
	front_weight = clampf(cg_x / config.wheelbase, 0.2, 0.8)


static func wing_angle_factor(part: VehiclePart, angle: int) -> float:
	var mid := (CarSetup.WING_ANGLE_MIN + CarSetup.WING_ANGLE_MAX) * 0.5
	var span := (CarSetup.WING_ANGLE_MAX - CarSetup.WING_ANGLE_MIN) * 0.5
	return 1.0 + part.stat("adjustability", 0.35) * (angle - mid) / span


func _aero(setup: CarSetup, config: VehiclePhysicsConfig) -> void:
	var front := setup.part("front_wing")
	var rear := setup.part("rear_wing")
	var front_susp := setup.part("front_suspension")
	var rear_susp := setup.part("rear_suspension")
	var body_df := config.body_downforce_area
	front_downforce_area = body_df * config.body_downforce_front_share
	rear_downforce_area = body_df * (1.0 - config.body_downforce_front_share)
	drag_area = config.body_drag_area
	if front:
		var f := wing_angle_factor(front, setup.front_wing_angle)
		var lv := setup.level("front_wing")
		front_downforce_area += front.stat("downforce_coefficient") * f * (1.0 + 0.05 * lv)
		# Drag grows a little faster than downforce as the angle steepens.
		drag_area += front.stat("drag_coefficient") * f * f * (1.0 - 0.025 * lv)
	if rear:
		var f := wing_angle_factor(rear, setup.rear_wing_angle)
		var lv := setup.level("rear_wing")
		rear_downforce_area += rear.stat("downforce_coefficient") * f * (1.0 + 0.05 * lv)
		drag_area += rear.stat("drag_coefficient") * f * f * (1.0 - 0.025 * lv)
	# A stiff platform keeps the wings and floor working; a soft one bleeds downforce.
	if front_susp:
		front_downforce_area *= front_susp.stat("aero_platform", 1.0)
	if rear_susp:
		rear_downforce_area *= rear_susp.stat("aero_platform", 1.0)
	# Body set and ride height: a lower car seals the floor for more downforce.
	var body: Dictionary = CarSetup.BODY_SETS[setup.body]
	var low := (5.0 - setup.ride_height) * 0.025
	front_downforce_area *= config.downforce_multiplier * float(body["downforce"]) * (1.0 + low)
	rear_downforce_area *= config.downforce_multiplier * float(body["downforce"]) * (1.0 + low)
	drag_area *= config.drag_multiplier * float(body["drag"]) * (1.0 + low * 0.25)
	front_aero = front_downforce_area / maxf(front_downforce_area + rear_downforce_area, 0.001)
	var q := 0.5 * config.air_density * 55.56 * 55.56
	downforce_200 = q * (front_downforce_area + rear_downforce_area)


func _chassis_and_grip(setup: CarSetup, config: VehiclePhysicsConfig) -> void:
	var chassis := setup.part("chassis")
	var front_susp := setup.part("front_suspension")
	var rear_susp := setup.part("rear_suspension")
	var tires := setup.part("tires")
	rigidity = chassis.stat("rigidity", 1.0) if chassis else 1.0
	front_mech_grip = front_susp.stat("mechanical_grip_modifier", 1.0) if front_susp else 0.9
	rear_mech_grip = rear_susp.stat("mechanical_grip_modifier", 1.0) if rear_susp else 0.9
	front_response = (front_susp.stat("response_modifier", 1.0) if front_susp else 1.0) * rigidity
	rear_response = (rear_susp.stat("response_modifier", 1.0) if rear_susp else 1.0) * rigidity
	front_curb = front_susp.stat("curb_compliance", 0.5) if front_susp else 0.5
	rear_curb = rear_susp.stat("curb_compliance", 0.5) if rear_susp else 0.5
	# A slammed car crashes over curbs; a high one rides them.
	front_curb = clampf(front_curb + (setup.ride_height - 5) * 0.04, 0.05, 1.0)
	rear_curb = clampf(rear_curb + (setup.ride_height - 5) * 0.04, 0.05, 1.0)
	# Anti-roll bars move grip between the axles: stiff front = understeer.
	front_mech_grip *= (1.0 - setup.anti_roll * 0.012) * (1.0 + 0.015 * setup.level("suspension"))
	rear_mech_grip *= (1.0 + setup.anti_roll * 0.012) * (1.0 + 0.015 * setup.level("suspension"))
	tire_grip = (tires.stat("base_grip", 1.45) if tires else 1.0) * config.tire_grip_multiplier * pressure_grip(setup.tyre_pressure)
	var caps_low := _axle_capability(LOW_SPEED_REF, config)
	var caps_high := _axle_capability(HIGH_SPEED_REF, config)
	mech_grip_g = _axle_grip_g(0.0, config)
	# Positive = front axle has spare capability -> rear lets go first -> oversteer.
	balance_low = log(caps_low.x / caps_low.y) + config.neutral_balance_offset
	balance_high = log(caps_high.x / caps_high.y) + config.neutral_balance_offset
	balance_index = (balance_low + balance_high) * 0.5


## Lateral acceleration each axle can sustain at `speed` (x = front, y = rear), m/s^2.
func _axle_capability(speed: float, config: VehiclePhysicsConfig) -> Vector2:
	var weight := mass * VehiclePhysicsConfig.GRAVITY
	var q := 0.5 * config.air_density * speed * speed
	var nf := weight * front_weight + q * front_downforce_area
	var nr := weight * (1.0 - front_weight) + q * rear_downforce_area
	var mu_f := tire_grip * front_mech_grip * config.load_factor(nf, config.front_reference_load)
	var mu_r := tire_grip * rear_mech_grip * config.rear_grip_bias * config.load_factor(nr, config.rear_reference_load)
	return Vector2(mu_f * nf / (mass * front_weight), mu_r * nr / (mass * (1.0 - front_weight)))


func _axle_grip_g(speed: float, config: VehiclePhysicsConfig) -> float:
	var caps := _axle_capability(speed, config)
	return minf(caps.x, caps.y) / VehiclePhysicsConfig.GRAVITY


static func pressure_grip(pressure: int) -> float:
	return 1.0 - (pressure - 5) * 0.008


static func balance_label_for(index: float) -> String:
	if index < -BALANCE_STRONG:
		return BALANCE_LABELS[0]
	if index < -BALANCE_MILD:
		return BALANCE_LABELS[1]
	if index <= BALANCE_MILD:
		return BALANCE_LABELS[2]
	if index <= BALANCE_STRONG:
		return BALANCE_LABELS[3]
	return BALANCE_LABELS[4]


func balance_label() -> String:
	return balance_label_for(balance_index)


func _performance(setup: CarSetup, config: VehiclePhysicsConfig) -> void:
	var engine_part := setup.part("engine")
	var gearbox_part := setup.part("gearbox")
	var brakes_part := setup.part("brakes")
	var tires_part := setup.part("tires")
	power_kw = (engine_part.stat("power_kw") if engine_part else 0.0) * (1.0 + 0.04 * setup.level("engine"))
	power_to_weight = power_kw / maxf(mass, 1.0) * 1000.0
	top_speed = 0.0
	accel_0_100 = 0.0
	braking_g = 0.0
	if brakes_part:
		var v := 55.56
		var q := 0.5 * config.air_density * v * v
		var grip_force := tire_grip * (mass * VehiclePhysicsConfig.GRAVITY + q * (front_downforce_area + rear_downforce_area)) * 0.93
		braking_g = (minf(brakes_part.stat("max_brake_force") * (1.0 + 0.06 * setup.level("brakes")), grip_force) + q * drag_area) / (mass * VehiclePhysicsConfig.GRAVITY)
	if engine_part == null or gearbox_part == null:
		return
	var engine := EngineModel.new()
	engine.configure(engine_part, 1.0 + 0.04 * setup.level("engine"))
	peak_torque = engine.peak_torque
	var gearbox := TransmissionModel.new()
	gearbox.configure(gearbox_part, setup.level("gearbox"))
	var rolling := (tires_part.stat("rolling_resistance", 0.012) if tires_part else 0.012) * mass * VehiclePhysicsConfig.GRAVITY
	# Top speed: fastest speed where some gear still out-pulls drag.
	var v_gear_limit := engine.redline_rpm / (gearbox.total_ratio(gearbox.gear_count())) * TAU * config.wheel_radius / 60.0
	var v := 20.0
	while v < 130.0:
		var force := _best_drive_force(engine, gearbox, v, config)
		if force < 0.5 * config.air_density * v * v * drag_area + rolling:
			break
		top_speed = v
		v += 0.25
	top_speed_limited_by = "GEARING" if top_speed >= v_gear_limit - 0.6 else "DRAG"
	# 0-100 km/h: integrate a traction-limited launch.
	var speed := 0.0
	var time := 0.0
	var accel := 0.0
	var step := 0.02
	var weight := mass * VehiclePhysicsConfig.GRAVITY
	while speed < 27.78 and time < 20.0:
		var rear_load := weight * (1.0 - front_weight) + mass * accel * config.cg_height / config.wheelbase + 0.5 * config.air_density * speed * speed * rear_downforce_area
		var traction := tire_grip * rear_mech_grip * config.rear_grip_bias * config.load_factor(rear_load, config.rear_reference_load) * rear_load * 0.95
		var force := minf(_best_drive_force(engine, gearbox, speed, config), traction)
		force -= 0.5 * config.air_density * speed * speed * drag_area + rolling
		accel = force / mass
		speed += accel * step
		time += step
	accel_0_100 = time + gearbox.shift_time


func _best_drive_force(engine: EngineModel, gearbox: TransmissionModel, speed: float, config: VehiclePhysicsConfig) -> float:
	var best := 0.0
	for g in range(1, gearbox.gear_count() + 1):
		var rpm := maxf(gearbox.rpm_at(speed, config.wheel_radius, g), engine.redline_rpm * 0.55)
		if rpm >= engine.redline_rpm:
			continue
		best = maxf(best, engine.full_torque_at(rpm) * gearbox.total_ratio(g) * gearbox.efficiency / config.wheel_radius)
	return best
