extends Node
## Dev tool: screenshots of every career screen.  godot res://scenes/tests/CareerShots.tscn -- <out dir>

var _dir := ""


func _ready() -> void:
	if get_tree().current_scene == self:
		var runner := Node.new()
		runner.set_script(get_script())
		get_tree().root.add_child.call_deferred(runner)
		return
	SaveManager.disabled = true
	GameManager.load_profile()
	AudioServer.set_bus_mute(0, true)
	_dir = OS.get_cmdline_user_args()[0]
	_run()


func _shot(name: String) -> void:
	await get_tree().create_timer(0.35).timeout
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_dir, name])
	print("shot ", name)


func _goto(path: String) -> Node:
	get_tree().change_scene_to_file(path)
	await get_tree().create_timer(0.3).timeout
	return get_tree().current_scene


func _run() -> void:
	GameManager.profile["tutorial_seen"] = true
	var menu := await _goto("res://scenes/MainMenu.tscn")
	await _shot("a_menu")
	CoachMarks.forced = true
	menu.call("_start_tutorial")
	await _shot("a_tutorial", 0.6)
	CoachMarks.forced = false
	var start := await _goto("res://scenes/career/CareerStart.tscn")
	await _shot("b_teams")
	start.set("_look", {"skin": 2, "hair": 5, "hair_color": 2, "accessory": 0, "outfit": 1, "face": 5})
	start.set("_team_id", "fer")
	start.call("_show_manager")
	await _shot("c_manager")
	Career.new_career("fer", {"name": "ALEX STONE", "look": {"skin": 2, "hair": 1, "hair_color": 0, "accessory": 1, "outfit": 0}})
	var hub := await _goto("res://scenes/career/CareerHub.tscn")
	await _shot("d_hq")
	hub.call("_show_schedule")
	await _shot("d_schedule")
	hub.call("_close_modal")
	for n in 3:
		Career.scout(Career.market()[0]["id"])
	Career.scout(Career.market()[1]["id"])
	Career._injure(Career.driver(Career.lineup()[1]), 2, "hurt in the crash")
	for i in range(1, 4):
		hub.call("_show_tab", i)
		await _shot("e_tab%d" % i)
	Career._post_race_messages([{"id": Career.lineup()[0], "position": 2, "dnf": false}, {"id": Career.lineup()[1], "position": 14, "dnf": false}], {"collision": false})
	Career.add_message("boss_mer", "Straight to it: $9.0M for your number two. Cash, today.", {"type": "sticker", "cash": 900})
	hub.call("_open_phone")
	await _shot("e_phone")
	await _goto("res://scenes/Saves.tscn")
	await _shot("e_saves")
	await _goto("res://scenes/career/RaceDay.tscn")
	await _shot("e_raceday")
	RaceReport.show(get_tree().current_scene, Career.quick_sim())
	await _shot("h_report")
	hub = await _goto("res://scenes/career/CareerHub.tscn")
	await _shot("i_event")
	await _goto("res://scenes/Garage.tscn")
	await _shot("j_garage")
	get_tree().quit()
