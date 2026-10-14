class_name Difficulty
extends RefCounted
## Difficulty modes. Choosing one writes its values and assists into the settings;
## everything that needs a difficulty number (AI pace, steering help, damage...) reads it
## from here.

const NAMES: PackedStringArray = ["ROOKIE", "INTERMEDIATE", "PRO", "CHAMPION", "LEGEND"]
const NOTES: PackedStringArray = [
	"Strong steering and braking help, slow rivals, forgiving damage.",
	"Some steering and braking help. Rivals make mistakes.",
	"No driving help beyond ABS and traction control. A fair fight.",
	"Fast, aggressive rivals. No stability assist or racing line.",
	"No assists at all. Rivals at the limit. Every touch costs you.",
]
const PRESETS: Array[Dictionary] = [
	{"diff_ai": 0.0, "diff_aggression": 0.1, "diff_steer_assist": 0.6, "diff_brake_assist": 0.8, "diff_grip": 1.0, "diff_damage": 0.1, "abs": 2, "traction_control": 2, "stability_assist": true, "racing_line": true, "automatic": true},
	{"diff_ai": 0.33, "diff_aggression": 0.35, "diff_steer_assist": 0.25, "diff_brake_assist": 0.35, "diff_grip": 0.5, "diff_damage": 0.3, "abs": 2, "traction_control": 1, "stability_assist": true, "racing_line": true, "automatic": true},
	{"diff_ai": 0.67, "diff_aggression": 0.55, "diff_steer_assist": 0.0, "diff_brake_assist": 0.0, "diff_grip": 0.0, "diff_damage": 0.5, "abs": 1, "traction_control": 1, "stability_assist": true, "racing_line": true},
	{"diff_ai": 0.85, "diff_aggression": 0.75, "diff_steer_assist": 0.0, "diff_brake_assist": 0.0, "diff_grip": 0.0, "diff_damage": 0.75, "abs": 1, "traction_control": 0, "stability_assist": false, "racing_line": false},
	{"diff_ai": 1.0, "diff_aggression": 1.0, "diff_steer_assist": 0.0, "diff_brake_assist": 0.0, "diff_grip": 0.0, "diff_damage": 1.0, "abs": 0, "traction_control": 0, "stability_assist": false, "racing_line": false},
]


static func mode() -> int:
	var value := int(GameManager.setting("difficulty"))
	if value < 0 or value >= PRESETS.size():
		# A save from when custom sliders existed: fall back to PRO.
		apply_preset(2)
		return 2
	return value


static func mode_name() -> String:
	return NAMES[mode()]


static func apply_preset(index: int) -> void:
	var settings: Dictionary = GameManager.profile["settings"]
	settings["difficulty"] = index
	if index < PRESETS.size():
		for key: String in PRESETS[index]:
			settings[key] = PRESETS[index][key]
	EventBus.settings_changed.emit()


static func _v(key: String) -> float:
	return clampf(float(GameManager.setting(key)), 0.0, 1.0)


## Added to every AI driver's pace (0.8-1.0 scale) on track.
static func ai_pace_offset() -> float:
	return lerpf(-0.08, 0.04, _v("diff_ai"))


## Added to every rival's car rating in the simulated grand prix.
static func sim_car_bonus() -> float:
	return lerpf(-5.0, 2.5, _v("diff_ai"))


static func ai_aggression_scale() -> float:
	return lerpf(0.5, 1.4, _v("diff_aggression"))


static func steer_assist() -> float:
	return _v("diff_steer_assist") * 0.75


static func brake_assist() -> float:
	return _v("diff_brake_assist")


static func player_grip() -> float:
	return lerpf(1.0, 1.12, _v("diff_grip"))


static func damage_scale() -> float:
	return 0.25 + 1.5 * _v("diff_damage")
