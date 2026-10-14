class_name DayTransition
extends CanvasLayer
## The calendar flip: a red panel slides in across the whole screen with the new date,
## holds a moment, and slides away.

var from_text := ""
var to_text := ""
var days := 1
var _panel: Control


static func play(parent: Node, from_date: String, to_date: String, day_count: int) -> void:
	var t := DayTransition.new()
	t.from_text = from_date
	t.to_text = to_date
	t.days = day_count
	parent.add_child(t)


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = Art.make(Vector2.ZERO, _paint)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var width := get_viewport().get_visible_rect().size.x
	_panel.position.x = width
	AudioManager.play("snap", -6.0, 0.8)
	var tween := create_tween()
	tween.tween_property(_panel, "position:x", 0.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.7)
	tween.tween_property(_panel, "position:x", -width, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


func _paint(a: Control) -> void:
	var size := a.size
	a.draw_rect(Rect2(Vector2.ZERO, size), UIKit.WARM)
	# Speed stripes and a chequered edge sell the slide.
	for i in 9:
		a.draw_rect(Rect2(0, 80.0 + i * 70.0, size.x, 6), Color(1, 1, 1, 0.08))
	PixelArt.draw_checker(a, Rect2(0, 0, 36, size.y), 12.0, Color.WHITE, UIKit.INK)
	PixelArt.draw_checker(a, Rect2(size.x - 36.0, 0, 36, size.y), 12.0, Color.WHITE, UIKit.INK)
	var f := UIKit.font()
	a.draw_string(f, Vector2(0, size.y * 0.34), from_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, Color(1, 1, 1, 0.6))
	a.draw_string(f, Vector2(0, size.y * 0.42), "▼" if days == 1 else "+%d DAYS" % days, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(1, 1, 1, 0.75))
	PixelFont.draw_centered(a, Rect2(0, size.y * 0.47, size.x, 90), to_text, 9.0, Color.WHITE, Color(0, 0, 0, 0.35))
