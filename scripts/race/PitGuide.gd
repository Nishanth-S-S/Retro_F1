class_name PitGuide
extends Node2D
## Pulsing amber arrows painted on the track that lead into the pit lane. Shown when the
## car needs a stop (low fuel, heavy damage, worn tyres, mandatory stop) or BOX is armed.

const PPM := VehiclePhysicsConfig.PPM
const RUN_IN := 160.0            # metres of arrows before the pit entry
const STEP := 16.0

var track: TrackData
var showing := false
var _pulse := 0.0


func _ready() -> void:
	z_index = 1


func _process(delta: float) -> void:
	_pulse += delta
	visible = showing
	if showing:
		queue_redraw()


func _draw() -> void:
	if track == null:
		return
	var lane := -(track.half_width + TrackData.PIT_WIDTH * 0.55)
	var edge := -(track.half_width - 1.4)
	var d := -RUN_IN
	var n := 0
	while d <= 30.0:
		var p := track.pit_start + d
		# Ease from the racing line to the left edge, then down into the lane.
		var lateral := lerpf(-track.half_width * 0.2, edge, clampf((d + RUN_IN) / (RUN_IN - 30.0), 0.0, 1.0)) if d < 0.0 else lerpf(edge, lane, clampf(d / 20.0, 0.0, 1.0))
		var at := track.position_at(p, lateral)
		var ahead := track.position_at(p + 4.0, lateral if d < 0.0 else lerpf(edge, lane, clampf((d + 4.0) / 20.0, 0.0, 1.0)))
		var fwd := (ahead - at).normalized()
		var side := fwd.orthogonal()
		# A wave of brightness runs towards the pit entry.
		var glow := 0.45 + 0.55 * maxf(0.0, sin(_pulse * 7.0 - n * 0.7))
		var col := Color(1.0, 0.70, 0.28, glow)
		var s := 1.7 * PPM
		var tip := at + fwd * s * 0.7
		var w := 0.35 * PPM
		for k in 2:
			var back := at - fwd * s * 0.25 + fwd * k * w * 2.2
			var t := tip + fwd * k * w * 2.2
			draw_line(back + side * s * 0.7, t, col, w)
			draw_line(back - side * s * 0.7, t, col, w)
		d += STEP
		n += 1
