class_name FatigueMeter
extends Control
## A small driver-fatigue bar under the car status panel, shown in races once the driver
## starts to tire. One short message explains it the first time fatigue really bites.

const NOTICE_AT := 0.45

var hud: HUDController
var _noticed := false


static func make(owner_hud: HUDController) -> FatigueMeter:
	var meter := FatigueMeter.new()
	meter.hud = owner_hud
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	meter.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	meter.size = Vector2(176, 24)
	meter.position = Vector2(-190, 176)
	return meter


func _process(_delta: float) -> void:
	var car := _car()
	visible = car != null and car.perf != null and car.perf.fatigue > 0.05
	if not visible:
		return
	if not _noticed and car.perf.fatigue >= NOTICE_AT:
		_noticed = true
		hud.show_message("DRIVER TIRING  -  LESS GRIP AND BRAKING")
	queue_redraw()


func _car() -> VehicleController:
	if hud == null or hud.manager == null or GameManager.session_mode != GameManager.MODE_RACE:
		return null
	return hud.manager.player


func _draw() -> void:
	var car := _car()
	if car == null or car.perf == null:
		return
	var fatigue := car.perf.fatigue
	var color := Color("5fe08a").lerp(Color("e0a23a"), clampf(fatigue / 0.5, 0.0, 1.0)).lerp(Color("e04a3a"), clampf((fatigue - 0.5) / 0.4, 0.0, 1.0))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	draw_string(UIKit.font(), Vector2(6, 16), "FATIGUE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	var bar := Rect2(66, 7, size.x - 74, 10)
	draw_rect(bar, Color(1, 1, 1, 0.18))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fatigue, bar.size.y)), color)
