class_name VehiclePhysicsConfig
extends Resource
## Every tunable constant of the driving model in one place.
## Edit data/physics/default_physics.tres in the inspector to retune without touching code.

## World scale shared by physics, track and rendering.
const PPM := 10.0
const GRAVITY := 9.81

enum Surface { ASPHALT, CURB, GRASS, GRAVEL }

@export_group("Geometry")
@export var wheelbase := 3.0
@export var track_width := 1.62
@export var cg_height := 0.17
@export var wheel_radius := 0.33
## Radius of gyration about the vertical axis. Larger = lazier rotation.
@export var yaw_gyration_radius := 1.22
@export var driver_mass := 75.0
@export var driver_position := 1.72
@export var base_fuel_mass := 46.0
@export var fuel_position := 1.2

@export_group("Steering")
@export var max_steer_deg := 28.0
@export var high_speed_steer_deg := 6.5
## Speed constant (m/s) of the exponential lock reduction.
@export var steer_speed_falloff := 17.0
## Front wheel slew rate in rad/s.
@export var steering_rate := 2.6

@export_group("Tires")
## Cornering stiffness per unit of load (1/rad). Higher = sharper, peakier tires.
@export var cornering_stiffness := 21.0
@export var tire_grip_multiplier := 1.0
## Rear tires are wider than the fronts on this architecture. This builds in a steady-state
## understeer margin; braking (load moves forward) and throttle (rear grip spent on drive)
## then rotate the car, which is what makes trail braking and throttle steering work.
@export var rear_grip_bias := 1.1
## Raw front/rear capability balance that feels neutral on track given the margin above.
@export var neutral_balance_offset := 0.095
## Grip coefficient lost per 100% of extra load.
@export var load_sensitivity := 0.18
@export var front_reference_load := 2950.0
@export var rear_reference_load := 3470.0
## Extra grip lost once the tire is sliding well past its peak slip angle.
@export var slide_grip_falloff := 0.1
## Grip lost by a locked wheel / a spinning wheel (kinetic vs static friction).
@export var lock_grip_penalty := 0.13
@export var spin_grip_penalty := 0.1
## Longitudinal demand may exceed grip by this factor before it is clipped.
@export var max_longitudinal_overdrive := 1.3
## Slip angle (rad) beyond which skid marks, smoke and squeal start.
@export var slip_threshold := 0.17
@export var low_speed_floor := 6.0

@export_group("Load transfer")
@export var weight_transfer_scale := 1.0
@export var weight_transfer_rate := 9.0

@export_group("Aero and drag")
@export var air_density := 1.225
@export var drag_multiplier := 1.0
@export var downforce_multiplier := 1.0
@export var body_drag_area := 0.42
@export var body_downforce_area := 0.7
@export var body_downforce_front_share := 0.4

@export_group("Assists")
## Fraction of available longitudinal grip TC allows, indexed by level (off, low, high).
@export var tc_levels: PackedFloat32Array = [1.0, 0.9, 0.76]
@export var abs_levels: PackedFloat32Array = [1.0, 0.9, 0.78]

## Stability assist: extra yaw damping and torque cut while the rear is sliding (per unit of slide).
@export var stability_yaw_gain := 2.5
@export var stability_torque_cut := 0.45

@export_group("Surfaces (asphalt, curb, grass, gravel)")
@export var surface_grip: PackedFloat32Array = [1.0, 0.93, 0.42, 0.5]
@export var surface_rolling: PackedFloat32Array = [1.0, 1.4, 9.0, 26.0]
@export var surface_steering: PackedFloat32Array = [1.0, 1.0, 0.85, 0.55]

@export_group("Stability limits")
@export var max_yaw_rate := 4.5
## Extra yaw damping torque per rad/s (N m s). Helps make small slides catchable.
@export var yaw_damping := 950.0
@export var collision_bounce := 0.05


func max_steer_angle(speed: float) -> float:
	return deg_to_rad(high_speed_steer_deg + (max_steer_deg - high_speed_steer_deg) * exp(-absf(speed) / steer_speed_falloff))


## Tire grip coefficient multiplier for a given vertical load (load sensitivity).
func load_factor(load: float, reference: float) -> float:
	return clampf(1.0 - load_sensitivity * (load / reference - 1.0), 0.7, 1.08)
