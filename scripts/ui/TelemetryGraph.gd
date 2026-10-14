class_name TelemetryGraph
extends Control
## Speed trace against lap distance (latest lap vs session-best lap), with throttle and
## brake strips underneath.

var lap: Dictionary = {}
var reference: Dictionary = {}
var track_length := 1.0
var lap_label := "LAST LAP"
var reference_label := "BEST LAP"


func set_data(lap_series: Dictionary, reference_series: Dictionary, length: float) -> void:
	lap = lap_series
	reference = reference_series
	track_length = maxf(length, 1.0)
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var plot := Rect2(40.0, 22.0, size.x - 50.0, size.y - 92.0)
	draw_rect(plot, Color(UIKit.BG_DEEP, 0.8))
	if lap.is_empty() or (lap.get("distance", []) as Array).size() < 2:
		draw_string(font, plot.position + Vector2(0, plot.size.y * 0.5), "Complete a lap to record telemetry.", HORIZONTAL_ALIGNMENT_CENTER, plot.size.x, 13, UIKit.TEXT_DIM)
		return
	var max_speed := 100.0
	for series: Dictionary in [lap, reference]:
		for v: float in series.get("speed", []):
			max_speed = maxf(max_speed, v)
	max_speed = ceilf(max_speed / 50.0) * 50.0
	# Grid and axis labels.
	var kmh := 0.0
	while kmh <= max_speed:
		var y := plot.end.y - kmh / max_speed * plot.size.y
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), UIKit.GRID_BOLD, 1.0)
		draw_string(font, Vector2(2.0, y + 4.0), "%d" % int(kmh), HORIZONTAL_ALIGNMENT_RIGHT, 34.0, 10, UIKit.TEXT_DIM)
		kmh += 50.0
	for q in 5:
		var x := plot.position.x + plot.size.x * q / 4.0
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), UIKit.GRID, 1.0)
	draw_string(font, Vector2(plot.position.x, 14.0), "SPEED km/h", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIKit.TEXT_DIM)
	if not reference.is_empty():
		_trace(reference, "speed", plot, max_speed, Color(UIKit.PURPLE, 0.8), 1.5)
	_trace(lap, "speed", plot, max_speed, UIKit.ACCENT, 2.0)
	# Pedal strips.
	var strip := Rect2(plot.position.x, plot.end.y + 8.0, plot.size.x, 22.0)
	draw_rect(strip, Color(UIKit.BG_DEEP, 0.8))
	_trace(lap, "throttle", strip, 1.0, UIKit.GOOD, 1.5)
	var strip2 := Rect2(plot.position.x, strip.end.y + 4.0, plot.size.x, 22.0)
	draw_rect(strip2, Color(UIKit.BG_DEEP, 0.8))
	_trace(lap, "brake", strip2, 1.0, UIKit.BAD, 1.5)
	draw_string(font, Vector2(2.0, strip.position.y + 15.0), "THR", HORIZONTAL_ALIGNMENT_RIGHT, 34.0, 10, UIKit.GOOD)
	draw_string(font, Vector2(2.0, strip2.position.y + 15.0), "BRK", HORIZONTAL_ALIGNMENT_RIGHT, 34.0, 10, UIKit.BAD)
	# Legend.
	var ly := size.y - 6.0
	draw_line(Vector2(plot.position.x, ly - 4.0), Vector2(plot.position.x + 18.0, ly - 4.0), UIKit.ACCENT, 2.0)
	draw_string(font, Vector2(plot.position.x + 24.0, ly), lap_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.TEXT)
	if not reference.is_empty():
		draw_line(Vector2(plot.position.x + 150.0, ly - 4.0), Vector2(plot.position.x + 168.0, ly - 4.0), UIKit.PURPLE, 2.0)
		draw_string(font, Vector2(plot.position.x + 174.0, ly), reference_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.TEXT)
	draw_string(font, Vector2(plot.position.x, ly), "distance →", HORIZONTAL_ALIGNMENT_RIGHT, plot.size.x, 10, UIKit.TEXT_DIM)


func _trace(series: Dictionary, key: String, rect: Rect2, max_value: float, color: Color, width: float) -> void:
	var distance: Array = series.get("distance", [])
	var values: Array = series.get(key, [])
	var points := PackedVector2Array()
	var last_x := -INF
	for i in mini(distance.size(), values.size()):
		var x := rect.position.x + clampf(float(distance[i]) / track_length, 0.0, 1.0) * rect.size.x
		if x < last_x:
			continue       # ignore the wrap sample at the start/finish line
		last_x = x
		points.append(Vector2(x, rect.end.y - clampf(float(values[i]) / max_value, 0.0, 1.0) * rect.size.y))
	if points.size() >= 2:
		draw_polyline(points, color, width, true)
