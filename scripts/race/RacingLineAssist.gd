class_name RacingLineAssist
extends Node2D
## Draws the racing line ahead of the player, coloured from the target-speed profile:
## blue = flat out, yellow = lift / carry speed, red = brake.

const AHEAD_SAMPLES := 80
const COLOR_NORMAL := Color(0.35, 0.8, 1.0, 0.55)
const COLOR_LIFT := Color(1.0, 0.82, 0.25, 0.6)
const COLOR_BRAKE := Color(1.0, 0.3, 0.28, 0.7)

var line: RacingLine
var car: VehicleController
var _colors := PackedColorArray()
var _points := PackedVector2Array()
var _draw_colors := PackedColorArray()
var _last_index := -1


func setup(racing_line: RacingLine, vehicle: VehicleController) -> void:
	line = racing_line
	car = vehicle
	z_index = -4
	var profile := line.speed_profile(car.physics.stats, car.physics_config, 1.0, 0.95)
	var n := profile.size()
	var cap := car.physics.stats.top_speed
	_colors.resize(n)
	for i in n:
		var next := profile[(i + 1) % n]
		var decel := (profile[i] * profile[i] - next * next) / (2.0 * line.track.spacing)
		if decel > 3.5:
			_colors[i] = COLOR_BRAKE
		elif profile[i] < cap * 0.9 and decel > -1.0:
			_colors[i] = COLOR_LIFT
		else:
			_colors[i] = COLOR_NORMAL
	_points.resize(AHEAD_SAMPLES)
	_draw_colors.resize(AHEAD_SAMPLES)


func _process(_delta: float) -> void:
	if car and car.track_index != _last_index:
		_last_index = car.track_index
		queue_redraw()


func _draw() -> void:
	if line == null or car == null:
		return
	var n := _colors.size()
	for k in AHEAD_SAMPLES:
		var i := posmod(car.track_index + 2 + k, n)
		_points[k] = line.points[i]
		var fade := 1.0 - float(k) / AHEAD_SAMPLES
		var c := _colors[i]
		_draw_colors[k] = Color(c.r, c.g, c.b, c.a * minf(1.0, fade * 2.2))
	draw_polyline_colors(_points, _draw_colors, 3.0, true)
