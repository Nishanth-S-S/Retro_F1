class_name TransmissionModel
extends RefCounted
## Six forward gears + reverse with a final drive. Automatic by default.

signal gear_changed(gear: int)

const UPSHIFT_FRACTION := 0.965
const DOWNSHIFT_FRACTION := 0.86

var ratios: PackedFloat32Array = [2.9, 2.2, 1.75, 1.42, 1.19, 1.0]
var reverse_ratio := 3.0
var final_drive := 3.95
var efficiency := 0.9
var shift_time := 0.2
var automatic := true

var gear := 1               # -1 reverse, 1..n forward
var shift_timer := 0.0


func configure(part: VehiclePart) -> void:
	var list: Array = part.stats.get("ratios", [2.9, 2.2, 1.75, 1.42, 1.19, 1.0])
	ratios = PackedFloat32Array()
	for r: Variant in list:
		ratios.append(float(r))
	reverse_ratio = part.stat("reverse_ratio", 3.0)
	final_drive = part.stat("final_drive", 3.95)
	efficiency = part.stat("efficiency", 0.9)
	shift_time = part.stat("shift_time", 0.2)
	reset()


func reset() -> void:
	gear = 1
	shift_timer = 0.0


func gear_count() -> int:
	return ratios.size()


func total_ratio(for_gear: int = 0) -> float:
	var g := gear if for_gear == 0 else for_gear
	if g < 0:
		return -reverse_ratio * final_drive
	return ratios[clampi(g, 1, ratios.size()) - 1] * final_drive


## Engine speed implied by road speed in the given gear.
func rpm_at(speed: float, wheel_radius: float, for_gear: int = 0) -> float:
	return absf(speed) / (TAU * wheel_radius) * 60.0 * absf(total_ratio(for_gear))


func is_shifting() -> bool:
	return shift_timer > 0.0


func shift_to(new_gear: int) -> bool:
	if new_gear == gear or new_gear == 0 or new_gear > ratios.size() or new_gear < -1 or shift_timer > 0.0:
		return false
	gear = new_gear
	shift_timer = shift_time
	gear_changed.emit(gear)
	return true


func shift_up() -> bool:
	return shift_to(1 if gear == -1 else gear + 1)


func shift_down(speed: float, wheel_radius: float, redline: float) -> bool:
	if gear == 1:
		return shift_to(-1) if absf(speed) < 1.5 else false
	if gear == -1:
		return false
	# Refuse downshifts that would over-rev the engine.
	if rpm_at(speed, wheel_radius, gear - 1) > redline * 1.02:
		return false
	return shift_to(gear - 1)


func update(delta: float, speed: float, wheel_radius: float, redline: float, throttle: float) -> void:
	shift_timer = maxf(0.0, shift_timer - delta)
	if not automatic or gear < 1 or shift_timer > 0.0:
		return
	var current := rpm_at(speed, wheel_radius)
	if current > redline * UPSHIFT_FRACTION and gear < ratios.size() and throttle > 0.05:
		shift_to(gear + 1)
	elif gear > 1 and rpm_at(speed, wheel_radius, gear - 1) < redline * DOWNSHIFT_FRACTION:
		shift_to(gear - 1)
