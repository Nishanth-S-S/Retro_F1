extends Node
## Scene switching with a short fade so transitions feel deliberate.

const SCENES := {
	"menu": "res://scenes/MainMenu.tscn",
	"garage": "res://scenes/Garage.tscn",
	"race": "res://scenes/Race.tscn",
	"results": "res://scenes/Results.tscn",
	"career": "res://scenes/career/CareerHub.tscn",
	"career_start": "res://scenes/career/CareerStart.tscn",
	"pitwall": "res://scenes/career/PitWall.tscn",
	"raceday": "res://scenes/career/RaceDay.tscn",
	"saves": "res://scenes/Saves.tscn",
}
const FADE_TIME := 0.16

var _layer: CanvasLayer
var _fade: ColorRect
var _busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.03, 0.045, 0.07, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_fade)


func goto(scene_key: String) -> void:
	if _busy or not SCENES.has(scene_key):
		return
	_busy = true
	get_tree().paused = false
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, FADE_TIME)
	await tween.finished
	get_tree().change_scene_to_file(SCENES[scene_key])
	await get_tree().process_frame
	tween = create_tween()
	tween.tween_property(_fade, "color:a", 0.0, FADE_TIME)
	await tween.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
