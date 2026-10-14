class_name WeatherFX
extends CanvasLayer
## Rain over the race view: a cool tint and slanted pixel streaks. Purely visual - the
## grip loss itself is applied to the cars by RaceManager.

const NAMES: PackedStringArray = ["DRY", "LIGHT RAIN", "HEAVY RAIN"]
## Tire grip multiplier on a dry, damp and soaked track.
const GRIP: PackedFloat32Array = [1.0, 0.84, 0.7]

var level := 0
var _canvas: Control
var _drops := PackedVector2Array()
var _speeds := PackedFloat32Array()
var _flash := 0.0
var _flash_timer := 6.0


## Grip on a track for slicks (0), intermediates (1) and full wets (2) in [dry, light, heavy].
const TIRE_GRIP := [[1.0, 0.84, 0.7], [0.9, 0.97, 0.86], [0.8, 0.92, 0.97]]


static func grip(weather: int) -> float:
	return GRIP[clampi(weather, 0, 2)]


static func tire_grip(weather: int, setup: CarSetup) -> float:
	var tires := setup.part("tires")
	var kind := clampi(int(tires.stat("wet", 0.0)) if tires else 0, 0, 2)
	return float(TIRE_GRIP[kind][clampi(weather, 0, 2)])


func _ready() -> void:
	layer = 5
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_paint)
	add_child(_canvas)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in (90 if level == 1 else 220):
		_drops.append(Vector2(rng.randf(), rng.randf()))
		_speeds.append(rng.randf_range(0.9, 1.5))
	visible = level > 0


func _process(delta: float) -> void:
	if level <= 0:
		return
	for i in _drops.size():
		var p := _drops[i]
		p.y += delta * _speeds[i] * (1.5 if level == 1 else 2.1)
		p.x -= delta * _speeds[i] * 0.35
		if p.y > 1.05:
			p.y -= 1.1
		if p.x < -0.05:
			p.x += 1.1
		_drops[i] = p
	if level == 2:
		# The odd flash of lightning in a storm.
		_flash = maxf(0.0, _flash - delta * 3.0)
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash_timer = randf_range(7.0, 16.0)
			_flash = 1.0
	_canvas.queue_redraw()


func _paint() -> void:
	var size := _canvas.size
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.22, 0.32, 0.14 if level == 1 else 0.26))
	var length := 14.0 if level == 1 else 22.0
	var color := Color(0.82, 0.9, 1.0, 0.5 if level == 1 else 0.62)
	for i in _drops.size():
		var p := _drops[i] * size
		# Chunky two-step streaks keep the retro look.
		_canvas.draw_rect(Rect2(p, Vector2(2, length * 0.5)), color)
		_canvas.draw_rect(Rect2(p + Vector2(-2, length * 0.5), Vector2(2, length * 0.5)), color)
	if _flash > 0.0:
		_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.35 * _flash))
