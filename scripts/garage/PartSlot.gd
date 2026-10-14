class_name PartSlot
extends Control
## One hardpoint on the car: a tappable ring. Only the selected (or missing) hardpoint
## shows a label, so the blueprint stays clean. Highlights while a part is dragged.

enum Highlight { NONE, VALID, TARGET, INVALID }

const HOTSPOT_RADIUS := 13.0
const HIT_RADIUS := 32.0

var slot := ""
var hotspot := Vector2.ZERO        # position on the car (workspace coordinates)
var tag_side := -1.0               # which side of the car the label opens towards
var highlight := Highlight.NONE:
	set(value):
		highlight = value
		queue_redraw()
var selected := false:
	set(value):
		selected = value
		queue_redraw()
var _pulse := 0.0
var _flash := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func flash() -> void:
	_flash = 1.0


func _process(delta: float) -> void:
	_pulse += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.2)
	queue_redraw()


func _draw() -> void:
	var part := GameManager.setup.part(slot)
	var missing := part == null and CarSetup.REQUIRED_SLOTS.has(slot)
	var glow := 0.5 + 0.5 * sin(_pulse * 4.0)
	var color := Color(1, 1, 1, 0.6)
	var radius := HOTSPOT_RADIUS
	var width := 1.4
	match highlight:
		Highlight.VALID:
			color = UIKit.GOOD
			width = 2.4
			draw_circle(hotspot, radius + 4.0 + glow * 4.0, Color(color, 0.14))
		Highlight.TARGET:
			color = UIKit.GOOD.lightened(0.3)
			radius += 6.0 + glow * 3.0
			width = 3.0
			draw_circle(hotspot, radius, Color(color, 0.28))
		Highlight.INVALID:
			color = UIKit.BAD
			width = 3.0
			draw_circle(hotspot, radius + 4.0, Color(color, 0.25))
		_:
			if missing:
				color = UIKit.BAD
				width = 2.4
				draw_circle(hotspot, radius + glow * 5.0, Color(color, 0.2))
			elif selected:
				color = UIKit.WARM
				width = 2.6
				draw_circle(hotspot, radius + 5.0, Color(color, 0.18))
	draw_arc(hotspot, radius, 0.0, TAU, 28, color, width, true)
	draw_circle(hotspot, 2.6, color)
	if _flash > 0.0:
		draw_arc(hotspot, HOTSPOT_RADIUS + (1.0 - _flash) * 52.0, 0.0, TAU, 36, Color(UIKit.GOOD, _flash), 3.0, true)
	if not (selected or missing or highlight == Highlight.TARGET or highlight == Highlight.INVALID):
		return
	# Label for the hardpoint that currently matters.
	var font := get_theme_default_font()
	var title := (CarSetup.SLOT_LABELS[slot] as String).to_upper()
	var value := part.display_name if part else ("MISSING" if missing else "EMPTY")
	var w := maxf(font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x) + 18.0
	var origin := hotspot + Vector2(tag_side * (radius + 16.0), -21.0)
	if tag_side < 0.0:
		origin.x -= w
	var rect := Rect2(origin, Vector2(w, 42.0))
	draw_line(hotspot + Vector2(tag_side * radius, 0), Vector2(rect.position.x if tag_side > 0.0 else rect.end.x, hotspot.y), Color(color, 0.8), 1.4)
	draw_style_box(UIKit.box(Color(UIKit.PANEL, 0.95), Color(color, 0.9), 5, 2, 0), rect)
	draw_string(font, rect.position + Vector2(9, 16), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(color, 1.0))
	draw_string(font, rect.position + Vector2(9, 35), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UIKit.TEXT if part else UIKit.BAD)
