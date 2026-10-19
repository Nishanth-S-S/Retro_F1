class_name SpeedStreaks
extends Control
## The sense of speed in the overhead view: thin streaks rush past in the direction of travel
## (as seen on screen, so they follow a rotating camera), thickening and lengthening from about
## 140 km/h, with a light vignette at the very top end. Off with "Reduced camera motion".

const START := 38.0                # m/s where streaks begin
const FULL := 80.0                 # m/s for full intensity

var hud: HUDController
var _rng := RandomNumberGenerator.new()
var _streaks: Array = []           # [position (0..1 screen), length factor, lane offset]


static func make(owner_hud: HUDController) -> SpeedStreaks:
	var s := SpeedStreaks.new()
	s.hud = owner_hud
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return s


func _ready() -> void:
	_rng.seed = 7
	for k in 34:
		_streaks.append([Vector2(_rng.randf(), _rng.randf()), _rng.randf_range(0.6, 1.4)])


func _process(delta: float) -> void:
	var car := _car()
	visible = car != null and not bool(GameManager.setting("reduced_motion"))
	if not visible:
		return
	var t := clampf((car.speed - START) / (FULL - START), 0.0, 1.0)
	if t <= 0.0:
		queue_redraw()
		return
	var dir := _screen_dir(car)
	for s: Array in _streaks:
		var p: Vector2 = s[0]
		p -= dir * delta * (1.2 + 2.6 * t) * float(s[1])
		# Wrap round the screen, keeping the middle (where the car is) clear.
		if p.x < -0.1 or p.x > 1.1 or p.y < -0.1 or p.y > 1.1:
			p = Vector2(_rng.randf(), _rng.randf()) + dir * 0.6
			p = Vector2(fposmod(p.x, 1.0), fposmod(p.y, 1.0))
		s[0] = p
	queue_redraw()


func _car() -> VehicleController:
	if hud == null or hud.manager == null or hud.manager.player == null or hud.manager.state != RaceManager.State.RACING:
		return null
	return hud.manager.player if not hud._driver_view else null


## Direction of travel on screen (the camera may rotate).
func _screen_dir(car: VehicleController) -> Vector2:
	var xf := get_viewport().get_canvas_transform()
	var v := xf.basis_xform(car.linear_velocity)
	return v.normalized() if v.length() > 1.0 else Vector2.UP


func _draw() -> void:
	var car := _car()
	if car == null:
		return
	var t := clampf((car.speed - START) / (FULL - START), 0.0, 1.0)
	if t <= 0.0:
		return
	var dir := _screen_dir(car)
	var centre := size * 0.5
	for s: Array in _streaks:
		var p: Vector2 = (s[0] as Vector2) * size
		var off := p - centre
		var clear := clampf(off.length() / (size.y * 0.32) - 0.6, 0.0, 1.0)
		if clear <= 0.0:
			continue
		var length := (40.0 + 140.0 * t) * float(s[1])
		draw_line(p, p - dir * length, Color(1, 1, 1, 0.22 * t * clear), 1.5 + 1.5 * t)
	# Light vignette at the top end.
	var v := clampf((car.speed - 65.0) / 25.0, 0.0, 1.0)
	if v > 0.0:
		for i in 5:
			var inset := i * 16.0
			draw_rect(Rect2(inset, inset, size.x - inset * 2.0, size.y - inset * 2.0), Color(0, 0, 0, 0.045 * v), false, 16.0)
