class_name CarPreview
extends Node2D
## Blueprint-style car shown in the garage and on the main menu. Wraps CarVisual and adds
## the little "something just got bolted on" bounce.

const S := VehiclePhysicsConfig.PPM
## Geometric middle of the car in metres ahead of the rear axle.
const CENTER_X := 1.75

@export var display_scale := 8.6
## Blueprint outline style; off = the real painted car.
var blueprint := false

var visual: CarVisual
var _tween: Tween


func _ready() -> void:
	visual = CarVisual.new()
	visual.blueprint = blueprint
	visual.line_width = 1.6 / display_scale
	visual.position = Vector2(-CENTER_X * S, 0.0)
	add_child(visual)
	rotation = -PI / 2.0            # nose up
	scale = Vector2(display_scale, display_scale)


func set_livery(color: Color, color2: Color) -> void:
	visual.body_color = color
	visual.accent_color = color2


func show_setup(setup: CarSetup) -> void:
	visual.setup = setup
	visual.refresh()


## Screen-space offset (relative to this node's position) of a point on the car.
func car_point(x_from_rear_axle: float, lateral: float) -> Vector2:
	return Vector2(lateral, -(x_from_rear_axle - CENTER_X)) * S * display_scale


func bounce() -> void:
	if _tween:
		_tween.kill()
	var base := Vector2(display_scale, display_scale)
	scale = base * 1.045
	_tween = create_tween()
	_tween.tween_property(self, "scale", base, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
