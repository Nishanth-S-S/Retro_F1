extends Node
## Local JSON persistence. A missing or corrupted save never crashes the game:
## the caller simply receives an empty Dictionary and builds a default profile.

const SLOT_COUNT := 6
const META_PATH := "user://apex_meta.json"

var slot := 1
var save_path := "user://apex_assembly_save.json"
const SAVE_VERSION := 1

## When true nothing is read from or written to disk (used by automated tests).
var disabled := false


func _ready() -> void:
	# Remember which save slot was used last.
	if FileAccess.file_exists(META_PATH):
		var meta: Variant = load_json(META_PATH)
		if meta is Dictionary:
			slot = clampi(int(meta.get("slot", 1)), 1, SLOT_COUNT)
	save_path = slot_path(slot)


func slot_path(index: int) -> String:
	return "user://apex_assembly_save.json" if index == 1 else "user://apex_slot_%d.json" % index


func set_slot(index: int) -> void:
	slot = clampi(index, 1, SLOT_COUNT)
	save_path = slot_path(slot)
	if disabled:
		return
	var file := FileAccess.open(META_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"slot": slot}))


## Raw contents of a slot for the save-select screen ({} when the slot is empty).
func slot_data(index: int) -> Dictionary:
	var path := slot_path(index)
	if disabled or not FileAccess.file_exists(path):
		return {}
	var data: Variant = load_json(path)
	return data if data is Dictionary else {}


func delete_slot(index: int) -> void:
	var path := slot_path(index)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func load_profile() -> Dictionary:
	if disabled or not FileAccess.file_exists(save_path):
		return {}
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		push_warning("Save file corrupted - backing it up and starting a fresh profile.")
		DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(save_path.replace(".json", ".corrupt.json")))
		return {}
	return json.data


func save_profile(profile: Dictionary) -> void:
	if disabled:
		return
	profile["version"] = SAVE_VERSION
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write save file.")
		return
	file.store_string(JSON.stringify(profile))
	file.close()


func delete_save() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


static func load_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Missing data file: %s" % path)
		return null
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("Bad JSON in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data
