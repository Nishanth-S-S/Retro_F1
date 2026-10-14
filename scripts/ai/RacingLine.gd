class_name RacingLine
extends RefCounted
## A racing line derived from the track centreline plus a per-car target speed profile.
## Used by AI drivers and by the player's racing-line assist.

const PPM := VehiclePhysicsConfig.PPM
const EDGE_MARGIN := 1.7           # metres kept between the line and the track edge
const LINE_GAIN := 600.0
const GRIP_SAFETY := 0.84

var track: TrackData
var offsets := PackedFloat32Array()      # lateral offset from centreline (m, + = right)
var points := PackedVector2Array()       # pixels
var curvature := PackedFloat32Array()    # of the line itself, 1/m
var curve := Curve2D.new()


static func build(track_data: TrackData) -> RacingLine:
	var line := RacingLine.new()
	line.track = track_data
	line._generate()
	return line


func _generate() -> void:
	var n := track.count
	# Difference of a narrow and a wide blur of curvature: positive at the apex (move inside),
	# negative on approach and exit (move outside). That is the classic out-in-out line.
	var narrow := track.curvature
	var wide := track.curvature
	for pass_index in 3:
		narrow = TrackData.smooth(narrow, 3)
		wide = TrackData.smooth(wide, 10)
	var max_offset := track.half_width - EDGE_MARGIN
	offsets.resize(n)
	for i in n:
		var raw := (narrow[i] - 0.8 * wide[i]) * LINE_GAIN
		offsets[i] = max_offset * tanh(raw / max_offset)
	offsets = TrackData.smooth(TrackData.smooth(offsets, 3), 3)
	points.resize(n)
	curve = Curve2D.new()
	for i in n:
		points[i] = track.points[i] + track.normals[i] * offsets[i] * PPM
		if i % 3 == 0:
			curve.add_point(points[i])
	var raw_curv := PackedFloat32Array()
	raw_curv.resize(n)
	for i in n:
		var a := points[(i - 2 + n) % n]
		var b := points[i]
		var c := points[(i + 2) % n]
		var ab := (b - a)
		var bc := (c - b)
		var seg := (ab.length() + bc.length()) * 0.5 / PPM
		raw_curv[i] = ab.angle_to(bc) / maxf(seg, 0.01)
	curvature = TrackData.smooth(TrackData.smooth(raw_curv, 2), 2)


func point(index: int, extra_offset: float = 0.0) -> Vector2:
	var i := posmod(index, track.count)
	return points[i] + track.normals[i] * extra_offset * PPM


## Target speed (m/s) at every sample for a given car: cornering limit from grip and
## downforce, then a backward pass so the car can actually brake down to each corner.
func speed_profile(stats: CarStats, config: VehiclePhysicsConfig, grip_scale: float = 1.0, brake_scale: float = 1.0) -> PackedFloat32Array:
	var n := track.count
	var g := VehiclePhysicsConfig.GRAVITY
	var mu := stats.tire_grip * minf(stats.front_mech_grip, stats.rear_mech_grip) * GRIP_SAFETY * grip_scale
	var k_aero := 0.5 * config.air_density * (stats.front_downforce_area + stats.rear_downforce_area) / stats.mass
	var k_drag := 0.5 * config.air_density * stats.drag_area / stats.mass
	var v_cap := maxf(stats.top_speed * 1.06, 30.0)
	var profile := PackedFloat32Array()
	profile.resize(n)
	for i in n:
		var denom := absf(curvature[i]) - mu * k_aero * 0.85
		var v := v_cap if denom < 0.0002 else minf(v_cap, sqrt(mu * g / denom))
		# Fast corners are limited by whichever axle runs out first at that speed (aero
		# balance), not by average grip - refine the estimate with the real axle limits.
		var k := absf(curvature[i])
		if k > 0.0015:
			for pass_index in 2:
				var caps := stats._axle_capability(v, config)
				v = minf(v, sqrt(minf(caps.x, caps.y) * GRIP_SAFETY * grip_scale / k))
		profile[i] = v
	var brake_part := stats.braking_g * g
	for pass_index in 2:
		for i in range(n - 1, -1, -1):
			var next := profile[(i + 1) % n]
			# Friction circle: grip already spent on cornering is not available for braking,
			# so the profile brakes hard in a straight line and bleeds off as the car turns in.
			var total := mu * (g + k_aero * next * next)
			var lateral := next * next * absf(curvature[i])
			var spare := sqrt(maxf(total * total - lateral * lateral, total * total * 0.02))
			var decel := minf(spare * 0.88, brake_part) * brake_scale + k_drag * next * next
			profile[i] = minf(profile[i], sqrt(next * next + 2.0 * decel * track.spacing))
	return profile
