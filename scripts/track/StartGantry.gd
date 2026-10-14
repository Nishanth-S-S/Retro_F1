class_name StartGantry
extends Node2D
## The start gantry over the grid: a beam across the track with five red light pods,
## drawn above the cars. Lights follow the race countdown.

var track: TrackData
var lit := 0


func _ready() -> void:
	z_index = 6


func _draw() -> void:
	if track == null:
		return
	var ppm := VehiclePhysicsConfig.PPM
	var p := track.points[0] + track.tangents[0] * 12.0 * ppm
	var n := track.normals[0]
	var t := track.tangents[0]
	var half := (track.half_width + 4.0) * ppm
	var corners := PackedVector2Array([p - n * half - t * 1.2 * ppm, p + n * half - t * 1.2 * ppm, p + n * half + t * 1.2 * ppm, p - n * half + t * 1.2 * ppm])
	draw_colored_polygon(PackedVector2Array([corners[0] + Vector2(8, 12), corners[1] + Vector2(8, 12), corners[2] + Vector2(8, 12), corners[3] + Vector2(8, 12)]), Color(0, 0, 0, 0.25))
	draw_colored_polygon(corners, Color("1d2026"))
	for i in 5:
		var c := p + n * (i - 2) * 2.4 * ppm
		draw_circle(c, 0.85 * ppm, Color("0d0f12"))
		draw_circle(c, 0.6 * ppm, Color("ff2a1a") if i < lit else Color("3a1412"))


func set_lit(count: int) -> void:
	lit = count
	queue_redraw()
