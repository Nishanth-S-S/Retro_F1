class_name EngineModel
extends RefCounted
## RPM-driven engine. Torque comes from a Curve resource scaled so that the peak
## power matches the part's rated power.

const AMBIENT_TEMP := 85.0
const DERATE_START := 106.0
const DERATE_RANGE := 22.0
const MAX_DERATE := 0.12

var idle_rpm := 1600.0
var redline_rpm := 9500.0
var peak_power_kw := 200.0
var peak_torque := 0.0
var throttle_response := 1.0
var heat_generation := 1.0
var torque_curve := Curve.new()

var rpm := 1600.0
var throttle := 0.0          # response-filtered throttle actually reaching the engine
var temperature := AMBIENT_TEMP
var _torque_scale := 1.0


func configure(part: VehiclePart) -> void:
	idle_rpm = part.stat("idle_rpm", 1600.0)
	redline_rpm = part.stat("redline_rpm", 9500.0)
	peak_power_kw = part.stat("power_kw", 200.0)
	throttle_response = part.stat("throttle_response", 1.0)
	heat_generation = part.stat("heat_generation", 1.0)
	torque_curve = Curve.new()
	var points: Array = part.stats.get("torque_curve", [[0.15, 0.7], [0.65, 1.0], [1.0, 0.85]])
	for p: Array in points:
		torque_curve.add_point(Vector2(float(p[0]), float(p[1])))
	torque_curve.bake()
	# Scale the normalised curve so that max(torque * omega) equals rated power.
	var best := 0.0
	peak_torque = 0.0
	for i in range(10, 101):
		var x := i / 100.0
		best = maxf(best, torque_curve.sample_baked(x) * x * redline_rpm * TAU / 60.0)
	_torque_scale = peak_power_kw * 1000.0 / maxf(best, 1.0)
	for i in range(10, 101):
		peak_torque = maxf(peak_torque, torque_curve.sample_baked(i / 100.0) * _torque_scale)
	reset()


func reset() -> void:
	rpm = idle_rpm
	throttle = 0.0
	temperature = AMBIENT_TEMP


func full_torque_at(at_rpm: float) -> float:
	if at_rpm >= redline_rpm:
		return 0.0
	return torque_curve.sample_baked(clampf(at_rpm / redline_rpm, 0.0, 1.0)) * _torque_scale


## Net crankshaft torque for the current rpm and filtered throttle (negative = engine braking).
func torque() -> float:
	var drive := full_torque_at(rpm) * throttle * power_factor()
	var braking := peak_torque * 0.09 * (rpm / redline_rpm) * (1.0 - throttle)
	return drive - braking


func power_factor() -> float:
	return 1.0 - MAX_DERATE * clampf((temperature - DERATE_START) / DERATE_RANGE, 0.0, 1.0)


func is_overheating() -> bool:
	return temperature > DERATE_START + 2.0


func update(delta: float, throttle_input: float, speed: float) -> void:
	# Turbo lag / flywheel inertia: laggy engines pick up slowly but all engines close quickly.
	var rate := (4.0 + 14.0 * throttle_response) if throttle_input > throttle else 18.0
	throttle = move_toward(throttle, throttle_input, rate * delta)
	var heat := heat_generation * throttle * (rpm / redline_rpm) * 9.0
	var cooling := (temperature - AMBIENT_TEMP + 25.0) * (0.05 + speed * 0.0035)
	temperature += (heat - cooling) * delta
