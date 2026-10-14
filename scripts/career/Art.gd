class_name Art
extends Control
## A control whose drawing is supplied by a callable: Art.make(size, func(canvas): ...).

var painter: Callable


static func make(min_size: Vector2, paint: Callable) -> Art:
	var art := Art.new()
	art.custom_minimum_size = min_size
	art.painter = paint
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return art


func _draw() -> void:
	if painter.is_valid():
		painter.call(self)


## Horizontal 0-100 bar with a label and value, used for ratings everywhere.
static func rating_bar(title: String, value: float, color: Color = UIKit.LINE, width: float = 220.0) -> Art:
	return make(Vector2(width, 22), func(c: Control) -> void:
		var f := UIKit.font()
		c.draw_string(f, Vector2(0, 14), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.TEXT_DIM)
		var x := 92.0
		var w := c.size.x - x - 34.0
		c.draw_rect(Rect2(x, 5, w, 11), UIKit.GRID_BOLD)
		c.draw_rect(Rect2(x, 5, w * clampf(value / 100.0, 0.0, 1.0), 11), color)
		c.draw_string(f, Vector2(0, 15), "%d" % int(round(value)), HORIZONTAL_ALIGNMENT_RIGHT, c.size.x, 13, UIKit.TEXT))


## Big square rating chip: "CAR 78".
static func chip(title: String, value: int, color: Color) -> Art:
	return make(Vector2(74, 58), func(c: Control) -> void:
		var f := UIKit.font()
		c.draw_rect(Rect2(Vector2.ZERO, c.size), color)
		c.draw_rect(Rect2(Vector2.ZERO, c.size), UIKit.INK, false, 3.0)
		c.draw_string(f, Vector2(0, 16), title, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 10, Color.WHITE)
		c.draw_string(f, Vector2(0, 46), str(value), HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 28, Color.WHITE))
