class_name TireModel
extends RefCounted
## One axle's pair of tires: compound grip, temperature, wear and slip state.

const START_TEMP := 70.0
## Temperature a rolling but unloaded tire settles at.
const AMBIENT_TEMP := 60.0
const COOLING_RATE := 0.032
const WORK_HEAT := 1.9           # deg C/s at full usage at speed
const SLIDE_HEAT := 7.0         # deg C/s per unit of sliding
const TEMP_GRIP_LOSS := 0.26     # max grip lost far outside the window
const TEMP_FALLOFF_SPAN := 38.0
const WEAR_GRIP_LOSS := 0.36     # grip lost at 0% tread
const BASE_WEAR_PER_SECOND := 0.0009

var base_grip := 1.45
var wear_rate := 1.0
var optimal_temperature := 92.0
var temperature_window := 16.0
var rolling_resistance := 0.012
var heat_rate := 1.0
## Multiplier from an AI driver's tire management (1.0 for the player).
var abuse_scale := 1.0
## The driver's tyre care (DriverPerformance.wear_multiplier): wear only, on top of how hard
## the tyre is actually worked, so careful hands never erase the cost of sliding.
var driver_wear := 1.0

var temperature := START_TEMP
var wear := 1.0                   # 1.0 = new, 0.0 = destroyed
var slip_angle := 0.0
var slip_ratio := 0.0             # longitudinal over-demand, 0 = hooked up
var usage := 0.0                  # fraction of the traction circle in use
var sliding := 0.0                # 0..1+ combined slide intensity (drives fx, heat, wear)
var locked := false
var spinning := false


func configure(part: VehiclePart) -> void:
	base_grip = part.stat("base_grip", 1.45)
	wear_rate = part.stat("wear_rate", 1.0)
	optimal_temperature = part.stat("optimal_temperature", 92.0)
	temperature_window = part.stat("temperature_window", 16.0)
	rolling_resistance = part.stat("rolling_resistance", 0.012)
	heat_rate = part.stat("heat_rate", 1.0)
	reset()


func reset() -> void:
	temperature = START_TEMP
	wear = 1.0
	slip_angle = 0.0
	slip_ratio = 0.0
	usage = 0.0
	sliding = 0.0
	locked = false
	spinning = false


## Smooth bell around the optimal window: 1.0 inside, falling off outside it.
func temperature_factor() -> float:
	var excess := maxf(0.0, absf(temperature - optimal_temperature) - temperature_window)
	var x := clampf(excess / TEMP_FALLOFF_SPAN, 0.0, 1.0)
	return 1.0 - TEMP_GRIP_LOSS * x * x * (3.0 - 2.0 * x)


func wear_factor() -> float:
	return 1.0 - WEAR_GRIP_LOSS * pow(1.0 - wear, 1.15)


func grip_coefficient() -> float:
	return base_grip * temperature_factor() * wear_factor()


func is_overheating() -> bool:
	return temperature > optimal_temperature + temperature_window + 6.0


## `surface_grip` scales friction heating: sliding on grass barely warms the tire.
func update(delta: float, speed: float, surface_grip: float = 1.0) -> void:
	var speed_factor := clampf(speed / 40.0, 0.0, 1.0)
	var work := minf(usage, 1.2)
	var heat := (WORK_HEAT * work * work * speed_factor + SLIDE_HEAT * minf(sliding, 1.3) * clampf(speed / 15.0, 0.2, 1.0)) * heat_rate * abuse_scale * surface_grip
	temperature += (heat - COOLING_RATE * (temperature - AMBIENT_TEMP) * (0.6 + 0.4 * speed_factor)) * delta
	temperature = clampf(temperature, AMBIENT_TEMP, 160.0)
	var overheat := clampf((temperature - optimal_temperature - temperature_window) / 20.0, 0.0, 2.0)
	var wear_speed := BASE_WEAR_PER_SECOND * wear_rate * abuse_scale * driver_wear * (work * work * speed_factor + 4.0 * minf(sliding, 1.3) * surface_grip + 1.0 * overheat * speed_factor)
	wear = maxf(0.0, wear - wear_speed * delta)
