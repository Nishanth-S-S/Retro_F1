class_name DebugOverlay
extends CanvasLayer
## Developer overlay (F3): raw physics numbers for tuning.

var manager: Node
var _label: Label
var _accum := 0.0


func _ready() -> void:
	layer = 50
	visible = false
	var panel := UIKit.panel(Color(0, 0, 0, 0.72), UIKit.LINE)
	panel.position = Vector2(12, 120)
	add_child(panel)
	_label = UIKit.label("", 12, Color("5fe08a"))
	panel.add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_overlay"):
		visible = not visible


func _process(delta: float) -> void:
	if not visible or manager == null:
		return
	_accum += delta
	if _accum < 0.1:
		return
	_accum = 0.0
	var car: VehicleController = manager.get("player")
	if car == null or car.physics.stats == null:
		return
	var p := car.physics
	var s := p.stats
	var surfaces := ["ASPHALT", "CURB", "GRASS", "GRAVEL"]
	var text := "FPS %d\n" % Engine.get_frames_per_second()
	text += "speed          %6.1f km/h\n" % car.speed_kmh()
	text += "long velocity  %6.2f m/s\n" % car.local_velocity.x
	text += "lat velocity   %6.2f m/s\n" % car.local_velocity.y
	text += "yaw rate       %6.2f rad/s\n" % car.angular_velocity
	text += "steer angle    %6.1f deg\n" % rad_to_deg(p.steer_angle)
	text += "front slip     %6.1f deg\n" % rad_to_deg(p.front_tire.slip_angle)
	text += "rear slip      %6.1f deg\n" % rad_to_deg(p.rear_tire.slip_angle)
	text += "front force    %6.0f / %6.0f N\n" % [p.front_force.length(), p.front_limit]
	text += "rear force     %6.0f / %6.0f N\n" % [p.rear_force.length(), p.rear_limit]
	text += "axle load F/R  %6.0f / %6.0f N\n" % [p.front_load, p.rear_load]
	text += "downforce F/R  %6.0f / %6.0f N\n" % [p.aero.front_downforce, p.aero.rear_downforce]
	text += "drag           %6.0f N\n" % p.aero.drag
	text += "long accel     %6.2f g\n" % (p.long_accel / VehiclePhysicsConfig.GRAVITY)
	text += "car mass       %6.0f kg\n" % s.mass
	text += "weight F/R     %4.1f / %4.1f %%\n" % [s.front_weight * 100.0, (1.0 - s.front_weight) * 100.0]
	text += "gear %d  rpm %5.0f  thr %.2f  brk %.2f\n" % [p.transmission.gear, p.display_rpm, car.input.throttle, car.input.brake]
	text += "tires F %3.0fC %3.0f%%  R %3.0fC %3.0f%%\n" % [p.front_tire.temperature, p.front_tire.wear * 100.0, p.rear_tire.temperature, p.rear_tire.wear * 100.0]
	text += "brakes %4.0fC  engine %3.0fC\n" % [p.brakes.temperature, p.engine.temperature]
	text += "surface %s / %s   progress %6.0f m  lat %+5.1f m\n" % [surfaces[car.surface_front], surfaces[car.surface_rear], car.progress, car.lateral]
	var drivers: Array = manager.get("drivers")
	if drivers and not drivers.is_empty():
		text += "AI: "
		for d: AIDriver in drivers:
			text += "%s " % d.state.substr(0, 4)
	_label.text = text
