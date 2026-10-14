class_name CoachMarks
extends CanvasLayer
## First-time tutorial in the style of mobile games: the screen dims, one control is
## spotlighted, a finger points at it and a speech bubble says what it does. Tap to go on.
## Each screen runs its own set once per save (`profile.coach_seen`); TUTORIAL on the main
## menu resets them all.

## Each step: [target, text]. Target is a Control, a Rect2 in screen pixels, or null (no spotlight).
var steps: Array = []
var key := ""
var pause_game := false
## When set, the steps are re-read from this callable just before showing (layouts settle).
var build: Callable
var _index := 0
var _canvas: Control
var _bubble: PanelContainer
var _text: Label
var _count: Label
var _time := 0.0
## Set by tests and screenshot tools.
static var forced := false


static func has_seen(seen_key: String) -> bool:
	return bool((GameManager.profile.get("coach_seen", {}) as Dictionary).get(seen_key, false))


static func reset_all() -> void:
	GameManager.profile["coach_seen"] = {}
	GameManager.save()


## Shows the steps for `seen_key` unless this save has already seen them. Skipped in
## automated tests (saves disabled) unless `forced`.
static func run_once(host: Node, seen_key: String, steps_builder: Callable, pause: bool = false) -> void:
	if has_seen(seen_key) or (SaveManager.disabled and not forced):
		return
	var marks := CoachMarks.new()
	marks.key = seen_key
	marks.build = steps_builder
	marks.pause_game = pause
	host.add_child(marks)


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.theme = UIKit.theme()
	_canvas.draw.connect(_paint)
	_canvas.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_advance())
	add_child(_canvas)
	_bubble = UIKit.panel(UIKit.PANEL, UIKit.WARM)
	_bubble.custom_minimum_size = Vector2(520, 0)
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_bubble)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(box)
	_text = UIKit.label("", 20)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(490, 0)
	box.add_child(_text)
	_count = UIKit.label("", 13, UIKit.HOT)
	box.add_child(_count)
	_canvas.visible = false
	# Wait two frames so the screen underneath has laid itself out.
	await get_tree().process_frame
	await get_tree().process_frame
	if build.is_valid():
		steps = build.call()
	if pause_game:
		get_tree().paused = true
	_canvas.visible = true
	_show_step()


func _target_rect() -> Rect2:
	if _index >= steps.size():
		return Rect2()
	var target: Variant = steps[_index][0]
	if target is Rect2:
		return target
	if target is Control and is_instance_valid(target) and (target as Control).is_visible_in_tree():
		return (target as Control).get_global_rect()
	return Rect2()


func _show_step() -> void:
	if _index >= steps.size():
		_finish()
		return
	_text.text = str(steps[_index][1])
	_count.text = "TAP TO CONTINUE   ·   %d / %d" % [_index + 1, steps.size()]
	var screen := _canvas.size
	var hole := _target_rect()
	_bubble.reset_size()
	var size := Vector2(520, _bubble.get_combined_minimum_size().y)
	var pos := (screen - size) * 0.5
	if hole.size != Vector2.ZERO:
		# The bubble sits on the roomier side of the spotlight.
		var below := hole.end.y + 70.0
		var above := hole.position.y - 70.0 - size.y
		pos.y = below if screen.y - hole.end.y > hole.position.y else above
		pos.x = clampf(hole.get_center().x - size.x * 0.5, 16.0, screen.x - size.x - 16.0)
		pos.y = clampf(pos.y, 16.0, screen.y - size.y - 16.0)
	_bubble.position = pos
	_bubble.scale = Vector2(0.9, 0.9)
	_bubble.pivot_offset = size * 0.5
	_bubble.create_tween().tween_property(_bubble, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)
	AudioManager.play("beep", -16.0, 1.4)


func _advance() -> void:
	_index += 1
	_show_step()


func _finish() -> void:
	if pause_game:
		get_tree().paused = false
	if not GameManager.profile.has("coach_seen"):
		GameManager.profile["coach_seen"] = {}
	GameManager.profile["coach_seen"][key] = true
	GameManager.save()
	queue_free()


func _process(delta: float) -> void:
	_time += delta
	if _canvas.visible:
		_canvas.queue_redraw()


func _paint() -> void:
	var screen := _canvas.size
	var dim := Color(0, 0, 0, 0.66)
	var hole := _target_rect()
	if hole.size == Vector2.ZERO:
		_canvas.draw_rect(Rect2(Vector2.ZERO, screen), dim)
		return
	hole = hole.grow(8.0)
	# Darken everything except the spotlight.
	_canvas.draw_rect(Rect2(0, 0, screen.x, hole.position.y), dim)
	_canvas.draw_rect(Rect2(0, hole.end.y, screen.x, screen.y - hole.end.y), dim)
	_canvas.draw_rect(Rect2(0, hole.position.y, hole.position.x, hole.size.y), dim)
	_canvas.draw_rect(Rect2(hole.end.x, hole.position.y, screen.x - hole.end.x, hole.size.y), dim)
	var pulse := 0.5 + 0.5 * sin(_time * 6.0)
	_canvas.draw_rect(hole.grow(2.0 + pulse * 4.0), Color(UIKit.WARM, 0.9), false, 4.0)
	# A pixel finger pointing at the spotlight, bobbing.
	var from_below := _bubble.position.y > hole.get_center().y
	var tip := Vector2(hole.get_center().x, (hole.end.y + 6.0) if from_below else (hole.position.y - 6.0))
	var bob := sin(_time * 7.0) * 6.0
	tip.y += bob if from_below else -bob
	_finger(tip, -1.0 if from_below else 1.0)


## A chunky pointing hand: the fingertip at `tip`, pointing up (dir -1) or down (dir 1).
func _finger(tip: Vector2, dir: float) -> void:
	var px := 5.0
	var ink := UIKit.INK
	var skin := Color("f6d3b3")
	var cells := [
		[0, 0, 2, 5], [2, 4, 2, 4], [4, 4, 2, 4], [6, 5, 2, 3], [-2, 6, 2, 4], [0, 5, 8, 6], [0, 11, 8, 2],
	]
	var origin := tip - Vector2(px, 0)
	for c: Array in cells:
		var y := float(c[1]) if dir < 0.0 else -float(c[1]) - float(c[3])
		var r := Rect2(origin + Vector2(float(c[0]), y) * px, Vector2(float(c[2]), float(c[3])) * px)
		_canvas.draw_rect(r.grow(px * 0.6), ink)
	for c: Array in cells:
		var y := float(c[1]) if dir < 0.0 else -float(c[1]) - float(c[3])
		_canvas.draw_rect(Rect2(origin + Vector2(float(c[0]), y) * px, Vector2(float(c[2]), float(c[3])) * px), skin)
	var cuff_y := 11.0 if dir < 0.0 else -13.0
	_canvas.draw_rect(Rect2(origin + Vector2(0, cuff_y) * px, Vector2(8, 2) * px), UIKit.WARM)
