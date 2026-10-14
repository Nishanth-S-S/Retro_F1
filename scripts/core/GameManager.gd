extends Node
## Owns the player's profile (economy, inventory, build, settings, records) and the
## state handed between scenes. All balance numbers come from data/progression.

const MODE_TEST := "test"
const MODE_TIME_TRIAL := "time_trial"
const MODE_RACE := "race"
const MODE_LABELS := {"test": "TEST DRIVE", "time_trial": "TIME TRIAL", "race": "5 LAP RACE"}
const RACE_LAPS := 5
const TRACKS: PackedStringArray = ["falcon_ridge", "tempo_park", "port_azure", "silver_lake", "nordhaven"]
const TRACK_NAMES := {"falcon_ridge": "FALCON RIDGE", "tempo_park": "TEMPO PARK", "port_azure": "PORT AZURE", "silver_lake": "SILVER LAKE", "nordhaven": "NORDHAVEN"}

const DEFAULT_SETTINGS := {
	"master_volume": 0.8, "music_volume": 0.5, "effects_volume": 0.8,
	"steering_sensitivity": 1.0, "steering_smoothing": 0.5,
	"abs": 1, "traction_control": 1, "automatic": true, "racing_line": true,
	"camera_rotation": true, "control_opacity": 0.6, "stability_assist": true,
}

var economy: Dictionary = {}
var challenges: Array = []
var tooltips: Dictionary = {}
var profile: Dictionary = {}
var setup: CarSetup
var session_mode := MODE_TEST
## Circuit used by the next on-track session.
var track_id := "falcon_ridge"
var last_results: Dictionary = {}
var active_mission := -1
## Set while a career grand prix is being driven by the player (see Career.prepare_drive).
var career_race: Dictionary = {}


func _ready() -> void:
	_register_input_actions()
	var eco: Variant = SaveManager.load_json("res://data/progression/economy.json")
	economy = eco if eco is Dictionary else {}
	var ch: Variant = SaveManager.load_json("res://data/progression/challenges.json")
	challenges = ch if ch is Array else []
	var tips: Variant = SaveManager.load_json("res://data/progression/tooltips.json")
	tooltips = tips if tips is Dictionary else {}
	load_profile()


# ---------------------------------------------------------------- tracks and records

func track_file() -> String:
	return "res://data/tracks/%s.json" % track_id


## Best lap, sectors, delta trace, corner reference and ghost for the current circuit.
func record() -> Dictionary:
	var records: Dictionary = profile["records"]
	if not records.has(track_id):
		records[track_id] = {"best_lap": 0.0, "best_sectors": [0.0, 0.0, 0.0], "best_lap_trace": [], "best_lap_corners": [], "ghost_data": []}
	return records[track_id]


# ---------------------------------------------------------------- unlock tiers

## R&D level reached in the career factory; parts of a tier unlock once it is reached.
func story_progress() -> int:
	return int(profile.get("story_progress", 0))


func mission() -> Dictionary:
	return {}


func unlock_chapter_of(part_id: String) -> int:
	return Career.part_tier(part_id) - 1


# ---------------------------------------------------------------- profile

func default_profile() -> Dictionary:
	var starting: Dictionary = economy.get("starting_parts", {})
	var owned: Array = []
	for slot: String in starting:
		if not owned.has(starting[slot]):
			owned.append(starting[slot])
	var unlocked: Array = []
	for id: String in PartDB.all_ids():
		if PartDB.get_part(id).research_cost <= 0:
			unlocked.append(id)
	var start_setup := CarSetup.new()
	for slot: String in starting:
		start_setup.install(slot, starting[slot])
	return {
		"money": int(economy.get("starting_money", 25000)),
		"research_points": int(economy.get("starting_research", 0)),
		"unlocked_parts": unlocked,
		"owned_parts": owned,
		"car_setup": start_setup.to_dict(),
		"best_lap": 0.0,
		"best_sectors": [0.0, 0.0, 0.0],
		"best_lap_trace": [],
		"best_lap_corners": [],
		"ghost_data": [],
		"settings": DEFAULT_SETTINGS.duplicate(),
		"completed_challenges": [],
		"claimed_targets": [],
		"first_lap_done": false,
		"story_progress": 0,
		"career": {},
		"tutorial_seen": false,
		"records": {},
		"camera_default_applied": true,
	}


func load_profile() -> void:
	var defaults := default_profile()
	var loaded := SaveManager.load_profile()
	profile = defaults
	# Merge key by key so old or partially damaged saves still load.
	for key: String in defaults:
		if loaded.has(key) and typeof(loaded[key]) == typeof(defaults[key]):
			profile[key] = loaded[key]
		elif loaded.has(key) and (loaded[key] is float or loaded[key] is int) and (defaults[key] is float or defaults[key] is int):
			profile[key] = loaded[key]
	var settings: Dictionary = profile["settings"]
	for key: String in DEFAULT_SETTINGS:
		if not settings.has(key):
			settings[key] = DEFAULT_SETTINGS[key]
	profile["money"] = int(profile["money"])
	profile["research_points"] = int(profile["research_points"])
	for id: String in defaults["unlocked_parts"]:
		if not profile["unlocked_parts"].has(id):
			profile["unlocked_parts"].append(id)
	# Older saves kept one set of records; they belong to Falcon Ridge.
	if (profile["records"] as Dictionary).is_empty() and float(profile["best_lap"]) > 0.0:
		profile["records"]["falcon_ridge"] = {"best_lap": profile["best_lap"], "best_sectors": profile["best_sectors"], "best_lap_trace": profile["best_lap_trace"], "best_lap_corners": profile["best_lap_corners"], "ghost_data": profile["ghost_data"]}
	if not loaded.is_empty() and not loaded.has("camera_default_applied"):
		settings["camera_rotation"] = true          # rotating camera became the default
	setup = CarSetup.from_dict(profile["car_setup"])
	# Never keep a part installed that the player does not own.
	for slot in CarSetup.SLOTS:
		if setup.parts.has(slot) and not is_owned(setup.parts[slot]):
			setup.remove(slot)


func save() -> void:
	profile["car_setup"] = setup.to_dict()
	SaveManager.save_profile(profile)


## Switches to another save slot (saving the current one first).
func switch_slot(index: int) -> void:
	save()
	SaveManager.set_slot(index)
	career_race = {}
	load_profile()
	EventBus.money_changed.emit(money())
	EventBus.inventory_changed.emit()
	EventBus.setup_changed.emit()
	EventBus.settings_changed.emit()


func reset_profile() -> void:
	SaveManager.delete_save()
	load_profile()
	save()
	EventBus.money_changed.emit(money())
	EventBus.research_changed.emit(research())
	EventBus.inventory_changed.emit()
	EventBus.setup_changed.emit()


# ---------------------------------------------------------------- economy

func money() -> int:
	return int(profile["money"])


func research() -> int:
	return int(profile["research_points"])


func add_money(amount: int) -> void:
	profile["money"] = money() + amount
	EventBus.money_changed.emit(money())


func add_research(amount: int) -> void:
	profile["research_points"] = research() + amount
	EventBus.research_changed.emit(research())


func is_owned(part_id: String) -> bool:
	return profile["owned_parts"].has(part_id)


## Parts unlock by progressing through the story (anything already owned stays usable).
func is_unlocked(part_id: String) -> bool:
	return unlock_chapter_of(part_id) < story_progress() or is_owned(part_id)


func unlock_part(part_id: String) -> bool:
	var part := PartDB.get_part(part_id)
	if part == null or is_unlocked(part_id) or research() < part.research_cost:
		return false
	add_research(-part.research_cost)
	profile["unlocked_parts"].append(part_id)
	EventBus.inventory_changed.emit()
	save()
	return true


func buy_part(part_id: String) -> bool:
	var part := PartDB.get_part(part_id)
	if part == null or is_owned(part_id) or not is_unlocked(part_id) or money() < part.price:
		return false
	if Career.active() and part.price > Career.cap_left():
		return false                 # would break the season's cost cap
	Career.charge_cap(part.price)
	add_money(-part.price)
	profile["owned_parts"].append(part_id)
	EventBus.inventory_changed.emit()
	save()
	return true


func install_part(slot: String, part_id: String) -> bool:
	var part := PartDB.get_part(part_id)
	if part == null or not is_owned(part_id) or CarSetup.SLOT_CATEGORY.get(slot, "") != part.category:
		return false
	setup.install(slot, part_id)
	EventBus.part_installed.emit(slot, part_id)
	EventBus.setup_changed.emit()
	save()
	return true


func remove_part(slot: String) -> void:
	if not setup.parts.has(slot):
		return
	setup.remove(slot)
	EventBus.part_removed.emit(slot)
	EventBus.setup_changed.emit()
	save()


# ---------------------------------------------------------------- settings

func setting(key: String) -> Variant:
	return profile["settings"].get(key, DEFAULT_SETTINGS.get(key))


func set_setting(key: String, value: Variant) -> void:
	profile["settings"][key] = value
	EventBus.settings_changed.emit()


func is_challenge_done(id: String) -> bool:
	return profile["completed_challenges"].has(id)


func start_free_session(mode: String) -> void:
	active_mission = -1
	career_race = {}
	start_session(mode)


func start_session(mode: String) -> void:
	session_mode = mode
	SceneManager.goto("race")


# ---------------------------------------------------------------- input

func _register_input_actions() -> void:
	var map := {
		"throttle": [KEY_W, KEY_UP], "brake": [KEY_S, KEY_DOWN],
		"steer_left": [KEY_A, KEY_LEFT], "steer_right": [KEY_D, KEY_RIGHT],
		"reset_car": [KEY_SPACE], "shift_down": [KEY_Q], "shift_up": [KEY_E],
		"debug_overlay": [KEY_F3], "pause": [KEY_ESCAPE],
	}
	for action: String in map:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		for key: int in map[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key as Key
			InputMap.action_add_event(action, event)
