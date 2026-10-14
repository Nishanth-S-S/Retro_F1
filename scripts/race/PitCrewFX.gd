class_name PitCrewFX
extends Node2D
## The pit crew during a stop, drawn around the car in pixel style: they run out of the
## garage, four wheel-gun crews swap the tyres, the jack men lift the car, a wing man fits
## a new nose if it was damaged, and the lollipop flips to green at the end.
## `progress` runs 0..1 over the stop.

const PPM := VehiclePhysicsConfig.PPM

var car: VehicleController
var color := Color("c8201e")
var color2 := Color("f4f6f2")
var new_tire := Color.WHITE
var wing := false
var progress := 0.0


func _ready() -> void:
	z_index = 4


## Crew spots in the car's frame (metres: +x forward from the centre of mass, +y right).
func _spots() -> Array:
	var cg := car.physics.stats.cg_x if car.physics.stats else 1.3
	var front := 3.0 - cg
	var rear := -cg
	var spots := [
		[Vector2(front, -1.6), "gun"], [Vector2(front, 1.6), "gun"], [Vector2(rear, -1.6), "gun"], [Vector2(rear, 1.6), "gun"],
		[Vector2(front + 1.9, 0.0), "jack"], [Vector2(rear - 1.7, 0.0), "jack"], [Vector2(front + 3.2, -1.6), "lollipop"],
	]
	if wing:
		spots.append([Vector2(front + 1.4, -1.9), "wing"])
	return spots


func _process(_delta: float) -> void:
	if car:
		global_position = car.global_position
		rotation = car.rotation
	queue_redraw()


func _person(pos: Vector2, facing: float, busy: bool, t: float) -> void:
	var p := pos * PPM
	var bob := sin(t * 40.0) * 0.08 * PPM if busy else 0.0
	draw_rect(Rect2(p + Vector2(-0.45, -0.35) * PPM + Vector2(0.15, 0.2) * PPM, Vector2(0.9, 0.7) * PPM), Color(0, 0, 0, 0.25))
	draw_rect(Rect2(p + Vector2(-0.45, -0.35) * PPM + Vector2(bob, 0), Vector2(0.9, 0.7) * PPM), color)
	draw_rect(Rect2(p + Vector2(-0.45, -0.1) * PPM + Vector2(bob, 0), Vector2(0.9, 0.2) * PPM), color2)
	draw_circle(p + Vector2(0.18 * facing, 0) * PPM + Vector2(bob, 0), 0.26 * PPM, Color("eef1f4"))
	draw_circle(p + Vector2(0.3 * facing, 0) * PPM + Vector2(bob, 0), 0.1 * PPM, Color("23262e"))


func _draw() -> void:
	if car == null:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var walk_in := clampf(progress / 0.15, 0.0, 1.0)
	var walk_out := clampf((progress - 0.88) / 0.12, 0.0, 1.0)
	var working := progress > 0.15 and progress < 0.88
	for spot: Array in _spots():
		var target: Vector2 = spot[0]
		var role: String = spot[1]
		# Everyone comes from the garage on the left of the car and goes back there.
		var garage := Vector2(target.x, -7.5)
		var pos := garage.lerp(target, smoothstep(0.0, 1.0, walk_in)).lerp(garage, smoothstep(0.0, 1.0, walk_out))
		match role:
			"gun":
				var side := signf(target.y)
				var wheel := Vector2(target.x, side * 0.8) * PPM
				var swap := clampf((progress - 0.35) / 0.25, 0.0, 1.0)
				if working:
					# Old tyre carried away, new one (with the new compound's band) carried in.
					var old_pos := wheel + Vector2(0, side * 2.6 * swap) * PPM
					draw_rect(Rect2(old_pos - Vector2(0.35, 0.22) * PPM, Vector2(0.7, 0.44) * PPM), Color("1b1d22"))
					var new_pos := wheel + Vector2(0, side * 2.6 * (1.0 - swap)) * PPM
					draw_rect(Rect2(new_pos - Vector2(0.35, 0.22) * PPM, Vector2(0.7, 0.44) * PPM), Color("2b2e34"))
					draw_rect(Rect2(new_pos - Vector2(0.05, 0.22) * PPM, Vector2(0.1, 0.44) * PPM), new_tire)
					if fmod(t * 12.0, 1.0) < 0.5:
						draw_rect(Rect2(wheel + Vector2(-0.1, -side * 0.15) * PPM, Vector2(0.2, 0.2) * PPM), Color("ffe07a"))
				_person(pos, -side, working, t)
			"jack":
				if working:
					draw_rect(Rect2((target + Vector2(-0.6 if target.x > 0.0 else 0.0, -0.12)) * PPM, Vector2(0.6, 0.24) * PPM), Color("8b95a3"))
				_person(pos, -signf(target.x), false, t)
			"wing":
				if working:
					var fit := clampf((progress - 0.3) / 0.4, 0.0, 1.0)
					draw_rect(Rect2((pos + Vector2(0.3, 0.6 + fit * 1.0)) * PPM, Vector2(0.4, 1.8) * PPM), color2)
				_person(pos, 1.0, working, t)
			"lollipop":
				_person(pos, -1.0, false, t)
				var board := (pos + Vector2(0.0, 1.0)) * PPM
				draw_line(pos * PPM, board, Color("d7dbe0"), 0.12 * PPM)
				draw_circle(board, 0.5 * PPM, Color("1e8a4a") if progress > 0.9 else Color("c8201e"))
